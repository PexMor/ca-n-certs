# pkipy Implementation Notes

## Overview

This document describes the implementation of `pkipy`, a pure Python tool for signing PowerShell scripts with Authenticode signatures and RFC3161 timestamps.

## Implementation Date

December 16, 2025

## What Was Implemented

### 1. Pure Python Authenticode Signer (`pkipy/__main__.py`)

A complete implementation of Authenticode signing for PowerShell scripts that:

- **Builds CMS SignedData** structures compatible with Microsoft Authenticode
- **Signs PowerShell scripts** with PKCS#7/CMS signatures
- **Embeds RFC3161 timestamps** as unsigned attributes (`id-aa-signatureTimeStampToken`)
- **Wraps signatures** in PowerShell's `# SIG #` comment block format
- **Validates on Windows** using `Get-AuthenticodeSignature`

#### Key Features:

- ✅ **Cross-platform**: Works on Linux, macOS, and Windows
- ✅ **No PowerShell required**: Pure Python implementation
- ✅ **PFX and PEM support**: Accepts both certificate formats
- ✅ **RFC3161 timestamping**: Optional trusted timestamp support
- ✅ **Flexible configuration**: Config file, environment variables, or CLI args

### 2. Code Signing Certificate Generation (`steps.sh::step_codesign`)

Added `step_codesign` function to generate Authenticode code signing certificates with:

- **Proper EKU**: `extendedKeyUsage = codeSigning` (OID 1.3.6.1.5.5.7.3.3)
- **Key Usage**: `digitalSignature` (critical)
- **RSA 3072-bit** (default): **Required for Windows Authenticode**
- **ECDSA P-384** (optional): For non-Windows platforms only
- **PKCS#12 export**: Creates `.p12` files for easy import
- **Certificate bundles**: Includes full chain (cert + ICA + Root)

#### Key Algorithm Choice

```bash
# RSA (default) - Required for Windows Authenticode/PowerShell
step_codesign "MyCodeSign"
step_codesign "MyCodeSign" rsa

# ECDSA - For non-Windows platforms only (Linux/macOS verification)
step_codesign "MyCodeSign" ecdsa
```

> ⚠️ **Windows Authenticode Limitation**: Windows' Authenticode implementation for PowerShell scripts
> **only supports RSA** code-signing certificates. ECDSA signatures are structurally valid CMS/PKCS#7
> but Windows will report `Status: NotSigned` for PowerShell scripts signed with ECDSA certificates.

### 3. Configuration Management

Implemented using `configargparse` with priority order:

1. **Config file**: `~/.config/pkipy/config.yaml` (or `.yml`, `.toml`)
2. **Environment variables**: Prefix with `PKIPY_`
3. **Command line arguments**: Direct CLI args

Example config file:

```yaml
pfx: ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
pfx-password: ""
timestamp-url: http://timestamp.digicert.com
```

### 4. Documentation

Created comprehensive documentation:

- **README.md**: Full usage guide with examples
- **QUICKSTART.md**: Quick start for new users
- **config.yaml.example**: Sample configuration file
- **IMPLEMENTATION_NOTES.md**: This file
- Updated **main README.md**: Added pkipy references

### 5. Testing & Demo

- **test-script.ps1**: Sample PowerShell script for testing
- **demo.sh**: Interactive demonstration script

## Technical Details

### How Authenticode Signing Works

1. **Read Script**: Load PowerShell script as UTF-8 bytes
2. **Build SignedData**:
   - Create CMS `SignedData` structure
   - Set `encapContentInfo.eContentType = data` (detached signature)
   - Build `SignerInfo` with signed attributes:
     - `contentType = data`
     - `messageDigest = SHA256(script_bytes)`
3. **Sign**: Sign the DER-encoded signed attributes with private key
4. **Timestamp** (optional):
   - Extract `signatureValue` from `SignerInfo`
   - Request RFC3161 timestamp for `SHA256(signatureValue)`
   - Embed `TimeStampToken` as unsigned attribute
5. **Embed**: Wrap CMS DER in Base64 and add to script:

```powershell
# SIG # Begin signature block
# MIIG...
# SIG # End signature block
```

### Standards Compliance

| Standard                   | Purpose                            |
| -------------------------- | ---------------------------------- |
| **RFC 5652**               | Cryptographic Message Syntax (CMS) |
| **RFC 3161**               | Time-Stamp Protocol (TSP)          |
| **RFC 6960**               | OCSP (for certificate validation)  |
| **Microsoft Authenticode** | Code signing format for Windows    |

### Dependencies

```toml
[project.dependencies]
cryptography>=42.0.0     # Cryptographic operations
asn1crypto>=1.5.1        # ASN.1 structure manipulation
rfc3161ng>=2.1.3         # RFC3161 timestamp client
requests>=2.31.0         # HTTP client for TSA
configargparse>=1.7      # Configuration management
pyyaml>=6.0.1            # YAML parsing
```

## Project Integration

### Certificate Generation Flow

```bash
# 1. Generate Root CA (steps.sh)
step01

# 2. Generate Intermediate CA (steps.sh)
step02

# 3. Generate Code Signing Certificate (NEW)
step_codesign "MyCodeSign"

# 4. Sign PowerShell Script (NEW)
uv run pkipy script.ps1 --output signed.ps1 \
    --pfx ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12 \
    --timestamp-url http://timestamp.digicert.com
```

### Directory Structure

