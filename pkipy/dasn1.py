#!/usr/bin/env python3
"""
ASN.1 Structure Dumper for PowerShell Authenticode Signatures

This tool extracts and displays the ASN.1 structure of Authenticode signatures
embedded in PowerShell scripts, making it easy to compare working vs non-working
signatures.

Usage:
    # Dump single file's signature structure
    uv run dasn1 signed.ps1

    # Compare two signatures side-by-side
    uv run dasn1 working.ps1 failed.ps1

    # Output raw DER for external analysis
    uv run dasn1 signed.ps1 --extract-der /tmp/sig.der

    # Show hex dump of specific fields
    uv run dasn1 signed.ps1 --show-hex
"""

import argparse
import base64
import hashlib
import sys
from pathlib import Path
from typing import Optional, Tuple, List
from dataclasses import dataclass

from asn1crypto import cms, core, algos, x509 as asn1x509


# Well-known OIDs for Authenticode
OIDS = {
    '1.2.840.113549.1.7.1': 'data',
    '1.2.840.113549.1.7.2': 'signedData',
    '1.2.840.113549.1.9.3': 'contentType',
    '1.2.840.113549.1.9.4': 'messageDigest',
    '1.2.840.113549.1.9.5': 'signingTime',
    '1.2.840.113549.1.9.16.2.14': 'id-aa-signatureTimeStampToken',
    '1.3.6.1.4.1.311.2.1.4': 'SPC_INDIRECT_DATA (Authenticode)',
    '1.3.6.1.4.1.311.2.1.15': 'SPC_PE_IMAGE_DATA',
    '1.3.6.1.4.1.311.2.1.12': 'SPC_SP_OPUS_INFO',
    '2.16.840.1.101.3.4.2.1': 'sha256',
    '1.3.14.3.2.26': 'sha1',
    '1.2.840.113549.1.1.1': 'rsaEncryption',
    '1.2.840.113549.1.1.11': 'sha256WithRSAEncryption',
    '1.2.840.113549.1.1.5': 'sha1WithRSAEncryption',
    '1.2.840.10045.4.3.2': 'ecdsa-with-SHA256',
    '1.2.840.10045.4.3.3': 'ecdsa-with-SHA384',
}


@dataclass
class SignatureInfo:
    """Parsed signature information for comparison."""
    filename: str
    der_bytes: bytes
    content_type: str
    encap_content_type: str
    digest_algorithm: str
    signature_algorithm: str
    file_hash: str
    message_digest: str
    signed_attrs_content_type: str
    has_timestamp: bool
    cert_subject: str
    cert_serial: str
    errors: List[str]


def oid_name(oid: str) -> str:
    """Convert OID to human-readable name."""
    return OIDS.get(oid, oid)


def extract_signature_block(script_path: str) -> Tuple[Optional[bytes], Optional[str]]:
    """
    Extract the signature block from a PowerShell script.
    
    Returns:
        (der_bytes, error_message)
    """
    try:
        content = Path(script_path).read_bytes()
    except Exception as e:
        return None, f"Failed to read file: {e}"
    
    # Find signature markers
    start_marker = b"# SIG # Begin signature block"
    end_marker = b"# SIG # End signature block"
    
    start_idx = content.find(start_marker)
    if start_idx == -1:
        return None, "No signature block found (missing '# SIG # Begin signature block')"
    
    end_idx = content.find(end_marker)
    if end_idx == -1:
        return None, "Incomplete signature block (missing '# SIG # End signature block')"
    
    # Extract the signature block
    sig_block = content[start_idx:end_idx].decode('ascii', errors='replace')
    
    # Parse base64 lines
    lines = sig_block.split('\n')
    b64_data = ''
    
    for line in lines[1:]:  # Skip "Begin signature block"
        line = line.strip()
        if line.startswith('# ') and not line.startswith('# SIG'):
            b64_data += line[2:]
    
    if not b64_data:
        return None, "No base64 data found in signature block"
    
    try:
        der_bytes = base64.b64decode(b64_data)
    except Exception as e:
        return None, f"Failed to decode base64: {e}"
    
    return der_bytes, None


