#!/bin/bash

BD=$HOME/.config/squid
mkdir -p $BD/logs
mkdir -p $BD/data
mkdir -p $BD/config
touch $BD/config/squid.conf
touch $BD/config/snippet.conf

# if [ ! -f $BD/config/squid.conf ]; then
    echo "Copy config"
    cp squid.conf $BD/config/squid.conf
# fi
# if [ ! -f $BD/config/bump.key ]; then
    echo "-=[ squid own TLS certificate and key"
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -sha256 -keyout $BD/config/squid.key -out $BD/config/squid.crt -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
    echo "-=[ root CA certificate and key"
    openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 -sha256 -keyout $BD/config/bumpca.key -out $BD/config/bumpca.crt -subj "/C=US/ST=State/L=City/O=Organization/CN=MyRootCA" \
    -extensions v3_ca \
    -config <(printf "[ v3_ca ]\nkeyUsage = critical, digitalSignature, keyCertSign, cRLSign\nbasicConstraints = critical, CA:true\nsubjectKeyIdentifier = hash\nauthorityKeyIdentifier = keyid:always,issuer\n")
#fi

# exit
echo "127.0.0.1 squid" >> $BD/config/hosts

echo "---"
find $BD
echo "---"

docker rm squid
docker run -it \
    --rm \
    --name squid \
    --hostname squid \
    --add-host=squid:127.0.0.1 \
    `#--network container:squid_net` \
    -e TZ=UTC \
    -v $BD/logs:/var/log/squid \
    -v $BD/data:/var/spool/squid \
    -v $BD/config:/etc/squid \
    `#-v $BD/config/snippet.conf:/etc/squid/conf.d/snippet.conf` \
    -p 3128:3128 \
    -p 3129:3129 \
    mysquid
