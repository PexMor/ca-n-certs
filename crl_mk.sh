#!/bin/bash
#
# crl_mk.sh - Certificate Revocation List (CRL) Management Script
#
# This script creates and manages Certificate Revocation Lists (CRLs)
# It can revoke certificates and generate properly signed CRLs
#
# Usage:
#   ./crl_mk.sh [BD_PATH] [revoke CERT_FILE [REASON]]
#   ./crl_mk.sh [BD_PATH] generate [ca|ica]
#   ./crl_mk.sh [BD_PATH] list [ca|ica]
#   ./crl_mk.sh [BD_PATH] info [ca|ica]
#
# Examples:
#   ./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/localhost/cert.pem keyCompromise
#   ./crl_mk.sh generate ica
#   ./crl_mk.sh list ica
#

set -e

DEF_BD="$HOME/.config/demo-cfssl"
BD=${1:-$DEF_BD}

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
COFF='\033[0m'

# Ensure base directory exists
[ -d "$BD" ] || mkdir -p "$BD"

# CRL directories for Root CA and Intermediate CA
CRL_CA_DIR="$BD/crl/ca"
CRL_ICA_DIR="$BD/crl/ica"

function usage() {
    echo "Usage: $0 [BD_PATH] COMMAND [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  revoke CERT_FILE [REASON]   - Revoke a certificate"
    echo "  generate [ca|ica]           - Generate CRL for CA (default: ica)"
    echo "  list [ca|ica]               - List revoked certificates"
    echo "  info [ca|ica]               - Show CRL information"
    echo ""
    echo "Revocation Reasons:"
    echo "  unspecified                 - Default reason"
    echo "  keyCompromise               - Private key compromised"
    echo "  CACompromise                - CA key compromised"
    echo "  affiliationChanged          - Certificate holder changed affiliation"
    echo "  superseded                  - Certificate replaced"
    echo "  cessationOfOperation        - Certificate no longer needed"
    echo "  certificateHold             - Temporarily revoked"
    echo ""
    echo "Examples:"
    echo "  $0 revoke $BD/hosts/localhost/cert.pem keyCompromise"
    echo "  $0 generate ica"
    echo "  $0 list ica"
    echo "  $0 info ica"
    exit 1
}

