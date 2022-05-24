#!/bin/bash

# based on:
# https://github.com/rob-blackbourn/ssl-certs
# and https://rob-blackbourn.medium.com/how-to-use-cfssl-to-create-self-signed-certificates-d55f76ba5781

BD="$HOME/.config/demo-ssl"

[ -d "$BD" ] || mkdir -p "$BD"
echo "Using BD: '$BD'"

function cfssl() {
    docker run -i --rm \
        --log-driver=none \
        -a stdin \
        -a stdout \
        -a stderr \
        -v $PWD:/cfg:ro \
        -v $BD:/workdir \
        cfssl/cfssl \
        "$@"
}

function cfssljson() {
    docker run -i --rm \
        --log-driver=none \
        -a stdin \
        -a stdout \
        -a stderr \
        -v $PWD:/cfg:ro \
        -v $BD:/workdir \
        --entrypoint cfssljson \
        cfssl/cfssl \
        "$@"
}

echo "Make Root CA..."
# the path on output is 
if [ ! -f "$BD/ca-key.pem" ]; then
    echo "Making new Root CA : ca-key.pem, etc."
    cfssl gencert -initca /cfg/00_ca.json | cfssljson -bare ca
else
    echo "Root CA exists"
fi
ls -l $BD/ca*.pem

echo "Making Intermediate CA..."
if [ ! -f "$BD/ica-key.pem" ]; then
    echo "Making new Intermediate CA : ica-key.pem, etc."
    cfssl gencert -initca /cfg/02_ica.json | cfssljson -bare ica
    mv $BD/ica.pem $BD/ica-self.pem
else
    echo "Intermediate CA exists"
fi
ls -l $BD/ica*.pem

if [ ! -f "$BD/ica.pem" ]; then
    echo "Sign the Intermediate CA"
    cfssl sign \
        -ca ca.pem \
        -ca-key ca-key.pem \
        -config /cfg/profiles.json \
        -profile intermediate_ca \
        ica.csr | cfssljson -bare ica
else
    echo "The Intermediate CA is already signed"
fi

function mkCert() {
    local CFG=$1
    local PROFILE=$2
    local FN=$3
    if [ ! -f $BD/${FN}-server-key.pem ]; then
        echo "Generating Server certificate"
        cfssl gencert \
            -ca ica.pem \
            -ca-key ica-key.pem \
            -config /cfg/profiles.json \
            -profile=${PROFILE} /cfg/$CFG | cfssljson -bare ${FN}-${PROFILE}
    else
        echo "Host certificate and key already exists"
    fi
    # concatenate the server, intermediate and root ca
    cat $BD/${FN}-${PROFILE}.pem $BD/ica.pem $BD/ca.pem >$BD/${FN}-${PROFILE}-bundle.pem
    # also create file suitable for haproxy
    cat $BD/${FN}-${PROFILE}-bundle.pem $BD/${FN}-${PROFILE}-key.pem >$BD/${FN}-${PROFILE}-haproxy.pem
}

cat $BD/ica.pem $BD/ca.pem >$BD/ca-bundle.pem

C_FN=localhost
C_TYPE=server
mkCert 03_host.json $C_TYPE $C_FN

[ -f $BD/dhparam.pem ] || openssl dhparam -out $BD/dhparam.pem 2048

echo "------------"
echo "Checking the Host certificate against the Intermediate CAs"
openssl verify -CAfile $BD/ca-bundle.pem -verbose $BD/${C_FN}-${C_TYPE}.pem
echo "Checking the Intermediate certificate against the Root CAs"
openssl verify -CAfile $BD/ca.pem -verbose $BD/ica.pem

echo "------------"
echo ":: Root CA cert"
openssl x509 -enddate -issuer -noout -in $BD/ca.pem
echo ":: Intermediate CA cert"
openssl x509 -enddate -issuer -noout -in $BD/ica.pem
for FN in localhost; do
    echo ":: Host $FN cert"
    openssl x509 -enddate -subject -issuer -noout -in $BD/${FN}-server.pem
done
