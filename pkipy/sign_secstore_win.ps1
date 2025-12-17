# This script should be run as
# powershell -ExecutionPolicy Bypass -File sign_win.ps1
# copy your
# - pki store : ~/.config/demo-cfssl/codesign/mycodesign/codesign.p12
# - script    : test-script.ps1
#
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
        Where-Object { $_.Subject -like "*MyCodeSign*" }

$cert

$scriptPath = "test-script.ps1"
$timestamp  = "http://timestamp.digicert.com"

Set-AuthenticodeSignature `
    -FilePath $scriptPath `
    -Certificate $cert `
    -TimestampServer $timestamp