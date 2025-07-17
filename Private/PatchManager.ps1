<#
.SYNOPSIS
    Manages the PSModulePath for virtual environments.

.DESCRIPTION
    This script contains functions to get system module paths, set the PSModulePath
    for an active environment, and restore it upon deactivation. It includes logic
    to handle path differences across Windows, macOS, and Linux.
#>

function Get-SystemModulePaths {
    <#
    .SYNOPSIS
        Gets the system module paths from PSModulePath.
    
    .DESCRIPTION
        Returns an array of system module paths, excluding user-specific paths to ensure
        isolation.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    
    $paths = $env:PSModulePath -split [IO.Path]::PathSeparator
    
    # Define user-specific paths for different operating systems
    if ($PSVersionTable.PSEdition -eq 'Core' -and $IsUnix) {
        $userPaths = @(
            (Join-Path $HOME '.local/share/powershell/Modules'),
            (Join-Path $HOME '.config/powershell/Modules')
        )
    } else {
        $userPaths = @(
            (Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules'),
            (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules')
        )
    }
    
    # Filter out user-specific paths to get only system paths
    $systemPaths = $paths | Where-Object {
        $currentPath = $_
        $isUserPath = $false
        foreach ($userPath in $userPaths) {
            # Check for exact match or if the path is within a user's home directory
            if ($currentPath -eq $userPath -or $currentPath -like "*$env:USERNAME*" -or ($IsUnix -and $currentPath -like "*$env:USER*")) {
                $isUserPath = $true
                break
            }
        }
        -not $isUserPath
    }
    
    return $systemPaths
}

function Set-PSModulePathForEnvironment {
    <#
    .SYNOPSIS
        Sets the PSModulePath for the active environment.
    
    .DESCRIPTION
        Modifies the PSModulePath to prioritize the virtual environment's module directory,
        optionally including system paths.
    
    .PARAMETER EnvironmentPath
        The path to the virtual environment.
    
    .PARAMETER IncludeSystemModules
        Whether to include system module paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentPath,
        
        [switch]$IncludeSystemModules
    )
    
    $envModulePath = Join-Path $EnvironmentPath 'Modules'
    
    if ($IncludeSystemModules.IsPresent) {
        $systemPaths = Get-SystemModulePaths
        $newPath = @($envModulePath) + $systemPaths
    } else {
        # Define a minimal set of essential system paths based on the OS and PowerShell edition
        $minimalSystemPaths = @()
        if ($IsCoreCLR) { # PowerShell 6+
            if ($IsUnix) {
                $minimalSystemPaths = @(
                    '/usr/local/share/powershell/Modules',
                    '/opt/microsoft/powershell/7/Modules'
                )
            } else { # Windows with PowerShell Core
                $minimalSystemPaths = @(
                    (Join-Path $env:ProgramFiles 'PowerShell\Modules'),
                    (Join-Path $env:ProgramFiles 'PowerShell\7\Modules'),
                    (Join-Path $env:windir 'system32\WindowsPowerShell\v1.0\Modules')
                )
            }
        } else { # Windows PowerShell 5.1
            $minimalSystemPaths = @(
                (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'),
                (Join-Path $env:windir 'system32\WindowsPowerShell\v1.0\Modules')
            )
            
            # Include x86 path on 64-bit systems if it exists
            if (Test-Path ${env:ProgramFiles(x86)}) {
                $minimalSystemPaths += (Join-Path ${env:ProgramFiles(x86)} 'WindowsPowerShell\Modules')
            }
        }
        
        # Construct the new path, ensuring the environment path is first
        $newPath = @($envModulePath) + ($minimalSystemPaths | Where-Object { Test-Path $_ })
    }
    
    $env:PSModulePath = $newPath -join [IO.Path]::PathSeparator
}

function Restore-OriginalPSModulePath {
    <#
    .SYNOPSIS
        Restores the original PSModulePath.
    
    .DESCRIPTION
        Restores the PSModulePath to its state before environment activation from the
        module-scoped backup variable.
    #>
    [CmdletBinding()]
    param()
    
    if ($script:OriginalPSModulePath) {
        $env:PSModulePath = $script:OriginalPSModulePath
        $script:OriginalPSModulePath = $null
        Write-Verbose "Restored original PSModulePath."
    } else {
        Write-Warning "No original PSModulePath backup found to restore."
    }
}

function Set-PSModulePathForEnvironment {
    <#
    .SYNOPSIS
        Sets the PSModulePath for the active environment with smart system module inclusion.
    
    .DESCRIPTION
        Modifies the PSModulePath to prioritize the virtual environment's module directory,
        while ensuring essential system modules remain accessible.
    
    .PARAMETER EnvironmentPath
        The path to the virtual environment.
    
    .PARAMETER IncludeSystemModules
        Whether to include system module paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentPath,
        
        [switch]$IncludeSystemModules
    )
    
    $envModulePath = Join-Path $EnvironmentPath 'Modules'
    
    # Always include essential system paths for critical modules like PowerShellGet
    $essentialSystemPaths = @()
    
    if ($PSVersionTable.PSEdition -eq 'Core') {
        if ($IsWindows) {
            $essentialSystemPaths = @(
                (Join-Path $env:ProgramFiles 'PowerShell\Modules'),
                (Join-Path $env:ProgramFiles 'PowerShell\7\Modules')
            )
        } else {
            $essentialSystemPaths = @(
                '/usr/local/share/powershell/Modules',
                '/opt/microsoft/powershell/7/Modules'
            )
        }
    } else {
        # Windows PowerShell
        $essentialSystemPaths = @(
            (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'),
            (Join-Path $env:windir 'system32\WindowsPowerShell\v1.0\Modules')
        )
    }
    
    # Filter to only existing paths
    $essentialSystemPaths = $essentialSystemPaths | Where-Object { Test-Path $_ }
    
    if ($IncludeSystemModules.IsPresent) {
        # Include all system paths
        $systemPaths = Get-SystemModulePaths
        $newPath = @($envModulePath) + $systemPaths
    } else {
        # Include only essential system paths (for PowerShellGet, etc.)
        $newPath = @($envModulePath) + $essentialSystemPaths
    }
    
    $env:PSModulePath = $newPath -join [IO.Path]::PathSeparator
    Write-Verbose "Set PSModulePath with environment priority: $($env:PSModulePath)"
}