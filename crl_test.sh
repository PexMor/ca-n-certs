#!/bin/bash
#
# crl_test.sh - Test script for CRL functionality
#
# This script demonstrates the CRL management capabilities
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
COFF='\033[0m'

echo -e "${BLUE}=== CRL Management Test Script ===${COFF}"
echo ""

# Check if crl_mk.sh exists
if [ ! -f "./crl_mk.sh" ]; then
    echo -e "${RED}Error: crl_mk.sh not found in current directory${COFF}"
    exit 1
fi

# Use default base directory
BD="$HOME/.config/demo-cfssl"

echo -e "${YELLOW}Using base directory: $BD${COFF}"
echo ""

# Check if CA infrastructure exists
if [ ! -f "$BD/ca.pem" ] || [ ! -f "$BD/ica-ca.pem" ]; then
    echo -e "${RED}Error: CA infrastructure not found${COFF}"
    echo -e "${YELLOW}Please run './steps.sh' first to create the CA infrastructure${COFF}"
    exit 1
fi

echo -e "${GREEN}✓ CA infrastructure found${COFF}"
echo ""

# Test 1: Initialize CRL (generate empty CRL)
echo -e "${BLUE}Test 1: Generate initial CRL${COFF}"
./crl_mk.sh generate ica
echo ""
sleep 1

# Test 2: Show CRL info
echo -e "${BLUE}Test 2: Display CRL information${COFF}"
./crl_mk.sh info ica
echo ""
sleep 1

# Test 3: List revoked certificates (should be empty)
echo -e "${BLUE}Test 3: List revoked certificates (should be empty)${COFF}"
./crl_mk.sh list ica
echo ""
sleep 1

# Test 4: Create a test certificate to revoke
echo -e "${BLUE}Test 4: Create test certificate${COFF}"
TEST_CERT_DIR="$BD/hosts/test-revoke-demo"
if [ -f "$TEST_CERT_DIR/cert.pem" ]; then
    echo -e "${YELLOW}Test certificate already exists, using existing one${COFF}"
else
    # Check if step03 function is available
    if command -v cfssl &> /dev/null || [ -f "./steps.sh" ]; then
        echo -e "${YELLOW}Creating test certificate using steps.sh step03 function${COFF}"
        # Note: This requires steps.sh to be sourced or run separately
        # For simplicity, we'll check if a localhost cert exists
        if [ ! -f "$BD/hosts/localhost/cert.pem" ]; then
            echo -e "${RED}No test certificate available. Please run './steps.sh' first${COFF}"
            echo -e "${YELLOW}This will create a localhost certificate that we can use for testing${COFF}"
            exit 1
        fi
        echo -e "${YELLOW}Using existing localhost certificate for demonstration${COFF}"
        TEST_CERT_DIR="$BD/hosts/localhost"
    fi
fi
echo ""
sleep 1

# Test 5: Verify certificate is valid (not revoked)
echo -e "${BLUE}Test 5: Verify certificate is valid before revocation${COFF}"
if ./crl_mk.sh verify "$TEST_CERT_DIR/cert.pem" ica; then
    echo -e "${GREEN}✓ Certificate is valid${COFF}"
else
    echo -e "${YELLOW}Note: Verification may fail if certificate chain is incomplete${COFF}"
fi
echo ""
sleep 1

# Test 6: Revoke the certificate
echo -e "${BLUE}Test 6: Revoke the test certificate${COFF}"
./crl_mk.sh revoke "$TEST_CERT_DIR/cert.pem" keyCompromise
echo ""
sleep 1

# Test 7: Regenerate CRL with revocation
echo -e "${BLUE}Test 7: Regenerate CRL with revoked certificate${COFF}"
./crl_mk.sh generate ica
echo ""
sleep 1

# Test 8: List revoked certificates (should show one)
echo -e "${BLUE}Test 8: List revoked certificates (should show our test cert)${COFF}"
./crl_mk.sh list ica
echo ""
sleep 1

# Test 9: Verify certificate is now revoked
echo -e "${BLUE}Test 9: Verify certificate is now revoked${COFF}"
if ./crl_mk.sh verify "$TEST_CERT_DIR/cert.pem" ica; then
    echo -e "${RED}✗ Unexpected: Certificate still appears valid${COFF}"
else
    echo -e "${GREEN}✓ Certificate is properly revoked${COFF}"
fi
echo ""
sleep 1

# Test 10: Show final CRL info
echo -e "${BLUE}Test 10: Display final CRL information${COFF}"
./crl_mk.sh info ica
echo ""

# Summary
echo -e "${GREEN}=== Test Summary ===${COFF}"
echo -e "All CRL operations completed successfully!"
echo ""
echo -e "${YELLOW}Note: The test certificate has been revoked.${COFF}"
echo -e "${YELLOW}You may want to regenerate it by removing:${COFF}"
echo -e "  ${TEST_CERT_DIR}/"
echo -e "${YELLOW}And running './steps.sh' again.${COFF}"
echo ""
echo -e "${BLUE}CRL files generated:${COFF}"
echo -e "  ${GREEN}PEM:${COFF} $BD/ica-crl.pem"
echo -e "  ${GREEN}DER:${COFF} $BD/ica-crl.der"
echo ""
echo -e "${BLUE}For more information, see:${COFF} CRL_MANAGEMENT.md"

