# pkipy - Pure Python PowerShell Authenticode Signer

A pure Python implementation of Authenticode signing for PowerShell scripts with RFC3161 timestamping support.

## Features

- ✅ **Pure Python** - No PowerShell or Windows required
- ✅ **Cross-platform** - Works on Linux, macOS, and Windows
- ✅ **RFC3161 Timestamping** - Optional trusted timestamp support
- ✅ **Flexible Configuration** - Config file, environment variables, or CLI args
- ✅ **PFX and PEM Support** - Use either certificate format

## Installation

This tool is managed by `uv` and integrated into the ca-n-certs project:

```bash
# Install dependencies
uv sync

# Run directly
uv run pkipy --help
```

## Quick Start

### 1. Generate a Code Signing Certificate

First, generate a code signing certificate using the project's certificate generation scripts:

```bash
# Source the steps.sh functions
source steps.sh

# Generate code signing certificate (RSA by default - required for Windows)
step_codesign "MyCodeSign"

# Or explicitly specify RSA
step_codesign "MyCodeSign" rsa
```

> ⚠️ **IMPORTANT**: Windows Authenticode for PowerShell scripts **only supports RSA certificates**.
> ECDSA signatures are valid CMS/PKCS#7 but Windows will report "NotSigned" for PS scripts.
> The `step_codesign` function defaults to RSA for this reason.

This creates:

- Certificate and key: `~/.config/demo-cfssl/codesign/mycodesign/`
- PKCS#12 file: `~/.config/demo-cfssl/codesign/mycodesign/codesign.p12`

### 2. Sign a PowerShell Script

```bash
# Using PFX file
uv run pkipy script.ps1 --output signed.ps1 \
  --pfx ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12 \
  --timestamp-url http://timestamp.digicert.com

# Using PEM files
uv run pkipy script.ps1 --output signed.ps1 \
  --cert ~/.config/demo-cfssl/codesign/mycodesign/cert.pem \
  --key ~/.config/demo-cfssl/codesign/mycodesign/key.pem \
  --timestamp-url http://timestamp.digicert.com
```

### 3. Verify the Signature (on Windows with PowerShell)

```powershell
Get-AuthenticodeSignature signed.ps1 | Format-List *
```

Expected output:

```
Status                : Valid
SignerCertificate     : [your certificate details]
TimeStamperCertificate: [TSA certificate details]
```

## Configuration

### Priority Order

Configuration is loaded in this order (later overrides earlier):

1. **Config file**: `~/.config/pkipy/config.yaml` (or `.yml`, `.toml`)
2. **Environment variables**: Prefix with `PKIPY_`
3. **Command line arguments**: Direct CLI args

### Config File Setup

Create a config file for easier usage:

```bash
# Create config directory
mkdir -p ~/.config/pkipy

# Copy example config
cp pkipy/config.yaml.example ~/.config/pkipy/config.yaml

# Edit with your settings
nano ~/.config/pkipy/config.yaml
```

Example `config.yaml`:

```yaml
# Use PFX file
pfx: ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
pfx-password: ""

# Or use PEM files (comment out pfx if using this)
# cert: ~/.config/demo-cfssl/codesign/mycodesign/cert.pem
# key: ~/.config/demo-cfssl/codesign/mycodesign/key.pem

# Timestamp server
timestamp-url: http://timestamp.digicert.com
```

With a config file, you can simply run:

```bash
uv run pkipy script.ps1 --output signed.ps1
```

### Environment Variables

All config options can be set via environment variables with the `PKIPY_` prefix:

```bash
export PKIPY_PFX=~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
export PKIPY_TIMESTAMP_URL=http://timestamp.digicert.com

uv run pkipy script.ps1 --output signed.ps1
```

## Usage Examples

### Basic Signing (No Timestamp)

```bash
uv run pkipy script.ps1 --output signed.ps1 \
  --pfx codesign.p12
```

### Signing with Timestamp

```bash
uv run pkipy script.ps1 --output signed.ps1 \
  --pfx codesign.p12 \
  --timestamp-url http://timestamp.digicert.com
```

### Using PEM Files with Password-Protected Key

```bash
uv run pkipy script.ps1 --output signed.ps1 \
  --cert cert.pem \
  --key key.pem \
  --key-password "mypassword" \
  --timestamp-url http://timestamp.digicert.com
```

### Using Custom Config File

```bash
uv run pkipy script.ps1 --output signed.ps1 \
  --config /path/to/custom-config.yaml
```

## Timestamp Servers

Popular RFC3161 timestamp servers (all free to use):

