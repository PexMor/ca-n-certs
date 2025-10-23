# Certificate Management

This guide covers creating, managing, and maintaining certificates using demo-cfssl.

## Certificate Hierarchy

```
Root CA (ca.pem)
  └── Intermediate CA (ica-ca.pem)
        ├── Host Certificates (TLS/SSL)
        ├── Email Certificates (S/MIME)
        └── Client Certificates
```

**Why use an Intermediate CA?**

- Protects Root CA private key (kept offline)
- Allows Root CA key rotation without re-issuing all certificates
- Industry best practice
- Enables certificate revocation without compromising root trust

## Certificate Types

### 1. Root CA Certificate

**Purpose**: Top-level trust anchor
**Validity**: 10 years (87,600 hours)
**Usage**: Signs Intermediate CA only

**Generation** (automatic via `steps.sh`):

```bash
cfssl gencert -initca 00_ca.json > ca.json
```

**Key Fields**:

- CN: `000-AtHome-Root-CA`
- Key Usage: Certificate Sign, CRL Sign
- Basic Constraints: CA:TRUE

### 2. Intermediate CA Certificate

**Purpose**: Signs end-entity certificates
**Validity**: 5-10 years
**Usage**: Signs host, email, client certificates

**Generation** (automatic via `steps.sh`):

```bash
# Generate self-signed
cfssl gencert -initca 01_ica.json > ica.json

# Sign with Root CA
cfssl sign -ca ca.pem -ca-key ca-key.pem \
    -config profiles.json -profile intermediate_ca \
    ica.csr > ica-ca.json
```

**Key Fields**:

- CN: `000-AtHome-Intermediate-CA`
- Key Usage: Digital Signature, Certificate Sign, CRL Sign
- Basic Constraints: CA:TRUE, pathlen:0

### 3. Host/Server Certificates (TLS/SSL)

**Purpose**: HTTPS, TLS servers
**Validity**: 47 days (industry trend)
**Profile**: `server`

**Key Usages**:

- Digital Signature
- Key Encipherment
- Server Authentication

**Generate with CFSSL**:

```bash
# Using steps.sh function
source steps.sh
step03 "server1.example.com" "*.example.com" "server1.local"
```

**Generate with OpenSSL (for OCSP/CRL URLs)**:

```bash
BD="$HOME/.config/demo-cfssl"
NAME="server1.example.com"
OCSP_URL="http://ocsp.example.com/ocsp"
CRL_URL="http://crl.example.com/ica.crl"

# Create OpenSSL config
cat > /tmp/server.cnf << EOF
[req]
distinguished_name = req_dn
req_extensions = v3_req
prompt = no

[req_dn]
C  = CZ
ST = Heart of Europe
L  = Prague
O  = At Home Company
OU = Security Dept.
CN = ${NAME}

[v3_req]
subjectAltName = DNS:${NAME},DNS:*.example.com

[v3_ca]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
authorityInfoAccess = OCSP;URI:${OCSP_URL}
crlDistributionPoints = URI:${CRL_URL}
subjectAltName = DNS:${NAME},DNS:*.example.com
EOF

# Generate key
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
    -out /tmp/server-key.pem

# Generate CSR
openssl req -new -key /tmp/server-key.pem \
    -out /tmp/server.csr -config /tmp/server.cnf

# Sign with ICA
openssl x509 -req -in /tmp/server.csr \
    -CA "$BD/ica-ca.pem" -CAkey "$BD/ica-key.pem" \
    -CAcreateserial -out /tmp/server-cert.pem \
    -days 47 -sha384 \
    -extfile /tmp/server.cnf -extensions v3_ca
```

**Subject Alternative Names (SANs)**:

- Always include CN in SANs
- Support wildcards: `*.example.com`
- Multiple names: `server1.com`, `server1.local`, `192.168.1.10`

### 4. Email Certificates (S/MIME)

**Purpose**: Email signing and encryption
**Validity**: 265 days (~9 months)
**Profile**: `email`

**Key Usages**:

- Digital Signature
- Key Encipherment
- Email Protection (with OpenSSL method)

**Generate with steps.sh**:

