#!/bin/bash
#
# crl_check.sh - Check Certificate Validity Against CRL
#
# This script checks whether a certificate is valid or revoked by verifying
# it against the appropriate Certificate Revocation List (CRL).
#
# Usage:
#   ./crl_check.sh CERT_FILE [OPTIONS]
#   ./crl_check.sh --batch CERT_LIST_FILE [OPTIONS]
#
# Options:
#   --crl FILE          Use specific CRL file instead of auto-detecting
#   --ca-bundle FILE    Use specific CA bundle for verification
#   --verbose           Show detailed certificate information
#   --quiet             Minimal output (exit code only)
#   --json              Output results in JSON format
#   --batch FILE        Check multiple certificates from file (one per line)
#
# Examples:
#   ./crl_check.sh ~/.config/demo-cfssl/hosts/localhost/cert.pem
#   ./crl_check.sh cert.pem --crl custom-crl.pem --ca-bundle ca.pem
#   ./crl_check.sh --batch cert-list.txt --json
#
# Exit Codes:
#   0 - Certificate is valid (not revoked)
#   1 - Certificate is revoked
#   2 - Error (file not found, invalid certificate, etc.)
#

set -e

# Default paths
DEF_BD="$HOME/.config/demo-cfssl"
BD="${CRL_CHECK_BD:-$DEF_BD}"

# Check whether running on MacOS or Linux and set appropriate tools
if [ "$(uname)" == "Darwin" ]; then
    DATE="gdate"
    SED="gsed"
else
    DATE="date"
    SED="sed"
fi

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
AZURE='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
COFF='\033[0m'

# Options
VERBOSE=0
QUIET=0
JSON_OUTPUT=0
BATCH_MODE=0
CUSTOM_CRL=""
CUSTOM_CA_BUNDLE=""

function usage() {
    cat << EOF
Usage: $0 CERT_FILE [OPTIONS]
       $0 --batch CERT_LIST_FILE [OPTIONS]

Check if a certificate is valid or revoked against CRL.

Options:
  --crl FILE          Use specific CRL file instead of auto-detecting
  --ca-bundle FILE    Use specific CA bundle for verification
  --verbose, -v       Show detailed certificate information
  --quiet, -q         Minimal output (exit code only)
  --json              Output results in JSON format
  --batch FILE        Check multiple certificates from file
  --help, -h          Show this help message

Examples:
  # Check a single certificate (auto-detect CRL)
  $0 ~/.config/demo-cfssl/hosts/localhost/cert.pem

  # Check with custom CRL
  $0 cert.pem --crl /path/to/crl.pem

  # Check with custom CA bundle
  $0 cert.pem --ca-bundle /path/to/ca-bundle.pem

  # Verbose mode with all details
  $0 cert.pem --verbose

  # Batch check multiple certificates
  $0 --batch cert-list.txt

  # JSON output for scripting
  $0 cert.pem --json

Exit Codes:
  0 - Certificate is valid (not revoked)
  1 - Certificate is revoked
  2 - Error occurred

Environment Variables:
  CRL_CHECK_BD        Override base directory (default: ~/.config/demo-cfssl)

EOF
    exit 0
}

function log_info() {
    if [ $QUIET -eq 0 ]; then
        echo -e "${BLUE}[INFO]${COFF} $1"
    fi
}

function log_success() {
    if [ $QUIET -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS]${COFF} $1"
    fi
}

function log_warning() {
    if [ $QUIET -eq 0 ]; then
        echo -e "${YELLOW}[WARNING]${COFF} $1"
    fi
}

function log_error() {
    echo -e "${RED}[ERROR]${COFF} $1" >&2
}

function get_cert_info() {
    local CERT_FILE=$1
    
    if [ ! -f "$CERT_FILE" ]; then
        echo "ERROR: Certificate file not found"
        return 1
    fi
    
    # Get certificate details
    local SERIAL=$(openssl x509 -in "$CERT_FILE" -noout -serial 2>/dev/null | cut -d= -f2)
    local SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject 2>/dev/null | cut -d= -f2-)
    local ISSUER=$(openssl x509 -in "$CERT_FILE" -noout -issuer 2>/dev/null | cut -d= -f2-)
    local ISSUER_CN=$(echo "$ISSUER" | grep -o "CN=[^,]*" | cut -d= -f2)
    local NOT_BEFORE=$(openssl x509 -in "$CERT_FILE" -noout -startdate 2>/dev/null | cut -d= -f2)
    local NOT_AFTER=$(openssl x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [ -z "$SERIAL" ]; then
        echo "ERROR: Invalid certificate file"
        return 1
    fi
    
    echo "SERIAL=$SERIAL"
    echo "SUBJECT=$SUBJECT"
    echo "ISSUER=$ISSUER"
    echo "ISSUER_CN=$ISSUER_CN"
    echo "NOT_BEFORE=$NOT_BEFORE"
    echo "NOT_AFTER=$NOT_AFTER"
    
    return 0
}

