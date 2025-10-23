#!/bin/bash
#
# Helper script to add OCSP and CRL URLs to certificate profiles
# This script updates profiles.json to include Authority Information Access
# and CRL Distribution Points extensions
#

set -e

BD="${DEMO_CFSSL_DIR:-$HOME/.config/demo-cfssl}"
PROFILES_JSON="$BD/profiles.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
COFF='\033[0m'

function print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${COFF}"
    echo -e "${BLUE}$1${COFF}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${COFF}"
    echo ""
}

function print_success() {
    echo -e "${GREEN}✓ $1${COFF}"
}

function print_error() {
    echo -e "${RED}✗ $1${COFF}"
}

function print_info() {
    echo -e "${YELLOW}ℹ $1${COFF}"
}

print_header "OCSP & CRL URL Configuration Helper"

# Get configuration from user
read -p "Enter OCSP responder URL [http://localhost:8080/ocsp]: " OCSP_URL
OCSP_URL=${OCSP_URL:-http://localhost:8080/ocsp}

read -p "Enter CRL distribution URL [http://localhost:8080/crl/ica.crl]: " CRL_URL
CRL_URL=${CRL_URL:-http://localhost:8080/crl/ica.crl}

print_info "OCSP URL: $OCSP_URL"
print_info "CRL URL: $CRL_URL"

# Check if profiles.json exists
if [ ! -f "$PROFILES_JSON" ]; then
    print_error "profiles.json not found at $PROFILES_JSON"
    print_info "Please run the certificate generation scripts first"
    exit 1
fi

# Backup original profiles.json
cp "$PROFILES_JSON" "$PROFILES_JSON.bak"
print_success "Backed up profiles.json to profiles.json.bak"

# Note: CFSSL doesn't directly support adding OCSP and CRL URLs via profiles.json
# These extensions need to be added using OpenSSL configuration

print_info "Creating OpenSSL configuration for certificates with OCSP and CRL..."

cat > "$BD/openssl-extensions.cnf" << EOF
# OpenSSL extensions for certificates with OCSP and CRL
# Generated: $(date)

[ v3_server ]
# Server certificate extensions
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer

# OCSP and CRL information
authorityInfoAccess = OCSP;URI:${OCSP_URL}
crlDistributionPoints = URI:${CRL_URL}

[ v3_client ]
# Client certificate extensions
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer

# OCSP and CRL information
authorityInfoAccess = OCSP;URI:${OCSP_URL}
crlDistributionPoints = URI:${CRL_URL}

[ v3_email ]
# Email (S/MIME) certificate extensions
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = emailProtection
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer

# OCSP and CRL information
authorityInfoAccess = OCSP;URI:${OCSP_URL}
crlDistributionPoints = URI:${CRL_URL}

[ v3_peer ]
# Peer certificate extensions (both client and server)
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer

# OCSP and CRL information
authorityInfoAccess = OCSP;URI:${OCSP_URL}
crlDistributionPoints = URI:${CRL_URL}
EOF

print_success "Created OpenSSL extensions configuration at $BD/openssl-extensions.cnf"

print_header "Next Steps"

cat << EOF
${YELLOW}Important:${COFF} CFSSL does not natively support adding OCSP and CRL URLs.
To include these extensions in your certificates, you have two options:

${BLUE}Option 1: Use OpenSSL directly (Recommended)${COFF}

Use the step_*_openssl functions or create certificates with OpenSSL:

  # For host/server certificates:
  openssl x509 -req \\
    -in cert.csr \\
    -CA $BD/ica-ca.pem \\
    -CAkey $BD/ica-key.pem \\
    -CAcreateserial \\
    -out cert.pem \\
    -days 47 \\
    -sha384 \\
    -extfile $BD/openssl-extensions.cnf \\
    -extensions v3_server

  # For email certificates:
  openssl x509 -req \\
    -in email.csr \\
    -CA $BD/ica-ca.pem \\
    -CAkey $BD/ica-key.pem \\
    -CAcreateserial \\
    -out cert.pem \\
    -days 265 \\
    -sha384 \\
    -extfile $BD/openssl-extensions.cnf \\
    -extensions v3_email

${BLUE}Option 2: Use custom wrapper functions${COFF}

See the main README.md for step_host_with_ocsp and step_email_with_ocsp functions
that automatically include OCSP and CRL URLs.

${BLUE}Verify extensions in certificate:${COFF}

  openssl x509 -in cert.pem -noout -text | grep -A5 "Authority Information"
  openssl x509 -in cert.pem -noout -text | grep -A3 "CRL Distribution"

${GREEN}Configuration saved!${COFF}
EOF

