function Uninstall-PSModuleInEnv {
    <#
    .SYNOPSIS
        Uninstalls a module from the active virtual environment.
    
    .DESCRIPTION
        Removes a PowerShell module from the currently active virtual environment.
        This only affects the environment and does not impact system-wide installations.
    
    .PARAMETER Name
        Module name to uninstall.
    
    .PARAMETER RequiredVersion
        Specific version to uninstall. If not specified, all versions are removed.
    
    .PARAMETER Force
        Force uninstallation without confirmation.
    
    .EXAMPLE
        Uninstall-PSModuleInEnv -Name "OldModule"
        Uninstalls all versions of OldModule from the active environment.
    
    .EXAMPLE
        Uninstall-PSModuleInEnv -Name "TestModule" -RequiredVersion "1.0.0" -Force
        Uninstalls version 1.0.0 of TestModule without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter()]
        [string]$RequiredVersion,
        
        [Parameter()]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Uninstalling module '$Name' from virtual environment"
        
        # Verify environment is active
        if (-not (Test-EnvironmentActive)) {
            throw "No virtual environment is active. Use Activate-PSVirtualEnv to activate an environment first."
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
        $moduleDir = Join-Path $modulePath $Name
        
        # Check if module exists
        if (-not (Test-Path $moduleDir)) {
            Write-Error "Module '$Name' is not installed in the active environment."
            return
        }
        
        # Find specific version if requested
        if ($RequiredVersion) {
            $versionDir = Join-Path $moduleDir $RequiredVersion
            if (-not (Test-Path $versionDir)) {
                Write-Error "Module '$Name' version '$RequiredVersion' is not installed in the active environment."
                return
            }
            $pathToRemove = $versionDir
            $removeMessage = "module '$Name' version '$RequiredVersion'"
        } else {
            $pathToRemove = $moduleDir
            $removeMessage = "all versions of module '$Name'"
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess("$removeMessage from environment '$($environment.Name)'", "Uninstall")) {
            try {
                # Remove module directory
                Remove-Item -Path $pathToRemove -Recurse -Force -ErrorAction Stop
                
                # Update environment configuration
                if ($RequiredVersion) {
                    # Remove specific version from config
                    $moduleEntry = $environment.Modules | Where-Object { $_.name -eq $Name -and $_.version -eq $RequiredVersion }
                    if ($moduleEntry) {
                        $environment.Modules.Remove($moduleEntry) | Out-Null
                    }
                } else {
                    # Remove all versions from config
                    $environment.RemoveModule($Name)
                }
                
                Set-EnvironmentConfig -Environment $environment
                
                # Log uninstallation
                $logPath = Join-Path $environment.Path "Logs\modules.log"
                $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Uninstalled: $Name$(if ($RequiredVersion) { " v$RequiredVersion" })"
                Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
                
                Write-Information "Successfully uninstalled $removeMessage" -InformationAction Continue
                
            } catch {
                Write-Error "Failed to uninstall module '$Name': $_"
            }
        }
    }
}
