# Production Deployment

This guide covers deploying demo-cfssl certificates and infrastructure to production environments.

## Adding Custom CA to System Trust Stores

To use your custom CA certificates, add them to system trust stores.

### Linux (Debian/Ubuntu)

```bash
# Copy CA certificate
sudo cp ~/.config/demo-cfssl/ca.pem /usr/local/share/ca-certificates/demo-ca.crt

# Update trust store
sudo update-ca-certificates

# Verify
openssl verify ~/.config/demo-cfssl/ica-ca.pem
```

**Note**: File must have `.crt` extension in `/usr/local/share/ca-certificates/`

### Linux (RHEL/Fedora/Rocky/Alma)

```bash
# Copy CA certificate
sudo cp ~/.config/demo-cfssl/ca.pem /etc/pki/ca-trust/source/anchors/demo-ca.pem

# Update trust store
sudo update-ca-trust

# Verify
openssl verify ~/.config/demo-cfssl/ica-ca.pem
```

### macOS

```bash
# Add to system keychain
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    ~/.config/demo-cfssl/ca.pem

# Or use Keychain Access GUI:
# 1. Open Keychain Access
# 2. File → Import Items
# 3. Select ca.pem
# 4. Double-click certificate
# 5. Trust → When using this certificate: Always Trust
```

### Windows

```powershell
# PowerShell (Run as Administrator)
certutil -addstore -f "ROOT" C:\path\to\ca.pem

# Or use GUI:
# 1. Double-click ca.pem
# 2. Install Certificate
# 3. Store Location: Local Machine
# 4. Place in: Trusted Root Certification Authorities
```

### FreeBSD

```bash
# Copy certificate
sudo cp ~/.config/demo-cfssl/ca.pem /usr/local/share/certs/demo-ca.pem

# Rehash
sudo c_rehash /usr/local/share/certs/
```

## Mobile Devices

### Android

```bash
# Method 1: Install via Settings
# 1. Transfer ca.pem to device
# 2. Settings → Security → Install from storage
# 3. Select ca.pem file
# 4. Name the certificate

# Method 2: ADB Push (requires root)
adb push ca.pem /sdcard/
adb shell settings put secure install_non_market_apps 1
```

**Android 11+**: User certificates not trusted by apps by default

### iOS/iPadOS

```bash
# 1. Email ca.pem to device or host on web server
# 2. Open ca.pem file
# 3. Settings → Profile Downloaded → Install
# 4. Settings → General → About → Certificate Trust Settings
# 5. Enable Full Trust for Root Certificate
```

## Web Browsers

### Firefox

Firefox uses its own certificate store:

```bash
# Method 1: GUI
# 1. Settings → Privacy & Security
# 2. Certificates → View Certificates
# 3. Authorities tab → Import
# 4. Select ca.pem
# 5. Trust for websites

# Method 2: Enterprise deployment
# Create policy file: /etc/firefox/policies/policies.json
```

Policy file example:
```json
{
  "policies": {
    "Certificates": {
      "Install": ["/path/to/ca.pem"]
    }
  }
}
```

### Chrome/Edge (Chromium-based)

Uses system certificate store on Linux/Windows.

macOS:
```bash
# Already done if added to system keychain above
# Or use Settings → Privacy and security → Security → Manage certificates
```

## Web Servers

### Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name example.com;

    # Server certificate (bundle-2.pem = cert + ICA)
    ssl_certificate /etc/ssl/certs/example.com/bundle-2.pem;
    ssl_certificate_key /etc/ssl/private/example.com/key.pem;
    
    # SSL/TLS configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/ssl/certs/example.com/ca-bundle.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Client certificate authentication (optional)
    # ssl_client_certificate /etc/ssl/certs/ca-bundle.pem;
    # ssl_crl /etc/ssl/certs/ica-crl.pem;
    # ssl_verify_client on;
    
    location / {
        root /var/www/html;
        index index.html;
    }
}

# HTTP redirect
server {
    listen 80;
    server_name example.com;
    return 301 https://$server_name$request_uri;
}
```

### Apache

```apache
<VirtualHost *:443>
    ServerName example.com
    DocumentRoot /var/www/html
    
    # SSL Engine
    SSLEngine on
    
    # Server certificate and key
    SSLCertificateFile /etc/ssl/certs/example.com/cert.pem
    SSLCertificateKeyFile /etc/ssl/private/example.com/key.pem
    SSLCertificateChainFile /etc/ssl/certs/example.com/ica-ca.pem
    
    # SSL/TLS configuration
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    SSLHonorCipherOrder off
    
    # OCSP Stapling
    SSLUseStapling on
    SSLStaplingCache "shmcb:logs/ssl_stapling(32768)"
    
    # HSTS
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    
    # Client certificate authentication (optional)
    # SSLCACertificateFile /etc/ssl/certs/ca-bundle.pem
    # SSLCARevocationFile /etc/ssl/certs/ica-crl.pem
    # SSLVerifyClient require
    # SSLVerifyDepth 2
