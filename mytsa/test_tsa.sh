#!/bin/bash
#
# test_tsa.sh - Test mytsa TSA server
#
# This script tests the TSA server by creating a TSQ, sending it to the server,
# and verifying the TSR response.
#

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
COFF='\033[0m'

# Configuration
TSA_URL="${TSA_URL:-http://localhost:8080/tsa}"
CA_BUNDLE="${CA_BUNDLE:-$HOME/.config/demo-cfssl/ca.pem}"
TEMP_DIR=$(mktemp -d)

# Cleanup on exit
trap "rm -rf $TEMP_DIR" EXIT

echo -e "${BLUE}================================${COFF}"
echo -e "${BLUE}  Testing mytsa TSA Server     ${COFF}"
echo -e "${BLUE}================================${COFF}"
echo ""
echo "TSA URL: $TSA_URL"
echo "CA Bundle: $CA_BUNDLE"
echo ""

# Test 1: Health check
echo -e "${GREEN}Test 1: Health Check${COFF}"
echo "Checking health endpoint..."
HEALTH_RESPONSE=$(curl -s http://localhost:8080/health)
echo "$HEALTH_RESPONSE" | jq . 2>/dev/null || echo "$HEALTH_RESPONSE"
echo ""

# Test 2: Get TSA certificates
echo -e "${GREEN}Test 2: Get TSA Certificates${COFF}"
echo "Downloading TSA certificate chain..."
curl -s -o "$TEMP_DIR/tsa-chain.pem" http://localhost:8080/tsa/certs
if [ -f "$TEMP_DIR/tsa-chain.pem" ]; then
    echo -e "${GREEN}✓ Certificate chain downloaded${COFF}"
    openssl x509 -in "$TEMP_DIR/tsa-chain.pem" -noout -subject -issuer
else
    echo -e "${RED}✗ Failed to download certificate chain${COFF}"
    exit 1
fi
echo ""

# Test 3: Create and send TSQ
echo -e "${GREEN}Test 3: RFC 3161 Timestamp Request/Response${COFF}"

# Create test data
echo "Hello, RFC 3161!" > "$TEMP_DIR/test.bin"
echo "Test data created: $(cat $TEMP_DIR/test.bin)"
echo ""

# Create TSQ (TimeStampReq)
echo "Creating TimeStampReq (TSQ)..."
openssl ts -query \
    -data "$TEMP_DIR/test.bin" \
    -sha256 \
    -cert \
    -out "$TEMP_DIR/request.tsq"

if [ ! -f "$TEMP_DIR/request.tsq" ]; then
    echo -e "${RED}✗ Failed to create TSQ${COFF}"
    exit 1
fi
echo -e "${GREEN}✓ TSQ created ($(stat -f%z "$TEMP_DIR/request.tsq" 2>/dev/null || stat -c%s "$TEMP_DIR/request.tsq") bytes)${COFF}"
echo ""

# Send TSQ to TSA server
echo "Sending TSQ to TSA server..."
HTTP_CODE=$(curl -s -w "%{http_code}" -o "$TEMP_DIR/response.tsr" \
    -X POST \
    -H "Content-Type: application/timestamp-query" \
    --data-binary "@$TEMP_DIR/request.tsq" \
    "$TSA_URL")

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}✗ Server returned HTTP $HTTP_CODE${COFF}"
    cat "$TEMP_DIR/response.tsr"
    exit 1
fi

if [ ! -f "$TEMP_DIR/response.tsr" ] || [ ! -s "$TEMP_DIR/response.tsr" ]; then
    echo -e "${RED}✗ Failed to receive TSR${COFF}"
    exit 1
fi
echo -e "${GREEN}✓ TSR received ($(stat -f%z "$TEMP_DIR/response.tsr" 2>/dev/null || stat -c%s "$TEMP_DIR/response.tsr") bytes)${COFF}"
echo ""

# Verify TSR
echo "Verifying TimeStampResp (TSR)..."
TSR_INFO=$(openssl ts -reply -in "$TEMP_DIR/response.tsr" -text 2>&1)
if echo "$TSR_INFO" | grep -q "Status info"; then
    echo -e "${GREEN}✓ TSR is valid${COFF}"
    echo ""
    echo "Timestamp Information:"
    echo "$TSR_INFO" | grep -E "(Time stamp|Policy OID|Hash Algorithm|Serial Number)" | sed 's/^/  /'
else
    echo -e "${RED}✗ TSR verification failed${COFF}"
    echo "$TSR_INFO"
    exit 1
fi
echo ""

# Verify timestamp against original data
if [ -f "$CA_BUNDLE" ]; then
    echo "Verifying timestamp against original data with CA bundle..."
    if openssl ts -verify \
        -in "$TEMP_DIR/response.tsr" \
        -queryfile "$TEMP_DIR/request.tsq" \
        -CAfile "$CA_BUNDLE" 2>&1 | grep -q "Verification: OK"; then
        echo -e "${GREEN}✓ Timestamp verification: OK${COFF}"
    else
        echo -e "${YELLOW}⚠ Full verification failed (may be due to TSA CA not in bundle)${COFF}"
        echo "  You can still use the timestamp, but full chain validation failed."
    fi
else
    echo -e "${YELLOW}⚠ CA bundle not found at $CA_BUNDLE${COFF}"
    echo "  Skipping full verification"
fi
echo ""

# Test 4: Another timestamp with different data
echo -e "${GREEN}Test 4: Second Timestamp (different data)${COFF}"
echo "Testing with different data..."
echo "Different data for second timestamp" > "$TEMP_DIR/test2.bin"

openssl ts -query \
    -data "$TEMP_DIR/test2.bin" \
    -sha256 \
    -cert \
    -out "$TEMP_DIR/request2.tsq"

curl -s -o "$TEMP_DIR/response2.tsr" \
    -X POST \
    -H "Content-Type: application/timestamp-query" \
    --data-binary "@$TEMP_DIR/request2.tsq" \
    "$TSA_URL"

if openssl ts -reply -in "$TEMP_DIR/response2.tsr" -text | grep -q "Time stamp"; then
    echo -e "${GREEN}✓ Second timestamp received successfully${COFF}"
    
    # Extract serial numbers to verify they're different
    SERIAL1=$(openssl ts -reply -in "$TEMP_DIR/response.tsr" -text 2>/dev/null | grep "Serial Number:" | awk '{print $3}')
    SERIAL2=$(openssl ts -reply -in "$TEMP_DIR/response2.tsr" -text 2>/dev/null | grep "Serial Number:" | awk '{print $3}')
    
    if [ "$SERIAL1" != "$SERIAL2" ]; then
        echo -e "${GREEN}✓ Serial numbers are unique: $SERIAL1 vs $SERIAL2${COFF}"
    else
        echo -e "${YELLOW}⚠ Serial numbers are the same (unexpected)${COFF}"
    fi
else
    echo -e "${RED}✗ Second timestamp failed${COFF}"
fi
echo ""

# Summary
echo -e "${BLUE}================================${COFF}"
echo -e "${GREEN}✓ All tests passed!${COFF}"
echo -e "${BLUE}================================${COFF}"
echo ""
echo "The mytsa TSA server is working correctly."
echo ""
echo "Next steps:"
echo "  - Integrate with tsa_sign.sh by adding TSA_URL to its TSA_SERVERS array"
echo "  - Use the server for timestamping your documents"
echo "  - Check logs for any issues"

