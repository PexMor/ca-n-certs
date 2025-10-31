# mytsa - Pure-Python RFC 3161 Time Stamp Authority Server

A pure-Python implementation of an RFC 3161 Time Stamp Authority (TSA) server using FastAPI. No OpenSSL binary required for server operation.

## Features

- ✅ **RFC 3161 Compliant**: Full implementation of the Time-Stamp Protocol
- ✅ **Pure Python**: No OpenSSL binary dependency (uses `asn1crypto` and `cryptography`)
- ✅ **FastAPI**: Modern, fast web framework with automatic API documentation
- ✅ **Easy Integration**: Works with existing CA infrastructure from `steps.sh`
- ✅ **Docker Support**: Ready-to-deploy containerized setup
- ✅ **Proper EKU**: Certificates generated with critical `timeStamping` Extended Key Usage
- ✅ **Thread-Safe**: Serial number management with file locking
- ✅ **Standards Compliant**: Includes `signingCertificateV2` attribute per RFC 5035

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for a 5-minute setup guide.

## Prerequisites

1. **Generate TSA Certificate** using `steps.sh`:

   ```bash
   # From the project root
   ./steps.sh
   ```

   This will create a TSA certificate at `~/.config/demo-cfssl/tsa/mytsa/` with the proper `timeStamping` Extended Key Usage.

2. **Python 3.13+** installed

3. **Install dependencies**:

   ```bash
   # Using uv (recommended)
   cd mytsa
   uv sync

   # Or using pip
   pip install -r requirements.txt
   ```

## Installation

### Option 1: Using uv (recommended)

```bash
cd mytsa
uv sync
uv run mytsa --help
```

### Option 2: Using pip

```bash
cd mytsa
pip install -e .
mytsa --help
```

### Option 3: Docker

```bash
cd mytsa
docker-compose up -d
```

## Usage

### Start the Server

```bash
# From mytsa directory
./start.sh

# Or directly
uvicorn mytsa.main:app --host 0.0.0.0 --port 8080

# Or with CLI
python -m mytsa --host 0.0.0.0 --port 8080
```

The server will start on `http://localhost:8080`

### Test the Server

```bash
# Run comprehensive tests
./test_tsa.sh

# Or run example workflow
./example_workflow.sh
```

## API Endpoints

### POST /tsa

RFC 3161 timestamp endpoint. Accepts DER-encoded `TimeStampReq` (TSQ) and returns DER-encoded `TimeStampResp` (TSR).

**Content-Type**: `application/timestamp-query` (required)

**Example**:

```bash
# Create timestamp request
openssl ts -query -data file.pdf -sha256 -cert -out request.tsq

# Send to TSA server
curl -X POST \
  -H "Content-Type: application/timestamp-query" \
  --data-binary @request.tsq \
  http://localhost:8080/tsa \
  -o response.tsr

# Verify response
openssl ts -reply -in response.tsr -text
```

### GET /tsa/certs

Download TSA certificate chain (TSA cert + intermediates + root) as PEM file.

**Example**:

```bash
curl -O http://localhost:8080/tsa/certs
```

### GET /health

Health check endpoint.

**Example**:

```bash
curl http://localhost:8080/health
```

### GET /

API information and status.

**Example**:

```bash
curl http://localhost:8080/
```

## Configuration

Configure via environment variables:

| Variable               | Default                                        | Description                   |
| ---------------------- | ---------------------------------------------- | ----------------------------- |
| `TSA_CERT_PATH`        | `~/.config/demo-cfssl/tsa/mytsa/cert.pem`      | TSA certificate file          |
| `TSA_KEY_PATH`         | `~/.config/demo-cfssl/tsa/mytsa/key.pem`       | TSA private key file          |
| `TSA_CHAIN_PATH`       | `~/.config/demo-cfssl/tsa/mytsa/bundle-3.pem`  | Certificate chain file        |
| `TSA_SERIAL_PATH`      | `~/.config/demo-cfssl/tsa/mytsa/tsaserial.txt` | Serial number file            |
| `TSA_POLICY_OID`       | `1.3.6.1.4.1.13762.3`                          | TSA policy OID                |
| `TSA_ACCURACY_SECONDS` | `1`                                            | Timestamp accuracy in seconds |
| `TSA_KEY_PASSWORD`     | (none)                                         | Optional private key password |

