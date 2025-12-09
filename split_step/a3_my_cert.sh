#!/bin/bash
#
# This script generates server certificates using existing Root CA and Intermediate CA
# Assumes ca.pem, ica-ca.pem, and ica-key.pem are available in the certificate directory
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

# Check for required CA files
echo "Checking required CA files..."
MISSING_FILES=0

if [ ! -f "$BD/ica-ca.pem" ]; then
    echo -e "${RED}Error: Intermediate CA certificate not found: ${BLUE}\${BD}/ica-ca.pem${COFF}" >&2
    MISSING_FILES=1
fi

if [ ! -f "$BD/ica-key.pem" ]; then
    echo -e "${RED}Error: Intermediate CA private key not found: ${BLUE}\${BD}/ica-key.pem${COFF}" >&2
    MISSING_FILES=1
fi

if [ $MISSING_FILES -eq 1 ]; then
    echo -e "${RED}Please ensure the required CA files are available in: ${BLUE}\${BD}${COFF}" >&2
    exit 1
fi

echo -e "${GREEN}All required CA files found${COFF}"

# Display ICA certificate information
display_ica_info "$BD"

# ============================================================================
# FUNCTIONS
# ============================================================================

function to_relative_path() {
    local file=$1
    # Replace BD with ${BD} if the path starts with BD
    if [[ "$file" == "$BD"/* ]]; then
        echo "\${BD}${file#$BD}"
    else
        echo "$file"
    fi
}

function get_file_description() {
    local file=$1
    local basename_file=$(basename "$file")
    case "$basename_file" in
        openssl.cnf)
            echo "OpenSSL configuration file (used during generation)"
            ;;
        key.pem)
            echo "Private key (used by: Nginx, Apache, Traefik, all TLS servers)"
            ;;
        host.csr)
            echo "Certificate Signing Request (used during generation)"
            ;;
        cert.pem)
            echo "Server certificate (use with key.pem + CA chain for: Nginx, Apache, Traefik)"
            ;;
        bundle-2.pem)
            echo "Certificate bundle (cert + ICA) - use with key.pem for: Nginx, Apache, Traefik"
            ;;
        bundle-3.pem)
            echo "Certificate bundle (cert + ICA + Root CA) - use with key.pem for: Nginx, Apache, Traefik"
            ;;
        haproxy.pem)
            echo "HAProxy bundle (cert + ICA + Root CA + key) - ready for HAProxy"
            ;;
        *)
            echo ""
            ;;
    esac
}

function list_existing_files() {
    local name=$1
    local dir="$BD/hosts/${name}"
    local files_found=0
    
    echo ""
    echo -e "${AZURE}Available files for '${name}':${COFF}"
    
    # List of files to check (in order of importance)
    local files_to_check=(
        "cert.pem"
        "key.pem"
        "bundle-3.pem"
        "bundle-2.pem"
        "haproxy.pem"
        "host.csr"
        "openssl.cnf"
    )
    
    for filename in "${files_to_check[@]}"; do
        local filepath="${dir}/${filename}"
        if [ -f "$filepath" ]; then
            local rel_path=$(to_relative_path "$filepath")
            local desc=$(get_file_description "$filepath")
            if [ -n "$desc" ]; then
                printf "  ${GREEN}✓${COFF} ${BLUE}%s${COFF} ${AZURE}(%s)${COFF}\n" "$rel_path" "$desc"
            else
                printf "  ${GREEN}✓${COFF} ${BLUE}%s${COFF}\n" "$rel_path"
            fi
            files_found=1
        fi
    done
    
    if [ $files_found -eq 0 ]; then
        echo -e "  ${YELLOW}No certificate files found${COFF}"
    fi
    echo ""
}

function ask_confirmation() {
    local operations=$1
    echo ""
    echo -e "${YELLOW}The following file operations will be performed:${COFF}"
    echo -e "$operations"
    echo ""
    echo -e "${YELLOW}Do you want to proceed? (yes/no):${COFF} "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            echo -e "${RED}Operation cancelled${COFF}"
            return 1
            ;;
    esac
}

function step03() {
    local NAME=$1
    shift
    ALT_NAMES=$@
    mkdir -p $BD/hosts/$NAME
    
    # Collect file operations
    OPERATIONS=""
    FILES_TO_DELETE=()
    FILES_TO_WRITE=()
    
    # check the validity of the certificate
    if [ -f "$BD/hosts/${NAME}/cert.pem" ]; then
        END_DATE=`$OPENSSL x509 -in "$BD/hosts/${NAME}/cert.pem" -noout -enddate | cut -d"=" -f2`
        END_DATE_SECS=`$DATE -d "$END_DATE" +%s`
        NUNIXTS=`$DATE +%s`
        if [ $END_DATE_SECS -lt $NUNIXTS ]; then
            echo -e "The certificate ${BLUE}\${BD}/hosts/${NAME}/cert.pem${COFF} is expired"
            FILES_TO_DELETE+=("$BD/hosts/${NAME}/cert.pem")
            FILES_TO_DELETE+=("$BD/hosts/${NAME}/key.pem")
            FILES_TO_DELETE+=("$BD/hosts/${NAME}/host.csr")
            FILES_TO_DELETE+=("$BD/hosts/${NAME}/openssl.cnf")
            FILES_TO_DELETE+=("$BD/hosts/${NAME}/bundle-2.pem")
            # Only delete bundle-3.pem and haproxy.pem if they exist
            [ -f "$BD/hosts/${NAME}/bundle-3.pem" ] && FILES_TO_DELETE+=("$BD/hosts/${NAME}/bundle-3.pem")
            [ -f "$BD/hosts/${NAME}/haproxy.pem" ] && FILES_TO_DELETE+=("$BD/hosts/${NAME}/haproxy.pem")
        else
            echo -e "The certificate ${BLUE}\${BD}/hosts/${NAME}/cert.pem${COFF} is still valid"
            list_existing_files "$NAME"
            x509info $BD/hosts/${NAME}/cert.pem
            return 0
        fi
    fi
    
    if [ ! -f $BD/hosts/${NAME}/cert.pem ]; then
        echo "Preparing to generate server '$NAME' certificate"
        
        # Files that will be created/written
        FILES_TO_WRITE+=("$BD/hosts/${NAME}/openssl.cnf")
        FILES_TO_WRITE+=("$BD/hosts/${NAME}/key.pem")
        FILES_TO_WRITE+=("$BD/hosts/${NAME}/host.csr")
        FILES_TO_WRITE+=("$BD/hosts/${NAME}/cert.pem")
        FILES_TO_WRITE+=("$BD/hosts/${NAME}/bundle-2.pem")
        # Only include bundle-3.pem and haproxy.pem if ca.pem exists
        if [ -f "$BD/ca.pem" ]; then
            FILES_TO_WRITE+=("$BD/hosts/${NAME}/bundle-3.pem")
            FILES_TO_WRITE+=("$BD/hosts/${NAME}/haproxy.pem")
        fi
        
        # Build operations list
        if [ ${#FILES_TO_DELETE[@]} -gt 0 ]; then
            OPERATIONS="${OPERATIONS}${RED}DELETE:${COFF}\n"
            for file in "${FILES_TO_DELETE[@]}"; do
                if [ -f "$file" ]; then
                    REL_PATH=$(to_relative_path "$file")
                    DESC=$(get_file_description "$file")
                    if [ -n "$DESC" ]; then
                        OPERATIONS="${OPERATIONS}  - ${BLUE}${REL_PATH}${COFF} ${AZURE}(${DESC})${COFF}\n"
                    else
                        OPERATIONS="${OPERATIONS}  - ${BLUE}${REL_PATH}${COFF}\n"
                    fi
                fi
            done
            OPERATIONS="${OPERATIONS}\n"
        fi
        
        OPERATIONS="${OPERATIONS}${GREEN}CREATE/WRITE:${COFF}\n"
        for file in "${FILES_TO_WRITE[@]}"; do
            REL_PATH=$(to_relative_path "$file")
            DESC=$(get_file_description "$file")
            if [ -f "$file" ]; then
                if [ -n "$DESC" ]; then
                    OPERATIONS="${OPERATIONS}  - ${BLUE}${REL_PATH}${COFF} ${AZURE}(${DESC})${COFF} ${YELLOW}(will overwrite)${COFF}\n"
                else
                    OPERATIONS="${OPERATIONS}  - ${BLUE}${REL_PATH}${COFF} ${YELLOW}(will overwrite)${COFF}\n"
                fi
            else
                if [ -n "$DESC" ]; then
                    OPERATIONS="${OPERATIONS}  - ${BLUE}${REL_PATH}${COFF} ${AZURE}(${DESC})${COFF}\n"
                else
                    OPERATIONS="${OPERATIONS}  - ${BLUE}${REL_PATH}${COFF}\n"
                fi
            fi
        done
        
        # Ask for confirmation
        if ! ask_confirmation "$OPERATIONS"; then
            return 1
        fi
        
        # Execute deletions
        if [ ${#FILES_TO_DELETE[@]} -gt 0 ]; then
            echo "Removing expired certificate files..."
            for file in "${FILES_TO_DELETE[@]}"; do
                rm -f "$file"
            done
        fi
        
        # Use certificate subject fields from variables
        CN="$NAME"
        C="$CERT_C"
        ST="$CERT_ST"
        L="$CERT_L"
        O="$CERT_O"
        OU="$CERT_OU"
        
        # Build Subject Alternative Name string from NAME and ALT_NAMES
        SAN_STRING="DNS:${NAME}"
        for host in ${ALT_NAMES[@]}; do
            SAN_STRING="${SAN_STRING},DNS:${host}"
        done
        
        # Calculate certificate validity in days (HOST_EXPIRY is in hours)
        CERT_DAYS=$((HOST_EXPIRY / 24))
        
        # Create OpenSSL config file
        cat > $BD/hosts/${NAME}/openssl.cnf <<EOF
[ req ]
default_bits        = 2048
default_md          = sha384
default_keyfile     = key.pem
prompt              = no
encrypt_key         = no
distinguished_name  = req_dn
req_extensions      = v3_req

[ req_dn ]
C                   = ${C}
ST                  = ${ST}
L                   = ${L}
O                   = ${O}
OU                  = ${OU}
CN                  = ${CN}

[ v3_req ]
# Extensions for server certificate
keyUsage            = critical, digitalSignature, keyEncipherment
extendedKeyUsage    = serverAuth
subjectAltName      = ${SAN_STRING}
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash

[ v3_ca ]
# Extensions for signing (CA perspective)
keyUsage            = critical, digitalSignature, keyEncipherment
extendedKeyUsage    = serverAuth
subjectAltName      = ${SAN_STRING}
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF
        
        # Generate private key (ECDSA P-384)
        echo "Generating private key..."
        $OPENSSL genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
            -out $BD/hosts/${NAME}/key.pem 2>/dev/null
        
        # Generate Certificate Signing Request
        echo "Generating Certificate Signing Request..."
        $OPENSSL req -new \
            -key $BD/hosts/${NAME}/key.pem \
            -out $BD/hosts/${NAME}/host.csr \
            -config $BD/hosts/${NAME}/openssl.cnf 2>/dev/null
        
        # Sign the certificate with Intermediate CA
        echo "Signing certificate with Intermediate CA..."
        $OPENSSL x509 -req \
            -in $BD/hosts/${NAME}/host.csr \
            -CA $BD/ica-ca.pem \
            -CAkey $BD/ica-key.pem \
            -CAcreateserial \
            -out $BD/hosts/${NAME}/cert.pem \
            -days ${CERT_DAYS} \
            -sha384 \
            -extfile $BD/hosts/${NAME}/openssl.cnf \
            -extensions v3_ca 2>/dev/null
        
        # concatenate the server, intermediate
        cat $BD/hosts/${NAME}/cert.pem $BD/ica-ca.pem > $BD/hosts/${NAME}/bundle-2.pem
        # concatenate the server, intermediate and root ca (only if ca.pem exists)
        if [ -f "$BD/ca.pem" ]; then
            cat $BD/hosts/${NAME}/cert.pem $BD/ica-ca.pem $BD/ca.pem > $BD/hosts/${NAME}/bundle-3.pem
            # also create file suitable for haproxy w/key (server, intermediate, root + key)
            cat $BD/hosts/${NAME}/bundle-3.pem $BD/hosts/${NAME}/key.pem > $BD/hosts/${NAME}/haproxy.pem
        fi
    else
        echo -e "Certificate ${BLUE}\${BD}/hosts/${NAME}/cert.pem${COFF} already exists"
    fi
    
    # Always show the list of available files
    list_existing_files "$NAME"
    x509info $BD/hosts/${NAME}/cert.pem
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================
# Example usage:
# step03 <name> <alt_names>

step03 my.example.com your.example.com '*.example.com'
