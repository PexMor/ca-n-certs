#!/bin/bash
#
# build_ca_bundle.sh - Create a combined CA bundle
#
# This script combines your custom CA chain with the system's trusted CAs
# The combined bundle can be used to verify both your own certificates
# and external certificates (like TSA certificates)
#

set -e

# Default values
DEF_BD="$HOME/.config/demo-cfssl"
BD=${1:-$DEF_BD}
OUTPUT_FILE="${2:-$BD/ca-bundle-all-roots.pem}"
OUTPUT_FILE_COMPLETE="${3:-$BD/ca-bundle-complete.pem}"
OUTPUT_FILE_MYCA_BUNDLE="${3:-$BD/ca-bundle-myca.pem}"
OUTPUT_FILE_SYSTEM_CA_BUNDLE="${4:-$BD/ca-bundle-system.pem}"

# ANSI colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
COFF='\033[0m'

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Building Complete CA Bundle"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check if custom CA files exist
if [ ! -f "$BD/ca.pem" ]; then
    echo -e "${RED}Error:${COFF} Root CA not found at $BD/ca.pem"
    exit 1
fi

if [ ! -f "$BD/ica-ca.pem" ]; then
    echo -e "${RED}Error:${COFF} Intermediate CA not found at $BD/ica-ca.pem"
    exit 1
fi

# Find system CA bundle
SYSTEM_CA=""
if [ -f /opt/homebrew/etc/openssl@3/cert.pem ]; then
    SYSTEM_CA="/opt/homebrew/etc/openssl@3/cert.pem"
elif [ -f /usr/local/etc/openssl/cert.pem ]; then
    SYSTEM_CA="/usr/local/etc/openssl/cert.pem"
elif [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    SYSTEM_CA="/etc/ssl/certs/ca-certificates.crt"
elif [ -f /etc/ssl/cert.pem ]; then
    SYSTEM_CA="/etc/ssl/cert.pem"
else
    echo -e "${RED}Error:${COFF} System CA bundle not found"
    echo "Please specify the system CA bundle location manually:"
    echo "  $0 <cfssl-dir> <output-file> <system-ca-file>"
    exit 1
fi

# Allow override as third parameter
if [ -n "$3" ]; then
    SYSTEM_CA="$3"
fi

echo -e "${BLUE}[INFO]${COFF} Custom CA directory: $BD"
echo -e "${BLUE}[INFO]${COFF} System CA bundle: $SYSTEM_CA"
echo -e "${BLUE}[INFO]${COFF} Output file: $OUTPUT_FILE"
echo ""

# Create the combined bundle
echo "Building CA bundle... $(basename "$OUTPUT_FILE")"

{
    echo "# Combined CA Bundle"
    echo "# Generated: $(date)"
    echo "# Contains: Custom CA chain + System trusted CAs"
    echo ""
    echo "# ============================================"
    echo "# Custom Root CA"
    echo "# ============================================"
    cat "$BD/ca.pem"
    echo ""
    echo "# ============================================"
    echo "# System Trusted CAs"
    echo "# ============================================"
    cat "$SYSTEM_CA"
} > "$OUTPUT_FILE"

echo "Building Complete CA bundle... $(basename "$OUTPUT_FILE_COMPLETE")"

{
    echo "# Combined CA Bundle"
    echo "# Generated: $(date)"
    echo "# Contains: Custom CA chain + System trusted CAs"
    echo ""
    echo "# ============================================"
    echo "# Custom Root CA"
    echo "# ============================================"
    cat "$BD/ca.pem"
    echo ""
    echo "# ============================================"
    echo "# Custom Intermediate CA"
    echo "# ============================================"
    cat "$BD/ica-ca.pem"
    echo ""
    echo "# ============================================"
    echo "# System Trusted CAs"
    echo "# ============================================"
    cat "$SYSTEM_CA"
} > "$OUTPUT_FILE_COMPLETE"

echo "Building My CA bundle... $(basename "$OUTPUT_FILE_MYCA_BUNDLE")"

{
    echo "# My CA Bundle"
    echo "# Generated: $(date)"
    echo "# Contains: Custom CA chain"
    echo ""
    echo "# ============================================"
    echo "# Custom Root CA"
    echo "# ============================================"
    cat "$BD/ca.pem"
    echo ""
    echo "# ============================================"
    echo "# Custom Intermediate CA"
    echo "# ============================================"
    cat "$BD/ica-ca.pem"
} > "$OUTPUT_FILE_MYCA_BUNDLE"

echo "Building System CA bundle... $(basename "$OUTPUT_FILE_SYSTEM_CA_BUNDLE")"
echo ""

cat "$SYSTEM_CA" > "$OUTPUT_FILE_SYSTEM_CA_BUNDLE"

echo -e "${GREEN}[SUCCESS]${COFF} Combined CA bundle created!"
echo ""

# Display statistics
CUSTOM_CERTS=$(grep -c "BEGIN CERTIFICATE" "$BD/ca.pem" "$BD/ica-ca.pem" 2>/dev/null || echo 0)
SYSTEM_CERTS=$(grep -c "BEGIN CERTIFICATE" "$SYSTEM_CA" 2>/dev/null || echo 0)
TOTAL_CERTS=$(grep -c "BEGIN CERTIFICATE" "$OUTPUT_FILE" 2>/dev/null || echo 0)

echo "Statistics:"
echo "  Custom CAs:     $CUSTOM_CERTS certificates"
echo "  System CAs:     $SYSTEM_CERTS certificates"
echo "  Total:          $TOTAL_CERTS certificates"
echo ""
echo -e "${GREEN}[SUCCESS]${COFF} CA bundle ready at: $OUTPUT_FILE"
echo ""
echo "Usage:"
echo "  # Verify your own certificates:"
echo "  ./verify_tsa.sh document.pdf --ca-file $OUTPUT_FILE --verify-cert"
echo ""
echo "  # Verify timestamps (TSA certificates):"
echo "  openssl ts -verify -in file.sign_tsa.tsr -data file.pdf -CAfile $OUTPUT_FILE"
echo ""

