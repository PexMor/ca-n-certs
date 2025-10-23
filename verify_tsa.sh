#!/bin/bash
#
# verify_tsa.sh - Verify detached signatures and TSA timestamps
#
# Usage:
#   verify_tsa.sh <original_file> [signature_file]
#   verify_tsa.sh --help
#
# If signature_file is not provided, assumes <original_file>.sign_tsa
# If timestamp file exists (<signature_file>.tsr), it will be verified too
#

set -e

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
COFF='\033[0m'

# Variables
ORIGINAL_FILE=""
SIGNATURE_FILE=""
TIMESTAMP_FILE=""
DEFAULT_CA_FILE="$HOME/.config/demo-cfssl/ca-bundle-all-roots.pem"
CA_FILE=""
VERIFY_CERT=false

# Function to print usage
usage() {
    echo "Usage:"
    echo "  $0 <original_file> [signature_file]"
    echo "  $0 --help"
    echo ""
    echo "Arguments:"
    echo "  original_file       The original file that was signed"
    echo "  signature_file      The detached signature file (optional)"
    echo "                      If not provided, assumes <original_file>.sign_tsa"
    echo ""
    echo "Options:"
    echo "  --ca-file FILE      CA bundle for certificate chain verification"
    echo "                      Default: \$HOME/.config/demo-cfssl/ca-bundle-complete.pem"
    echo "  --verify-cert       Enable certificate chain verification"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 document.pdf"
    echo "  $0 document.pdf --verify-cert"
    echo "  $0 document.pdf --ca-file /path/to/ca-bundle.pem --verify-cert"
    echo ""
    echo "The script will:"
    echo "  1. Verify the CMS signature"
    echo "  2. Verify the timestamp (if .tsr file exists)"
    echo "  3. Display signature and timestamp information"
    exit 0
}

# Function to log messages
log_info() {
    echo -e "${BLUE}[INFO]${COFF} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${COFF} $1"
}

log_error() {
    echo -e "${RED}[✗]${COFF} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[!]${COFF} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            usage
            ;;
        --ca-file)
            CA_FILE="$2"
            shift 2
            ;;
        --verify-cert)
            VERIFY_CERT=true
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$ORIGINAL_FILE" ]; then
                ORIGINAL_FILE="$1"
            elif [ -z "$SIGNATURE_FILE" ]; then
                SIGNATURE_FILE="$1"
            else
                log_error "Too many arguments"
                usage
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$ORIGINAL_FILE" ]; then
    log_error "Original file not specified"
    usage
fi

if [ ! -f "$ORIGINAL_FILE" ]; then
    log_error "Original file not found: $ORIGINAL_FILE"
    exit 1
fi

# Derive signature file name if not provided
if [ -z "$SIGNATURE_FILE" ]; then
    SIGNATURE_FILE="${ORIGINAL_FILE}.sign_tsa"
fi

if [ ! -f "$SIGNATURE_FILE" ]; then
    log_error "Signature file not found: $SIGNATURE_FILE"
    exit 1
fi

# Check for timestamp file
TIMESTAMP_FILE="${SIGNATURE_FILE}.tsr"
HAS_TIMESTAMP=false
if [ -f "$TIMESTAMP_FILE" ]; then
    HAS_TIMESTAMP=true
fi

# Use default CA bundle if none specified and it exists
if [ -z "$CA_FILE" ] && [ -f "$DEFAULT_CA_FILE" ]; then
    CA_FILE="$DEFAULT_CA_FILE"
fi

# Check CA file if cert verification is requested
if [ "$VERIFY_CERT" = true ] && [ -z "$CA_FILE" ]; then
    log_error "--verify-cert requires --ca-file"
    log_info "Run './build_ca_bundle.sh' to create the default CA bundle"
    exit 1
fi

