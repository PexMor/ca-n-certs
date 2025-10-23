# Certificate Revocation List (CRL) Management

This document describes how to manage Certificate Revocation Lists (CRLs) in this demo-cfssl project.

## Overview

The `crl_mk.sh` script provides a complete solution for creating and managing Certificate Revocation Lists. It allows you to:

- Revoke certificates that are compromised or no longer valid
- Generate signed CRLs for both Root CA and Intermediate CA
- List all revoked certificates
- Verify certificates against CRLs

## Prerequisites

Before using CRL management, you need to have your CA infrastructure set up:

```bash
# Create Root CA and Intermediate CA
./steps.sh

# Or use the Docker-based approach
./mkCert.sh
```

## Basic Usage

### 1. Revoke a Certificate

To revoke a certificate, you need to provide the certificate file and optionally a revocation reason:

```bash
./crl_mk.sh revoke /path/to/certificate.pem [REASON]
```

**Example:**

```bash
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/localhost/cert.pem keyCompromise
```

**Revocation Reasons:**

- `unspecified` - Default reason (used if no reason provided)
- `keyCompromise` - Private key has been compromised
- `CACompromise` - CA key has been compromised
- `affiliationChanged` - Certificate holder changed organization/affiliation
- `superseded` - Certificate has been replaced with a new one
- `cessationOfOperation` - Service/operation no longer exists
- `certificateHold` - Temporarily revoked (can be reversed)

### 2. Generate CRL

After revoking certificates, generate the CRL:

```bash
./crl_mk.sh generate [ca|ica]
```

**Examples:**

```bash
# Generate CRL for Intermediate CA (most common)
./crl_mk.sh generate ica

# Generate CRL for Root CA
./crl_mk.sh generate ca
```

The script will create:

- `~/.config/demo-cfssl/ica-crl.pem` - CRL in PEM format
- `~/.config/demo-cfssl/ica-crl.der` - CRL in DER format
- CRL database files in `~/.config/demo-cfssl/crl/ica/`

### 3. List Revoked Certificates

View all revoked certificates:

```bash
./crl_mk.sh list [ca|ica]
```

**Example:**

```bash
./crl_mk.sh list ica
```

This displays:

- Serial number of revoked certificate
- Revocation date and time
- Revocation reason
- Certificate subject

### 4. View CRL Information

Display detailed information about the CRL:

```bash
./crl_mk.sh info [ca|ica]
```

**Example:**

```bash
./crl_mk.sh info ica
```

This shows:

- CRL version and signature algorithm
- Issuer information
- Last update time
- Next update time (when CRL expires)
- Number of revoked certificates
- Days remaining until CRL expiration

### 5. Verify Certificate Against CRL

Check if a certificate is revoked using either the integrated command or the dedicated checking tool:

**Using crl_mk.sh:**

```bash
./crl_mk.sh verify /path/to/certificate.pem [ca|ica]
```

**Using the dedicated crl_check.sh tool (recommended):**

```bash
./crl_check.sh /path/to/certificate.pem
```

**Examples:**

```bash
# Basic check (auto-detects CRL)
./crl_check.sh ~/.config/demo-cfssl/hosts/localhost/cert.pem

# Verbose mode with detailed information
./crl_check.sh ~/.config/demo-cfssl/hosts/localhost/cert.pem --verbose

# Quiet mode (exit code only)
./crl_check.sh ~/.config/demo-cfssl/hosts/localhost/cert.pem --quiet

# JSON output for scripting
./crl_check.sh ~/.config/demo-cfssl/hosts/localhost/cert.pem --json

# Custom CRL and CA bundle
./crl_check.sh cert.pem --crl custom-crl.pem --ca-bundle ca-bundle.pem

# Batch check multiple certificates
./crl_check.sh --batch cert-list.txt
```

The `crl_check.sh` tool provides:
- Automatic CA detection (Root vs Intermediate)
- Detailed certificate information display
- Multiple output formats (normal, verbose, quiet, JSON)
- Batch checking mode for multiple certificates
- Clear exit codes for scripting (0=valid, 1=revoked, 2=error)

## Advanced Usage

### Custom Base Directory

You can specify a custom base directory for certificates:

```bash
./crl_mk.sh /custom/path revoke /custom/path/cert.pem keyCompromise
./crl_mk.sh /custom/path generate ica
```

### Workflow Example

Here's a complete workflow for revoking a server certificate:

```bash
# 1. Generate a server certificate (if not already done)
./steps.sh

# 2. Revoke the certificate (e.g., server was compromised)
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/localhost/cert.pem keyCompromise

# 3. Generate the updated CRL
./crl_mk.sh generate ica

# 4. Verify the certificate is now revoked
./crl_mk.sh verify ~/.config/demo-cfssl/hosts/localhost/cert.pem ica

# 5. List all revoked certificates
./crl_mk.sh list ica

# 6. Check CRL information
./crl_mk.sh info ica
```

## CRL Distribution

After generating a CRL, you typically need to distribute it to clients and services that need to verify certificates.

### Web Server Configuration

#### HAProxy

Add CRL verification to HAProxy:

```haproxy
global
    # ... other settings ...

frontend https_front
    bind *:443 ssl crt /path/to/certs/ ca-file /path/to/ca-bundle.pem crl-file /path/to/ica-crl.pem verify required
```

#### Nginx

```nginx
server {
    listen 443 ssl;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    ssl_client_certificate /path/to/ca-bundle.pem;
    ssl_crl /path/to/ica-crl.pem;
    ssl_verify_client on;
}
```

#### Apache

```apache
SSLCACertificateFile /path/to/ca-bundle.pem
SSLCARevocationFile /path/to/ica-crl.pem
SSLVerifyClient require
```

