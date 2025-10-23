FROM python:3.11-slim

LABEL maintainer="demo-cfssl"
LABEL description="OCSP Responder for demo-cfssl Certificate Authority"

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY main.py .

# Environment variables
ENV DEMO_CFSSL_DIR=/certs
ENV OCSP_HOST=0.0.0.0
ENV OCSP_PORT=8080

# Expose OCSP port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

# Run OCSP responder
CMD ["python", "main.py"]

