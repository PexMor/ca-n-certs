# Split Step - Simplified Certificate Authority

## Overview

This folder provides a **simplified, modular approach** to Certificate Authority (CA) and certificate generation, splitting the functionality of the original [../steps.sh](../steps.sh) into focused, easy-to-understand components.

The original `steps.sh` grew to over 900 lines and became difficult to maintain. This split-step approach follows the Unix philosophy of **"do one thing and do it well"**, making it easier to understand, modify, and extend.

## Purpose

- **Educational**: Demonstrate CA hierarchy (Root CA → Intermediate CA → Server Certificate)
- **Practical**: Generate production-ready certificates for TLS/SSL servers
- **Maintainable**: Clean separation of configuration, utilities, and operations
- **Portable**: Works on Linux, macOS, and Windows (WSL2)

## Files in This Folder

| File                | Purpose               | Description                                                                    |
| ------------------- | --------------------- | ------------------------------------------------------------------------------ |
| **`a0_cfg.sh`**     | Configuration         | Certificate settings, DN fields, algorithms, validity periods                  |
| **`a1_lib.sh`**     | Library functions     | Reusable utilities for OS detection, certificate info display, date formatting |
| **`a2_my_ca.sh`**   | CA Generator          | Creates Root CA and Intermediate CA (run once)                                 |
| **`a3_my_cert.sh`** | Certificate Generator | Creates server certificates signed by Intermediate CA (run as needed)          |

## Quick Start

### 1. Generate Certificate Authority (One-Time Setup)

```bash
cd split_step
./a2_my_ca.sh
```

This creates:

- **Root CA**: Self-signed certificate (`ca.pem`, `ca-key.pem`)
- **Intermediate CA**: Signed by Root CA (`ica-ca.pem`, `ica-key.pem`)

### 2. Generate Server Certificate

```bash
./a3_my_cert.sh
```

This creates a certificate for `my.example.com` including:

- Private key (`key.pem`)
- Server certificate (`cert.pem`)
- Certificate bundles for various servers (Nginx, Apache, HAProxy)

## Configuration Options

All configuration is centralized in **`a0_cfg.sh`**. Edit this file to customize your certificates.

### Certificate Directory

```bash
DEF_BD="$HOME/.config/split_step"
```

- **Default**: `~/.config/split_step`
- **Override**: Pass directory as argument: `./a2_my_ca.sh /path/to/certs`

### Certificate Algorithm & Key Size

```bash
KEY_ALGO="ecdsa"    # Options: "ecdsa" or "rsa"
KEY_SIZE=384        # ECDSA: 256, 384, 521 | RSA: 2048, 4096
```

**Recommendations**:

- **ECDSA P-384**: Modern, fast, smaller keys (equivalent to RSA-7680)
- **RSA 4096**: Traditional, widely compatible

### Validity Periods

```bash
CA_EXPIRY=87600      # Root/Intermediate CA: 10 years (in hours)
HOST_EXPIRY=1128     # Server certificates: 47 days (in hours)
```

**Industry Context**:

- **47 days**: Follows modern CA/Browser Forum trend (previously 398 → 200 → 100 → 47 days)
- **10 years**: Root CAs are long-lived and rarely changed

### Distinguished Name (DN) Fields

```bash
CERT_C="CZ"                          # Country
CERT_ST="Heart of Europe"            # State/Province
CERT_L="Prague"                      # Locality/City
CERT_O="00 Split Step Company"       # Organization
CERT_OU="Security Dept."             # Organizational Unit

CA_CN="00-Split-Step-Root-CA"        # Root CA Common Name
ICA_CN="00-Split-Step-Intermediate-CA"  # Intermediate CA CN
HOST_CN="my.example.com"             # Server certificate CN
```

**Note**: Organization name starts with `00` to sort near the top in certificate lists.

### Subject Alternative Names (SANs)

