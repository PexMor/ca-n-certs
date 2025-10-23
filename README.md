# Demo cfssl

An example how to use cfssl

The key path is `~/.config/demo-cfssl` at that place all the files are stored:

CA, ICA and server DN.O: `000 Special Org`

Other components of the X.509 DN (distingushed name is in `*.json`)

| file name     | purpose - description                          |
| ------------- | ---------------------------------------------- |
| ca-bundle.pem | root CA + intermediate CA certs                |
| ca-key.pem    | private key for root CA                        |
| ca.csr        | CA signing request                             |
| ca.pem        | root CA cert                                   |
| dhparam.pem   | DH parameters used by TLS server               |
| ica-key.pem   | private key for intermediate CA                |
| ica-self.pem  | self-signed intermediate CA cert               |
| ica.csr       | intermediate CA signing requests               |
| ica.pem       | root CA signed intermediate CA certificate     |
| hosts/        | directory containing host/server certificates  |
| smime/        | directory containing S/MIME email certificates |

### Hosts Directory Structure

Files in `hosts/<hostname>/` (e.g., `hosts/localhost/`):

| file name    | purpose - description                         |
| ------------ | --------------------------------------------- |
| cfg.json     | certificate configuration with CN and SANs    |
| host.json    | full certificate response from cfssl          |
| cert.pem     | host/server certificate (public key)          |
| key.pem      | private key for the certificate               |
| host.csr     | certificate signing request                   |
| bundle-2.pem | cert + intermediate CA                        |
| bundle-3.pem | cert + intermediate CA + root CA (full chain) |
| haproxy.pem  | bundle-3.pem + key.pem (for HAProxy)          |

### S/MIME Directory Structure

Files in `smime/<person-name>/` (e.g., `smime/john_doe/`):

| file name    | purpose - description                           |
| ------------ | ----------------------------------------------- |
| cfg.json     | certificate configuration with CN and emails    |
| email.json   | full certificate response from cfssl            |
| cert.pem     | S/MIME certificate (public key)                 |
| key.pem      | private key for the certificate                 |
| email.csr    | certificate signing request                     |
| bundle-2.pem | cert + intermediate CA                          |
| bundle-3.pem | cert + intermediate CA + root CA (full chain)   |
| email.p12    | PKCS#12 bundle for importing into email clients |

## Things to tweak

This line in `./mkCert.sh` creates the actual host certificate:

```bash
# ...
mkCert 03_host.json $C_TYPE $C_FN
# ...
```

parameters:

- `C_TYPE=server` ref. [profiles.json](profiles.json)
- `C_FN` is just a filename.

You should also tweak `03_host.json` either via

```bash
jq . 03_host.json | jq '.names[0].ST="Some" | .hosts=["super.name.lan"]' >tmp-03_host.json
```

Also a thing to look at is the `profiles.json`...

This example runs `containerized` in particular `Dockerized`.