def parse_signature(filename: str, der_bytes: bytes) -> SignatureInfo:
    """Parse a DER-encoded signature and extract key information."""
    info = SignatureInfo(
        filename=filename,
        der_bytes=der_bytes,
        content_type="",
        encap_content_type="",
        digest_algorithm="",
        signature_algorithm="",
        file_hash="",
        message_digest="",
        signed_attrs_content_type="",
        has_timestamp=False,
        cert_subject="",
        cert_serial="",
        errors=[],
    )
    
    try:
        # Parse outer ContentInfo
        content_info = cms.ContentInfo.load(der_bytes)
        info.content_type = oid_name(content_info['content_type'].native)
        
        # Get SignedData
        if content_info['content_type'].native != 'signed_data':
            info.errors.append(f"Expected signedData, got {content_info['content_type'].native}")
            return info
        
        signed_data = content_info['content']
        
        # Encapsulated content info
        eci = signed_data['encap_content_info']
        eci_type = eci['content_type'].dotted
        info.encap_content_type = oid_name(eci_type)
        
        # Try to extract file hash from SpcIndirectDataContent
        if eci_type == '1.3.6.1.4.1.311.2.1.4':
            try:
                # Parse SpcIndirectDataContent - could be wrapped in various ways
                eci_content = eci['content']
                if eci_content is not None:
                    content_bytes = None
                    
                    # Try different ways to get the content bytes
                    if hasattr(eci_content, 'parsed') and eci_content.parsed:
                        # ParsableOctetString with parsed content
                        content_bytes = eci_content.parsed.dump()
                    elif hasattr(eci_content, 'contents') and eci_content.contents:
                        content_bytes = eci_content.contents
                    elif hasattr(eci_content, 'dump'):
                        content_bytes = eci_content.dump()
                    elif hasattr(eci_content, 'native') and isinstance(eci_content.native, bytes):
                        content_bytes = eci_content.native
                    
                    if content_bytes:
                        # The content might be wrapped in context-specific tag [0] EXPLICIT
                        # Skip the wrapper by finding the inner SEQUENCE (0x30)
                        seq_start = content_bytes.find(b'\x30')
                        if seq_start > 0:
                            content_bytes = content_bytes[seq_start:]
                        
                        # Parse as sequence: SpcIndirectDataContent ::= SEQUENCE { data, messageDigest }
                        spc = core.Sequence.load(content_bytes)
                        # message_digest is the second element (DigestInfo)
                        if len(spc) >= 2:
                            digest_info = spc[1]
                            # DigestInfo ::= SEQUENCE { algorithm, digest }
                            if len(digest_info) >= 2:
                                digest_bytes = digest_info[1]
                                if hasattr(digest_bytes, 'native') and isinstance(digest_bytes.native, bytes):
                                    info.file_hash = digest_bytes.native.hex()
                                elif hasattr(digest_bytes, 'contents'):
                                    info.file_hash = digest_bytes.contents.hex()
            except Exception as e:
                info.errors.append(f"Failed to parse SpcIndirectDataContent: {e}")
        
        # Digest algorithms
        digest_algs = signed_data['digest_algorithms']
        if digest_algs:
            alg = digest_algs[0]['algorithm'].dotted
            info.digest_algorithm = oid_name(alg)
        
        # Signer info
        signer_infos = signed_data['signer_infos']
        if signer_infos:
            signer = signer_infos[0]
            
            # Signature algorithm
            sig_alg = signer['signature_algorithm']['algorithm'].dotted
            info.signature_algorithm = oid_name(sig_alg)
            
            # Signed attributes
            signed_attrs = signer['signed_attrs']
            if signed_attrs:
                for attr in signed_attrs:
                    attr_type = attr['type'].native
                    if attr_type == 'content_type':
                        ct = attr['values'][0].dotted
                        info.signed_attrs_content_type = oid_name(ct)
                    elif attr_type == 'message_digest':
                        info.message_digest = attr['values'][0].native.hex()
            
            # Unsigned attributes (timestamp)
            unsigned_attrs = signer['unsigned_attrs']
            if unsigned_attrs and unsigned_attrs.native:
                for attr in unsigned_attrs:
                    if attr['type'].dotted == '1.2.840.113549.1.9.16.2.14':
                        info.has_timestamp = True
        
        # Certificate info - find the signing certificate based on signer ID
        certs = signed_data['certificates']
        if certs and signer_infos:
            signer = signer_infos[0]
            sid = signer['sid']
            
            # Get issuer/serial from signer identifier
            if sid.name == 'issuer_and_serial_number':
                issuer_serial = sid.chosen
                target_serial = issuer_serial['serial_number'].native
                
                # Find the certificate that matches the signer
                signing_cert = None
                for c in certs:
                    cert = c.chosen
                    if cert.serial_number == target_serial:
                        signing_cert = cert
                        break
                
                if signing_cert:
                    info.cert_subject = signing_cert.subject.human_friendly
                    info.cert_serial = hex(signing_cert.serial_number)
                else:
                    # Fallback to first cert
                    cert = certs[0].chosen
                    info.cert_subject = f"(first cert) {cert.subject.human_friendly}"
                    info.cert_serial = hex(cert.serial_number)
            else:
                # Subject key identifier - just use first cert
                cert = certs[0].chosen
                info.cert_subject = cert.subject.human_friendly
                info.cert_serial = hex(cert.serial_number)
            
    except Exception as e:
        info.errors.append(f"Parse error: {e}")
    
    return info


