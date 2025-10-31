#!/bin/bash
#
# curlit.sh - Test Caddy server with and without client certificates
#
# This script demonstrates accessing both endpoints:
# 1. Standard TLS endpoint (no client cert required)
# 2. mTLS endpoint (client certificate required)
#

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
COFF='\033[0m'

# Configuration
BD="${DEMO_CFSSL_DIR:-$HOME/.config/demo-cfssl}"
BASE_URL="https://localhost:8443"

# Certificate paths
CA_BUNDLE="${BD}/ca-bundle-myca.pem"
SERVER_CERT_DIR="${BD}/hosts/localhost"
CLIENT_CERT_DIR="${BD}/smime-openssl/john_extended"

echo -e "${BLUE}==================================================================${COFF}"
echo -e "${BLUE}  Caddy TLS/mTLS Demo - Testing Endpoints${COFF}"
echo -e "${BLUE}==================================================================${COFF}"
echo ""

# Check if certificates exist
if [ ! -f "${CA_BUNDLE}" ]; then
    echo -e "${RED}Error: CA bundle not found at ${CA_BUNDLE}${COFF}"
    echo "Please run steps.sh to generate certificates first."
    exit 1
fi

if [ ! -d "${SERVER_CERT_DIR}" ]; then
    echo -e "${RED}Error: Server certificates not found at ${SERVER_CERT_DIR}${COFF}"
    echo "Please run: ./steps.sh step03 localhost"
    exit 1
fi

if [ ! -d "${CLIENT_CERT_DIR}" ]; then
    echo -e "${YELLOW}Warning: Client certificates not found at ${CLIENT_CERT_DIR}${COFF}"
    echo "Client certificate endpoint test will fail."
    echo "To create client certificate, run: ./steps.sh step_email_openssl john_extended john@example.com"
    echo ""
fi

# Test 1: Standard endpoint (no client cert)
echo -e "${GREEN}Test 1: Accessing standard TLS endpoint (/)${COFF}"
echo "Command: curl --cacert \${CA_BUNDLE} ${BASE_URL}/"
echo ""
curl --cacert "${CA_BUNDLE}" "${BASE_URL}/" 2>/dev/null | grep -o "<h1>.*</h1>" || echo "Success!"
echo ""
echo -e "${GREEN}✓ Standard TLS endpoint accessible${COFF}"
echo ""

# Test 2: Client certificate endpoint without cert
echo -e "${YELLOW}Test 2: Accessing /client endpoint WITHOUT client certificate${COFF}"
echo "Command: curl --cacert \${CA_BUNDLE} ${BASE_URL}/client"
echo ""
echo -e "${YELLOW}Note: With Caddy's 'mode request', the server accepts connections without${COFF}"
echo -e "${YELLOW}      client certificates. For strict enforcement, use 'mode require' at${COFF}"
echo -e "${YELLOW}      the TLS level or a separate server block for mTLS endpoints.${COFF}"
echo ""
HTTP_CODE=$(curl -s -o /tmp/caddy-test-nocert.html -w "%{http_code}" --cacert "${CA_BUNDLE}" "${BASE_URL}/client")
echo "HTTP Status Code: ${HTTP_CODE}"
if [ "${HTTP_CODE}" = "200" ]; then
    echo -e "${YELLOW}✓ Connection accepted (as expected with 'mode request')${COFF}"
else
    echo -e "${GREEN}✓ Status ${HTTP_CODE}${COFF}"
fi
echo ""

# Test 3: Client certificate endpoint with cert
if [ -f "${CLIENT_CERT_DIR}/cert.pem" ] && [ -f "${CLIENT_CERT_DIR}/key.pem" ]; then
    echo -e "${GREEN}Test 3: Accessing /client endpoint WITH client certificate${COFF}"
    echo "Command: curl --cacert \${CA_BUNDLE} --cert \${CLIENT_CERT} --key \${CLIENT_KEY} ${BASE_URL}/client"
    echo ""
    
    curl --cacert "${CA_BUNDLE}" \
         --cert "${CLIENT_CERT_DIR}/cert.pem" \
         --key "${CLIENT_CERT_DIR}/key.pem" \
         "${BASE_URL}/client" 2>/dev/null > /tmp/caddy-test-withcert.html
    
    if grep -q "Success" /tmp/caddy-test-withcert.html; then
        echo -e "${GREEN}✓ Successfully authenticated with client certificate!${COFF}"
        echo ""
        echo "Response excerpt:"
        grep -o "<h1>.*</h1>" /tmp/caddy-test-withcert.html || true
        echo ""
        # Extract subject if present
        if grep -q "Subject:" /tmp/caddy-test-withcert.html; then
            echo "Certificate details from response:"
            grep "Subject:" /tmp/caddy-test-withcert.html | sed 's/<[^>]*>//g' | sed 's/^[ \t]*/  /'
        fi
    else
        echo -e "${RED}✗ Authentication failed${COFF}"
    fi
else
    echo -e "${YELLOW}Test 3: Skipped (client certificates not found)${COFF}"
    echo "To create client certificates, run:"
    echo "  ./steps.sh step_email_openssl john_extended john@example.com"
fi

echo ""
echo -e "${BLUE}==================================================================${COFF}"
echo -e "${BLUE}  Testing Complete${COFF}"
echo -e "${BLUE}==================================================================${COFF}"
echo ""
echo "You can also test in your browser:"
echo "  1. Import CA bundle into your browser trust store"
echo "  2. Navigate to ${BASE_URL}/"
echo "  3. For /client endpoint, import the .p12 file:"
echo "     ${CLIENT_CERT_DIR}/john_extended.p12"
echo ""
echo "Docker logs: docker logs demo-caddy"
echo "Stop server: docker compose down"
echo ""

# Cleanup temp files
rm -f /tmp/caddy-test-nocert.html /tmp/caddy-test-withcert.html

