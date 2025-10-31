# mytsa - Quick Start Guide

Get your RFC 3161 Time Stamp Authority server running in 5 minutes!

## Step 1: Generate TSA Certificate (2 minutes)

The TSA certificate requires a special `timeStamping` Extended Key Usage. Use the provided `steps.sh` script:

```bash
# From the project root directory
cd /path/to/ca-n-certs

# Run steps.sh (it includes step_tsa call)
./steps.sh
```

This creates:

- ✅ Root CA and Intermediate CA (if they don't exist)
- ✅ TSA certificate at `~/.config/demo-cfssl/tsa/mytsa/cert.pem`
- ✅ Private key at `~/.config/demo-cfssl/tsa/mytsa/key.pem`
- ✅ Certificate bundles
- ✅ Serial number file

**Verify the certificate has timeStamping EKU:**

```bash
openssl x509 -in ~/.config/demo-cfssl/tsa/mytsa/cert.pem -noout -text \
  | grep -A2 "Extended Key Usage"
```

You should see: `Time Stamping`

## Step 2: Install and Run (2 minutes)

### Option A: Using uv (recommended)

```bash
cd mytsa

# Install dependencies
uv sync

# Start server
./start.sh
```

### Option B: Using pip

```bash
cd mytsa

# Install dependencies
pip install -r requirements.txt

# Start server
./start.sh
```

### Option C: Using Docker

```bash
cd mytsa

# Build and start
docker-compose up -d

# Check logs
docker logs mytsa-server
```

The server will be running at `http://localhost:8080`

## Step 3: Test It! (1 minute)

### Quick Test

```bash
# From mytsa directory
./test_tsa.sh
```

This runs comprehensive tests including:

- Health check
- Certificate download
- Timestamp request/response
- Verification

### Manual Test with OpenSSL

```bash
# Create test data
echo "Hello, RFC 3161!" > test.txt

# Create timestamp request (TSQ)
openssl ts -query -data test.txt -sha256 -cert -out request.tsq

# Get timestamp from server (TSR)
curl -X POST \
  -H "Content-Type: application/timestamp-query" \
  --data-binary @request.tsq \
  http://localhost:8080/tsa \
  -o response.tsr

# Verify the timestamp
openssl ts -reply -in response.tsr -text

# Full verification with CA bundle
openssl ts -verify -in response.tsr -queryfile request.tsq \
  -CAfile ~/.config/demo-cfssl/ca.pem
```

**Success!** You should see: `Verification: OK`

## Next Steps

### Use with Existing Tools

**1. With tsa_sign.sh:**

Edit `tsa_sign.sh` and add your local TSA to the servers array:

```bash
TSA_SERVERS=(
    "http://localhost:8080/tsa"    # Your local TSA!
    "http://freetsa.org/tsr"
)
```

Then sign documents:

```bash
./tsa_sign.sh --p12 cert.p12 document.pdf
```

**2. With Python:**

```python
from rfc3161ng import RemoteTimestamper

rt = RemoteTimestamper('http://localhost:8080/tsa')
tsr = rt.timestamp(data=b"My document")
```

**3. With OpenSSL (command line):**

```bash
# One-liner to timestamp any file
openssl ts -query -data myfile.pdf -sha256 -out req.tsq && \
curl -H "Content-Type: application/timestamp-query" \
  --data-binary @req.tsq http://localhost:8080/tsa -o resp.tsr && \
openssl ts -reply -in resp.tsr -text
```

### API Endpoints

- `POST http://localhost:8080/tsa` - Get timestamp (RFC 3161)
- `GET http://localhost:8080/tsa/certs` - Download TSA cert chain
- `GET http://localhost:8080/health` - Health check
- `GET http://localhost:8080/` - API info

### Configuration

Override defaults with environment variables:

```bash
export TSA_POLICY_OID="1.2.3.4.5"
export TSA_ACCURACY_SECONDS=5
./start.sh
```

See [README.md](README.md) for all configuration options.

## Troubleshooting

### "TSA certificate not found"

**Solution**: Run `steps.sh` from the project root:

```bash
cd /path/to/ca-n-certs
./steps.sh
```

### "Verification failed"

**Solution**: Use the correct CA bundle:

```bash
openssl ts -verify -in response.tsr -queryfile request.tsq \
  -CAfile ~/.config/demo-cfssl/ca.pem
```

### Port 8080 already in use

**Solution**: Use a different port:

```bash
PORT=8081 ./start.sh
```

Or find and stop the process:

```bash
lsof -ti:8080 | xargs kill
```

## Example Workflow

Run the complete example workflow:

```bash
cd mytsa
./example_workflow.sh
```

This demonstrates:

- Certificate checking
- Server startup
- Multiple timestamp requests
- Verification
- Integration examples

## Documentation

- **Full README**: [README.md](README.md)
- **API Documentation**: http://localhost:8080/docs (when server is running)
- **RFC 3161**: https://tools.ietf.org/html/rfc3161

## Summary

You now have a working RFC 3161 Time Stamp Authority server! 🎉

```
Certificate Generated → Server Running → Tests Passed → Ready to Use!
```

For production deployment, see the **Security Considerations** section in [README.md](README.md).

---

**Need help?** Check [README.md](README.md) for detailed documentation and troubleshooting.
