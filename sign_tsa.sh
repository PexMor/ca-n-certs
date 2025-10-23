#!/bin/bash
#
# sign_tsa.sh - Sign files with detached signature and TSA timestamp
#
# Usage:
#   sign_tsa.sh --p12 <file.p12> [--password-file <pass.txt>] <file1> [file2 ...]
#   sign_tsa.sh --cert <cert.pem> --key <key.pem> <file1> [file2 ...]
#
# This script signs files using S/MIME certificates and adds a trusted timestamp
# from a free Time Stamp Authority (TSA). The detached signature is saved as
# <original_filename>.sign_tsa
#
# Free TSA servers used (in order of preference):
# 1. FreeTSA.org - http://freetsa.org/tsr
# 2. Sectigo - http://timestamp.sectigo.com
# 3. DigiCert - http://timestamp.digicert.com
#

set -e

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
COFF='\033[0m'

# Default TSA servers (in order of preference)
TSA_SERVERS=(
    "http://freetsa.org/tsr"
    "http://timestamp.sectigo.com"
    "http://timestamp.digicert.com"
)

# Variables
P12_FILE=""
CERT_FILE=""
KEY_FILE=""
PASSWORD_FILE=""
FILES_TO_SIGN=()
TEMP_DIR=""

# Function to print usage
usage() {
    echo "Usage:"
    echo "  $0 --p12 <file.p12> [--password-file <pass.txt>] <file1> [file2 ...]"
    echo "  $0 --cert <cert.pem> --key <key.pem> <file1> [file2 ...]"
    echo ""
    echo "Options:"
    echo "  --p12 FILE              PKCS#12 file containing certificate and private key"
    echo "  --cert FILE             Certificate file in PEM format"
    echo "  --key FILE              Private key file in PEM format"
    echo "  --password-file FILE    File containing password for P12 file (optional)"
    echo "  --tsa URL               Custom TSA server URL (optional)"
    echo "  --help                  Show this help message"
    echo ""
    echo "Output:"
    echo "  Creates <filename>.sign_tsa for each input file"
    echo ""
    echo "Example:"
    echo "  $0 --p12 email.p12 document.pdf"
    echo "  $0 --p12 email.p12 --password-file pass.txt report.pdf contract.docx"
    echo "  $0 --cert cert.pem --key key.pem presentation.pptx"
    exit 1
}

# Function to cleanup temporary files
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# Function to log messages
log_info() {
    echo -e "${BLUE}[INFO]${COFF} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${COFF} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${COFF} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${COFF} $1"
}

# Function to try TSA servers
get_timestamp() {
    local request_file=$1
    local response_file=$2
    
    for tsa_url in "${TSA_SERVERS[@]}"; do
        log_info "Trying TSA server: $tsa_url"
        if curl -s -S -H "Content-Type: application/timestamp-query" \
                --data-binary "@${request_file}" \
                -o "${response_file}" \
                "${tsa_url}" 2>/dev/null; then
            
            # Verify the response is valid
            if openssl ts -reply -in "${response_file}" -text >/dev/null 2>&1; then
                log_success "Received valid timestamp from $tsa_url"
                return 0
            else
                log_warning "Invalid response from $tsa_url, trying next..."
            fi
        else
            log_warning "Failed to contact $tsa_url, trying next..."
        fi
    done
    
    log_error "All TSA servers failed"
    return 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --p12)
            P12_FILE="$2"
            shift 2
            ;;
        --cert)
            CERT_FILE="$2"
            shift 2
            ;;
        --key)
            KEY_FILE="$2"
            shift 2
            ;;
        --password-file)
            PASSWORD_FILE="$2"
            shift 2
            ;;
        --tsa)
            TSA_SERVERS=("$2")
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            FILES_TO_SIGN+=("$1")
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$P12_FILE" ] && [ -z "$CERT_FILE" ]; then
    log_error "Either --p12 or --cert/--key must be specified"
    usage
fi

if [ -n "$CERT_FILE" ] && [ -z "$KEY_FILE" ]; then
    log_error "--cert requires --key"
    usage
fi

if [ -n "$KEY_FILE" ] && [ -z "$CERT_FILE" ]; then
    log_error "--key requires --cert"
    usage
fi

