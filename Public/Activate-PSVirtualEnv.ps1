function Activate-PSVirtualEnv {
    <#
    .SYNOPSIS
        Activates a PowerShell virtual environment in the current session.
    
    .DESCRIPTION
        Activates a PowerShell virtual environment by modifying the PSModulePath to prioritize
        the environment's module directory. Also updates the prompt to show the active environment.
    
    .PARAMETER Name
        Name of the environment to activate.
    
    .PARAMETER Scope
        Scope of activation (Session, Global). Defaults to Session.
        Note: Global scope is not recommended as it affects all PowerShell sessions.
    
    .EXAMPLE
        Activate-PSVirtualEnv -Name "WebProject"
        Activates the "WebProject" environment in the current session.
    
    .EXAMPLE
        Activate-PSVirtualEnv -Name "Testing" -Scope Global
        Activates the "Testing" environment globally (not recommended).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter()]
        [ValidateSet('Session', 'Global')]
        [string]$Scope = 'Session'
    )
    
    begin {
        Write-Verbose "Activating PowerShell virtual environment: $Name"
    }
    
    process {
        # Check if another environment is already active
        if (Test-EnvironmentActive) {
            $activeEnv = Get-ActiveEnvironment
            Write-Warning "Environment '$($activeEnv.Name)' is currently active. Deactivating it first."
            Deactivate-PSVirtualEnv
        }
        
        # Get environment from registry
        $environment = Get-EnvironmentFromRegistry -Name $Name
        
        if (-not $environment) {
            Write-Error "Environment '$Name' not found. Use Get-PSVirtualEnv to list available environments."
            return
        }
        
        # Verify environment path exists
        if (-not (Test-Path $environment.Path)) {
            Write-Error "Environment path '$($environment.Path)' does not exist. The environment may be corrupted."
            return
        }
        
        try {
            # Store original PSModulePath
            $script:OriginalPSModulePath = $env:PSModulePath
            Write-Verbose "Stored original PSModulePath"
            
            # Set new PSModulePath
            Set-PSModulePathForEnvironment -EnvironmentPath $environment.Path -IncludeSystemModules:$environment.Settings.includeSystemModules
            Write-Verbose "Updated PSModulePath for environment"
            
            # Store original prompt function
            $script:OriginalPromptFunction = (Get-Command prompt -ErrorAction SilentlyContinue).ScriptBlock
            
            # Update prompt to show active environment
            $promptFunction = {
                if ($script:ActiveEnvironment) {
                    Write-Host "($($script:ActiveEnvironment.Name)) " -NoNewline -ForegroundColor Green
                }
                if ($script:OriginalPromptFunction) {
                    & $script:OriginalPromptFunction
                }
                else {
                    "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
                }
            }
            
            Set-Item -Path function:prompt -Value $promptFunction
            Write-Verbose "Updated prompt function"
            
            # Set active environment
            $script:ActiveEnvironment = @{
                Name         = $environment.Name
                Path         = $environment.Path
                OriginalPath = $script:OriginalPSModulePath
            }

            # ENHANCEMENT: Enable PSModulePath protection
            Enable-PSModulePathProtection -ProtectedPath $script:ActiveEnvironment.path
            
            # ENHANCEMENT: Enable module import hooks
            Enable-ModuleImportHooks
            
            # ENHANCEMENT: Register PowerShell idle event handler as backup
            $idleAction = {
                if ($script:ActiveEnvironment -and $env:PSModulePath -ne $script:ActiveEnvironment.path) {
                    Write-Verbose "PowerShell idle event detected path change, restoring"
                    $env:PSModulePath = $script:ActiveEnvironment.path
                }
            }
            
            Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action $idleAction | Out-Null
            
            # ENHANCEMENT: Pre-load critical modules that might trigger auto-loading
            $criticalModules = @('Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility', 'Microsoft.PowerShell.Security')
            foreach ($module in $criticalModules) {
                if (Get-Module -Name $module -ListAvailable -ErrorAction SilentlyContinue) {
                    Import-Module $module -Force -Global -ErrorAction SilentlyContinue
                }
            }
            
            # Log activation
            $logPath = Join-Path $environment.Path "Logs\activation.log"
            $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Environment activated by $env:USERNAME"
            Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
            
            Write-Information "Successfully activated virtual environment '$Name'" -InformationAction Continue
            Write-Information "Module installations will now be isolated to this environment" -InformationAction Continue
            
        }
        catch {
            Write-Error "Failed to activate virtual environment: $_"
            
            # Rollback changes
            try {
                Disable-PSModulePathProtection
                Disable-ModuleImportHooks
                Get-EventSubscriber | Where-Object { $_.SourceIdentifier -eq 'PowerShell.OnIdle' } | Unregister-Event -Force
                
                if ($script:OriginalPSModulePath) {
                    $env:PSModulePath = $script:OriginalPSModulePath
                    $script:OriginalPSModulePath = $null
                }
                $script:ActiveEnvironment = $null
            } catch {
                Write-Warning "Failed to properly rollback activation changes: $_"
            }
        }
    }
}