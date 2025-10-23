# Examples & Workflows

Practical examples and common scenarios for using demo-cfssl.

## Complete Workflow Examples

### 1. Basic Certificate Setup

Complete workflow from setup to deployment.

```bash
# 1. Generate CA infrastructure
./steps.sh

# 2. Verify certificates
openssl verify -CAfile ~/.config/demo-cfssl/ca.pem \
    ~/.config/demo-cfssl/ica-ca.pem

# 3. Generate additional host certificate
source steps.sh
step03 "web.example.com" "*.example.com"

# 4. Copy to web server
sudo cp ~/.config/demo-cfssl/hosts/web.example.com/bundle-2.pem \
    /etc/ssl/certs/web.example.com.pem
sudo cp ~/.config/demo-cfssl/hosts/web.example.com/key.pem \
    /etc/ssl/private/web.example.com.key

# 5. Configure web server (see deployment.md)

# 6. Add CA to trust store
sudo cp ~/.config/demo-cfssl/ca.pem \
    /usr/local/share/ca-certificates/demo-ca.crt
sudo update-ca-certificates

# 7. Test
curl https://web.example.com
```

### 2. Email Certificate Workflow

Complete S/MIME certificate setup.

```bash
# 1. Generate email certificate
source steps.sh
step_email_openssl "John Doe" john.doe@example.com john@company.com

# 2. Locate PKCS#12 file
P12_FILE=~/.config/demo-cfssl/smime-openssl/john_doe/email.p12

# 3. Import to Thunderbird
# Settings → Privacy & Security → Certificates → Manage Certificates
# Your Certificates → Import → Select email.p12

# 4. Test signing
# Compose email → Security → Digitally Sign This Message

# 5. Test encryption
# (Recipient must share their public cert first)
# Compose email → Security → Encrypt This Message
```

### 3. OCSP Complete Workflow

Setting up OCSP validation end-to-end.

```bash
# 1. Start OCSP responder
cd ocsp
./start.sh
# Keep this running in separate terminal

# 2. Generate certificate with OCSP URL
cd ..
source steps.sh

# Configure OCSP URL
export OCSP_URL="http://localhost:8080/ocsp"
export CRL_URL="http://localhost:8080/crl/ica.crl"

# Generate certificate with extensions
mkdir -p ~/.config/demo-cfssl/hosts/ocsp-test
OCSP_CONFIG=~/.config/demo-cfssl/hosts/ocsp-test/openssl.cnf

cat > "$OCSP_CONFIG" << 'EOF'
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
CN = ocsp-test.example.com

[v3_req]
subjectAltName = DNS:ocsp-test.example.com

[v3_ca]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
authorityInfoAccess = OCSP;URI:http://localhost:8080/ocsp
crlDistributionPoints = URI:http://localhost:8080/crl/ica.crl
subjectAltName = DNS:ocsp-test.example.com
EOF

# Generate key and certificate
BD=~/.config/demo-cfssl
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
    -out "$BD/hosts/ocsp-test/key.pem"

openssl req -new -key "$BD/hosts/ocsp-test/key.pem" \
    -out "$BD/hosts/ocsp-test/cert.csr" -config "$OCSP_CONFIG"

openssl x509 -req -in "$BD/hosts/ocsp-test/cert.csr" \
    -CA "$BD/ica-ca.pem" -CAkey "$BD/ica-key.pem" \
    -CAcreateserial -out "$BD/hosts/ocsp-test/cert.pem" \
    -days 47 -sha384 -extfile "$OCSP_CONFIG" -extensions v3_ca

# 3. Verify OCSP URL is embedded
openssl x509 -in "$BD/hosts/ocsp-test/cert.pem" -noout -text | \
    grep -A3 "Authority Information Access"

# 4. Test OCSP validation (should be GOOD)
openssl ocsp -issuer "$BD/ica-ca.pem" \
    -cert "$BD/hosts/ocsp-test/cert.pem" \
    -url http://localhost:8080/ocsp -text

# 5. Revoke certificate
./crl_mk.sh revoke "$BD/hosts/ocsp-test/cert.pem" keyCompromise
./crl_mk.sh generate ica

# 6. Restart OCSP responder (to reload database)
# Ctrl+C in OCSP terminal, then:
cd ocsp && ./start.sh

# 7. Test again (should be REVOKED)
openssl ocsp -issuer "$BD/ica-ca.pem" \
    -cert "$BD/hosts/ocsp-test/cert.pem" \
    -url http://localhost:8080/ocsp -text
```

