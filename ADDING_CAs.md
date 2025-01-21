# How to add custom CA to various systems

This document describes how to add custom CA X.509 certificate
(CA that is not distributed with a common trust stores)
into various systems or environments.

Some hints also at: [Charles: SSL Certificates](https://www.charlesproxy.com/documentation/using-charles/ssl-certificates/)

## Desktop OSes

This section is about how to add a custom CA to the trust store of the OS.

### Debian and Ubuntu

```bash
sudo cp myCA.pem /usr/local/share/ca-certificates/myCA.crt
sudo update-ca-certificates
```

### Fedora and Redhat (Rocklinux, Almati)

```bash
sudo cp myCA.pem /etc/pki/ca-trust/source/anchors/myCA.pem
sudo update-ca-trust
```

### MacOS

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain myCA.pem
```

### Windows

```powershell
certutil -addstore -f "ROOT" myCA.pem
```

### FreeBSD

```bash
sudo cp myCA.pem /usr/local/share/certs/myCA.pem
sudo c_rehash
```

## Mobile OSes

This section describes how the custom CA can be added to the trust store of the mobile OS.

### Android

Click on the link on <http://my.server.com/myCA.pem> and follow the instructions.
If the web server provides correct MIME type, the system will ask you to install the certificate.

### iOS

Click on the link on <http://my.server.com/myCA.pem> it should show a dialog stating:

1. `Website is trying to download a new configuration profile. Do you want to allow this?`
   Click `Allow` to download profile "myCA".
2. It then says `Profile Downloaded: Review the profile in Settings app if you want to install it.`
   Click `Close`
3. Go to `Settings` -> `Profile Downloaded` and install the profile (top right corner).
4. Enter the device passcode.
5. Click `Install` in the next dialog.

## Browsers

How add CA certificate to the browser.

### Firefox

1. Open the Firefox browser.
2. Click on the menu button (three horizontal lines) in the upper right corner.
3. Click on `Options`.
4. Click on `Privacy & Security`.
5. Scroll down to the "Certificates" section.
6. Click on `View Certificates`.
7. Click on `Authorities`.
8. Click on `Import`.
9. Select the CA certificate file.
10. Click on `Open`.
11. Check the `Trust this CA to identify websites` checkbox.
12. Click on `OK`.

### Chrome and Chromium based

Chrome and Chromium use the system trust store, so you have to add the CA to the system trust store.

## Command line tools

This section describes how to add the custom CA to the trust store of the command line tools.

### Curl

```bash
curl --cacert myCA.pem https://my.server.com
```

### Java

```bash
sudo keytool -import -trustcacerts -alias myCA -file myCA.pem -keystore $JAVA_HOME/jre/lib/security/cacerts
```

### Python (incl.Conda)

The most common package that provides the CA bundle (collection of trusted CA certs)
is the [certify@PyPi](https://pypi.org/project/certifi/)

Python packages: `.../site-packages/certifi/cacert.pem` or Unix: `find / -name cacert.pem` or MacOS: `mdfind -name cacert.pem`

```python
import certifi
certifi.where()
```

```bash
pip install certifi
python -m certifi
```

> **Trick with system CA store**

- <https://pypi.org/project/certifi-system-store/>
- <https://pypi.org/project/pip-system-certs/>

```bash
SSL_CERT_FILE=/System/Library/OpenSSL/cert.pem
REQUESTS_CA_BUNDLE=/System/Library/OpenSSL/cert.pem
conda config --set ssl_verify /path/to/converted/certificate.pem
```

**.condarc**:

```yaml
channels:
  - defaults
#ssl_verify: C:\Users\ravikumk\certs\ca.crt

ssl_verify: false

# Show channel URLs when displaying what is going to be downloaded and
# in 'conda list'. The default is False.
show_channel_urls: True
allow_other_channels: True
```

```bash
conda update conda --insecure
conda update openssl pyopenssl ca-certificates certifi --insecure
```

**Do not DO this** ... however:

```bash
SSL_NO_VERIFY=1
conda config --set ssl_verify false
```

If you have `DER` (binary, `.crt`) form of cert you have to convert it into `PEM`

Using `openssl` (<https://wiki.openssl.org/index.php/Binaries>)

```bash
openssl x509 -in source.crt -inform der -out dest.pem -outform pem
```

- online: <https://www.sslshopper.com/ssl-converter.html>
- python: <https://pythontic.com/ssl/ssl-module/der_cert_to_pem_cert>
- gnutls: `certtool --certificate-info --infile cert.der --inder --outfile cert.pem`

Test:

```bash
openssl s_client -connect www.google.com:443 -servername www.google.com -showcerts -crlf
```

that among other output yields (last cert it the one closest to the root CA, should be issued by the "root CA"):

```text
 2 s:/C=US/O=Google Trust Services LLC/CN=GTS Root R1
   i:/C=BE/O=GlobalSign nv-sa/OU=Root CA/CN=GlobalSign Root CA
-----BEGIN CERTIFICATE-----
MIIFYjCCBEqgAwIBAgIQd70NbNs2+RrqIQ/E8FjTDTANBgkqhkiG9w0BAQsFADBX
MQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEQMA4GA1UE
CxMHUm9vdCBDQTEbMBkGA1UEAxMSR2xvYmFsU2lnbiBSb290IENBMB4XDTIwMDYx
OTAwMDA0MloXDTI4MDEyODAwMDA0MlowRzELMAkGA1UEBhMCVVMxIjAgBgNVBAoT
GUdvb2dsZSBUcnVzdCBTZXJ2aWNlcyBMTEMxFDASBgNVBAMTC0dUUyBSb290IFIx
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAthECix7joXebO9y/lD63
ladAPKH9gvl9MgaCcfb2jH/76Nu8ai6Xl6OMS/kr9rH5zoQdsfnFl97vufKj6bwS
iV6nqlKr+CMny6SxnGPb15l+8Ape62im9MZaRw1NEDPjTrETo8gYbEvs/AmQ351k
KSUjB6G00j0uYODP0gmHu81I8E3CwnqIiru6z1kZ1q+PsAewnjHxgsHA3y6mbWwZ
DrXYfiYaRQM9sHmklCitD38m5agI/pboPGiUU+6DOogrFZYJsuB6jC511pzrp1Zk
j5ZPaK49l8KEj8C8QMALXL32h7M1bKwYUH+E4EzNktMg6TO8UpmvMrUpsyUqtEj5
cuHKZPfmghCN6J3Cioj6OGaK/GP5Afl4/Xtcd/p2h/rs37EOeZVXtL0m79YB0esW
CruOC7XFxYpVq9Os6pFLKcwZpDIlTirxZUTQAs6qzkm06p98g7BAe+dDq6dso499
iYH6TKX/1Y7DzkvgtdizjkXPdsDtQCv9Uw+wp9U7DbGKogPeMa3Md+pvez7W35Ei
Eua++tgy/BBjFFFy3l3WFpO9KWgz7zpm7AeKJt8T11dleCfeXkkUAKIAf5qoIbap
sZWwpbkNFhHax2xIPEDgfg1azVY80ZcFuctL7TlLnMQ/0lUTbiSw1nH69MG6zO0b
9f6BQdgAmD06yK56mDcYBZUCAwEAAaOCATgwggE0MA4GA1UdDwEB/wQEAwIBhjAP
BgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTkrysmcRorSCeFL1JmLO/wiRNxPjAf
BgNVHSMEGDAWgBRge2YaRQ2XyolQL30EzTSo//z9SzBgBggrBgEFBQcBAQRUMFIw
JQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnBraS5nb29nL2dzcjEwKQYIKwYBBQUH
MAKGHWh0dHA6Ly9wa2kuZ29vZy9nc3IxL2dzcjEuY3J0MDIGA1UdHwQrMCkwJ6Al
oCOGIWh0dHA6Ly9jcmwucGtpLmdvb2cvZ3NyMS9nc3IxLmNybDA7BgNVHSAENDAy
MAgGBmeBDAECATAIBgZngQwBAgIwDQYLKwYBBAHWeQIFAwIwDQYLKwYBBAHWeQIF
AwMwDQYJKoZIhvcNAQELBQADggEBADSkHrEoo9C0dhemMXoh6dFSPsjbdBZBiLg9
NR3t5P+T4Vxfq7vqfM/b5A3Ri1fyJm9bvhdGaJQ3b2t6yMAYN/olUazsaL+yyEn9
WprKASOshIArAoyZl+tJaox118fessmXn1hIVw41oeQa1v1vg4Fv74zPl6/AhSrw
9U5pCZEt4Wi4wStz6dTZ/CLANx8LZh1J7QJVj2fhMtfTJr9w4z30Z209fOU0iOMy
+qduBmpvvYuR7hZL6Dupszfnw0Skfths18dG9ZKb59UhvmaSGZRVbNQpsg3BZlvi
d0lIKO2d1xozclOzgjXPYovJJIultzkMu34qQb9Sz/yilrbCgj8=
-----END CERTIFICATE-----
```
