# OCSP Responder Quick Start Guide

Get your OCSP responder running in 5 minutes!

## Prerequisites

- Python 3.8 or higher
- Certificates generated from parent demo-cfssl project
- OpenSSL command-line tools

## Installation

### Option 1: Using pip (Fastest)

```bash
cd ocsp
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### Option 2: Using uv (Recommended for development)

```bash
cd ocsp
uv venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
uv pip install -r requirements.txt
```

### Option 3: Using Docker

```bash
cd ocsp
docker build -t demo-cfssl-ocsp .
```

## Running the OCSP Responder

### Local Development

```bash
# Make sure you're in the ocsp directory and venv is activated
python main.py
```

The responder will start on `http://0.0.0.0:8080`

### Using Docker

```bash
docker run -d \
    --name ocsp-responder \
    -p 8080:8080 \
    -v ~/.config/demo-cfssl:/certs:ro \
    -e DEMO_CFSSL_DIR=/certs \
    demo-cfssl-ocsp
```

### Using Docker Compose

```bash
docker-compose up -d
```

## Testing

### Quick Test

```bash
# Check if responder is running
curl http://localhost:8080/health

# Check status
curl http://localhost:8080/status | python -m json.tool
```

### Test OCSP Validation

```bash
# Test with a certificate
openssl ocsp \
    -issuer ~/.config/demo-cfssl/ica-ca.pem \
    -cert ~/.config/demo-cfssl/hosts/localhost/cert.pem \
    -url http://localhost:8080/ocsp \
    -text
```

### Run Test Suite

```bash
./test_ocsp.sh
```

### Complete Workflow Demo

```bash
./example_workflow.sh
```

## Creating Certificates with OCSP URLs

### Quick Method

Use the helper script:

```bash
# This will interactively configure OCSP and CRL URLs
./add_ocsp_to_profiles.sh
```

### Manual Method

Create a certificate with embedded OCSP and CRL URLs:

```bash
BD="$HOME/.config/demo-cfssl"
OCSP_URL="http://localhost:8080/ocsp"
CRL_URL="http://localhost:8080/crl/ica.crl"

# Create OpenSSL config with extensions
cat > /tmp/cert-extensions.cnf << EOF
[v3_server]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
authorityInfoAccess = OCSP;URI:${OCSP_URL}
crlDistributionPoints = URI:${CRL_URL}
subjectAltName = DNS:test.example.com
EOF

# Generate key
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
    -out /tmp/test-key.pem

# Generate CSR
openssl req -new -key /tmp/test-key.pem -out /tmp/test.csr \
    -subj "/C=CZ/ST=Heart of Europe/L=Prague/O=At Home Company/OU=Security Dept./CN=test.example.com"

# Sign with ICA
openssl x509 -req -in /tmp/test.csr \
    -CA "$BD/ica-ca.pem" \
    -CAkey "$BD/ica-key.pem" \
    -CAcreateserial \
    -out /tmp/test-cert.pem \
    -days 47 \
    -sha384 \
    -extfile /tmp/cert-extensions.cnf \
    -extensions v3_server

# Verify OCSP URL is embedded
openssl x509 -in /tmp/test-cert.pem -noout -text | grep -A3 "Authority Information Access"

# Test OCSP validation
openssl ocsp \
    -issuer "$BD/ica-ca.pem" \
    -cert /tmp/test-cert.pem \
    -url http://localhost:8080/ocsp \
    -text
```

## Common Tasks

### Check OCSP Responder Status

```bash
curl http://localhost:8080/status
```

Example response:

```json
{
  "ca_loaded": true,
  "ica_loaded": true,
  "revoked_certificates": {
    "ca": 0,
    "ica": 2,
    "total": 2
  },
  "timestamp": "2025-10-23T12:00:00.000000+00:00"
}
```

### Revoke a Certificate and Update OCSP

```bash
# 1. Revoke certificate
cd ..
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/localhost/cert.pem keyCompromise

# 2. Generate updated CRL
./crl_mk.sh generate ica

# 3. Restart OCSP responder to reload revocation database
cd ocsp
# Press Ctrl+C to stop, then restart:
python main.py
```

### View Logs

```bash
# Local development - logs to stdout
python main.py

# Docker
docker logs -f ocsp-responder

# Docker Compose
docker-compose logs -f
```

## Troubleshooting

### "CA certificate not found" error

**Problem:** OCSP responder can't find certificates

**Solution:**

```bash
# Check certificate location
ls -la ~/.config/demo-cfssl/

# Set custom location
export DEMO_CFSSL_DIR=/path/to/your/certs
python main.py
```

### "Port 8080 already in use"

**Problem:** Another service is using port 8080

**Solution:**

```bash
# Use different port
export OCSP_PORT=9090
python main.py

# Or stop the conflicting service
lsof -ti:8080 | xargs kill
```

### "OCSP verification failed"

**Problem:** OpenSSL can't verify OCSP response

**Solution:**

```bash
# Add -VAfile option with issuer certificate
openssl ocsp \
    -issuer ~/.config/demo-cfssl/ica-ca.pem \
    -cert ~/.config/demo-cfssl/hosts/localhost/cert.pem \
    -url http://localhost:8080/ocsp \
    -VAfile ~/.config/demo-cfssl/ica-ca.pem \
    -text
```

### Certificate shows as "good" when it's revoked

**Problem:** OCSP responder hasn't reloaded revocation database

**Solution:**

```bash
# Restart the OCSP responder
# Press Ctrl+C and run again:
python main.py
```

For production, implement auto-reload or database watching.

## Next Steps

1. **Production Deployment** - See [README.md](README.md#production-deployment) for systemd service, nginx reverse proxy, and HTTPS setup

2. **High Availability** - Deploy multiple OCSP responder instances behind a load balancer

3. **Monitoring** - Set up health checks and alerting

   ```bash
   # Simple monitoring script
   while true; do
       if curl -s http://localhost:8080/health | grep -q "healthy"; then
           echo "$(date): ✓ OCSP responder healthy"
       else
           echo "$(date): ✗ OCSP responder unhealthy"
       fi
       sleep 60
   done
   ```

4. **Certificate Generation** - Update your certificate generation process to include OCSP and CRL URLs (see main [README.md](../README.md#including-ocsp-and-crl-urls-in-certificates))

5. **Web Server Integration** - Enable OCSP stapling in your web servers:
   - [Nginx OCSP Stapling](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_stapling)
   - [Apache OCSP Stapling](https://httpd.apache.org/docs/trunk/ssl/ssl_howto.html#ocspstapling)

## Resources

- [Main README](../README.md) - Certificate generation and management
- [OCSP README](README.md) - Detailed documentation
- [RFC 6960](https://tools.ietf.org/html/rfc6960) - OCSP Specification
- [Example Workflow](example_workflow.sh) - Complete demonstration script
- [Test Suite](test_ocsp.sh) - Automated testing

## Getting Help

If you encounter issues:

1. Check the logs for error messages
2. Verify certificates exist in `~/.config/demo-cfssl/`
3. Ensure the OCSP responder has read access to certificates
4. Test with `curl http://localhost:8080/health`
5. Review the [troubleshooting section](#troubleshooting)

Happy OCSP'ing! 🔐
