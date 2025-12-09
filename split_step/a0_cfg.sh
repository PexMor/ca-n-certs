#!/bin/bash
#
# Configuration file for certificate generation scripts
# Modify these variables to customize certificate generation behavior
#

# ============================================================================
# USER-CUSTOMIZABLE VARIABLES
# ============================================================================

# Default base directory for certificates (can be overridden via command line argument)
DEF_BD="$HOME/.config/split_step"

# Key algorithm and size
# Options: "rsa" (with KEY_SIZE=2048, 3072, or 4096) or "ecdsa" (with KEY_SIZE=256, 384, or 521)
KEY_ALGO="ecdsa"
KEY_SIZE=384

# Certificate validity periods (in hours)
CA_EXPIRY=$((365 * 24))        # CA certificates: 1 year
HOST_EXPIRY=$((47 * 24))       # Server certificates: ~47 days
EMAIL_EXPIRY=$((265 * 24))     # Email certificates: ~265 days

# Certificate subject fields (used in all generated certificates)
CERT_C="CZ"                    # Country
CERT_ST="Heart of Europe"      # State/Province
CERT_L="Prague"                # Locality/City
CERT_O="00 Split Step Company"   # Organization
CERT_OU="Security Dept."       # Organizational Unit

# CA Certificate Names
CA_CN="000-Split-Step-Root-CA"
ICA_CN="000-Split-Step-Intermediate-CA"

# ============================================================================
# INTERNAL VARIABLES (do not modify)
# ============================================================================
# Date format for display
DFMT="%Y/%m/%d %H:%M:%S %Z"

