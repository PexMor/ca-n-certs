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

| Component                  | Technology       | Reason                                                           |
| -------------------------- | ---------------- | ---------------------------------------------------------------- |
| **CA Generation**          | CFSSL            | Industry-standard, simple JSON configuration, Docker support     |
| **OCSP Responder**         | Python + FastAPI | Fast, modern, easy to extend, excellent documentation            |
| **Certificate Operations** | OpenSSL          | Universal standard, available everywhere, comprehensive features |
| **Container Runtime**      | Docker           | Portability, isolation, reproducibility                          |
| **Scripting**              | Bash             | Universal availability, simple automation, chain-able commands   |

### OCSP Responder Stack

- **FastAPI** (0.115.0+)
  - _Why_: Modern Python framework, auto-documentation, async support, type safety
  - _Alternative considered_: Flask (too basic), Django (too heavy)
- **uvicorn**

  - _Why_: High-performance ASGI server, production-ready
  - _Alternative considered_: Gunicorn (less async support)

- **cryptography** library
  - _Why_: Pure Python, comprehensive, well-maintained, RFC-compliant
  - _Alternative considered_: PyOpenSSL (lower-level, less convenient)

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

| Certificate Type | Validity   | Rationale                                  |
| ---------------- | ---------- | ------------------------------------------ |
| Root CA          | 10 years   | Long-lived, rarely changed                 |
| Intermediate CA  | 5-10 years | Balance security/operations                |
| TLS/SSL          | 47 days    | Industry trend (398 → 200 → 100 → 47 days) |
| Email            | 265 days   | No industry mandate, ~9 months reasonable  |

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

### ADR-011: Code Signing Certificate Algorithm (RSA Required)

**Decision**: Use RSA 3072-bit for code signing certificates, NOT ECDSA

**Context**: Windows Authenticode for PowerShell scripts only supports RSA

**Problem**:
ECDSA signatures are valid CMS/PKCS#7 structures, but Windows' Authenticode implementation
for PowerShell scripts effectively only understands RSA code-signing certificates.
PowerShell's SIP ignores ECDSA signatures and `Get-AuthenticodeSignature` reports `NotSigned`.

**Solution**:

```bash
# The step_codesign function defaults to RSA
step_codesign "MyCodeSign"          # RSA 3072-bit (default)
step_codesign "MyCodeSign" rsa      # Explicit RSA
step_codesign "MyCodeSign" ecdsa    # ECDSA - NOT for Windows!
```

**Key Algorithm Compatibility**:

| Platform                          | RSA          | ECDSA                |
| --------------------------------- | ------------ | -------------------- |
| Windows Authenticode (PowerShell) | ✅ Required  | ❌ Reports NotSigned |
| Windows Authenticode (PE/DLL)     | ✅ Supported | ⚠️ Limited support   |
| Linux/macOS (CMS verification)    | ✅ Supported | ✅ Supported         |

**Technical Details**:

- Windows CryptoAPI and Authenticode ecosystem is RSA-centric
- `Set-AuthenticodeSignature` fails with ECDSA code-signing certs
- ECDSA signatures have valid `signedData` (OID 1.2.840.113549.1.7.2) but are ignored
- RSA 3072-bit provides equivalent security to ECDSA P-256

**Rationale**:

- Maximize compatibility with Windows systems
- Avoid confusion when signatures appear valid but report "NotSigned"
- RSA 3072-bit is still secure and performant for code signing use cases
- `test_ocsp.sh` - Comprehensive OCSP testing
- `example_workflow.sh` - Interactive demonstration
- `crl_test.sh` - CRL management testing

### ADR-012: Code Signing Intermediate CA (CSICA)

**Decision**: Use a separate Intermediate CA specifically for code signing certificates

**Context**: Windows Authenticode validates EKU chain compatibility

**Problem**:
Windows CryptoAPI computes effective EKU as the **intersection** of EKUs along the entire certificate chain.
The regular Intermediate CA (ICA) has EKUs: `ServerAuth, ClientAuth, SecureEmail` but NOT `codeSigning`.
Even though the leaf certificate has `codeSigning` EKU, Windows rejects the chain because:

```
{CodeSigning} ∩ {ServerAuth, ClientAuth, SecureEmail} = ∅
```

This results in "Certificate is not valid for the requested usage" error.

**Solution**:

Create a dedicated Code Signing Intermediate CA (CSICA) with `codeSigning` EKU:

```bash
# CSICA is created automatically before code signing certificates
step_csica                    # Creates Code Signing Intermediate CA
step_codesign "MyCodeSign"    # Issues cert from CSICA (not regular ICA)
```

**Certificate Chain Structure**:

| Certificate              | EKU                                 | Purpose                       |
| ------------------------ | ----------------------------------- | ----------------------------- |
| Root CA                  | (none - unconstrained)              | Trust anchor                  |
| ICA (regular)            | ServerAuth, ClientAuth, SecureEmail | TLS, email certificates       |
| **CSICA (code signing)** | **codeSigning**                     | **Code signing certificates** |
| Code Signing Leaf        | codeSigning                         | Signs PowerShell, executables |

**EKU Chain Validation** (Windows):

