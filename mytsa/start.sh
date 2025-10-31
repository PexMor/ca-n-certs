#!/bin/bash
#
# start.sh - Launch mytsa TSA server
#
# This script starts the mytsa Time Stamp Authority server with default configuration.
# You can override settings using environment variables.
#

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
COFF='\033[0m'

# Default configuration
DEFAULT_BASE="$HOME/.config/demo-cfssl/tsa/mytsa"
TSA_CERT_PATH="${TSA_CERT_PATH:-$DEFAULT_BASE/cert.pem}"
TSA_KEY_PATH="${TSA_KEY_PATH:-$DEFAULT_BASE/key.pem}"
TSA_CHAIN_PATH="${TSA_CHAIN_PATH:-$DEFAULT_BASE/bundle-3.pem}"
TSA_SERIAL_PATH="${TSA_SERIAL_PATH:-$DEFAULT_BASE/tsaserial.txt}"
TSA_POLICY_OID="${TSA_POLICY_OID:-1.3.6.1.4.1.13762.3}"
TSA_ACCURACY_SECONDS="${TSA_ACCURACY_SECONDS:-1}"

# Server configuration
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
RELOAD="${RELOAD:-}"

# Export environment variables
export TSA_CERT_PATH
export TSA_KEY_PATH
export TSA_CHAIN_PATH
export TSA_SERIAL_PATH
export TSA_POLICY_OID
export TSA_ACCURACY_SECONDS

echo -e "${BLUE}================================${COFF}"
echo -e "${BLUE}  mytsa - RFC 3161 TSA Server  ${COFF}"
echo -e "${BLUE}================================${COFF}"
echo ""
echo -e "${GREEN}Configuration:${COFF}"
echo "  TSA Certificate: $TSA_CERT_PATH"
echo "  TSA Private Key: $TSA_KEY_PATH"
echo "  Certificate Chain: $TSA_CHAIN_PATH"
echo "  Serial Number File: $TSA_SERIAL_PATH"
echo "  Policy OID: $TSA_POLICY_OID"
echo "  Accuracy: $TSA_ACCURACY_SECONDS seconds"
echo ""
echo -e "${GREEN}Server:${COFF}"
echo "  Host: $HOST"
echo "  Port: $PORT"
echo ""

# Check if certificates exist
if [ ! -f "$TSA_CERT_PATH" ]; then
    echo -e "${YELLOW}Warning: TSA certificate not found at $TSA_CERT_PATH${COFF}"
    echo ""
    echo "Please generate TSA certificate first:"
    echo "  cd \$(dirname \$(dirname \$(realpath \$0)))"
    echo "  ./steps.sh"
    echo "  # Then uncomment or run: step_tsa \"MyTSA\""
    echo ""
    exit 1
fi

# Check if uv is available
if command -v uv &> /dev/null; then
    echo -e "${GREEN}Using uv to run server...${COFF}"
    USE_UV=true
else
    echo -e "${YELLOW}uv not found, using system uvicorn...${COFF}"
    USE_UV=false
fi

# Build uvicorn command
if [ "$USE_UV" = true ]; then
    CMD="uv run uvicorn mytsa.app:app --host $HOST --port $PORT"
else
    CMD="uvicorn mytsa.app:app --host $HOST --port $PORT"
fi

if [ -n "$RELOAD" ]; then
    CMD="$CMD --reload"
fi

echo -e "${GREEN}Starting server...${COFF}"
echo ""
echo "Endpoints:"
echo "  POST http://localhost:$PORT/tsa - RFC 3161 timestamp endpoint"
echo "  GET  http://localhost:$PORT/tsa/certs - Download certificate chain"
echo "  GET  http://localhost:$PORT/health - Health check"
echo "  GET  http://localhost:$PORT/ - API information"
echo ""
echo "Press CTRL+C to stop"
echo ""

# Run server
$CMD

