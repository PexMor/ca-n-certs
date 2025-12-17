# Remove old MyCodeSign certificate and related CAs from Windows certificate store
# Run this BEFORE importing the new certificate chain with CSICA
#
# Why is this needed?
# The old MyCodeSign certificate was issued by the regular ICA which has EKUs:
#   ServerAuth, ClientAuth, SecureEmail (no codeSigning!)
# Windows validates the entire chain must permit codeSigning EKU.
# The new chain uses CSICA (Code Signing Intermediate CA) with codeSigning EKU.

Write-Host "=== Removing old MyCodeSign certificates ===" -ForegroundColor Cyan
Write-Host ""

# Find and remove MyCodeSign certificates from Personal store
$certs = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -like "*MyCodeSign*" }

if ($certs) {
    Write-Host "Found MyCodeSign certificate(s) in Personal store:" -ForegroundColor Yellow
    foreach ($cert in $certs) {
        Write-Host "  Subject: $($cert.Subject)"
        Write-Host "  Issuer: $($cert.Issuer)"
        Write-Host "  Thumbprint: $($cert.Thumbprint)"
        Write-Host "  Serial: $($cert.SerialNumber)"
        Write-Host ""
    }
    
    $confirm = Read-Host "Remove these certificates? (y/N)"
    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        foreach ($cert in $certs) {
            Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
            Write-Host "Removed: $($cert.Subject)" -ForegroundColor Green
        }
    } else {
        Write-Host "Skipped removal of MyCodeSign certificates" -ForegroundColor Gray
    }
} else {
    Write-Host "No MyCodeSign certificates found in Personal store" -ForegroundColor Gray
}

Write-Host ""

# Find and remove old Intermediate CA (the one WITHOUT codeSigning EKU)
$oldIcas = Get-ChildItem Cert:\CurrentUser\CA |
    Where-Object { $_.Subject -like "*000-AtHome-Intermediate-CA*" }

if ($oldIcas) {
    Write-Host "Found old Intermediate CA(s) in CA store:" -ForegroundColor Yellow
    foreach ($ica in $oldIcas) {
        $ekuList = $ica.EnhancedKeyUsageList | ForEach-Object { $_.FriendlyName }
        $hasCodeSigning = $ekuList -contains "Code Signing"
        
        Write-Host "  Subject: $($ica.Subject)"
        Write-Host "  Issuer: $($ica.Issuer)"
        Write-Host "  EKUs: $($ekuList -join ', ')"
        Write-Host "  Has CodeSigning EKU: $hasCodeSigning"
        Write-Host "  Thumbprint: $($ica.Thumbprint)"
        Write-Host ""
        
        if (-not $hasCodeSigning) {
            Write-Host "  *** This ICA does NOT have codeSigning EKU - should be removed ***" -ForegroundColor Red
        }
    }
    
    $confirm = Read-Host "Remove old Intermediate CA(s)? (y/N)"
    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        foreach ($ica in $oldIcas) {
            Remove-Item -Path "Cert:\CurrentUser\CA\$($ica.Thumbprint)" -Force
            Write-Host "Removed: $($ica.Subject)" -ForegroundColor Green
        }
    } else {
        Write-Host "Skipped removal of old Intermediate CA(s)" -ForegroundColor Gray
    }
} else {
    Write-Host "No old Intermediate CA found in CA store" -ForegroundColor Gray
}

Write-Host ""

# Check for Code Signing Intermediate CA (CSICA) - this should NOT be removed
$csicas = Get-ChildItem Cert:\CurrentUser\CA |
    Where-Object { $_.Subject -like "*000-AtHome-CodeSign-Intermediate-CA*" }

if ($csicas) {
    Write-Host "Found Code Signing Intermediate CA (CSICA) - keeping:" -ForegroundColor Green
    foreach ($csica in $csicas) {
        Write-Host "  Subject: $($csica.Subject)"
        Write-Host "  EKUs: $($csica.EnhancedKeyUsageList | ForEach-Object { $_.FriendlyName })"
    }
} else {
    Write-Host "Code Signing Intermediate CA (CSICA) not found - you need to import it" -ForegroundColor Yellow
    Write-Host "  Import-Certificate -FilePath csica-ca.pem -CertStoreLocation Cert:\CurrentUser\CA"
}

Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Import Root CA (if not already done):"
Write-Host "   Import-Certificate -FilePath ca.pem -CertStoreLocation Cert:\CurrentUser\Root"
Write-Host ""
Write-Host "2. Import Code Signing Intermediate CA (CSICA):"
Write-Host "   Import-Certificate -FilePath csica-ca.pem -CertStoreLocation Cert:\CurrentUser\CA"
Write-Host ""
Write-Host "3. Import new MyCodeSign certificate:"
Write-Host '   $pwd = Read-Host "PFX password" -AsSecureString'
Write-Host '   Import-PfxCertificate -FilePath codesign.p12 -CertStoreLocation Cert:\CurrentUser\My -Password $pwd'
Write-Host ""

