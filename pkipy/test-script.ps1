# Test PowerShell Script for Signing
# This is a simple script to test Authenticode signing

param(
    [string]$Name = "World"
)

Write-Host "Hello, $Name!"
Write-Host "This script has been signed with Authenticode."
Write-Host "Current time: $(Get-Date)"

# Example function
function Test-Signing {
    Write-Host "Testing digital signature functionality..."
    $sig = Get-AuthenticodeSignature $PSCommandPath
    
    if ($sig.Status -eq "Valid") {
        Write-Host "✓ Signature is VALID" -ForegroundColor Green
        Write-Host "  Signer: $($sig.SignerCertificate.Subject)"
        if ($sig.TimeStamperCertificate) {
            Write-Host "  Timestamp: $($sig.TimeStamperCertificate.Subject)" -ForegroundColor Cyan
        }
    } else {
        Write-Host "✗ Signature status: $($sig.Status)" -ForegroundColor Red
    }
}

# Run the test if called directly
Test-Signing

