# CRL Management - Quick Examples

This document provides practical examples for common CRL management scenarios.

## Scenario 1: Server Compromise

Your server has been compromised and you need to revoke its certificate immediately.

```bash
# 1. Revoke the compromised server certificate
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/compromised-server/cert.pem keyCompromise

# 2. Generate and publish the updated CRL
./crl_mk.sh generate ica

# 3. Copy CRL to your web server or distribution point
cp ~/.config/demo-cfssl/ica-crl.pem /var/www/crl/ica-crl.pem

# 4. Verify the certificate is now revoked
./crl_mk.sh verify ~/.config/demo-cfssl/hosts/compromised-server/cert.pem ica

# 5. Generate a new certificate for the server
# Edit steps.sh and run step03 function with new parameters
```

## Scenario 2: Certificate Replacement

You're replacing an old certificate with a new one (e.g., updating to a longer key size or changing domains).

```bash
# 1. Generate new certificate first (before revoking old one)
# This ensures no service downtime
# (Use steps.sh step03 function)

# 2. Deploy new certificate to your server
# Test that it works

# 3. Revoke the old certificate with "superseded" reason
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/old-server/cert.pem superseded

# 4. Update the CRL
./crl_mk.sh generate ica

# 5. List all revoked certificates to confirm
./crl_mk.sh list ica
```

## Scenario 3: Employee Departure

An employee with an S/MIME certificate leaves the company.

```bash
# 1. Revoke their email certificate
./crl_mk.sh revoke ~/.config/demo-cfssl/smime-openssl/john_doe/cert.pem affiliationChanged

# 2. Update the CRL
./crl_mk.sh generate ica

# 3. Verify revocation
./crl_mk.sh verify ~/.config/demo-cfssl/smime-openssl/john_doe/cert.pem ica

# 4. Inform email server administrators to update CRL
# Or publish to HTTP endpoint
```

## Scenario 4: Setting Up Initial CRL Infrastructure

First time setting up CRL for your CA infrastructure.

```bash
# 1. Ensure CA infrastructure exists
./steps.sh

# 2. Generate initial empty CRL for Intermediate CA
./crl_mk.sh generate ica

# 3. Generate initial empty CRL for Root CA (if needed)
./crl_mk.sh generate ca

# 4. Check CRL information
./crl_mk.sh info ica

# 5. Set up automatic CRL regeneration (edit crontab)
crontab -e
# Add: 0 2 * * 1 /path/to/demo-cfssl/crl_mk.sh generate ica

# 6. Set up CRL distribution (see Scenario 7)
```

## Scenario 5: Regular CRL Maintenance

Scheduled maintenance to regenerate CRLs before they expire.

```bash
# 1. Check current CRL status
./crl_mk.sh info ica

# 2. Regenerate CRL (even if no new revocations)
# This extends the validity period
./crl_mk.sh generate ica

# 3. Distribute updated CRL to all servers
# (See Scenario 7)

# 4. Verify CRL is valid
openssl crl -in ~/.config/demo-cfssl/ica-crl.pem -noout -text | head -20
```

## Scenario 6: Bulk Certificate Revocation

Multiple certificates need to be revoked at once (e.g., security audit findings).

```bash
# 1. Create a list of certificates to revoke
cat > revoke-list.txt << EOF
~/.config/demo-cfssl/hosts/server1/cert.pem keyCompromise
~/.config/demo-cfssl/hosts/server2/cert.pem keyCompromise
~/.config/demo-cfssl/hosts/server3/cert.pem superseded
~/.config/demo-cfssl/smime-openssl/old_user/cert.pem affiliationChanged
EOF

# 2. Revoke all certificates
while IFS=' ' read -r cert reason; do
    echo "Revoking: $cert (Reason: $reason)"
    ./crl_mk.sh revoke "$cert" "$reason"
done < revoke-list.txt

# 3. Generate CRL once (includes all revocations)
./crl_mk.sh generate ica

# 4. Review all revoked certificates
./crl_mk.sh list ica

# 5. Distribute updated CRL
```

## Scenario 7: CRL Distribution Setup

Publishing CRLs to make them accessible to clients.

### Option A: Simple HTTP Distribution

