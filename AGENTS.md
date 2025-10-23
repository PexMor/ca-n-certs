# Architectural Decision Record (ADR) and AI Agent Guidance

This document captures architectural decisions, technology choices, and design patterns to help both humans and AI agents understand and work with this codebase.

## Project Overview

**Purpose**: A comprehensive demonstration of Certificate Authority (CA) management using CloudFlare's CFSSL toolkit, including certificate generation, revocation (CRL), and online validation (OCSP).

**Target Audience**: 
- Developers learning PKI/certificate management
- System administrators managing internal CAs
- Teams needing certificate infrastructure for development/testing
- AI agents assisting with certificate operations

## Technology Stack

### Core Technologies

| Component | Technology | Reason |
|-----------|-----------|---------|
| **CA Generation** | CFSSL | Industry-standard, simple JSON configuration, Docker support |
| **OCSP Responder** | Python + FastAPI | Fast, modern, easy to extend, excellent documentation |
| **Certificate Operations** | OpenSSL | Universal standard, available everywhere, comprehensive features |
| **Container Runtime** | Docker | Portability, isolation, reproducibility |
| **Scripting** | Bash | Universal availability, simple automation, chain-able commands |

### OCSP Responder Stack

- **FastAPI** (0.115.0+)
  - *Why*: Modern Python framework, auto-documentation, async support, type safety
  - *Alternative considered*: Flask (too basic), Django (too heavy)
  
- **uvicorn** 
  - *Why*: High-performance ASGI server, production-ready
  - *Alternative considered*: Gunicorn (less async support)

- **cryptography** library
  - *Why*: Pure Python, comprehensive, well-maintained, RFC-compliant
  - *Alternative considered*: PyOpenSSL (lower-level, less convenient)

### Why Not Use CFSSL's Built-in OCSP?

CFSSL includes `cfssl ocspserve`, but we implemented our own:

**Reasons**:
1. **Learning Value**: Educational project demonstrating RFC 6960
2. **Flexibility**: Easier to customize and extend
3. **Integration**: Better integration with our CRL database format
4. **Monitoring**: Custom health/status endpoints
5. **Control**: Full control over response logic

## Architectural Decisions

### ADR-001: Certificate Storage Location

**Decision**: Store certificates in `~/.config/demo-cfssl/`

**Context**: Need predictable, user-accessible location

**Rationale**:
- Follows XDG Base Directory Specification
- User-writable without sudo
- Clean separation from system certs
- Easy to backup/migrate

**Alternatives Considered**:
- `/opt/demo-cfssl` - Requires root, less portable
- `./certs/` - Not discoverable across sessions
- `~/.demo-cfssl/` - Pollutes home directory with dot-file

### ADR-002: Dual Certificate Generation Methods

**Decision**: Support both CFSSL and OpenSSL for certificate generation

**Context**: CFSSL cannot add OCSP/CRL URLs natively

**Rationale**:
- CFSSL: Simple, JSON-based, good for basic certificates
- OpenSSL: Required for X.509 extensions (AIA, CDP)
- Both methods use same CA/ICA for signing

**Implementation**:
- `step03()` function - CFSSL method
- `step03_with_ocsp()` - OpenSSL method with extensions
- `step_email_openssl()` - OpenSSL for email certs with proper EKU

### ADR-003: CRL Database Format

**Decision**: Simple text-based database file

**Format**: `R|serial_hex|revocation_date|reason|CN`

**Rationale**:
- Human-readable and auditable
- Easy to parse in shell scripts
- No database server required
- Sufficient for small to medium scale

**Limitations**:
- Not suitable for millions of certificates
- Requires file locking for concurrent writes
- No transaction support

**Future Migration Path**: PostgreSQL or SQLite for scale

### ADR-004: Key Algorithm Choice

**Decision**: ECDSA P-384 by default, RSA 4096 as alternative

**Current Default**:
```bash
KEY_ALGO="ecdsa"
KEY_SIZE=384  # P-384 curve
```

**Rationale**:
- Shorter keys, faster operations
- Equivalent security to RSA-7680
- Modern cryptography standard
- Smaller certificate sizes

**Override**: Set in `steps.sh` for RSA if needed