def dump_asn1_tree(der_bytes: bytes, show_hex: bool = False, indent: int = 0) -> str:
    """
    Dump ASN.1 structure as a tree for visual inspection.
    """
    lines = []
    
    def add_line(depth: int, text: str):
        lines.append("  " * depth + text)
    
    def dump_cms_object(obj, depth: int = 0, name: str = ""):
        """Handle CMS-specific objects by accessing their fields."""
        prefix = f"{name}: " if name else ""
        type_name = obj.__class__.__name__
        
        if obj is None:
            add_line(depth, f"{prefix}(null)")
            return
        
        # Check if it's a CMS object with _fields
        if hasattr(obj, '_fields') and hasattr(obj, '__getitem__'):
            add_line(depth, f"{prefix}SEQUENCE ({type_name})")
            for field_name, field_type, *_ in obj._fields:
                try:
                    field_val = obj[field_name]
                    if field_val is not None:
                        dump_cms_object(field_val, depth + 1, field_name)
                except:
                    pass
        elif isinstance(obj, core.SetOf) or (hasattr(obj, '_child_spec') and hasattr(obj, '__iter__')):
            add_line(depth, f"{prefix}SET ({type_name})")
            for i, item in enumerate(obj):
                dump_cms_object(item, depth + 1, f"[{i}]")
        elif isinstance(obj, core.Choice):
            chosen = obj.chosen
            add_line(depth, f"{prefix}CHOICE ({type_name}) -> {obj.name}")
            dump_cms_object(chosen, depth + 1)
        elif isinstance(obj, core.ObjectIdentifier):
            oid = obj.dotted
            add_line(depth, f"{prefix}OID: {oid} ({oid_name(oid)})")
        elif isinstance(obj, (core.OctetString, core.ParsableOctetString)):
            data = obj.native if hasattr(obj, 'native') else obj.contents
            if isinstance(data, bytes):
                if show_hex or len(data) <= 32:
                    add_line(depth, f"{prefix}OCTET STRING [{len(data)}]: {data.hex()}")
                else:
                    add_line(depth, f"{prefix}OCTET STRING [{len(data)}]: {data[:16].hex()}...{data[-8:].hex()}")
                # Try to parse nested content
                if len(data) > 2 and data[0] == 0x30:  # SEQUENCE tag
                    try:
                        nested = core.Sequence.load(data)
                        dump_cms_object(nested, depth + 1, "parsed")
                    except:
                        pass
            else:
                add_line(depth, f"{prefix}OCTET STRING: {data}")
        elif isinstance(obj, core.BitString):
            data = obj.native
            if isinstance(data, bytes):
                if len(data) <= 64:
                    add_line(depth, f"{prefix}BIT STRING [{len(data)}]: {data.hex()}")
                else:
                    add_line(depth, f"{prefix}BIT STRING [{len(data)}]: {data[:32].hex()}...")
            else:
                add_line(depth, f"{prefix}BIT STRING: {data}")
        elif isinstance(obj, core.Integer):
            val = obj.native
            if isinstance(val, int) and val > 0xFFFFFF:
                add_line(depth, f"{prefix}INTEGER: {hex(val)}")
            else:
                add_line(depth, f"{prefix}INTEGER: {val}")
        elif isinstance(obj, (core.UTF8String, core.PrintableString, core.IA5String, 
                              core.BMPString, core.TeletexString, core.GeneralString)):
            add_line(depth, f"{prefix}STRING: {obj.native}")
        elif isinstance(obj, (core.UTCTime, core.GeneralizedTime)):
            add_line(depth, f"{prefix}TIME: {obj.native}")
        elif isinstance(obj, core.Boolean):
            add_line(depth, f"{prefix}BOOLEAN: {obj.native}")
        elif isinstance(obj, core.Any):
            add_line(depth, f"{prefix}ANY [{len(obj.contents)}]")
            try:
                parsed = core.Sequence.load(obj.contents)
                dump_cms_object(parsed, depth + 1, "parsed")
            except:
                if show_hex:
                    add_line(depth + 1, f"raw: {obj.contents[:64].hex()}...")
        elif isinstance(obj, core.Sequence):
            add_line(depth, f"{prefix}SEQUENCE ({type_name})")
            for i, item in enumerate(obj):
                dump_cms_object(item, depth + 1, f"[{i}]")
        elif hasattr(obj, '__iter__') and not isinstance(obj, (str, bytes)):
            add_line(depth, f"{prefix}{type_name}")
            try:
                for i, item in enumerate(obj):
                    dump_cms_object(item, depth + 1, f"[{i}]")
            except:
                add_line(depth + 1, f"(not iterable: {obj.native if hasattr(obj, 'native') else obj})")
        else:
            val = obj.native if hasattr(obj, 'native') else obj
            add_line(depth, f"{prefix}{type_name}: {val}")
    
    try:
        content_info = cms.ContentInfo.load(der_bytes)
        dump_cms_object(content_info, indent, "ContentInfo")
    except Exception as e:
        add_line(indent, f"Parse error: {e}")
        # Try raw parse
        try:
            raw = core.Sequence.load(der_bytes)
            dump_cms_object(raw, indent, "Raw")
        except:
            add_line(indent, f"Raw bytes [{len(der_bytes)}]: {der_bytes[:32].hex()}...")
    
    return "\n".join(lines)


