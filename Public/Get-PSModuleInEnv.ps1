function Get-PSModuleInEnv {
    <#
    .SYNOPSIS
        Lists modules installed in the active virtual environment.
    
    .DESCRIPTION
        Shows all PowerShell modules installed in the currently active virtual environment.
        Can filter by module name and show available versions.
    
    .PARAMETER Name
        Filter by module name pattern. Supports wildcards.
    
    .PARAMETER ListAvailable
        Show all available modules in the environment, including different versions.
    
    .EXAMPLE
        Get-PSModuleInEnv
        Lists all modules in the active environment.
    
    .EXAMPLE
        Get-PSModuleInEnv -Name "Pester*"
        Lists all modules starting with "Pester" in the active environment.
    
    .EXAMPLE
        Get-PSModuleInEnv -ListAvailable
        Shows all available module versions in the active environment.
    #>
    [CmdletBinding()]
    [OutputType([PSModuleInfo[]])]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [string]$Name = '*',
        
        [Parameter()]
        [switch]$ListAvailable
    )
    
    begin {
        Write-Verbose "Getting modules in virtual environment"
        
        # Verify environment is active
        if (-not (Test-EnvironmentActive)) {
            Write-Warning "No virtual environment is active. Use Activate-PSVirtualEnv to activate an environment first."
            return
        }
    }
    
    process {
        $activeEnv = Get-ActiveEnvironment
        $environment = Get-EnvironmentFromRegistry -Name $activeEnv.Name
        
        if (-not $environment) {
            Write-Error "Active environment configuration not found. The environment may be corrupted."
            return
        }
        
        $modulePath = Join-Path $environment.Path 'Modules'
        
        if (-not (Test-Path $modulePath)) {
            Write-Warning "Module directory not found in environment. No modules installed."
            return
        }
        
        # Get modules using Get-Module with specific path
        $getModuleParams = @{
            Name = $Name
            ListAvailable = $true
            ErrorAction = 'SilentlyContinue'
        }
        
        # Temporarily modify PSModulePath to only search in environment
        $originalPath = $env:PSModulePath
        $env:PSModulePath = $modulePath
        
        try {
            $modules = Get-Module @getModuleParams
            
            if (-not $ListAvailable) {
                # Group by name and get latest version only
                $modules = $modules | Group-Object Name | ForEach-Object {
                    $_.Group | Sort-Object Version -Descending | Select-Object -First 1
                }
            }
            
            # Add custom property to indicate it's from virtual environment
            $modules | ForEach-Object {
                $_ | Add-Member -NotePropertyName 'VirtualEnvironment' -NotePropertyValue $environment.Name -Force
                $_
            }
            
        } finally {
            # Restore PSModulePath
            $env:PSModulePath = $originalPath
        }
    }
}