#!/bin/bash
#
# This script splits the mkCert.sh into three parts
# please set the BD variable to the directory where the certificates will be stored
#

# stop on error
set -e

DEF_BD="$HOME/.config/demo-cfssl"
BD=${1:-$DEF_BD}
# check whether your are running on MacOS or Linux
# and set the STAT to point either stat or gstat
if [ "$(uname)" == "Darwin" ]; then
    STAT="gstat"
    DATE="gdate"
    SED="gsed"
else
    STAT="stat"
    DATE="date"
    SED="sed"
fi
DFMT="%Y/%m/%d %H:%M:%S %Z"
# ansi colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
AZURE='\033[0;36m'
YELLOW='\033[1;33m'
# BRIGHTYELLOW='\033[1;33m'
COFF='\033[0m'

[ -d "$BD" ] || mkdir -p "$BD"

# KEY_ALGO="rsa"
# KEY_SIZE=4096
KEY_ALGO="ecdsa"
KEY_SIZE=384
CA_EXPIRY=`expr 365 \* 24`
HOST_EXPIRY=`expr 47 \* 24`
EMAIL_EXPIRY=`expr 265 \* 24`

JSON_00_CA=`cat <<EOF
{
    "CN": "000-AtHome-Root-CA",
    "key": {
        "algo": "$KEY_ALGO",
        "size": $KEY_SIZE
    },
    "names": [
        {
            "C": "CZ",
            "L": "Prague",
            "O": "At Home Company",
            "OU": "Security Dept.",
            "ST": "Heart of Europe"
        }
    ],
    "ca": {
        "expiry": "${CA_EXPIRY}h"
    }
}
EOF
`

JSON_01_ICA=`cat <<EOF
{
    "CN": "000-AtHome-Intermediate-CA",
    "key": {
        "algo": "$KEY_ALGO",
        "size": $KEY_SIZE
    },
    "names": [
        {
            "C": "CZ",
            "L": "Prague",
            "O": "At Home Company",
            "OU": "Security Dept.",
            "ST": "Heart of Europe"
        }
    ],
    "ca": {
        "expiry": "${CA_EXPIRY}h"
    }
}
EOF
`

JSON_02_HOST=`cat <<EOF
{
    "CN": "localhost",
    "key": {
        "algo": "$KEY_ALGO",
        "size": $KEY_SIZE
    },
    "expiry": "${HOST_EXPIRY}h",
    "names": [
        {
            "C": "CZ",
            "L": "Prague",
            "O": "At Home Company",
            "OU": "Security Dept.",
            "ST": "Heart of Europe"
        }
    ],
    "hosts": [
        "localhost",
        "*.lan"
    ]
}
EOF
`

JSON_03_EMAIL=`cat <<EOF
{
    "CN": "User Name",
    "key": {
        "algo": "$KEY_ALGO",
        "size": $KEY_SIZE
    },
    "expiry": "${EMAIL_EXPIRY}h",
    "names": [
        {
            "C": "CZ",
            "L": "Prague",
            "O": "At Home Company",
            "OU": "Security Dept.",
            "ST": "Heart of Europe"
        }
    ],
    "hosts": []
}
EOF
`

JSON_PROFILES=`cat <<EOF
{
    "signing": {
        "default": {
            "expiry": "${CA_EXPIRY}h"
        },
        "profiles": {
            "intermediate_ca": {
                "usages": [
                    "signing",
                    "digital signature",
                    "key encipherment",
                    "cert sign",
                    "crl sign",
                    "server auth",
                    "client auth"
                ],
                "expiry": "${CA_EXPIRY}h",
                "ca_constraint": {
                    "is_ca": true,
                    "max_path_len": 0,
                    "max_path_len_zero": true
                }
            },
            "peer": {
                "usages": [
                    "signing",
                    "digital signature",
                    "key encipherment",
                    "client auth",
                    "server auth"
                ],
                "expiry": "${HOST_EXPIRY}h"
            },
            "server": {
                "usages": [
                    "signing",
                    "digital signing",
                    "key encipherment",
                    "server auth"
                ],
                "expiry": "${HOST_EXPIRY}h"
            },
            "client": {
                "usages": [
                    "signing",
                    "digital signature",
                    "key encipherment",
                    "client auth"
                ],
                "expiry": "${HOST_EXPIRY}h"
            },
            "email": {
                "usages": [
                    "signing",
                    "digital signature",
                    "key encipherment",
                    "client auth"
                ],
                "expiry": "${EMAIL_EXPIRY}h"
            }
        }
    }
}
EOF
`

function info() {
    local FN=$1
    FSIZE=`$STAT --printf="%s" "$FN"`
    FDATE=`$STAT --printf="%y" "$FN" | cut -d"." -f1`
    FDATE=`$DATE -d "$FDATE" +"$DFMT"`
    BN=`basename $FN`
    printf "%-10s : $FDATE $FSIZE bytes\n" $BN
}