def format_comparison(info1: SignatureInfo, info2: SignatureInfo) -> str:
    """Format two signatures for side-by-side comparison."""
    
    def compare_field(name: str, val1: str, val2: str) -> str:
        if val1 == val2:
            return f"  {name}: {val1} ✓"
        else:
            return f"  {name}:\n    ← {val1}\n    → {val2} ✗"
    
    lines = [
        "=" * 70,
        "SIGNATURE COMPARISON",
        "=" * 70,
        f"File 1: {info1.filename}",
        f"File 2: {info2.filename}",
        "",
        "--- Structure ---",
        compare_field("ContentInfo.contentType", info1.content_type, info2.content_type),
        compare_field("EncapContentInfo.contentType", info1.encap_content_type, info2.encap_content_type),
        compare_field("DigestAlgorithm", info1.digest_algorithm, info2.digest_algorithm),
        compare_field("SignatureAlgorithm", info1.signature_algorithm, info2.signature_algorithm),
        "",
        "--- Signed Attributes ---",
        compare_field("content_type", info1.signed_attrs_content_type, info2.signed_attrs_content_type),
        compare_field("messageDigest", info1.message_digest, info2.message_digest),
        "",
        "--- Content ---",
        compare_field("File hash (in SpcIndirectData)", info1.file_hash, info2.file_hash),
        "",
        "--- Metadata ---",
        compare_field("Has timestamp", str(info1.has_timestamp), str(info2.has_timestamp)),
        compare_field("Cert subject", info1.cert_subject[:50], info2.cert_subject[:50]),
        "",
        "--- DER Size ---",
        f"  File 1: {len(info1.der_bytes)} bytes",
        f"  File 2: {len(info2.der_bytes)} bytes",
    ]
    
    if info1.errors or info2.errors:
        lines.extend(["", "--- Errors ---"])
        for e in info1.errors:
            lines.append(f"  File 1: {e}")
        for e in info2.errors:
            lines.append(f"  File 2: {e}")
    
    lines.append("=" * 70)
    return "\n".join(lines)


