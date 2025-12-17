#!/usr/bin/env python3
"""
Pure Python PowerShell Authenticode Signer with RFC3161 Timestamping

This tool signs PowerShell (.ps1) scripts using Authenticode signatures
with optional RFC3161 timestamping, all implemented in pure Python.

The signature format matches Set-AuthenticodeSignature output, using
SpcIndirectDataContent (OID 1.3.6.1.4.1.311.2.1.4) as required by
Windows Authenticode validation.

CRITICAL AUTHENTICODE REQUIREMENTS:
1. Sign EXACT bytes of the script (no normalization)
2. Use SPC_INDIRECT_DATA_OBJID (1.3.6.1.4.1.311.2.1.4) as content type
3. SpcIndirectDataContent must NOT be wrapped in OCTET STRING
4. messageDigest in signed_attrs = hash of SpcIndirectDataContent DER
5. File hash is embedded inside SpcIndirectDataContent.message_digest

Configuration can be provided via:
1. Config file: ~/.config/pkipy/config.yaml or config.toml
2. Environment variables (prefix: PKIPY_)
3. Command line arguments

Example usage:
    # Using PFX/P12 file
    uv run pkipy script.ps1 --pfx codesign.p12 --pfx-password "pass" \\
        --output signed.ps1 --timestamp-url http://timestamp.digicert.com

    # Using PEM files
    uv run pkipy script.ps1 --cert cert.pem --key key.pem \\
        --output signed.ps1 --timestamp-url http://timestamp.digicert.com

    # Using config file
    uv run pkipy script.ps1 --output signed.ps1
"""

import base64
import hashlib
import sys
from pathlib import Path
from typing import Optional, Literal

import configargparse
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa, ec
from cryptography.hazmat.primitives.serialization import pkcs12, load_pem_private_key

from asn1crypto import cms, x509 as asn1x509, algos, core
from rfc3161ng import RemoteTimestamper


# -------------------------
# Windows SIP Encoding Detection (matching pwrshsip.dll behavior)
# -------------------------

def is_text_utf8(data: bytes) -> bool:
    """
    Check if the first 32 bytes contain valid multi-byte UTF-8 sequences.
    This matches the Windows SIP IsTextUTF8 function behavior.
    
    Returns True if there's at least one valid multi-byte UTF-8 sequence
    in the first 32 bytes (indicating the file should be treated as UTF-8).
    """
    check_data = data[:32] if len(data) > 32 else data
    
    contains_extended = False
    remaining_octets = 0
    
    for b in check_data:
        if remaining_octets == 0:
            if (b & 0b10000000) == 0:
                # 7-bit ASCII character
                continue
            
            contains_extended = True
            
            # Count leading 1 bits to get octet count
            current = b
            while (current & 0b10000000) != 0:
                current <<= 1
                remaining_octets += 1
            
            # Count includes this octet, must have at least 1 extra
            remaining_octets -= 1
            if remaining_octets == 0:
                return False
        else:
            # Non-leading octets must start with 10xxxxxx
            if (b & 0b11000000) != 0b10000000:
                return False
            remaining_octets -= 1
    
    # Valid if all sequences complete and at least one extended char found
    return remaining_octets == 0 and contains_extended


def get_script_encoding(data: bytes) -> str:
    """
    Detect the encoding for a PowerShell script, matching Windows SIP behavior.
    
    The Windows PowerShell SIP checks for:
    1. UTF-16-LE BOM (FF FE)
    2. UTF-16-BE BOM (FE FF)
    3. UTF-8 BOM (EF BB BF)
    4. UTF-8 multi-byte sequences in first 32 bytes
    5. Falls back to Windows-1252 (CP1252) ANSI code page
    
    Returns the encoding name to use with decode().
    """
    if len(data) >= 2:
        # Check for BOM
        if data[0] == 0xFF and data[1] == 0xFE:
            return 'utf-16-le'
        elif data[0] == 0xFE and data[1] == 0xFF:
            return 'utf-16-be'
        elif len(data) >= 3 and data[0] == 0xEF and data[1] == 0xBB and data[2] == 0xBF:
            return 'utf-8-sig'  # UTF-8 with BOM
    
    # Check for UTF-8 multi-byte sequences in first 32 bytes
    if is_text_utf8(data):
        return 'utf-8'
    
    # Fall back to Windows-1252 (ANSI code page)
    return 'cp1252'


def compute_sip_hash(script_bytes: bytes, hash_algorithm: str = 'sha1') -> bytes:
    """
    Compute the hash the same way Windows PowerShell SIP does.
    
    The SIP:
    1. Detects encoding (BOM, UTF-8 in first 32 bytes, or ANSI/CP1252)
    2. Decodes bytes to string
    3. Converts string to UTF-16-LE
    4. Hashes the UTF-16-LE bytes
    
    This is CRITICAL for Windows validation - the embedded hash must match
    what the SIP computes during verification.
    """
    # Step 1: Detect encoding
    encoding = get_script_encoding(script_bytes)
    
    # Step 2: Decode to string
    text = script_bytes.decode(encoding)
    
    # Step 3: Convert to UTF-16-LE (this is what the SIP hashes)
    utf16_le_bytes = text.encode('utf-16-le')
    
    # Step 4: Compute hash
    if hash_algorithm == 'sha1':
        return hashlib.sha1(utf16_le_bytes).digest()
    else:
        return hashlib.sha256(utf16_le_bytes).digest()


