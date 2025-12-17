# pkipy Implementation Notes

## Overview

This document describes the implementation of `pkipy`, a **pure Python cross-platform PowerShell Authenticode signer** that produces signatures validated by Windows' native `Get-AuthenticodeSignature`.

## 🎉 Major Breakthrough: Windows SIP Canonicalization Discovered!

**December 17, 2025**: After extensive reverse-engineering, we discovered exactly how the Windows PowerShell SIP (Subject Interface Package) computes the file hash. This allows `pkipy` to produce signatures that **validate on Windows without requiring Windows for signing!**

### The Discovery

The Windows PowerShell SIP (`pwrshsip.dll`) does NOT hash raw file bytes. Instead:

1. **Encoding Detection**: Check the first 32 bytes for UTF-8 multi-byte sequences
2. **Fallback to CP1252**: If no BOM and no UTF-8 multi-byte chars in first 32 bytes → use Windows-1252
3. **Decode to String**: Decode raw bytes to Unicode string using detected encoding
4. **Convert to UTF-16-LE**: Encode the string as UTF-16-LE bytes
5. **Hash**: SHA1/SHA256 of the UTF-16-LE bytes

### Proof

For a test script with UTF-8 special characters (✓ ✗) located at positions 473 and 770:

| Method                      | Hash                                              |
| --------------------------- | ------------------------------------------------- |
| Raw bytes SHA1              | `c71dbef72717fef7fea2acc2235d5927cdbc3725`        |
| UTF-8 → UTF-16-LE SHA1      | `fadd6127c82c3501fdccd31768b52083e35bdbe4`        |
| **CP1252 → UTF-16-LE SHA1** | **`81f785f3a076e0a6a6d8cd5393ed251a5432cccb`** ✅ |
| Windows embedded hash       | `81f785f3a076e0a6a6d8cd5393ed251a5432cccb` ✅     |

**Why CP1252?** The UTF-8 multi-byte chars (✓ ✗) are at positions 473 and 770, **far beyond the first 32 bytes** that the SIP checks. So the SIP sees only ASCII in the first 32 bytes → falls back to CP1252.

### The Algorithm (Pseudocode)

```python
def compute_sip_hash(raw_bytes: bytes, algorithm: str) -> bytes:
    # Step 1: Detect encoding
    if has_utf16_le_bom(raw_bytes):
        encoding = 'utf-16-le'
    elif has_utf16_be_bom(raw_bytes):
        encoding = 'utf-16-be'
    elif has_utf8_bom(raw_bytes):
        encoding = 'utf-8-sig'
    elif has_utf8_multibyte_in_first_32_bytes(raw_bytes):
        encoding = 'utf-8'
    else:
        encoding = 'cp1252'  # Windows-1252 ANSI code page

    # Step 2: Decode to string
    text = raw_bytes.decode(encoding)

    # Step 3: Convert to UTF-16-LE
    utf16_bytes = text.encode('utf-16-le')

    # Step 4: Hash
    return hashlib.sha1(utf16_bytes).digest()
```

### Key Insight from OpenAuthenticode

