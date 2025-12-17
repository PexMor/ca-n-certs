$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
        Where-Object { $_.Subject -like "*MyCodeSign*" }

Write-Output "Subject: $($cert.Subject)"
Write-Output "HasPrivateKey: $($cert.HasPrivateKey)"
Write-Output "PublicKeyAlgorithm: $($cert.PublicKey.Oid.FriendlyName)"
Write-Output "EnhancedKeyUsage: $($cert.EnhancedKeyUsageList -join ', ')"
Write-Output "KeyUsage: $($cert.KeyUsage)"
Write-Output "NotBefore: $($cert.NotBefore)"
Write-Output "NotAfter: $($cert.NotAfter)"
Write-Output "Thumbprint: $($cert.Thumbprint)"
Write-Output "SerialNumber: $($cert.SerialNumber)"
Write-Output "Issuer: $($cert.Issuer)"
Write-Output "Extensions:"
$cert.Extensions | Format-Table -AutoSize

# Intermediate CA
Get-ChildItem Cert:\CurrentUser\CA |
  Where-Object { $_.Subject -like "*000-AtHome-Intermediate-CA*" } |
  Format-List Subject,Issuer,EnhancedKeyUsageList,Extensions

# Root CA
Get-ChildItem Cert:\CurrentUser\Root |
  Where-Object { $_.Subject -like "*AtHome-Root*" } |
  Format-List Subject,Issuer,EnhancedKeyUsageList,Extensions

# CSICA
Get-ChildItem Cert:\CurrentUser\CA |
  Where-Object { $_.Subject -like "*000-AtHome-Code-Signing-Intermediate-CA*" } |
  Format-List Subject,Issuer,EnhancedKeyUsageList,Extensions