# -------------------------
# Authenticode OIDs
# -------------------------

# Microsoft Authenticode OID for SPC_INDIRECT_DATA_OBJID
SPC_INDIRECT_DATA_OBJID = '1.3.6.1.4.1.311.2.1.4'

# SPC_PE_IMAGE_DATA_OBJID - used in SpcAttributeTypeAndOptionalValue.type
# This tells Windows what kind of content is being signed
SPC_PE_IMAGE_DATA_OBJID = '1.3.6.1.4.1.311.2.1.15'

# SPC_SIGINFO_OBJID - used for PowerShell scripts
# This is required for PowerShell Authenticode validation
SPC_SIGINFO_OBJID = '1.3.6.1.4.1.311.2.1.30'

# PowerShell SIP (Subject Interface Package) GUID
# This identifies the content type as PowerShell script
# Extracted from working.ps1 signature
POWERSHELL_SIP_GUID = bytes.fromhex('1fcc3b60594b084eb724d2c6297ef351')

# SPC_SP_OPUS_INFO_OBJID - publisher info (optional)
SPC_SP_OPUS_INFO_OBJID = '1.3.6.1.4.1.311.2.1.12'


# -------------------------
# ASN.1 Structures for Authenticode
# -------------------------

class SpcString(core.Choice):
    """SPC string can be Unicode or ASCII."""
    _alternatives = [
        ('unicode', core.BMPString, {'implicit': 0}),
        ('ascii', core.IA5String, {'implicit': 1}),
    ]


class SpcSerializedObject(core.Sequence):
    """Serialized object for SPC."""
    _fields = [
        ('class_id', core.OctetString),
        ('serialized_data', core.OctetString),
    ]


class SpcLink(core.Choice):
    """SPC link - URL, moniker, or file."""
    _alternatives = [
        ('url', core.IA5String, {'implicit': 0}),
        ('moniker', SpcSerializedObject, {'implicit': 1}),
        ('file', SpcString, {'explicit': 2}),
    ]


class SpcSpOpusInfo(core.Sequence):
    """Publisher information (optional)."""
    _fields = [
        ('program_name', SpcString, {'explicit': 0, 'optional': True}),
        ('more_info', SpcLink, {'explicit': 1, 'optional': True}),
    ]


class DigestInfo(core.Sequence):
    """Standard DigestInfo structure."""
    _fields = [
        ('digest_algorithm', algos.DigestAlgorithm),
        ('digest', core.OctetString),
    ]


class SpcAttributeTypeAndOptionalValue(core.Sequence):
    """
    SpcAttributeTypeAndOptionalValue describes what kind of content is being signed.
    For PowerShell scripts, we use a minimal structure.
    """
    _fields = [
        ('type', core.ObjectIdentifier),
        ('value', core.Any, {'optional': True}),
    ]


class SpcIndirectDataContent(core.Sequence):
    """
    SpcIndirectDataContent is the core Authenticode structure.
    It contains:
    - data: describes what is being signed (type + optional value)
    - message_digest: the actual hash of the content
    """
    _fields = [
        ('data', SpcAttributeTypeAndOptionalValue),
        ('message_digest', DigestInfo),
    ]


class AuthenticodeEncapsulatedContentInfo(core.Sequence):
    """
    Custom EncapsulatedContentInfo for Authenticode signatures.
    
    CRITICAL DIFFERENCE from standard CMS:
    - Standard CMS wraps content in OCTET STRING: [0] EXPLICIT OCTET STRING
    - Authenticode places SpcIndirectDataContent directly as [0] EXPLICIT content
    
    IMPORTANT: The content field uses core.Any because PowerShell's Authenticode
    format outputs the SpcIndirectDataContent fields (data + messageDigest)
    as raw concatenated DER, NOT wrapped in an outer SEQUENCE tag.
    
    This matches how Set-AuthenticodeSignature produces signatures.
    """
    _fields = [
        ('content_type', cms.ContentType),
        ('content', core.Any, {'explicit': 0, 'optional': True}),
    ]


class DigestAlgorithms(core.SetOf):
    """Set of DigestAlgorithm for SignedData."""
    _child_spec = algos.DigestAlgorithm


class AuthenticodeSignedData(core.Sequence):
    """
    Custom SignedData for Authenticode that uses AuthenticodeEncapsulatedContentInfo.
    
    This is necessary because cms.SignedData expects cms.EncapsulatedContentInfo
    which wraps content in OCTET STRING - wrong for Authenticode.
    """
    _fields = [
        ('version', cms.CMSVersion),
        ('digest_algorithms', DigestAlgorithms),
        ('encap_content_info', AuthenticodeEncapsulatedContentInfo),
        ('certificates', cms.CertificateSet, {'implicit': 0, 'optional': True}),
        ('crls', cms.RevocationInfoChoices, {'implicit': 1, 'optional': True}),
        ('signer_infos', cms.SignerInfos),
    ]


class AuthenticodeContentInfo(core.Sequence):
    """
    Custom ContentInfo wrapper for our AuthenticodeSignedData.
    
    cms.ContentInfo is strict about type checking and requires cms.SignedData.
    This class allows us to use AuthenticodeSignedData directly.
    """
    _fields = [
        ('content_type', cms.ContentType),
        ('content', AuthenticodeSignedData, {'explicit': 0}),
    ]


