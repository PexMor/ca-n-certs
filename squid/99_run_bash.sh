#!/bin/bash

BD=$HOME/.config/squid
docker rm squidsh
docker run -it \
    --name squidsh \
    --hostname squidsh \
    --add-host=squid:127.0.0.1 \
    --add-host=squidsh:127.0.0.1 \
    `#--network container:squid_net` \
    -e TZ=UTC \
    -v $BD/logs:/var/log/squid \
    -v $BD/data:/var/spool/squid \
    -v $BD/config:/etc/squid \
    `#-v $BD/config/snippet.conf:/etc/squid/conf.d/snippet.conf` \
    -p 3128:3128 \
    --entrypoint /bin/bash \
    mysquid