```bash
HOST_SAN=(
    "DNS:my.example.com"
    "DNS:*.my.example.com"
    "DNS:localhost"
    "IP:127.0.0.1"
    "IP:::1"
)
```

Edit this array to add/remove SANs for your server certificate.

## Detailed Script Descriptions

### a0_cfg.sh - Configuration

**Purpose**: Central configuration file for all certificate parameters.

**Key Settings**:

- Certificate validity periods
- Key algorithms and sizes
- Distinguished Name (DN) fields
- Subject Alternative Names (SANs)
- Base directory for certificate storage

**Usage**: Edit this file before running CA or certificate generation scripts.

### a1_lib.sh - Library Functions

**Purpose**: Shared utility functions used by other scripts.

**Key Functions**:

- `detect_os_and_set_commands()`: Auto-detects OS (Linux/macOS) and sets correct commands
  - macOS: Uses GNU tools (`gstat`, `gdate`, `gsed`) - install via `brew install coreutils gnu-sed`
  - Linux: Uses standard tools (`stat`, `date`, `sed`)
- `info()`: Displays file size and modification date
- `x509info()`: Shows certificate details (validity, subject, issuer, SANs)
- `display_ica_info()`: Shows Intermediate CA information with colored output
- Color codes: `RED`, `GREEN`, `BLUE`, `YELLOW`, `AZURE` for readable terminal output

**Usage**: Automatically sourced by `a2_my_ca.sh` and `a3_my_cert.sh`.

### a2_my_ca.sh - CA Generator

**Purpose**: Generates Root CA and Intermediate CA certificates.

**What It Does**:

1. **Step 1 - Root CA**: Creates self-signed Root CA certificate

   - Generates ECDSA P-384 private key
   - Creates self-signed certificate with CA extensions
   - Sets Key Usage: `cRLSign`, `keyCertSign`
   - Sets Basic Constraints: `CA:TRUE`

2. **Step 2 - Intermediate CA**: Creates ICA signed by Root CA
   - Generates ECDSA P-384 private key
   - Creates Certificate Signing Request (CSR)
   - Signs with Root CA
   - Sets Basic Constraints: `CA:TRUE, pathlen:0` (cannot sign other CAs)

**Output Files** (in `$BD`):

```
ca-key.pem              # Root CA private key
ca.pem                  # Root CA certificate
ca-openssl.cnf          # OpenSSL config for Root CA
ica-key.pem             # Intermediate CA private key
ica-ca.pem              # Intermediate CA certificate
ica.csr                 # Intermediate CA CSR
ica-openssl.cnf         # OpenSSL config for ICA
ca.srl                  # Serial number tracker
```

**When to Run**:

- **Once** during initial setup
- **Every 10 years** (or before Root CA expires)

**Usage**:

```bash
./a2_my_ca.sh                        # Use default directory
./a2_my_ca.sh /custom/path           # Use custom directory
```

### a3_my_cert.sh - Certificate Generator

**Purpose**: Generates server (TLS/SSL) certificates signed by Intermediate CA.

**What It Does**:

1. Verifies Intermediate CA exists (`ica-ca.pem`, `ica-key.pem`)
2. Displays ICA information (validity, expiration warnings)
3. Generates server certificate for configured hostname
4. Creates multiple bundle formats for different servers

**Output Files** (in `$BD/my.example.com/`):

```
key.pem                 # Private key (for all TLS servers)
host.csr                # Certificate Signing Request
cert.pem                # Server certificate
bundle-2.pem            # cert + ICA (for most servers)
bundle-3.pem            # cert + ICA + Root CA (complete chain)
haproxy.pem             # Complete bundle with private key (HAProxy format)
openssl.cnf             # OpenSSL config used during generation
```

**Server Integration**:

