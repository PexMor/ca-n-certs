#!/bin/bash
#
# Quick start script for OCSP responder
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
COFF='\033[0m'

BD="${DEMO_CFSSL_DIR:-$HOME/.config/demo-cfssl}"

echo -e "${BLUE}═══════════════════════════════════════════════════════════${COFF}"
echo -e "${BLUE}  OCSP Responder - Quick Start${COFF}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${COFF}"
echo ""

# Check if certificates exist
if [ ! -f "$BD/ica-ca.pem" ]; then
    echo -e "${RED}✗ Certificates not found in $BD${COFF}"
    echo -e "${YELLOW}ℹ Please run the certificate generation script first:${COFF}"
    echo "  cd .. && ./steps.sh"
    exit 1
fi

echo -e "${GREEN}✓ Found certificates in $BD${COFF}"

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo ""
    echo -e "${YELLOW}Virtual environment not found. Creating one...${COFF}"
    
    # Try uv first, fall back to venv
    if command -v uv &> /dev/null; then
        echo -e "${BLUE}Using uv...${COFF}"
        uv venv
        source .venv/bin/activate
        uv pip install -r requirements.txt
    else
        echo -e "${BLUE}Using python venv...${COFF}"
        python3 -m venv .venv
        source .venv/bin/activate
        pip install -r requirements.txt
    fi
    
    echo -e "${GREEN}✓ Virtual environment created and dependencies installed${COFF}"
else
    echo -e "${GREEN}✓ Virtual environment found${COFF}"
    source .venv/bin/activate
    
    # Check if dependencies are installed
    if ! python -c "import fastapi" 2>/dev/null; then
        echo -e "${YELLOW}ℹ Installing dependencies...${COFF}"
        if command -v uv &> /dev/null; then
            uv pip install -r requirements.txt
        else
            pip install -r requirements.txt
        fi
        echo -e "${GREEN}✓ Dependencies installed${COFF}"
    fi
fi

echo ""
echo -e "${BLUE}Starting OCSP Responder...${COFF}"
echo ""
echo -e "${YELLOW}Configuration:${COFF}"
echo "  Certificate Directory: $BD"
echo "  Host: ${OCSP_HOST:-0.0.0.0}"
echo "  Port: ${OCSP_PORT:-8080}"
echo ""
echo -e "${YELLOW}Endpoints:${COFF}"
echo "  http://localhost:${OCSP_PORT:-8080}/ - API documentation"
echo "  http://localhost:${OCSP_PORT:-8080}/health - Health check"
echo "  http://localhost:${OCSP_PORT:-8080}/status - Status and statistics"
echo "  http://localhost:${OCSP_PORT:-8080}/ocsp - OCSP endpoint"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop${COFF}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${COFF}"
echo ""

# Run the OCSP responder
python main.py

