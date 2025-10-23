# Troubleshooting Guide

Common issues and solutions for demo-cfssl.

## Certificate Generation Issues

### CFSSL Command Not Found

**Problem**: `bash: cfssl: command not found`

**Solutions**:
```bash
# Option 1: Install CFSSL
wget https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssl_1.6.5_linux_amd64
chmod +x cfssl_*
sudo mv cfssl_* /usr/local/bin/cfssl

# Option 2: Use Docker
# Ensure Docker is running
docker ps

# Scripts should auto-detect and use Docker image
```

### Permission Denied on Key Files

**Problem**: `Permission denied: ca-key.pem`

**Solution**:
```bash
# Fix permissions
chmod 600 ~/.config/demo-cfssl/*-key.pem
chmod 700 ~/.config/demo-cfssl/

# Check ownership
ls -la ~/.config/demo-cfssl/
# If owned by wrong user:
sudo chown -R $USER:$USER ~/.config/demo-cfssl/
```

### Certificate Already Exists

**Problem**: `Certificate already exists, won't overwrite`

**Solutions**:
```bash
# Option 1: Remove existing certificate
rm ~/.config/demo-cfssl/hosts/example.com/*

# Option 2: Use different name
step03 "example-new.com"

# Option 3: Force regenerate in steps.sh (edit script)
```

### JSON Parse Error

**Problem**: `Error parsing JSON configuration`

**Solution**:
```bash
# Validate JSON
jq . ~/.config/demo-cfssl/00_ca.json

# Common issues:
# - Missing comma
# - Extra comma at end
# - Unquoted strings
# - Wrong bracket types

# Fix with jq
jq . broken.json > fixed.json
```

## Certificate Verification Issues

### Unable to Get Local Issuer Certificate

**Problem**: `error 20: unable to get local issuer certificate`

**Solutions**:
```bash
# Solution 1: Specify CA file explicitly
openssl verify -CAfile ~/.config/demo-cfssl/ca.pem \
    ~/.config/demo-cfssl/ica-ca.pem

# Solution 2: Use CA bundle
openssl verify -CAfile ~/.config/demo-cfssl/ca-bundle.pem \
    ~/.config/demo-cfssl/hosts/example.com/cert.pem

# Solution 3: Add CA to system trust store
sudo cp ~/.config/demo-cfssl/ca.pem \
    /usr/local/share/ca-certificates/demo-ca.crt
sudo update-ca-certificates
```

### Certificate Has Expired

**Problem**: `certificate has expired`

**Solutions**:
```bash
# Check expiration date
openssl x509 -in cert.pem -noout -dates

# If expired, regenerate:
source steps.sh
rm -rf ~/.config/demo-cfssl/hosts/example.com/*
step03 "example.com"

# For CA certificates, you'll need to regenerate everything
# Backup first!
```

### Self-Signed Certificate

**Problem**: `self-signed certificate in certificate chain`

**Solutions**:
```bash
# This is expected for custom CAs
# Either:
# 1. Add CA to trust store (see above)
# 2. Or specify CA file:
curl --cacert ~/.config/demo-cfssl/ca-bundle.pem https://example.com

# 3. Or disable verification (NOT for production!):
curl -k https://example.com
```

### Subject Alternative Name Missing

**Problem**: Browser shows "Subject Alternative Name Missing"

**Solution**:
```bash
# Always include CN in SANs
# Check certificate:
openssl x509 -in cert.pem -noout -text | grep -A5 "Subject Alternative Name"

# Regenerate with proper SANs:
step03 "example.com" "example.com" "*.example.com"
#      ^CN           ^SAN1         ^SAN2
```

## OCSP Issues

### OCSP Responder Not Starting

**Problem**: `Error: CA certificate not found`

