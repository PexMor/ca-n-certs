#!/bin/bash
#
# crl_check_examples.sh - Usage examples for crl_check.sh
#
# This file demonstrates various ways to use the crl_check.sh script
# for checking certificate revocation status.
#

echo "=== CRL Certificate Checking Examples ==="
echo ""

BD="$HOME/.config/demo-cfssl"

# Example 1: Basic check
echo "Example 1: Basic Certificate Check"
echo "-----------------------------------"
echo "Command:"
echo "  ./crl_check.sh $BD/hosts/localhost/cert.pem"
echo ""
echo "This performs a simple check and shows if the certificate is valid or revoked."
echo ""

# Example 2: Verbose mode
echo "Example 2: Verbose Mode"
echo "-----------------------"
echo "Command:"
echo "  ./crl_check.sh $BD/hosts/localhost/cert.pem --verbose"
echo ""
echo "This displays detailed certificate information including:"
echo "  - Certificate serial number"
echo "  - Subject and Issuer"
echo "  - Validity period"
echo "  - CRL being used"
echo "  - Detailed OpenSSL verification output"
echo ""

# Example 3: Quiet mode
echo "Example 3: Quiet Mode (for scripting)"
echo "--------------------------------------"
echo "Command:"
echo "  ./crl_check.sh $BD/hosts/localhost/cert.pem --quiet"
echo '  echo "Exit code: $?"'
echo ""
echo "Returns only exit code:"
echo "  0 = Certificate is valid"
echo "  1 = Certificate is revoked"
echo "  2 = Error occurred"
echo ""

# Example 4: JSON output
echo "Example 4: JSON Output"
echo "----------------------"
echo "Command:"
echo "  ./crl_check.sh $BD/hosts/localhost/cert.pem --json"
echo ""
echo "Outputs structured JSON for parsing:"
echo '  {'
echo '    "certificate": "/path/to/cert.pem",'
echo '    "serial": "ABC123...",'
echo '    "subject": "CN=localhost,...",'
echo '    "status": "valid",'
echo '    "timestamp": "2025-10-23T12:00:00Z"'
echo '  }'
echo ""

# Example 5: Custom CRL
echo "Example 5: Custom CRL File"
echo "--------------------------"
echo "Command:"
echo "  ./crl_check.sh cert.pem --crl /path/to/custom-crl.pem"
echo ""
echo "Use a specific CRL file instead of auto-detection."
echo ""

# Example 6: Custom CA bundle
echo "Example 6: Custom CA Bundle"
echo "---------------------------"
echo "Command:"
echo "  ./crl_check.sh cert.pem --ca-bundle /path/to/ca-bundle.pem"
echo ""
echo "Use a specific CA bundle for verification."
echo ""

# Example 7: Batch checking
echo "Example 7: Batch Certificate Checking"
echo "--------------------------------------"
echo "Commands:"
echo "  # Create a list of certificates"
echo "  cat > certs.txt << EOF"
echo "  $BD/hosts/server1/cert.pem"
echo "  $BD/hosts/server2/cert.pem"
echo "  $BD/smime-openssl/john_doe/cert.pem"
echo "  EOF"
echo ""
echo "  # Check all certificates"
echo "  ./crl_check.sh --batch certs.txt"
echo ""
echo "Displays results for all certificates with a summary."
echo ""

# Example 8: Batch with JSON
echo "Example 8: Batch Checking with JSON Output"
echo "-------------------------------------------"
echo "Command:"
echo "  ./crl_check.sh --batch certs.txt --json > report.json"
echo ""
echo "Generates a JSON report of all certificate statuses."
echo ""

# Example 9: Scripting example
echo "Example 9: Integration in Shell Script"
echo "---------------------------------------"
cat << 'EOF'
#!/bin/bash
CERT="/path/to/certificate.pem"

if ./crl_check.sh "$CERT" --quiet; then
    echo "Certificate is valid, proceeding..."
    # Continue with operations
else
    exit_code=$?
    if [ $exit_code -eq 1 ]; then
        echo "ERROR: Certificate is revoked!"
        exit 1
    else
        echo "ERROR: Failed to check certificate"
        exit 2
    fi
fi
EOF
echo ""

# Example 10: Monitoring script
echo "Example 10: Automated Monitoring Script"
echo "----------------------------------------"
cat << 'EOF'
#!/bin/bash
# check-all-certs-cron.sh - Run from cron

BD="$HOME/.config/demo-cfssl"
LOG="/var/log/cert-check.log"
ALERT_EMAIL="admin@example.com"

# Find all certificates
find "$BD/hosts" "$BD/smime-openssl" -name "cert.pem" > /tmp/all-certs.txt

# Check them all
if ! ./crl_check.sh --batch /tmp/all-certs.txt > "$LOG" 2>&1; then
    # Some certificates are revoked or errors occurred
    cat "$LOG" | mail -s "Certificate Alert: Revoked certs found" "$ALERT_EMAIL"
fi

# Generate JSON report
./crl_check.sh --batch /tmp/all-certs.txt --json > /var/www/reports/cert-status.json

rm /tmp/all-certs.txt
EOF
echo ""
echo "Add to crontab:"
echo "  0 * * * * /path/to/check-all-certs-cron.sh"
echo ""

# Example 11: Pre-deployment check
echo "Example 11: Pre-Deployment Validation"
echo "--------------------------------------"
cat << 'EOF'
#!/bin/bash
# deploy-cert.sh - Deploy certificate only if valid

CERT="$1"
DEST="$2"

echo "Validating certificate before deployment..."
if ./crl_check.sh "$CERT" --verbose; then
    echo "Certificate is valid. Deploying..."
    cp "$CERT" "$DEST"
    systemctl reload nginx
    echo "Deployment complete."
else
    echo "ERROR: Certificate validation failed!"
    echo "Certificate is either revoked or invalid."
    exit 1
fi
EOF
echo ""

# Example 12: Load balancer health check
echo "Example 12: Load Balancer Certificate Health Check"
echo "---------------------------------------------------"
cat << 'EOF'
#!/bin/bash
# check-lb-certs.sh - Check all load balancer certificates

SERVERS=(
    "/etc/ssl/server1/cert.pem"
    "/etc/ssl/server2/cert.pem"
    "/etc/ssl/server3/cert.pem"
)

for cert in "${SERVERS[@]}"; do
    server=$(basename $(dirname "$cert"))
    echo -n "Checking $server: "
    
    if ./crl_check.sh "$cert" --quiet; then
        echo "✓ OK"
    else
        echo "✗ REVOKED - Removing from pool"
        # Remove from load balancer pool
        # curl -X DELETE "http://lb-api/remove/$server"
    fi
done
EOF
echo ""

echo "=== Quick Reference ==="
echo ""
echo "Check single certificate:"
echo "  ./crl_check.sh /path/to/cert.pem"
echo ""
echo "Verbose output:"
echo "  ./crl_check.sh /path/to/cert.pem --verbose"
echo ""
echo "For scripting (exit code only):"
echo "  ./crl_check.sh /path/to/cert.pem --quiet"
echo ""
echo "JSON output:"
echo "  ./crl_check.sh /path/to/cert.pem --json"
echo ""
echo "Batch checking:"
echo "  ./crl_check.sh --batch cert-list.txt"
echo ""
echo "Help:"
echo "  ./crl_check.sh --help"
echo ""
echo "For complete documentation, see CRL_MANAGEMENT.md"

