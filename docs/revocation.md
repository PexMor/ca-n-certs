# Certificate Revocation

This guide covers both Certificate Revocation Lists (CRL) and Online Certificate Status Protocol (OCSP) for managing revoked certificates.

## Overview

**Why Revoke Certificates?**

- Private key compromised
- Certificate information incorrect
- Service decommissioned
- Employee departed
- Certificate superseded

**Two Methods**:

1. **CRL** - Certificate Revocation List (periodic download)
2. **OCSP** - Online Certificate Status Protocol (real-time query)

## Certificate Revocation Lists (CRL)

### What is CRL?

CRLs are signed lists of revoked certificates published periodically by the CA.

**Advantages**:

- Works offline (after download)
- Standardized format
- Easy to verify

**Disadvantages**:

- Can be large (many revoked certs)
- Periodic updates (not real-time)
- Bandwidth intensive

### CRL Management with crl_mk.sh

The `crl_mk.sh` script provides complete CRL management.

#### Revoke a Certificate

```bash
# Syntax
./crl_mk.sh revoke /path/to/certificate.pem [REASON]

# Example
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/server1/cert.pem keyCompromise
```

**Revocation Reasons**:

- `unspecified` - Default (no specific reason)
- `keyCompromise` - Private key was compromised
- `CACompromise` - CA key was compromised
- `affiliationChanged` - Certificate holder changed affiliation
- `superseded` - Replaced with new certificate
- `cessationOfOperation` - Service no longer exists
- `certificateHold` - Temporarily suspended (reversible)

#### Generate CRL

```bash
# Generate CRL for Intermediate CA
./crl_mk.sh generate ica

# Generate CRL for Root CA
./crl_mk.sh generate ca

# Generates both PEM and DER formats:
# - ~/.config/demo-cfssl/ica-crl.pem
# - ~/.config/demo-cfssl/ica-crl.der
```

**CRL Validity**: 30 days (regenerate before expiration)

#### List Revoked Certificates

```bash
# List all revoked certificates
./crl_mk.sh list ica

# Example output:
# Serial: 2a3b4c5d
# CN: server1.example.com
# Revocation Date: 2025-10-23 12:00:00
# Reason: keyCompromise
```

#### View CRL Information

```bash
# View CRL details
./crl_mk.sh info ica

# Shows:
# - Issuer
# - Last Update
# - Next Update
# - Revoked certificate count
```

#### Verify Certificate Against CRL

```bash
# Quick check
./crl_mk.sh verify ~/.config/demo-cfssl/hosts/server1/cert.pem ica

# Detailed check
./crl_check.sh ~/.config/demo-cfssl/hosts/server1/cert.pem

# Verbose output
./crl_check.sh cert.pem --verbose

# JSON output (for automation)
./crl_check.sh cert.pem --json
```

#### Batch Certificate Checking

```bash
# Create file list
cat > certs-to-check.txt << EOF
~/.config/demo-cfssl/hosts/server1/cert.pem
~/.config/demo-cfssl/hosts/server2/cert.pem
~/.config/demo-cfssl/smime/john_doe/cert.pem
EOF

# Batch check
./crl_check.sh --batch certs-to-check.txt
```

### CRL Distribution

#### HTTP Distribution

Serve CRLs via HTTP for client access:

```bash
# Copy CRL to web server
cp ~/.config/demo-cfssl/ica-crl.der /var/www/html/crl/ica.crl

# Nginx configuration
server {
    listen 80;
    server_name crl.example.com;

    location /crl/ {
        alias /var/www/html/crl/;
        add_header Content-Type application/pkix-crl;
        add_header Cache-Control "max-age=3600";
    }
}
```

#### Automated Updates

```bash
# Cron job to regenerate CRL weekly
# /etc/cron.d/crl-update
0 2 * * 1 /path/to/demo-cfssl/crl_mk.sh generate ica
5 2 * * 1 cp ~/.config/demo-cfssl/ica-crl.der /var/www/html/crl/ica.crl
```

### CRL Files and Database

**Files**:

```
~/.config/demo-cfssl/
├── ica-crl.pem          # CRL in PEM format
├── ica-crl.der          # CRL in DER format
├── ca-crl.pem           # Root CA CRL (if needed)
├── ca-crl.der
└── crl/                 # Revocation database
    ├── ica/
    │   ├── database.txt # Revocation records
    │   └── serial.txt   # Next serial number
    └── ca/
        ├── database.txt
        └── serial.txt
```

**Database Format** (`database.txt`):

```
R|deadbeef|2025-10-23T12:00:00|keyCompromise|server1.example.com
R|cafe1234|2025-10-22T10:30:00|superseded|server2.example.com
```

