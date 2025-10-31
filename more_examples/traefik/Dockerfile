FROM traefik:v3.2

# Create directory for HTML content
USER root
RUN mkdir -p /var/www/html && chmod 755 /var/www/html

# Create HTML pages
RUN echo '<html><head><title>Traefik TLS Demo</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f0f0f0}.container{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}h1{color:#37ABC8}a{color:#37ABC8}</style></head><body><div class="container"><h1>Hello from Traefik!</h1><p>This is the standard TLS endpoint (port 8443).</p><p>Try <a href="https://localhost:8444/">https://localhost:8444/</a> for mTLS protected endpoint.</p><p><a href="/health">Health check</a></p></div></body></html>' > /var/www/html/index.html

RUN echo '<html><head><title>Traefik mTLS Success</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f0f0f0}.container{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}h1{color:#37ABC8}.info{background:#e8f4f8;padding:15px;border-radius:4px;margin:20px 0}.label{font-weight:bold;color:#333}.value{color:#555;margin-left:10px}</style></head><body><div class="container"><h1>✓ Client Certificate Authentication Success!</h1><p>You have successfully authenticated using your client certificate via Traefik.</p><div class="info"><p><span class="label">Common Name:</span><span class="value">Verified via mTLS</span></p><p><span class="label">Proxy:</span><span class="value">Traefik</span></p></div><p><a href="https://localhost:8443/">← Back to standard TLS endpoint</a></p></div></body></html>' > /var/www/html/mtls.html

RUN echo 'OK' > /var/www/html/health.txt

# Note: Running as root for simplicity in this demo
# In production, consider creating a non-root user

EXPOSE 8443 8444 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["traefik"]