# Register our custom OID with asn1crypto's cms module
# This allows cms.ContentType to recognize our Authenticode OID
cms.ContentType._map[SPC_INDIRECT_DATA_OBJID] = 'spc_indirect_data'


# -------------------------
# Certificate Loading
# -------------------------

def load_cert_key_from_pfx(pfx_path: str, password: Optional[str]):
    """Load certificate and key from PFX/P12 file."""
    data = Path(pfx_path).read_bytes()
    key, cert, extra_certs = pkcs12.load_key_and_certificates(
        data,
        password.encode() if password else None
    )
    if cert is None or key is None:
        raise ValueError("PFX does not contain cert + private key")

    # Convert to asn1crypto
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    asn1_cert = asn1x509.Certificate.load(cert_der)

    extras_asn1 = []
    for c in extra_certs or []:
        extras_asn1.append(asn1x509.Certificate.load(
            c.public_bytes(serialization.Encoding.DER)
        ))

    return key, asn1_cert, extras_asn1


def load_cert_key_from_pem(cert_path: str, key_path: str, key_password: Optional[str] = None):
    """Load certificate and key from PEM files."""
    cert_pem = Path(cert_path).read_bytes()
    key_pem = Path(key_path).read_bytes()

    cert = x509.load_pem_x509_certificate(cert_pem)
    key = load_pem_private_key(key_pem, password=key_password.encode() if key_password else None)

    cert_der = cert.public_bytes(serialization.Encoding.DER)
    asn1_cert = asn1x509.Certificate.load(cert_der)

    return key, asn1_cert, []


# ---------------------------------------
# Build SignedData (Authenticode-style)
# ---------------------------------------

def build_spc_indirect_data_content(
    file_hash: bytes,
    hash_algorithm: Literal['sha1', 'sha256'] = 'sha1'
) -> SpcIndirectDataContent:
    """
    Build the SpcIndirectDataContent structure for Authenticode.
    
    This structure tells Windows:
    1. What type of content we're signing (via 'data' field)
    2. The hash of that content (via 'message_digest' field)
    
    For PowerShell scripts, we use a minimal 'data' field with
    SPC_PE_IMAGE_DATA_OBJID and no value (NULL).
    """
    # The 'data' field describes what we're signing
    # For scripts, we use SPC_PE_IMAGE_DATA_OBJID with no value
    # This matches what Set-AuthenticodeSignature produces
    spc_data = SpcAttributeTypeAndOptionalValue({
        'type': core.ObjectIdentifier(SPC_PE_IMAGE_DATA_OBJID),
        # 'value' is omitted (optional) - PowerShell uses this for scripts
    })
    
    # The message_digest contains the actual file hash
    digest_info = DigestInfo({
        'digest_algorithm': algos.DigestAlgorithm({'algorithm': hash_algorithm}),
        'digest': core.OctetString(file_hash),
    })
    
    spc_content = SpcIndirectDataContent({
        'data': spc_data,
        'message_digest': digest_info,
    })
    
    return spc_content


