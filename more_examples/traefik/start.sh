#!/bin/bash
#
# start.sh - Easy startup script for Traefik TLS/mTLS demo
#

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
COFF='\033[0m'

BD="${DEMO_CFSSL_DIR:-$HOME/.config/demo-cfssl}"

echo -e "${BLUE}==================================================================${COFF}"
echo -e "${BLUE}  Traefik TLS/mTLS Demo - Startup Script${COFF}"
echo -e "${BLUE}==================================================================${COFF}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${COFF}"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${COFF}"
    exit 1
fi
echo -e "${GREEN}✓ Docker found${COFF}"

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not available${COFF}"
    exit 1
fi
echo -e "${GREEN}✓ Docker Compose found${COFF}"

# Check CA bundle
if [ ! -f "${BD}/ca-bundle-myca.pem" ]; then
    echo -e "${RED}Error: CA bundle not found at ${BD}/ca-bundle-myca.pem${COFF}"
    echo "Please run: cd ../.. && ./build_ca_bundle.sh"
    exit 1
fi
echo -e "${GREEN}✓ CA bundle exists${COFF}"

# Check server certificates
if [ ! -f "${BD}/hosts/localhost/bundle-3.pem" ] || [ ! -f "${BD}/hosts/localhost/key.pem" ]; then
    echo -e "${RED}Error: Server certificates not found${COFF}"
    echo "Please run: cd ../.. && ./steps.sh step03 localhost"
    exit 1
fi
echo -e "${GREEN}✓ Server certificates exist${COFF}"

# Check client certificates (optional)
if [ ! -f "${BD}/tls-clients/john_tls_client/cert.pem" ]; then
    echo -e "${YELLOW}⚠ Client certificate not found (optional)${COFF}"
    echo "  The mTLS endpoint (port 8444) will not work until you create client certificates."
    echo "  Run: cd ../.. && ./steps.sh step_tls_client \"John TLS Client\" john@example.com"
    echo ""
else
    echo -e "${GREEN}✓ Client certificate exists${COFF}"
fi

echo ""
echo -e "${YELLOW}Starting Traefik server...${COFF}"

# Start Docker Compose
docker compose up -d

echo ""
echo -e "${GREEN}✓ Traefik server started successfully!${COFF}"
echo ""
echo -e "${BLUE}==================================================================${COFF}"
echo -e "${BLUE}  Server Information${COFF}"
echo -e "${BLUE}==================================================================${COFF}"
echo ""
echo "Containers: demo-traefik, demo-traefik-files, demo-traefik-files-mtls"
echo ""
echo "Available endpoints:"
echo "  - https://localhost:8443/       → Standard TLS (no client cert)"
echo "  - https://localhost:8444/       → mTLS required (client cert)"
echo "  - https://localhost:8443/health → Health check"
echo "  - https://localhost:8444/health → Health check (mTLS)"
echo "  - http://localhost:8080/        → Dashboard"
echo ""
echo -e "${BLUE}==================================================================${COFF}"
echo -e "${BLUE}  Testing${COFF}"
echo -e "${BLUE}==================================================================${COFF}"
echo ""
echo "Run automated tests:"
echo -e "  ${GREEN}./curlit.sh${COFF}"
echo ""
echo "View dashboard:"
echo -e "  ${GREEN}open http://localhost:8080${COFF}"
echo ""
echo "View logs:"
echo -e "  ${GREEN}docker logs demo-traefik${COFF}"
echo ""
echo "Stop server:"
echo -e "  ${GREEN}docker compose down${COFF}"
echo ""
echo -e "${BLUE}==================================================================${COFF}"
echo ""

# Wait for server to be ready
sleep 3

# Test if server is responding
echo -e "${YELLOW}Testing server health...${COFF}"
if curl -s --cacert "${BD}/ca-bundle-myca.pem" https://localhost:8443/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Server is responding correctly!${COFF}"
    echo ""
    echo -e "${GREEN}Ready to test! Run: ./curlit.sh${COFF}"
else
    echo -e "${YELLOW}⚠ Server may still be starting up...${COFF}"
    echo "Check logs with: docker logs demo-traefik"
fi
echo ""