Platform binaries to be downloaded at [https://github.com/cloudflare/cfssl/releases](https://github.com/cloudflare/cfssl/releases):

- cfssl-bundle
- cfssl-certinfo
- cfssl-newkey
- cfssl-scan
- [cfssljson](https://github.com/cloudflare/cfssl#the-cfssljson-utility) - program, which takes the JSON output from the cfssl and multirootca programs and writes certificates, keys, CSRs, and bundles to disk
- [cfssl](https://github.com/cloudflare/cfssl#using-the-command-line-tool) - program, which is the canonical command line utility using the CFSSL packages
- [mkbundle](https://github.com/cloudflare/cfssl#the-mkbundle-utility) - program is used to build certificate pool bundles
- [multirootca](https://github.com/cloudflare/cfssl#the-multirootca) - program, which is a certificate authority server that can use multiple signing keys

...it is GO-Lang: `go get github.com/cloudflare/cfssl/cmd/...`

## Testing and deploying

**Firefox:** have independed certificate store (incl.RootCA).
**Chrome & Safari & Edge/Chrome** use the system cert store (incl.RootCA).

```bash
export BP="$HOME/.config/demo-cfssl"
# following does not work with `update-ca-certificates`
# export DST="/usr/share/ca-certificates/extra"
export DST="/usr/local/share/ca-certificates/extra"
sudo mkdir -p "$DST"
cat "$BP/ca.pem" | sudo tee "$DST/000ca.crt"
sudo update-ca-certificates
# sudo dpkg-reconfigure ca-certificates
```

check intermediate CA CERT w/explicit root CA CERT:

```bash
openssl verify -CAfile "$BP/ca.pem" -verbose "$BP/ica.pem"
```

check intermediate CA CERT w/system root CA CERT - verifies the deployment went well:

```bash
openssl verify -verbose "$BP/ica.pem"
```

> Note: in the following examples the parameter `-untrusted` is the actual and correct one, as the trustworthiness is verified by the root CA...

check host CERT w/explicit root CA:

```bash
openssl verify -verbose -CAfile "$BP/ca.pem" \
    -untrusted "$BP/ica.pem" "$BP/localhost-server.pem"
```

check host CERT w/system root CA:

```bash
openssl verify -verbose -untrusted "$BP/ica.pem" "$BP/localhost-server.pem"
```

> Note: cfssl does not support plug-in (USB, Bluetooth, NFC) PKCS#11 tokens :-(

## HA Proxy test

This addition presents the use of generated CA's keys with `haproxy` in Docker container.

To test at first run the certificate creation as described above and the run `./demoHaproxy.sh`

## Do it on RaspberryPi

Head to releases: <https://github.com/cloudflare/cfssl/releases>

Select the latest build for `ARMv6` or `ARM64` if you are on RPi5 and later.

At the time of writing it was `cfssl_1.6.5_linux_armv6`

While revisiting the **one-click** solution I have found that for `day 2` operation perspective
it might be too fast for certain use-cases. For that reason I would elaborate a bit on steps
that you might find useful in case you do not need kind of **one-shot CA and server**.

The procedure is following:

1. generate **long term** CA certificate and key (like 10 years, do not forget **make note** in calendar!)
2. do the same for **long term** intermediate CA certificate (same as above)
3. generate **short term** certificate for what ever you need server, e-mail or even sub-CA (short period should be around 90 days - hint: **certbot - Let's Encrypt** policy)

## Notes

`8760` hours = `365` days

### Cert validity

as of `Oct23 2025`

For host (TLS/SSL) certificates, the current maximum validity period is
398 days, but this is being phased out in favor of shorter lifecycles. There is no official recommendation for email (S/MIME) certificates, but best practices suggest using a new key pair for each certificate and ensuring an annual renewal.

#### Current recommendations for host (TLS/SSL) certificates

The CA/Browser Forum, an industry body that includes major browsers like Apple, Google, and Microsoft, has approved a new schedule to progressively reduce the maximum validity of public TLS certificates.

- Current maximum (until March 15, 2026): 398 days, or approximately 13 months.
- Starting March 15, 2026: Maximum validity will be reduced to 200 days.
- Starting March 15, 2027: Maximum validity will drop to 100 days.
- Starting March 15, 2029: Maximum validity will be limited to just 47 days.

These changes are driven by security concerns, as shorter validity periods reduce the window of opportunity for attackers to exploit compromised keys or misissued certificates.

#### Recommendations for email (S/MIME) certificates

Email certificates, known as S/MIME certificates, are not subject to the same CA/Browser Forum rules as TLS/SSL certificates.

- Maximum validity: The validity period for S/MIME certificates is not publicly dictated by the CA/Browser Forum and is generally longer, with a maximum validity period of up to three years.
- Best practices: While not mandatory, best practices for secure email encourage shorter lifecycles and frequent key rotation. The following are suggested to improve security:
  - Annual renewal: Set a policy to renew S/MIME certificates on an annual basis.
  - New key pair: Generate a new public/private key pair with each renewal. This prevents attackers who might compromise an old key from decrypting future email traffic.
  - Automate management: Given the increasing complexity, automate the management of email certificates to ensure timely renewals and proper configuration.

## S/MIME Email Certificates

The `step_email` function generates S/MIME certificates for email signing and encryption following RFC 5280 standards.

### Usage

```bash
# Generate email certificate for a person
step_email "Person Name" email1@example.com [email2@example.com ...]
```

Parameters:

- First parameter: Person's name (becomes the CN in the certificate)
- Remaining parameters: Email addresses (added to Subject Alternative Name as rfc822Name)

Example:

```bash
step_email "John Doe" john.doe@example.com john@company.com
```

### Generated Files

Certificates are stored in `$BD/smime/<slugified-name>/` directory:

| File name    | Purpose                                               |
| ------------ | ----------------------------------------------------- |
| cfg.json     | Certificate configuration with CN and email addresses |
| email.json   | Full certificate response from cfssl                  |
| cert.pem     | S/MIME certificate (public key)                       |
| key.pem      | Private key                                           |
| email.csr    | Certificate signing request                           |
| bundle-2.pem | Certificate + intermediate CA                         |
| bundle-3.pem | Certificate + intermediate CA + root CA               |
| email.p12    | PKCS#12 file for importing into email clients         |

Note: The folder name is slugified (e.g., "John Doe" → "john_doe") for filesystem safety.

### PKCS#12 Password

By default, the PKCS#12 file is created without a password for ease of use. To set a password:

```bash
EMAIL_P12_PASSWORD="mypassword" step_email "John Doe" john.doe@example.com
```

### Importing into Email Clients

The `email.p12` file can be imported into:

- **Thunderbird**: Settings → Privacy & Security → Certificates → Manage Certificates → Your Certificates → Import
- **Outlook**: File → Options → Trust Center → Trust Center Settings → Email Security → Import/Export
- **Apple Mail**: Double-click the .p12 file or import via Keychain Access
- **Gmail/Webmail**: Settings → Accounts → Add S/MIME certificate

After importing, you'll be able to digitally sign and encrypt emails using your certificate.

### Certificate Profile

The email profile uses the following key usages suitable for S/MIME:

- `signing` - General signing capability
- `digital signature` - For signing emails
- `key encipherment` - For encrypting emails

Default expiry: 1 year (8760 hours)

## Signing Files with Timestamps

The `tsa_sign.sh` script allows you to sign files with detached signatures and add trusted timestamps from free TSA (Time Stamp Authority) servers.

### Usage

```bash
# Sign with P12 file (no password)
./tsa_sign.sh --p12 email.p12 document.pdf

# Sign with P12 file (with password)
./tsa_sign.sh --p12 email.p12 --password-file pass.txt report.pdf

# Sign with separate cert and key files
./tsa_sign.sh --cert cert.pem --key key.pem presentation.pptx

# Sign multiple files
./tsa_sign.sh --p12 email.p12 file1.pdf file2.docx file3.txt
```

### Features

- Creates detached signatures in PEM format (saved as `<filename>.sign_tsa`)
- Adds trusted timestamps from free TSA servers:
  - FreeTSA.org (http://freetsa.org/tsr)
  - Sectigo (http://timestamp.sectigo.com)
  - DigiCert (http://timestamp.digicert.com)
- Timestamp tokens saved separately as `<filename>.sign_tsa.tsr`
- Supports both PKCS#12 (.p12) and separate PEM files
- Password can be provided via file for automation
- Automatically tries multiple TSA servers if one fails
- Color-coded output for easy reading

### Verification

The `tsa_verify.sh` script provides easy verification of signed files:

```bash
# Simple verification (auto-detects signature file)
./tsa_verify.sh document.pdf

# Verify with certificate chain validation (uses default CA bundle)
./tsa_verify.sh document.pdf --verify-cert

# Verify with custom CA bundle
./tsa_verify.sh document.pdf --ca-file /path/to/ca-bundle.pem --verify-cert
```

The script automatically:

- Uses `$HOME/.config/demo-cfssl/ca-bundle-complete.pem` as default CA bundle
- Verifies the CMS signature
- Checks for and verifies timestamp (if .tsr file exists)
- Displays signer and certificate information
- Provides clear pass/fail status

**Manual verification with OpenSSL:**

```bash
# Verify signature (without checking certificate validity)
openssl cms -verify -in document.pdf.sign_tsa -inform PEM -content document.pdf -noverify

# Verify with certificate chain
openssl cms -verify -in document.pdf.sign_tsa -inform PEM -content document.pdf -CAfile ca-bundle.pem

# Verify timestamp (if .tsr file exists)
openssl ts -verify -in document.pdf.sign_tsa.tsr -data document.pdf -CAfile ca-bundle.pem
```

Note: The signature files are in PEM format (text-based, base64 encoded) for better portability.
Timestamp tokens are saved as separate `.tsr` files and can be verified independently.

### Building Complete CA Bundle

To verify signatures and timestamps, you need a CA bundle that combines your custom CAs with system trusted CAs:

```bash
# Build the combined CA bundle
./build_ca_bundle.sh

# This creates: $HOME/.config/demo-cfssl/ca-bundle-complete.pem
# Contains: Your Root CA + Intermediate CA + System trusted CAs
```

The combined bundle is needed for:

- Verifying your own certificate signatures with chain validation
- Verifying TSA timestamps (TSA certificates are signed by public CAs)

### Example Workflow

```bash
# 1. Generate email certificate
step_email "John Doe" john.doe@example.com

# 2. Build CA bundle (one time, or after CA changes)
./build_ca_bundle.sh

# 3. Sign a document
./tsa_sign.sh --p12 $HOME/.config/demo-cfssl/smime/john_doe/email.p12 important-document.pdf

# 4. Verify the signature (basic - no chain validation)
./tsa_verify.sh important-document.pdf

# 5. Verify with certificate chain validation (recommended)
./tsa_verify.sh important-document.pdf --verify-cert
```

## Certificate Revocation List (CRL) Management

The `crl_mk.sh` script provides comprehensive CRL management for both the Root CA and Intermediate CA.

### Quick Start

```bash
# Revoke a compromised certificate
./crl_mk.sh revoke ~/.config/demo-cfssl/hosts/localhost/cert.pem keyCompromise

# Generate the updated CRL
./crl_mk.sh generate ica

# List all revoked certificates
./crl_mk.sh list ica

# View CRL information (validity, expiration, etc.)
./crl_mk.sh info ica

# Verify a certificate against the CRL
./crl_mk.sh verify ~/.config/demo-cfssl/hosts/localhost/cert.pem ica

# Or use the dedicated checking tool
./crl_check.sh ~/.config/demo-cfssl/hosts/localhost/cert.pem
```

### Revocation Reasons

When revoking a certificate, you can specify a reason:

- `unspecified` - Default reason
- `keyCompromise` - Private key has been compromised
- `CACompromise` - CA key has been compromised
- `affiliationChanged` - Certificate holder changed organization
- `superseded` - Certificate has been replaced
- `cessationOfOperation` - Service no longer exists
- `certificateHold` - Temporarily revoked

### CRL Files

After generating a CRL, you'll find:

| File name     | Purpose                                    |
| ------------- | ------------------------------------------ |
| ica-crl.pem   | Intermediate CA CRL in PEM format          |
| ica-crl.der   | Intermediate CA CRL in DER format          |
| ca-crl.pem    | Root CA CRL in PEM format (if needed)      |
| ca-crl.der    | Root CA CRL in DER format (if needed)      |
| crl/ica/      | Intermediate CA revocation database        |
| crl/ca/       | Root CA revocation database                |

### Testing CRL Functionality

Run the included test script to see CRL management in action:

```bash
./crl_test.sh
```

This script demonstrates:
- Generating an initial CRL
- Revoking a certificate
- Updating the CRL
- Verifying revocation status
- Listing revoked certificates

### CRL Maintenance

CRLs expire after 30 days by default. Set up a cron job to regenerate them:

```bash
# Regenerate Intermediate CA CRL every Monday at 2 AM
0 2 * * 1 /path/to/demo-cfssl/crl_mk.sh generate ica
```

### Integration with Web Servers

**HAProxy:**
```haproxy
frontend https_front
    bind *:443 ssl crt /path/to/certs/ ca-file ca-bundle.pem crl-file ica-crl.pem verify required
```

**Nginx:**
```nginx
server {
    listen 443 ssl;
    ssl_client_certificate /path/to/ca-bundle.pem;
    ssl_crl /path/to/ica-crl.pem;
    ssl_verify_client on;
}
```

**Apache:**
```apache
SSLCACertificateFile /path/to/ca-bundle.pem
SSLCARevocationFile /path/to/ica-crl.pem
SSLVerifyClient require
```

For complete documentation, see [CRL_MANAGEMENT.md](CRL_MANAGEMENT.md).

### Certificate Revocation Checking

The `crl_check.sh` script provides a dedicated tool for checking certificate validity:

```bash
# Basic check
./crl_check.sh /path/to/certificate.pem

# Verbose mode with full details
./crl_check.sh cert.pem --verbose

# JSON output for automation
./crl_check.sh cert.pem --json

# Batch check multiple certificates
cat > certs-to-check.txt << EOF
~/.config/demo-cfssl/hosts/server1/cert.pem
~/.config/demo-cfssl/hosts/server2/cert.pem
~/.config/demo-cfssl/smime-openssl/john_doe/cert.pem
EOF

./crl_check.sh --batch certs-to-check.txt
```

**Features:**
- Auto-detects appropriate CRL (Root CA vs Intermediate CA)
- Multiple output formats: normal, verbose, quiet, JSON
- Batch checking mode for multiple certificates
- Exit codes: 0 (valid), 1 (revoked), 2 (error)
- Detailed certificate information display
- Suitable for scripting and automation

## To-Dos

- OCSP (Online Certificate Status Protocol)
- OCSP Stapling integration
- Automated CRL distribution (HTTP/HTTPS endpoint)