```
~/.config/demo-cfssl/
├── ca.pem                          # Root CA
├── ca-key.pem
├── ica-ca.pem                      # Intermediate CA
├── ica-key.pem
├── hosts/                          # TLS/SSL certificates
├── smime/                          # S/MIME certificates
├── tls-clients/                    # TLS client certificates
├── tsa/                            # TSA certificates
└── codesign/                       # Code signing certificates (NEW)
    └── mycodesign/
        ├── cert.pem                # Certificate
        ├── key.pem                 # Private key
        ├── codesign.p12            # PKCS#12 bundle
        ├── bundle-2.pem            # cert + ICA
        ├── bundle-3.pem            # cert + ICA + Root
        └── openssl.cnf             # OpenSSL config
```

## Usage Examples

### Basic Signing

```bash
uv run pkipy script.ps1 --output signed.ps1 \
    --pfx codesign.p12
```

### With Timestamp

```bash
uv run pkipy script.ps1 --output signed.ps1 \
    --pfx codesign.p12 \
    --timestamp-url http://timestamp.digicert.com
```

### Using PEM Files

```bash
uv run pkipy script.ps1 --output signed.ps1 \
    --cert cert.pem \
    --key key.pem \
    --timestamp-url http://timestamp.digicert.com
```

### Using Config File

```bash
# Create config
mkdir -p ~/.config/pkipy
cat > ~/.config/pkipy/config.yaml << EOF
pfx: ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
timestamp-url: http://timestamp.digicert.com
EOF

# Sign
uv run pkipy script.ps1 --output signed.ps1
```

### Using Environment Variables

```bash
export PKIPY_PFX=~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
export PKIPY_TIMESTAMP_URL=http://timestamp.digicert.com

uv run pkipy script.ps1 --output signed.ps1
```

## Verification (Windows)

```powershell
# Check signature
Get-AuthenticodeSignature signed.ps1 | Format-List *

# Expected output:
# Status                : Valid
# SignerCertificate     : [X509Certificate]
# TimeStamperCertificate: [X509Certificate]

# Trust CA certificates
Import-Certificate -FilePath ca.pem -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath ica-ca.pem -CertStoreLocation Cert:\LocalMachine\CA
```

## Known Limitations

1. **Windows Authenticode RSA-Only**: Windows Authenticode for PowerShell scripts **only supports RSA**

   - ECDSA signatures are valid CMS/PKCS#7 but Windows reports `NotSigned`
   - The `step_codesign` function defaults to RSA for Windows compatibility
   - Use `step_codesign "Name" ecdsa` only for non-Windows platforms

2. **Signature Algorithm**: Supports both RSA (PKCS#1 v1.5) and ECDSA

   - Auto-detects key type and uses appropriate algorithm
   - RSA uses SHA-256, ECDSA uses SHA-256 for signing

3. **Timestamp Verification**: Tool creates timestamps but doesn't verify them

   - Verification is done by PowerShell/Windows
   - Could add verification function for completeness

4. **Certificate Chain**: Only includes certificates from PFX

   - Could auto-discover and include full chain
   - Currently relies on PFX containing complete chain

5. **Hash Algorithm**: Fixed to SHA256
   - Modern and secure, but could be made configurable
   - Would need to match in both content hash and signature

## Future Enhancements

### Short Term

- [x] ~~Support ECDSA signatures (detect key type)~~ - Implemented, but Windows Authenticode is RSA-only
- [ ] Add signature verification function
- [ ] Support for multiple signers
- [ ] Batch signing of multiple scripts

### Long Term

- [ ] Support for other file types (DLL, EXE)
- [ ] Catalog file (`.cat`) signing
- [ ] MSI installer signing
- [ ] GUI application for Windows

## Comparison with Other Tools

| Feature            | pkipy | Set-AuthenticodeSignature | osslsigncode |
| ------------------ | ----- | ------------------------- | ------------ |
| Pure Python        | ✅    | ❌ (PowerShell)           | ❌ (C)       |
| Cross-platform     | ✅    | ❌ (Windows only)         | ✅           |
| RFC3161 Timestamp  | ✅    | ✅                        | ✅           |
| PFX Support        | ✅    | ✅                        | ✅           |
| PEM Support        | ✅    | ❌                        | ✅           |
| Config File        | ✅    | ❌                        | ❌           |
| PowerShell Scripts | ✅    | ✅                        | ❌           |
| PE Executables     | ❌    | ✅                        | ✅           |
| DLL Signing        | ❌    | ✅                        | ✅           |

## References

- [RFC 5652 - Cryptographic Message Syntax](https://tools.ietf.org/html/rfc5652)
- [RFC 3161 - Time-Stamp Protocol](https://tools.ietf.org/html/rfc3161)
- [Microsoft Authenticode Specification](https://docs.microsoft.com/en-us/windows-hardware/drivers/install/authenticode)
- [PowerShell Code Signing](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing)
- [PKCS#7 / CMS](https://en.wikipedia.org/wiki/PKCS_7)

## Credits

Implementation based on:

- Original ChatGPT conversation from `tmp/sign-ps1.md`
- `cryptography` library for crypto operations
- `asn1crypto` library for ASN.1 structures
- `rfc3161ng` library for RFC3161 timestamping

---

**Author**: AI Assistant (Claude Sonnet 4.5)  
**Date**: December 16, 2025  
**Project**: ca-n-certs / demo-cfssl  
**Version**: 0.1.0
