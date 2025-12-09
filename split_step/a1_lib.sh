#!/bin/bash
#
# Shared library functions for certificate generation scripts
#

# ============================================================================
# ANSI COLOR CODES
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
AZURE='\033[0;36m'
COFF='\033[0m'

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Function to check if a command exists
check_command() {
    local cmd=$1
    local required=$2
    if ! command -v "$cmd" >/dev/null 2>&1; then
        if [ "$required" = "true" ]; then
            echo -e "${RED}Error: Required command '$cmd' not found${COFF}" >&2
            return 1
        else
            return 1
        fi
    fi
    return 0
}

# Function to check if a command supports GNU-style options
check_gnu_version() {
    local cmd=$1
    local test_flag=$2
    if ! "$cmd" "$test_flag" --version >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Function to detect OS and set appropriate commands
# Sets: STAT, DATE, SED, OPENSSL
detect_os_and_set_commands() {
    # Check openssl
    if ! check_command "openssl" "true"; then
        exit 1
    fi
    OPENSSL="openssl"
    
    # Check basic utilities
    for cmd in cut basename expr cat mkdir rm printf; do
        if ! check_command "$cmd" "true"; then
            exit 1
        fi
    done
    
    # Detect OS and set appropriate commands
    if [ "$(uname)" == "Darwin" ]; then
        # macOS - need GNU versions
        if ! check_command "gstat" "false"; then
            echo -e "${RED}Error: 'gstat' (GNU stat) not found. Install via: brew install coreutils${COFF}" >&2
            exit 1
        fi
        if ! check_command "gdate" "false"; then
            echo -e "${RED}Error: 'gdate' (GNU date) not found. Install via: brew install coreutils${COFF}" >&2
            exit 1
        fi
        if ! check_command "gsed" "false"; then
            echo -e "${RED}Error: 'gsed' (GNU sed) not found. Install via: brew install gnu-sed${COFF}" >&2
            exit 1
        fi
        
        # Verify GNU versions
        if ! check_gnu_version "gstat" "--version"; then
            echo -e "${RED}Error: 'gstat' does not appear to be GNU stat${COFF}" >&2
            exit 1
        fi
        if ! check_gnu_version "gdate" "--version"; then
            echo -e "${RED}Error: 'gdate' does not appear to be GNU date${COFF}" >&2
            exit 1
        fi
        if ! check_gnu_version "gsed" "--version"; then
            echo -e "${RED}Error: 'gsed' does not appear to be GNU sed${COFF}" >&2
            exit 1
        fi
        
        STAT="gstat"
        DATE="gdate"
        SED="gsed"
    else
        # Linux - check for GNU versions
        if ! check_command "stat" "true"; then
            exit 1
        fi
        if ! check_command "date" "true"; then
            exit 1
        fi
        if ! check_command "sed" "true"; then
            exit 1
        fi
        
        # Verify GNU versions on Linux
        if ! check_gnu_version "stat" "--version"; then
            echo -e "${YELLOW}Warning: 'stat' may not be GNU stat, some features may not work${COFF}" >&2
        fi
        if ! check_gnu_version "date" "--version"; then
            echo -e "${RED}Error: 'date' does not appear to be GNU date${COFF}" >&2
            exit 1
        fi
        if ! check_gnu_version "sed" "--version"; then
            echo -e "${RED}Error: 'sed' does not appear to be GNU sed${COFF}" >&2
            exit 1
        fi
        
        STAT="stat"
        DATE="date"
        SED="sed"
    fi
    
    echo -e "${GREEN}All required binaries found${COFF}"
}

# Function to display file information
function info() {
    local FN=$1
    FSIZE=`$STAT --printf="%s" "$FN"`
    FDATE=`$STAT --printf="%y" "$FN" | cut -d"." -f1`
    FDATE=`$DATE -d "$FDATE" +"$DFMT"`
    BN=`basename $FN`
    printf "%-10s : $FDATE $FSIZE bytes\n" $BN
}

# Function to display X.509 certificate information
function x509info() {
    local FN=$1
    BN=`basename $FN`
    echo "--=[ X.509 details ($BN):"
    START_DATE=`$OPENSSL x509 -in "$FN" -noout -startdate | cut -d"=" -f2`
    START_DATE_SECS=`$DATE -d "$START_DATE" +%s`
    START_DATE_HOURS=$[ $START_DATE_SECS / 3600 ]
    END_DATE=`$OPENSSL x509 -in "$FN" -noout -enddate | cut -d"=" -f2`
    END_DATE_SECS=`$DATE -d "$END_DATE" +%s`
    END_DATE_HOURS=$[ $END_DATE_SECS / 3600 ]
    DELTA_SECS=$[ $END_DATE_SECS - $START_DATE_SECS ]
    DELTA_HOURS=$[ $DELTA_SECS / 3600 ]
    printf "${AZURE}%10s${COFF} : %s\n" "Total" "$DELTA_SECS secs ($[ $DELTA_SECS / 86400 ] days = $DELTA_HOURS hours)"
    $OPENSSL x509 -in "$FN" -noout -subject -issuer -dates | \
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
                echo "$value" | $SED -e 's/, /\n/g' | \
                    while IFS="=" read -r key value; do
                        printf "${RED}%s${COFF}=${GREEN}%s${COFF}, " "$key" "$value"
                    done
                echo
            fi
        done
    ALT_NAMES=`$OPENSSL x509 -noout -ext subjectAltName -in "$FN" 2>/dev/null | tr -d "\r\n" | cut -d: -f2- | $SED -e 's/^\s*//g'`
    if [ -n "$ALT_NAMES" ]; then
        printf "${AZURE}Alt Names${COFF}  : "
        echo "$ALT_NAMES" | $SED -e 's/, /\n/g' | \
            while IFS=":" read -r key value; do
                printf "${RED}%s${COFF}=${GREEN}%s${COFF}, " "$key" "$value"
            done
        echo
    fi
}

# Function to display ICA certificate information (for b_my_cert.sh)
function display_ica_info() {
    local BD=$1
    local ICA_CERT="$BD/ica-ca.pem"
    local ICA_KEY="$BD/ica-key.pem"
    
    echo ""
    echo -e "${AZURE}Intermediate CA Certificate Information:${COFF}"
    printf "${AZURE}Certificate${COFF}  : ${BLUE}\${BD}/ica-ca.pem${COFF}\n"
    printf "${AZURE}Private Key${COFF}  : ${BLUE}\${BD}/ica-key.pem${COFF}\n"
    echo ""
    
    SUBJECT=`$OPENSSL x509 -in "$ICA_CERT" -noout -subject 2>/dev/null | cut -d"=" -f2-`
    ISSUER=`$OPENSSL x509 -in "$ICA_CERT" -noout -issuer 2>/dev/null | cut -d"=" -f2-`
    START_DATE=`$OPENSSL x509 -in "$ICA_CERT" -noout -startdate 2>/dev/null | cut -d"=" -f2`
    END_DATE=`$OPENSSL x509 -in "$ICA_CERT" -noout -enddate 2>/dev/null | cut -d"=" -f2`
    
    # Display Subject DN with colors
    printf "${AZURE}Subject${COFF}     : "
    echo "$SUBJECT" | $SED -e 's/, /\n/g' | \
        while IFS="=" read -r key value; do
            printf "${RED}%s${COFF}=${GREEN}%s${COFF}, " "$key" "$value"
        done
    echo ""
    
    # Display Issuer DN with colors
    printf "${AZURE}Issuer${COFF}      : "
    echo "$ISSUER" | $SED -e 's/, /\n/g' | \
        while IFS="=" read -r key value; do
            printf "${RED}%s${COFF}=${GREEN}%s${COFF}, " "$key" "$value"
        done
    echo ""
    
    # Display validity dates
    if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then
        START_DATE_SECS=`$DATE -d "$START_DATE" +%s 2>/dev/null`
        END_DATE_SECS=`$DATE -d "$END_DATE" +%s 2>/dev/null`
        NUNIXTS=`$DATE +%s`
        
        if [ -n "$START_DATE_SECS" ] && [ -n "$END_DATE_SECS" ]; then
            START_DATE_FMT=`$DATE -d "$START_DATE" +"$DFMT" 2>/dev/null`
            END_DATE_FMT=`$DATE -d "$END_DATE" +"$DFMT" 2>/dev/null`
            
            printf "${AZURE}Valid from${COFF}  : ${GREEN}%s${COFF}\n" "$START_DATE_FMT"
            printf "${AZURE}Valid until${COFF} : ${GREEN}%s${COFF}\n" "$END_DATE_FMT"
            
            # Check if certificate is expired or expiring soon
            if [ $END_DATE_SECS -lt $NUNIXTS ]; then
                DELTA_SECS=$[ $NUNIXTS - $END_DATE_SECS ]
                DELTA_DAYS=$[ $DELTA_SECS / 86400 ]
                echo -e "${RED}Certificate expired ${DELTA_DAYS} days ago${COFF}"
            else
                DELTA_SECS=$[ $END_DATE_SECS - $NUNIXTS ]
                DELTA_DAYS=$[ $DELTA_SECS / 86400 ]
                if [ $DELTA_DAYS -lt 30 ]; then
                    echo -e "${YELLOW}Certificate expires in ${DELTA_DAYS} days${COFF}"
                else
                    echo -e "${GREEN}Certificate valid for ${DELTA_DAYS} more days${COFF}"
                fi
            fi
        fi
    fi
    echo ""
}

# Utility function to join array elements with a delimiter
function join_by { local IFS="$1"; shift; echo "$*"; }