```bash
source steps.sh

# Basic method (CFSSL)
step_email "John Doe" john.doe@example.com john@company.com

# OpenSSL method (proper Email Protection EKU)
step_email_openssl "John Doe" john.doe@example.com john@company.com
```

**Generated Files**:

```
smime/john_doe/
├── cert.pem      # Certificate
├── key.pem       # Private key
├── email.csr     # Signing request
├── bundle-2.pem  # Cert + ICA
├── bundle-3.pem  # Cert + ICA + CA
└── email.p12     # PKCS#12 for email clients
```

**PKCS#12 Password**:

```bash
# Without password (default)
step_email "John Doe" john@example.com

# With password
EMAIL_P12_PASSWORD="mypassword" step_email "John Doe" john@example.com
```

**Import into Email Clients**:

- **Thunderbird**: Settings → Privacy & Security → Certificates → Import
- **Outlook**: File → Options → Trust Center → Email Security → Import/Export
- **Apple Mail**: Double-click `.p12` file
- **Gmail**: Settings → Accounts → Add S/MIME certificate

### 5. Client Certificates

**Purpose**: Client authentication (mTLS)
**Validity**: Configurable
**Profile**: `client` or `peer`

**Usage Scenarios**:

- API authentication
- VPN access
- Database connections
- SSH certificate authentication

## Certificate Profiles

Profiles defined in `profiles.json`:

### intermediate_ca

```json
{
  "usages": [
    "signing",
    "digital signature",
    "key encipherment",
    "cert sign",
    "crl sign",
    "server auth",
    "client auth"
  ],
  "expiry": "87600h",
  "ca_constraint": {
    "is_ca": true,
    "max_path_len": 0
  }
}
```

### server

```json
{
  "usages": ["signing", "digital signing", "key encipherment", "server auth"],
  "expiry": "1128h"
}
```

### email

```json
{
  "usages": ["signing", "digital signature", "key encipherment"],
  "expiry": "6360h"
}
```

## Certificate Bundles

### Bundle Types

1. **bundle-2.pem**: Certificate + Intermediate CA

   - Use when Root CA is in trust store
   - Most common for web servers

2. **bundle-3.pem**: Certificate + Intermediate CA + Root CA

   - Complete chain
   - Use when Root CA not in trust store
   - Good for testing

3. **haproxy.pem**: bundle-3.pem + Private Key
   - Specific to HAProxy format
   - Contains both certificate chain and key

### Creating Bundles

```bash
BD="$HOME/.config/demo-cfssl"
CERT_DIR="$BD/hosts/server1"

# Bundle-2
cat "$CERT_DIR/cert.pem" "$BD/ica-ca.pem" > "$CERT_DIR/bundle-2.pem"

# Bundle-3
cat "$CERT_DIR/cert.pem" "$BD/ica-ca.pem" "$BD/ca.pem" > "$CERT_DIR/bundle-3.pem"

# HAProxy bundle
cat "$CERT_DIR/bundle-3.pem" "$CERT_DIR/key.pem" > "$CERT_DIR/haproxy.pem"
```

## Certificate Inspection

### View Certificate Details

```bash
# Basic info
openssl x509 -in cert.pem -noout -text

# Subject and Issuer
openssl x509 -in cert.pem -noout -subject -issuer

# Validity dates
openssl x509 -in cert.pem -noout -dates

# Serial number
openssl x509 -in cert.pem -noout -serial

# Subject Alternative Names
openssl x509 -in cert.pem -noout -ext subjectAltName

# Key usage
openssl x509 -in cert.pem -noout -ext keyUsage,extendedKeyUsage

# OCSP and CRL URLs
openssl x509 -in cert.pem -noout -text | grep -A3 "Authority Information"
openssl x509 -in cert.pem -noout -text | grep -A3 "CRL Distribution"
```

### Verify Certificate

```bash
BD="$HOME/.config/demo-cfssl"

# Verify ICA against Root CA
openssl verify -CAfile "$BD/ca.pem" "$BD/ica-ca.pem"

# Verify host cert against chain
openssl verify -CAfile "$BD/ca-bundle.pem" "$BD/hosts/server1/cert.pem"

# Verify with explicit chain
openssl verify -CAfile "$BD/ca.pem" -untrusted "$BD/ica-ca.pem" \
    "$BD/hosts/server1/cert.pem"
```