if [ ${#FILES_TO_SIGN[@]} -eq 0 ]; then
    log_error "No files to sign specified"
    usage
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
log_info "Using temporary directory: $TEMP_DIR"

# Extract certificate and key from P12 if needed
if [ -n "$P12_FILE" ]; then
    if [ ! -f "$P12_FILE" ]; then
        log_error "P12 file not found: $P12_FILE"
        exit 1
    fi
    
    log_info "Extracting certificate and key from P12 file..."
    
    PASS_OPTION=""
    if [ -n "$PASSWORD_FILE" ]; then
        if [ ! -f "$PASSWORD_FILE" ]; then
            log_error "Password file not found: $PASSWORD_FILE"
            exit 1
        fi
        PASS_OPTION="-passin file:$PASSWORD_FILE"
    else
        PASS_OPTION="-passin pass:"
    fi
    
    # Extract certificate
    openssl pkcs12 -in "$P12_FILE" $PASS_OPTION -clcerts -nokeys -out "$TEMP_DIR/cert.pem" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to extract certificate from P12 file. Check password?"
        exit 1
    fi
    
    # Extract private key
    openssl pkcs12 -in "$P12_FILE" $PASS_OPTION -nocerts -nodes -out "$TEMP_DIR/key.pem" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to extract private key from P12 file. Check password?"
        exit 1
    fi
    
    CERT_FILE="$TEMP_DIR/cert.pem"
    KEY_FILE="$TEMP_DIR/key.pem"
    
    log_success "Certificate and key extracted successfully"
fi

# Verify certificate and key files exist
if [ ! -f "$CERT_FILE" ]; then
    log_error "Certificate file not found: $CERT_FILE"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    log_error "Private key file not found: $KEY_FILE"
    exit 1
fi

# Display certificate info
log_info "Certificate information:"
openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates | sed 's/^/  /'

# Sign each file
for file in "${FILES_TO_SIGN[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        continue
    fi
    
    output_file="${file}.sign_tsa"
    log_info "Signing file: $file"
    
    # Create detached signature in PEM format
    # Note: -binary flag removed to avoid signature verification issues
    # with text files that may have line ending transformations
    
    # Try to find CA bundle to include in signature
    CA_BUNDLE=""
    if [ -f "$HOME/.config/demo-cfssl/ica-ca.pem" ]; then
        CA_BUNDLE="$HOME/.config/demo-cfssl/ica-ca.pem"
    fi
    
    if [ -n "$CA_BUNDLE" ]; then
        # Include intermediate CA certificate in signature
        if ! openssl cms -sign \
            -in "$file" \
            -signer "$CERT_FILE" \
            -inkey "$KEY_FILE" \
            -certfile "$CA_BUNDLE" \
            -outform PEM \
            -out "${output_file}.tmp" 2>/dev/null; then
            log_error "Failed to create signature for $file"
            continue
        fi
    else
        # Sign without CA chain
        if ! openssl cms -sign \
            -in "$file" \
            -signer "$CERT_FILE" \
            -inkey "$KEY_FILE" \
            -outform PEM \
            -out "${output_file}.tmp" 2>/dev/null; then
            log_error "Failed to create signature for $file"
            continue
        fi
    fi
    
    # Create timestamp request
    log_info "Creating timestamp request..."
    if ! openssl ts -query \
        -data "$file" \
        -sha256 \
        -cert \
        -out "$TEMP_DIR/ts_request.tsq" 2>/dev/null; then
        log_error "Failed to create timestamp request"
        rm -f "${output_file}.tmp"
        continue
    fi
    
    # Get timestamp from TSA
    if get_timestamp "$TEMP_DIR/ts_request.tsq" "$TEMP_DIR/ts_response.tsr"; then
        # Verify timestamp
        log_info "Verifying timestamp..."
        if openssl ts -reply \
            -in "$TEMP_DIR/ts_response.tsr" \
            -text >/dev/null 2>&1; then
            
            # Save signature
            mv "${output_file}.tmp" "$output_file"
            
            # Save the full timestamp response (not just the token)
            # This allows for proper verification later
            cp "$TEMP_DIR/ts_response.tsr" "${output_file}.tsr"
            
            log_success "Signed with timestamp: $output_file"
            log_info "Timestamp saved to: ${output_file}.tsr"
            
            # Show timestamp info
            echo -e "${BLUE}  Timestamp details:${COFF}"
            openssl ts -reply -in "$TEMP_DIR/ts_response.tsr" -text 2>/dev/null | grep -E "(Time stamp|Hash Algorithm|Message data)" | sed 's/^/    /'
        else
            log_warning "Timestamp verification failed, saving signature without timestamp"
            mv "${output_file}.tmp" "$output_file"
            log_success "Signed (no timestamp): $output_file"
        fi
    else
        log_warning "Could not obtain timestamp, saving signature without timestamp"
        mv "${output_file}.tmp" "$output_file"
        log_success "Signed (no timestamp): $output_file"
    fi
    
    echo ""
done

log_success "Signing complete!"
log_info "To verify a signature, use:"
echo "  openssl cms -verify -in <file>.sign_tsa -inform PEM -content <file> -noverify"