function detect_ca_type() {
    local ISSUER_CN=$1
    
    # Detect if certificate was issued by Root CA or Intermediate CA
    if echo "$ISSUER_CN" | grep -qi "root"; then
        echo "ca"
    else
        echo "ica"
    fi
}

function check_cert_expiry() {
    local NOT_AFTER=$1
    
    local NOT_AFTER_SECS=$($DATE -d "$NOT_AFTER" +%s 2>/dev/null || echo "0")
    local NOW_SECS=$($DATE +%s)
    
    if [ "$NOT_AFTER_SECS" -eq "0" ]; then
        echo "unknown"
        return 2
    fi
    
    if [ $NOT_AFTER_SECS -lt $NOW_SECS ]; then
        echo "expired"
        return 1
    else
        local DAYS_LEFT=$(( ($NOT_AFTER_SECS - $NOW_SECS) / 86400 ))
        echo "valid:$DAYS_LEFT"
        return 0
    fi
}

function check_certificate() {
    local CERT_FILE=$1
    local RESULT_VAR=$2
    
    # Get certificate information
    local CERT_INFO=$(get_cert_info "$CERT_FILE")
    if [ $? -ne 0 ]; then
        eval "$RESULT_VAR='error:invalid_certificate'"
        return 2
    fi
    
    # Parse certificate info
    local SERIAL=$(echo "$CERT_INFO" | grep "^SERIAL=" | cut -d= -f2)
    local SUBJECT=$(echo "$CERT_INFO" | grep "^SUBJECT=" | cut -d= -f2-)
    local ISSUER=$(echo "$CERT_INFO" | grep "^ISSUER=" | cut -d= -f2-)
    local ISSUER_CN=$(echo "$CERT_INFO" | grep "^ISSUER_CN=" | cut -d= -f2-)
    local NOT_BEFORE=$(echo "$CERT_INFO" | grep "^NOT_BEFORE=" | cut -d= -f2-)
    local NOT_AFTER=$(echo "$CERT_INFO" | grep "^NOT_AFTER=" | cut -d= -f2-)
    
    # Check certificate expiry
    local EXPIRY_STATUS=$(check_cert_expiry "$NOT_AFTER")
    local EXPIRY_CODE=$?
    
    if [ $VERBOSE -eq 1 ]; then
        echo -e "${AZURE}Certificate Information:${COFF}"
        echo -e "  ${AZURE}File:${COFF}    $CERT_FILE"
        echo -e "  ${AZURE}Serial:${COFF}  $SERIAL"
        echo -e "  ${AZURE}Subject:${COFF} $SUBJECT"
        echo -e "  ${AZURE}Issuer:${COFF}  $ISSUER"
        echo -e "  ${AZURE}Valid From:${COFF} $NOT_BEFORE"
        echo -e "  ${AZURE}Valid To:${COFF}   $NOT_AFTER"
        
        if [ "$EXPIRY_STATUS" == "expired" ]; then
            echo -e "  ${RED}Status:${COFF}  Certificate is EXPIRED"
        elif [[ "$EXPIRY_STATUS" == valid:* ]]; then
            local DAYS_LEFT=$(echo "$EXPIRY_STATUS" | cut -d: -f2)
            echo -e "  ${GREEN}Status:${COFF}  Valid for $DAYS_LEFT more days"
        else
            echo -e "  ${YELLOW}Status:${COFF}  Unknown expiry status"
        fi
        echo ""
    fi
    
    # Determine which CRL to use
    local CRL_FILE
    if [ -n "$CUSTOM_CRL" ]; then
        CRL_FILE="$CUSTOM_CRL"
        log_info "Using custom CRL: $CRL_FILE"
    else
        # Auto-detect CA type
        local CA_TYPE=$(detect_ca_type "$ISSUER_CN")
        
        if [ "$CA_TYPE" == "ca" ]; then
            CRL_FILE="$BD/ca-crl.pem"
            log_info "Detected Root CA issuer, using: $CRL_FILE"
        else
            CRL_FILE="$BD/ica-crl.pem"
            log_info "Detected Intermediate CA issuer, using: $CRL_FILE"
        fi
    fi
    
    # Check if CRL exists
    if [ ! -f "$CRL_FILE" ]; then
        log_error "CRL file not found: $CRL_FILE"
        log_info "Generate CRL with: ./crl_mk.sh generate ica"
        eval "$RESULT_VAR='error:crl_not_found'"
        return 2
    fi
    
    # Determine CA bundle
    local CA_BUNDLE
    if [ -n "$CUSTOM_CA_BUNDLE" ]; then
        CA_BUNDLE="$CUSTOM_CA_BUNDLE"
    else
        if [ -f "$BD/ca-bundle.pem" ]; then
            CA_BUNDLE="$BD/ca-bundle.pem"
        elif [ -f "$BD/ca.pem" ]; then
            CA_BUNDLE="$BD/ca.pem"
        else
            log_error "CA bundle not found in $BD"
            eval "$RESULT_VAR='error:ca_bundle_not_found'"
            return 2
        fi
    fi
    
    if [ $VERBOSE -eq 1 ]; then
        log_info "Using CA bundle: $CA_BUNDLE"
        echo ""
    fi
    
    # Check if certificate is in CRL
    log_info "Checking certificate against CRL..."
    
    # First, check if the serial number appears in the CRL
    local SERIAL_IN_CRL=$(openssl crl -in "$CRL_FILE" -noout -text 2>/dev/null | grep -i "Serial Number:.*$SERIAL")
    
    if [ -n "$SERIAL_IN_CRL" ]; then
        # Certificate serial found in CRL - it's revoked
        log_warning "Certificate serial number found in CRL"
        
        # Try to extract revocation details
        if [ $VERBOSE -eq 1 ]; then
            echo -e "${YELLOW}Revocation Details:${COFF}"
            openssl crl -in "$CRL_FILE" -noout -text 2>/dev/null | \
                grep -A5 "Serial Number:.*$SERIAL" | head -6 | \
                sed 's/^/  /'
            echo ""
        fi
        
        eval "$RESULT_VAR='revoked'"
        return 1
    fi
    
    # Perform full OpenSSL verification with CRL check
    local VERIFY_OUTPUT=$(openssl verify -CAfile "$CA_BUNDLE" -crl_check -CRLfile "$CRL_FILE" "$CERT_FILE" 2>&1)
    local VERIFY_CODE=$?
    
    if [ $VERBOSE -eq 1 ]; then
        echo -e "${AZURE}OpenSSL Verification:${COFF}"
        echo "$VERIFY_OUTPUT" | sed 's/^/  /'
        echo ""
    fi
    
    # Analyze verification result
    if echo "$VERIFY_OUTPUT" | grep -qi "certificate revoked"; then
        eval "$RESULT_VAR='revoked'"
        return 1
    elif echo "$VERIFY_OUTPUT" | grep -qi "OK"; then
        eval "$RESULT_VAR='valid'"
        return 0
    elif echo "$VERIFY_OUTPUT" | grep -qi "unable to get certificate CRL"; then
        log_warning "Could not retrieve CRL for verification"
        eval "$RESULT_VAR='error:crl_unavailable'"
        return 2
    else
        # Other verification error
        if [ $QUIET -eq 0 ]; then
            log_warning "Verification returned: $VERIFY_OUTPUT"
        fi
        eval "$RESULT_VAR='error:verification_failed'"
        return 2
    fi
}

