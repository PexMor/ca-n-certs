# demo-cfssl

An example how to use cfssl

The key path is `~/.config/demo-cfssl`.

# Things to tweak

This line in `./mkCert.sh` creates the actual host certificate:

```bash
# ...
mkCert 03_host.json $C_TYPE $C_FN
# ...
```

parameters:

* `C_TYPE=server` ref. [profiles.json](profiles.json)
* `C_FN` is just a filename.

You should also tweak `03_host.json` either via

```bash
jq . 03_host.json | jq '.names[0].ST="Some" | .hosts=["super.name.lan"]' >tmp-03_host.json
```

Also a thing to look at is the `profiles.json`...

This example runs `containerized` in particular `Dockerized`.

Platform binaries to be downloaded at [https://github.com/cloudflare/cfssl/releases](https://github.com/cloudflare/cfssl/releases):

* cfssl-bundle
* cfssl-certinfo
* cfssl-newkey
* cfssl-scan
* [cfssljson](https://github.com/cloudflare/cfssl#the-cfssljson-utility) - program, which takes the JSON output from the cfssl and multirootca programs and writes certificates, keys, CSRs, and bundles to disk
* [cfssl](https://github.com/cloudflare/cfssl#using-the-command-line-tool) - program, which is the canonical command line utility using the CFSSL packages
* [mkbundle](https://github.com/cloudflare/cfssl#the-mkbundle-utility) - program is used to build certificate pool bundles
* [multirootca](https://github.com/cloudflare/cfssl#the-multirootca) - program, which is a certificate authority server that can use multiple signing keys

...it is GO-Lang: `go get github.com/cloudflare/cfssl/cmd/...`

## Testing and deploying

__Firefox:__ have independed certificate store (incl.RootCA).
__Chrome & Safari & Edge/Chrome__ use the system cert store (incl.RootCA).

```bash
export BP="$HOME/.config/demo-ssl"
# following does not work with `update-ca-certificates`
# export DST="/usr/share/ca-certificates/extra"
export DST="/usr/local/share/ca-certificates/extra"
sudo mkdir -p "$DST"
cat "$BP/ca.pem" | sudo tee "$DST/000ca.crt"
sudo update-ca-certificates
# sudo dpkg-reconfigure ca-certificates
```

check intermediate CA CERT w/explicit root CA CERT:

```bash
openssl verify -CAfile "$BP/ca.pem" -verbose "$BP/ica.pem"
```

check intermediate CA CERT w/system root CA CERT - verifies the deployment went well:

```bash
openssl verify -verbose "$BP/ica.pem"
```

> Note: in the following examples the parameter `-untrusted` is the actual and correct one, as the trustworthiness is verified by the root CA...

check host CERT w/explicit root CA:

```bash
openssl verify -verbose -CAfile "$BP/ca.pem" \
    -untrusted "$BP/ica.pem" "$BP/localhost-server.pem"
```

check host CERT w/system root CA:

```bash
openssl verify -verbose -untrusted "$BP/ica.pem" "$BP/localhost-server.pem"
```

> Note: cfssl does not support plug-in (USB, Bluetooth, NFC) PKCS#11 tokens :-(