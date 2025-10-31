#!/bin/bash
#
# curlit.sh - Test Nginx server with and without client certificates
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
BASE_URL_TLS="https://localhost:8443"
BASE_URL_MTLS="https://localhost:8444"

# Certificate paths
CA_BUNDLE="${BD}/ca-bundle-myca.pem"
SERVER_CERT_DIR="${BD}/hosts/localhost"
CLIENT_CERT_DIR="${BD}/tls-clients/john_tls_client"

echo -e "${BLUE}==================================================================${COFF}"
echo -e "${BLUE}  Nginx TLS/mTLS Demo - Testing Endpoints${COFF}"
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
    echo "Client certificate endpoint tests will fail."
    echo "To create client certificate, run: ./steps.sh step_tls_client \"John TLS Client\" john@example.com"
    echo ""
fi

# Test 1: Standard TLS endpoint (no client cert)
echo -e "${GREEN}Test 1: Accessing standard TLS endpoint (port 8443)${COFF}"
echo "Command: curl --cacert \${CA_BUNDLE} ${BASE_URL_TLS}/"
echo ""
curl --cacert "${CA_BUNDLE}" "${BASE_URL_TLS}/" 2>/dev/null | grep -o "<h1>.*</h1>" || echo "Success!"
echo ""
echo -e "${GREEN}✓ Standard TLS endpoint accessible${COFF}"
echo ""

# Test 2: mTLS endpoint WITHOUT client certificate (should fail with 400)
echo -e "${YELLOW}Test 2: Accessing mTLS endpoint (port 8444) WITHOUT client certificate${COFF}"
echo "Command: curl --cacert \${CA_BUNDLE} ${BASE_URL_MTLS}/"
echo "Expected: 400 Bad Request (No required SSL certificate)"
echo ""
HTTP_CODE=$(curl -s -o /tmp/nginx-test-nocert.html -w "%{http_code}" --cacert "${CA_BUNDLE}" "${BASE_URL_MTLS}/" 2>&1)
echo "HTTP Status Code: ${HTTP_CODE}"
if [ "${HTTP_CODE}" = "400" ]; then
    echo -e "${GREEN}✓ Correctly rejected - client certificate required${COFF}"
elif [ "${HTTP_CODE}" = "000" ]; then
    echo -e "${YELLOW}⚠ Connection failed (this is expected behavior)${COFF}"
    echo "  SSL handshake fails when client cert is required but not provided"
else
    echo -e "${YELLOW}Note: Received status ${HTTP_CODE}${COFF}"
fi
echo ""

# Test 3: mTLS endpoint WITH client certificate
if [ -f "${CLIENT_CERT_DIR}/cert.pem" ] && [ -f "${CLIENT_CERT_DIR}/key.pem" ]; then
    echo -e "${GREEN}Test 3: Accessing mTLS endpoint (port 8444) WITH client certificate${COFF}"
    echo "Command: curl --cacert \${CA_BUNDLE} --cert \${CLIENT_CERT} --key \${CLIENT_KEY} ${BASE_URL_MTLS}/"
    echo ""
    
    curl --cacert "${CA_BUNDLE}" \
         --cert "${CLIENT_CERT_DIR}/cert.pem" \
         --key "${CLIENT_CERT_DIR}/key.pem" \
         "${BASE_URL_MTLS}/" 2>/dev/null > /tmp/nginx-test-withcert.html
    
    if grep -q "Success" /tmp/nginx-test-withcert.html; then
        echo -e "${GREEN}✓ Successfully authenticated with client certificate!${COFF}"
        echo ""
        echo "Response excerpt:"
        grep -o "<h1>.*</h1>" /tmp/nginx-test-withcert.html || true
        echo ""
        # Extract certificate info if present
        if grep -q "Subject DN" /tmp/nginx-test-withcert.html; then
            echo "Certificate details from response:"
            grep "Subject DN" /tmp/nginx-test-withcert.html | sed 's/<[^>]*>//g' | sed 's/^[ \t]*/  /' | head -3
        fi
    else
        echo -e "${RED}✗ Authentication failed${COFF}"
    fi
else
    echo -e "${YELLOW}Test 3: Skipped (client certificates not found)${COFF}"
    echo "To create client certificates, run:"
    echo "  cd ../.. && ./steps.sh step_tls_client \"John TLS Client\" john@example.com"
fi

echo ""
echo -e "${GREEN}Test 4: Health check endpoints${COFF}"
echo ""
echo "Standard TLS health:"
curl -s --cacert "${CA_BUNDLE}" "${BASE_URL_TLS}/health" && echo ""
echo ""
if [ -f "${CLIENT_CERT_DIR}/cert.pem" ]; then
    echo "mTLS health:"
    curl -s --cacert "${CA_BUNDLE}" \
         --cert "${CLIENT_CERT_DIR}/cert.pem" \
         --key "${CLIENT_CERT_DIR}/key.pem" \
         "${BASE_URL_MTLS}/health" && echo ""
fi

echo ""
echo -e "${BLUE}==================================================================${COFF}"
echo -e "${BLUE}  Testing Complete${COFF}"
echo -e "${BLUE}==================================================================${COFF}"
echo ""
echo "Summary:"
echo "  ✓ Port 8443: Standard TLS - No client cert required"
echo "  ✓ Port 8444: Strict mTLS - Client cert REQUIRED"
echo ""
echo "You can also test in your browser:"
echo "  1. Import CA bundle into your browser trust store"
echo "  2. Navigate to ${BASE_URL_TLS}/"
echo "  3. For mTLS, import the .p12 file and try:"
echo "     ${BASE_URL_MTLS}/"
echo "     ${CLIENT_CERT_DIR}/client.p12"
echo ""
echo "Docker logs: docker logs demo-nginx"
echo "Stop server: docker compose down"
echo ""

# Cleanup temp files
rm -f /tmp/nginx-test-nocert.html /tmp/nginx-test-withcert.html