```
Code Signing chain: Root (∅) ∩ CSICA ({codeSigning}) ∩ Leaf ({codeSigning}) = {codeSigning} ✅
TLS chain:          Root (∅) ∩ ICA ({Server,Client,Email}) ∩ Leaf ({Server}) = {Server} ✅
```

**Files Created**:

- `~/.config/demo-cfssl/csica-key.pem` - CSICA private key (RSA 4096-bit)
- `~/.config/demo-cfssl/csica-ca.pem` - CSICA certificate (signed by Root CA)
- `~/.config/demo-cfssl/csica-openssl.cnf` - OpenSSL config used

**Important Notes**:

1. CSICA uses RSA 4096-bit key for maximum Windows compatibility
2. CSICA has `pathlen:0` constraint - can only issue end-entity certs
3. After regenerating CSICA, all code signing certificates must be reissued
4. Import both Root CA and CSICA to Windows trust stores for validation

**Windows Import**:

```powershell
# Import Root CA to Trusted Root
Import-Certificate -FilePath ca.pem -CertStoreLocation Cert:\CurrentUser\Root

# Import CSICA to Intermediate CA store
Import-Certificate -FilePath csica-ca.pem -CertStoreLocation Cert:\CurrentUser\CA

# Import code signing PFX to Personal store
Import-PfxCertificate -FilePath codesign.p12 -CertStoreLocation Cert:\CurrentUser\My
```

### ADR-013: Windows SIP Canonicalization for Cross-Platform Signing

**Decision**: Implement Windows PowerShell SIP hash canonicalization in Python for cross-platform script signing

**Context**: PowerShell script signatures require a specific hash computation that differs from raw file hashing

**Discovery Date**: December 17, 2025

**The Problem**:

Windows' PowerShell SIP (`pwrshsip.dll`) does NOT hash raw file bytes. Early attempts at cross-platform
signing failed with `HashMismatch` because we computed SHA1 of raw bytes while Windows computes SHA1 of
UTF-16-LE encoded content.

**Hash Comparison** (same file content):

| Method                 | SHA1 Hash                                         |
| ---------------------- | ------------------------------------------------- |
| Raw bytes              | `c71dbef72717fef7fea2acc2235d5927cdbc3725`        |
| UTF-8 → UTF-16-LE      | `fadd6127c82c3501fdccd31768b52083e35bdbe4`        |
| **CP1252 → UTF-16-LE** | **`81f785f3a076e0a6a6d8cd5393ed251a5432cccb`** ✅ |
| Windows embedded       | `81f785f3a076e0a6a6d8cd5393ed251a5432cccb` ✅     |

**The Algorithm** (reverse-engineered from `pwrshsip.dll` behavior):

```python
def compute_sip_hash(raw_bytes: bytes, algorithm: str = 'sha1') -> bytes:
    # Step 1: Detect encoding (check first 32 bytes only!)
    if has_utf16_le_bom(raw_bytes):
        encoding = 'utf-16-le'
    elif has_utf16_be_bom(raw_bytes):
        encoding = 'utf-16-be'
    elif has_utf8_bom(raw_bytes):
        encoding = 'utf-8-sig'
    elif has_utf8_multibyte_in_first_32_bytes(raw_bytes):
        encoding = 'utf-8'
    else:
        encoding = 'cp1252'  # Windows-1252 ANSI fallback

    # Step 2: Decode to string
    text = raw_bytes.decode(encoding)

    # Step 3: Convert to UTF-16-LE (the canonicalization!)
    utf16_bytes = text.encode('utf-16-le')

    # Step 4: Hash
    return hashlib.sha1(utf16_bytes).digest()
```

**Key Insight**: The encoding detection only checks the **first 32 bytes**. If a file has UTF-8
multi-byte characters (like ✓ ✗) at position 473, they won't be detected, and the file falls
back to CP1252. This causes UTF-8 multi-byte sequences to be interpreted as separate CP1252
characters, producing a different Unicode string and thus a different UTF-16-LE hash.

**Implementation** (`pkipy/__main__.py`):

```python
def is_text_utf8(data: bytes) -> bool:
    """Check first 32 bytes for valid UTF-8 multi-byte sequences."""
    check_data = data[:32]
    # ... (validates UTF-8 continuation bytes)

def get_script_encoding(data: bytes) -> str:
    """Detect encoding matching Windows SIP behavior."""
    # Check BOMs first, then UTF-8 multi-byte, then fallback to CP1252

def compute_sip_hash(script_bytes: bytes, hash_algorithm: str) -> bytes:
    """Compute hash the same way Windows PowerShell SIP does."""
    encoding = get_script_encoding(script_bytes)
    text = script_bytes.decode(encoding)
    utf16_bytes = text.encode('utf-16-le')
    return hashlib.sha1(utf16_bytes).digest()
```

**Result**: `pkipy` can now sign PowerShell scripts on Linux/macOS that validate on Windows!

**References**:

- [PowerShell-OpenAuthenticode](https://github.com/jborean93/PowerShell-OpenAuthenticode) - Key insight into UTF-16-LE
- PowerShell SIP GUID: `603BCC1F-4B59-4E08-B724-D2C6297EF351`
- SIP DLL: `pwrshsip.dll`

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