function init_crl_db() {
    local CA_TYPE=$1  # "ca" or "ica"
    local CRL_DIR
    local CA_CERT
    local CA_KEY
    
    if [ "$CA_TYPE" == "ca" ]; then
        CRL_DIR="$CRL_CA_DIR"
        CA_CERT="$BD/ca.pem"
        CA_KEY="$BD/ca-key.pem"
    elif [ "$CA_TYPE" == "ica" ]; then
        CRL_DIR="$CRL_ICA_DIR"
        CA_CERT="$BD/ica-ca.pem"
        CA_KEY="$BD/ica-key.pem"
    else
        echo "Error: Invalid CA type. Must be 'ca' or 'ica'"
        return 1
    fi
    
    # Check if CA exists
    if [ ! -f "$CA_CERT" ]; then
        echo -e "${RED}Error: CA certificate not found: $CA_CERT${COFF}"
        echo "Please run mkCert.sh or steps.sh first to create the CA"
        return 1
    fi
    
    if [ ! -f "$CA_KEY" ]; then
        echo -e "${RED}Error: CA key not found: $CA_KEY${COFF}"
        return 1
    fi
    
    # Create CRL directory structure
    mkdir -p "$CRL_DIR"
    
    # Initialize database if it doesn't exist
    if [ ! -f "$CRL_DIR/index.txt" ]; then
        touch "$CRL_DIR/index.txt"
        echo -e "${GREEN}Created CRL database: $CRL_DIR/index.txt${COFF}"
    fi
    
    # Initialize serial number for CRL
    if [ ! -f "$CRL_DIR/crlnumber" ]; then
        echo "01" > "$CRL_DIR/crlnumber"
        echo -e "${GREEN}Initialized CRL number: $CRL_DIR/crlnumber${COFF}"
    fi
    
    # Create OpenSSL configuration for CRL
    cat > "$CRL_DIR/openssl.cnf" << EOF
# OpenSSL configuration for CRL generation
# Generated: $(date)

[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $CRL_DIR
database          = \$dir/index.txt
serial            = \$dir/serial
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha384

certificate       = $CA_CERT
private_key       = $CA_KEY

[ crl_ext ]
# CRL extensions
authorityKeyIdentifier = keyid:always
EOF
    
    echo -e "${GREEN}Initialized CRL database for $CA_TYPE${COFF}"
}

function revoke_cert() {
    local CERT_FILE=$1
    local REASON=${2:-unspecified}
    
    if [ ! -f "$CERT_FILE" ]; then
        echo -e "${RED}Error: Certificate file not found: $CERT_FILE${COFF}"
        return 1
    fi
    
    # Determine which CA issued this certificate
    local ISSUER_CN=$(openssl x509 -in "$CERT_FILE" -noout -issuer | grep -o "CN=[^,]*" | cut -d= -f2)
    local CA_TYPE
    
    if echo "$ISSUER_CN" | grep -q "Root"; then
        CA_TYPE="ca"
        echo -e "${BLUE}Certificate was issued by Root CA${COFF}"
    else
        CA_TYPE="ica"
        echo -e "${BLUE}Certificate was issued by Intermediate CA${COFF}"
    fi
    
    # Initialize CRL database if needed
    init_crl_db "$CA_TYPE"
    
    local CRL_DIR
    local CA_CERT
    local CA_KEY
    
    if [ "$CA_TYPE" == "ca" ]; then
        CRL_DIR="$CRL_CA_DIR"
        CA_CERT="$BD/ca.pem"
        CA_KEY="$BD/ca-key.pem"
    else
        CRL_DIR="$CRL_ICA_DIR"
        CA_CERT="$BD/ica-ca.pem"
        CA_KEY="$BD/ica-key.pem"
    fi
    
    # Get certificate serial number
    local SERIAL=$(openssl x509 -in "$CERT_FILE" -noout -serial | cut -d= -f2)
    local SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject)
    
    echo -e "${AZURE}Certificate Details:${COFF}"
    echo -e "  ${AZURE}Subject:${COFF} $SUBJECT"
    echo -e "  ${AZURE}Serial:${COFF}  $SERIAL"
    echo -e "  ${AZURE}Reason:${COFF}  $REASON"
    
    # Check if certificate is already revoked
    if grep -q "^R.*$SERIAL" "$CRL_DIR/index.txt" 2>/dev/null; then
        echo -e "${YELLOW}Warning: Certificate is already revoked${COFF}"
        return 0
    fi
    
    # Add certificate to revocation database
    # Format: R	revocation_date	[reason]	serial	subject_dn
    local REVOKE_DATE=$($DATE -u +"%y%m%d%H%M%SZ")
    local SUBJECT_DN=$(openssl x509 -in "$CERT_FILE" -noout -subject -nameopt RFC2253 | cut -d= -f2-)
    
    # Get certificate validity dates
    local NOT_AFTER=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
    local EXPIRY_DATE=$($DATE -d "$NOT_AFTER" -u +"%y%m%d%H%M%SZ")
    
    # Build the index.txt entry
    # Format: flag expiry_date revocation_date serial unknown subject
    echo "R	${EXPIRY_DATE}	${REVOKE_DATE},${REASON}	${SERIAL}	unknown	${SUBJECT_DN}" >> "$CRL_DIR/index.txt"
    
    echo -e "${GREEN}✓ Certificate revoked successfully${COFF}"
    echo -e "${YELLOW}Note: Run './crl_mk.sh generate $CA_TYPE' to update the CRL${COFF}"
}

