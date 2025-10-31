#!/bin/bash
#
# integrate_with_tsa_sign.sh - Helper to integrate mytsa with tsa_sign.sh
#
# This script helps configure tsa_sign.sh to use the local mytsa server
#

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
COFF='\033[0m'

TSA_SIGN_PATH="../tsa_sign.sh"
LOCAL_TSA_URL="http://localhost:8080/tsa"

echo -e "${BLUE}========================================${COFF}"
echo -e "${BLUE}  mytsa Integration with tsa_sign.sh  ${COFF}"
echo -e "${BLUE}========================================${COFF}"
echo ""

# Check if tsa_sign.sh exists
if [ ! -f "$TSA_SIGN_PATH" ]; then
    echo -e "${YELLOW}Warning: tsa_sign.sh not found at $TSA_SIGN_PATH${COFF}"
    echo ""
    echo "Please ensure you're running this from the mytsa directory"
    echo "and that tsa_sign.sh exists in the parent directory."
    exit 1
fi

echo "Found tsa_sign.sh at: $TSA_SIGN_PATH"
echo ""

# Check if mytsa server is running
echo "Checking if mytsa server is running..."
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ mytsa server is running on port 8080${COFF}"
else
    echo -e "${YELLOW}⚠ mytsa server is not running${COFF}"
    echo ""
    echo "Please start the server first:"
    echo "  cd mytsa"
    echo "  ./start.sh"
    echo ""
    echo "Then run this script again."
    exit 1
fi
echo ""

# Check current TSA_SERVERS in tsa_sign.sh
echo "Checking current TSA_SERVERS configuration..."
if grep -q "http://localhost:8080/tsa" "$TSA_SIGN_PATH"; then
    echo -e "${GREEN}✓ Local TSA already configured in tsa_sign.sh${COFF}"
    echo ""
    echo "Your tsa_sign.sh is already set up to use mytsa!"
else
    echo -e "${YELLOW}Local TSA not found in tsa_sign.sh${COFF}"
    echo ""
    echo "To add it, edit $TSA_SIGN_PATH and modify the TSA_SERVERS array:"
    echo ""
    echo -e "${BLUE}# Add this line at the beginning of TSA_SERVERS array:${COFF}"
    echo "TSA_SERVERS=("
    echo "    \"http://localhost:8080/tsa\"    # Local mytsa server"
    echo "    \"http://freetsa.org/tsr\""
    echo "    \"http://timestamp.sectigo.com\""
    echo "    \"http://timestamp.digicert.com\""
    echo ")"
    echo ""
    echo "This will make tsa_sign.sh try your local server first,"
    echo "and fall back to public TSA servers if needed."
fi
echo ""

# Test integration
echo "Testing integration..."
echo ""

# Create test file
TEST_FILE=$(mktemp)
echo "Test document content" > "$TEST_FILE"
echo "Created test file: $TEST_FILE"

# Check if we have a test certificate
TEST_CERT="$HOME/.config/demo-cfssl/smime-openssl/john_extended/email.p12"
if [ ! -f "$TEST_CERT" ]; then
    # Try to find any .p12 file
    TEST_CERT=$(find "$HOME/.config/demo-cfssl" -name "*.p12" | head -1)
fi

if [ -f "$TEST_CERT" ]; then
    echo "Using test certificate: $TEST_CERT"
    echo ""
    echo "Running: $TSA_SIGN_PATH --p12 $TEST_CERT $TEST_FILE"
    echo ""
    
    # Run tsa_sign.sh
    if "$TSA_SIGN_PATH" --p12 "$TEST_CERT" "$TEST_FILE" 2>&1 | grep -q "localhost:8080"; then
        echo ""
        echo -e "${GREEN}✓ Integration successful!${COFF}"
        echo "  Your local mytsa server was used for timestamping"
    else
        echo ""
        echo -e "${YELLOW}Note: tsa_sign.sh completed but may have used a different TSA${COFF}"
        echo "  Check the output above to see which TSA was used"
    fi
    
    # Cleanup
    rm -f "$TEST_FILE" "${TEST_FILE}.sign_tsa" "${TEST_FILE}.sign_tsa.tsr"
else
    echo -e "${YELLOW}No test certificate found${COFF}"
    echo "Skipping tsa_sign.sh test"
    echo ""
    echo "To test manually:"
    echo "  $TSA_SIGN_PATH --p12 your-cert.p12 document.pdf"
fi
echo ""

# Summary
echo -e "${BLUE}========================================${COFF}"
echo -e "${GREEN}Integration Guide Summary${COFF}"
echo -e "${BLUE}========================================${COFF}"
echo ""
echo "To use mytsa with tsa_sign.sh:"
echo ""
echo "1. Start mytsa server:"
echo "   cd mytsa && ./start.sh"
echo ""
echo "2. Edit tsa_sign.sh to add local TSA first in TSA_SERVERS array"
echo ""
echo "3. Use tsa_sign.sh as normal:"
echo "   ./tsa_sign.sh --p12 cert.p12 document.pdf"
echo ""
echo "Benefits:"
echo "  ✓ Fast (local server, no network latency)"
echo "  ✓ Reliable (no dependency on external services)"
echo "  ✓ Private (timestamps stay on your network)"
echo "  ✓ Free (no rate limits or costs)"
echo ""
echo "Your timestamps will be trusted if you distribute the CA bundle"
echo "from ~/.config/demo-cfssl/ to verifying parties."

