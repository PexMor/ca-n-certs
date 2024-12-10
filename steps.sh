#!/bin/sh
#
# This script splits the mkCert.sh into three parts
# please set the BD variable to the directory where the certificates will be stored
#

# stop on error
set -e

DEF_BD="$HOME/.config/my-cfssl"
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
        "expiry": "87600h"
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
        "expiry": "87600h"
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

JSON_PROFILES=`cat <<EOF
{
    "signing": {
        "default": {
            "expiry": "8760h"
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
                "expiry": "87600h",
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
                "expiry": "8760h"
            },
            "server": {
                "usages": [
                    "signing",
                    "digital signing",
                    "key encipherment",
                    "server auth"
                ],
                "expiry": "2160h"
            },
            "client": {
                "usages": [
                    "signing",
                    "digital signature",
                    "key encipherment",
                    "client auth"
                ],
                "expiry": "8760h"
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
                    echo "${YELLOW}Days since${COFF} : $[ $DELTA_SECS / 86400 ] (${DELTA_SECS} secs)"
                else
                    DELTA_SECS=$[ $DUNIXTS - $NUNIXTS ]
                    echo "${YELLOW}Days left${COFF}  : $[ $DELTA_SECS / 86400 ] (${DELTA_SECS} secs)"
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
        echo "${AZURE}Alt Names${COFF}  : $ALT_NAMES"
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