</VirtualHost>

<VirtualHost *:80>
    ServerName example.com
    Redirect permanent / https://example.com/
</VirtualHost>
```

### HAProxy

```haproxy
global
    # SSL/TLS configuration
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    mode http
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/example.com/haproxy.pem
    
    # HSTS
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    
    # Client certificate auth (optional)
    # bind *:443 ssl crt /etc/haproxy/certs/example.com/haproxy.pem \
    #     ca-file /etc/haproxy/certs/ca-bundle.pem \
    #     crl-file /etc/haproxy/certs/ica-crl.pem \
    #     verify required
    
    default_backend web_servers

frontend http_front
    bind *:80
    # Redirect to HTTPS
    http-request redirect scheme https code 301

backend web_servers
    balance roundrobin
    server web1 192.168.1.10:80 check
    server web2 192.168.1.11:80 check
```

**Note**: HAProxy requires combined PEM file (certificate chain + private key)

## Application Integration

### Python (requests)

```python
import requests

# Use custom CA bundle
response = requests.get(
    'https://example.com',
    verify='/path/to/ca-bundle.pem'
)

# Or set globally
import os
os.environ['REQUESTS_CA_BUNDLE'] = '/path/to/ca-bundle.pem'
```

### Node.js

```javascript
// Set extra CA certificates
process.env.NODE_EXTRA_CA_CERTS = '/path/to/ca-bundle.pem';

const https = require('https');
https.get('https://example.com', (res) => {
    console.log('Status:', res.statusCode);
});

// Or per-request
const options = {
    hostname: 'example.com',
    port: 443,
    path: '/',
    method: 'GET',
    ca: fs.readFileSync('/path/to/ca-bundle.pem')
};
```

### Java

```java
// Import CA certificate into Java keystore
keytool -import -trustcacerts \
    -alias demo-ca \
    -file ca.pem \
    -keystore $JAVA_HOME/lib/security/cacerts \
    -storepass changeit

// Or use custom truststore
System.setProperty("javax.net.ssl.trustStore", "/path/to/truststore.jks");
System.setProperty("javax.net.ssl.trustStorePassword", "password");
```

### curl

```bash
# Use CA bundle
curl --cacert /path/to/ca-bundle.pem https://example.com

# Or set globally
export CURL_CA_BUNDLE=/path/to/ca-bundle.pem
curl https://example.com
```

### Git

```bash
# Per repository
git config http.sslCAInfo /path/to/ca-bundle.pem

# Globally
git config --global http.sslCAInfo /path/to/ca-bundle.pem

# System-wide
git config --system http.sslCAInfo /path/to/ca-bundle.pem
```

### Docker

```dockerfile
# Add CA to Docker image
FROM ubuntu:22.04

COPY ca.pem /usr/local/share/ca-certificates/demo-ca.crt
RUN update-ca-certificates
```

## OCSP Responder Production Deployment

### Systemd Service

```ini
# /etc/systemd/system/ocsp-responder.service
[Unit]
Description=OCSP Responder for demo-cfssl
After=network.target

[Service]
Type=simple
User=ocsp
Group=ocsp
WorkingDirectory=/opt/demo-cfssl/ocsp
Environment="DEMO_CFSSL_DIR=/etc/demo-cfssl"
Environment="OCSP_HOST=0.0.0.0"
Environment="OCSP_PORT=8080"
ExecStart=/opt/demo-cfssl/ocsp/.venv/bin/python main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/ocsp

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable ocsp-responder
sudo systemctl start ocsp-responder
sudo systemctl status ocsp-responder

# View logs
sudo journalctl -u ocsp-responder -f
```

### Nginx Reverse Proxy for OCSP

```nginx
upstream ocsp_backend {
    server 127.0.0.1:8080;
    # Add more instances for HA
    # server 127.0.0.1:8081;
    # server 127.0.0.1:8082;
}

server {
    listen 80;
    server_name ocsp.example.com;
    
    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ocsp.example.com;
    
    # SSL configuration
    ssl_certificate /etc/ssl/certs/ocsp.example.com/bundle-2.pem;
    ssl_certificate_key /etc/ssl/private/ocsp.example.com/key.pem;
    
    # OCSP responses should not be cached
    add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    add_header Pragma "no-cache" always;
    add_header Expires "0" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=ocsp_limit:10m rate=10r/s;
    limit_req zone=ocsp_limit burst=20 nodelay;
    
    location / {
        proxy_pass http://ocsp_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 5s;
        proxy_send_timeout 10s;
        proxy_read_timeout 10s;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://ocsp_backend/health;
        access_log off;
    }
}
```

### Docker Production Deployment

```yaml
# docker-compose.prod.yml
version: "3.8"

