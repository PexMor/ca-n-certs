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
