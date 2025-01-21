FROM ubuntu/squid:edge

# install squid-openssl
RUN apt-get update && apt-get install -y squid-openssl && apt clean -y && rm -rf /var/lib/apt/lists/*