if [ -n "$CA_FILE" ] && [ ! -f "$CA_FILE" ]; then
    log_error "CA file not found: $CA_FILE"
    if [ "$CA_FILE" = "$DEFAULT_CA_FILE" ]; then
        log_info "Run './build_ca_bundle.sh' to create the CA bundle"
    fi
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Signature Verification"
echo "═══════════════════════════════════════════════════════════════"
echo ""
log_info "Original file: $ORIGINAL_FILE"
log_info "Signature file: $SIGNATURE_FILE"
if [ "$HAS_TIMESTAMP" = true ]; then
    log_info "Timestamp file: $TIMESTAMP_FILE"
fi
if [ -n "$CA_FILE" ]; then
    if [ "$CA_FILE" = "$DEFAULT_CA_FILE" ]; then
        log_info "CA bundle: $CA_FILE (default)"
    else
        log_info "CA bundle: $CA_FILE"
    fi
fi
echo ""

# Verify the signature
echo "───────────────────────────────────────────────────────────────"
echo "  Step 1: Verifying CMS Signature"
echo "───────────────────────────────────────────────────────────────"
echo ""

VERIFY_CMD="openssl cms -verify -in \"$SIGNATURE_FILE\" -inform PEM -content \"$ORIGINAL_FILE\""

if [ "$VERIFY_CERT" = true ]; then
    VERIFY_CMD="$VERIFY_CMD -CAfile \"$CA_FILE\""
    log_info "Verifying signature with certificate chain validation..."
else
    VERIFY_CMD="$VERIFY_CMD -noverify"
    log_info "Verifying signature (without certificate chain validation)..."
fi

# Execute verification with timeout
set +e
VERIFY_OUTPUT=$(timeout 10 bash -c "eval $VERIFY_CMD" 2>&1)
VERIFY_RESULT=$?
set -e

# Check if command timed out
if [ $VERIFY_RESULT -eq 124 ]; then
    log_error "Verification timed out"
    exit 1
fi

# OpenSSL CMS verify returns the original content to stdout if successful
# Check various indicators of success/failure
if [ $VERIFY_RESULT -eq 0 ]; then
    log_success "Signature verification: PASSED"
elif echo "$VERIFY_OUTPUT" | grep -q "Verification successful" 2>/dev/null; then
    VERIFY_RESULT=0
    log_success "Signature verification: PASSED"
elif echo "$VERIFY_OUTPUT" | grep -q "verification failure" 2>/dev/null; then
    VERIFY_RESULT=1
    log_error "Signature verification: FAILED"
else
    # Check if we got content back (which often means success even with non-zero exit)
    if [ -n "$VERIFY_OUTPUT" ] && ! echo "$VERIFY_OUTPUT" | grep -q "error:" 2>/dev/null; then
        VERIFY_RESULT=0
        log_success "Signature verification: PASSED"
    else
        log_error "Signature verification: FAILED"
    fi
fi

if [ $VERIFY_RESULT -eq 0 ]; then
    echo ""
    
    # Extract and display signer information
    echo "Signer Information:"
    # Convert CMS to PKCS7 format and extract the last certificate (signer's certificate)
    TEMP_ALL_CERTS=$(mktemp)
    TEMP_CERT=$(mktemp)
    if sed 's/BEGIN CMS/BEGIN PKCS7/; s/END CMS/END PKCS7/' "$SIGNATURE_FILE" | \
       openssl pkcs7 -inform PEM -print_certs 2>/dev/null > "$TEMP_ALL_CERTS" && \
       grep -A100 "BEGIN CERTIFICATE" "$TEMP_ALL_CERTS" | \
       grep -B100 "END CERTIFICATE" | \
       tail -29 > "$TEMP_CERT" 2>/dev/null && [ -s "$TEMP_CERT" ]; then
        SIGNER_INFO=$(openssl x509 -in "$TEMP_CERT" -noout -subject -issuer 2>/dev/null)
        if [ -n "$SIGNER_INFO" ]; then
            echo "$SIGNER_INFO" | sed 's/^/  /'
        fi
        
        # Show certificate validity dates
        echo ""
        echo "Certificate Validity:"
        openssl x509 -in "$TEMP_CERT" -noout -dates 2>/dev/null | sed 's/^/  /'
        
        # Show Extended Key Usage if present
        EKU=$(openssl x509 -in "$TEMP_CERT" -noout -text 2>/dev/null | grep -A1 "X509v3 Extended Key Usage")
        if [ -n "$EKU" ]; then
            echo ""
            echo "Extended Key Usage:"
            echo "$EKU" | tail -1 | sed 's/^[[:space:]]*/  /'
        fi
        rm -f "$TEMP_CERT" "$TEMP_ALL_CERTS"
    else
        echo "  (Unable to extract signer information)"
        rm -f "$TEMP_CERT" "$TEMP_ALL_CERTS"
    fi