We discovered this by studying [jborean93/PowerShell-OpenAuthenticode](https://github.com/jborean93/PowerShell-OpenAuthenticode), a cross-platform PowerShell module. Their C# implementation shows:

```csharp
// From PowerShellScriptProvider.cs, line 44 and 64:
hashableData = Encoding.Unicode.GetBytes(scriptContents.ToArray());
```

The content is **always converted to UTF-16-LE before hashing**. The difference between OpenAuthenticode and the real Windows SIP is in encoding detection for files without BOMs.

---

## Implementation Date

December 16-17, 2025

## What Was Implemented

### 1. Pure Python Authenticode Signer (`pkipy/__main__.py`)

A complete implementation producing **Windows-validated signatures**:

- ✅ **Cross-platform**: Works on Linux, macOS, and Windows
- ✅ **Windows Validated**: Signatures pass `Get-AuthenticodeSignature`
- ✅ **Correct SIP Hash**: Implements Windows' canonicalization algorithm
- ✅ **RFC3161 Timestamps**: Full support for trusted timestamps
- ✅ **Proper Authenticode Structure**: SpcIndirectDataContent with all required OIDs

#### Key Functions

```python
def get_script_encoding(data: bytes) -> str:
    """Detect encoding matching Windows SIP behavior."""

def is_text_utf8(data: bytes) -> bool:
    """Check first 32 bytes for UTF-8 multi-byte sequences."""

def compute_sip_hash(script_bytes: bytes, hash_algorithm: str) -> bytes:
    """Compute hash the same way Windows PowerShell SIP does."""
```

### 2. Code Signing Certificate Generation (`steps.sh::step_codesign`)

- **RSA 3072-bit** (default): Required for Windows Authenticode
- **ECDSA P-384** (optional): For non-Windows platforms only
- **Proper EKU**: `codeSigning` (OID 1.3.6.1.5.5.7.3.3)
- **PKCS#12 export**: Creates `.p12` files for easy import

### 3. Supporting Tools

- **`dasn1`**: ASN.1 signature analyzer for debugging
- **`sign_script_win.ps1`**: Windows signing helper (alternative)
- **Configuration management**: YAML config, environment variables, CLI args

---

## Technical Details

### Windows SIP Canonicalization

The PowerShell SIP is implemented in `pwrshsip.dll` with GUID `603BCC1F-4B59-4E08-B724-D2C6297EF351`.

#### Encoding Detection Priority

1. **UTF-16-LE BOM** (`FF FE`): Use UTF-16-LE
2. **UTF-16-BE BOM** (`FE FF`): Use UTF-16-BE
3. **UTF-8 BOM** (`EF BB BF`): Use UTF-8
4. **UTF-8 multi-byte in first 32 bytes**: Use UTF-8
5. **Default**: Use Windows-1252 (CP1252)

#### UTF-8 Multi-byte Detection

```python
def is_text_utf8(data: bytes) -> bool:
    """
    Check first 32 bytes for valid multi-byte UTF-8 sequences.
    Returns True only if extended characters (≥0x80) are found
    AND they form valid UTF-8 sequences.
    """
    check_data = data[:32]
    contains_extended = False
    remaining_octets = 0

    for b in check_data:
        if remaining_octets == 0:
            if (b & 0b10000000) == 0:
                continue  # ASCII
            contains_extended = True
            # Count leading 1 bits for sequence length
            ...
        else:
            # Check continuation bytes (10xxxxxx)
            ...

    return remaining_octets == 0 and contains_extended
```

### Authenticode Structure

```
ContentInfo (SignedData)
├── version: 1
├── digestAlgorithms: { SHA1 }
├── encapContentInfo
│   ├── contentType: 1.3.6.1.4.1.311.2.1.4 (SPC_INDIRECT_DATA)
│   └── content: [0] EXPLICIT
│       └── SpcIndirectDataContent
│           ├── data (SpcAttributeTypeAndOptionalValue)
│           │   ├── type: 1.3.6.1.4.1.311.2.1.30 (SPC_SIGINFO)
│           │   └── value: SpcSipInfo
│           │       ├── dwSIPversion: 0x10000
│           │       ├── gSubjectType: {603BCC1F-4B59-4E08-B724-D2C6297EF351}
│           │       └── reserved[5]: 0
│           └── messageDigest (DigestInfo)
│               ├── algorithm: SHA1
│               └── digest: <SIP_HASH>  ← This is the UTF-16-LE hash!
├── certificates: [signing cert, intermediate CA, root CA]
├── crls: (empty)
└── signerInfos[0]
    ├── version: 1
    ├── sid: issuerAndSerialNumber
    ├── digestAlgorithm: SHA1
    ├── signedAttrs
    │   ├── contentType: 1.3.6.1.4.1.311.2.1.4
    │   ├── signingTime: <timestamp>
    │   ├── messageDigest: <hash of SpcIndirectDataContent>
    │   ├── SPC_SP_OPUS_INFO (optional)
    │   └── SPC_STATEMENT_TYPE
    ├── signatureAlgorithm: rsaEncryption (1.2.840.113549.1.1.1)
    ├── signature: <RSA signature>
    └── unsignedAttrs
        └── id-aa-signatureTimeStampToken (RFC3161)
```

### Signature Block Format

```powershell
<script content>
# SIG # Begin signature block
# MIIx...  (Base64 DER, 64 chars per line)
# ...
# SIG # End signature block
```

---

## Usage Examples

### Basic Signing (Cross-Platform)

```bash
# Generate code signing certificate
source steps.sh
step_codesign "MyCodeSign"

# Sign a PowerShell script
uv run pkipy script.ps1 --output signed.ps1 \
    --pfx ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12 \
    --timestamp-url http://timestamp.digicert.com
```

### Verification on Windows

```powershell
# Import CA certificates (one-time setup)
Import-Certificate -FilePath ca.pem -CertStoreLocation Cert:\CurrentUser\Root
Import-Certificate -FilePath csica-ca.pem -CertStoreLocation Cert:\CurrentUser\CA

# Verify signature
Get-AuthenticodeSignature signed.ps1 | Format-List *

# Expected output:
# Status                : Valid
# StatusMessage         : Signature verified.
```

---

## Known Limitations

1. **Windows Authenticode RSA-Only**: PowerShell scripts require RSA certificates

   - ECDSA signatures are valid CMS but Windows reports `NotSigned`
   - Use `step_codesign "Name"` (defaults to RSA 3072-bit)

2. **Encoding Edge Cases**: Files with non-ASCII in first 32 bytes will be detected as UTF-8

   - This matches Windows behavior but may differ from file's actual encoding
   - Always use consistent encoding (UTF-8 with BOM for clarity)

3. **SHA-1 Default**: Matches PowerShell's default for maximum compatibility
   - Use `--hash-algorithm sha256` for SHA-256 (requires newer Windows)

---

## Comparison with Other Tools

| Feature            | pkipy | Set-AuthenticodeSignature | osslsigncode | OpenAuthenticode |
| ------------------ | ----- | ------------------------- | ------------ | ---------------- |
| Pure Python        | ✅    | ❌                        | ❌           | ❌               |
| Cross-platform     | ✅    | ❌                        | ✅           | ✅               |
| Windows Validated  | ✅    | ✅                        | N/A          | ✅               |
| PowerShell Scripts | ✅    | ✅                        | ❌           | ✅               |
| RFC3161 Timestamp  | ✅    | ✅                        | ✅           | ✅               |
| PFX Support        | ✅    | ✅                        | ✅           | ✅               |
| PEM Support        | ✅    | ❌                        | ✅           | ✅               |
| Config File        | ✅    | ❌                        | ❌           | ❌               |

---

## References

- [RFC 5652 - Cryptographic Message Syntax](https://tools.ietf.org/html/rfc5652)
- [RFC 3161 - Time-Stamp Protocol](https://tools.ietf.org/html/rfc3161)
- [Microsoft Authenticode Specification](https://docs.microsoft.com/en-us/windows-hardware/drivers/install/authenticode)
- [PowerShell-OpenAuthenticode](https://github.com/jborean93/PowerShell-OpenAuthenticode) - Cross-platform implementation
- [PowerShell Code Signing](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing)

---

## Credits

- **OpenAuthenticode** by Jordan Borean - Key insight into UTF-16-LE canonicalization
- **asn1crypto** library - ASN.1 structure manipulation
- **cryptography** library - Cryptographic operations
- **rfc3161ng** library - RFC3161 timestamping

---

**Author**: AI Assistant (Claude Opus 4.5)  
**Date**: December 17, 2025  
**Project**: ca-n-certs / demo-cfssl  
**Version**: 1.0.0 (Full cross-platform signing with Windows SIP canonicalization)
