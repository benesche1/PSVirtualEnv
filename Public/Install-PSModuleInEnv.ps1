function Install-PSModuleInEnv {
    <#
    .SYNOPSIS
        Installs a PowerShell module into the active virtual environment with true isolation.
    
    .DESCRIPTION
        Installs a PowerShell module from a repository into the currently active virtual 
        environment without contaminating the current session with global modules.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter()]
        [string]$RequiredVersion,
        
        [Parameter()]
        [string]$Repository = 'PSGallery',
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$AllowPrerelease
    )
    
    begin {
        Write-Verbose "Installing module '$Name' into virtual environment with true isolation"
        
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
        
        if ($PSCmdlet.ShouldProcess("$Name in environment '$($environment.Name)'", "Install module")) {
            try {
                Write-Information "Installing module '$Name' from repository '$Repository' with isolation..." -InformationAction Continue
                
                # Use isolated installation method
                $moduleInfo = Install-ModuleToEnvironment -Name $Name -EnvironmentPath $environment.Path -RequiredVersion $RequiredVersion -Repository $Repository -Force:$Force -AllowPrerelease:$AllowPrerelease
                
                # Update environment configuration
                $environment.AddModule($moduleInfo.Name, $moduleInfo.Version.ToString())
                Set-EnvironmentConfig -Environment $environment
                Add-EnvironmentToRegistry -Environment $environment
                
                # Log installation
                $logPath = Join-Path $environment.Path "Logs\modules.log"
                $logDir = Split-Path $logPath -Parent
                if (-not (Test-Path $logDir)) {
                    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
                }
                $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installed (isolated): $($moduleInfo.Name) v$($moduleInfo.Version)"
                Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
                
                Write-Information "Successfully installed module '$($moduleInfo.Name)' version $($moduleInfo.Version) with true isolation" -InformationAction Continue
                
            } catch {
                Write-Error "Failed to install module '$Name': $_"
            }
        }
    }
}