## Common Scenarios

### Scenario 1: Server Compromise

Your server was compromised and you need to revoke its certificate.

```bash
# 1. Revoke immediately
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/compromised-server/cert.pem keyCompromise

# 2. Update CRL
./crl_mk.sh generate ica

# 3. Distribute updated CRL
cp ~/.config/demo-cfssl/ica-crl.der /var/www/crl/ica.crl

# 4. Restart OCSP responder (if running)
systemctl restart ocsp-responder

# 5. Verify revocation
./crl_check.sh ~/.config/demo-cfssl/hosts/compromised-server/cert.pem
# Should show: REVOKED

# 6. Generate new certificate
source steps.sh
step03 "compromised-server" "*.example.com"

# 7. Deploy new certificate
# (Copy files to server and reload web server)
```

### Scenario 2: Certificate Renewal

Renew an expiring certificate without service interruption.

```bash
# 1. Check current certificate expiration
openssl x509 -in ~/.config/demo-cfssl/hosts/web-server/cert.pem \
    -noout -dates

# 2. Generate new certificate (before old one expires)
source steps.sh

# Remove old files
rm -rf ~/.config/demo-cfssl/hosts/web-server/*

# Generate new
step03 "web-server.example.com" "*.example.com"

# 3. Test new certificate locally
openssl verify -CAfile ~/.config/demo-cfssl/ca-bundle.pem \
    ~/.config/demo-cfssl/hosts/web-server/cert.pem

# 4. Deploy to staging first
scp ~/.config/demo-cfssl/hosts/web-server/bundle-2.pem \
    staging:/tmp/web-server.pem
scp ~/.config/demo-cfssl/hosts/web-server/key.pem \
    staging:/tmp/web-server.key

# 5. Test on staging
ssh staging 'sudo cp /tmp/web-server.* /etc/ssl/ && sudo systemctl reload nginx'
curl https://staging.example.com

# 6. Deploy to production during maintenance window
scp ~/.config/demo-cfssl/hosts/web-server/bundle-2.pem \
    prod:/tmp/web-server.pem
scp ~/.config/demo-cfssl/hosts/web-server/key.pem \
    prod:/tmp/web-server.key

ssh prod 'sudo cp /tmp/web-server.* /etc/ssl/ && sudo systemctl reload nginx'

# 7. Verify production
curl https://web-server.example.com

# 8. Optionally revoke old certificate
./crl_mk.sh revoke /backup/old-web-server-cert.pem superseded
./crl_mk.sh generate ica
```

### Scenario 3: Employee Departure

Revoke employee's email and client certificates.

```bash
# 1. List employee's certificates
find ~/.config/demo-cfssl/smime* -name "cert.pem" | \
    xargs -I {} sh -c 'openssl x509 -in {} -noout -subject -enddate && echo "File: {}" && echo ""'

# 2. Revoke email certificate
./crl_mk.sh revoke ~/.config/demo-cfssl/smime-openssl/john_doe/cert.pem \
    affiliationChanged

# 3. Revoke any client certificates
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/john-laptop/cert.pem \
    affiliationChanged

# 4. Update CRL
./crl_mk.sh generate ica

# 5. Verify revocations
./crl_mk.sh list ica

# 6. Notify services
echo "Revoked certificates for John Doe" | \
    mail -s "Certificate Revocation Notice" it-team@example.com

# 7. Archive employee's certificates
mkdir -p /archive/former-employees/john_doe
cp -r ~/.config/demo-cfssl/smime-openssl/john_doe \
    /archive/former-employees/
rm -rf ~/.config/demo-cfssl/smime-openssl/john_doe
```

### Scenario 4: Multiple Environment Setup

Set up certificates for dev, staging, and production.

