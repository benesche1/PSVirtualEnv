function Import-PSModuleInEnv {
    <#
    .SYNOPSIS
        Imports a module from the virtual environment with full dependency resolution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$ResolveDependencies = $true
    )
    
    begin {
        Write-Verbose "Importing module '$Name' from virtual environment with dependency resolution"
        
        if (-not (Test-EnvironmentActive)) {
            throw "No virtual environment is active. Use Activate-PSVirtualEnv to activate an environment first."
        }
    }
    
    process {
        $activeEnv = Get-ActiveEnvironment
        $environment = Get-EnvironmentFromRegistry -Name $activeEnv.Name
        
        if (-not $environment) {
            Write-Error "Active environment configuration not found."
            return
        }
        
        # Store the currently pristine, isolated path.
        $isolatedPath = $env:PSModulePath
        # Store the user's current autoloading preference
        $originalAutoLoadingPref = $PSModuleAutoLoadingPreference
        $result = $null


        try {

            $PSModuleAutoLoadingPreference = 'None'

            $importParams = @{
                Name     = $Name
                Force    = $Force.IsPresent
                PassThru = $PassThru.IsPresent
            }
        
            if ($Global.IsPresent) {
                $importParams['Global'] = $true
            }
        
            Write-Verbose "Importing module from: $name with autoloading disabled."
            $result = Import-Module @importParams
            return $result
            <#if ($ResolveDependencies) {

                 
                # Use advanced dependency resolution
                $result = Import-ModuleWithDependencies -ModuleName $Name -EnvironmentPath $environment.Path -Force:$Force
                
                if ($result.Success) {
                    Write-Information "Successfully imported '$Name' with all dependencies" -InformationAction Continue
                }
                else {
                    Write-Warning "Import completed with some failures. Check loaded modules with Get-Module."
                }
                
                return $result
            }
            else {
                # Simple import (fallback to original method)
                $result = Import-ModuleFromEnvironment -Name $Name -EnvironmentPath $environment.Path -Force:$Force -PassThru
                Write-Information "Successfully imported '$Name' (simple mode)" -InformationAction Continue
                return $result
            }#>
            
        }
        catch {
            Write-Error "Failed to import module '$Name': $_"
            throw
        }
        finally {

            $PSModuleAutoLoadingPreference = $originalAutoLoadingPref
            <#
            if ($env:PSModulePath -ne $isolatedPath) {
                Write-Verbose "PowerShell auto-loader modified PSModulePath during import. Restoring strict isolation."
                $env:PSModulePath = $isolatedPath
            }#>
        }
    }
}