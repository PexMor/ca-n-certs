#!/bin/bash
#
# This script generates Root CA and Intermediate CA certificates using OpenSSL
# Please set the BD variable to the directory where the certificates will be stored
#

# stop on error
set -euo pipefail

# ============================================================================
# SOURCE CONFIGURATION AND LIBRARY FILES
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/a0_cfg.sh"
source "$SCRIPT_DIR/a1_lib.sh"

# ============================================================================
# INITIALIZATION
# ============================================================================

# Check for required binaries and detect OS
echo "Checking required binaries..."
detect_os_and_set_commands

# Set base directory (from command line argument or default)
BD=${1:-$DEF_BD}
[ -d "$BD" ] || mkdir -p "$BD"

# Display base directory
echo -e "${AZURE}Base directory:${COFF} BD=${BLUE}${BD}${COFF}"
echo ""

# Calculate certificate validity in days (CA_EXPIRY is in hours)
CA_DAYS=$((CA_EXPIRY / 24))

# ============================================================================
# FUNCTIONS
# ============================================================================

function step01() {
    # Generate Root CA (self-signed)
    if [ ! -f "$BD/ca-key.pem" ]; then
        echo "Making Root CA..."
        echo "Making self-signed Root CA : ca-key.pem, ca.pem, etc."
        
        # Create OpenSSL config file for Root CA
        cat > "$BD/ca-openssl.cnf" <<EOF
# OpenSSL configuration for Root CA certificate generation
# Generated: $(date)

[ req ]
default_bits        = 2048
default_md          = sha384
default_keyfile     = ca-key.pem
prompt              = no
encrypt_key         = no
distinguished_name  = req_dn
req_extensions      = v3_ca

[ req_dn ]
C                   = ${CERT_C}
ST                  = ${CERT_ST}
L                   = ${CERT_L}
O                   = ${CERT_O}
OU                  = ${CERT_OU}
CN                  = ${CA_CN}

[ v3_ca ]
# Extensions for Root CA certificate
keyUsage            = critical, cRLSign, keyCertSign
basicConstraints    = critical, CA:TRUE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF
        
        # Generate private key (ECDSA P-384)
        echo "Generating Root CA private key..."
        $OPENSSL genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
            -out "$BD/ca-key.pem" 2>/dev/null
        
        # Generate self-signed Root CA certificate
        echo "Generating self-signed Root CA certificate..."
        $OPENSSL req -new -x509 \
            -key "$BD/ca-key.pem" \
            -out "$BD/ca.pem" \
            -days ${CA_DAYS} \
            -sha384 \
            -config "$BD/ca-openssl.cnf" \
            -extensions v3_ca 2>/dev/null
        
        echo -e "${GREEN}Root CA generated successfully${COFF}"
    else
        echo "Root CA exists"
    fi
    
    echo "--=[ Root CA files:"
    # display file size and date created
    info "$BD/ca-key.pem"
    info "$BD/ca.pem"
    x509info "$BD/ca.pem"
}

function step02() {
    # Generate Intermediate CA (signed by Root CA)
    if [ ! -f "$BD/ica-key.pem" ]; then
        echo "Making Intermediate CA..."
        echo "Making Root CA signed Intermediate CA : ica-key.pem, ica-ca.pem, etc."
        
        # Check if Root CA exists
        if [ ! -f "$BD/ca.pem" ] || [ ! -f "$BD/ca-key.pem" ]; then
            echo -e "${RED}Error: Root CA not found. Please run step01 first.${COFF}" >&2
            exit 1
        fi
        
        # Create OpenSSL config file for Intermediate CA
        cat > "$BD/ica-openssl.cnf" <<EOF
# OpenSSL configuration for Intermediate CA certificate generation
# Generated: $(date)

[ req ]
default_bits        = 2048
default_md          = sha384
default_keyfile     = ica-key.pem
prompt              = no
encrypt_key         = no
distinguished_name  = req_dn
req_extensions      = v3_req

[ req_dn ]
C                   = ${CERT_C}
ST                  = ${CERT_ST}
L                   = ${CERT_L}
O                   = ${CERT_O}
OU                  = ${CERT_OU}
CN                  = ${ICA_CN}

[ v3_req ]
# Extensions for Intermediate CA certificate request
keyUsage            = critical, cRLSign, keyCertSign
basicConstraints    = critical, CA:TRUE, pathlen:0
subjectKeyIdentifier = hash

[ v3_ca ]
# Extensions for signing (CA perspective)
keyUsage            = critical, cRLSign, keyCertSign
basicConstraints    = critical, CA:TRUE, pathlen:0
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF
        
        # Generate private key (ECDSA P-384)
        echo "Generating Intermediate CA private key..."
        $OPENSSL genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
            -out "$BD/ica-key.pem" 2>/dev/null
        
        # Generate Certificate Signing Request (CSR)
        echo "Generating Intermediate CA Certificate Signing Request..."
        $OPENSSL req -new \
            -key "$BD/ica-key.pem" \
            -out "$BD/ica.csr" \
            -config "$BD/ica-openssl.cnf" \
            -extensions v3_req 2>/dev/null
        
        # Sign the Intermediate CA certificate with Root CA
        echo "Signing Intermediate CA certificate with Root CA..."
        $OPENSSL x509 -req \
            -in "$BD/ica.csr" \
            -CA "$BD/ca.pem" \
            -CAkey "$BD/ca-key.pem" \
            -CAcreateserial \
            -out "$BD/ica-ca.pem" \
            -days ${CA_DAYS} \
            -sha384 \
            -extfile "$BD/ica-openssl.cnf" \
            -extensions v3_ca 2>/dev/null
        
        echo -e "${GREEN}Intermediate CA generated successfully${COFF}"
    else
        echo "Intermediate CA exists"
    fi
    
    echo "--=[ Intermediate CA files:"
    # display file size and date created
    info "$BD/ica-key.pem"
    info "$BD/ica-ca.pem"
    x509info "$BD/ica-ca.pem"
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================
# Step 1 - prepare the Root CA (if not exists)
# usually you run this step only once (or once every 10 years = expiry date - 10%)

step01 # prepare the Root CA

# Step 2 - prepare the Intermediate CA (if not exists)
# usually you run this step only once (or once every 10 years = expiry date - 10%)
step02 # prepare the Intermediate CA
