#!/bin/bash

# Extract the base64 signature block
grep -A1000 "# SIG # Begin" signed.ps1 | grep "^#" | grep -v "SIG #" | sed 's/^# //' | base64 -d > sig.der

# Inspect the CMS structure
openssl pkcs7 -in sig.der -inform DER -print_certs -text -noout

# Or view the full ASN.1 structure
openssl asn1parse -in sig.der -inform DER