def build_authenticode_signeddata(
    script_bytes: bytes,
    signing_key,
    signing_cert: asn1x509.Certificate,
    chain: Optional[list] = None,
    hash_algorithm: Literal['sha1', 'sha256'] = 'sha1'
) -> cms.ContentInfo:
    """
    Build a proper Authenticode SignedData structure.
    
    Key differences from generic CMS:
    1. contentType is SPC_INDIRECT_DATA_OBJID (1.3.6.1.4.1.311.2.1.4)
    2. encapContentInfo contains SpcIndirectDataContent directly (NOT in OCTET STRING!)
    3. signed_attrs.content_type matches the SPC OID
    4. message_digest in signed_attrs is hash of SpcIndirectDataContent DER (not file)
    5. The file hash is embedded INSIDE SpcIndirectDataContent.message_digest
    
    CRITICAL: Using cms.EncapsulatedContentInfo with ParsableOctetString wraps
    the content in OCTET STRING, which produces INVALID Authenticode signatures.
    We use AuthenticodeEncapsulatedContentInfo instead.
    """
    chain = chain or []
    
    # Step 1: Compute hash using Windows SIP canonicalization
    # CRITICAL: The Windows PowerShell SIP:
    # 1. Detects encoding (BOM, UTF-8 in first 32 bytes, or CP1252)
    # 2. Decodes bytes to string using that encoding
    # 3. Converts the string to UTF-16-LE
    # 4. Hashes the UTF-16-LE bytes
    # 
    # This is NOT the same as hashing the raw bytes!
    encoding = get_script_encoding(script_bytes)
    file_hash = compute_sip_hash(script_bytes, hash_algorithm)
    
    print(f"  Detected encoding: {encoding}")
    print(f"  SIP hash ({hash_algorithm}): {file_hash.hex()}")
    
    # Step 2: Build SpcIndirectDataContent components
    # CRITICAL for PowerShell: Use SPC_SIGINFO_OBJID with SpcSigInfo value structure
    # The content is TWO SIBLING SEQUENCES (NOT wrapped in outer SEQUENCE):
    #   - SpcAttributeTypeAndOptionalValue (with SpcSigInfo value)
    #   - DigestInfo
    
    # Build SpcSigInfo value structure (required for PowerShell scripts)
    # Structure: SEQUENCE { INTEGER, OCTET STRING (GUID), INTEGER x5 }
    spc_sig_info = (
        bytes([0x30, 0x26]) +  # SEQUENCE, 38 bytes
        bytes([0x02, 0x03, 0x01, 0x00, 0x00]) +  # INTEGER 65536 (0x10000) - dwSIPversion
        bytes([0x04, 0x10]) + POWERSHELL_SIP_GUID +  # OCTET STRING (16 bytes) - gSubjectType GUID
        bytes([0x02, 0x01, 0x00]) +  # INTEGER 0 - pzReserved1
        bytes([0x02, 0x01, 0x00]) +  # INTEGER 0 - pzReserved2
        bytes([0x02, 0x01, 0x00]) +  # INTEGER 0 - pzReserved3
        bytes([0x02, 0x01, 0x00]) +  # INTEGER 0 - pzReserved4
        bytes([0x02, 0x01, 0x00])    # INTEGER 0 - pzReserved5
    )
    
    # Build SpcAttributeTypeAndOptionalValue manually
    # Structure: SEQUENCE { OID, value_SEQUENCE }
    oid_der = core.ObjectIdentifier(SPC_SIGINFO_OBJID).dump()  # 06 0a 2b...1e
    spc_data_inner = oid_der + spc_sig_info
    spc_data_len = len(spc_data_inner)
    if spc_data_len < 128:
        spc_data_der = bytes([0x30, spc_data_len]) + spc_data_inner
    else:
        spc_data_der = bytes([0x30, 0x81, spc_data_len]) + spc_data_inner
    
    # Build DigestInfo (the 'messageDigest' field)
    digest_info = DigestInfo({
        'digest_algorithm': algos.DigestAlgorithm({'algorithm': hash_algorithm}),
        'digest': core.OctetString(file_hash),
    })
    digest_info_der = digest_info.dump()
    
    # Concatenate as SIBLING sequences (this is what gets hashed for messageDigest)
    spc_inner_der = spc_data_der + digest_info_der
    
    print(f"  SpcIndirectDataContent inner DER: {len(spc_inner_der)} bytes (data:{len(spc_data_der)} + digest:{len(digest_info_der)})")
    
    # Step 3: Hash the INNER content (two sibling sequences WITHOUT outer wrapper)
    # CRITICAL: messageDigest = hash(data_seq + digest_seq), NOT hash(SEQUENCE { ... })!
    # This matches what working.ps1 has: messageDigest is hash of 89 bytes, not 91
    if hash_algorithm == 'sha1':
        spc_hash = hashlib.sha1(spc_inner_der).digest()
    else:
        spc_hash = hashlib.sha256(spc_inner_der).digest()
    
    # Now wrap in outer SEQUENCE for encap_content_info
    # Working.ps1 structure: [0] { SEQUENCE { data_seq, digest_seq } }
    inner_len = len(spc_inner_der)
    if inner_len < 128:
        spc_content_der = bytes([0x30, inner_len]) + spc_inner_der
    elif inner_len < 256:
        spc_content_der = bytes([0x30, 0x81, inner_len]) + spc_inner_der
    else:
        spc_content_der = bytes([0x30, 0x82, (inner_len >> 8) & 0xff, inner_len & 0xff]) + spc_inner_der
    
    print(f"  SpcIndirectDataContent hash (for messageDigest): {spc_hash.hex()}")
    
    # Step 4: Build encapsulated content info with SPC OID
    # Structure: EncapsulatedContentInfo SEQUENCE {
    #   contentType OID,
    #   [0] EXPLICIT {
    #     SEQUENCE (SpcIndirectDataContent) { data_seq, digest_seq }
    #   }
    # }
    
    # Build the [0] EXPLICIT wrapper around spc_content_der (which includes SEQUENCE tag)
    content_len = len(spc_content_der)
    if content_len < 128:
        tagged_content_der = bytes([0xa0, content_len]) + spc_content_der
    elif content_len < 256:
        tagged_content_der = bytes([0xa0, 0x81, content_len]) + spc_content_der
    else:
        tagged_content_der = bytes([0xa0, 0x82, (content_len >> 8) & 0xff, content_len & 0xff]) + spc_content_der
    
    # Build the EncapsulatedContentInfo SEQUENCE manually
    eci_content_type_der = cms.ContentType(SPC_INDIRECT_DATA_OBJID).dump()
    eci_content_der = eci_content_type_der + tagged_content_der
    
    # Wrap in SEQUENCE
    eci_len = len(eci_content_der)
    if eci_len < 128:
        eci_header = bytes([0x30, eci_len])
    elif eci_len < 256:
        eci_header = bytes([0x30, 0x81, eci_len])
    else:
        eci_header = bytes([0x30, 0x82, (eci_len >> 8) & 0xff, eci_len & 0xff])
    
    full_eci_der = eci_header + eci_content_der
    
    # Parse back as our custom class
    eci = AuthenticodeEncapsulatedContentInfo.load(full_eci_der)
    
    # Step 5: Certificates to include
    certs = [signing_cert] + list(chain)
    
    # Step 6: Build signer identifier
    issuer = signing_cert.issuer
    serial_number = signing_cert['tbs_certificate']['serial_number'].native
    
    sid = cms.SignerIdentifier({
        'issuer_and_serial_number': cms.IssuerAndSerialNumber({
            'issuer': issuer,
            'serial_number': serial_number
        })
    })
    
    # Step 7: Signed attributes
    # CRITICAL: Must include all required Authenticode attributes!
    # Working.ps1 has: SPC_SP_OPUS_INFO, contentType, SPC_STATEMENT_TYPE, messageDigest
    
    # SPC_STATEMENT_TYPE (1.3.6.1.4.1.311.2.1.11) - Required!
    # Value is OID 1.3.6.1.4.1.311.2.1.21 (SPC_INDIVIDUAL_SP_KEY_PURPOSE)
    SPC_STATEMENT_TYPE_OBJID = '1.3.6.1.4.1.311.2.1.11'
    SPC_INDIVIDUAL_SP_KEY = '1.3.6.1.4.1.311.2.1.21'
    
    # Build SPC_STATEMENT_TYPE value: SEQUENCE { OID }
    spc_statement_value = core.Sequence()
    spc_statement_value._fields = [('oid', core.ObjectIdentifier)]
    spc_statement_seq = bytes([0x30, 0x0c]) + core.ObjectIdentifier(SPC_INDIVIDUAL_SP_KEY).dump()
    
    # SPC_SP_OPUS_INFO (1.3.6.1.4.1.311.2.1.12) - Optional but included by Set-AuthenticodeSignature
    # Value is SpcSpOpusInfo with empty programName and moreInfo
    # Structure: SEQUENCE { [0] { [0] "" }, [1] { [0] "" } }
    spc_opus_value = bytes([
        0x30, 0x08,  # SEQUENCE 8 bytes
        0xa0, 0x02, 0x80, 0x00,  # [0] EXPLICIT { [0] IMPLICIT empty BMPString }
        0xa1, 0x02, 0x80, 0x00   # [1] EXPLICIT { [0] IMPLICIT empty IA5String }
    ])
    
    signed_attrs = cms.CMSAttributes([
        # SPC_SP_OPUS_INFO - publisher info (optional but PowerShell includes it)
        cms.CMSAttribute({
            'type': cms.CMSAttributeType(SPC_SP_OPUS_INFO_OBJID),
            'values': [core.Any.load(spc_opus_value)]
        }),
        # contentType - must be SPC_INDIRECT_DATA
        cms.CMSAttribute({
            'type': cms.CMSAttributeType('content_type'),
            'values': [cms.ContentType(SPC_INDIRECT_DATA_OBJID)]
        }),
        # SPC_STATEMENT_TYPE - required for code signing
        cms.CMSAttribute({
            'type': cms.CMSAttributeType(SPC_STATEMENT_TYPE_OBJID),
            'values': [core.Any.load(spc_statement_seq)]
        }),
        # messageDigest - hash of SpcIndirectDataContent inner bytes
        cms.CMSAttribute({
            'type': cms.CMSAttributeType('message_digest'),
            'values': [core.OctetString(spc_hash)]
        }),
    ])
    
    # Step 8: DER encode signed attributes and sign
    signed_attrs_der = signed_attrs.dump()
    
    # Determine algorithm OIDs
    # CRITICAL: For Authenticode, the signature algorithm should be just 'rsaEncryption'
    # (OID 1.2.840.113549.1.1.1), NOT 'sha1WithRSAEncryption' (1.2.840.113549.1.1.5)
    # The digest algorithm is specified separately in digestAlgorithm field.
    digest_alg = algos.DigestAlgorithm({'algorithm': hash_algorithm})
    
    if isinstance(signing_key, rsa.RSAPrivateKey):
        if hash_algorithm == 'sha1':
            hash_obj = hashes.SHA1()
        else:
            hash_obj = hashes.SHA256()
        
        signature = signing_key.sign(
            signed_attrs_der,
            padding.PKCS1v15(),
            hash_obj
        )
        # Use rsaEncryption OID (1.2.840.113549.1.1.1) - NOT sha1WithRSAEncryption!
        # This matches what Set-AuthenticodeSignature produces
        # The name 'rsassa_pkcs1v15' maps to OID 1.2.840.113549.1.1.1
        sig_alg = algos.SignedDigestAlgorithm({'algorithm': 'rsassa_pkcs1v15'})
    elif isinstance(signing_key, ec.EllipticCurvePrivateKey):
        if hash_algorithm == 'sha1':
            hash_obj = hashes.SHA1()
            sig_alg_name = 'sha1_ecdsa'
        else:
            hash_obj = hashes.SHA256()
            sig_alg_name = 'sha256_ecdsa'
        
        signature = signing_key.sign(
            signed_attrs_der,
            ec.ECDSA(hash_obj)
        )
        sig_alg = algos.SignedDigestAlgorithm({'algorithm': sig_alg_name})
    else:
        raise ValueError(f"Unsupported key type: {type(signing_key)}")
    
    # Step 9: Build SignerInfo
    signer_info = cms.SignerInfo({
        'version': 'v1',
        'sid': sid,
        'digest_algorithm': digest_alg,
        'signed_attrs': signed_attrs,
        'signature_algorithm': sig_alg,
        'signature': signature,
    })
    
    # Step 10: Build SignedData using our custom AuthenticodeSignedData
    # CRITICAL: Use AuthenticodeSignedData, NOT cms.SignedData
    # This ensures the EncapsulatedContentInfo is formatted correctly for Authenticode
    signed_data = AuthenticodeSignedData({
        'version': 'v1',
        'digest_algorithms': [digest_alg],
        'encap_content_info': eci,
        'certificates': certs,
        'signer_infos': [signer_info]
    })
    
    # Step 11: Wrap in ContentInfo using our custom class
    # We use AuthenticodeContentInfo instead of cms.ContentInfo
    # because cms.ContentInfo requires cms.SignedData, not our custom class
    content_info = AuthenticodeContentInfo({
        'content_type': cms.ContentType('signed_data'),
        'content': signed_data,
    })
    
    return content_info


