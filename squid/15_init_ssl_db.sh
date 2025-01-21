#!/bin/bash

BD=$HOME/.config/squid

docker rm squid_ssl_db
docker run -it \
    --name squid_ssl_db \
    --hostname squid_ssl_db \
    -e TZ=UTC \
    -v $BD/logs:/var/log/squid \
    -v $BD/data:/var/spool/squid \
    -v $BD/config:/etc/squid \
    --entrypoint /usr/lib/squid/security_file_certgen \
    mysquid \
    -c -s /var/spool/squid/ssl_db -M 20MB
