# pkipy Quick Start Guide

Sign PowerShell scripts with Authenticode signatures **from any platform** (Linux, macOS, Windows)!

🎉 **Cross-platform signing now works!** Signatures validate with Windows `Get-AuthenticodeSignature`.

## Prerequisites

- `uv` package manager installed
- Root CA and Intermediate CA already generated (run `../steps.sh` first)

## Step 1: Generate Code Signing Certificate

> ⚠️ **IMPORTANT**: Windows Authenticode for PowerShell scripts **only supports RSA certificates**.
> The `step_codesign` function defaults to RSA for this reason.

```bash
# Navigate to project root
cd /path/to/ca-n-certs

# Source the certificate generation functions
source steps.sh

# Generate code signing certificate (RSA by default - required for Windows)
step_codesign "MyCodeSign"
```

This creates:

- `~/.config/demo-cfssl/codesign/mycodesign/cert.pem` - Certificate
- `~/.config/demo-cfssl/codesign/mycodesign/key.pem` - Private key
- `~/.config/demo-cfssl/codesign/mycodesign/codesign.p12` - PKCS#12 bundle

## Step 2: (Optional) Create Configuration File

```bash
mkdir -p ~/.config/pkipy

cat > ~/.config/pkipy/config.yaml << EOF
pfx: ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
timestamp-url: http://timestamp.digicert.com
EOF
```

## Step 3: Sign a PowerShell Script

### Using Config File

```bash
cd pkipy
uv run pkipy script.ps1 --output signed.ps1
```

### Using Command Line Arguments

```bash
cd pkipy
uv run pkipy script.ps1 --output signed.ps1 \
    --pfx ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12 \
    --timestamp-url http://timestamp.digicert.com
```

### Using PEM Files

```bash
cd pkipy
uv run pkipy script.ps1 --output signed.ps1 \
    --cert ~/.config/demo-cfssl/codesign/mycodesign/cert.pem \
    --key ~/.config/demo-cfssl/codesign/mycodesign/key.pem \
    --timestamp-url http://timestamp.digicert.com
```

## Step 4: Verify Signature (on Windows)

Copy the signed script to a Windows machine and run:

```powershell
Get-AuthenticodeSignature signed.ps1 | Format-List *
```

### Trust the Certificate (Windows)

For the signature to show as "Valid", import your CA certificates:

```powershell
# Import Root CA
Import-Certificate -FilePath ca.pem -CertStoreLocation Cert:\LocalMachine\Root

# Import Intermediate CA
Import-Certificate -FilePath ica-ca.pem -CertStoreLocation Cert:\LocalMachine\CA
```

## Interactive Demo

Run the interactive demo to see everything in action:

```bash
cd pkipy
./demo.sh
```

## What's Next?

- Read the [full README](README.md) for detailed documentation
- Learn about [configuration options](config.yaml.example)
- Understand [how it works](../AGENTS.md) (ADR-010: Code Signing)

## Troubleshooting

### "Error: Either --pfx or both --cert and --key must be provided"

You need to specify certificate source. Either:

- Add to config: `~/.config/pkipy/config.yaml`
- Use `--pfx` flag
- Use `--cert` and `--key` flags
- Set environment: `export PKIPY_PFX=path/to/cert.p12`

### "Status: UnknownError" on Windows

Import your CA certificates (see "Trust the Certificate" above).

### Timestamp fails

- Check network connectivity to timestamp server
- Try a different timestamp server (see README for alternatives)
- Sign without timestamp using `--timestamp-url` omitted

### "Status: NotSigned" on Windows

This means you used an **ECDSA certificate**. Windows Authenticode only supports RSA.

```bash
# Remove old certificate and regenerate with RSA (default)
rm -rf ~/.config/demo-cfssl/codesign/mycodesign
source steps.sh && step_codesign "MyCodeSign"
```

## Quick Reference

```bash
# Generate certificate
source steps.sh && step_codesign "MyCodeSign"

# Sign script (minimal)
uv run pkipy script.ps1 --output signed.ps1 --pfx codesign.p12

# Sign with timestamp
uv run pkipy script.ps1 --output signed.ps1 \
    --pfx codesign.p12 \
    --timestamp-url http://timestamp.digicert.com

# View help
uv run pkipy --help

# View signature (Windows)
Get-AuthenticodeSignature signed.ps1
```

## Environment Variables

All options can be set via environment variables with `PKIPY_` prefix:

```bash
export PKIPY_PFX=~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
export PKIPY_TIMESTAMP_URL=http://timestamp.digicert.com

uv run pkipy script.ps1 --output signed.ps1
```

---

**Happy Signing! 🔐**