Example:

```bash
export TSA_POLICY_OID="1.2.3.4.5"
export TSA_ACCURACY_SECONDS=5
./start.sh
```

## TSA Certificate Requirements

The TSA certificate **must** have the following extensions:

- `extendedKeyUsage = critical, timeStamping` (OID: 1.3.6.1.5.5.7.3.8)
- `keyUsage = digitalSignature, nonRepudiation`
- `basicConstraints = CA:FALSE`

The `step_tsa()` function in `steps.sh` generates certificates with these extensions automatically.

To verify your certificate has the correct extensions:

```bash
openssl x509 -in ~/.config/demo-cfssl/tsa/mytsa/cert.pem -noout -text | grep -A2 "Extended Key Usage"
```

You should see: `Time Stamping`

## Client Examples

### OpenSSL Command Line

```bash
# Create timestamp request
echo "Document to timestamp" > document.txt
openssl ts -query -data document.txt -sha256 -cert -out request.tsq

# Get timestamp
curl -X POST \
  -H "Content-Type: application/timestamp-query" \
  --data-binary @request.tsq \
  http://localhost:8080/tsa \
  -o response.tsr

# Verify timestamp
openssl ts -reply -in response.tsr -text
openssl ts -verify -in response.tsr -queryfile request.tsq \
  -CAfile ~/.config/demo-cfssl/ca.pem
```

### Python with rfc3161ng

```python
from rfc3161ng import RemoteTimestamper

# Connect to TSA
rt = RemoteTimestamper('http://localhost:8080/tsa')

# Get timestamp
data = b"Document content to timestamp"
tsr = rt.timestamp(data=data)

# Verify
rt.check(tsr, data=data)
```

### Integration with tsa_sign.sh

Modify the `TSA_SERVERS` array in `tsa_sign.sh` to use your local TSA:

```bash
TSA_SERVERS=(
    "http://localhost:8080/tsa"      # Local mytsa server
    "http://freetsa.org/tsr"         # Fallback
    "http://timestamp.sectigo.com"   # Fallback
)
```

Then use `tsa_sign.sh` as normal:

```bash
./tsa_sign.sh --p12 email.p12 document.pdf
```

## Docker Deployment

### Build and Run

```bash
cd mytsa

# Build image
docker build -t mytsa:latest .

# Run with docker-compose
docker-compose up -d

# Check logs
docker logs mytsa-server

# Check health
curl http://localhost:8080/health
```

### Environment Variables in Docker

Edit `docker-compose.yaml` to customize:

```yaml
environment:
  - TSA_POLICY_OID=1.2.3.4.5
  - TSA_ACCURACY_SECONDS=5
```

## Troubleshooting

### Server won't start

**Error**: `TSA certificate not found`

**Solution**: Run `steps.sh` to generate TSA certificates:

```bash
cd /path/to/ca-n-certs
./steps.sh
```

The script includes a `step_tsa "MyTSA"` call that generates all required files.

### Certificate verification fails

**Error**: Timestamp verification fails with CA error

**Solution**: Make sure you're using the correct CA bundle:

```bash
openssl ts -verify -in response.tsr -queryfile request.tsq \
  -CAfile ~/.config/demo-cfssl/ca.pem
```

### Serial number file issues

**Error**: Failed to read/write serial number

**Solution**: Check permissions and ensure directory exists:

```bash
mkdir -p ~/.config/demo-cfssl/tsa/mytsa
echo "1000" > ~/.config/demo-cfssl/tsa/mytsa/tsaserial.txt
chmod 644 ~/.config/demo-cfssl/tsa/mytsa/tsaserial.txt
```

### Invalid Content-Type

**Error**: HTTP 415 Unsupported Media Type

**Solution**: Ensure you're sending the correct Content-Type header:

```bash
curl -H "Content-Type: application/timestamp-query" \
  --data-binary @request.tsq http://localhost:8080/tsa
```

## RFC 3161 Compliance

This implementation follows:

- **RFC 3161**: Time-Stamp Protocol (TSP)
- **RFC 5035**: Enhanced Security Services (ESS) Update (for `signingCertificateV2`)
- **RFC 3852**: Cryptographic Message Syntax (CMS)

Features:

- ✅ SHA-256 and SHA-384 message imprint algorithms
- ✅ Nonce support for replay prevention
- ✅ Accuracy specification (configurable, default 1 second)
- ✅ `signingCertificateV2` attribute
- ✅ Proper status codes (granted, rejection, waiting, etc.)
- ✅ Error responses per RFC 3161

## Security Considerations

### Production Deployment

For production use, consider:

1. **HSM/KMS Integration**: Store private keys in Hardware Security Module or Key Management Service
2. **Key Rotation**: Implement regular key rotation policy
3. **Audit Logging**: Enable comprehensive audit logs for all timestamp issuance
4. **Rate Limiting**: Add rate limiting to prevent abuse
5. **HTTPS**: Deploy behind reverse proxy with TLS (nginx, Caddy, Traefik)
6. **Monitoring**: Monitor serial number file, certificate expiration, and server health
7. **Backup**: Regular backup of serial number file and audit logs

### Key Protection

Current setup stores private keys as files. For production:

```bash
# Restrict key permissions
chmod 600 ~/.config/demo-cfssl/tsa/mytsa/key.pem

# Or use encrypted keys
openssl ec -aes256 -in key.pem -out key-encrypted.pem
export TSA_KEY_PASSWORD="your-secure-password"
```

### Policy OID

Use your organization's OID for the policy:

```bash
export TSA_POLICY_OID="1.3.6.1.4.1.YOUR_ORG.YOUR_POLICY"
```

Register your policy OID and publish a Certificate Policy (CP) or Certification Practice Statement (CPS).

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ POST /tsa (TSQ)
       ↓
┌─────────────────────────────────────┐
│         FastAPI Server              │
│  ┌───────────────────────────────┐  │
│  │  TimeStampAuthority           │  │
│  │  - Parse TSQ                  │  │
│  │  - Validate message imprint   │  │
│  │  - Build TSTInfo              │  │
│  │  - Create CMS SignedData      │  │
│  │  - Build TSR                  │  │
│  └───────────────────────────────┘  │
│         ↓                           │
│  ┌───────────────────────────────┐  │
│  │  Config (env vars)            │  │
│  │  Utils (serial, cert loading) │  │
│  └───────────────────────────────┘  │
└──────┬──────────────────────────────┘
       │
       ↓
┌──────────────────────────┐
│  File System             │
│  - TSA Certificate       │
│  - Private Key           │
│  - Serial Number File    │
└──────────────────────────┘
```

## Development

### Running Tests

```bash
# Unit tests (TODO)
pytest tests/

# Integration test
./test_tsa.sh

# Example workflow
./example_workflow.sh
```

### Code Structure

```
mytsa/
├── mytsa/
│   ├── __init__.py       # Package initialization
│   ├── __main__.py       # CLI entry point
│   ├── config.py         # Configuration management
│   ├── core.py           # TSA core logic (RFC 3161)
│   └── utils.py          # Utility functions
├── main.py               # FastAPI application
├── requirements.txt      # Dependencies
├── pyproject.toml        # Project metadata
├── start.sh              # Development server launcher
├── test_tsa.sh           # Test script
├── example_workflow.sh   # Example workflow
├── Dockerfile            # Container image
└── docker-compose.yaml   # Container orchestration
```

## License

This project follows the same license as the parent `ca-n-certs` project.

## Contributing

Contributions welcome! Please ensure:

1. TSA certificate requirements are preserved (critical `timeStamping` EKU)
2. RFC 3161 compliance is maintained
3. Tests pass
4. Documentation is updated

## Related Projects

- **OCSP Responder**: `ocsp/` directory - OCSP responder implementation
- **PDF Signer**: `pdf-signer/` directory - PDF signing with TSA support
- **CA Management**: `steps.sh` - Certificate authority management

## References

- [RFC 3161](https://tools.ietf.org/html/rfc3161) - Time-Stamp Protocol (TSP)
- [RFC 5035](https://tools.ietf.org/html/rfc5035) - Enhanced Security Services (ESS)
- [RFC 3852](https://tools.ietf.org/html/rfc3852) - Cryptographic Message Syntax (CMS)
- [CA/Browser Forum](https://cabforum.org/) - Industry standards
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [asn1crypto Documentation](https://github.com/wbond/asn1crypto)

## Support

For issues, questions, or contributions, please refer to the main project repository.

---

**Version**: 0.1.0  
**Last Updated**: November 2024
