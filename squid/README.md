# Configure Squid

- to use TLS with clients
- authenticate clients
- use a custom CA
- use a custom certificate
- inspect traffic

```bash
curl --proxy http://localhost:3128 httpbin.io/ip
```

```bash
# use the proxy with authentication without client-proxy TLS
curl --proxy http://username:pass@localhost:3128 httpbin.io/ip
# use the proxy with authentication with client-proxy TLS
curl --proxy-cacert ~/.config/squid/config/squid.crt -v  --proxy https://username:pass@localhost:3128 httpbin.io/ip
# use bump-ssl with authentication, ignore the certificate CA
curl -k -v --proxy http://username:pass@localhost:3129 https://httpbin.io/ip
# verify the certificate with the custom CA
curl --cacert ~/.config/squid/config/bumpca.crt -v  --proxy http://username:pass@localhost:3129 https://httpbin.io/ip
# aliases
alias pcurl='curl --proxy-cacert ~/.config/squid/config/squid.crt -v  --proxy https://username:pass@localhost:3128'
alias pcurl1='curl --proxy-cacert ~/.config/squid/config/squid.crt -v  --proxy https://u1:p1@localhost:3128'
alias pcurl2='curl --proxy-cacert ~/.config/squid/config/squid.crt -v  --proxy https://u2:p2@localhost:3128'
alias pcurl3='curl --proxy-cacert ~/.config/squid/config/squid.crt -v  --proxy https://u3:p3@localhost:3128'
```
