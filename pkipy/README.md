# pkipy - Cross-Platform PowerShell Authenticode Signer

A **pure Python** implementation of Authenticode signing for PowerShell scripts that produces signatures **validated by Windows** without requiring Windows for signing.

## ✅ Key Features

- ✅ **Cross-platform**: Sign on Linux, macOS, or Windows
- ✅ **Windows Validated**: Signatures pass `Get-AuthenticodeSignature`
- ✅ **RFC3161 Timestamping**: Trusted timestamp support
- ✅ **PFX and PEM Support**: Use either certificate format
- ✅ **Flexible Configuration**: Config file, environment variables, or CLI args

## 🎉 How It Works

Windows' PowerShell SIP (Subject Interface Package) doesn't hash raw file bytes. Instead, it:

1. **Detects encoding** (BOM, UTF-8 in first 32 bytes, or CP1252)
2. **Decodes to string** using that encoding
3. **Converts to UTF-16-LE**
4. **Hashes the UTF-16-LE bytes**

`pkipy` implements this exact algorithm, allowing cross-platform signing!

## Quick Start

### 1. Generate a Code Signing Certificate

```bash
# Source the steps.sh functions
source steps.sh

# Generate code signing certificate (RSA by default - required for Windows)
step_codesign "MyCodeSign"
```

> ⚠️ **IMPORTANT**: Windows Authenticode for PowerShell scripts **only supports RSA certificates**.

This creates:

- Certificate: `~/.config/demo-cfssl/codesign/mycodesign/cert.pem`
- PKCS#12: `~/.config/demo-cfssl/codesign/mycodesign/codesign.p12`

### 2. Sign a PowerShell Script

```bash
# Sign with timestamp
uv run pkipy script.ps1 --output signed.ps1 \
  --pfx ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12 \
  --timestamp-url http://timestamp.digicert.com
```

### 3. Verify on Windows

```powershell
# Import CA certificates (one-time setup)
Import-Certificate -FilePath ca.pem -CertStoreLocation Cert:\CurrentUser\Root
Import-Certificate -FilePath csica-ca.pem -CertStoreLocation Cert:\CurrentUser\CA

# Verify signature
Get-AuthenticodeSignature signed.ps1 | Format-List *

# Expected:
# Status        : Valid
# StatusMessage : Signature verified.
```

## Configuration

### Config File (`~/.config/pkipy/config.yaml`)

```yaml
pfx: ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
pfx-password: ""
timestamp-url: http://timestamp.digicert.com
```

With a config file:

```bash
uv run pkipy script.ps1 --output signed.ps1
```

### Environment Variables

```bash
export PKIPY_PFX=~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
export PKIPY_TIMESTAMP_URL=http://timestamp.digicert.com

uv run pkipy script.ps1 --output signed.ps1
```

## Usage Examples

### Basic Signing

```bash
uv run pkipy script.ps1 --output signed.ps1 \
  --pfx codesign.p12
```

### With PEM Files

```bash
uv run pkipy script.ps1 --output signed.ps1 \
  --cert cert.pem \
  --key key.pem \
  --timestamp-url http://timestamp.digicert.com
```

### SHA-256 Hash Algorithm

```bash
uv run pkipy script.ps1 --output signed.ps1 \
  --pfx codesign.p12 \
  --hash-algorithm sha256 \
  --timestamp-url http://timestamp.digicert.com
```

## Timestamp Servers

Popular RFC3161 timestamp servers (all free):

- DigiCert: `http://timestamp.digicert.com`
- Sectigo: `http://timestamp.sectigo.com`
- GlobalSign: `http://timestamp.globalsign.com/scripts/timestamp.dll`

## Technical Details

### Windows SIP Canonicalization

The key to cross-platform signing is understanding how Windows computes the hash:

```python
# Encoding detection priority:
# 1. UTF-16-LE BOM (FF FE)
# 2. UTF-16-BE BOM (FE FF)
# 3. UTF-8 BOM (EF BB BF)
# 4. UTF-8 multi-byte in first 32 bytes
# 5. Default: Windows-1252 (CP1252)

encoding = get_script_encoding(raw_bytes)
text = raw_bytes.decode(encoding)
utf16_bytes = text.encode('utf-16-le')
hash = sha1(utf16_bytes)
```

### Authenticode Structure

The signature embeds:

- `SpcIndirectDataContent` with file hash
- `SpcSipInfo` with PowerShell SIP GUID
- Full certificate chain
- RFC3161 timestamp (optional)

See [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) for full technical details.

## Troubleshooting

### "Status: NotSigned" on Windows

This means you used an **ECDSA certificate**. Windows requires RSA:

```bash
# Remove old certificate
rm -rf ~/.config/demo-cfssl/codesign/mycodesign

# Generate RSA certificate (default)
source steps.sh
step_codesign "MyCodeSign"
```

### "Status: UnknownError" or "Certificate not trusted"

Import CA certificates to Windows trust store:

```powershell
Import-Certificate -FilePath ca.pem -CertStoreLocation Cert:\CurrentUser\Root
Import-Certificate -FilePath csica-ca.pem -CertStoreLocation Cert:\CurrentUser\CA
```

### "HashMismatch" Error

This should not happen with current pkipy. If it does:

1. Ensure you're using the latest version
2. Check that the script file isn't corrupted
3. Try re-signing the original unsigned script

## Comparison with Other Tools

| Feature            | pkipy | Set-AuthenticodeSignature | osslsigncode |
| ------------------ | ----- | ------------------------- | ------------ |
| Pure Python        | ✅    | ❌                        | ❌           |
| Cross-platform     | ✅    | ❌                        | ✅           |
| Windows Validated  | ✅    | ✅                        | N/A          |
| PowerShell Scripts | ✅    | ✅                        | ❌           |
| RFC3161 Timestamp  | ✅    | ✅                        | ✅           |
| PFX Support        | ✅    | ✅                        | ✅           |
| PEM Support        | ✅    | ❌                        | ✅           |
| Config File        | ✅    | ❌                        | ❌           |

## Dependencies

- `cryptography` - Cryptographic operations
- `asn1crypto` - ASN.1 structure manipulation
- `rfc3161ng` - RFC3161 timestamp client
- `requests` - HTTP client for TSA
- `configargparse` - Configuration management
- `pyyaml` - YAML parsing

## License

Same as the parent ca-n-certs project. See LICENSE file.

## References

- [RFC 5652 - Cryptographic Message Syntax](https://tools.ietf.org/html/rfc5652)
- [RFC 3161 - Time-Stamp Protocol](https://tools.ietf.org/html/rfc3161)
- [PowerShell-OpenAuthenticode](https://github.com/jborean93/PowerShell-OpenAuthenticode)
- [Microsoft Authenticode](https://docs.microsoft.com/en-us/windows-hardware/drivers/install/authenticode)
