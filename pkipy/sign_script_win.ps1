<#
.SYNOPSIS
    Signs a PowerShell script using Set-AuthenticodeSignature
    
.DESCRIPTION
    This script signs a PowerShell script file using a certificate from the Windows
    certificate store. Use this when you need a properly signed script, as the
    PowerShell SIP uses a proprietary hash computation that cannot be replicated
    outside of Windows.
    
.PARAMETER ScriptPath
    Path to the script file to sign
    
.PARAMETER CertSubject
    Certificate subject to search for (e.g., "CN=MyCodeSign")
    
.PARAMETER OutputPath
    Optional output path. If not specified, signs the file in place.
    
.EXAMPLE
    .\sign_script_win.ps1 -ScriptPath Z:\myscript.ps1 -CertSubject "CN=MyCodeSign"
    
.EXAMPLE
    .\sign_script_win.ps1 -ScriptPath Z:\myscript.ps1 -CertSubject "MyCodeSign" -OutputPath Z:\signed.ps1
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,
    
    [Parameter(Mandatory=$false)]
    [string]$CertSubject = "CN=MyCodeSign",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ""
)

# Find the certificate
$cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | 
    Where-Object { $_.Subject -like "*$CertSubject*" } | 
    Select-Object -First 1

if (-not $cert) {
    Write-Error "No code signing certificate found matching: $CertSubject"
    Write-Host "Available code signing certificates:"
    Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | ForEach-Object {
        Write-Host "  - $($_.Subject)"
    }
    exit 1
}

Write-Host "Using certificate: $($cert.Subject)"
Write-Host "Thumbprint: $($cert.Thumbprint)"

# If OutputPath specified, copy first
if ($OutputPath -ne "") {
    Copy-Item -Path $ScriptPath -Destination $OutputPath -Force
    $TargetPath = $OutputPath
} else {
    $TargetPath = $ScriptPath
}

# Sign the script
$result = Set-AuthenticodeSignature -FilePath $TargetPath -Certificate $cert

if ($result.Status -eq "Valid") {
    Write-Host "`nSigning successful!" -ForegroundColor Green
    Write-Host "Signed file: $TargetPath"
    Write-Host "Status: $($result.Status)"
} else {
    Write-Error "Signing failed: $($result.StatusMessage)"
    exit 1
}

# Verify
$verify = Get-AuthenticodeSignature -FilePath $TargetPath
Write-Host "`nVerification:"
Write-Host "  Status: $($verify.Status)"
Write-Host "  Message: $($verify.StatusMessage)"

