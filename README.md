# Demo cfssl

An example how to use cfssl

The key path is `~/.config/demo-cfssl` at that place all the files are stored:

CA, ICA and server DN.O: `000 Special Org`

Other components of the X.509 DN (distingushed name is in `*.json`)

| file name                    | purpose - description                       |
| ---------------------------- | ------------------------------------------- |
| ca-bundle.pem                | root CA + intermediate CA certs             |
| ca-key.pem                   | private key for root CA                     |
| ca.csr                       | CA signing request                          |
| ca.pem                       | root CA cert                                |
| dhparam.pem                  | DH parameters used by TLS server            |
| ica-key.pem                  | intermediate CA cert                        |
| ica-self.pem                 | self-signed interediate CA cert             |
| ica.csr                      | intermediate CA signing requests            |
| ica.pem                      | root CA signed intermediate CA certificate  |
| localhost-server-bundle.pem  | server cert + ca-bundle                     |
| localhost-server-haproxy.pem | server bundle + private key for server cert |
| localhost-server-key.pem     | server private key                          |
| localhost-server.csr         | server cert signign request                 |
| localhost-server.pem         | server cert alone                           |

## Things to tweak

This line in `./mkCert.sh` creates the actual host certificate:

```bash
# ...
mkCert 03_host.json $C_TYPE $C_FN
# ...
```

parameters:

- `C_TYPE=server` ref. [profiles.json](profiles.json)
- `C_FN` is just a filename.

You should also tweak `03_host.json` either via

```bash
jq . 03_host.json | jq '.names[0].ST="Some" | .hosts=["super.name.lan"]' >tmp-03_host.json
```

Also a thing to look at is the `profiles.json`...

This example runs `containerized` in particular `Dockerized`.

Platform binaries to be downloaded at [https://github.com/cloudflare/cfssl/releases](https://github.com/cloudflare/cfssl/releases):

- cfssl-bundle
- cfssl-certinfo
- cfssl-newkey
- cfssl-scan
- [cfssljson](https://github.com/cloudflare/cfssl#the-cfssljson-utility) - program, which takes the JSON output from the cfssl and multirootca programs and writes certificates, keys, CSRs, and bundles to disk
- [cfssl](https://github.com/cloudflare/cfssl#using-the-command-line-tool) - program, which is the canonical command line utility using the CFSSL packages
- [mkbundle](https://github.com/cloudflare/cfssl#the-mkbundle-utility) - program is used to build certificate pool bundles
- [multirootca](https://github.com/cloudflare/cfssl#the-multirootca) - program, which is a certificate authority server that can use multiple signing keys

...it is GO-Lang: `go get github.com/cloudflare/cfssl/cmd/...`

## Testing and deploying

**Firefox:** have independed certificate store (incl.RootCA).
**Chrome & Safari & Edge/Chrome** use the system cert store (incl.RootCA).

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

## HA Proxy test

This addition presents the use of generated CA's keys with `haproxy` in Docker container.

To test at first run the certificate creation as described above and the run `./demoHaproxy.sh`

## Do it on RaspberryPi

Head to releases: <https://github.com/cloudflare/cfssl/releases>

Select the latest build for `ARMv6` or `ARM64` if you are on RPi5 and later.

At the time of writing it was `cfssl_1.6.5_linux_armv6`

While revisiting the **one-click** solution I have found that for `day 2` operation perspective
it might be too fast for certain use-cases. For that reason I would elaborate a bit on steps
that you might find useful in case you do not need kind of **one-shot CA and server**.

The procedure is following:

1. generate **long term** CA certificate and key (like 10 years, do not forget **make note** in calendar!)
2. do the same for **long term** intermediate CA certificate (same as above)
3. generate **short term** certificate for what ever you need server, e-mail or even sub-CA (short period should be around 90 days - hint: **certbot - Let's Encrypt** policy)