function x509info() {
    local FN=$1
    BN=`basename $FN`
    echo "--=[ X.509 details ($BN):"
    START_DATE=`openssl x509 -in "$FN" -noout -startdate | cut -d"=" -f2`
    START_DATE_SECS=`$DATE -d "$START_DATE" +%s`
    START_DATE_HOURS=$[ $START_DATE_SECS / 3600 ]
    END_DATE=`openssl x509 -in "$FN" -noout -enddate | cut -d"=" -f2`
    END_DATE_SECS=`$DATE -d "$END_DATE" +%s`
    END_DATE_HOURS=$[ $END_DATE_SECS / 3600 ]
    DELTA_SECS=$[ $END_DATE_SECS - $START_DATE_SECS ]
    DELTA_HOURS=$[ $DELTA_SECS / 3600 ]
    printf "${AZURE}%10s${COFF} : %s\n" "Total" "$DELTA_SECS secs ($[ $DELTA_SECS / 86400 ] days = $DELTA_HOURS hours)"
    openssl x509 -in "$FN" -noout -subject -issuer -dates | \
        while IFS="=" read -r key value; do
            if [ "$key" == "notAfter" -o "$key" == "notBefore" ]; then
                DUNIXTS=`$DATE -d "$value" +%s`
                NUNIXTS=`$DATE +%s`
                DT=`$DATE -d "$value" +"$DFMT"`
                printf "${AZURE}%10s${COFF} : %s\n" "$key" "$DT"
                if [ $DUNIXTS -lt $NUNIXTS ]; then
                    DELTA_SECS=$[ $NUNIXTS - $DUNIXTS ]
                    printf "${YELLOW}Days since${COFF} : $[ $DELTA_SECS / 86400 ] (${DELTA_SECS} secs)\n"
                else
                    DELTA_SECS=$[ $DUNIXTS - $NUNIXTS ]
                    printf "${YELLOW}Days left${COFF}  : $[ $DELTA_SECS / 86400 ] (${DELTA_SECS} secs)\n"
                fi
            else
                # display DN
                printf "${AZURE}%-10s${COFF} : " "$key"
                # split DN value
                # C=CZ, ST=Heart of Europe, L=Prague, O=000 AtHome Root CA, OU=Security Dept., CN=000-AtHome-Root-CA
                # into key-value pairs and colorize them
                echo "$value" | sed -e 's/, /\n/g' | \
                    while IFS="=" read -r key value; do
                        printf "${RED}%s${COFF}=${GREEN}%s${COFF}, " "$key" "$value"
                    done
                echo
            fi
        done
    ALT_NAMES=`openssl x509 -noout -ext subjectAltName -in "$FN" 2>/dev/null | tr -d "\r\n" | cut -d: -f2- | $SED -e 's/^\s*//g'`
    if [ -n "$ALT_NAMES" ]; then
        printf "${AZURE}Alt Names${COFF}  : "
        echo "$ALT_NAMES" | sed -e 's/, /\n/g' | \
            while IFS=":" read -r key value; do
                printf "${RED}%s${COFF}=${GREEN}%s${COFF}, " "$key" "$value"
            done
        echo
    fi
}

if [ ! -f "$BD/00_ca.json" ]; then
    echo "$JSON_00_CA" > $BD/00_ca.json
else
    echo "00_ca.json exists"
fi
if [ ! -f "$BD/01_ica.json" ]; then
    echo "$JSON_01_ICA" > $BD/01_ica.json
else
    echo "01_ica.json exists"
fi
if [ ! -f "$BD/02_host.json" ]; then
    echo "$JSON_02_HOST" > $BD/02_host.json
else
    echo "02_host.json exists"
fi
if [ ! -f "$BD/03_email.json" ]; then
    echo "$JSON_03_EMAIL" > $BD/03_email.json
else
    echo "03_email.json exists"
fi
if [ ! -f "$BD/profiles.json" ]; then
    echo "$JSON_PROFILES" > $BD/profiles.json
else
    echo "profiles.json exists"
fi

function step01() {
    if [ ! -f "$BD/ca-key.pem" ]; then
        echo "Making Root CA..."
        echo "Making self-signed Root CA : ca-key.pem, etc."
        cfssl gencert -initca $BD/00_ca.json > $BD/ca.json
        jq -r .cert $BD/ca.json > $BD/ca.pem
        jq -r .key $BD/ca.json > $BD/ca-key.pem
        jq -r .csr $BD/ca.json > $BD/ca.csr
    else
        echo "Root CA exists"
    fi
    echo "--=[ Root CA files:"
    # display file size and date created
    info $BD/ca-key.pem
    info $BD/ca.pem
    x509info $BD/ca.pem
}

function step02() {
    if [ ! -f "$BD/ica-key.pem" ]; then
        echo "Making Intermediate CA..."
        echo "Making Root CA signed Intermediate CA : ica-key.pem, etc."
        cfssl gencert -initca $BD/01_ica.json > $BD/ica.json
        jq -r .cert $BD/ica.json > $BD/ica.pem
        jq -r .key $BD/ica.json > $BD/ica-key.pem
        jq -r .csr $BD/ica.json > $BD/ica.csr
    else
        echo "Intermediate CA exists"
    fi
    echo "--=[ Intermediate CA files:"
    # display file size and date created
    info $BD/ica-key.pem
    info $BD/ica.pem
    x509info $BD/ica.pem
    echo "Sign the Intermediate CA"
    if [ ! -f "$BD/ica-ca.json" ]; then
        cfssl sign \
            -ca $BD/ca.pem \
            -ca-key $BD/ca-key.pem \
            -config $BD/profiles.json \
            -profile intermediate_ca \
            $BD/ica.csr > $BD/ica-ca.json
        jq -r .cert $BD/ica-ca.json > $BD/ica-ca.pem
        jq -r .csr $BD/ica-ca.json > $BD/ica-ca.csr
    else
        echo "The Intermediate CA is already signed"
    fi
    x509info $BD/ica-ca.pem
}

function join_by { local IFS="$1"; shift; echo "$*"; }

function step03() {
    local NAME=$1
    shift
    ALT_NAMES=$@
    mkdir -p $BD/hosts/$NAME
    VALS=`join_by , $NAME ${ALT_NAMES[@]}`
    jq ".CN=\"$NAME\"" $BD/02_host.json | \
        jq --arg value "$VALS" '.hosts = ($value / ",")' | \
        cat > $BD/hosts/${NAME}/cfg.json
    # check the validity of the certificate
    if [ -f "$BD/hosts/${NAME}/cert.pem" ]; then
        END_DATE=`openssl x509 -in "$BD/hosts/${NAME}/cert.pem" -noout -enddate | cut -d"=" -f2`
        END_DATE_SECS=`$DATE -d "$END_DATE" +%s`
        NUNIXTS=`$DATE +%s`
        if [ $END_DATE_SECS -lt $NUNIXTS ]; then
            echo "The certificate hosts/${NAME}/cert.pem is expired"
            echo "Removing the expired certificate"
            rm -f $BD/hosts/${NAME}/cert.pem
            # we might want to keep the key for the future
            rm -f $BD/hosts/${NAME}/key.pem
            rm -f $BD/hosts/${NAME}/host.json
            rm -f $BD/hosts/${NAME}/bundle-2.pem
            rm -f $BD/hosts/${NAME}/bundle-3.pem
            rm -f $BD/hosts/${NAME}/haproxy.pem
        else
            echo "The certificate hosts/${NAME}/cert.pem is still valid"
        fi
    fi
    if [ ! -f $BD/hosts/${NAME}/host.json ]; then
        echo "Generating server '$NAME' certificate"
        cfssl gencert \
            -ca $BD/ica-ca.pem \
            -ca-key $BD/ica-key.pem \
            -config $BD/profiles.json \
            -profile=server \
            $BD/hosts/${NAME}/cfg.json > $BD/hosts/${NAME}/host.json
        jq -r .cert $BD/hosts/${NAME}/host.json > $BD/hosts/${NAME}/cert.pem
        jq -r .key $BD/hosts/${NAME}/host.json > $BD/hosts/${NAME}/key.pem
        jq -r .csr $BD/hosts/${NAME}/host.json > $BD/hosts/${NAME}/host.csr
        # concatenate the server, intermediate
        cat $BD/hosts/${NAME}/cert.pem $BD/ica-ca.pem > $BD/hosts/${NAME}/bundle-2.pem
        # concatenate the server, intermediate and root ca
        cat $BD/hosts/${NAME}/cert.pem $BD/ica-ca.pem $BD/ca.pem > $BD/hosts/${NAME}/bundle-3.pem
        # also create file suitable for haproxy w/key (server, intermediate, root + key)
        cat $BD/hosts/${NAME}/bundle-3.pem $BD/hosts/${NAME}/key.pem > $BD/hosts/${NAME}/haproxy.pem
    else
        echo "Host hosts/${NAME}/host.json already exists"
    fi
    x509info $BD/hosts/${NAME}/cert.pem
}