**Solution**:
```bash
# Ensure certificates exist
ls -la ~/.config/demo-cfssl/ca.pem
ls -la ~/.config/demo-cfssl/ica-ca.pem

# If missing, generate:
./steps.sh

# Check environment variable
echo $DEMO_CFSSL_DIR

# If custom location:
export DEMO_CFSSL_DIR=/path/to/certs
cd ocsp && python main.py
```

### Port Already in Use

**Problem**: `Address already in use: port 8080`

**Solutions**:
```bash
# Solution 1: Find and kill process
lsof -ti:8080 | xargs kill

# Solution 2: Use different port
export OCSP_PORT=9090
cd ocsp && python main.py

# Solution 3: Check what's using the port
lsof -i:8080
netstat -tulpn | grep 8080
```

### OCSP Response Verify Failure

**Problem**: `Response Verify Failure`

**Solutions**:
```bash
# Solution 1: Add -VAfile option
openssl ocsp -issuer ica-ca.pem -cert cert.pem \
    -url http://localhost:8080/ocsp \
    -VAfile ~/.config/demo-cfssl/ica-ca.pem \
    -text

# Solution 2: Check OCSP responder has access to CA keys
ls -la ~/.config/demo-cfssl/ica-key.pem
```

### Certificate Shows Good When Revoked

**Problem**: OCSP shows "good" for revoked certificate

**Solution**:
```bash
# OCSP responder needs restart to reload database
cd ocsp
# Press Ctrl+C
python main.py

# Or if using systemd:
sudo systemctl restart ocsp-responder

# Verify in database:
cat ~/.config/demo-cfssl/crl/ica/database.txt | grep <serial>
```

## CRL Issues

### CRL Has Expired

**Problem**: `CRL has expired`

**Solution**:
```bash
# Regenerate CRL (expires after 30 days)
./crl_mk.sh generate ica

# Check expiry:
./crl_mk.sh info ica

# Set up cron job for auto-regeneration:
# crontab -e
# 0 2 * * 1 /path/to/demo-cfssl/crl_mk.sh generate ica
```

### Certificate Not Found in CRL Database

**Problem**: `Certificate serial number not found in revocation database`

**Solution**:
```bash
# This is not an error - certificate is not revoked

# To verify certificate is issued by your CA:
openssl verify -CAfile ~/.config/demo-cfssl/ca-bundle.pem cert.pem

# Check certificate serial:
openssl x509 -in cert.pem -noout -serial

# Check revoked certificates:
./crl_mk.sh list ica
```

### CRL Verification Failed

**Problem**: `CRL verification failed`

**Solutions**:
```bash
# Verify CRL signature:
openssl crl -in ~/.config/demo-cfssl/ica-crl.pem -noout -text

# Ensure CRL is signed by correct CA:
openssl verify -crl_check \
    -CRLfile ~/.config/demo-cfssl/ica-crl.pem \
    -CAfile ~/.config/demo-cfssl/ca-bundle.pem \
    cert.pem
```

## Web Server Issues

### Nginx: SSL Certificate Not Found

**Problem**: Nginx fails to start with SSL error

**Solutions**:
```bash
# Check file paths in config
nginx -t

# Verify files exist
ls -la /etc/ssl/certs/example.com/
ls -la /etc/ssl/private/example.com/

# Check permissions
sudo chown root:root /etc/ssl/certs/example.com/*.pem
sudo chmod 644 /etc/ssl/certs/example.com/*.pem
sudo chmod 600 /etc/ssl/private/example.com/*.pem
```

### Apache: Unable to Configure Verify Locations

**Problem**: `Unable to configure verify locations for client authentication`

**Solution**:
```bash
# Check CA bundle exists
ls -la /path/to/ca-bundle.pem

# Ensure proper format (PEM)
openssl x509 -in ca-bundle.pem -noout -text

# Check Apache config:
sudo apachectl configtest
```

### HAProxy: SSL Handshake Failure

**Problem**: HAProxy SSL handshake fails

