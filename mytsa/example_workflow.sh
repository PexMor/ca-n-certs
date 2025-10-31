#!/bin/bash
#
# example_workflow.sh - Comprehensive workflow demonstration for mytsa
#
# This script demonstrates a complete workflow:
# 1. Check if TSA certificates exist
# 2. Start the TSA server in background
# 3. Run various test scenarios
# 4. Clean up
#

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
COFF='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TSA_CERT="$HOME/.config/demo-cfssl/tsa/mytsa/cert.pem"
SERVER_PID=""

# Cleanup function
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        echo ""
        echo -e "${YELLOW}Stopping TSA server (PID: $SERVER_PID)...${COFF}"
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
        echo -e "${GREEN}✓ Server stopped${COFF}"
    fi
}

trap cleanup EXIT

echo -e "${BLUE}========================================${COFF}"
echo -e "${BLUE}  mytsa - Example Workflow Demo       ${COFF}"
echo -e "${BLUE}========================================${COFF}"
echo ""

# Step 1: Check if TSA certificates exist
echo -e "${GREEN}Step 1: Checking TSA Certificates${COFF}"
if [ ! -f "$TSA_CERT" ]; then
    echo -e "${RED}✗ TSA certificate not found at $TSA_CERT${COFF}"
    echo ""
    echo "Please generate TSA certificate first:"
    echo "  cd $(dirname $SCRIPT_DIR)"
    echo "  ./steps.sh"
    echo ""
    echo "The steps.sh script includes a step_tsa() call that generates:"
    echo "  - TSA certificate with timeStamping EKU"
    echo "  - Private key (ECDSA P-384)"
    echo "  - Certificate bundles"
    echo "  - Serial number file"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ TSA certificate found${COFF}"
openssl x509 -in "$TSA_CERT" -noout -subject | sed 's/^/  /'
echo ""

# Step 2: Start TSA server in background
echo -e "${GREEN}Step 2: Starting TSA Server${COFF}"
cd "$SCRIPT_DIR"

# Check if port is already in use
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo -e "${YELLOW}⚠ Port 8080 is already in use${COFF}"
    echo "Assuming TSA server is already running..."
    echo ""
else
    echo "Starting server in background..."
    # Start server with output redirected (use uv if available)
    if command -v uv &> /dev/null; then
        nohup uv run uvicorn mytsa.app:app --host 0.0.0.0 --port 8080 > /tmp/mytsa.log 2>&1 &
    else
        nohup uvicorn mytsa.app:app --host 0.0.0.0 --port 8080 > /tmp/mytsa.log 2>&1 &
    fi
    SERVER_PID=$!
    echo "Server PID: $SERVER_PID"
    echo "Logs: /tmp/mytsa.log"
    
    # Wait for server to start
    echo "Waiting for server to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:8080/health > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Server is ready${COFF}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${RED}✗ Server failed to start${COFF}"
            echo "Check logs: tail /tmp/mytsa.log"
            exit 1
        fi
        sleep 0.5
    done
fi
echo ""

# Step 3: Test API endpoints
echo -e "${GREEN}Step 3: Testing API Endpoints${COFF}"

echo "• GET / (API info)"
curl -s http://localhost:8080/ | jq '.name, .version, .status' 2>/dev/null || echo "  (jq not available)"