function step_email() {
    # Generate S/MIME certificate for email signing and encryption
    # Usage: step_email "Person Name" email1@example.com [email2@example.com ...]
    # First parameter is the CN (person's name)
    # Remaining parameters are email addresses (added to SAN)
    local NAME=$1
    shift
    EMAIL_ADDRESSES=$@
    
    # Create slugified folder name from CN (lowercase, replace spaces/special chars with underscore)
    local FOLDER_NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | $SED 's/[^a-z0-9]/_/g' | $SED 's/__*/_/g' | $SED 's/^_//;s/_$//')
    
    # Create directory for this email certificate
    mkdir -p "$BD/smime/$FOLDER_NAME"
    
    # Build comma-separated list of email addresses for hosts field
    VALS=`join_by , ${EMAIL_ADDRESSES[@]}`
    
    # Generate certificate configuration from email template
    jq ".CN=\"$NAME\"" "$BD/03_email.json" | \
        jq --arg value "$VALS" '.hosts = ($value / ",")' | \
        cat > "$BD/smime/${FOLDER_NAME}/cfg.json"
    
    # check the validity of the certificate
    if [ -f "$BD/smime/${FOLDER_NAME}/cert.pem" ]; then
        END_DATE=`openssl x509 -in "$BD/smime/${FOLDER_NAME}/cert.pem" -noout -enddate | cut -d"=" -f2`
        END_DATE_SECS=`$DATE -d "$END_DATE" +%s`
        NUNIXTS=`$DATE +%s`
        if [ $END_DATE_SECS -lt $NUNIXTS ]; then
            echo "The certificate smime/${FOLDER_NAME}/cert.pem is expired"
            echo "Removing the expired certificate"
            rm -f "$BD/smime/${FOLDER_NAME}/cert.pem"
            # we might want to keep the key for the future
            rm -f "$BD/smime/${FOLDER_NAME}/key.pem"
            rm -f "$BD/smime/${FOLDER_NAME}/email.json"
            rm -f "$BD/smime/${FOLDER_NAME}/bundle-2.pem"
            rm -f "$BD/smime/${FOLDER_NAME}/bundle-3.pem"
            rm -f "$BD/smime/${FOLDER_NAME}/email.p12"
        else
            echo "The certificate smime/${FOLDER_NAME}/cert.pem is still valid"
        fi
    fi
    
    if [ ! -f "$BD/smime/${FOLDER_NAME}/email.json" ]; then
        echo "Generating email certificate for '$NAME'"
        echo "Email addresses: $EMAIL_ADDRESSES"
        
        # Generate certificate with email profile
        cfssl gencert \
            -ca "$BD/ica-ca.pem" \
            -ca-key "$BD/ica-key.pem" \
            -config "$BD/profiles.json" \
            -profile=email \
            "$BD/smime/${FOLDER_NAME}/cfg.json" > "$BD/smime/${FOLDER_NAME}/email.json"
        
        # Extract certificate components
        jq -r .cert "$BD/smime/${FOLDER_NAME}/email.json" > "$BD/smime/${FOLDER_NAME}/cert.pem"
        jq -r .key "$BD/smime/${FOLDER_NAME}/email.json" > "$BD/smime/${FOLDER_NAME}/key.pem"
        jq -r .csr "$BD/smime/${FOLDER_NAME}/email.json" > "$BD/smime/${FOLDER_NAME}/email.csr"
        
        # concatenate the certificate, intermediate
        cat "$BD/smime/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" > "$BD/smime/${FOLDER_NAME}/bundle-2.pem"
        # concatenate the certificate, intermediate and root ca
        cat "$BD/smime/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" "$BD/ca.pem" > "$BD/smime/${FOLDER_NAME}/bundle-3.pem"
        
        # Create PKCS#12 file for email clients (Thunderbird, Outlook, etc.)
        # Password can be configured via EMAIL_P12_PASSWORD environment variable
        P12_PASS="${EMAIL_P12_PASSWORD:-}"
        if [ -z "$P12_PASS" ]; then
            echo "Creating PKCS#12 file without password (use EMAIL_P12_PASSWORD env var to set password)"
            openssl pkcs12 -export -out "$BD/smime/${FOLDER_NAME}/email.p12" \
                -inkey "$BD/smime/${FOLDER_NAME}/key.pem" \
                -in "$BD/smime/${FOLDER_NAME}/bundle-3.pem" \
                -name "${NAME}" \
                -passout pass:
        else
            echo "Creating PKCS#12 file with password"
            openssl pkcs12 -export -out "$BD/smime/${FOLDER_NAME}/email.p12" \
                -inkey "$BD/smime/${FOLDER_NAME}/key.pem" \
                -in "$BD/smime/${FOLDER_NAME}/bundle-3.pem" \
                -name "${NAME}" \
                -passout pass:$P12_PASS
        fi
        echo "Saved PKCS#12 file to $BD/smime/${FOLDER_NAME}/email.p12"
        echo "Import this file into your email client to use for S/MIME signing and encryption"
    else
        echo "Email certificate smime/${FOLDER_NAME}/email.json already exists"
    fi
    x509info "$BD/smime/${FOLDER_NAME}/cert.pem"
}

