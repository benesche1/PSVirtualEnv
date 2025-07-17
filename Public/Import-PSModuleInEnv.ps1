function Import-PSModuleInEnv {
    <#
    .SYNOPSIS
        Imports a module from the active virtual environment.
        
    .DESCRIPTION
        Imports a module specifically from the virtual environment, ensuring
        it doesn't conflict with or load from system locations.
        
    .PARAMETER Name
        Module name to import.
        
    .PARAMETER Force
        Force import even if already loaded.
        
    .PARAMETER Global
        Import to global scope.
        
    .PARAMETER PassThru
        Return the module info.
        
    .EXAMPLE
        Import-PSModuleInEnv -Name "Pester"
        Imports Pester from the active virtual environment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$Global,
        
        [Parameter()]
        [switch]$PassThru
    )
    
    begin {
        Write-Verbose "Importing module '$Name' from virtual environment"
        
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
        
        try {
            $result = Import-ModuleFromEnvironment -Name $Name -EnvironmentPath $environment.Path -Force:$Force -Global:$Global -PassThru:$PassThru
            
            Write-Information "Successfully imported '$Name' from virtual environment" -InformationAction Continue
            
            if ($PassThru) {
                return $result
            }
            
        } catch {
            Write-Error "Failed to import module '$Name' from virtual environment: $_"
        }
    }
}