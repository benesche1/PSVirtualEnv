# Global variables to track path protection
$script:PathProtectionActive = $false
$script:ProtectedPSModulePath = $null
$script:PathCheckTimer = $null
$script:TemporaryPathBypass = $false
$script:BypassStartTime = $null
$script:SystemModulePaths = $null

function Initialize-SystemModulePaths {
    <#
    .SYNOPSIS
        Initializes and caches system module paths for smart protection.
    #>
    [CmdletBinding()]
    param()
    
    if ($script:SystemModulePaths) {
        return $script:SystemModulePaths
    }
    
    # Get essential system paths that should always be available
    $systemPaths = @()
    
    if ($PSVersionTable.PSEdition -eq 'Core') {
        if ($IsWindows) {
            $systemPaths += @(
                (Join-Path $env:ProgramFiles 'PowerShell\Modules'),
                (Join-Path $env:ProgramFiles 'PowerShell\7\Modules'),
                (Join-Path $env:windir 'system32\WindowsPowerShell\v1.0\Modules')
            )
        }
        else {
            $systemPaths += @(
                '/usr/local/share/powershell/Modules',
                '/opt/microsoft/powershell/7/Modules'
            )
        }
    }
    else {
        # Windows PowerShell
        $systemPaths += @(
            (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'),
            (Join-Path $env:windir 'system32\WindowsPowerShell\v1.0\Modules')
        )
        
        if (Test-Path ${env:ProgramFiles(x86)}) {
            $systemPaths += (Join-Path ${env:ProgramFiles(x86)} 'WindowsPowerShell\Modules')
        }
    }
    
    # Filter to only existing paths
    $script:SystemModulePaths = $systemPaths | Where-Object { Test-Path $_ }
    return $script:SystemModulePaths
}

function Enable-PSModulePathProtection {
    <#
    .SYNOPSIS
        Enables smart protection of PSModulePath in virtual environment.
    
    .DESCRIPTION
        Creates a timer-based monitoring system with smart bypass capabilities
        for legitimate module operations.
    
    .PARAMETER ProtectedPath
        The PSModulePath that should be maintained and protected.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProtectedPath
    )
    
    if ($script:PathProtectionActive) {
        Write-Verbose "PSModulePath protection already active"
        return
    }
    
    # Initialize system paths
    Initialize-SystemModulePaths | Out-Null
    
    $script:ProtectedPSModulePath = $ProtectedPath
    $script:PathProtectionActive = $true
    $script:TemporaryPathBypass = $false
    
    # Create a timer that checks PSModulePath every 200ms (reduced frequency)
    $script:PathCheckTimer = New-Object System.Timers.Timer
    $script:PathCheckTimer.Interval = 200
    $script:PathCheckTimer.AutoReset = $true
    
    # FIX: Simplified event action. It no longer tries to be "smart" about the path's content.
    # Its only job is to restore the path if it's wrong AND a bypass is not active.
    $eventAction = {
        # If a temporary bypass is active, do nothing.
        if ($script:TemporaryPathBypass) {
            return
        }

        # If protection is active and the path is wrong, fix it.
        if ($script:PathProtectionActive -and $env:PSModulePath -ne $script:ProtectedPSModulePath) {
            Write-Verbose "PSModulePath was modified outside of a bypass, restoring protected path."
            $env:PSModulePath = $script:ProtectedPSModulePath
        }
    
        Register-ObjectEvent -InputObject $script:PathCheckTimer -EventName Elapsed -Action $eventAction | Out-Null
        $script:PathCheckTimer.Start()
    
        Write-Verbose "Smart PSModulePath protection enabled with path: $ProtectedPath"
    }
}

function Request-TemporaryPathBypass {
    <#
    .SYNOPSIS
        Requests a temporary bypass of path protection for module operations.
    
    .DESCRIPTION
        Temporarily disables path protection to allow legitimate module operations
        like Install-Module or Import-Module to access system modules.
    
    .PARAMETER DurationSeconds
        How long the bypass should last (default: 10 seconds).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$DurationSeconds = 10
    )
    
    if (-not $script:PathProtectionActive) {
        return
    }
    
    Write-Verbose "Requesting temporary path bypass for $DurationSeconds seconds"
    $script:TemporaryPathBypass = $true
    $script:BypassStartTime = Get-Date
    
    # Schedule automatic re-enable
    $timer = New-Object System.Timers.Timer
    $timer.Interval = $DurationSeconds * 1000
    $timer.AutoReset = $false
    
    Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
        $script:TemporaryPathBypass = $false
        $script:BypassStartTime = $null
        Write-Verbose "Temporary path bypass expired automatically"
        $sender.Dispose()
    } | Out-Null
    
    $timer.Start()
}

function Disable-PSModulePathProtection {
    <#
    .SYNOPSIS
        Disables PSModulePath protection.
    #>
    [CmdletBinding()]
    param()
    
    if (-not $script:PathProtectionActive) {
        Write-Verbose "PSModulePath protection already inactive"
        return
    }
    
    $script:PathProtectionActive = $false
    $script:TemporaryPathBypass = $false
    $script:BypassStartTime = $null
    
    if ($script:PathCheckTimer) {
        $script:PathCheckTimer.Stop()
        
        # Remove all event handlers for this timer
        Get-EventSubscriber | Where-Object { 
            $_.SourceObject -eq $script:PathCheckTimer 
        } | Unregister-Event -Force
        
        $script:PathCheckTimer.Dispose()
        $script:PathCheckTimer = $null
    }
    
    # Clean up any temporary bypass timers
    Get-EventSubscriber | Where-Object { 
        $_.Action -like "*TemporaryPathBypass*" 
    } | Unregister-Event -Force
    
    $script:ProtectedPSModulePath = $null
    Write-Verbose "PSModulePath protection disabled"
}

function Test-PSModulePathProtection {
    <#
    .SYNOPSIS
        Tests if PSModulePath protection is currently active.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    return $script:PathProtectionActive
}

function Get-ProtectedPSModulePath {
    <#
    .SYNOPSIS
        Gets the currently protected PSModulePath.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    return $script:ProtectedPSModulePath
}
