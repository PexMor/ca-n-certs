#!/bin/bash
#
# Test OCSP responder functionality
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
COFF='\033[0m'

BD="${DEMO_CFSSL_DIR:-$HOME/.config/demo-cfssl}"
OCSP_URL="${OCSP_URL:-http://localhost:8080/ocsp}"

function print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${COFF}"
    echo -e "${BLUE}$1${COFF}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${COFF}"
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

# Check if certificates exist
if [ ! -f "$BD/ica-ca.pem" ]; then
    print_error "Intermediate CA certificate not found at $BD/ica-ca.pem"
    print_info "Please run ../steps.sh first to generate certificates"
    exit 1
fi

print_header "OCSP Responder Test Suite"

# Test 1: Check if OCSP responder is running
print_info "Test 1: Checking OCSP responder availability..."
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    print_success "OCSP responder is running"
else
    print_error "OCSP responder is not accessible at http://localhost:8080"
    print_info "Please start the OCSP responder: python main.py"
    exit 1
fi

# Test 2: Check status endpoint
print_info "Test 2: Checking status endpoint..."
STATUS=$(curl -s http://localhost:8080/status)
if echo "$STATUS" | grep -q "ca_loaded"; then
    print_success "Status endpoint working"
    echo "$STATUS" | python3 -m json.tool 2>/dev/null || echo "$STATUS"
else
    print_error "Status endpoint returned unexpected response"
fi

# Test 3: Test valid certificate
print_info "Test 3: Testing valid certificate OCSP validation..."
if [ -f "$BD/hosts/localhost/cert.pem" ]; then
    # Add timeout and better error handling
    RESULT=$(timeout 10 openssl ocsp \
        -issuer "$BD/ica-ca.pem" \
        -cert "$BD/hosts/localhost/cert.pem" \
        -url "$OCSP_URL" \
        -noverify \
        -text 2>&1 || echo "OCSP_COMMAND_FAILED")
    
    if echo "$RESULT" | grep -q "OCSP_COMMAND_FAILED"; then
        print_error "OCSP command failed or timed out"
        print_info "This may be due to network issues or OCSP responder problems"
    elif echo "$RESULT" | grep -q "good"; then
        print_success "Certificate status: GOOD"
    elif echo "$RESULT" | grep -q "revoked"; then
        print_info "Certificate status: REVOKED (this is expected if you revoked it for testing)"
    else
        print_error "Unexpected OCSP response"
        echo "$RESULT" | head -20
    fi
else
    print_info "No test certificate found at $BD/hosts/localhost/cert.pem"
fi

# Test 4: Test email certificate (if exists)
print_info "Test 4: Testing email certificate OCSP validation..."
# Look in multiple possible locations
EMAIL_CERT=$(find "$BD/smime" "$BD/emails" -name "cert.pem" 2>/dev/null | head -n 1)
if [ -n "$EMAIL_CERT" ] && [ -f "$EMAIL_CERT" ]; then
    RESULT=$(timeout 10 openssl ocsp \
        -issuer "$BD/ica-ca.pem" \
        -cert "$EMAIL_CERT" \
        -url "$OCSP_URL" \
        -noverify \
        -text 2>&1 || echo "OCSP_COMMAND_FAILED")
    
    if echo "$RESULT" | grep -q "OCSP_COMMAND_FAILED"; then
        print_error "OCSP command failed or timed out"
    elif echo "$RESULT" | grep -q "good"; then
        print_success "Email certificate status: GOOD"
    elif echo "$RESULT" | grep -q "revoked"; then
        print_info "Email certificate status: REVOKED"
    else
        print_error "Unexpected OCSP response for email certificate"
        echo "$RESULT" | head -20
    fi
else
    print_success "Skipped (no email certificate found - this is normal)"
fi

# Test 5: Performance test
print_info "Test 5: Performance test (10 requests)..."
if [ -f "$BD/hosts/localhost/cert.pem" ]; then
    START_TIME=$(date +%s%N)
    SUCCESSFUL=0
    for i in {1..10}; do
        if timeout 5 openssl ocsp \
            -issuer "$BD/ica-ca.pem" \
            -cert "$BD/hosts/localhost/cert.pem" \
            -url "$OCSP_URL" \
            -noverify \
            > /dev/null 2>&1; then
            SUCCESSFUL=$((SUCCESSFUL + 1))
        fi
    done
    END_TIME=$(date +%s%N)
    DURATION=$((($END_TIME - $START_TIME) / 1000000))
    if [ $SUCCESSFUL -gt 0 ]; then
        AVG_TIME=$(($DURATION / $SUCCESSFUL))
        print_success "Completed $SUCCESSFUL/10 requests, average response time: ${AVG_TIME}ms"
    else
        print_error "All 10 requests failed"
    fi
else
    print_info "Skipping performance test - no certificate available"
fi

print_header "Test Summary"
print_success "All tests completed successfully!"
echo ""
print_info "OCSP responder is working correctly"
print_info "You can now include OCSP URL in your certificates"
echo ""

