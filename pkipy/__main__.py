#!/usr/bin/env python3
"""
Pure Python PowerShell Authenticode Signer with RFC3161 Timestamping

This tool signs PowerShell (.ps1) scripts using Authenticode signatures
with optional RFC3161 timestamping, all implemented in pure Python.

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
import sys
from pathlib import Path
from typing import Optional

import configargparse
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa, ec
from cryptography.hazmat.primitives.serialization import pkcs12, load_pem_private_key

from asn1crypto import cms, x509 as asn1x509, algos
from rfc3161ng import RemoteTimestamper


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

def build_signeddata_for_script(
    script_bytes: bytes,
    signing_key,
    signing_cert: asn1x509.Certificate,
    chain: Optional[list] = None
) -> cms.ContentInfo:
    """
    Build Authenticode-like CMS SignedData structure for the whole script.
    Detached signature with signedAttrs.
    """
    chain = chain or []

    # Digest of the *content* (script bytes)
    digest = hashes.Hash(hashes.SHA256())
    digest.update(script_bytes)
    content_hash = digest.finalize()

    # digestAlgorithms set
    digest_alg = algos.DigestAlgorithm({'algorithm': 'sha256'})
    digest_algs = [digest_alg]

    # encapContentInfo (type = data, no embedded eContent => detached)
    eci = cms.ContentInfo({
        'content_type': 'data',
        # 'content' omitted = detached
    })

    # Certificates: include signer cert + chain
    certs = [signing_cert]
    for c in chain:
        certs.append(c)

    # SignerInfo
    issuer = signing_cert.issuer
    serial_number = signing_cert['tbs_certificate']['serial_number'].native

    sid = cms.SignerIdentifier({
        'issuer_and_serial_number': cms.IssuerAndSerialNumber({
            'issuer': issuer,
            'serial_number': serial_number
        })
    })

    # Signed attributes
    signed_attrs = [
        # contentType = data
        cms.CMSAttribute({
            'type': 'content_type',
            'values': ['data']
        }),
        # messageDigest = hash(script)
        cms.CMSAttribute({
            'type': 'message_digest',
            'values': [content_hash]
        })
    ]

    # DER encode signedAttrs and sign that
    signed_attrs_obj = cms.CMSAttributes(signed_attrs)
    signed_attrs_der = signed_attrs_obj.dump()

    # Sign based on key type
    if isinstance(signing_key, rsa.RSAPrivateKey):
        signature = signing_key.sign(
            signed_attrs_der,
            padding.PKCS1v15(),
            hashes.SHA256()
        )
        sig_alg = algos.SignedDigestAlgorithm({'algorithm': 'rsa'})
    elif isinstance(signing_key, ec.EllipticCurvePrivateKey):
        signature = signing_key.sign(
            signed_attrs_der,
            ec.ECDSA(hashes.SHA256())
        )
        sig_alg = algos.SignedDigestAlgorithm({'algorithm': 'ecdsa'})
    else:
        raise ValueError(f"Unsupported key type: {type(signing_key)}")

    # SignerInfo structure
    signer_info = cms.SignerInfo({
        'version': 'v1',
        'sid': sid,
        'digest_algorithm': digest_alg,
        'signed_attrs': signed_attrs_obj,
        'signature_algorithm': sig_alg,
        'signature': signature,
        # unsignedAttrs will be filled later (timestamp)
    })

    signed_data = cms.SignedData({
        'version': 'v1',
        'digest_algorithms': digest_algs,
        'encap_content_info': eci,
        'certificates': certs,
        'signer_infos': [signer_info]
    })

    content_info = cms.ContentInfo({
        'content_type': 'signed_data',
        'content': signed_data
    })

    return content_info


# ------------------------------------------
# RFC3161 Timestamp
# ------------------------------------------

def rfc3161_timestamp_signature(signature_bytes: bytes, tsa_url: str) -> cms.ContentInfo:
    """
    Ask TSA to timestamp SHA256(signature_bytes) and return TimeStampToken as CMS ContentInfo.
    """
    print(f"  Requesting timestamp from {tsa_url}...")
    ts = RemoteTimestamper(tsa_url, hashname='sha256')

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


# --------------------------------------------------------
# Embed CMS as # SIG # block into .ps1
# --------------------------------------------------------

def embed_sig_block(script_text: str, cms_der: bytes) -> str:
    """Embed CMS signature block into PowerShell script."""
    b64 = base64.encodebytes(cms_der).decode('ascii')
    # normalize line breaks
    lines = [line for line in b64.splitlines() if line.strip()]

    sig_lines = ["# SIG # Begin signature block"]
    for line in lines:
        sig_lines.append(f"# {line}")
    sig_lines.append("# SIG # End signature block")

    # PowerShell usually uses CRLF
    return script_text + "\r\n" + "\r\n".join(sig_lines) + "\r\n"


# --------------------------------------------------------
# High-level signing function
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
):
    """
    Sign a PowerShell script with Authenticode signature and optional RFC3161 timestamp.
    """
    print(f"Reading script: {script_path}")
    script_text = Path(script_path).read_text(encoding="utf-8")
    script_bytes = script_text.encode("utf-8")

    # Load key + cert
    if pfx:
        print(f"Loading certificate from PFX: {pfx}")
        signing_key, signing_cert, chain = load_cert_key_from_pfx(pfx, pfx_password)
    elif cert_pem and key_pem:
        print(f"Loading certificate from PEM files: {cert_pem}, {key_pem}")
        signing_key, signing_cert, chain = load_cert_key_from_pem(cert_pem, key_pem, key_password)
    else:
        raise ValueError("Either --pfx or both --cert and --key must be provided")

    # Build CMS SignedData (no timestamp yet)
    print("Building Authenticode signature...")
    content_info = build_signeddata_for_script(
        script_bytes, signing_key, signing_cert, chain
    )

    # Add timestamp if requested
    if tsa_url:
        signed_data = content_info['content']
        signer_info = signed_data['signer_infos'][0]
        signature_bytes = signer_info['signature'].native

        # Get RFC3161 timestamp for signature
        ts_token = rfc3161_timestamp_signature(signature_bytes, tsa_url)
        print("  ✓ Timestamp received")

        # Embed timestamp token as unsigned attribute
        content_info = add_timestamp_unsigned_attr(content_info, ts_token)
        print("  ✓ Timestamp embedded in signature")

    # Serialize to DER and embed as SIG block
    print("Embedding signature block...")
    cms_der = content_info.dump()
    signed_script = embed_sig_block(script_text, cms_der)

    Path(out_path).write_text(signed_script, encoding="utf-8")
    print(f"\n✓ Signed script written to: {out_path}")
    
    if tsa_url:
        print("  Signature includes RFC3161 timestamp")
    
    print("\nVerify with PowerShell:")
    print(f"  Get-AuthenticodeSignature {out_path} | Format-List *")


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
        )
        return 0
    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())