```bash
# 1. Set up a simple web server directory
sudo mkdir -p /var/www/pki/crl
sudo chmod 755 /var/www/pki/crl

# 2. Create a script to publish CRL
cat > publish-crl.sh << 'EOF'
#!/bin/bash
cp ~/.config/demo-cfssl/ica-crl.pem /var/www/pki/crl/ica-crl.pem
cp ~/.config/demo-cfssl/ica-crl.der /var/www/pki/crl/ica-crl.der
chmod 644 /var/www/pki/crl/*
echo "CRL published: $(date)"
EOF
chmod +x publish-crl.sh

# 3. Configure web server (Nginx example)
cat > /etc/nginx/sites-available/pki << 'EOF'
server {
    listen 80;
    server_name pki.yourdomain.com;
    root /var/www/pki;
    
    location /crl/ {
        autoindex on;
        add_header Content-Type application/pkix-crl;
    }
}
EOF
sudo ln -s /etc/nginx/sites-available/pki /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 4. Update CRL and publish
./crl_mk.sh generate ica
./publish-crl.sh

# 5. Test access
curl -o test-crl.pem http://pki.yourdomain.com/crl/ica-crl.pem
openssl crl -in test-crl.pem -noout -text | head -10
```

### Option B: Local File Distribution

```bash
# For environments without HTTP server, distribute via shared filesystem
# 1. Set CRL location (e.g., NFS or SMB share)
CRL_SHARE="/mnt/shared/pki/crl"
mkdir -p "$CRL_SHARE"

# 2. Publish CRL to shared location
cp ~/.config/demo-cfssl/ica-crl.pem "$CRL_SHARE/"
cp ~/.config/demo-cfssl/ica-crl.der "$CRL_SHARE/"

# 3. Configure clients to use file:// URLs in CRL Distribution Points
```

## Scenario 8: Verify All Issued Certificates

Check which certificates are still valid and which are revoked.

### Method 1: Using crl_check.sh in batch mode (recommended)

```bash
# 1. Create a list of all certificates
cat > all-certs.txt << EOF
$(find ~/.config/demo-cfssl/hosts -name "cert.pem" 2>/dev/null)
$(find ~/.config/demo-cfssl/smime-openssl -name "cert.pem" 2>/dev/null)
EOF

# 2. Check all certificates at once
./crl_check.sh --batch all-certs.txt

# 3. For JSON output (useful for logging/monitoring)
./crl_check.sh --batch all-certs.txt --json > cert-status-report.json
```

### Method 2: Using a custom verification script

```bash
# 1. Create verification script
cat > verify-all-certs.sh << 'EOF'
#!/bin/bash
BD="$HOME/.config/demo-cfssl"

echo "=== Verifying All Host Certificates ==="
for cert in "$BD"/hosts/*/cert.pem; do
    hostname=$(basename $(dirname "$cert"))
    echo -n "Checking $hostname: "
    ./crl_check.sh "$cert" --quiet
    if [ $? -eq 0 ]; then
        echo "✓ Valid"
    elif [ $? -eq 1 ]; then
        echo "✗ Revoked"
    else
        echo "⚠ Error"
    fi
done

echo ""
echo "=== Verifying All Email Certificates ==="
for cert in "$BD"/smime-openssl/*/cert.pem; do
    person=$(basename $(dirname "$cert"))
    echo -n "Checking $person: "
    ./crl_check.sh "$cert" --quiet
    if [ $? -eq 0 ]; then
        echo "✓ Valid"
    elif [ $? -eq 1 ]; then
        echo "✗ Revoked"
    else
        echo "⚠ Error"
    fi
done
EOF
chmod +x verify-all-certs.sh

# 2. Run verification
./verify-all-certs.sh
```

## Scenario 9: CRL Monitoring and Alerting

Set up monitoring to alert before CRL expiration.

```bash
# 1. Create monitoring script
cat > check-crl-expiry.sh << 'EOF'
#!/bin/bash
CRL_FILE="$HOME/.config/demo-cfssl/ica-crl.pem"
DAYS_WARNING=7

if [ ! -f "$CRL_FILE" ]; then
    echo "ERROR: CRL file not found: $CRL_FILE"
    exit 2
fi

NEXT_UPDATE=$(openssl crl -in "$CRL_FILE" -noout -nextupdate | cut -d= -f2)
NEXT_UPDATE_SECS=$(date -d "$NEXT_UPDATE" +%s)
NOW_SECS=$(date +%s)
DAYS_LEFT=$(( ($NEXT_UPDATE_SECS - $NOW_SECS) / 86400 ))

echo "CRL Next Update: $NEXT_UPDATE"
echo "Days Remaining: $DAYS_LEFT"

if [ $DAYS_LEFT -lt 0 ]; then
    echo "CRITICAL: CRL is EXPIRED!"
    exit 2
elif [ $DAYS_LEFT -lt $DAYS_WARNING ]; then
    echo "WARNING: CRL expires in $DAYS_LEFT days"
    exit 1
else
    echo "OK: CRL is valid"
    exit 0
fi
EOF
chmod +x check-crl-expiry.sh

# 2. Test the script
./check-crl-expiry.sh

# 3. Add to cron for daily checks with email alerts
crontab -e
# Add: 0 9 * * * /path/to/check-crl-expiry.sh || mail -s "CRL Alert" admin@example.com
```