function output_json_result() {
    local CERT_FILE=$1
    local STATUS=$2
    local SERIAL=$3
    local SUBJECT=$4
    
    # Escape JSON strings
    CERT_FILE=$(echo "$CERT_FILE" | sed 's/"/\\"/g')
    SUBJECT=$(echo "$SUBJECT" | sed 's/"/\\"/g')
    
    cat << EOF
{
  "certificate": "$CERT_FILE",
  "serial": "$SERIAL",
  "subject": "$SUBJECT",
  "status": "$STATUS",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

function batch_check() {
    local BATCH_FILE=$1
    
    if [ ! -f "$BATCH_FILE" ]; then
        log_error "Batch file not found: $BATCH_FILE"
        return 2
    fi
    
    local TOTAL=0
    local VALID=0
    local REVOKED=0
    local ERRORS=0
    
    if [ $JSON_OUTPUT -eq 1 ]; then
        echo "["
    else
        echo -e "${BLUE}=== Batch Certificate Check ===${COFF}"
        echo ""
    fi
    
    local FIRST=1
    while IFS= read -r cert_file; do
        # Skip empty lines and comments
        [[ -z "$cert_file" ]] && continue
        [[ "$cert_file" =~ ^[[:space:]]*# ]] && continue
        
        TOTAL=$((TOTAL + 1))
        
        # Expand tilde
        cert_file="${cert_file/#\~/$HOME}"
        
        if [ $JSON_OUTPUT -eq 1 ]; then
            if [ $FIRST -eq 0 ]; then
                echo ","
            fi
            FIRST=0
        fi
        
        local RESULT=""
        local OLD_QUIET=$QUIET
        local OLD_VERBOSE=$VERBOSE
        
        if [ $JSON_OUTPUT -eq 1 ]; then
            QUIET=1
            VERBOSE=0
        fi
        
        check_certificate "$cert_file" RESULT
        local EXIT_CODE=$?
        
        QUIET=$OLD_QUIET
        VERBOSE=$OLD_VERBOSE
        
        # Get cert info for output
        local CERT_INFO=$(get_cert_info "$cert_file" 2>/dev/null)
        local SERIAL=$(echo "$CERT_INFO" | grep "^SERIAL=" | cut -d= -f2)
        local SUBJECT=$(echo "$CERT_INFO" | grep "^SUBJECT=" | cut -d= -f2-)
        
        if [ $JSON_OUTPUT -eq 1 ]; then
            output_json_result "$cert_file" "$RESULT" "$SERIAL" "$SUBJECT"
        else
            printf "%-50s " "$(basename "$cert_file"):"
            
            if [ "$RESULT" == "valid" ]; then
                echo -e "${GREEN}✓ VALID${COFF}"
                VALID=$((VALID + 1))
            elif [ "$RESULT" == "revoked" ]; then
                echo -e "${RED}✗ REVOKED${COFF}"
                REVOKED=$((REVOKED + 1))
            else
                echo -e "${YELLOW}⚠ ERROR ($RESULT)${COFF}"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    done < "$BATCH_FILE"
    
    if [ $JSON_OUTPUT -eq 1 ]; then
        echo ""
        echo "]"
    else
        echo ""
        echo -e "${BLUE}=== Summary ===${COFF}"
        echo -e "Total:   $TOTAL"
        echo -e "${GREEN}Valid:   $VALID${COFF}"
        echo -e "${RED}Revoked: $REVOKED${COFF}"
        echo -e "${YELLOW}Errors:  $ERRORS${COFF}"
    fi
    
    # Return appropriate exit code
    if [ $ERRORS -gt 0 ]; then
        return 2
    elif [ $REVOKED -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Parse command line arguments
CERT_FILE=""
BATCH_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        --json)
            JSON_OUTPUT=1
            QUIET=1
            shift
            ;;
        --batch)
            BATCH_MODE=1
            BATCH_FILE="$2"
            shift 2
            ;;
        --crl)
            CUSTOM_CRL="$2"
            shift 2
            ;;
        --ca-bundle)
            CUSTOM_CA_BUNDLE="$2"
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$CERT_FILE" ]; then
                CERT_FILE="$1"
            else
                log_error "Multiple certificate files specified. Use --batch for multiple certificates."
                usage
            fi
            shift
            ;;
    esac
done

# Main execution
if [ $BATCH_MODE -eq 1 ]; then
    # Batch mode
    if [ -z "$BATCH_FILE" ]; then
        log_error "Batch file not specified"
        usage
    fi
    batch_check "$BATCH_FILE"
    EXIT_CODE=$?
else
    # Single certificate mode
    if [ -z "$CERT_FILE" ]; then
        log_error "Certificate file not specified"
        usage
    fi
    
    # Expand tilde
    CERT_FILE="${CERT_FILE/#\~/$HOME}"
    
    if [ ! -f "$CERT_FILE" ]; then
        log_error "Certificate file not found: $CERT_FILE"
        exit 2
    fi
    
    RESULT=""
    check_certificate "$CERT_FILE" RESULT
    EXIT_CODE=$?
    
    if [ $JSON_OUTPUT -eq 1 ]; then
        # Get cert info for JSON output
        CERT_INFO=$(get_cert_info "$CERT_FILE" 2>/dev/null)
        SERIAL=$(echo "$CERT_INFO" | grep "^SERIAL=" | cut -d= -f2)
        SUBJECT=$(echo "$CERT_INFO" | grep "^SUBJECT=" | cut -d= -f2-)
        output_json_result "$CERT_FILE" "$RESULT" "$SERIAL" "$SUBJECT"
    else
        echo ""
        echo -e "${BLUE}=== Result ===${COFF}"
        
        if [ "$RESULT" == "valid" ]; then
            echo -e "${GREEN}✓ Certificate is VALID (not revoked)${COFF}"
        elif [ "$RESULT" == "revoked" ]; then
            echo -e "${RED}✗ Certificate is REVOKED${COFF}"
        elif [[ "$RESULT" == error:* ]]; then
            ERROR_TYPE=$(echo "$RESULT" | cut -d: -f2)
            echo -e "${YELLOW}⚠ Error: $ERROR_TYPE${COFF}"
        else
            echo -e "${YELLOW}⚠ Unknown status: $RESULT${COFF}"
        fi
    fi
fi

exit $EXIT_CODE