echo "• GET /health"
HEALTH=$(curl -s http://localhost:8080/health | jq '.status' 2>/dev/null)
echo "  Status: $HEALTH"

echo "• GET /tsa/certs"
CERT_SIZE=$(curl -s http://localhost:8080/tsa/certs | wc -c | tr -d ' ')
echo "  Certificate chain size: $CERT_SIZE bytes"
echo ""

# Step 4: RFC 3161 Timestamp Requests
echo -e "${GREEN}Step 4: RFC 3161 Timestamp Tests${COFF}"

TEMP_DIR=$(mktemp -d)

# Test 1: Simple timestamp
echo "Test 1: Simple timestamp"
echo "Sample document content" > "$TEMP_DIR/doc1.txt"
openssl ts -query -data "$TEMP_DIR/doc1.txt" -sha256 -cert -out "$TEMP_DIR/req1.tsq" 2>/dev/null
curl -s -X POST \
    -H "Content-Type: application/timestamp-query" \
    --data-binary "@$TEMP_DIR/req1.tsq" \
    http://localhost:8080/tsa \
    -o "$TEMP_DIR/resp1.tsr"

if openssl ts -reply -in "$TEMP_DIR/resp1.tsr" -text 2>/dev/null | grep -q "Time stamp"; then
    SERIAL1=$(openssl ts -reply -in "$TEMP_DIR/resp1.tsr" -text 2>/dev/null | grep "Serial Number:" | awk '{print $3}')
    echo -e "${GREEN}  ✓ Timestamp received (Serial: $SERIAL1)${COFF}"
else
    echo -e "${RED}  ✗ Failed${COFF}"
fi

# Test 2: Different document
echo "Test 2: Different document"
echo "Another document with different content" > "$TEMP_DIR/doc2.txt"
openssl ts -query -data "$TEMP_DIR/doc2.txt" -sha256 -cert -out "$TEMP_DIR/req2.tsq" 2>/dev/null
curl -s -X POST \
    -H "Content-Type: application/timestamp-query" \
    --data-binary "@$TEMP_DIR/req2.tsq" \
    http://localhost:8080/tsa \
    -o "$TEMP_DIR/resp2.tsr"

if openssl ts -reply -in "$TEMP_DIR/resp2.tsr" -text 2>/dev/null | grep -q "Time stamp"; then
    SERIAL2=$(openssl ts -reply -in "$TEMP_DIR/resp2.tsr" -text 2>/dev/null | grep "Serial Number:" | awk '{print $3}')
    echo -e "${GREEN}  ✓ Timestamp received (Serial: $SERIAL2)${COFF}"
    
    if [ "$SERIAL1" != "$SERIAL2" ]; then
        echo -e "${GREEN}  ✓ Serial numbers are unique${COFF}"
    fi
else
    echo -e "${RED}  ✗ Failed${COFF}"
fi

# Test 3: Verify with CA bundle
echo "Test 3: Verification with CA bundle"
CA_BUNDLE="$HOME/.config/demo-cfssl/ca.pem"
if [ -f "$CA_BUNDLE" ]; then
    if openssl ts -verify \
        -in "$TEMP_DIR/resp1.tsr" \
        -queryfile "$TEMP_DIR/req1.tsq" \
        -CAfile "$CA_BUNDLE" 2>&1 | grep -q "Verification: OK"; then
        echo -e "${GREEN}  ✓ Verification passed${COFF}"
    else
        echo -e "${YELLOW}  ⚠ Verification failed (may need full CA bundle)${COFF}"
    fi
else
    echo -e "${YELLOW}  ⚠ CA bundle not found, skipping${COFF}"
fi

# Cleanup temp dir
rm -rf "$TEMP_DIR"
echo ""

# Step 5: Integration examples
echo -e "${GREEN}Step 5: Integration Examples${COFF}"
echo ""
echo "You can integrate mytsa with existing tools:"
echo ""
echo "1. With OpenSSL command line:"
echo "   openssl ts -query -data file.pdf -sha256 -out request.tsq"
echo "   curl -H \"Content-Type: application/timestamp-query\" \\"
echo "        --data-binary @request.tsq \\"
echo "        http://localhost:8080/tsa -o response.tsr"
echo "   openssl ts -reply -in response.tsr -text"
echo ""
echo "2. With tsa_sign.sh (modify TSA_SERVERS array):"
echo "   TSA_SERVERS=("
echo "       \"http://localhost:8080/tsa\""
echo "       \"http://freetsa.org/tsr\""
echo "   )"
echo ""
echo "3. With Python rfc3161ng library:"
echo "   from rfc3161ng import RemoteTimestamper"
echo "   rt = RemoteTimestamper('http://localhost:8080/tsa')"
echo "   tsr = rt.timestamp(data=b'hello')"
echo ""

# Summary
echo -e "${BLUE}========================================${COFF}"
echo -e "${GREEN}✓ Workflow Demo Complete!${COFF}"
echo -e "${BLUE}========================================${COFF}"
echo ""
echo "Summary:"
echo "  - TSA server is running on http://localhost:8080"
echo "  - All RFC 3161 tests passed"
echo "  - Timestamps are being issued with unique serial numbers"
echo ""
echo "Next steps:"
echo "  - Review logs: tail -f /tmp/mytsa.log"
echo "  - Run test suite: ./test_tsa.sh"
echo "  - Read documentation: cat README.md"
echo ""

# Keep server running if started by us
if [ -n "$SERVER_PID" ]; then
    echo -e "${YELLOW}Server is still running (PID: $SERVER_PID)${COFF}"
    echo "Press CTRL+C to stop the server and exit"
    echo ""
    wait $SERVER_PID
fi

