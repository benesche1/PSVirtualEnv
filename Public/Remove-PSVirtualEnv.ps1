function Remove-PSVirtualEnv {
    <#
    .SYNOPSIS
        Removes an existing PowerShell virtual environment.
    
    .DESCRIPTION
        Removes a PowerShell virtual environment and all its contents, including installed modules.
        This operation is non-recoverable. The environment must not be currently active.
    
    .PARAMETER Name
        Name of the environment to remove. This parameter is mandatory.
    
    .PARAMETER Force
        Skip the confirmation prompt and force removal.
    
    .EXAMPLE
        Remove-PSVirtualEnv -Name "OldProject"
        Removes the environment named "OldProject" after asking for confirmation.
    
    .EXAMPLE
        Remove-PSVirtualEnv -Name "Testing" -Force
        Removes the environment named "Testing" immediately without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter()]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Attempting to remove PowerShell virtual environment: $Name"
    }
    
    process {
        # Get environment details from the central registry
        $environment = Get-EnvironmentFromRegistry -Name $Name
        
        if (-not $environment) {
            Write-Error "Environment '$Name' not found. Use Get-PSVirtualEnv to list available environments."
            return
        }
        
        # Prevent removal of a currently active environment
        if (Test-EnvironmentActive) {
            $activeEnv = Get-ActiveEnvironment
            if ($activeEnv.Name -eq $Name) {
                Write-Error "Cannot remove currently active environment '$Name'. Please deactivate it first using Deactivate-PSVirtualEnv."
                return
            }
        }
        
        # Confirm removal unless -Force is specified
        if ($Force.IsPresent -or $PSCmdlet.ShouldProcess("'$Name' at path '$($environment.path)'", "Remove virtual environment")) {
            try {
                # --- Atomic Operation Change ---
                # 1. Remove from registry first. If this fails, we don't proceed.
                Remove-EnvironmentFromRegistry -Name $Name
                Write-Verbose "Removed environment '$Name' from registry."
                
                # 2. Remove the environment directory. If this fails, the registry is already clean.
                if (Test-Path $environment.path) {
                    Remove-Item -Path $environment.path -Recurse -Force -ErrorAction Stop
                    Write-Verbose "Removed environment directory: $($environment.path)"
                }
                
                Write-Information "Successfully removed virtual environment '$Name'." -InformationAction Continue
                
            } catch {
                # Provide a detailed error message if any step fails
                Write-Error "Failed to remove virtual environment '$Name'. Error: $_"
            }
        }
    }
}