## Certificate Renewal

### When to Renew

Monitor certificate expiration:

```bash
# Check days until expiry
openssl x509 -in cert.pem -noout -enddate

# Check if expired
openssl x509 -in cert.pem -noout -checkend 0

# Check if expires in 30 days
openssl x509 -in cert.pem -noout -checkend 2592000
```

### Renewal Process

1. **Generate new certificate** (same CN, new keys recommended)
2. **Test new certificate** before deploying
3. **Deploy new certificate** to servers
4. **Verify deployment** works
5. **Revoke old certificate** (optional but recommended)
6. **Update CRL** if revoked

```bash
# Renew server certificate
source steps.sh

# Remove old certificate
rm -rf ~/.config/demo-cfssl/hosts/server1/*

# Generate new
step03 "server1.example.com" "*.example.com"

# Optionally revoke old
./crl_mk.sh revoke /backup/old-cert.pem superseded
./crl_mk.sh generate ica
```

## Certificate Validity Best Practices

### Current Standards (October 2025)

| Certificate Type | Current Max | Future Trend                                                   |
| ---------------- | ----------- | -------------------------------------------------------------- |
| TLS/SSL          | 398 days    | 200 days (Mar 2026) → 100 days (Mar 2027) → 47 days (Mar 2029) |
| Email            | No mandate  | Annual renewal recommended                                     |
| Root CA          | 10-20 years | Offline storage                                                |
| Intermediate CA  | 5-10 years  | Regular rotation                                               |

### Recommendations

1. **TLS/SSL Certificates**: Use 47 days to prepare for future requirements
2. **Email Certificates**: Renew annually with new key pairs
3. **Automate renewal**: Set up monitoring and automation
4. **Key rotation**: Generate new keys with each renewal

## Key Management

### Key Protection

```bash
# Set proper permissions (owner read-only)
chmod 600 ~/.config/demo-cfssl/ca-key.pem
chmod 600 ~/.config/demo-cfssl/ica-key.pem
chmod 600 ~/.config/demo-cfssl/hosts/*/key.pem
```

### Key Backup

```bash
# Backup CA keys (critical!)
tar -czf ca-keys-backup-$(date +%Y%m%d).tar.gz \
    ~/.config/demo-cfssl/ca-key.pem \
    ~/.config/demo-cfssl/ica-key.pem

# Store backup securely (encrypted, offline)
gpg -c ca-keys-backup-*.tar.gz
rm ca-keys-backup-*.tar.gz
```

### Key Types

**ECDSA P-384** (default):

- Faster operations
- Smaller certificates
- Equivalent to RSA-7680
- Modern standard

**RSA 4096**:

- Wider compatibility
- Larger keys/certificates
- More CPU intensive
- Traditional choice

## Advanced Topics

### Certificate Transparency

For public certificates:

```bash
# Submit to CT logs (not needed for private CAs)
curl -X POST https://ct.googleapis.com/logs/argon2021/ct/v1/add-chain \
    -H "Content-Type: application/json" \
    -d @cert.json
```

### OCSP Stapling

Include OCSP response in TLS handshake:

```nginx
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /path/to/ca-bundle.pem;
```

### Certificate Pinning

Pin specific certificates or public keys:

```http
Public-Key-Pins: pin-sha256="base64=="; max-age=2592000
```

## Troubleshooting

### Common Issues

**"unable to get local issuer certificate"**

```bash
# Add CA to system trust store (see deployment.md)
# Or specify full chain
openssl verify -CAfile ca-bundle.pem cert.pem
```

**"certificate has expired"**

```bash
# Check expiration
openssl x509 -in cert.pem -noout -dates

# Renew certificate
```

**"subject alternative name missing"**

```bash
# Always include CN in SANs
# Regenerate with proper SANs
```

## Next Steps

- **[Certificate Revocation](revocation.md)** - CRL and OCSP
- **[Production Deployment](deployment.md)** - Deploy certificates
- **[Examples](examples.md)** - Practical scenarios
