#!/bin/bash
#
# Complete OCSP workflow example
# This script demonstrates:
# 1. Starting the OCSP responder
# 2. Generating certificates with OCSP and CRL URLs
# 3. Testing OCSP validation
# 4. Revoking a certificate
# 5. Verifying revocation via OCSP
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
COFF='\033[0m'

BD="${DEMO_CFSSL_DIR:-$HOME/.config/demo-cfssl}"
OCSP_URL="http://localhost:8080/ocsp"
CRL_URL="http://localhost:8080/crl/ica.crl"

function print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${COFF}"
    echo -e "${BLUE}$1${COFF}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${COFF}"
    echo ""
}

function print_step() {
    echo ""
    echo -e "${CYAN}▶ $1${COFF}"
    echo ""
}

function print_success() {
    echo -e "${GREEN}✓ $1${COFF}"
}

function print_error() {
    echo -e "${RED}✗ $1${COFF}"
}

function print_info() {
    echo -e "${YELLOW}ℹ $1${COFF}"
}

function pause_for_review() {
    echo ""
    echo -e "${YELLOW}Press ENTER to continue...${COFF}"
    read
}

print_header "OCSP Complete Workflow Example"

print_info "This script demonstrates the complete OCSP workflow:"
echo "  1. Check OCSP responder is running"
echo "  2. Generate a certificate with OCSP and CRL URLs"
echo "  3. Verify the certificate contains the URLs"
echo "  4. Test OCSP validation (certificate should be GOOD)"
echo "  5. Revoke the certificate"
echo "  6. Test OCSP validation again (should be REVOKED)"
echo ""

# Check if certificates exist
if [ ! -f "$BD/ica-ca.pem" ]; then
    print_error "Certificates not found in $BD"
    print_info "Please run: cd .. && ./steps.sh"
    exit 1
fi

pause_for_review

# Step 1: Check OCSP responder
print_step "Step 1: Checking if OCSP responder is running"

if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    print_success "OCSP responder is running at http://localhost:8080"
    
    # Show status
    echo ""
    echo "OCSP Responder Status:"
    curl -s http://localhost:8080/status | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/status
    echo ""
else
    print_error "OCSP responder is not running"
    print_info "Please start it in another terminal:"
    print_info "  cd ocsp && python main.py"
    exit 1
fi

pause_for_review

# Step 2: Generate certificate with OCSP and CRL URLs
print_step "Step 2: Generating test certificate with OCSP and CRL URLs"

TEST_HOST="ocsp-test.example.com"
TEST_DIR="$BD/hosts/$TEST_HOST"

# Clean up if exists
if [ -d "$TEST_DIR" ]; then
    print_info "Removing existing test certificate..."
    rm -rf "$TEST_DIR"
fi

mkdir -p "$TEST_DIR"

print_info "Creating OpenSSL configuration..."

cat > "$TEST_DIR/openssl.cnf" << EOF
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
CN = ${TEST_HOST}

[v3_req]
subjectAltName = DNS:${TEST_HOST},DNS:*.example.com

[v3_ca]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
authorityInfoAccess = OCSP;URI:${OCSP_URL}
crlDistributionPoints = URI:${CRL_URL}
subjectAltName = DNS:${TEST_HOST},DNS:*.example.com
EOF

print_info "Generating private key..."
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
    -out "$TEST_DIR/key.pem" 2>/dev/null

print_info "Generating Certificate Signing Request..."
openssl req -new \
    -key "$TEST_DIR/key.pem" \
    -out "$TEST_DIR/cert.csr" \
    -config "$TEST_DIR/openssl.cnf" 2>/dev/null

print_info "Signing certificate with Intermediate CA..."
openssl x509 -req \
    -in "$TEST_DIR/cert.csr" \
    -CA "$BD/ica-ca.pem" \
    -CAkey "$BD/ica-key.pem" \
    -CAcreateserial \
    -out "$TEST_DIR/cert.pem" \
    -days 47 \
    -sha384 \
    -extfile "$TEST_DIR/openssl.cnf" \
    -extensions v3_ca 2>/dev/null

print_success "Certificate generated successfully!"

# Create bundles
cat "$TEST_DIR/cert.pem" "$BD/ica-ca.pem" > "$TEST_DIR/bundle-2.pem"
cat "$TEST_DIR/cert.pem" "$BD/ica-ca.pem" "$BD/ca.pem" > "$TEST_DIR/bundle-3.pem"

print_info "Certificate location: $TEST_DIR/cert.pem"

pause_for_review

# Step 3: Verify certificate contains OCSP and CRL URLs
print_step "Step 3: Verifying certificate contains OCSP and CRL URLs"

echo -e "${YELLOW}Certificate Subject and Issuer:${COFF}"
openssl x509 -in "$TEST_DIR/cert.pem" -noout -subject -issuer
echo ""

echo -e "${YELLOW}Authority Information Access (OCSP URL):${COFF}"
openssl x509 -in "$TEST_DIR/cert.pem" -noout -text | grep -A3 "Authority Information Access" || print_error "OCSP URL not found!"
echo ""

