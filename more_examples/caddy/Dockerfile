FROM caddy:2.8-alpine

# Copy Caddyfile
COPY Caddyfile /etc/caddy/Caddyfile

# Create a simple HTML directory
RUN mkdir -p /srv/www

# Create simple index page
RUN echo '<html><head><title>Caddy Demo</title></head><body><h1>Hello from Caddy!</h1><p>This is the standard TLS endpoint.</p><p>Try <a href="/client">/client</a> for mTLS protected endpoint.</p></body></html>' > /srv/www/index.html

# Create client-only page
RUN echo '<html><head><title>Client Cert Required</title></head><body><h1>Success!</h1><p>You have successfully authenticated with a client certificate.</p><p>Certificate Subject: {http.request.tls.client.subject}</p></body></html>' > /srv/www/client.html

EXPOSE 8443

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

