# Dockerfile for mytsa - Pure-Python RFC 3161 Time Stamp Authority server

FROM python:3.13-slim

# Set working directory
WORKDIR /app

# Install dependencies first (better layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY mytsa/ mytsa/

# Create non-root user
RUN useradd -m -u 1000 -s /bin/bash mytsa && \
    chown -R mytsa:mytsa /app

# Switch to non-root user
USER mytsa

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Run the application
CMD ["uvicorn", "mytsa.app:app", "--host", "0.0.0.0", "--port", "8080"]

