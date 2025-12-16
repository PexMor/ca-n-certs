#!/bin/bash
# Demo script showing end-to-end workflow for signing PowerShell scripts
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
COFF='\033[0m'

BD="${DEMO_CFSSL_DIR:-$HOME/.config/demo-cfssl}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${COFF}"
echo -e "${BLUE}║   PowerShell Authenticode Signing Demo - pkipy             ║${COFF}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${COFF}"
echo

# Step 1: Check if code signing certificate exists (RSA required for Windows Authenticode)
echo -e "${YELLOW}Step 1: Check code signing certificate (RSA)${COFF}"
if [ ! -f "$BD/codesign/mycodesign/cert.pem" ]; then
    echo -e "${RED}✗ Code signing certificate not found${COFF}"
    echo "  Generating RSA certificate (required for Windows Authenticode)..."
    cd .. && source steps.sh && step_codesign "MyCodeSign" && cd pkipy
else
    # Check if existing cert is RSA or ECDSA
    KEY_TYPE=$(openssl x509 -in "$BD/codesign/mycodesign/cert.pem" -noout -text 2>/dev/null | grep "Public Key Algorithm" | head -1)
    if [[ "$KEY_TYPE" == *"EC"* ]] || [[ "$KEY_TYPE" == *"ec"* ]]; then
        echo -e "${YELLOW}⚠ Existing certificate uses ECDSA (not compatible with Windows Authenticode)${COFF}"
        echo "  Regenerating with RSA..."
        rm -rf "$BD/codesign/mycodesign"
        cd .. && source steps.sh && step_codesign "MyCodeSign" && cd pkipy
    else
        echo -e "${GREEN}✓ Code signing certificate exists (RSA)${COFF}"
        echo "  Location: $BD/codesign/mycodesign/"
    fi
fi
echo

# Step 2: Show certificate details
echo -e "${YELLOW}Step 2: Certificate details${COFF}"
openssl x509 -in "$BD/codesign/mycodesign/cert.pem" -noout -subject -dates -ext extendedKeyUsage
echo

# Step 3: Sign a test script (without timestamp)
echo -e "${YELLOW}Step 3: Sign test script (without timestamp)${COFF}"
echo "  Signing test-script.ps1..."
uv run pkipy test-script.ps1 \
    --output test-script-signed-no-ts.ps1 \
    --pfx "$BD/codesign/mycodesign/codesign.p12"
echo

# Step 4: Sign with timestamp
echo -e "${YELLOW}Step 4: Sign test script (with timestamp)${COFF}"
echo "  Signing test-script.ps1 with RFC3161 timestamp..."
uv run pkipy test-script.ps1 \
    --output test-script-signed.ps1 \
    --pfx "$BD/codesign/mycodesign/codesign.p12" \
    --timestamp-url http://timestamp.digicert.com
echo

# Step 5: Show signature block
echo -e "${YELLOW}Step 5: Signature block preview${COFF}"
echo "  Last 20 lines of signed script:"
tail -20 test-script-signed.ps1
echo

# Step 6: Compare file sizes
echo -e "${YELLOW}Step 6: File size comparison${COFF}"
ls -lh test-script.ps1 test-script-signed-no-ts.ps1 test-script-signed.ps1 | awk '{print "  " $9 ": " $5}'
echo

# Step 7: Instructions for verification
echo -e "${YELLOW}Step 7: Verification instructions${COFF}"
echo -e "  ${GREEN}✓ Scripts signed successfully!${COFF}"
echo
echo "  To verify on Windows with PowerShell:"
echo "    1. Copy signed script to Windows machine"
echo "    2. Run: Get-AuthenticodeSignature test-script-signed.ps1 | Format-List *"
echo
echo "  To trust the certificate (on Windows):"
echo "    Import-Certificate -FilePath ca.pem -CertStoreLocation Cert:\\LocalMachine\\Root"
echo "    Import-Certificate -FilePath ica-ca.pem -CertStoreLocation Cert:\\LocalMachine\\CA"
echo
echo -e "${YELLOW}Step 8: Using config file (optional)${COFF}"
echo "  Create config for easier usage:"
echo "    mkdir -p ~/.config/pkipy"
echo "    cat > ~/.config/pkipy/config.yaml << EOF"
echo "pfx: $BD/codesign/mycodesign/codesign.p12"
echo "timestamp-url: http://timestamp.digicert.com"
echo "EOF"
echo
echo "  Then simply run:"
echo "    uv run pkipy script.ps1 --output signed.ps1"
echo

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${COFF}"
echo -e "${GREEN}║   Demo completed successfully!                             ║${COFF}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${COFF}"