## Scenario 10: Migration from Old CRL

Migrating from manually managed CRL to this automated system.

```bash
# 1. Backup existing CRL infrastructure
mkdir -p ~/crl-backup
cp -r ~/.config/demo-cfssl/crl ~/crl-backup/crl-$(date +%Y%m%d)

# 2. Parse old CRL and extract revoked certificate serials
OLD_CRL="path/to/old-crl.pem"
openssl crl -in "$OLD_CRL" -text -noout | \
    grep "Serial Number:" | \
    awk '{print $3}' > old-revoked-serials.txt

# 3. For each serial, find matching certificate and revoke
# (This requires you to have access to the original certificates)

# 4. Generate new CRL with all revocations
./crl_mk.sh generate ica

# 5. Compare old and new CRL
echo "Old CRL revocations:"
openssl crl -in "$OLD_CRL" -text -noout | grep -c "Serial Number:"
echo "New CRL revocations:"
openssl crl -in ~/.config/demo-cfssl/ica-crl.pem -text -noout | grep -c "Serial Number:"
```

## Scenario 11: Emergency CA Compromise

The CA private key has been compromised - emergency revocation procedure.

```bash
# 1. IMMEDIATELY stop using the compromised CA
# Do not issue any new certificates

# 2. Revoke ALL certificates issued by compromised CA
# (Document and notify all certificate holders)

# 3. If Intermediate CA is compromised
./crl_mk.sh revoke ~/.config/demo-cfssl/ica-ca.pem CACompromise

# 4. Generate CRL from Root CA
./crl_mk.sh generate ca

# 5. Publish revocation to all possible channels
# - Email all certificate holders
# - Update CRL distribution points
# - Contact any external relying parties

# 6. Generate new CA infrastructure
# (Follow steps.sh to create new Root/Intermediate CA)

# 7. Re-issue all certificates under new CA
```

## Scenario 12: Temporary Certificate Hold

Temporarily suspend a certificate (can be reversed if needed).

```bash
# 1. Place certificate on hold
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/suspicious-server/cert.pem certificateHold

# 2. Update CRL
./crl_mk.sh generate ica

# 3. Later, to permanently revoke, manually edit the CRL database
# Edit: ~/.config/demo-cfssl/crl/ica/index.txt
# Change the reason from "certificateHold" to desired reason
# Then regenerate CRL

# Note: Full "unrevocation" is not supported by standard X.509 CRL
# If you need to restore the certificate, remove its entry from index.txt
# and regenerate the CRL
```

## Tips and Best Practices

### Automate CRL Updates
```bash
# Add to root's crontab
sudo crontab -e
# Regenerate CRL weekly
0 2 * * 1 /path/to/demo-cfssl/crl_mk.sh generate ica
# Check CRL status daily
0 9 * * * /path/to/check-crl-expiry.sh
```

### Keep Revocation Records
```bash
# Backup CRL database regularly
cp ~/.config/demo-cfssl/crl/ica/index.txt \
   ~/backups/crl-index-$(date +%Y%m%d).txt
```

### Monitor CRL Size
```bash
# Check CRL size and number of revocations
ls -lh ~/.config/demo-cfssl/ica-crl.pem
./crl_mk.sh list ica | grep "Total revoked"
```

### Document Revocations
```bash
# Create revocation log
echo "$(date): Revoked cert for server1 - Reason: keyCompromise - Ticket: SEC-12345" \
    >> ~/.config/demo-cfssl/revocation-log.txt
```

## Troubleshooting

### CRL Too Large
If CRL becomes very large due to many revocations:
- Consider shortening certificate lifetimes
- Remove expired certificate entries from CRL (they're no longer needed)
- Implement CRL partitioning (Delta CRLs)

### Distribution Delays
If CRL updates take too long to propagate:
- Implement caching with appropriate TTL
- Use CDN for CRL distribution
- Consider implementing OCSP as an alternative

### Revocation Not Taking Effect
If revoked certificates still validate:
- Check that CRL is being consulted by client applications
- Verify CRL distribution is working
- Ensure CRL hasn't expired
- Check that correct CRL is being used (ca vs ica)