## Online Certificate Status Protocol (OCSP)

### What is OCSP?

OCSP provides real-time certificate status checking via HTTP queries.

**Advantages**:

- Real-time status
- Reduced bandwidth (query specific certs)
- No large downloads
- Faster for single checks

**Disadvantages**:

- Requires network connection
- Privacy concerns (CA knows what you're checking)
- Availability dependency

### OCSP Responder

The `ocsp/` directory contains a complete FastAPI-based OCSP responder.

#### Start OCSP Responder

```bash
# Quick start
cd ocsp
./start.sh

# Manual start
cd ocsp
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

**Default**: Runs on `http://0.0.0.0:8080`

#### Configuration

```bash
# Custom port
export OCSP_PORT=9090

# Custom certificate directory
export DEMO_CFSSL_DIR=/path/to/certs

# Custom host
export OCSP_HOST=0.0.0.0

python main.py
```

#### OCSP API Endpoints

| Endpoint  | Method | Purpose                    |
| --------- | ------ | -------------------------- |
| `/`       | GET    | Service information        |
| `/health` | GET    | Health check               |
| `/status` | GET    | Statistics                 |
| `/ocsp`   | POST   | OCSP validation (RFC 6960) |

**Health Check**:

```bash
curl http://localhost:8080/health

# Response:
# {"status": "healthy", "timestamp": "2025-10-23T12:00:00Z"}
```

**Status**:

```bash
curl http://localhost:8080/status

# Response:
# {
#   "ca_loaded": true,
#   "ica_loaded": true,
#   "revoked_certificates": {
#     "ca": 0,
#     "ica": 2,
#     "total": 2
#   }
# }
```

#### Test OCSP Validation

```bash
# Basic test
openssl ocsp \
    -issuer ~/.config/demo-cfssl/ica-ca.pem \
    -cert ~/.config/demo-cfssl/hosts/server1/cert.pem \
    -url http://localhost:8080/ocsp \
    -text

# With verification
openssl ocsp \
    -issuer ~/.config/demo-cfssl/ica-ca.pem \
    -cert ~/.config/demo-cfssl/hosts/server1/cert.pem \
    -url http://localhost:8080/ocsp \
    -VAfile ~/.config/demo-cfssl/ica-ca.pem \
    -text

# Expected responses:
# - Good: "cert.pem: good"
# - Revoked: "cert.pem: revoked"
```

#### OCSP Workflow

1. **Revoke certificate**:

   ```bash
   ./crl_mk.sh revoke path/to/cert.pem keyCompromise
   ./crl_mk.sh generate ica
   ```

2. **Restart OCSP responder** (to reload database):

   ```bash
   cd ocsp
   # Press Ctrl+C, then:
   python main.py
   ```

3. **Test revocation**:
   ```bash
   openssl ocsp -issuer ica-ca.pem -cert cert.pem \
       -url http://localhost:8080/ocsp -text
   # Should show: revoked
   ```

### Embedding OCSP/CRL URLs in Certificates

To enable automatic OCSP validation, embed URLs in certificates.

#### Create Extensions Configuration

```bash
BD="$HOME/.config/demo-cfssl"
OCSP_URL="http://ocsp.example.com/ocsp"
CRL_URL="http://crl.example.com/ica.crl"

cat > "$BD/cert-extensions.cnf" << EOF
[v3_server]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
authorityInfoAccess = OCSP;URI:${OCSP_URL}
crlDistributionPoints = URI:${CRL_URL}

[v3_email]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = emailProtection
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
authorityInfoAccess = OCSP;URI:${OCSP_URL}
crlDistributionPoints = URI:${CRL_URL}
EOF
```

#### Generate Certificate with URLs

```bash
# Generate key
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
    -out /tmp/server-key.pem

# Generate CSR
openssl req -new -key /tmp/server-key.pem \
    -out /tmp/server.csr \
    -subj "/C=CZ/ST=Heart of Europe/L=Prague/O=At Home Company/OU=Security/CN=server.example.com"

# Sign with extensions
openssl x509 -req -in /tmp/server.csr \
    -CA "$BD/ica-ca.pem" -CAkey "$BD/ica-key.pem" \
    -CAcreateserial -out /tmp/server-cert.pem \
    -days 47 -sha384 \
    -extfile "$BD/cert-extensions.cnf" \
    -extensions v3_server
```

#### Verify URLs Are Embedded

```bash
# Check OCSP URL
openssl x509 -in cert.pem -noout -text | grep -A3 "Authority Information Access"

# Check CRL URL
openssl x509 -in cert.pem -noout -text | grep -A3 "CRL Distribution Points"
```

### OCSP Docker Deployment

```bash
cd ocsp

# Build image
docker build -t demo-cfssl-ocsp .

# Run container
docker run -d --name ocsp-responder \
    -p 8080:8080 \
    -v ~/.config/demo-cfssl:/certs:ro \
    -e DEMO_CFSSL_DIR=/certs \
    demo-cfssl-ocsp

# Check logs
docker logs -f ocsp-responder

# Stop/Start
docker stop ocsp-responder
docker start ocsp-responder
```

**Docker Compose**:

```bash
cd ocsp
docker-compose up -d
docker-compose logs -f
docker-compose down
```

## CRL vs OCSP Comparison

| Feature         | CRL                       | OCSP                         |
| --------------- | ------------------------- | ---------------------------- |
| **Real-time**   | No (periodic updates)     | Yes                          |
| **Bandwidth**   | High (download full list) | Low (single query)           |
| **Offline**     | Yes (after download)      | No                           |
| **Privacy**     | Better (download once)    | Lower (CA sees queries)      |
| **Complexity**  | Simple                    | More complex                 |
| **Caching**     | File-based                | Time-based                   |
| **Scalability** | Decreases with size       | Better for large deployments |

## Web Server Integration

### Nginx with CRL

```nginx
server {
    listen 443 ssl;
    ssl_certificate /path/to/bundle-2.pem;
    ssl_certificate_key /path/to/key.pem;

    # Client certificate verification
    ssl_client_certificate /path/to/ca-bundle.pem;
    ssl_crl /path/to/ica-crl.pem;
    ssl_verify_client on;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /path/to/ca-bundle.pem;
}
```

### Apache with CRL

```apache
<VirtualHost *:443>
    SSLEngine on
    SSLCertificateFile /path/to/cert.pem
    SSLCertificateKeyFile /path/to/key.pem
    SSLCertificateChainFile /path/to/ca-bundle.pem

    # CRL checking
    SSLCARevocationFile /path/to/ica-crl.pem
    SSLVerifyClient require

    # OCSP Stapling
    SSLUseStapling on
    SSLStaplingCache "shmcb:logs/ssl_stapling(32768)"
</VirtualHost>
```

### HAProxy with CRL

```haproxy
frontend https_front
    bind *:443 ssl crt /path/to/haproxy.pem \
        ca-file /path/to/ca-bundle.pem \
        crl-file /path/to/ica-crl.pem \
        verify required
```

## Best Practices

### CRL Best Practices

1. **Regular Regeneration**: Automate CRL generation (weekly recommended)
2. **Monitor Expiration**: Alert before CRL expires
3. **Distribution**: Use CDN for high availability
4. **Backup**: Keep database backups
5. **Audit**: Log all revocations

### OCSP Best Practices

1. **High Availability**: Run multiple instances
2. **Load Balancing**: Distribute queries
3. **Monitoring**: Track response times
4. **Auto-reload**: Implement database watching
5. **Caching**: Cache responses with appropriate TTL
6. **Rate Limiting**: Prevent abuse

### Combined Approach

Use both CRL and OCSP for defense in depth:

```bash
# Generate CRL for offline/backup
./crl_mk.sh generate ica

# Run OCSP for real-time
cd ocsp && ./start.sh

# Embed both URLs in certificates
# Clients will try OCSP first, fall back to CRL
```

## Troubleshooting

### CRL Issues

**"CRL has expired"**:

```bash
./crl_mk.sh generate ica  # Regenerate
```

**"Certificate not found in CRL database"**:

```bash
./crl_mk.sh list ica  # Check revoked certs
```

**"Permission denied"**:

```bash
chmod +x crl_mk.sh
chmod 644 ~/.config/demo-cfssl/crl/*/database.txt
```

### OCSP Issues

**"Connection refused"**:

```bash
# Check if running
curl http://localhost:8080/health

# Start if not running
cd ocsp && ./start.sh
```

**"OCSP response verify failure"**:

```bash
# Use -VAfile option
openssl ocsp -issuer ica-ca.pem -cert cert.pem \
    -url http://localhost:8080/ocsp \
    -VAfile ica-ca.pem
```

**"Certificate shows 'good' when revoked"**:

```bash
# Restart OCSP responder to reload database
cd ocsp
# Ctrl+C, then:
python main.py
```

## Next Steps

- **[Production Deployment](deployment.md)** - Deploy to production
- **[Examples](examples.md)** - Practical revocation scenarios
- **[Troubleshooting](troubleshooting.md)** - Common issues

## References

- [RFC 5280](https://tools.ietf.org/html/rfc5280) - CRL Specification
- [RFC 6960](https://tools.ietf.org/html/rfc6960) - OCSP Specification
- [OCSP README](../ocsp/README.md) - Detailed OCSP documentation
