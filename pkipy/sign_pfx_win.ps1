# This script should be run as
# powershell -ExecutionPolicy Bypass -File sign_win.ps1
# copy your
# - pki store : ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
# - script    : test-script.ps1
#
$path = "codesign.p12"
$pwd  = ""

$flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    $path,
    $pwd,
    $flags
)

$cert  # to verify it loaded correctly

$scriptPath = "test-script.ps1"
$timestamp  = "http://timestamp.digicert.com"

Set-AuthenticodeSignature `
    -FilePath $scriptPath `
    -Certificate $cert `
    -TimestampServer $timestamp