| Server      | Use These Files            | Configuration                                 |
| ----------- | -------------------------- | --------------------------------------------- |
| **Nginx**   | `key.pem` + `bundle-2.pem` | `ssl_certificate`, `ssl_certificate_key`      |
| **Apache**  | `key.pem` + `bundle-2.pem` | `SSLCertificateFile`, `SSLCertificateKeyFile` |
| **Traefik** | `key.pem` + `bundle-2.pem` | Dynamic config or file provider               |
| **HAProxy** | `haproxy.pem`              | Single combined file                          |
| **Caddy**   | `key.pem` + `cert.pem`     | `tls` directive                               |

**When to Run**:

- **As needed** when you need new server certificates
- **Before expiry** (certificate expires in 47 days by default)

**Usage**:

```bash
./a3_my_cert.sh                      # Use default directory
./a3_my_cert.sh /custom/path         # Use custom directory
```

## Certificate Hierarchy

The scripts create a standard two-tier PKI hierarchy:

```
Root CA (ca.pem)
  └─> Intermediate CA (ica-ca.pem)
        └─> Server Certificate (cert.pem)
```

**Benefits**:

- **Security**: Root CA key can be stored offline
- **Flexibility**: Can revoke ICA without affecting Root CA
- **Best Practice**: Follows industry-standard PKI architecture

## System Requirements

### Required Tools

| Tool                       | Purpose                | Installation             |
| -------------------------- | ---------------------- | ------------------------ |
| **OpenSSL**                | Certificate operations | Usually pre-installed    |
| **bash**                   | Script execution       | Standard on Linux/macOS  |
| **coreutils** (macOS only) | GNU utilities          | `brew install coreutils` |
| **gnu-sed** (macOS only)   | GNU sed                | `brew install gnu-sed`   |

### macOS Setup

```bash
brew install coreutils gnu-sed
```

This provides `gstat`, `gdate`, and `gsed` which the scripts automatically detect and use.

### Linux Setup

No additional packages needed - standard utilities are sufficient.

### Windows (WSL2)

Install Ubuntu or Debian WSL2, then follow Linux instructions.

## Examples

### Example 1: Generate Complete PKI from Scratch

```bash
cd split_step
./a2_my_ca.sh           # Create Root CA + Intermediate CA
./a3_my_cert.sh         # Create server certificate
```

### Example 2: Use Custom Directory

```bash
mkdir -p /tmp/my-pki
./a2_my_ca.sh /tmp/my-pki
./a3_my_cert.sh /tmp/my-pki
```

### Example 3: Change to RSA Keys

Edit `a0_cfg.sh`:

```bash
KEY_ALGO="rsa"
KEY_SIZE=4096
```

Then generate:

```bash
./a2_my_ca.sh
./a3_my_cert.sh
```

### Example 4: Multiple Server Certificates

Modify `HOST_CN` and `HOST_SAN` in `a0_cfg.sh` between runs:

```bash
# First server
# Edit a0_cfg.sh: HOST_CN="server1.example.com"
./a3_my_cert.sh

# Second server
# Edit a0_cfg.sh: HOST_CN="server2.example.com"
./a3_my_cert.sh
```

## Advantages Over Original steps.sh

| Feature             | Original `steps.sh`                   | Split Step                             |
| ------------------- | ------------------------------------- | -------------------------------------- |
| **Size**            | 900+ lines                            | 4 files, ~250 lines each               |
| **Modularity**      | Single monolithic script              | Separate config, lib, CA, cert         |
| **Maintainability** | Hard to navigate                      | Clear separation of concerns           |
| **Reusability**     | Functions mixed with execution        | Reusable library (`a1_lib.sh`)         |
| **Configuration**   | Embedded in script                    | Centralized in `a0_cfg.sh`             |
| **Learning Curve**  | Steep (need to understand everything) | Gentle (understand one file at a time) |
| **Error Handling**  | Mixed                                 | Consistent with `set -euo pipefail`    |

## Relationship to Main Project

This `split_step/` folder is an **alternative, simplified implementation** of the main project's certificate generation:

