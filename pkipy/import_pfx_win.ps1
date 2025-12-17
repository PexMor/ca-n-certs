# $pwd = ConvertTo-SecureString -String "" -AsPlainText -Force
$pwd = Read-Host "PFX password" -AsSecureString

Import-PfxCertificate `
    -FilePath "codesign.p12" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -Password $pwd