# ------------------------------------------
# RFC3161 Timestamp
# ------------------------------------------

def rfc3161_timestamp_signature(
    signature_bytes: bytes,
    tsa_url: str,
    hash_algorithm: Literal['sha1', 'sha256'] = 'sha256'
) -> cms.ContentInfo:
    """
    Ask TSA to timestamp SHA256(signature_bytes) and return TimeStampToken as CMS ContentInfo.
    """
    print(f"  Requesting timestamp from {tsa_url}...")
    ts = RemoteTimestamper(tsa_url, hashname=hash_algorithm)

    # returns raw RFC3161 response (TimeStampResp)
    ts_token = ts.timestamp(data=signature_bytes)

    # Convert to CMS ContentInfo
    ts_content_info = cms.ContentInfo.load(ts_token)

    return ts_content_info


# --------------------------------------------------------
# Add timestamp token as unsigned attribute
# --------------------------------------------------------

def add_timestamp_unsigned_attr(content_info: cms.ContentInfo, ts_token: cms.ContentInfo) -> cms.ContentInfo:
    """
    Modify SignedData's SignerInfo to include id-aa-signatureTimeStampToken unsigned attribute.
    (For standard CMS SignedData - kept for backwards compatibility)
    """
    signed_data: cms.SignedData = content_info['content']

    signer_infos = signed_data['signer_infos']
    if len(signer_infos) != 1:
        raise ValueError("This helper assumes exactly 1 signer")

    signer_info: cms.SignerInfo = signer_infos[0]

    # Construct unsigned attribute: id-aa-signatureTimeStampToken
    # OID: 1.2.840.113549.1.9.16.2.14
    ts_attr = cms.CMSAttribute({
        'type': cms.CMSAttributeType('1.2.840.113549.1.9.16.2.14'),
        'values': [ts_token]  # TimeStampToken is itself a CMS ContentInfo
    })

    if signer_info['unsigned_attrs'].native is None:
        # no unsigned_attrs yet
        signer_info['unsigned_attrs'] = cms.CMSAttributes([ts_attr])
    else:
        ua = signer_info['unsigned_attrs']
        ua.append(ts_attr)
        signer_info['unsigned_attrs'] = ua

    # put modified signer_info back
    signer_infos[0] = signer_info
    signed_data['signer_infos'] = signer_infos
    content_info['content'] = signed_data

    return content_info