```bash
source steps.sh

# Development environment
step03 "dev.example.com" "*.dev.example.com"

# Staging environment
step03 "staging.example.com" "*.staging.example.com"

# Production environment
step03 "prod.example.com" "*.prod.example.com" "example.com"

# List all certificates
find ~/.config/demo-cfssl/hosts -name "cert.pem" | \
    xargs -I {} sh -c 'echo "=== {} ===" && openssl x509 -in {} -noout -subject'

# Create deployment package for each environment
for env in dev staging prod; do
    tar -czf "${env}-certs.tar.gz" \
        ~/.config/demo-cfssl/hosts/${env}.example.com/
done

# Deploy to environments
scp dev-certs.tar.gz dev-server:/tmp/
scp staging-certs.tar.gz staging-server:/tmp/
scp prod-certs.tar.gz prod-server:/tmp/
```

### Scenario 5: Client Certificate Authentication

Set up mutual TLS (mTLS) for API authentication.

```bash
# 1. Generate client certificate
source steps.sh
step03 "api-client-1" "client1.internal"

# 2. Configure server (Nginx example)
cat > /etc/nginx/conf.d/api-mtls.conf << 'EOF'
server {
    listen 443 ssl;
    server_name api.example.com;
    
    ssl_certificate /etc/ssl/certs/api.example.com/bundle-2.pem;
    ssl_certificate_key /etc/ssl/private/api.example.com/key.pem;
    
    # Client certificate verification
    ssl_client_certificate /etc/ssl/certs/ca-bundle.pem;
    ssl_crl /etc/ssl/certs/ica-crl.pem;
    ssl_verify_client on;
    ssl_verify_depth 2;
    
    location /api {
        # Pass client certificate details to backend
        proxy_set_header X-SSL-Client-Cert $ssl_client_cert;
        proxy_set_header X-SSL-Client-DN $ssl_client_s_dn;
        proxy_set_header X-SSL-Client-Verify $ssl_client_verify;
        proxy_pass http://backend;
    }
}
EOF

# 3. Test with curl
curl --cert ~/.config/demo-cfssl/hosts/api-client-1/cert.pem \
     --key ~/.config/demo-cfssl/hosts/api-client-1/key.pem \
     --cacert ~/.config/demo-cfssl/ca-bundle.pem \
     https://api.example.com/api/test

# 4. Python client example
cat > api_client.py << 'EOF'
import requests

response = requests.get(
    'https://api.example.com/api/test',
    cert=('/path/to/cert.pem', '/path/to/key.pem'),
    verify='/path/to/ca-bundle.pem'
)
print(response.text)
EOF
```

### Scenario 6: Document Signing Workflow

Sign documents with timestamps.

```bash
# 1. Build complete CA bundle (one-time)
./build_ca_bundle.sh

# 2. Generate email certificate (if not done)
source steps.sh
step_email_openssl "Document Signer" signer@example.com

# 3. Sign a document
./tsa_sign.sh --p12 ~/.config/demo-cfssl/smime-openssl/document_signer/email.p12 \
    important-contract.pdf

# This creates:
# - important-contract.pdf.sign_tsa (signature)
# - important-contract.pdf.sign_tsa.tsr (timestamp)

# 4. Verify signature
./tsa_verify.sh important-contract.pdf --verify-cert

# 5. Sign multiple documents
for doc in contracts/*.pdf; do
    ./tsa_sign.sh --p12 ~/.config/demo-cfssl/smime-openssl/document_signer/email.p12 "$doc"
done

# 6. Verify all
for doc in contracts/*.pdf; do
    echo "Verifying: $doc"
    ./tsa_verify.sh "$doc"
done
```

### Scenario 7: Wildcard Certificate for Subdomain

Create wildcard certificate for all subdomains.

```bash
source steps.sh

# Generate wildcard certificate
step03 "*.example.com" "example.com"

# This certificate is valid for:
# - api.example.com
# - web.example.com
# - mail.example.com
# - etc.

# BUT NOT valid for:
# - example.com (add as separate SAN)
# - sub.api.example.com (wildcards only cover one level)

# Deploy to multiple services
cp ~/.config/demo-cfssl/hosts/*.example.com/bundle-2.pem \
    /etc/ssl/certs/wildcard.example.com.pem

# Use in all subdomains
```