**Solutions**:
```bash
# Check HAProxy cert format (must include key!)
cat cert.pem ica-ca.pem ca.pem key.pem > haproxy.pem

# Or use generated file:
cp ~/.config/demo-cfssl/hosts/example.com/haproxy.pem \
    /etc/haproxy/certs/

# Test HAProxy config:
haproxy -c -f /etc/haproxy/haproxy.cfg

# Check file permissions:
ls -la /etc/haproxy/certs/
sudo chown haproxy:haproxy /etc/haproxy/certs/*.pem
```

## macOS Specific Issues

### stat: illegal option

**Problem**: `stat: illegal option -- printf`

**Solution**:
```bash
# macOS uses BSD stat, need GNU coreutils
brew install coreutils

# Verify installation:
which gstat
which gdate

# Script should auto-detect macOS and use gstat/gdate
```

### Security: Command Not Found

**Problem**: Can't add CA to macOS keychain

**Solution**:
```bash
# Use full path
/usr/bin/security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    ~/.config/demo-cfssl/ca.pem

# Or add via Keychain Access GUI
open ~/.config/demo-cfssl/ca.pem
```

## Docker Issues

### Docker Not Running

**Problem**: `Cannot connect to the Docker daemon`

**Solution**:
```bash
# Start Docker
# macOS/Windows: Open Docker Desktop
# Linux:
sudo systemctl start docker

# Verify:
docker ps
```

### Permission Denied (Docker Socket)

**Problem**: `permission denied while trying to connect to Docker daemon socket`

**Solutions**:
```bash
# Solution 1: Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in

# Solution 2: Use sudo (not recommended)
sudo docker ps

# Verify:
docker ps
```

### Container Cannot Access Certificates

**Problem**: OCSP container can't read certificate files

**Solution**:
```bash
# Check volume mount
docker inspect ocsp-responder | grep Mounts -A10

# Ensure correct path:
docker run -d \
    -v ~/.config/demo-cfssl:/certs:ro \
    -e DEMO_CFSSL_DIR=/certs \
    demo-cfssl-ocsp

# Check permissions:
ls -la ~/.config/demo-cfssl/
```

## Python/OCSP Issues

### ModuleNotFoundError

**Problem**: `ModuleNotFoundError: No module named 'fastapi'`

**Solutions**:
```bash
# Ensure virtual environment is activated
cd ocsp
source .venv/bin/activate  # or: .venv\Scripts\activate on Windows

# Install dependencies
pip install -r requirements.txt

# Verify installation:
pip list | grep fastapi
```

### Import Error: cryptography

**Problem**: `ImportError: cannot import name 'x509' from 'cryptography'`

**Solution**:
```bash
# Update cryptography library
pip install --upgrade cryptography

# Or reinstall:
pip uninstall cryptography
pip install cryptography>=43.0.0
```

## Certificate Import Issues

### Thunderbird Won't Import P12

**Problem**: "This personal certificate can't be installed"

**Solutions**:
```bash
# Verify P12 file:
openssl pkcs12 -info -in email.p12 -noout

# Try with password:
EMAIL_P12_PASSWORD="mypassword" step_email "John Doe" john@example.com

# Check file integrity:
ls -lh ~/.config/demo-cfssl/smime/*/email.p12
```

### Browser Doesn't Trust Certificate

**Problem**: Browser shows "Not Secure" despite adding CA

**Solutions**:
```bash
# Chrome/Edge: Use system trust store
# Already added if you ran update-ca-certificates

# Firefox: Uses own store
# Settings → Privacy & Security → Certificates → Import ca.pem

# Safari: Should use system keychain
# Verify CA is in keychain and trusted for SSL

# Clear browser cache and restart
```

## Performance Issues

### Slow Certificate Generation

**Problem**: Certificate generation takes very long