- DigiCert: `http://timestamp.digicert.com`
- Sectigo: `http://timestamp.sectigo.com`
- Comodo: `http://timestamp.comodoca.com`
- IdenTrust: `http://timestamp.identrust.com`
- Starfield: `http://tsa.starfieldtech.com`

**Why use timestamps?**

Timestamps prove when code was signed, allowing signatures to remain valid even after the certificate expires.

## Technical Details

### How It Works

1. **Build CMS SignedData**: Creates an Authenticode-compatible PKCS#7/CMS structure
2. **Sign the Script**: Signs the script content with your private key
3. **Request Timestamp** (optional): Asks RFC3161 TSA to timestamp the signature
4. **Embed Timestamp**: Adds timestamp as unsigned attribute (`id-aa-signatureTimeStampToken`)
5. **Embed Signature Block**: Wraps the CMS in PowerShell's `# SIG #` comment block

### Standards Compliance

- **RFC 5652**: Cryptographic Message Syntax (CMS)
- **RFC 6960**: X.509 Internet Public Key Infrastructure Online Certificate Status Protocol (OCSP)
- **RFC 3161**: Time-Stamp Protocol (TSP)
- **Microsoft Authenticode**: Code signing format for Windows executables and scripts

### Dependencies

- `cryptography` - Cryptographic operations
- `asn1crypto` - ASN.1 structure manipulation
- `rfc3161ng` - RFC3161 timestamp client
- `requests` - HTTP client for TSA communication
- `configargparse` - Configuration management
- `pyyaml` - YAML configuration parsing

## Troubleshooting

### "Status: NotSigned" on Windows

This almost always means you used an **ECDSA certificate** instead of RSA.
Windows Authenticode for PowerShell scripts **only supports RSA certificates**.

**Solution**: Regenerate your code signing certificate with RSA (the default):

```bash
# Remove old ECDSA certificate (if exists)
rm -rf ~/.config/demo-cfssl/codesign/mycodesign

# Generate new RSA certificate (default)
source steps.sh
step_codesign "MyCodeSign"

# Re-sign your script
uv run pkipy script.ps1 --output signed.ps1 \
  --pfx ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12 \
  --timestamp-url http://timestamp.digicert.com
```

### "Status: UnknownError" in PowerShell

This usually means the certificate chain is not trusted. Solutions:

1. **Import Root CA** into Windows Trusted Root store:

   ```powershell
   Import-Certificate -FilePath ca.pem -CertStoreLocation Cert:\LocalMachine\Root
   ```

2. **Import Intermediate CA** into Intermediate store:
   ```powershell
   Import-Certificate -FilePath ica-ca.pem -CertStoreLocation Cert:\LocalMachine\CA
   ```

### "The certificate chain was issued by an authority that is not trusted"

Same as above - import your CA certificates into Windows certificate store.

### Signature works but no timestamp

Check that:

- TSA URL is accessible from your network
- Firewall allows outbound HTTP/HTTPS to TSA
- TSA server is operational (try different TSA if one is down)

### "Error: Either --pfx or both --cert and --key must be provided"

You must specify certificate source. Options:

- Use `--pfx codesign.p12`
- Use `--cert cert.pem --key key.pem`
- Configure in `~/.config/pkipy/config.yaml`
- Set via environment: `PKIPY_PFX=codesign.p12`

## Integration with Project

This tool integrates with the ca-n-certs project:

1. **Certificate Generation**: Use `step_codesign` function in `steps.sh`
2. **CA Infrastructure**: Leverages existing Root CA and Intermediate CA
3. **Certificate Format**: Compatible with project's certificate structure

### Key Algorithm Requirements

| Platform                   | Algorithm    | Status                       |
| -------------------------- | ------------ | ---------------------------- |
| Windows (PowerShell)       | **RSA only** | ✅ Required for Authenticode |
| Windows (PowerShell)       | ECDSA        | ❌ Reports "NotSigned"       |
| Linux/macOS (verification) | RSA          | ✅ Supported                 |
| Linux/macOS (verification) | ECDSA        | ✅ Supported                 |

The `step_codesign` function defaults to RSA 3072-bit for Windows compatibility.

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

## License

Same as the parent ca-n-certs project. See LICENSE file.

## Contributing

This tool is part of the ca-n-certs demonstration project. Contributions welcome!

## References

- [RFC 5652 - Cryptographic Message Syntax](https://tools.ietf.org/html/rfc5652)
- [RFC 3161 - Time-Stamp Protocol](https://tools.ietf.org/html/rfc3161)
- [Microsoft Authenticode Specification](https://docs.microsoft.com/en-us/windows-hardware/drivers/install/authenticode)
- [PowerShell Code Signing](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing)
