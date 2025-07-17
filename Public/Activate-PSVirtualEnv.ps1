function Activate-PSVirtualEnv {
    <#
    .SYNOPSIS
        Activates a PowerShell virtual environment with true isolation.
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
        Write-Verbose "Activating PowerShell virtual environment with true isolation: $Name"
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
            
            # Initialize isolated operations
            Initialize-IsolatedOperations
            
            # Set strict isolation
            Set-VirtualEnvironmentIsolation -EnvironmentPath $environment.Path
            
            # Store original prompt function
            $script:OriginalPromptFunction = (Get-Command prompt -ErrorAction SilentlyContinue).ScriptBlock
            
            # Update prompt to show active environment
            $promptFunction = {
                if ($script:ActiveEnvironment) {
                    Write-Host "($($script:ActiveEnvironment.Name)) " -NoNewline -ForegroundColor Green
                }
                if ($script:OriginalPromptFunction) {
                    & $script:OriginalPromptFunction
                } else {
                    "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
                }
            }
            
            Set-Item -Path function:prompt -Value $promptFunction
            Write-Verbose "Updated prompt function"
            
            # Set active environment
            $script:ActiveEnvironment = @{
                Name = $environment.Name
                Path = $environment.Path
                OriginalPath = $script:OriginalPSModulePath
                ProtectedPath = $environment.Path
            }
            
            # Log activation
            $logPath = Join-Path $environment.Path "Logs\activation.log"
            $logDir = Split-Path $logPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
            $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Environment activated with true isolation by $env:USERNAME"
            Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
            
            Write-Information "Successfully activated virtual environment '$Name' with TRUE ISOLATION" -InformationAction Continue
            Write-Information "Only modules installed in this environment will be available" -InformationAction Continue
            Write-Information "Use Install-PSModuleInEnv to add modules to this environment" -InformationAction Continue
            
        } catch {
            Write-Error "Failed to activate virtual environment: $_"
            
            # Rollback changes
            try {
                Remove-VirtualEnvironmentIsolation
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