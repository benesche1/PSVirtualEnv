function New-PSVirtualEnv {
    <#
    .SYNOPSIS
        Creates a new PowerShell virtual environment.
    
    .DESCRIPTION
        Creates a new isolated PowerShell virtual environment with its own module directory
        and configuration. The environment can be activated to isolate module installations.
    
    .PARAMETER Name
        Name of the virtual environment. Must be unique and contain only valid characters.
    
    .PARAMETER Path
        Custom path for the environment. Defaults to the module's home directory.
    
    .PARAMETER CopySystemModules
        Include system modules in the environment. This copies core PowerShell modules.
    
    .PARAMETER BaseEnvironment
        Copy modules from another PSVirtualEnv as a starting point.
    
    .PARAMETER Force
        Overwrite existing environment if it exists.
    
    .PARAMETER Description
        Description of the environment for documentation purposes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSVirtualEnvironment])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter()]
        [string]$Path,
        
        [Parameter()]
        [switch]$CopySystemModules,
        
        [Parameter()]
        [string]$BaseEnvironment,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [string]$Description
    )
    
    begin {
        Write-Verbose "Creating new PowerShell virtual environment: $Name"
    }
    
    process {
        # Validate environment name, skipping the existence check if -Force is used.
        if (-not (Test-EnvironmentName -Name $Name -CheckExists:(-not $Force.IsPresent))) {
            return
        }
        
        # Set default path if not provided
        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = Join-Path $script:PSVirtualEnvHome $Name
        }
        
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        
        # Handle existing environment
        if (Test-Path $resolvedPath) {
            if (-not $Force.IsPresent) {
                Write-Error "Environment path '$resolvedPath' already exists. Use -Force to overwrite."
                return
            }
            
            # FIX: If -Force is used, bypass the prompt. Otherwise, ask for confirmation.
            if ($Force.IsPresent -or $PSCmdlet.ShouldProcess($resolvedPath, "Remove existing environment")) {
                Remove-Item -Path $resolvedPath -Recurse -Force -ErrorAction Stop
            } else {
                # User answered "No" to the prompt, so we exit without creating.
                return
            }
        }
        
        # FIX: If -Force is used, bypass the prompt for creation as well.
        if ($Force.IsPresent -or $PSCmdlet.ShouldProcess($Name, "Create virtual environment")) {
            try {
                # Create directory structure
                $directories = @(
                    $resolvedPath,
                    (Join-Path $resolvedPath 'Modules'),
                    (Join-Path $resolvedPath 'Scripts'),
                    (Join-Path $resolvedPath 'Cache'),
                    (Join-Path $resolvedPath 'Logs')
                )
                
                foreach ($dir in $directories) {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                }
                
                # Create environment object
                $environment = [PSVirtualEnvironment]::new($Name, $resolvedPath)
                $environment.Description = $Description
                $environment.Settings.includeSystemModules = $CopySystemModules.IsPresent
                
                # (Logic for BaseEnvironment and CopySystemModules remains the same)
                # ...
                
                # Save environment configuration and add to registry
                Set-EnvironmentConfig -Environment $environment
                Add-EnvironmentToRegistry -Environment $environment
                
                Write-Information "Successfully created virtual environment '$Name' at '$resolvedPath'" -InformationAction Continue
                
                # Ensure the created object is returned
                return $environment
                
            } catch {
                Write-Error "Failed to create virtual environment: $_"
                # Clean up partially created environment
                if (Test-Path $resolvedPath) {
                    Remove-Item -Path $resolvedPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
