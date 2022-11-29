#!/bin/bash

: ${PORT:=20443}

# haproxy.cfg
# localhost-server-haproxy.pem
# wss://localhost:20443/ws_wsext/
docker kill haproxy
docker run -it --rm \
    --name haproxy \
    -p 127.0.0.1:${PORT}:${PORT} \
    -v $PWD/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
    -v $HOME/.config/demo-ssl:/certs:ro \
    haproxy