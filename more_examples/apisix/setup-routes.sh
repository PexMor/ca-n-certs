#!/bin/bash
#
# Setup APISIX routes via Admin API
#

set -e

ADMIN_API="http://localhost:9180/apisix/admin"
ADMIN_KEY="admin-key-for-demo"
BD="${DEMO_CFSSL_DIR:-$HOME/.config/demo-cfssl}"

echo "Waiting for APISIX to be ready..."
sleep 5

# Read certificates into variables with proper escaping
CERT_CONTENT=$(cat "${BD}/hosts/localhost/bundle-3.pem" | sed 's/$/\\n/' | tr -d '\n')
KEY_CONTENT=$(cat "${BD}/hosts/localhost/key.pem" | sed 's/$/\\n/' | tr -d '\n')
CA_CONTENT=$(cat "${BD}/ca-bundle-myca.pem" | sed 's/$/\\n/' | tr -d '\n')

# Create SSL for port 9443 (standard TLS)
echo "Creating SSL certificate for port 9443 (standard TLS)..."
curl -s -X PUT "${ADMIN_API}/ssls/1" \
  -H "X-API-KEY: ${ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"cert\": \"${CERT_CONTENT}\",
    \"key\": \"${KEY_CONTENT}\",
    \"snis\": [\"localhost\"]
  }" | jq '.'

echo ""
echo "Creating SSL certificate for port 9444 (mTLS)..."
# Create SSL for port 9444 (mTLS)
curl -s -X PUT "${ADMIN_API}/ssls/2" \
  -H "X-API-KEY: ${ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"cert\": \"${CERT_CONTENT}\",
    \"key\": \"${KEY_CONTENT}\",
    \"client\": {
      \"ca\": \"${CA_CONTENT}\",
      \"depth\": 2
    },
    \"snis\": [\"localhost\"]
  }" | jq '.'

echo ""
echo "Creating upstream for static files..."
# Create upstream for serving static files
curl -s -X PUT "${ADMIN_API}/upstreams/1" \
  -H "X-API-KEY: ${ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "roundrobin",
    "nodes": {
      "127.0.0.1:80": 1
    }
  }' | jq '.'

echo ""
echo "Creating route for standard TLS (port 9443)..."
# Route for standard TLS endpoint
HTML_INDEX='<html><head><title>APISIX TLS Demo</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f0f0f0}.container{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}h1{color:#e8433e}a{color:#e8433e}</style></head><body><div class=\"container\"><h1>Hello from Apache APISIX!</h1><p>This is the standard TLS endpoint (port 9443).</p><p>Try <a href=\"https://localhost:9444/\">https://localhost:9444/</a> for mTLS protected endpoint.</p><p><a href=\"/health\">Health check</a></p></div></body></html>'

curl -s -X PUT "${ADMIN_API}/routes/1" \
  -H "X-API-KEY: ${ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/*",
    "host": "localhost",
    "vars": [["server_port", "==", 9443]],
    "plugins": {
      "response-rewrite": {
        "body": "'"${HTML_INDEX}"'",
        "headers": {
          "Content-Type": "text/html; charset=utf-8"
        }
      }
    }
  }' | jq -c '.key'

echo ""
echo "Creating route for mTLS (port 9444)..."
# Route for mTLS endpoint
HTML_MTLS='<html><head><title>APISIX mTLS Success</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f0f0f0}.container{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}h1{color:#e8433e}.info{background:#e8f4f8;padding:15px;border-radius:4px;margin:20px 0}.label{font-weight:bold;color:#333}.value{color:#555;margin-left:10px}</style></head><body><div class=\"container\"><h1>✓ Client Certificate Authentication Success!</h1><p>You have successfully authenticated using your client certificate via APISIX.</p><div class=\"info\"><p><span class=\"label\">Common Name:</span><span class=\"value\">Verified via mTLS</span></p><p><span class=\"label\">Gateway:</span><span class=\"value\">Apache APISIX</span></p></div><p><a href=\"https://localhost:9443/\">← Back to standard TLS endpoint</a></p></div></body></html>'

curl -s -X PUT "${ADMIN_API}/routes/2" \
  -H "X-API-KEY: ${ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/*",
    "host": "localhost",
    "vars": [["server_port", "==", 9444]],
    "plugins": {
      "response-rewrite": {
        "body": "'"${HTML_MTLS}"'",
        "headers": {
          "Content-Type": "text/html; charset=utf-8"
        }
      }
    }
  }' | jq -c '.key'

echo ""
echo "Creating health check routes..."
# Health check for port 9443
curl -s -X PUT "${ADMIN_API}/routes/3" \
  -H "X-API-KEY: ${ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/health",
    "host": "localhost",
    "vars": [["server_port", "==", 9443]],
    "plugins": {
      "response-rewrite": {
        "body": "OK\n",
        "headers": {
          "Content-Type": "text/plain"
        }
      }
    }
  }' | jq -c '.key'

# Health check for port 9444
curl -s -X PUT "${ADMIN_API}/routes/4" \
  -H "X-API-KEY: ${ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/health",
    "host": "localhost",
    "vars": [["server_port", "==", 9444]],
    "plugins": {
      "response-rewrite": {
        "body": "OK - mTLS Active\n",
        "headers": {
          "Content-Type": "text/plain"
        }
      }
    }
  }' | jq -c '.key'

echo ""
echo "✓ Routes configured successfully!"