### OpenSSL Verification

Manual verification using OpenSSL:

```bash
# Verify certificate with CRL check
openssl verify -CAfile ~/.config/demo-cfssl/ca-bundle.pem \
    -crl_check \
    -CRLfile ~/.config/demo-cfssl/ica-crl.pem \
    ~/.config/demo-cfssl/hosts/localhost/cert.pem
```

## CRL Maintenance

### CRL Expiration

CRLs have an expiration date (default: 30 days). You should:

1. **Monitor CRL expiration**: Check regularly using `./crl_mk.sh info ica`
2. **Regenerate before expiration**: Run `./crl_mk.sh generate ica` periodically
3. **Automate regeneration**: Set up a cron job to regenerate CRLs

### Automated CRL Updates (Cron Job)

Add to your crontab to regenerate CRL weekly:

```bash
# Regenerate Intermediate CA CRL every Monday at 2 AM
0 2 * * 1 /path/to/demo-cfssl/crl_mk.sh generate ica >> /var/log/crl-update.log 2>&1
```

### Multiple Revocations

You can revoke multiple certificates before generating the CRL:

```bash
# Revoke several certificates
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/server1/cert.pem keyCompromise
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/server2/cert.pem superseded
./crl_mk.sh revoke ~/.config/demo-cfssl/smime-openssl/john_doe/cert.pem affiliationChanged

# Generate CRL once with all revocations
./crl_mk.sh generate ica
```

## File Structure

After using CRL management, you'll have the following structure:

```
~/.config/demo-cfssl/
├── ca.pem                    # Root CA certificate
├── ca-key.pem                # Root CA private key
├── ca-crl.pem               # Root CA CRL (PEM format)
├── ca-crl.der               # Root CA CRL (DER format)
├── ica-ca.pem               # Intermediate CA certificate
├── ica-key.pem              # Intermediate CA private key
├── ica-crl.pem              # Intermediate CA CRL (PEM format)
├── ica-crl.der              # Intermediate CA CRL (DER format)
└── crl/
    ├── ca/
    │   ├── index.txt        # Root CA revocation database
    │   ├── crlnumber        # CRL serial number
    │   ├── openssl.cnf      # OpenSSL config for Root CA CRL
    │   └── crl.pem          # Current Root CA CRL
    └── ica/
        ├── index.txt        # Intermediate CA revocation database
        ├── crlnumber        # CRL serial number
        ├── openssl.cnf      # OpenSSL config for Intermediate CA CRL
        └── crl.pem          # Current Intermediate CA CRL
```

## Technical Details

### CRL Format

The script generates CRLs in both formats:

- **PEM format** (`.pem`): Text-based, Base64 encoded, human-readable headers
- **DER format** (`.der`): Binary format, more compact

Use PEM for most applications, DER for systems that specifically require it.

### Database Format

The `index.txt` file uses the standard OpenSSL CA database format:

```
R	expiry_date	revocation_date,reason	serial	unknown	subject_dn
```

Where:

- `R` = Revoked status
- `expiry_date` = Original certificate expiration
- `revocation_date` = When certificate was revoked
- `reason` = Revocation reason code
- `serial` = Certificate serial number
- `subject_dn` = Certificate distinguished name

### CRL Validity Period

Default CRL validity: 30 days (`default_crl_days` in OpenSSL config)

To change this, edit the generated `openssl.cnf` in the CRL directory:

```bash
# Edit the config
nano ~/.config/demo-cfssl/crl/ica/openssl.cnf

# Change this line:
default_crl_days  = 90  # Now valid for 90 days

# Regenerate CRL
./crl_mk.sh generate ica
```

## Troubleshooting

### "Certificate was issued by Root CA" but expecting ICA

The script automatically detects which CA issued a certificate. If you see this message but expected the Intermediate CA, verify the certificate:

```bash
openssl x509 -in /path/to/cert.pem -noout -issuer
```

### "CRL is EXPIRED"

Regenerate the CRL:

```bash
./crl_mk.sh generate ica
```

### "Certificate is already revoked"

The certificate is already in the revocation database. This is not an error, just a warning that the revocation was already recorded.

### gdate/gstat not found (macOS)

Install GNU coreutils:

```bash
brew install coreutils
```

## Security Considerations

1. **Protect CRL signing keys**: The CA private keys are used to sign CRLs. Keep them secure.
2. **Regular CRL updates**: Even if no new revocations, regenerate CRLs before expiration.
3. **Distribution**: Ensure CRLs are accessible to all systems that need to verify certificates.
4. **Backup revocation database**: The `index.txt` file contains all revocation records.
5. **Immediate revocation**: After revoking a certificate, immediately generate and distribute the new CRL.

## Integration with Existing Scripts

The CRL management integrates seamlessly with existing scripts:

```bash
# Full workflow
./steps.sh                                    # Create CA infrastructure
./crl_mk.sh generate ica                     # Create initial empty CRL

# Later, if a certificate is compromised
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/server1/cert.pem keyCompromise
./crl_mk.sh generate ica                     # Update CRL

# Generate new certificate for the server
./steps.sh                                    # Creates new certificate with new serial

# Verify new certificate is not revoked
./crl_mk.sh verify ~/.config/demo-cfssl/hosts/server1/cert.pem ica
```

## References

- [RFC 5280 - X.509 Certificate and CRL Profile](https://tools.ietf.org/html/rfc5280)
- [OpenSSL CA Documentation](https://www.openssl.org/docs/man1.1.1/man1/ca.html)
- [OpenSSL CRL Documentation](https://www.openssl.org/docs/man1.1.1/man1/crl.html)