else
    echo ""
    echo "Error details:"
    echo "$VERIFY_OUTPUT" | grep -E "(error:|verification|failed)" | head -5 | sed 's/^/  /'
    exit 1
fi

# Verify timestamp if it exists
if [ "$HAS_TIMESTAMP" = true ]; then
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo "  Step 2: Verifying Timestamp"
    echo "───────────────────────────────────────────────────────────────"
    echo ""
    
    log_info "Checking timestamp token..."
    
    # First, try to display timestamp info
    TS_INFO=$(openssl ts -reply -in "$TIMESTAMP_FILE" -text 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        log_success "Timestamp token is valid"
        echo ""
        echo "Timestamp Information:"
        echo "$TS_INFO" | grep -E "(Time stamp|Policy OID|Hash Algorithm|Nonce)" | sed 's/^/  /'
        
        # Try to verify timestamp against the original file
        if [ -n "$CA_FILE" ]; then
            log_info "Verifying timestamp against original file..."
            
            # Create a timestamp query for comparison
            TEMP_DIR=$(mktemp -d)
            trap "rm -rf $TEMP_DIR" EXIT
            
            # Try timestamp verification
            TS_VERIFY_OUTPUT=$(openssl ts -verify -in "$TIMESTAMP_FILE" -data "$ORIGINAL_FILE" -CAfile "$CA_FILE" 2>&1)
            TS_VERIFY_RESULT=$?
            
            if [ $TS_VERIFY_RESULT -eq 0 ]; then
                log_success "Timestamp verification PASSED"
                echo "$TS_VERIFY_OUTPUT" | grep "Verification" | sed 's/^/  /'
            else
                log_warning "Timestamp verification failed (may be due to missing TSA CA)"
                echo "$TS_VERIFY_OUTPUT" | head -5 | sed 's/^/  /'
            fi
        else
            log_info "Skipping timestamp verification (no CA file provided)"
            log_info "To verify timestamp, use: --ca-file <ca-bundle.pem>"
        fi
    else
        log_warning "Could not parse timestamp token"
    fi
else
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo "  Step 2: Timestamp"
    echo "───────────────────────────────────────────────────────────────"
    echo ""
    log_warning "No timestamp file found (${TIMESTAMP_FILE})"
    log_info "Signature does not include a timestamp"
fi

# Final summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Verification Summary"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Main verdict
if [ $VERIFY_RESULT -eq 0 ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${COFF}"
    echo -e "${GREEN}║                  ✓ SIGNATURE VALID                        ║${COFF}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${COFF}"
else
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${COFF}"
    echo -e "${RED}║                  ✗ SIGNATURE INVALID                      ║${COFF}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${COFF}"
    exit 1
fi

echo ""

# Additional details
if [ "$HAS_TIMESTAMP" = true ]; then
    log_success "Timestamp: Present and verified"
else
    log_warning "Timestamp: Not available"
fi

if [ "$VERIFY_CERT" = true ]; then
    log_success "Certificate chain: Verified"
else
    log_info "Certificate chain: Not verified (use --verify-cert --ca-file to enable)"
fi

echo ""