def format_single(info: SignatureInfo, show_tree: bool = False, show_hex: bool = False) -> str:
    """Format a single signature for display."""
    
    lines = [
        "=" * 70,
        f"SIGNATURE ANALYSIS: {info.filename}",
        "=" * 70,
        "",
        "--- Structure ---",
        f"  ContentInfo.contentType:      {info.content_type}",
        f"  EncapContentInfo.contentType: {info.encap_content_type}",
        f"  DigestAlgorithm:              {info.digest_algorithm}",
        f"  SignatureAlgorithm:           {info.signature_algorithm}",
        "",
        "--- Signed Attributes ---",
        f"  content_type:   {info.signed_attrs_content_type}",
        f"  messageDigest:  {info.message_digest}",
        "",
        "--- Content ---",
        f"  File hash (in SpcIndirectData): {info.file_hash}",
        "",
        "--- Metadata ---",
        f"  Has timestamp:  {info.has_timestamp}",
        f"  Cert subject:   {info.cert_subject}",
        f"  Cert serial:    {info.cert_serial}",
        f"  DER size:       {len(info.der_bytes)} bytes",
    ]
    
    if info.errors:
        lines.extend(["", "--- Errors ---"])
        for e in info.errors:
            lines.append(f"  {e}")
    
    if show_tree:
        lines.extend(["", "--- ASN.1 Tree ---"])
        lines.append(dump_asn1_tree(info.der_bytes, show_hex))
    
    lines.append("=" * 70)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        'files',
        nargs='+',
        help='PowerShell script(s) with signature to analyze (1 or 2 files)'
    )
    
    parser.add_argument(
        '--tree', '-t',
        action='store_true',
        help='Show full ASN.1 tree structure'
    )
    
    parser.add_argument(
        '--show-hex', '-x',
        action='store_true',
        help='Show hex dump of binary fields'
    )
    
    parser.add_argument(
        '--extract-der', '-e',
        metavar='PATH',
        help='Extract DER bytes to file (first input only)'
    )
    
    parser.add_argument(
        '--raw-der', '-r',
        action='store_true',
        help='Input is raw DER file, not PowerShell script'
    )
    
    args = parser.parse_args()
    
    if len(args.files) > 2:
        print("Error: Maximum 2 files for comparison", file=sys.stderr)
        return 1
    
    # Extract signatures
    signatures = []
    for filepath in args.files:
        if args.raw_der:
            try:
                der_bytes = Path(filepath).read_bytes()
                error = None
            except Exception as e:
                der_bytes = None
                error = str(e)
        else:
            der_bytes, error = extract_signature_block(filepath)
        
        if error:
            print(f"Error processing {filepath}: {error}", file=sys.stderr)
            return 1
        
        signatures.append((filepath, der_bytes))
    
    # Extract DER if requested
    if args.extract_der and signatures:
        Path(args.extract_der).write_bytes(signatures[0][1])
        print(f"DER extracted to: {args.extract_der}")
    
    # Parse and display
    if len(signatures) == 1:
        filepath, der_bytes = signatures[0]
        info = parse_signature(filepath, der_bytes)
        print(format_single(info, show_tree=args.tree, show_hex=args.show_hex))
    else:
        info1 = parse_signature(signatures[0][0], signatures[0][1])
        info2 = parse_signature(signatures[1][0], signatures[1][1])
        print(format_comparison(info1, info2))
        
        if args.tree:
            print("\n" + "=" * 70)
            print("ASN.1 TREE - File 1")
            print("=" * 70)
            print(dump_asn1_tree(info1.der_bytes, args.show_hex))
            print("\n" + "=" * 70)
            print("ASN.1 TREE - File 2")
            print("=" * 70)
            print(dump_asn1_tree(info2.der_bytes, args.show_hex))
    
    return 0


if __name__ == "__main__":
    sys.exit(main())