function step_email_openssl() {
    # Generate S/MIME certificate using OpenSSL directly with proper Extended Key Usage
    # Usage: step_email_openssl "Person Name" email1@example.com [email2@example.com ...]
    # This function creates certificates with emailProtection EKU which CFSSL cannot do
    local NAME=$1
    shift
    EMAIL_ADDRESSES=$@
    
    # Create slugified folder name from CN
    local FOLDER_NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | $SED 's/[^a-z0-9]/_/g' | $SED 's/__*/_/g' | $SED 's/^_//;s/_$//')
    
    # Create directory for this email certificate
    mkdir -p "$BD/smime-openssl/$FOLDER_NAME"
    
    echo "Generating S/MIME certificate for '$NAME' using OpenSSL..."
    echo "Email addresses: $EMAIL_ADDRESSES"
    
    # Check if certificate already exists
    if [ -f "$BD/smime-openssl/${FOLDER_NAME}/cert.pem" ]; then
        END_DATE=`openssl x509 -in "$BD/smime-openssl/${FOLDER_NAME}/cert.pem" -noout -enddate | cut -d"=" -f2`
        END_DATE_SECS=`$DATE -d "$END_DATE" +%s`
        NUNIXTS=`$DATE +%s`
        if [ $END_DATE_SECS -lt $NUNIXTS ]; then
            echo "The certificate is expired, regenerating..."
            rm -f "$BD/smime-openssl/${FOLDER_NAME}"/*
        else
            echo "Valid certificate already exists at smime-openssl/${FOLDER_NAME}/cert.pem"
            x509info "$BD/smime-openssl/${FOLDER_NAME}/cert.pem"
            return
        fi
    fi
    
    # Build Subject Alternative Name string with email addresses
    SAN_EMAILS=""
    for email in $EMAIL_ADDRESSES; do
        if [ -z "$SAN_EMAILS" ]; then
            SAN_EMAILS="email:${email}"
        else
            SAN_EMAILS="${SAN_EMAILS},email:${email}"
        fi
    done
    
    # Create OpenSSL config file for this certificate
    cat > "$BD/smime-openssl/${FOLDER_NAME}/openssl.cnf" << EOF
# OpenSSL configuration for S/MIME certificate generation
# Generated: $(date)

[ req ]
default_bits        = 2048
default_md          = sha256
default_keyfile     = key.pem
prompt              = no
encrypt_key         = no
distinguished_name  = req_dn
req_extensions      = v3_req

[ req_dn ]
C                   = CZ
ST                  = Heart of Europe
L                   = Prague
O                   = At Home Company
OU                  = Security Dept.
CN                  = ${NAME}

[ v3_req ]
# Extensions for S/MIME certificate
keyUsage            = critical, digitalSignature, keyEncipherment
extendedKeyUsage    = emailProtection
subjectAltName      = ${SAN_EMAILS}
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash

[ v3_ca ]
# Extensions for signing (CA perspective)
keyUsage            = critical, digitalSignature, keyEncipherment
extendedKeyUsage    = emailProtection
subjectAltName      = ${SAN_EMAILS}
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF
    
    # Generate private key
    echo "Generating private key..."
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
        -out "$BD/smime-openssl/${FOLDER_NAME}/key.pem" 2>/dev/null
    
    # Generate Certificate Signing Request (CSR)
    echo "Generating Certificate Signing Request..."
    openssl req -new \
        -key "$BD/smime-openssl/${FOLDER_NAME}/key.pem" \
        -out "$BD/smime-openssl/${FOLDER_NAME}/email.csr" \
        -config "$BD/smime-openssl/${FOLDER_NAME}/openssl.cnf" 2>/dev/null
    
    # Sign the certificate with Intermediate CA
    echo "Signing certificate with Intermediate CA..."
    openssl x509 -req \
        -in "$BD/smime-openssl/${FOLDER_NAME}/email.csr" \
        -CA "$BD/ica-ca.pem" \
        -CAkey "$BD/ica-key.pem" \
        -CAcreateserial \
        -out "$BD/smime-openssl/${FOLDER_NAME}/cert.pem" \
        -days 265 \
        -sha384 \
        -extfile "$BD/smime-openssl/${FOLDER_NAME}/openssl.cnf" \
        -extensions v3_ca 2>/dev/null
    
    # Create certificate bundles
    cat "$BD/smime-openssl/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" > "$BD/smime-openssl/${FOLDER_NAME}/bundle-2.pem"
    cat "$BD/smime-openssl/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" "$BD/ca.pem" > "$BD/smime-openssl/${FOLDER_NAME}/bundle-3.pem"
    
    # Create PKCS#12 file
    P12_PASS="${EMAIL_P12_PASSWORD:-}"
    if [ -z "$P12_PASS" ]; then
        echo "Creating PKCS#12 file without password (use EMAIL_P12_PASSWORD env var to set password)"
        openssl pkcs12 -export -out "$BD/smime-openssl/${FOLDER_NAME}/email.p12" \
            -inkey "$BD/smime-openssl/${FOLDER_NAME}/key.pem" \
            -in "$BD/smime-openssl/${FOLDER_NAME}/bundle-3.pem" \
            -name "${NAME}" \
            -passout pass:
    else
        echo "Creating PKCS#12 file with password"
        openssl pkcs12 -export -out "$BD/smime-openssl/${FOLDER_NAME}/email.p12" \
            -inkey "$BD/smime-openssl/${FOLDER_NAME}/key.pem" \
            -in "$BD/smime-openssl/${FOLDER_NAME}/bundle-3.pem" \
            -name "${NAME}" \
            -passout pass:$P12_PASS
    fi
    
    echo ""
    echo "✓ Certificate generated successfully!"
    echo "  Directory: $BD/smime-openssl/${FOLDER_NAME}/"
    echo "  PKCS#12: $BD/smime-openssl/${FOLDER_NAME}/email.p12"
    echo ""
    
    # Display certificate information
    x509info "$BD/smime-openssl/${FOLDER_NAME}/cert.pem"
    
    echo ""
    echo "Certificate Extensions:"
    openssl x509 -in "$BD/smime-openssl/${FOLDER_NAME}/cert.pem" -noout -text | grep -A15 "X509v3 extensions" | sed 's/^/  /'
}

function step_tls_client() {
    # Generate TLS client certificate using OpenSSL with proper Extended Key Usage
    # Usage: step_tls_client "Client Name" [email@example.com]
    # This function creates certificates with clientAuth EKU for TLS client authentication
    local NAME=$1
    local EMAIL=${2:-""}
    
    # Create slugified folder name from CN
    local FOLDER_NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | $SED 's/[^a-z0-9]/_/g' | $SED 's/__*/_/g' | $SED 's/^_//;s/_$//')
    
    # Create directory for this TLS client certificate
    mkdir -p "$BD/tls-clients/$FOLDER_NAME"
    
    echo "Generating TLS client certificate for '$NAME' using OpenSSL..."
    if [ -n "$EMAIL" ]; then
        echo "Email address: $EMAIL"
    fi
    
    # Check if certificate already exists
    if [ -f "$BD/tls-clients/${FOLDER_NAME}/cert.pem" ]; then
        END_DATE=`openssl x509 -in "$BD/tls-clients/${FOLDER_NAME}/cert.pem" -noout -enddate | cut -d"=" -f2`
        END_DATE_SECS=`$DATE -d "$END_DATE" +%s`
        NUNIXTS=`$DATE +%s`
        if [ $END_DATE_SECS -lt $NUNIXTS ]; then
            echo "The certificate is expired, regenerating..."
            rm -f "$BD/tls-clients/${FOLDER_NAME}"/*
        else
            echo "Valid certificate already exists at tls-clients/${FOLDER_NAME}/cert.pem"
            x509info "$BD/tls-clients/${FOLDER_NAME}/cert.pem"
            return
        fi
    fi
    
    # Build Subject Alternative Name string
    SAN_STRING=""
    if [ -n "$EMAIL" ]; then
        SAN_STRING="email:${EMAIL}"
    fi
    
    # Create OpenSSL config file for this certificate
    cat > "$BD/tls-clients/${FOLDER_NAME}/openssl.cnf" << EOF
# OpenSSL configuration for TLS client certificate generation
# Generated: $(date)

[ req ]
default_bits        = 2048
default_md          = sha256
default_keyfile     = key.pem
prompt              = no
encrypt_key         = no
distinguished_name  = req_dn
req_extensions      = v3_req

[ req_dn ]
C                   = CZ
ST                  = Heart of Europe
L                   = Prague
O                   = At Home Company
OU                  = Security Dept.
CN                  = ${NAME}
$([ -n "$EMAIL" ] && echo "emailAddress        = ${EMAIL}")

[ v3_req ]
# Extensions for TLS client certificate
keyUsage            = critical, digitalSignature, keyEncipherment
extendedKeyUsage    = clientAuth
$([ -n "$SAN_STRING" ] && echo "subjectAltName      = ${SAN_STRING}")
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash

[ v3_ca ]
# Extensions for signing (CA perspective)
keyUsage            = critical, digitalSignature, keyEncipherment
extendedKeyUsage    = clientAuth
$([ -n "$SAN_STRING" ] && echo "subjectAltName      = ${SAN_STRING}")
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF
    
    # Generate private key
    echo "Generating private key..."
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
        -out "$BD/tls-clients/${FOLDER_NAME}/key.pem" 2>/dev/null
    
    # Generate Certificate Signing Request (CSR)
    echo "Generating Certificate Signing Request..."
    openssl req -new \
        -key "$BD/tls-clients/${FOLDER_NAME}/key.pem" \
        -out "$BD/tls-clients/${FOLDER_NAME}/client.csr" \
        -config "$BD/tls-clients/${FOLDER_NAME}/openssl.cnf" 2>/dev/null
    
    # Sign the certificate with Intermediate CA
    echo "Signing certificate with Intermediate CA..."
    openssl x509 -req \
        -in "$BD/tls-clients/${FOLDER_NAME}/client.csr" \
        -CA "$BD/ica-ca.pem" \
        -CAkey "$BD/ica-key.pem" \
        -CAcreateserial \
        -out "$BD/tls-clients/${FOLDER_NAME}/cert.pem" \
        -days 265 \
        -sha384 \
        -extfile "$BD/tls-clients/${FOLDER_NAME}/openssl.cnf" \
        -extensions v3_ca 2>/dev/null
    
    # Create certificate bundles
    cat "$BD/tls-clients/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" > "$BD/tls-clients/${FOLDER_NAME}/bundle-2.pem"
    cat "$BD/tls-clients/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" "$BD/ca.pem" > "$BD/tls-clients/${FOLDER_NAME}/bundle-3.pem"
    
    # Create PKCS#12 file
    P12_PASS="${TLS_CLIENT_P12_PASSWORD:-}"
    if [ -z "$P12_PASS" ]; then
        echo "Creating PKCS#12 file without password (use TLS_CLIENT_P12_PASSWORD env var to set password)"
        openssl pkcs12 -export -out "$BD/tls-clients/${FOLDER_NAME}/client.p12" \
            -inkey "$BD/tls-clients/${FOLDER_NAME}/key.pem" \
            -in "$BD/tls-clients/${FOLDER_NAME}/bundle-3.pem" \
            -name "${NAME}" \
            -passout pass:
    else
        echo "Creating PKCS#12 file with password"
        openssl pkcs12 -export -out "$BD/tls-clients/${FOLDER_NAME}/client.p12" \
            -inkey "$BD/tls-clients/${FOLDER_NAME}/key.pem" \
            -in "$BD/tls-clients/${FOLDER_NAME}/bundle-3.pem" \
            -name "${NAME}" \
            -passout pass:$P12_PASS
    fi
    
    echo ""
    echo -e "${GREEN}✓ TLS client certificate generated successfully!${COFF}"
    echo "  Directory: $BD/tls-clients/${FOLDER_NAME}/"
    echo "  Certificate: $BD/tls-clients/${FOLDER_NAME}/cert.pem"
    echo "  Private Key: $BD/tls-clients/${FOLDER_NAME}/key.pem"
    echo "  PKCS#12: $BD/tls-clients/${FOLDER_NAME}/client.p12"
    echo ""
    
    # Display certificate information
    x509info "$BD/tls-clients/${FOLDER_NAME}/cert.pem"
    
    echo ""
    echo "Certificate Extensions:"
    openssl x509 -in "$BD/tls-clients/${FOLDER_NAME}/cert.pem" -noout -text | grep -A15 "X509v3 extensions" | sed 's/^/  /'
    
    echo ""
    echo -e "${AZURE}Usage:${COFF}"
    echo "  # With curl:"
    echo "  curl --cacert $BD/ca-bundle-myca.pem \\"
    echo "       --cert $BD/tls-clients/${FOLDER_NAME}/cert.pem \\"
    echo "       --key $BD/tls-clients/${FOLDER_NAME}/key.pem \\"
    echo "       https://your-mtls-server:8444/"
    echo ""
    echo "  # Import PKCS#12 into browser:"
    echo "  $BD/tls-clients/${FOLDER_NAME}/client.p12"
}

function step_tsa() {
    # Generate TSA (Time Stamp Authority) certificate using OpenSSL with proper Extended Key Usage
    # Usage: step_tsa "TSA_NAME"
    # This function creates certificates with timeStamping EKU for RFC 3161 TSA operations
    local NAME=$1
    
    if [ -z "$NAME" ]; then
        echo -e "${RED}Error: TSA name is required${COFF}"
        echo "Usage: step_tsa \"TSA_NAME\""
        return 1
    fi
    
    # Create slugified folder name from name
    local FOLDER_NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | $SED 's/[^a-z0-9]/_/g' | $SED 's/__*/_/g' | $SED 's/^_//;s/_$//')
    
    # Create directory for this TSA certificate
    mkdir -p "$BD/tsa/$FOLDER_NAME"
    
    echo "Generating TSA certificate for '$NAME' using OpenSSL..."
    
    # Check if certificate already exists
    if [ -f "$BD/tsa/${FOLDER_NAME}/cert.pem" ]; then
        END_DATE=`openssl x509 -in "$BD/tsa/${FOLDER_NAME}/cert.pem" -noout -enddate | cut -d"=" -f2`
        END_DATE_SECS=`$DATE -d "$END_DATE" +%s`
        NUNIXTS=`$DATE +%s`
        if [ $END_DATE_SECS -lt $NUNIXTS ]; then
            echo "The certificate is expired, regenerating..."
            rm -f "$BD/tsa/${FOLDER_NAME}"/*
        else
            echo "Valid certificate already exists at tsa/${FOLDER_NAME}/cert.pem"
            x509info "$BD/tsa/${FOLDER_NAME}/cert.pem"
            return
        fi
    fi
    
    # Create OpenSSL config file for this certificate
    cat > "$BD/tsa/${FOLDER_NAME}/openssl.cnf" << EOF
# OpenSSL configuration for TSA certificate generation
# Generated: $(date)
# RFC 3161 Time Stamp Authority Certificate

[ req ]
default_bits        = 2048
default_md          = sha256
default_keyfile     = key.pem
prompt              = no
encrypt_key         = no
distinguished_name  = req_dn
req_extensions      = v3_req

[ req_dn ]
C                   = CZ
ST                  = Heart of Europe
L                   = Prague
O                   = At Home Company
OU                  = Time Stamp Authority
CN                  = ${NAME}

[ v3_req ]
# Extensions for TSA certificate
keyUsage            = critical, digitalSignature, nonRepudiation
extendedKeyUsage    = critical, timeStamping
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash

[ v3_ca ]
# Extensions for signing (CA perspective)
keyUsage            = critical, digitalSignature, nonRepudiation
extendedKeyUsage    = critical, timeStamping
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF
    
    # Generate private key (ECDSA P-384 to match project defaults)
    echo "Generating private key (ECDSA P-384)..."
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
        -out "$BD/tsa/${FOLDER_NAME}/key.pem" 2>/dev/null
    
    # Generate Certificate Signing Request (CSR)
    echo "Generating Certificate Signing Request..."
    openssl req -new \
        -key "$BD/tsa/${FOLDER_NAME}/key.pem" \
        -out "$BD/tsa/${FOLDER_NAME}/tsa.csr" \
        -config "$BD/tsa/${FOLDER_NAME}/openssl.cnf" 2>/dev/null
    
    # Sign the certificate with Intermediate CA
    echo "Signing certificate with Intermediate CA..."
    openssl x509 -req \
        -in "$BD/tsa/${FOLDER_NAME}/tsa.csr" \
        -CA "$BD/ica-ca.pem" \
        -CAkey "$BD/ica-key.pem" \
        -CAcreateserial \
        -out "$BD/tsa/${FOLDER_NAME}/cert.pem" \
        -days 825 \
        -sha384 \
        -extfile "$BD/tsa/${FOLDER_NAME}/openssl.cnf" \
        -extensions v3_ca 2>/dev/null
    
    # Create certificate bundles
    cat "$BD/tsa/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" > "$BD/tsa/${FOLDER_NAME}/bundle-2.pem"
    cat "$BD/tsa/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" "$BD/ca.pem" > "$BD/tsa/${FOLDER_NAME}/bundle-3.pem"
    
    # Initialize serial number file for TSA operations
    echo "1000" > "$BD/tsa/${FOLDER_NAME}/tsaserial.txt"
    echo "Initialized serial number file: $BD/tsa/${FOLDER_NAME}/tsaserial.txt"
    
    echo ""
    echo -e "${GREEN}✓ TSA certificate generated successfully!${COFF}"
    echo "  Directory: $BD/tsa/${FOLDER_NAME}/"
    echo "  Certificate: $BD/tsa/${FOLDER_NAME}/cert.pem"
    echo "  Private Key: $BD/tsa/${FOLDER_NAME}/key.pem"
    echo "  Bundle (cert+ICA): $BD/tsa/${FOLDER_NAME}/bundle-2.pem"
    echo "  Bundle (cert+ICA+Root): $BD/tsa/${FOLDER_NAME}/bundle-3.pem"
    echo "  Serial Number File: $BD/tsa/${FOLDER_NAME}/tsaserial.txt"
    echo ""
    
    # Display certificate information
    x509info "$BD/tsa/${FOLDER_NAME}/cert.pem"
    
    echo ""
    echo "Certificate Extensions:"
    openssl x509 -in "$BD/tsa/${FOLDER_NAME}/cert.pem" -noout -text | grep -A15 "X509v3 extensions" | sed 's/^/  /'
    
    echo ""
    echo -e "${AZURE}Usage:${COFF}"
    echo "  This certificate can be used with a Time Stamp Authority (TSA) server"
    echo "  that implements RFC 3161 Time-Stamp Protocol."
    echo ""
    echo "  Environment variables for TSA server:"
    echo "  export TSA_CERT_PATH=$BD/tsa/${FOLDER_NAME}/cert.pem"
    echo "  export TSA_KEY_PATH=$BD/tsa/${FOLDER_NAME}/key.pem"
    echo "  export TSA_CHAIN_PATH=$BD/tsa/${FOLDER_NAME}/bundle-3.pem"
    echo "  export TSA_SERIAL_PATH=$BD/tsa/${FOLDER_NAME}/tsaserial.txt"
}

function step_codesign() {
    # Generate Code Signing certificate using OpenSSL with proper Extended Key Usage
    # Usage: step_codesign "CODESIGN_NAME" [rsa|ecdsa]
    # 
    # IMPORTANT: Windows Authenticode for PowerShell scripts ONLY supports RSA certificates!
    # ECDSA signatures are valid CMS/PKCS#7 but Windows will report "NotSigned" for PS scripts.
    # 
    # Key Algorithm Options:
    #   rsa   - RSA 3072-bit (default) - Required for Windows Authenticode/PowerShell
    #   ecdsa - ECDSA P-384 - For non-Windows platforms only
    #
    # This function creates certificates with codeSigning EKU for Authenticode signing
    
    local NAME=$1
    local KEY_TYPE=${2:-rsa}  # Default to RSA for Windows Authenticode compatibility
    
    if [ -z "$NAME" ]; then
        echo -e "${RED}Error: Code signing certificate name is required${COFF}"
        echo "Usage: step_codesign \"CODESIGN_NAME\" [rsa|ecdsa]"
        echo ""
        echo "Options:"
        echo "  rsa   - RSA 3072-bit (default) - Required for Windows Authenticode"
        echo "  ecdsa - ECDSA P-384 - For non-Windows platforms only"
        return 1
    fi
    
    # Validate key type
    if [ "$KEY_TYPE" != "rsa" ] && [ "$KEY_TYPE" != "ecdsa" ]; then
        echo -e "${RED}Error: Invalid key type '$KEY_TYPE'. Use 'rsa' or 'ecdsa'${COFF}"
        return 1
    fi
    
    # Warn about ECDSA limitation
    if [ "$KEY_TYPE" == "ecdsa" ]; then
        echo -e "${YELLOW}⚠ WARNING: ECDSA code signing certificates are NOT supported by Windows Authenticode!${COFF}"
        echo -e "${YELLOW}  PowerShell will report 'NotSigned' for scripts signed with ECDSA certificates.${COFF}"
        echo -e "${YELLOW}  Use 'rsa' (default) for Windows compatibility.${COFF}"
        echo ""
    fi
    
    # Create slugified folder name from name
    local FOLDER_NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | $SED 's/[^a-z0-9]/_/g' | $SED 's/__*/_/g' | $SED 's/^_//;s/_$//')
    
    # Create directory for this code signing certificate
    mkdir -p "$BD/codesign/$FOLDER_NAME"
    
    echo "Generating Code Signing certificate for '$NAME' using OpenSSL (key type: ${KEY_TYPE})..."
    
    # Check if certificate already exists
    if [ -f "$BD/codesign/${FOLDER_NAME}/cert.pem" ]; then
        END_DATE=`openssl x509 -in "$BD/codesign/${FOLDER_NAME}/cert.pem" -noout -enddate | cut -d"=" -f2`
        END_DATE_SECS=`$DATE -d "$END_DATE" +%s`
        NUNIXTS=`$DATE +%s`
        if [ $END_DATE_SECS -lt $NUNIXTS ]; then
            echo "The certificate is expired, regenerating..."
            rm -f "$BD/codesign/${FOLDER_NAME}"/*
        else
            # Check if existing cert has different key type
            EXISTING_KEY_TYPE=$(openssl x509 -in "$BD/codesign/${FOLDER_NAME}/cert.pem" -noout -text 2>/dev/null | grep -o "Public Key Algorithm:.*" | head -1)
            if [[ "$KEY_TYPE" == "rsa" && "$EXISTING_KEY_TYPE" == *"EC"* ]] || [[ "$KEY_TYPE" == "ecdsa" && "$EXISTING_KEY_TYPE" == *"rsaEncryption"* ]]; then
                echo "Existing certificate uses different key algorithm, regenerating with $KEY_TYPE..."
                rm -f "$BD/codesign/${FOLDER_NAME}"/*
            else
                echo "Valid certificate already exists at codesign/${FOLDER_NAME}/cert.pem"
                x509info "$BD/codesign/${FOLDER_NAME}/cert.pem"
                return
            fi
        fi
    fi
    
    # Set key-specific parameters
    local KEY_BITS HASH_ALG
    if [ "$KEY_TYPE" == "rsa" ]; then
        KEY_BITS=3072
        HASH_ALG=sha256
    else
        KEY_BITS=384
        HASH_ALG=sha384
    fi
    
    # Create OpenSSL config file for this certificate
    cat > "$BD/codesign/${FOLDER_NAME}/openssl.cnf" << EOF
# OpenSSL configuration for Code Signing certificate generation
# Generated: $(date)
# Key Type: ${KEY_TYPE}
# Authenticode / Code Signing Certificate
#
# NOTE: Windows Authenticode only supports RSA for PowerShell script signing.
# ECDSA certificates will result in "NotSigned" status on Windows.

[ req ]
default_bits        = ${KEY_BITS}
default_md          = ${HASH_ALG}
default_keyfile     = key.pem
prompt              = no
encrypt_key         = no
distinguished_name  = req_dn
req_extensions      = v3_req

[ req_dn ]
C                   = CZ
ST                  = Heart of Europe
L                   = Prague
O                   = At Home Company
OU                  = Development
CN                  = ${NAME}

[ v3_req ]
# Extensions for Code Signing certificate
keyUsage            = critical, digitalSignature
extendedKeyUsage    = codeSigning
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash

[ v3_ca ]
# Extensions for signing (CA perspective)
keyUsage            = critical, digitalSignature
extendedKeyUsage    = codeSigning
basicConstraints    = critical, CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF
    
    # Generate private key based on key type
    if [ "$KEY_TYPE" == "rsa" ]; then
        echo "Generating private key (RSA ${KEY_BITS}-bit)..."
        openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:${KEY_BITS} \
            -out "$BD/codesign/${FOLDER_NAME}/key.pem" 2>/dev/null
    else
        echo "Generating private key (ECDSA P-384)..."
        openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:secp384r1 \
            -out "$BD/codesign/${FOLDER_NAME}/key.pem" 2>/dev/null
    fi
    
    # Generate Certificate Signing Request (CSR)
    echo "Generating Certificate Signing Request..."
    openssl req -new \
        -key "$BD/codesign/${FOLDER_NAME}/key.pem" \
        -out "$BD/codesign/${FOLDER_NAME}/codesign.csr" \
        -config "$BD/codesign/${FOLDER_NAME}/openssl.cnf" 2>/dev/null
    
    # Sign the certificate with Intermediate CA
    echo "Signing certificate with Intermediate CA..."
    openssl x509 -req \
        -in "$BD/codesign/${FOLDER_NAME}/codesign.csr" \
        -CA "$BD/ica-ca.pem" \
        -CAkey "$BD/ica-key.pem" \
        -CAcreateserial \
        -out "$BD/codesign/${FOLDER_NAME}/cert.pem" \
        -days 825 \
        -${HASH_ALG} \
        -extfile "$BD/codesign/${FOLDER_NAME}/openssl.cnf" \
        -extensions v3_ca 2>/dev/null
    
    # Create certificate bundles
    cat "$BD/codesign/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" > "$BD/codesign/${FOLDER_NAME}/bundle-2.pem"
    cat "$BD/codesign/${FOLDER_NAME}/cert.pem" "$BD/ica-ca.pem" "$BD/ca.pem" > "$BD/codesign/${FOLDER_NAME}/bundle-3.pem"
    
    # Create PKCS#12 file for use with signing tools
    P12_PASS="${CODESIGN_P12_PASSWORD:-}"
    if [ -z "$P12_PASS" ]; then
        echo "Creating PKCS#12 file without password (use CODESIGN_P12_PASSWORD env var to set password)"
        openssl pkcs12 -export -out "$BD/codesign/${FOLDER_NAME}/codesign.p12" \
            -inkey "$BD/codesign/${FOLDER_NAME}/key.pem" \
            -in "$BD/codesign/${FOLDER_NAME}/bundle-3.pem" \
            -name "${NAME}" \
            -passout pass:
    else
        echo "Creating PKCS#12 file with password"
        openssl pkcs12 -export -out "$BD/codesign/${FOLDER_NAME}/codesign.p12" \
            -inkey "$BD/codesign/${FOLDER_NAME}/key.pem" \
            -in "$BD/codesign/${FOLDER_NAME}/bundle-3.pem" \
            -name "${NAME}" \
            -passout pass:$P12_PASS
    fi
    
    echo ""
    echo -e "${GREEN}✓ Code Signing certificate generated successfully!${COFF}"
    echo "  Key Type: ${KEY_TYPE}"
    echo "  Directory: $BD/codesign/${FOLDER_NAME}/"
    echo "  Certificate: $BD/codesign/${FOLDER_NAME}/cert.pem"
    echo "  Private Key: $BD/codesign/${FOLDER_NAME}/key.pem"
    echo "  PKCS#12: $BD/codesign/${FOLDER_NAME}/codesign.p12"
    echo "  Bundle (cert+ICA): $BD/codesign/${FOLDER_NAME}/bundle-2.pem"
    echo "  Bundle (cert+ICA+Root): $BD/codesign/${FOLDER_NAME}/bundle-3.pem"
    
    if [ "$KEY_TYPE" == "rsa" ]; then
        echo ""
        echo -e "${GREEN}  ✓ RSA key - Compatible with Windows Authenticode${COFF}"
    else
        echo ""
        echo -e "${YELLOW}  ⚠ ECDSA key - NOT compatible with Windows Authenticode${COFF}"
    fi
    echo ""
    
    # Display certificate information
    x509info "$BD/codesign/${FOLDER_NAME}/cert.pem"
    
    echo ""
    echo "Certificate Extensions:"
    openssl x509 -in "$BD/codesign/${FOLDER_NAME}/cert.pem" -noout -text | grep -A15 "X509v3 extensions" | sed 's/^/  /'
    
    echo ""
    echo -e "${AZURE}Usage with pkipy:${COFF}"
    echo "  # Using PFX file:"
    echo "  uv run pkipy script.ps1 --output signed.ps1 \\"
    echo "    --pfx $BD/codesign/${FOLDER_NAME}/codesign.p12 \\"
    echo "    --timestamp-url http://timestamp.digicert.com"
    echo ""
    echo "  # Using PEM files:"
    echo "  uv run pkipy script.ps1 --output signed.ps1 \\"
    echo "    --cert $BD/codesign/${FOLDER_NAME}/cert.pem \\"
    echo "    --key $BD/codesign/${FOLDER_NAME}/key.pem \\"
    echo "    --timestamp-url http://timestamp.digicert.com"
    echo ""
    echo -e "${AZURE}Or create config file:${COFF}"
    echo "  mkdir -p ~/.config/pkipy"
    echo "  cat > ~/.config/pkipy/config.yaml << EOY"
    echo "pfx: $BD/codesign/${FOLDER_NAME}/codesign.p12"
    echo "timestamp-url: http://timestamp.digicert.com"
    echo "EOY"
}

# The main script
# Step 1 - prepare the Root CA (if not exists)
# ususally you run this step only once (or once every 10 years = expiry date - 10%)

step01 # prepare the Root CA

# Step 2 - prepare the Intermediate CA (if not exists)
# ususally you run this step only once (or once every 10 years = expiry date - 10%)
step02 # prepare the Intermediate CA

# Step 3 - prepare the server certificate
# ususally you run this step for each server you want to secure
# the default profile is "server" and the certificate is valid for 90 days
#
# prepare the server(s) certificate, set the cn and alternative names
# note the first argument is the common name (CN) and the rest are alternative names
# CN is also the name of the file where the certificate will be stored
step03 localhost '*.lan'

step_tls_client "John TLS Client" john@example.com

step_email "John Doe" john.doe@example.com john@company.com

step_email_openssl "John Extended" john.extended@example.com johne@company.com

# Step 4 - prepare TSA certificate for Time Stamp Authority
# Usually you run this step once for your TSA server
step_tsa "MyTSA"

# Step 5 - prepare Code Signing certificate for Authenticode signing
# Usually you run this step once for code signing operations
# NOTE: RSA is the default and REQUIRED for Windows Authenticode/PowerShell scripts
# Use: step_codesign "Name" rsa     (default - Windows compatible)
#      step_codesign "Name" ecdsa   (non-Windows only)
step_codesign "MyCodeSign"  # Uses RSA by default for Windows Authenticode compatibility