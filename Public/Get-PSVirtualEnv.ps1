function Get-PSVirtualEnv {
    <#
    .SYNOPSIS
        Lists PowerShell virtual environments.
    
    .DESCRIPTION
        Lists all PowerShell virtual environments or filters by specific criteria.
        Shows environment names, paths, creation dates, and active status.
    
    .PARAMETER Name
        Filter by specific environment name. Supports wildcards.
    
    .PARAMETER Active
        Show only the currently active environment.
    
    .PARAMETER Detailed
        Show detailed information including installed modules and settings.
    
    .EXAMPLE
        Get-PSVirtualEnv
        Lists all virtual environments.
    
    .EXAMPLE
        Get-PSVirtualEnv -Active
        Shows only the currently active environment.
    
    .EXAMPLE
        Get-PSVirtualEnv -Name "Web*" -Detailed
        Shows detailed information for all environments starting with "Web".
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSVirtualEnvironment[]])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'List')]
        [SupportsWildcards()]
        [string]$Name,
        
        [Parameter(ParameterSetName = 'Active')]
        [switch]$Active,
        
        [Parameter(ParameterSetName = 'Active')]
        [switch]$Detailed
    )
    
    begin {
        Write-Verbose "Getting PowerShell virtual environments"
    }
    
    process {
        # Get all environments from registry
        $registry = Get-EnvironmentRegistry
        $environments = @()
        
        foreach ($envData in $registry) {
            $env = [PSVirtualEnvironment]::FromHashtable($envData)
            
            # Check if this is the active environment
            if (Test-EnvironmentActive) {
                $activeEnv = Get-ActiveEnvironment
                $env.IsActive = ($activeEnv.Name -eq $env.Name)
            }
            
            $environments += $env
        }
        
        # Filter by parameter set
        if ($Active) {
            $environments = $environments | Where-Object { $_.IsActive }
            if ($environments.Count -eq 0) {
                Write-Warning "No virtual environment is currently active."
                return
            }
        } elseif ($Name) {
            $environments = $environments | Where-Object { $_.Name -like $Name }
            if ($environments.Count -eq 0) {
                Write-Warning "No environments found matching pattern '$Name'."
                return
            }
        }
        
        # Output based on detail level
        if ($Detailed) {
            # Return full objects
            $environments
        } else {
            # Return formatted summary
            $environments | ForEach-Object {
                $output = [PSCustomObject]@{
                    Name = $_.Name
                    Path = $_.Path
                    Created = $_.Created
                    IsActive = $_.IsActive
                    ModuleCount = $_.Modules.Count
                    Description = $_.Description
                }
                
                # Add type name for formatting
                $output.PSObject.TypeNames.Insert(0, 'PSVirtualEnv.Summary')
                $output
            }
        }
    }
}