services:
  ocsp:
    image: demo-cfssl-ocsp:latest
    container_name: ocsp-responder
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"  # Only localhost
    volumes:
      - /etc/demo-cfssl:/certs:ro
    environment:
      - DEMO_CFSSL_DIR=/certs
      - OCSP_HOST=0.0.0.0
      - OCSP_PORT=8080
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - backend

  nginx:
    image: nginx:latest
    container_name: ocsp-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/ssl/certs:/etc/ssl/certs:ro
      - /etc/ssl/private:/etc/ssl/private:ro
    depends_on:
      - ocsp
    networks:
      - backend

networks:
  backend:
    driver: bridge
```

## Security Best Practices

### Key Protection

```bash
# Secure permissions
chmod 600 /path/to/private-keys/*.pem
chown root:root /path/to/private-keys/*.pem

# Store CA keys offline
# Encrypt backups
gpg -c ca-key-backup.tar.gz

# Use HSM for production CAs
# Consider: YubiHSM, AWS CloudHSM, Azure Key Vault
```

### Certificate Deployment

```bash
# Use ansible/puppet/chef for deployment
# Example ansible task:
# - name: Deploy certificate
#   copy:
#     src: "{{ cert_path }}"
#     dest: /etc/ssl/certs/{{ domain }}/
#     mode: '0644'
#     owner: root
#     group: root
```

### Monitoring

```bash
# Monitor certificate expiration
#!/bin/bash
CERT="/etc/ssl/certs/example.com/cert.pem"
DAYS=30

if openssl x509 -in "$CERT" -noout -checkend $((DAYS * 86400)); then
    echo "Certificate valid for next $DAYS days"
else
    echo "Certificate expires within $DAYS days!" | mail -s "Certificate Expiry Warning" admin@example.com
fi
```

### Backup Strategy

```bash
# Automated backup script
#!/bin/bash
BACKUP_DIR="/backup/demo-cfssl"
DATE=$(date +%Y%m%d_%H%M%S)

# Backup certificates and keys
tar -czf "$BACKUP_DIR/cfssl-backup-$DATE.tar.gz" \
    ~/.config/demo-cfssl/ \
    --exclude="*.csr"

# Encrypt backup
gpg -e -r admin@example.com "$BACKUP_DIR/cfssl-backup-$DATE.tar.gz"

# Remove unencrypted
rm "$BACKUP_DIR/cfssl-backup-$DATE.tar.gz"

# Keep only last 30 days
find "$BACKUP_DIR" -name "cfssl-backup-*.tar.gz.gpg" -mtime +30 -delete
```

## High Availability

### Multiple OCSP Responders

```bash
# Run multiple instances
OCSP_PORT=8080 python main.py &
OCSP_PORT=8081 python main.py &
OCSP_PORT=8082 python main.py &

# Load balance with nginx (see above)
```

### Geo-distributed CRL

```bash
# Use CDN for CRL distribution
# - AWS CloudFront
# - Cloudflare
# - Akamai

# Sync CRL to multiple locations
rsync -avz ica-crl.der user@cdn1.example.com:/var/www/crl/
rsync -avz ica-crl.der user@cdn2.example.com:/var/www/crl/
```

## Compliance and Auditing

### Logging

```bash
# Enable audit logging
# Log all certificate operations
LOG_FILE="/var/log/cfssl/audit.log"

# Log format: timestamp | action | certificate | user
echo "$(date) | REVOKE | server1.example.com | admin" >> "$LOG_FILE"
```

### Regular Audits

```bash
# List all issued certificates
find ~/.config/demo-cfssl/hosts -name "cert.pem" -exec openssl x509 -in {} -noout -subject -enddate \;

# Check for expiring certificates
find ~/.config/demo-cfssl/hosts -name "cert.pem" | while read cert; do
    if ! openssl x509 -in "$cert" -noout -checkend $((30 * 86400)); then
        echo "Expiring soon: $cert"
    fi
done
```

## Next Steps

- **[Examples](examples.md)** - Practical deployment scenarios
- **[Troubleshooting](troubleshooting.md)** - Common deployment issues
- **[Certificate Management](certificate-management.md)** - Certificate operations

## References

- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [SSL Labs Server Test](https://www.ssllabs.com/ssltest/)
- [CAA Record Generator](https://sslmate.com/caa/)

