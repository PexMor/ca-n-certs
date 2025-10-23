#!/bin/bash
#
# Example script showing how to sign PDFs with certificates from demo-cfssl
#

# Configuration
CERT_DIR="$HOME/.config/demo-cfssl/smime-openssl/john_extended"
P12_FILE="$CERT_DIR/email.p12"
SIGNATURE_IMAGE="signature.png"
INPUT_PDF="sample-document.pdf"
OUTPUT_PDF="signed-document.pdf"

echo "=== PDF Signing Example ==="
echo ""

# Check if certificate exists
if [ ! -f "$P12_FILE" ]; then
    echo "Error: Certificate not found at $P12_FILE"
    echo "Please run demo-cfssl steps.sh to generate certificates first"
    exit 1
fi

# Create a sample signature image if it doesn't exist
if [ ! -f "$SIGNATURE_IMAGE" ]; then
    echo "Creating sample signature image..."
    # This requires ImageMagick
    if command -v convert &> /dev/null; then
        convert -size 500x200 xc:white \
            -font Arial -pointsize 24 \
            -fill black \
            -gravity center \
            -annotate +0+0 "John Extended\nDigitally Signed" \
            -bordercolor black -border 2 \
            "$SIGNATURE_IMAGE"
        echo "✓ Created $SIGNATURE_IMAGE"
    else
        echo "Note: ImageMagick not found. You can create your own signature image."
        echo "      The signing will work without an image, using text-only signature."
    fi
fi

# Create a sample PDF if it doesn't exist
if [ ! -f "$INPUT_PDF" ]; then
    echo "Creating sample PDF document..."
    cat > temp.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Sample Document</title></head>
<body style="font-family: Arial, sans-serif; padding: 50px;">
    <h1>Sample Document for Signing</h1>
    <p>This is a sample document that will be digitally signed.</p>
    <p>The signature will be added at the bottom-right corner of this page.</p>
    <p>Date: $(date)</p>
    <br><br><br><br><br><br>
    <p style="color: #888;">Space reserved for digital signature</p>
</body>
</html>
EOF
    
    # Try to convert HTML to PDF (requires wkhtmltopdf or similar)
    if command -v wkhtmltopdf &> /dev/null; then
        wkhtmltopdf temp.html "$INPUT_PDF"
        rm temp.html
        echo "✓ Created $INPUT_PDF"
    else
        echo "Note: wkhtmltopdf not found. Please provide your own PDF file."
        echo "      You can use any PDF file as INPUT_PDF"
        rm temp.html
        exit 1
    fi
fi

# Sign the PDF
echo ""
echo "Signing PDF..."
echo "  Input:  $INPUT_PDF"
echo "  Output: $OUTPUT_PDF"
echo "  Cert:   $P12_FILE"

if [ -f "$SIGNATURE_IMAGE" ]; then
    echo "  Image:  $SIGNATURE_IMAGE"
    pdf-signer sign "$INPUT_PDF" "$OUTPUT_PDF" \
        --p12 "$P12_FILE" \
        --image "$SIGNATURE_IMAGE" \
        --position bottom-right \
        --width 250 \
        --height 120 \
        --reason "Document Approval" \
        --location "Prague, CZ" \
        --contact "john.extended@example.com"
else
    echo "  Image:  (none - text only)"
    pdf-signer sign "$INPUT_PDF" "$OUTPUT_PDF" \
        --p12 "$P12_FILE" \
        --position bottom-right \
        --width 250 \
        --height 120 \
        --reason "Document Approval" \
        --location "Prague, CZ" \
        --contact "john.extended@example.com"
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ PDF signed successfully!"
    echo ""
    echo "Verifying signature..."
    pdf-signer verify "$OUTPUT_PDF" --verbose
    echo ""
    echo "You can now open $OUTPUT_PDF in Adobe Acrobat or another PDF viewer"
    echo "to see and verify the digital signature."
else
    echo ""
    echo "✗ Signing failed"
    exit 1
fi

