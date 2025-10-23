# Getting Started with demo-cfssl

This guide will help you set up and use demo-cfssl for certificate management.

## Prerequisites

### Required Tools

1. **CFSSL** - Certificate generation toolkit

   - Download from [CloudFlare CFSSL Releases](https://github.com/cloudflare/cfssl/releases)
   - Required binaries: `cfssl`, `cfssljson`
   - Or use Docker: `cfssl/cfssl`

2. **OpenSSL** - Certificate operations

   - Usually pre-installed on Linux/macOS
   - Windows: Install from [OpenSSL.org](https://www.openssl.org/)

3. **Python 3.8+** (for OCSP responder)

   ```bash
   python3 --version
   ```

4. **Bash** - Shell scripting (Linux/macOS/WSL)

### Optional Tools

- **Docker** - For containerized deployment
- **jq** - JSON processing (recommended)
- **GNU coreutils** - For macOS users: `brew install coreutils`

## Installation

### Method 1: Using System CFSSL

```bash
# Linux (example for x86_64)
wget https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssl_1.6.5_linux_amd64
wget https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssljson_1.6.5_linux_amd64
chmod +x cfssl_* cfssljson_*
sudo mv cfssl_* /usr/local/bin/cfssl
sudo mv cfssljson_* /usr/local/bin/cfssljson

# Verify installation
cfssl version
cfssljson --version
```

### Method 2: Using Docker

No installation needed - scripts use Docker image `cfssl/cfssl`

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/demo-cfssl.git
cd demo-cfssl
```

### 2. Generate CA Infrastructure

```bash
# This creates Root CA, Intermediate CA, and first host certificate
./steps.sh
```

This will create certificates in `~/.config/demo-cfssl/`:

- Root CA (`ca.pem`, `ca-key.pem`)
- Intermediate CA (`ica-ca.pem`, `ica-key.pem`)
- Localhost certificate (`hosts/localhost/`)

### 3. Verify Certificates

```bash
# Check Root CA
openssl x509 -in ~/.config/demo-cfssl/ca.pem -noout -text

# Check Intermediate CA
openssl x509 -in ~/.config/demo-cfssl/ica-ca.pem -noout -text

# Verify chain
openssl verify -CAfile ~/.config/demo-cfssl/ca.pem \
    ~/.config/demo-cfssl/ica-ca.pem

# Verify host certificate
openssl verify -CAfile ~/.config/demo-cfssl/ca-bundle.pem \
    ~/.config/demo-cfssl/hosts/localhost/cert.pem
```

### 4. Start OCSP Responder (Optional)

```bash
cd ocsp
./start.sh
```

## Basic Usage

### Generate Host Certificate

```bash
# Edit steps.sh and add at the end:
step03 "myserver.example.com" "*.example.com" "server.local"

# Or use the function directly:
source steps.sh
step03 "myserver.example.com" "*.example.com"
```

### Generate Email Certificate

```bash
source steps.sh
step_email "John Doe" john.doe@example.com john@company.com
```

The generated `.p12` file can be imported into email clients.

### Check Certificate Status

```bash
# Check if certificate is revoked
./crl_check.sh ~/.config/demo-cfssl/hosts/myserver/cert.pem
```

### Sign a Document

```bash
# Sign with S/MIME certificate
./tsa_sign.sh --p12 ~/.config/demo-cfssl/smime/john_doe/email.p12 document.pdf

# Verify signature
./tsa_verify.sh document.pdf
```

## Directory Structure After Setup

```
~/.config/demo-cfssl/
├── 00_ca.json           # Root CA config
├── 01_ica.json          # Intermediate CA config
├── 02_host.json         # Host certificate template
├── 03_email.json        # Email certificate template
├── profiles.json        # Certificate profiles
├── ca.pem               # Root CA certificate
├── ca-key.pem           # Root CA private key (protect!)
├── ca.csr               # Root CA signing request
├── ica-ca.pem           # Intermediate CA certificate
├── ica-key.pem          # Intermediate CA private key (protect!)
├── ica.csr              # Intermediate CA signing request
├── ca-bundle.pem        # CA + ICA bundle
├── dhparam.pem          # DH parameters for TLS
├── hosts/               # Host certificates directory
│   └── localhost/
│       ├── cfg.json
│       ├── cert.pem     # Certificate
│       ├── key.pem      # Private key (protect!)
│       ├── host.csr     # Signing request
│       ├── bundle-2.pem # Cert + ICA
│       ├── bundle-3.pem # Cert + ICA + CA
│       └── haproxy.pem  # Full chain + key
├── smime/               # Email certificates directory
│   └── john_doe/
│       ├── cfg.json
│       ├── cert.pem
│       ├── key.pem
│       ├── email.csr
│       ├── bundle-*.pem
│       └── email.p12    # PKCS#12 for email clients
└── crl/                 # Revocation database
    ├── ca/
    └── ica/
```

## Configuration

### Certificate Validity Periods

Edit `steps.sh` to change default validity periods:

```bash
CA_EXPIRY=`expr 365 \* 24`      # 1 year in hours
HOST_EXPIRY=`expr 47 \* 24`     # 47 days
EMAIL_EXPIRY=`expr 265 \* 24`   # ~9 months
```

### Key Algorithm

Change between RSA and ECDSA in `steps.sh`:

```bash
# For ECDSA (default, recommended)
KEY_ALGO="ecdsa"
KEY_SIZE=384  # P-384 curve

# For RSA
KEY_ALGO="rsa"
KEY_SIZE=4096
```

### Distinguished Name Fields

Edit the JSON configuration files:

```bash
# Root CA
nano ~/.config/demo-cfssl/00_ca.json

# Intermediate CA
nano ~/.config/demo-cfssl/01_ica.json
```

Change fields like `C` (Country), `ST` (State), `L` (Locality), `O` (Organization), `OU` (Organizational Unit).

## Customization

### Custom Certificate Storage Location

```bash
# Set custom directory
export DEMO_CFSSL_DIR=/path/to/custom/location
./steps.sh
```

### Custom OCSP and CRL URLs

When generating certificates with OCSP/CRL URLs:

```bash
export OCSP_URL="http://ocsp.yourdomain.com/ocsp"
export CRL_URL="http://crl.yourdomain.com/ica.crl"

# Use helper to configure
cd ocsp
./add_ocsp_to_profiles.sh
```

## Next Steps

- **[Certificate Management](certificate-management.md)** - Detailed certificate operations
- **[Certificate Revocation](revocation.md)** - CRL and OCSP setup
- **[Production Deployment](deployment.md)** - Deploy to production
- **[Examples & Workflows](examples.md)** - Practical examples

## Common Issues

### CFSSL Not Found

```bash
# Check if installed
which cfssl

# If using Docker, ensure Docker is running
docker ps
```

### Permission Denied

```bash
# Ensure scripts are executable
chmod +x *.sh

# Check directory permissions
ls -la ~/.config/demo-cfssl/
```

### Certificate Verification Failed

```bash
# Check if CA is in system trust store
openssl verify ~/.config/demo-cfssl/ica-ca.pem

# If not, add CA to system (see deployment.md)
```

### macOS Missing GNU Tools

```bash
# Install GNU coreutils
brew install coreutils

# Verify installation
which gstat
which gdate
```

## Support

- **Documentation**: See other files in `docs/`
- **Examples**: Check `examples.md` for practical scenarios
- **Troubleshooting**: See `troubleshooting.md`
- **Architecture**: See `AGENTS.md` for design decisions

## Related Tools

- **[OCSP Responder](../ocsp/README.md)** - Online certificate validation
- **[PDF Signer](../pdf-signer/README.md)** - Document signing tool
