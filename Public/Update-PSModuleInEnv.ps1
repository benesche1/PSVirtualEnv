function Update-PSModuleInEnv {
    <#
    .SYNOPSIS
        Updates modules in the active virtual environment.
    
    .DESCRIPTION
        Updates PowerShell modules in the currently active virtual environment to their
        latest versions available in the configured repositories.
    
    .PARAMETER Name
        Specific module to update. If not specified, updates all modules.
    
    .PARAMETER Force
        Force update even if the module is already at the latest version.
    
    .PARAMETER AcceptLicense
        Automatically accept license agreements during update.
    
    .EXAMPLE
        Update-PSModuleInEnv
        Updates all modules in the active environment to their latest versions.
    
    .EXAMPLE
        Update-PSModuleInEnv -Name "Pester" -Force
        Forces an update of the Pester module to the latest version.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Name,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$AcceptLicense
    )
    
    begin {
        Write-Verbose "Updating modules in virtual environment"
        
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
        
        # Get modules to update
        if ($Name) {
            $modulesToUpdate = Get-PSModuleInEnv -Name $Name
            if (-not $modulesToUpdate) {
                Write-Error "Module '$Name' is not installed in the active environment."
                return
            }
        } else {
            $modulesToUpdate = Get-PSModuleInEnv
            if (-not $modulesToUpdate) {
                Write-Warning "No modules found in the active environment to update."
                return
            }
        }
        
        $updateCount = 0
        $failCount = 0
        
        foreach ($module in $modulesToUpdate) {
            Write-Information "Checking for updates to '$($module.Name)' (current version: $($module.Version))..." -InformationAction Continue
            
            try {
                # Find latest version
                $latestModule = Find-Module -Name $module.Name -ErrorAction Stop | Select-Object -First 1
                
                if ($latestModule.Version -gt $module.Version -or $Force) {
                    if ($PSCmdlet.ShouldProcess("$($module.Name) from $($module.Version) to $($latestModule.Version)", "Update module")) {
                        # Install new version
                        $installParams = @{
                            Name = $module.Name
                            RequiredVersion = $latestModule.Version.ToString()
                            Force = $true
                        }
                        
                        if ($AcceptLicense) {
                            $installParams['AcceptLicense'] = $true
                        }
                        
                        Install-PSModuleInEnv @installParams
                        
                        # Remove old version
                        $oldVersionPath = Join-Path $modulePath "$($module.Name)\$($module.Version)"
                        if (Test-Path $oldVersionPath) {
                            Remove-Item -Path $oldVersionPath -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        
                        # Update environment configuration
                        $moduleEntry = $environment.Modules | Where-Object { $_.name -eq $module.Name }
                        if ($moduleEntry) {
                            $moduleEntry.version = $latestModule.Version.ToString()
                            $moduleEntry.installed = (Get-Date).ToString('o')
                        }
                        
                        Write-Information "Updated '$($module.Name)' from $($module.Version) to $($latestModule.Version)" -InformationAction Continue
                        $updateCount++
                    }
                } else {
                    Write-Verbose "'$($module.Name)' is already at the latest version ($($module.Version))"
                }
                
            } catch {
                Write-Warning "Failed to update module '$($module.Name)': $_"
                $failCount++
            }
        }
        
        # Save updated configuration
        if ($updateCount -gt 0) {
            Set-EnvironmentConfig -Environment $environment
            
            # Log update summary
            $logPath = Join-Path $environment.Path "Logs\modules.log"
            $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Update completed: $updateCount module(s) updated, $failCount failed"
            Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
        }
        
        Write-Information "Update completed: $updateCount module(s) updated$(if ($failCount -gt 0) { ", $failCount failed" })" -InformationAction Continue
    }
}