### ADR-005: Certificate Validity Periods

**Decision**: Conservative validity periods

| Certificate Type | Validity | Rationale |
|-----------------|----------|-----------|
| Root CA | 10 years | Long-lived, rarely changed |
| Intermediate CA | 5-10 years | Balance security/operations |
| TLS/SSL | 47 days | Industry trend (398 → 200 → 100 → 47 days) |
| Email | 265 days | No industry mandate, ~9 months reasonable |

**Context**: CA/Browser Forum requirements, industry best practices

### ADR-006: OCSP Responder Architecture

**Decision**: Stateless responder with database reload on restart

**Architecture**:
```
Client → OCSP Responder → In-Memory Revocation DB
                             ↑
                        Load from CRL database on startup
```

**Rationale**:
- Simple implementation
- Fast lookups (O(1) in-memory dict)
- No database server required
- Restart to reload (acceptable for small scale)

**Limitations**:
- Requires restart to pick up revocations
- Memory usage grows with revoked certs
- Not suitable for high-frequency revocations

**Future Enhancement**: File watching with inotify/watchdog

### ADR-007: Separate OCSP Project Structure

**Decision**: OCSP responder in dedicated `ocsp/` directory

**Structure**:
```
ocsp/
├── main.py              # Self-contained application
├── requirements.txt     # Independent dependencies
├── README.md            # Comprehensive docs
└── start.sh            # Easy launcher
```

**Rationale**:
- Clear separation of concerns
- Independent deployment
- Self-documenting
- Can be extracted as separate project

### ADR-008: Documentation Strategy

**Decision**: Multi-level documentation

