FROM nginx:1.27-alpine

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create HTML directory
RUN mkdir -p /usr/share/nginx/html

# Create index page
RUN echo '<html><head><title>Nginx TLS Demo</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f0f0f0}.container{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}h1{color:#009639}a{color:#009639}</style></head><body><div class="container"><h1>Hello from Nginx!</h1><p>This is the standard TLS endpoint (port 8443).</p><p>Try <a href="https://localhost:8444/">https://localhost:8444/</a> for mTLS protected endpoint.</p><p><a href="/health">Health check</a></p></div></body></html>' > /usr/share/nginx/html/index.html

# Create mTLS page
RUN echo '<html><head><title>Nginx mTLS Success</title><style>body{font-family:Arial,sans-serif;margin:40px;background:#f0f0f0}.container{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1)}h1{color:#009639}.info{background:#e8f4f8;padding:15px;border-radius:4px;margin:20px 0}.label{font-weight:bold;color:#333}.value{color:#555;margin-left:10px}</style></head><body><div class="container"><h1>✓ Client Certificate Authentication Success!</h1><p>You have successfully authenticated using your client certificate.</p><div class="info"><p><span class="label">Subject DN:</span><span class="value">$ssl_client_s_dn</span></p><p><span class="label">Issuer DN:</span><span class="value">$ssl_client_i_dn</span></p><p><span class="label">Serial:</span><span class="value">$ssl_client_serial</span></p><p><span class="label">Valid From:</span><span class="value">$ssl_client_v_start</span></p><p><span class="label">Valid Until:</span><span class="value">$ssl_client_v_end</span></p><p><span class="label">Verify:</span><span class="value">$ssl_client_verify</span></p></div><p><a href="https://localhost:8443/">← Back to standard TLS endpoint</a></p></div></body></html>' > /usr/share/nginx/html/mtls.html

# Create health check page
RUN echo 'OK' > /usr/share/nginx/html/health.html

EXPOSE 8443 8444

CMD ["nginx", "-g", "daemon off;"]

