#!/bin/bash
#
# complete-workflow.sh - Complete PDF signing workflow example
#
# This script demonstrates the complete workflow:
# 1. Create a demo PDF
# 2. Create a signature image
# 3. Sign the PDF
# 4. Verify the signature
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==================================================================="
echo "      PDF Signing Complete Workflow Demo"
echo "==================================================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
COFF='\033[0m'

# Check for certificate
CERT_DIR="$HOME/.config/demo-cfssl/smime-openssl"
P12_FILE=""

echo -e "${BLUE}Step 0: Checking for certificates...${COFF}"

# Find first available certificate
if [ -d "$CERT_DIR" ]; then
    for cert_dir in "$CERT_DIR"/*; do
        if [ -f "$cert_dir/email.p12" ]; then
            P12_FILE="$cert_dir/email.p12"
            CERT_NAME=$(basename "$cert_dir")
            echo -e "${GREEN}✓ Found certificate: $CERT_NAME${COFF}"
            break
        fi
    done
fi

if [ -z "$P12_FILE" ]; then
    echo -e "${YELLOW}⚠ No demo-cfssl certificates found${COFF}"
    echo ""
    echo "Please either:"
    echo "  1. Run ../steps.sh to generate certificates, or"
    echo "  2. Provide your own certificate with --p12 option"
    echo ""
    echo "Continuing with demo (you'll need to provide certificate later)..."
    P12_FILE="certificate.p12"
fi

echo ""

# Step 1: Create demo PDF
echo -e "${BLUE}Step 1: Creating demo 3-page PDF...${COFF}"
cd "$PROJECT_DIR/examples"
./mk-demo.sh
echo ""

# Step 2: Create signature image (if ImageMagick available)
echo -e "${BLUE}Step 2: Creating signature image...${COFF}"
if command -v convert &> /dev/null; then
    convert -size 500x200 xc:white \
        -font Arial -pointsize 24 \
        -fill black \
        -gravity center \
        -annotate +0-20 "Digitally Signed" \
        -annotate +0+20 "$(date +%Y-%m-%d)" \
        -bordercolor navy -border 2 \
        "$SCRIPT_DIR/signature-demo.png"
    echo -e "${GREEN}✓ Created signature image: signature-demo.png${COFF}"
else
    echo -e "${YELLOW}⚠ ImageMagick not found, skipping signature image creation${COFF}"
    echo "  The PDF will be signed with text-only signature"
fi
echo ""

# Step 3: Sign the PDF
echo -e "${BLUE}Step 3: Signing the PDF...${COFF}"
cd "$PROJECT_DIR"

SIGN_CMD="uv run python -m pdf_signer.sign sign examples/demo3page.pdf examples/demo3page-signed.pdf --p12 \"$P12_FILE\""

if [ -f "$SCRIPT_DIR/signature-demo.png" ]; then
    SIGN_CMD="$SIGN_CMD --image examples/signature-demo.png"
fi

SIGN_CMD="$SIGN_CMD --position bottom-right --page 3 --reason \"Demo Signature\" --location \"Prague, CZ\""

echo "Running:"
echo "  $SIGN_CMD"
echo ""

if [ -f "$P12_FILE" ]; then
    eval $SIGN_CMD || {
        echo -e "${RED}✗ Signing failed${COFF}"
        echo ""
        echo "The certificate file exists but signing failed."
        echo "This might be due to:"
        echo "  - Incorrect password"
        echo "  - Corrupted certificate"
        echo "  - Invalid certificate format"
        exit 1
    }
    echo -e "${GREEN}✓ PDF signed successfully!${COFF}"
else
    echo -e "${YELLOW}⚠ Certificate not found at: $P12_FILE${COFF}"
    echo ""
    echo "To complete this step, provide a valid PKCS#12 certificate:"
    echo "  uv run python -m pdf_signer.sign sign examples/demo3page.pdf examples/demo3page-signed.pdf \\"
    echo "      --p12 /path/to/your/certificate.p12 \\"
    if [ -f "$SCRIPT_DIR/signature-demo.png" ]; then
        echo "      --image examples/signature-demo.png \\"
    fi
    echo "      --position bottom-right \\"
    echo "      --page 3 \\"
    echo "      --reason \"Demo Signature\" \\"
    echo "      --location \"Prague, CZ\""
    echo ""
    echo "Skipping remaining steps..."
    exit 0
fi
echo ""

# Step 4: Verify the signature
echo -e "${BLUE}Step 4: Verifying the signature...${COFF}"
uv run python -m pdf_signer.sign verify examples/demo3page-signed.pdf --verbose
echo ""

# Summary
echo "==================================================================="
echo -e "${GREEN}✓ Workflow Complete!${COFF}"
echo "==================================================================="
echo ""
echo "Generated files:"
echo "  📄 examples/demo3page.pdf           - Original 3-page document"
if [ -f "$SCRIPT_DIR/signature-demo.png" ]; then
    echo "  🖼️  examples/signature-demo.png     - Signature image"
fi
echo "  ✅ examples/demo3page-signed.pdf   - Signed document"
echo ""
echo "You can now:"
echo "  1. Open demo3page-signed.pdf in Adobe Acrobat to see the signature"
echo "  2. Click on the signature to view certificate details"
echo "  3. Use the signed PDF as a template for your own documents"
echo ""
echo "To clean up:"
echo "  rm examples/demo3page*.pdf examples/signature-demo.png"
echo ""