1. **README.md** - Brief overview, links to detailed docs
2. **AGENTS.md** - Architectural decisions (this file)
3. **docs/** - Comprehensive guides by topic
4. **Component READMEs** - Specific documentation (ocsp/, pdf-signer/)

**Rationale**:
- Avoid overwhelming users
- Progressive disclosure
- Easy for AI agents to parse
- Maintainable by topic

### ADR-009: Error Handling Philosophy

**Decision**: Fail fast in shell scripts, graceful in services

**Shell Scripts** (`set -e`):
- Exit immediately on error
- Clear error messages
- Predictable behavior

**Services** (OCSP):
- Graceful error responses
- Logging for debugging
- Continue serving

### ADR-010: Testing Approach

**Decision**: Practical examples > Unit tests

**Rationale**:
- Educational project
- Shell scripts hard to unit test
- Integration tests more valuable
- Example scripts serve as tests

**Implementation**:
- `test_ocsp.sh` - Comprehensive OCSP testing
- `example_workflow.sh` - Interactive demonstration
- `crl_test.sh` - CRL management testing

## Code Patterns

### Shell Script Pattern

```bash
#!/bin/bash
set -e  # Fail fast

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
COFF='\033[0m'

# Configuration
BD="${DEMO_CFSSL_DIR:-$HOME/.config/demo-cfssl}"

# Functions first
function do_something() {
    local ARG=$1
    # ...
}

# Main execution
do_something "value"
```

### Python Service Pattern (OCSP)

```python
# FastAPI application
app = FastAPI(title="Service Name")

# Configuration from environment
CONFIG = os.environ.get('VAR', 'default')

# Class-based logic
class ServiceHandler:
    def __init__(self):
        self.load_data()
    
    def load_data(self):
        # Load from files
        pass

# Endpoints
@app.get("/")
async def root():
    return {"info": "..."}

@app.get("/health")
async def health():
    return {"status": "healthy"}

# Main
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

## Security Considerations

### Key Protection

**Private Keys**: Stored with 600 permissions
- Root CA key: `~/.config/demo-cfssl/ca-key.pem`
- ICA key: `~/.config/demo-cfssl/ica-key.pem`

**Production**: Use HSM or key management service

### OCSP Security

**Current**: OCSP responder reads CA private keys directly

**Production Improvements**:
1. Dedicated OCSP signing certificate
2. HSM integration
3. Key file access auditing
4. Network segmentation

### CRL Security

**Current**: CRLs signed with CA/ICA private keys

**Best Practice**: Regular regeneration (30 day expiry)

## Scaling Considerations

### Small Scale (< 1000 certs)

Current implementation is suitable:
- File-based storage
- Single OCSP instance
- Manual CRL distribution

### Medium Scale (1000-10000 certs)

Enhancements needed:
- Database backend (PostgreSQL)
- Multiple OCSP instances + load balancer
- Automated CRL distribution (CDN)
- Monitoring and alerting

### Large Scale (> 10000 certs)

Consider:
- Full PKI solution (EJBCA, Boulder)
- HSM for key storage
- OCSP stapling pre-generation
- Geo-distributed OCSP responders

## Integration Points

### With Web Servers

Certificates integrate with:
- **Nginx**: `ssl_certificate`, `ssl_certificate_key`
- **Apache**: `SSLCertificateFile`, `SSLCertificateKeyFile`
- **HAProxy**: Combined PEM file (`bundle-3.pem` + `key.pem`)

### With Email Clients

PKCS#12 files (`.p12`) import into:
- Thunderbird
- Outlook
- Apple Mail
- Gmail/Webmail

### With Applications

CA bundle for validation:
- System trust store: `/etc/ssl/certs/`
- Application-specific: Pass `ca-bundle.pem`
- Python `requests`: `verify='path/to/ca-bundle.pem'`
- Node.js: `NODE_EXTRA_CA_CERTS=path/to/ca-bundle.pem`

## AI Agent Guidance

### When Generating Certificates

1. Check if CA/ICA exist: `test -f ~/.config/demo-cfssl/ca.pem`
2. For basic certs: Use `step03()` function
3. For certs with OCSP: Use `step03_with_ocsp()` with URLs
4. For email: Use `step_email_openssl()` for proper EKU

### When Managing Revocation

1. Revoke: `./crl_mk.sh revoke path/to/cert.pem reason`
2. Generate CRL: `./crl_mk.sh generate ica`
3. Verify: `./crl_check.sh path/to/cert.pem`
4. Restart OCSP to reload database

### When Debugging

1. Check certificate details: `openssl x509 -in cert.pem -noout -text`
2. Verify chain: `openssl verify -CAfile ca-bundle.pem cert.pem`
3. Test OCSP: `openssl ocsp -issuer ica-ca.pem -cert cert.pem -url http://localhost:8080/ocsp -text`
4. Check CRL: `openssl crl -in crl.pem -noout -text`

### Common Modifications

**Change validity periods**: Edit `steps.sh` variables:
```bash
CA_EXPIRY=`expr 365 \* 24`      # Hours
HOST_EXPIRY=`expr 47 \* 24`
EMAIL_EXPIRY=`expr 265 \* 24`
```

**Change key algorithm**: Edit `steps.sh`:
```bash
KEY_ALGO="rsa"  # or "ecdsa"
KEY_SIZE=4096   # or 384 for ECDSA
```

**Add OCSP/CRL URLs**: Use OpenSSL method or helper functions in docs

## Maintenance Guidelines

### Regular Tasks

1. **CRL Regeneration**: Every 30 days (cron job)
2. **Certificate Renewal**: Before expiry (monitoring recommended)
3. **OCSP Health Check**: Monitor `/health` endpoint
4. **Backup**: CA keys, revocation database

### Monitoring

**Key Metrics**:
- Certificate expiration dates
- CRL validity period
- OCSP response time
- Revocation database size

**Health Checks**:
- `curl http://localhost:8080/health`
- `./crl_mk.sh info ica`
- `openssl x509 -in cert.pem -noout -enddate`

## Future Enhancements

### Short Term
- Auto-reload OCSP on database changes
- Web UI for certificate management
- Prometheus metrics

### Long Term
- Database backend option
- Multi-CA support
- HSM integration
- Kubernetes operators

## References

- [RFC 5280](https://tools.ietf.org/html/rfc5280) - X.509 Certificates
- [RFC 6960](https://tools.ietf.org/html/rfc6960) - OCSP
- [RFC 5280](https://tools.ietf.org/html/rfc5280) - CRL
- [CA/Browser Forum](https://cabforum.org/) - Industry standards
- [CFSSL Documentation](https://github.com/cloudflare/cfssl)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

---

**Last Updated**: October 23, 2025
**Document Version**: 1.0.0