### Scenario 8: HAProxy with SNI

Configure HAProxy with Server Name Indication for multiple domains.

```bash
# 1. Generate certificates for multiple domains
source steps.sh
step03 "site1.example.com"
step03 "site2.example.com"
step03 "site3.example.com"

# 2. Create HAProxy bundle for each
BD=~/.config/demo-cfssl
for site in site1 site2 site3; do
    cat "$BD/hosts/${site}.example.com/bundle-3.pem" \
        "$BD/hosts/${site}.example.com/key.pem" \
        > "/etc/haproxy/certs/${site}.example.com.pem"
done

# 3. Configure HAProxy
cat > /etc/haproxy/haproxy.cfg << 'EOF'
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/ # Loads all .pem files
    
    # SNI-based routing
    acl site1 ssl_fc_sni site1.example.com
    acl site2 ssl_fc_sni site2.example.com
    acl site3 ssl_fc_sni site3.example.com
    
    use_backend site1_backend if site1
    use_backend site2_backend if site2
    use_backend site3_backend if site3

backend site1_backend
    server site1 192.168.1.10:80

backend site2_backend
    server site2 192.168.1.11:80

backend site3_backend
    server site3 192.168.1.12:80
EOF

# 4. Test
curl -v https://site1.example.com
curl -v https://site2.example.com
curl -v https://site3.example.com
```

## Testing Scenarios

### Test Certificate Chain

```bash
# Verify complete chain
openssl verify -CAfile ~/.config/demo-cfssl/ca.pem \
    -untrusted ~/.config/demo-cfssl/ica-ca.pem \
    ~/.config/demo-cfssl/hosts/server/cert.pem

# Should output: OK
```

### Test TLS Connection

```bash
# Test with openssl s_client
openssl s_client -connect example.com:443 \
    -CAfile ~/.config/demo-cfssl/ca-bundle.pem \
    -showcerts

# Test with specific protocol
openssl s_client -connect example.com:443 -tls1_3

# Show certificate details
openssl s_client -connect example.com:443 2>/dev/null | \
    openssl x509 -noout -text
```

### Load Testing OCSP

```bash
# Simple load test
for i in {1..100}; do
    openssl ocsp -issuer ~/.config/demo-cfssl/ica-ca.pem \
        -cert ~/.config/demo-cfssl/hosts/localhost/cert.pem \
        -url http://localhost:8080/ocsp &
done
wait

# Check response times
time openssl ocsp -issuer ~/.config/demo-cfssl/ica-ca.pem \
    -cert ~/.config/demo-cfssl/hosts/localhost/cert.pem \
    -url http://localhost:8080/ocsp
```

## Automation Examples

### Automated Certificate Monitoring

```bash
#!/bin/bash
# check-expiry.sh - Monitor certificate expiration

BD="$HOME/.config/demo-cfssl"
WARN_DAYS=30
CRIT_DAYS=7

find "$BD/hosts" -name "cert.pem" | while read cert; do
    HOSTNAME=$(openssl x509 -in "$cert" -noout -subject | sed 's/.*CN = //')
    
    if ! openssl x509 -in "$cert" -noout -checkend $((WARN_DAYS * 86400)); then
        if ! openssl x509 -in "$cert" -noout -checkend $((CRIT_DAYS * 86400)); then
            echo "CRITICAL: $HOSTNAME expires in < $CRIT_DAYS days"
        else
            echo "WARNING: $HOSTNAME expires in < $WARN_DAYS days"
        fi
    fi
done
```

### Automated CRL Updates

```bash
#!/bin/bash
# update-crl.sh - Regenerate and distribute CRL

# Regenerate CRL
/path/to/demo-cfssl/crl_mk.sh generate ica

# Copy to web servers
for server in web1 web2 web3; do
    scp ~/.config/demo-cfssl/ica-crl.der \
        ${server}:/var/www/crl/ica.crl
done

# Notify monitoring
curl -X POST https://monitoring.example.com/api/crl-updated
```

## Next Steps

- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions
- **[Deployment](deployment.md)** - Production deployment guide
- **[Certificate Management](certificate-management.md)** - Certificate operations

