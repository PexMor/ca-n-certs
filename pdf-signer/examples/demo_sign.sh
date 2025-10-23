#!/bin/bash
#
# demo_sign.sh - Sign the demo PDF with demo-cfssl certificate
#
# This script signs demo3page.pdf using the john_extended certificate
# from demo-cfssl and the signature-demo.png image.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
COFF='\033[0m'

echo "==================================================================="
echo "      Demo PDF Signing Script"
echo "==================================================================="
echo ""

# Input files
INPUT_PDF="$SCRIPT_DIR/demo3page.pdf"
SIGNATURE_IMAGE="$SCRIPT_DIR/signature-demo.png"
OUTPUT_PDF="$SCRIPT_DIR/demo3page-signed.pdf"

# Certificate path
CERT_DIR="$HOME/.config/demo-cfssl/smime-openssl/john_extended"
P12_FILE="$CERT_DIR/email.p12"

echo -e "${BLUE}Configuration:${COFF}"
echo "  Input PDF:  $INPUT_PDF"
echo "  Signature:  $SIGNATURE_IMAGE"
echo "  Output PDF: $OUTPUT_PDF"
echo "  Certificate: $P12_FILE"
echo ""

# Check if input PDF exists
if [ ! -f "$INPUT_PDF" ]; then
    echo -e "${YELLOW}⚠ Demo PDF not found. Creating it now...${COFF}"
    cd "$SCRIPT_DIR"
    ./mk-demo.sh
    echo ""
fi

# Check if signature image exists
if [ ! -f "$SIGNATURE_IMAGE" ]; then
    echo -e "${YELLOW}⚠ Signature image not found. Creating it now...${COFF}"
    cd "$SCRIPT_DIR"
    ./mk-demo.sh
    echo ""
fi

# Check if certificate exists
if [ ! -f "$P12_FILE" ]; then
    echo -e "${RED}✗ Certificate not found: $P12_FILE${COFF}"
    echo ""
    echo "The john_extended certificate doesn't exist yet."
    echo ""
    echo "To create it, run from the demo-cfssl directory:"
    echo "  cd ../.."
    echo "  ./steps.sh"
    echo ""
    echo "This will generate all necessary certificates including john_extended."
    echo ""
    echo "Alternatively, you can specify a different certificate:"
    echo "  P12_FILE=/path/to/your/cert.p12 $0"
    exit 1
fi

echo -e "${BLUE}Signing PDF...${COFF}"
echo ""

# Change to project directory
cd "$PROJECT_DIR"

# Sign the PDF
# Note: The certificate is created without a password by default in demo-cfssl
# We create a temporary empty password file to avoid interactive prompts

# Create temporary password file with empty password
TEMP_PASS_FILE=$(mktemp)
echo "" > "$TEMP_PASS_FILE"

# Trap to ensure cleanup
trap "rm -f '$TEMP_PASS_FILE'" EXIT

uv run python -m pdf_signer.sign sign \
    "$INPUT_PDF" \
    "$OUTPUT_PDF" \
    --p12 "$P12_FILE" \
    --password-file "$TEMP_PASS_FILE" \
    --image "$SIGNATURE_IMAGE" \
    --position bottom-right \
    --width 250 \
    --height 120 \
    --page 3 \
    --reason "Demo Document Signature" \
    --location "Prague, Czech Republic" \
    --contact "john.extended@example.com" \
    --field-name "DemoSignature1"

if [ $? -eq 0 ]; then
    echo ""
    echo "==================================================================="
    echo -e "${GREEN}✅ PDF Signed Successfully!${COFF}"
    echo "==================================================================="
    echo ""
    echo "Output file: $OUTPUT_PDF"
    ls -lh "$OUTPUT_PDF"
    echo ""
    echo "Next steps:"
    echo "  1. Open the signed PDF:"
    echo "     open $OUTPUT_PDF"
    echo ""
    echo "  2. Verify the signature:"
    echo "     cd $PROJECT_DIR"
    echo "     uv run python -m pdf_signer.sign verify examples/demo3page-signed.pdf --verbose"
    echo ""
    echo "  3. View in Adobe Acrobat for best signature display"
    echo ""
else
    echo ""
    echo -e "${RED}✗ Signing failed${COFF}"
    echo ""
    echo "Common issues:"
    echo "  - Certificate password might be incorrect (try without --password flag)"
    echo "  - Certificate might be corrupted"
    echo "  - Permissions issue with output file"
    exit 1
fi
