function Deactivate-PSVirtualEnv {
    <#
    .SYNOPSIS
        Deactivates the currently active PowerShell virtual environment.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()
    
    begin {
        Write-Verbose "Deactivating PowerShell virtual environment"
    }
    
    process {
        # Check if any environment is active
        if (-not (Test-EnvironmentActive)) {
            Write-Warning "No virtual environment is currently active."
            return
        }
        
        $activeEnv = Get-ActiveEnvironment
        
        try {
            # Remove isolation
            Remove-VirtualEnvironmentIsolation
            
            # Restore original prompt function
            if ($script:OriginalPromptFunction) {
                Set-Item -Path function:prompt -Value $script:OriginalPromptFunction
                $script:OriginalPromptFunction = $null
                Write-Verbose "Restored original prompt function"
            } else {
                # Set default prompt if no original was stored
                Set-Item -Path function:prompt -Value {
                    "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
                }
            }
            
            # Log deactivation
            $environment = Get-EnvironmentFromRegistry -Name $activeEnv.Name
            if ($environment) {
                $logPath = Join-Path $environment.Path "Logs\activation.log"
                $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Environment deactivated (isolation removed) by $env:USERNAME"
                Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
            }
            
            # Clear active environment
            $envName = $script:ActiveEnvironment.Name
            $script:ActiveEnvironment = $null
            
            Write-Information "Successfully deactivated virtual environment '$envName' and restored system access" -InformationAction Continue
            
        } catch {
            Write-Error "Failed to deactivate virtual environment: $_"
        }
    }
}