function Install-PSModuleInEnv {
    <#
    .SYNOPSIS
        Installs a PowerShell module into the active virtual environment.
    
    .DESCRIPTION
        Installs a PowerShell module from a repository (default: PSGallery) into the
        currently active virtual environment's module directory. The module will only
        be available when the environment is active.
    
    .PARAMETER Name
        Module name to install. Supports wildcards for searching.
    
    .PARAMETER RequiredVersion
        Specific version to install. If not specified, installs the latest version.
    
    .PARAMETER Repository
        Repository to install from. Defaults to PSGallery.
    
    .PARAMETER Scope
        Always set to CurrentUser for environment isolation. This parameter is ignored.
    
    .PARAMETER Force
        Force installation even if the module already exists.
    
    .PARAMETER AllowPrerelease
        Allow installation of prerelease versions.
    
    .EXAMPLE
        Install-PSModuleInEnv -Name "Pester" -RequiredVersion "5.3.0"
        Installs Pester version 5.3.0 into the active environment.
    
    .EXAMPLE
        Install-PSModuleInEnv -Name "PSScriptAnalyzer" -Force
        Installs the latest version of PSScriptAnalyzer, overwriting if it exists.
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
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser',
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$AllowPrerelease
    )
    
    begin {
        Write-Verbose "Installing module '$Name' into virtual environment"
        
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
        
        # Build Install-Module parameters
        $installParams = @{
            Name = $Name
            Repository = $Repository
            Scope = 'CurrentUser'
            Force = $Force.IsPresent
            AllowPrerelease = $AllowPrerelease.IsPresent
            ErrorAction = 'Stop'
        }
        
        if ($RequiredVersion) {
            $installParams['RequiredVersion'] = $RequiredVersion
        }
        
        # Add Path parameter to force installation to environment directory
        $installParams['Path'] = $modulePath
        
        if ($PSCmdlet.ShouldProcess("$Name in environment '$($environment.Name)'", "Install module")) {
            try {
                Write-Information "Installing module '$Name' from repository '$Repository'..." -InformationAction Continue
                
                # Temporarily modify PSModulePath to ensure proper installation
                $originalPath = $env:PSModulePath
                $env:PSModulePath = "$modulePath;$originalPath"
                
                try {
                    # Find the module first to get version info
                    $findParams = @{
                        Name = $Name
                        Repository = $Repository
                        ErrorAction = 'Stop'
                    }
                    
                    if ($RequiredVersion) {
                        $findParams['RequiredVersion'] = $RequiredVersion
                    }
                    
                    if ($AllowPrerelease) {
                        $findParams['AllowPrerelease'] = $true
                    }
                    
                    $moduleToInstall = Find-Module @findParams | Select-Object -First 1
                    
                    if (-not $moduleToInstall) {
                        throw "Module '$Name' not found in repository '$Repository'"
                    }
                    
                    # Save the module to the environment path
                    $saveParams = @{
                        Name = $moduleToInstall.Name
                        Path = $modulePath
                        Repository = $Repository
                        Force = $Force.IsPresent
                        ErrorAction = 'Stop'
                    }
                    
                    if ($RequiredVersion) {
                        $saveParams['RequiredVersion'] = $RequiredVersion
                    } else {
                        $saveParams['RequiredVersion'] = $moduleToInstall.Version.ToString()
                    }
                    
                    if ($AllowPrerelease) {
                        $saveParams['AllowPrerelease'] = $true
                    }
                    
                    Save-Module @saveParams
                    
                    # Update environment configuration
                    $environment.AddModule($moduleToInstall.Name, $moduleToInstall.Version.ToString())
                    Set-EnvironmentConfig -Environment $environment
                    
                    # Log installation
                    $logPath = Join-Path $environment.Path "Logs\modules.log"
                    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Installed: $($moduleToInstall.Name) v$($moduleToInstall.Version)"
                    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
                    
                    Write-Information "Successfully installed module '$($moduleToInstall.Name)' version $($moduleToInstall.Version)" -InformationAction Continue
                    
                } finally {
                    # Restore original PSModulePath
                    $env:PSModulePath = $originalPath
                }
                
            } catch {
                Write-Error "Failed to install module '$Name': $_"
            }
        }
    }
}