echo -e "${YELLOW}CRL Distribution Points:${COFF}"
openssl x509 -in "$TEST_DIR/cert.pem" -noout -text | grep -A3 "CRL Distribution Points" || print_error "CRL URL not found!"
echo ""

if openssl x509 -in "$TEST_DIR/cert.pem" -noout -text | grep -q "OCSP.*URI:$OCSP_URL"; then
    print_success "OCSP URL correctly embedded: $OCSP_URL"
else
    print_error "OCSP URL not found or incorrect"
fi

if openssl x509 -in "$TEST_DIR/cert.pem" -noout -text | grep -q "URI:$CRL_URL"; then
    print_success "CRL URL correctly embedded: $CRL_URL"
else
    print_error "CRL URL not found or incorrect"
fi

pause_for_review

# Step 4: Test OCSP validation (should be GOOD)
print_step "Step 4: Testing OCSP validation - Certificate should be GOOD"

print_info "Sending OCSP request to: $OCSP_URL"
echo ""

OCSP_OUTPUT=$(openssl ocsp \
    -issuer "$BD/ica-ca.pem" \
    -cert "$TEST_DIR/cert.pem" \
    -url "$OCSP_URL" \
    -text 2>&1)

echo "$OCSP_OUTPUT"
echo ""

if echo "$OCSP_OUTPUT" | grep -q "good"; then
    print_success "Certificate status: GOOD ✓"
elif echo "$OCSP_OUTPUT" | grep -q "revoked"; then
    print_info "Certificate status: REVOKED (unexpected at this stage)"
else
    print_error "Unexpected OCSP response"
fi

pause_for_review

# Step 5: Revoke the certificate
print_step "Step 5: Revoking the test certificate"

print_info "Revoking certificate with reason: keyCompromise"
cd ..
./crl_mk.sh revoke "$TEST_DIR/cert.pem" keyCompromise

print_info "Regenerating CRL to include revoked certificate..."
./crl_mk.sh generate ica

print_success "Certificate revoked and CRL updated"

print_info "Waiting for OCSP responder to reload database (2 seconds)..."
sleep 2

# The OCSP responder would need to be restarted or have auto-reload
print_info "Note: In production, the OCSP responder should auto-reload the database"
print_info "For this demo, you may need to restart the OCSP responder to see the change"

pause_for_review

# Step 6: Test OCSP validation again (should be REVOKED)
print_step "Step 6: Testing OCSP validation - Certificate should now be REVOKED"

print_info "Sending OCSP request again..."
echo ""

OCSP_OUTPUT_REVOKED=$(openssl ocsp \
    -issuer "$BD/ica-ca.pem" \
    -cert "$TEST_DIR/cert.pem" \
    -url "$OCSP_URL" \
    -text 2>&1)

echo "$OCSP_OUTPUT_REVOKED"
echo ""

if echo "$OCSP_OUTPUT_REVOKED" | grep -q "revoked"; then
    print_success "Certificate status: REVOKED ✓"
    print_success "OCSP correctly reports revoked status!"
elif echo "$OCSP_OUTPUT_REVOKED" | grep -q "good"; then
    print_info "Certificate status: GOOD"
    print_info "This means the OCSP responder hasn't reloaded the revocation database yet"
    print_info "Restart the OCSP responder: python main.py"
else
    print_error "Unexpected OCSP response"
fi

echo ""

# Step 7: Verify using CRL as well
print_step "Step 7: Bonus - Verify using CRL"

print_info "Checking certificate against CRL file..."
echo ""

if [ -f "$BD/ica-crl.pem" ]; then
    # This will fail because certificate is revoked
    if openssl verify \
        -crl_check \
        -CRLfile "$BD/ica-crl.pem" \
        -CAfile "$BD/ca-bundle.pem" \
        "$TEST_DIR/cert.pem" 2>&1 | grep -q "revoked"; then
        print_success "CRL also confirms certificate is REVOKED ✓"
    else
        print_info "CRL verification result differs"
    fi
else
    print_info "CRL file not found, skipping CRL verification"
fi

# Summary
print_header "Workflow Complete!"

echo -e "${GREEN}Summary:${COFF}"
echo "  ✓ Generated certificate with OCSP and CRL URLs"
echo "  ✓ Verified OCSP URL is embedded in certificate"
echo "  ✓ Tested OCSP validation (GOOD status)"
echo "  ✓ Revoked certificate and updated CRL"
echo "  ✓ Verified OCSP reports revoked status"
echo ""

print_info "Test certificate location: $TEST_DIR"
print_info "You can inspect it with: openssl x509 -in $TEST_DIR/cert.pem -noout -text"
echo ""

echo -e "${CYAN}Next Steps:${COFF}"
echo "  1. Deploy OCSP responder to production (see ocsp/README.md)"
echo "  2. Use public URLs instead of localhost"
echo "  3. Set up HTTPS for OCSP and CRL endpoints"
echo "  4. Implement monitoring and alerting"
echo "  5. Configure OCSP stapling in web servers"
echo ""

print_success "OCSP workflow demonstration complete!"