function generate_crl() {
    local CA_TYPE=${1:-ica}
    
    # Initialize CRL database if needed
    init_crl_db "$CA_TYPE"
    
    local CRL_DIR
    local CA_CERT
    local CA_KEY
    local CRL_FILE
    
    if [ "$CA_TYPE" == "ca" ]; then
        CRL_DIR="$CRL_CA_DIR"
        CA_CERT="$BD/ca.pem"
        CA_KEY="$BD/ca-key.pem"
        CRL_FILE="$BD/ca-crl.pem"
    else
        CRL_DIR="$CRL_ICA_DIR"
        CA_CERT="$BD/ica-ca.pem"
        CA_KEY="$BD/ica-key.pem"
        CRL_FILE="$BD/ica-crl.pem"
    fi
    
    echo -e "${BLUE}Generating CRL for $CA_TYPE...${COFF}"
    
    # Generate CRL
    openssl ca -gencrl \
        -config "$CRL_DIR/openssl.cnf" \
        -out "$CRL_FILE" \
        -cert "$CA_CERT" \
        -keyfile "$CA_KEY" 2>/dev/null
    
    # Also save a copy in the CRL directory
    cp "$CRL_FILE" "$CRL_DIR/crl.pem"
    
    # Convert to DER format (some applications prefer this)
    openssl crl -in "$CRL_FILE" -outform DER -out "${CRL_FILE%.pem}.der"
    
    echo -e "${GREEN}✓ CRL generated successfully${COFF}"
    echo -e "  ${AZURE}PEM format:${COFF} $CRL_FILE"
    echo -e "  ${AZURE}DER format:${COFF} ${CRL_FILE%.pem}.der"
    
    # Display CRL information
    info_crl "$CA_TYPE"
}

function list_crl() {
    local CA_TYPE=${1:-ica}
    
    local CRL_DIR
    if [ "$CA_TYPE" == "ca" ]; then
        CRL_DIR="$CRL_CA_DIR"
    else
        CRL_DIR="$CRL_ICA_DIR"
    fi
    
    if [ ! -f "$CRL_DIR/index.txt" ]; then
        echo -e "${YELLOW}No revocation database found for $CA_TYPE${COFF}"
        return 0
    fi
    
    echo -e "${AZURE}=== Revoked Certificates ($CA_TYPE) ===${COFF}"
    echo ""
    
    # Count revoked certificates
    local COUNT=$(grep -c "^R" "$CRL_DIR/index.txt" 2>/dev/null || echo "0")
    
    if [ "$COUNT" -eq "0" ]; then
        echo -e "${GREEN}No revoked certificates${COFF}"
        return 0
    fi
    
    echo -e "${YELLOW}Total revoked: $COUNT${COFF}"
    echo ""
    
    # Parse and display revoked certificates
    grep "^R" "$CRL_DIR/index.txt" | while IFS=$'\t' read -r flag expiry revoke_info serial unknown subject; do
        # Parse revocation date and reason from revoke_info
        local REVOKE_DATE=$(echo "$revoke_info" | cut -d, -f1)
        local REASON=$(echo "$revoke_info" | cut -d, -f2)
        
        # Format dates
        local REV_DATE_FORMATTED=$($DATE -d "20${REVOKE_DATE:0:2}-${REVOKE_DATE:2:2}-${REVOKE_DATE:4:2} ${REVOKE_DATE:6:2}:${REVOKE_DATE:8:2}:${REVOKE_DATE:10:2}" +"%Y-%m-%d %H:%M:%S UTC" 2>/dev/null || echo "$REVOKE_DATE")
        
        echo -e "${RED}Serial:${COFF} $serial"
        echo -e "${RED}Revoked:${COFF} $REV_DATE_FORMATTED"
        echo -e "${RED}Reason:${COFF} $REASON"
        echo -e "${RED}Subject:${COFF} $subject"
        echo ""
    done
}

