<#
.SYNOPSIS
    Test script to verify that auto-loading protection is working correctly.

.DESCRIPTION
    This script tests the PSVirtualEnv auto-loading protection by:
    1. Creating a test environment
    2. Activating it
    3. Triggering PowerShell auto-loading
    4. Verifying that PSModulePath remains protected

.EXAMPLE
    .\Test-AutoLoadingProtection.ps1
#>

function Test-AutoLoadingProtection {
    [CmdletBinding()]
    param()
    
    Write-Host "Testing PSVirtualEnv Auto-Loading Protection" -ForegroundColor Yellow
    Write-Host "=" * 50 -ForegroundColor Yellow
    
    try {
        # Create a test environment
        $testEnvName = "AutoLoadTest_$(Get-Random)"
        Write-Host "Creating test environment: $testEnvName" -ForegroundColor Green
        New-PSVirtualEnv -Name $testEnvName -Force
        
        # Activate the environment
        Write-Host "Activating environment..." -ForegroundColor Green
        Activate-PSVirtualEnv -Name $testEnvName
        
        # Store the protected path
        $protectedPath = $env:PSModulePath
        Write-Host "Protected PSModulePath: $protectedPath" -ForegroundColor Cyan
        
        # Test 1: Manual Import-Module
        Write-Host "`nTest 1: Manual Import-Module" -ForegroundColor Yellow
        $pathBeforeImport = $env:PSModulePath
        Import-Module Microsoft.PowerShell.Management -Force
        $pathAfterImport = $env:PSModulePath
        
        if ($pathBeforeImport -eq $pathAfterImport) {
            Write-Host "✓ Manual Import-Module protection: PASSED" -ForegroundColor Green
        } else {
            Write-Host "✗ Manual Import-Module protection: FAILED" -ForegroundColor Red
            Write-Host "  Before: $pathBeforeImport" -ForegroundColor Red
            Write-Host "  After:  $pathAfterImport" -ForegroundColor Red
        }
        
        # Test 2: Auto-loading trigger
        Write-Host "`nTest 2: Auto-loading trigger (Get-Process)" -ForegroundColor Yellow
        $pathBeforeAuto = $env:PSModulePath
        
        # Remove the Management module to force auto-loading
        Remove-Module Microsoft.PowerShell.Management -Force -ErrorAction SilentlyContinue
        
        # This should trigger auto-loading
        Get-Process | Select-Object -First 1 | Out-Null
        
        # Wait a moment for protection to kick in
        Start-Sleep -Milliseconds 200
        
        $pathAfterAuto = $env:PSModulePath
        
        if ($pathBeforeAuto -eq $pathAfterAuto) {
            Write-Host "✓ Auto-loading protection: PASSED" -ForegroundColor Green
        } else {
            Write-Host "✗ Auto-loading protection: FAILED" -ForegroundColor Red
            Write-Host "  Before: $pathBeforeAuto" -ForegroundColor Red
            Write-Host "  After:  $pathAfterAuto" -ForegroundColor Red
        }
        
        # Test 3: Protection status
        Write-Host "`nTest 3: Protection status" -ForegroundColor Yellow
        if (Test-PSModulePathProtection) {
            Write-Host "✓ Protection is active: PASSED" -ForegroundColor Green
        } else {
            Write-Host "✗ Protection is not active: FAILED" -ForegroundColor Red
        }
        
        # Test 4: Current path matches protected path
        Write-Host "`nTest 4: Path integrity" -ForegroundColor Yellow
        $currentPath = $env:PSModulePath
        $expectedPath = Get-ProtectedPSModulePath
        
        if ($currentPath -eq $expectedPath) {
            Write-Host "✓ Path integrity maintained: PASSED" -ForegroundColor Green
        } else {
            Write-Host "✗ Path integrity compromised: FAILED" -ForegroundColor Red
            Write-Host "  Current:  $currentPath" -ForegroundColor Red
            Write-Host "  Expected: $expectedPath" -ForegroundColor Red
        }
        
        Write-Host "`nProtection test completed!" -ForegroundColor Yellow
        
    } finally {
        # Clean up
        Write-Host "`nCleaning up test environment..." -ForegroundColor Green
        Deactivate-PSVirtualEnv -ErrorAction SilentlyContinue
        if ($testEnvName) {
            Remove-PSVirtualEnv -Name $testEnvName -Force -ErrorAction SilentlyContinue
        }
    }
}

# Run the test if this script is executed directly
if ($MyInvocation.InvocationName -ne '.') {
    Test-AutoLoadingProtection
}