def add_timestamp_unsigned_attr_authenticode(
    content_info: cms.ContentInfo, 
    ts_token: cms.ContentInfo,
    signed_data: AuthenticodeSignedData
) -> cms.ContentInfo:
    """
    Add timestamp to our custom AuthenticodeSignedData and rebuild the ContentInfo.
    
    This is separate from add_timestamp_unsigned_attr because our ContentInfo
    wraps AuthenticodeSignedData in core.Any, not cms.SignedData directly.
    """
    signer_infos = signed_data['signer_infos']
    if len(signer_infos) != 1:
        raise ValueError("This helper assumes exactly 1 signer")

    signer_info: cms.SignerInfo = signer_infos[0]

    # Construct unsigned attribute: id-aa-signatureTimeStampToken
    # OID: 1.2.840.113549.1.9.16.2.14
    ts_attr = cms.CMSAttribute({
        'type': cms.CMSAttributeType('1.2.840.113549.1.9.16.2.14'),
        'values': [ts_token]  # TimeStampToken is itself a CMS ContentInfo
    })

    if signer_info['unsigned_attrs'].native is None:
        signer_info['unsigned_attrs'] = cms.CMSAttributes([ts_attr])
    else:
        ua = signer_info['unsigned_attrs']
        ua.append(ts_attr)
        signer_info['unsigned_attrs'] = ua

    # Rebuild the SignedData and ContentInfo
    signer_infos[0] = signer_info
    signed_data['signer_infos'] = signer_infos
    
    # Re-wrap in AuthenticodeContentInfo
    new_content_info = AuthenticodeContentInfo({
        'content_type': cms.ContentType('signed_data'),
        'content': signed_data,
    })
    
    return new_content_info


# --------------------------------------------------------
# Embed CMS as # SIG # block into .ps1 (bytes-based)
# --------------------------------------------------------