**Solutions**:
```bash
# Use ECDSA instead of RSA (edit steps.sh):
KEY_ALGO="ecdsa"
KEY_SIZE=384  # Much faster than RSA 4096

# Ensure enough entropy:
# Linux:
cat /proc/sys/kernel/random/entropy_avail
# Should be > 1000

# Install rng-tools if low:
sudo apt-get install rng-tools
```

### OCSP Responder Slow

**Problem**: OCSP responses take > 100ms

**Solutions**:
```bash
# Check database size:
wc -l ~/.config/demo-cfssl/crl/ica/database.txt

# Monitor performance:
time openssl ocsp -issuer ica-ca.pem -cert cert.pem -url http://localhost:8080/ocsp

# For large databases, consider:
# - Multiple OCSP instances
# - Load balancer
# - Response caching
# - Database backend (PostgreSQL)
```

## Debugging Tips

### Enable Verbose Output

```bash
# OpenSSL verbose mode
openssl x509 -in cert.pem -noout -text

# CFSSL debug mode
cfssl gencert -v ...

# OCSP debug
openssl ocsp -issuer ica-ca.pem -cert cert.pem \
    -url http://localhost:8080/ocsp -text -noverify

# Nginx debug
nginx -t -c /etc/nginx/nginx.conf
```

### Check File Formats

```bash
# Verify PEM format
openssl x509 -in cert.pem -noout -text

# Convert DER to PEM
openssl x509 -inform DER -in cert.der -out cert.pem

# Check if file is actually PEM:
head -1 cert.pem  # Should be: -----BEGIN CERTIFICATE-----
```

### Trace Network Issues

```bash
# Check if OCSP port is accessible
nc -zv localhost 8080
telnet localhost 8080

# Check HTTP response
curl -v http://localhost:8080/health

# Check DNS resolution
nslookup ocsp.example.com
dig ocsp.example.com

# Trace route
traceroute ocsp.example.com
```

## Getting More Help

### Log Files

```bash
# OCSP responder logs
docker logs ocsp-responder

# Systemd logs
journalctl -u ocsp-responder -f

# Nginx logs
tail -f /var/log/nginx/error.log

# Apache logs
tail -f /var/log/apache2/error.log
```

### Collect Debug Information

```bash
#!/bin/bash
# collect-debug-info.sh

echo "=== System Information ==="
uname -a
cat /etc/os-release

echo -e "\n=== CFSSL Version ==="
cfssl version || echo "CFSSL not found"

echo -e "\n=== OpenSSL Version ==="
openssl version

echo -e "\n=== Python Version ==="
python3 --version

echo -e "\n=== Certificate Files ==="
ls -laR ~/.config/demo-cfssl/

echo -e "\n=== OCSP Status ==="
curl -s http://localhost:8080/status || echo "OCSP not running"

echo -e "\n=== CRL Info ==="
./crl_mk.sh info ica 2>&1 || echo "CRL command failed"
```

### Community Resources

- [CFSSL GitHub Issues](https://github.com/cloudflare/cfssl/issues)
- [OpenSSL Documentation](https://www.openssl.org/docs/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/ssl)

## Common Error Messages

| Error Message | Solution |
|--------------|----------|
| `certificate verify failed` | Add CA to trust store |
| `No route to host` | Check firewall/network |
| `Connection refused` | Check service is running |
| `Permission denied` | Fix file/directory permissions |
| `command not found` | Install missing software |
| `JSON parse error` | Fix JSON syntax |
| `Key too short` | Increase key size |
| `Invalid certificate purpose` | Check Extended Key Usage |

## Next Steps

- **[Getting Started](getting-started.md)** - Basic setup
- **[Examples](examples.md)** - Practical scenarios
- **[Deployment](deployment.md)** - Production deployment

## Still Having Issues?

1. Check [AGENTS.md](../AGENTS.md) for architectural details
2. Review component-specific READMEs (ocsp/README.md, etc.)
3. Run example scripts to verify basic functionality
4. Compare your setup with working examples
5. Check logs for specific error messages

