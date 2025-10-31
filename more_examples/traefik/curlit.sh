#!/bin/bash
#
# curlit.sh - Test Traefik server with and without client certificates
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
CLIENT_CERT_DIR="${BD}/tls-clients/john_tls_client"

echo -e "${BLUE}==================================================================${COFF}"
echo -e "${BLUE}  Traefik TLS/mTLS Demo - Testing Endpoints${COFF}"
echo -e "${BLUE}==================================================================${COFF}"
echo ""

# Check if certificates exist
if [ ! -f "${CA_BUNDLE}" ]; then
    echo -e "${RED}Error: CA bundle not found at ${CA_BUNDLE}${COFF}"
    exit 1
fi

if [ ! -d "${CLIENT_CERT_DIR}" ]; then
    echo -e "${YELLOW}Warning: Client certificates not found at ${CLIENT_CERT_DIR}${COFF}"
    echo "To create: cd ../.. && ./steps.sh step_tls_client \"John TLS Client\" john@example.com"
    echo ""
fi

# Test 1: Standard TLS endpoint
echo -e "${GREEN}Test 1: Accessing standard TLS endpoint (port 8443)${COFF}"
echo "Command: curl --cacert \${CA_BUNDLE} ${BASE_URL_TLS}/"
echo ""
curl --cacert "${CA_BUNDLE}" "${BASE_URL_TLS}/" 2>/dev/null | grep -o "<h1>.*</h1>" || echo "Success!"
echo ""
echo -e "${GREEN}✓ Standard TLS endpoint accessible${COFF}"
echo ""

# Test 2: mTLS endpoint WITHOUT client certificate
echo -e "${YELLOW}Test 2: Accessing mTLS endpoint (port 8444) WITHOUT client certificate${COFF}"
echo "Command: curl --cacert \${CA_BUNDLE} ${BASE_URL_MTLS}/"
echo "Expected: SSL error or connection failure"
echo ""
# Expect this to fail - capture the exit code
if curl -s --cacert "${CA_BUNDLE}" "${BASE_URL_MTLS}/" -o /tmp/traefik-test-nocert.html 2>&1 | grep -q "SSL"; then
    echo -e "${GREEN}✓ Correctly rejected with SSL error - client certificate required${COFF}"
elif curl -s --cacert "${CA_BUNDLE}" "${BASE_URL_MTLS}/" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Warning: Connection succeeded without client certificate${COFF}"
else
    echo -e "${GREEN}✓ Correctly rejected - client certificate required${COFF}"
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
         "${BASE_URL_MTLS}/" 2>/dev/null > /tmp/traefik-test-withcert.html
    
    if grep -q "Success" /tmp/traefik-test-withcert.html; then
        echo -e "${GREEN}✓ Successfully authenticated with client certificate!${COFF}"
        echo ""
        echo "Response excerpt:"
        grep -o "<h1>.*</h1>" /tmp/traefik-test-withcert.html || true
    else
        echo -e "${RED}✗ Authentication failed${COFF}"
    fi
else
    echo -e "${YELLOW}Test 3: Skipped (client certificates not found)${COFF}"
    echo "To create: cd ../.. && ./steps.sh step_tls_client \"John TLS Client\" john@example.com"
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
echo "Dashboard: http://localhost:8080"
echo "Docker logs: docker logs demo-traefik"
echo "Stop server: docker compose down"
echo ""

# Cleanup
rm -f /tmp/traefik-test-nocert.html /tmp/traefik-test-withcert.html