def build_sig_block_bytes(cms_der: bytes) -> bytes:
    """
    Build the signature block as bytes.
    
    PowerShell signature blocks have this exact format:
    # SIG # Begin signature block
    # <base64 line 1>
    # <base64 line 2>
    # ...
    # SIG # End signature block
    
    With CRLF line endings.
    """
    # Base64 encode, split into 64-char lines (matching PowerShell output)
    b64 = base64.b64encode(cms_der).decode('ascii')
    
    # Split into 64-character lines (this matches Set-AuthenticodeSignature output)
    lines = [b64[i:i+64] for i in range(0, len(b64), 64)]
    
    sig_lines = ["# SIG # Begin signature block"]
    for line in lines:
        sig_lines.append(f"# {line}")
    sig_lines.append("# SIG # End signature block")

    # PowerShell signature blocks use CRLF
    return ("\r\n".join(sig_lines) + "\r\n").encode('ascii')


# --------------------------------------------------------
# High-level signing function (bytes-based to avoid hash mismatch)
# --------------------------------------------------------

def sign_and_timestamp_ps1(
    script_path: str,
    out_path: str,
    tsa_url: Optional[str] = None,
    pfx: Optional[str] = None,
    pfx_password: Optional[str] = None,
    cert_pem: Optional[str] = None,
    key_pem: Optional[str] = None,
    key_password: Optional[str] = None,
    hash_algorithm: Literal['sha1', 'sha256'] = 'sha1',
):
    """
    Sign a PowerShell script with Authenticode signature and optional RFC3161 timestamp.
    
    CRITICAL BYTE-HANDLING RULES (to avoid hash mismatches):
    1. Read exact bytes from file - no text encoding/decoding
    2. Remove existing signature block byte-exactly
    3. DO NOT normalize line endings in the script body
    4. The bytes we sign MUST equal the bytes before "# SIG # Begin" in output
    
    PowerShell's Authenticode validation:
    - Reads the file as bytes
    - Finds "# SIG # Begin signature block"
    - Hashes everything BEFORE it (including the final CRLF before the marker)
    - Compares with hash inside SpcIndirectDataContent.message_digest
    
    Args:
        script_path: Path to the PowerShell script to sign
        out_path: Path for the signed output
        tsa_url: RFC3161 timestamp server URL (optional)
        pfx: Path to PFX/P12 file
        pfx_password: Password for PFX file
        cert_pem: Path to certificate PEM file
        key_pem: Path to private key PEM file
        key_password: Password for private key
        hash_algorithm: 'sha1' (default, matches PowerShell) or 'sha256'
    """
    print(f"Reading script: {script_path}")
    print(f"Hash algorithm: {hash_algorithm.upper()}")
    
    # 1) Read raw file bytes - NEVER use read_text()!
    raw_bytes = Path(script_path).read_bytes()
    print(f"  Raw file size: {len(raw_bytes)} bytes")
    
    # 2) Remove existing signature block if present
    #    Find the EXACT start of the signature marker line
    sig_marker = b"# SIG # Begin signature block"
    marker_idx = raw_bytes.find(sig_marker)
    
    if marker_idx != -1:
        # The signature block starts at marker_idx
        # We need to also remove the line ending BEFORE the marker
        # (the CRLF that separates script from sig block)
        cut_idx = marker_idx
        
        # Check if there's a CRLF or LF before the marker
        if cut_idx >= 2 and raw_bytes[cut_idx - 2:cut_idx] == b'\r\n':
            cut_idx -= 2
        elif cut_idx >= 1 and raw_bytes[cut_idx - 1:cut_idx] == b'\n':
            cut_idx -= 1
        # Don't cut back over other whitespace - preserve exact script content
        
        unsigned_bytes = raw_bytes[:cut_idx]
        print(f"  Removing existing signature block (was at byte {marker_idx})")
    else:
        unsigned_bytes = raw_bytes
    
    print(f"  Unsigned content size: {len(unsigned_bytes)} bytes")
    
    # 3) The content to hash is the ORIGINAL unsigned bytes (no normalization!)
    #    The Windows SIP canonicalizes by converting to UTF-16-LE internally,
    #    NOT by changing the file contents.
    #    
    #    CRITICAL: Do NOT normalize line endings - this changes the hash!
    #    The SIP decodes using encoding detection and converts to UTF-16-LE.
    hashable_content = unsigned_bytes
    
    # 4) Build the output file content:
    #    [original script content] + [CRLF separator] + [signature block]
    #    The signature block must start on a new line with "# SIG # Begin"
    #    The SIP looks for "\r\n# SIG # Begin" to find the signature
    script_with_separator = unsigned_bytes + b'\r\n'
    
    print(f"  Hashable content: {len(hashable_content)} bytes")
    print(f"  Encoding detected: {get_script_encoding(hashable_content)}")
    
    # 5) Load key + cert
    if pfx:
        print(f"Loading certificate from PFX: {pfx}")
        signing_key, signing_cert, chain = load_cert_key_from_pfx(pfx, pfx_password)
    elif cert_pem and key_pem:
        print(f"Loading certificate from PEM files: {cert_pem}, {key_pem}")
        signing_key, signing_cert, chain = load_cert_key_from_pem(cert_pem, key_pem, key_password)
    else:
        raise ValueError("Either --pfx or both --cert and --key must be provided")

    # 6) Build proper Authenticode CMS SignedData
    #    CRITICAL: The hash is computed on hashable_content (original bytes)
    #    The SIP canonicalizes by decoding to string and converting to UTF-16-LE
    print("Building Authenticode signature...")
    content_info = build_authenticode_signeddata(
        hashable_content, signing_key, signing_cert, chain, hash_algorithm
    )

    # 7) Add timestamp if requested
    if tsa_url:
        # Get the SignedData directly from our AuthenticodeContentInfo
        signed_data = content_info['content']
        signer_info = signed_data['signer_infos'][0]
        signature_bytes = signer_info['signature'].native

        # Get RFC3161 timestamp for signature
        # Note: timestamp hash can be different from signature hash
        ts_token = rfc3161_timestamp_signature(signature_bytes, tsa_url, 'sha256')
        print("  ✓ Timestamp received")

        # Embed timestamp token as unsigned attribute
        content_info = add_timestamp_unsigned_attr_authenticode(
            content_info, ts_token, signed_data
        )
        print("  ✓ Timestamp embedded in signature")

    # 8) Serialize to DER and build signature block
    print("Embedding signature block...")
    cms_der = content_info.dump()
    sig_block = build_sig_block_bytes(cms_der)
    
    # 9) Combine: script content (with separator) + signature block
    #    The script_with_separator already includes the line separator
    signed_bytes = script_with_separator + sig_block
    
    # 10) Write as raw bytes - no encoding conversion!
    Path(out_path).write_bytes(signed_bytes)
    print(f"\n✓ Signed script written to: {out_path}")
    
    if tsa_url:
        print("  Signature includes RFC3161 timestamp")
    
    print("\nVerify with PowerShell (Windows only):")
    print(f"  Get-AuthenticodeSignature '{out_path}' | Format-List *")