function info_crl() {
    local CA_TYPE=${1:-ica}
    
    local CRL_FILE
    if [ "$CA_TYPE" == "ca" ]; then
        CRL_FILE="$BD/ca-crl.pem"
    else
        CRL_FILE="$BD/ica-crl.pem"
    fi
    
    if [ ! -f "$CRL_FILE" ]; then
        echo -e "${YELLOW}No CRL found for $CA_TYPE. Run 'generate $CA_TYPE' first.${COFF}"
        return 0
    fi
    
    echo -e "${AZURE}=== CRL Information ($CA_TYPE) ===${COFF}"
    echo ""
    
    # Display CRL details
    openssl crl -in "$CRL_FILE" -noout -text | grep -A 20 "Certificate Revocation List" | head -20
    
    echo ""
    echo -e "${AZURE}=== CRL Validity ===${COFF}"
    
    # Get last update and next update
    local LAST_UPDATE=$(openssl crl -in "$CRL_FILE" -noout -lastupdate | cut -d= -f2)
    local NEXT_UPDATE=$(openssl crl -in "$CRL_FILE" -noout -nextupdate | cut -d= -f2)
    
    echo -e "${GREEN}Last Update:${COFF} $LAST_UPDATE"
    echo -e "${GREEN}Next Update:${COFF} $NEXT_UPDATE"
    
    # Check how many days until next update
    local NEXT_UPDATE_SECS=$($DATE -d "$NEXT_UPDATE" +%s)
    local NOW_SECS=$($DATE +%s)
    local DAYS_LEFT=$(( ($NEXT_UPDATE_SECS - $NOW_SECS) / 86400 ))
    
    if [ $DAYS_LEFT -lt 0 ]; then
        echo -e "${RED}Status: CRL is EXPIRED (regenerate needed)${COFF}"
    elif [ $DAYS_LEFT -lt 7 ]; then
        echo -e "${YELLOW}Status: CRL expires in $DAYS_LEFT days (regenerate soon)${COFF}"
    else
        echo -e "${GREEN}Status: CRL is valid ($DAYS_LEFT days remaining)${COFF}"
    fi
    
    # Count revoked certificates in CRL
    echo ""
    local REVOKED_COUNT=$(openssl crl -in "$CRL_FILE" -noout -text | grep -c "Serial Number:" || echo "0")
    echo -e "${AZURE}Revoked Certificates:${COFF} $REVOKED_COUNT"
}

function verify_cert_with_crl() {
    local CERT_FILE=$1
    local CA_TYPE=${2:-ica}
    
    if [ ! -f "$CERT_FILE" ]; then
        echo -e "${RED}Error: Certificate file not found: $CERT_FILE${COFF}"
        return 1
    fi
    
    local CRL_FILE
    local CA_BUNDLE
    
    if [ "$CA_TYPE" == "ca" ]; then
        CRL_FILE="$BD/ca-crl.pem"
        CA_BUNDLE="$BD/ca.pem"
    else
        CRL_FILE="$BD/ica-crl.pem"
        CA_BUNDLE="$BD/ca-bundle.pem"
    fi
    
    if [ ! -f "$CRL_FILE" ]; then
        echo -e "${YELLOW}No CRL found. Run 'generate $CA_TYPE' first.${COFF}"
        return 1
    fi
    
    echo -e "${AZURE}Verifying certificate against CRL...${COFF}"
    
    # Verify certificate with CRL check
    if openssl verify -CAfile "$CA_BUNDLE" -crl_check -CRLfile "$CRL_FILE" "$CERT_FILE" 2>&1; then
        echo -e "${GREEN}✓ Certificate is valid and not revoked${COFF}"
        return 0
    else
        echo -e "${RED}✗ Certificate verification failed (may be revoked)${COFF}"
        return 1
    fi
}

# Main script logic
if [ $# -lt 1 ]; then
    usage
fi

# Shift BD parameter if it looks like a path
if [[ "$1" == /* ]] || [[ "$1" =~ ^\~ ]]; then
    BD="$1"
    shift
fi

# If no command provided after BD, show usage
if [ $# -lt 1 ]; then
    usage
fi

COMMAND=$1
shift

case "$COMMAND" in
    revoke)
        if [ $# -lt 1 ]; then
            echo -e "${RED}Error: Certificate file required${COFF}"
            usage
        fi
        CERT_FILE="$1"
        REASON="${2:-unspecified}"
        revoke_cert "$CERT_FILE" "$REASON"
        ;;
    generate)
        CA_TYPE="${1:-ica}"
        generate_crl "$CA_TYPE"
        ;;
    list)
        CA_TYPE="${1:-ica}"
        list_crl "$CA_TYPE"
        ;;
    info)
        CA_TYPE="${1:-ica}"
        info_crl "$CA_TYPE"
        ;;
    verify)
        if [ $# -lt 1 ]; then
            echo -e "${RED}Error: Certificate file required${COFF}"
            usage
        fi
        CERT_FILE="$1"
        CA_TYPE="${2:-ica}"
        verify_cert_with_crl "$CERT_FILE" "$CA_TYPE"
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$COMMAND'${COFF}"
        usage
        ;;
esac

