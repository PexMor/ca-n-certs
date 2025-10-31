FROM apache/apisix:3.11.0-debian

# The base image already has APISIX installed
# We just need to copy our configuration

USER root

# Create directory for HTML content
RUN mkdir -p /var/www/html

# Create simple HTML pages
RUN echo '<html><head><title>APISIX TLS Demo</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f0f0f0}.container{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}h1{color:#e8433e}a{color:#e8433e}</style></head><body><div class="container"><h1>Hello from Apache APISIX!</h1><p>This is the standard TLS endpoint (port 9443).</p><p>Try <a href="https://localhost:9444/">https://localhost:9444/</a> for mTLS protected endpoint.</p><p><a href="/health">Health check</a></p></div></body></html>' > /var/www/html/index.html

RUN echo '<html><head><title>APISIX mTLS Success</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f0f0f0}.container{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}h1{color:#e8433e}.info{background:#e8f4f8;padding:15px;border-radius:4px;margin:20px 0}.label{font-weight:bold;color:#333}.value{color:#555;margin-left:10px}</style></head><body><div class="container"><h1>✓ Client Certificate Authentication Success!</h1><p>You have successfully authenticated using your client certificate via APISIX.</p><div class="info"><p><span class="label">Common Name:</span><span class="value">Verified via mTLS</span></p><p><span class="label">Gateway:</span><span class="value">Apache APISIX</span></p></div><p><a href="https://localhost:9443/">← Back to standard TLS endpoint</a></p></div></body></html>' > /var/www/html/mtls.html

RUN echo 'OK' > /var/www/html/health.txt

USER apisix

EXPOSE 9443 9444 9180

CMD ["sh", "-c", "/usr/bin/apisix init && /usr/bin/apisix init_etcd && /usr/local/openresty/bin/openresty -p /usr/local/apisix -g 'daemon off;'"]

