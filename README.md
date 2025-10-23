# demo-cfssl

A comprehensive example of using CloudFlare's CFSSL for creating and managing a Certificate Authority (CA) infrastructure with CRL and OCSP support.

## Quick Start

```bash
# Generate CA, Intermediate CA, and first certificate
./steps.sh

# Start OCSP responder
cd ocsp && ./start.sh
```

## Features

- ✅ Root CA and Intermediate CA setup
- ✅ Host/Server certificate generation (TLS/SSL)
- ✅ S/MIME email certificates with PKCS#12 export
- ✅ Certificate Revocation Lists (CRL)
- ✅ OCSP Responder (RFC 6960 compliant)
- ✅ Document signing with timestamps (TSA)
- ✅ Comprehensive testing and examples
- ✅ Docker support for all components

## Documentation

- **[Getting Started](docs/getting-started.md)** - Installation and first steps
- **[Certificate Management](docs/certificate-management.md)** - Creating and managing certificates
- **[Certificate Revocation](docs/revocation.md)** - CRL and OCSP revocation
- **[Production Deployment](docs/deployment.md)** - Deploy to production environments
- **[Examples & Workflows](docs/examples.md)** - Practical examples and use cases
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## Architecture

See **[AGENTS.md](AGENTS.md)** for architectural decisions, technology choices, and AI agent guidance.

## Project Structure

```
demo-cfssl/
├── steps.sh              # Main certificate generation script
├── mkCert.sh             # Docker-based certificate generation
├── crl_mk.sh            # CRL management
├── crl_check.sh         # Certificate revocation checking
├── tsa_sign.sh          # Document signing with timestamps
├── tsa_verify.sh        # Signature verification
├── build_ca_bundle.sh   # Build complete CA bundle
├── profiles.json        # Certificate profiles configuration
├── ocsp/                # OCSP responder implementation
│   ├── main.py          # FastAPI OCSP server
│   ├── start.sh         # Quick start script
│   └── README.md        # OCSP documentation
├── haproxy/             # HAProxy example configuration
├── squid/               # Squid proxy example
├── pdf-signer/          # PDF signing tool
└── tests/               # Test implementations
```

## Storage Location

Certificates are stored in `~/.config/demo-cfssl/` by default:

```
~/.config/demo-cfssl/
├── ca.pem              # Root CA certificate
├── ca-key.pem          # Root CA private key
├── ica-ca.pem          # Intermediate CA certificate
├── ica-key.pem         # Intermediate CA private key
├── ca-bundle.pem       # CA + ICA bundle
├── hosts/              # Server certificates
│   └── hostname/
│       ├── cert.pem
│       ├── key.pem
│       └── bundle-*.pem
├── smime/              # Email certificates
│   └── person_name/
│       ├── cert.pem
│       ├── key.pem
│       └── email.p12
└── crl/                # Revocation database
```

## Requirements

- **cfssl** / **cfssljson** - Certificate generation
- **OpenSSL** - Certificate operations
- **Python 3.8+** - OCSP responder
- **Docker** (optional) - Containerized deployment

### Platform Binaries

Download from [cloudflare/cfssl releases](https://github.com/cloudflare/cfssl/releases):
- `cfssl` - Certificate generation
- `cfssljson` - JSON to certificate converter
- `cfssl-bundle` - Bundle creator
- `cfssl-certinfo` - Certificate inspector

Or use Docker: `cfssl/cfssl`

## Key Commands

```bash
# Generate certificates
./steps.sh

# Revoke a certificate
./crl_mk.sh revoke path/to/cert.pem keyCompromise
./crl_mk.sh generate ica

# Check certificate status
./crl_check.sh path/to/cert.pem

# Sign a document with timestamp
./tsa_sign.sh --p12 email.p12 document.pdf

# Start OCSP responder
cd ocsp && python main.py

# Test OCSP validation
openssl ocsp -issuer ~/.config/demo-cfssl/ica-ca.pem \
    -cert ~/.config/demo-cfssl/hosts/localhost/cert.pem \
    -url http://localhost:8080/ocsp -text
```

## Certificate Validity Periods

Following current industry standards (as of October 2025):

- **Root CA**: 10 years (87,600 hours)
- **Intermediate CA**: 5-10 years
- **TLS/SSL Certificates**: 47 days (maximum 398 days until March 2026)
- **Email Certificates**: 265 days (approximately 9 months)

See [Certificate Management](docs/certificate-management.md) for detailed information on validity periods and renewal strategies.

## Use Cases

- **Development**: Local HTTPS testing with custom CA
- **Enterprise**: Internal PKI infrastructure
- **Learning**: Understanding certificate authorities and PKI
- **Testing**: Certificate revocation and validation
- **Production**: Small to medium-scale certificate management

## License

See [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please see individual component documentation for specific areas.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.

## Related Projects

- [pdf-signer](pdf-signer/) - PDF document signing tool
- [CloudFlare CFSSL](https://github.com/cloudflare/cfssl) - Certificate authority toolkit
- [Let's Encrypt](https://letsencrypt.org/) - Free, automated CA for public certificates

---

**Note**: This is a demonstration project for educational and testing purposes. For production use, ensure proper security measures, key protection, and compliance with your organization's policies.