| Main Project            | Split Step Equivalent           |
| ----------------------- | ------------------------------- |
| `steps.sh`              | `a2_my_ca.sh` + `a3_my_cert.sh` |
| CFSSL (CloudFlare)      | Pure OpenSSL                    |
| `~/.config/demo-cfssl/` | `~/.config/split_step/`         |
| JSON configs            | Shell variables                 |
| Docker support          | Direct command-line             |

**Use Split Step If**:

- You prefer pure OpenSSL over CFSSL
- You want simpler, easier-to-understand scripts
- You're learning PKI/certificate concepts
- You need a starting point to customize

**Use Main Project If**:

- You need OCSP responder integration
- You want CRL (Certificate Revocation List) support
- You prefer JSON-based configuration (CFSSL)
- You need the full feature set (TSA, PDF signing, etc.)

## Security Considerations

### Private Key Protection

- **Root CA key** (`ca-key.pem`): Store securely, use only for signing ICA
- **ICA key** (`ica-key.pem`): Store securely, use only for signing server certs
- **Server key** (`key.pem`): Deploy to server, but protect with file permissions (600)

### Recommended Practices

1. **Backup CA keys**: Store encrypted backups of `ca-key.pem` and `ica-key.pem`
2. **Restrict permissions**: `chmod 600 *.pem` on private keys
3. **Offline Root CA**: In production, keep Root CA on air-gapped system
4. **Certificate renewal**: Renew server certs before expiry (default: 47 days)
5. **Monitor expiration**: Set up alerts for certificate expiration

## Troubleshooting

### Error: "gstat not found" (macOS)

```bash
brew install coreutils
```

### Error: "gsed not found" (macOS)

```bash
brew install gnu-sed
```

### Error: "Intermediate CA certificate not found"

Run `./a2_my_ca.sh` first to create the CA hierarchy.

### Certificate Expired

Certificates are created with 47-day validity by default. To extend:

Edit `a0_cfg.sh`:

```bash
HOST_EXPIRY=8760  # 1 year in hours
```

Then regenerate:

```bash
./a3_my_cert.sh
```

### Wrong Organization Name in Certificate

Edit `CERT_O` in `a0_cfg.sh`, then regenerate:

```bash
rm -rf ~/.config/split_step  # Delete old certificates
./a2_my_ca.sh                # Regenerate CA
./a3_my_cert.sh              # Regenerate server cert
```

## Platform Compatibility

| Platform             | Status             | Notes                                     |
| -------------------- | ------------------ | ----------------------------------------- |
| **Linux**            | ✅ Fully Supported | Standard GNU tools                        |
| **macOS**            | ✅ Fully Supported | Requires `brew install coreutils gnu-sed` |
| **Windows WSL2**     | ✅ Supported       | Use Ubuntu/Debian distribution            |
| **Windows (native)** | ❌ Not Supported   | Use WSL2 instead                          |

## Future Enhancements

Potential additions (contributions welcome):

- [ ] Email certificate generation (S/MIME)
- [ ] Client certificate generation (mutual TLS)
- [ ] OCSP URL extensions
- [ ] CRL distribution point extensions
- [ ] Interactive mode with prompts
- [ ] Certificate renewal automation
- [ ] Expiration monitoring script

## References

- [RFC 5280](https://tools.ietf.org/html/rfc5280) - X.509 Certificates
- [CA/Browser Forum](https://cabforum.org/) - Industry standards
- [OpenSSL Documentation](https://www.openssl.org/docs/)
- [Main Project AGENTS.md](../AGENTS.md) - Architectural decisions

## Support

For issues, questions, or contributions:

1. Check [../docs/troubleshooting.md](../docs/troubleshooting.md)
2. Review [../docs/getting-started.md](../docs/getting-started.md)
3. Open an issue on the project repository

---

**Organization**: 00 Split Step Company (designed to sort first in certificate lists)  
**Default Directory**: `$HOME/.config/split_step`  
**Tested On**: Linux, macOS, Windows WSL2