# --------------------------------------------------------
# CLI and Configuration
# --------------------------------------------------------

def get_default_config_path():
    """Get default config file path."""
    config_dir = Path.home() / ".config" / "pkipy"
    
    # Try YAML first, then TOML
    for ext in ['.yaml', '.yml', '.toml']:
        config_file = config_dir / f"config{ext}"
        if config_file.exists():
            return str(config_file)
    
    # Return default even if doesn't exist
    return str(config_dir / "config.yaml")


def main():
    """Main entry point for pkipy CLI."""
    parser = configargparse.ArgumentParser(
        default_config_files=[get_default_config_path()],
        description=__doc__,
        formatter_class=configargparse.RawDescriptionHelpFormatter,
        auto_env_var_prefix='PKIPY_',
    )
    
    parser.add_argument(
        '-c', '--config',
        is_config_file=True,
        help='Config file path (default: ~/.config/pkipy/config.yaml)',
    )
    
    parser.add_argument(
        'script',
        help='PowerShell script (.ps1) to sign',
    )
    
    parser.add_argument(
        '-o', '--output',
        required=True,
        help='Output path for signed script',
    )
    
    # Certificate source (mutually exclusive in practice)
    cert_group = parser.add_argument_group('Certificate source (use either PFX or PEM)')
    cert_group.add_argument(
        '--pfx',
        help='Path to PFX/PKCS#12 file (.pfx/.p12)',
    )
    cert_group.add_argument(
        '--pfx-password',
        help='Password for PFX file',
    )
    cert_group.add_argument(
        '--cert',
        help='Path to certificate in PEM format',
    )
    cert_group.add_argument(
        '--key',
        help='Path to private key in PEM format',
    )
    cert_group.add_argument(
        '--key-password',
        help='Password for private key',
    )
    
    # Timestamp options
    ts_group = parser.add_argument_group('Timestamp options')
    ts_group.add_argument(
        '--timestamp-url',
        help='RFC3161 timestamp server URL (e.g., http://timestamp.digicert.com)',
    )
    
    # Hash algorithm
    parser.add_argument(
        '--hash-algorithm',
        choices=['sha1', 'sha256'],
        default='sha1',
        help='Hash algorithm for signature (default: sha1 to match PowerShell)',
    )
    
    # Parse arguments
    args = parser.parse_args()
    
    # Validate inputs
    script_path = Path(args.script)
    if not script_path.exists():
        print(f"Error: Script file not found: {script_path}", file=sys.stderr)
        return 1
    
    if not script_path.suffix.lower() == '.ps1':
        print(f"Warning: File does not have .ps1 extension: {script_path}", file=sys.stderr)
    
    # Validate certificate source
    if not args.pfx and not (args.cert and args.key):
        print("Error: Either --pfx or both --cert and --key must be provided", file=sys.stderr)
        print("You can also configure these in ~/.config/pkipy/config.yaml", file=sys.stderr)
        return 1
    
    if args.pfx:
        pfx_path = Path(args.pfx)
        if not pfx_path.exists():
            print(f"Error: PFX file not found: {pfx_path}", file=sys.stderr)
            return 1
    
    if args.cert:
        cert_path = Path(args.cert)
        if not cert_path.exists():
            print(f"Error: Certificate file not found: {cert_path}", file=sys.stderr)
            return 1
    
    if args.key:
        key_path = Path(args.key)
        if not key_path.exists():
            print(f"Error: Key file not found: {key_path}", file=sys.stderr)
            return 1
    
    try:
        sign_and_timestamp_ps1(
            script_path=str(args.script),
            out_path=str(args.output),
            tsa_url=args.timestamp_url,
            pfx=args.pfx,
            pfx_password=args.pfx_password,
            cert_pem=args.cert,
            key_pem=args.key,
            key_password=args.key_password,
            hash_algorithm=args.hash_algorithm,
        )
        return 0
    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
