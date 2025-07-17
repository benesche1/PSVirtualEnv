function Test-EnvironmentName {
    <#
    .SYNOPSIS
        Validates an environment name.
    
    .DESCRIPTION
        Checks if the environment name is valid and doesn't conflict with existing environments.
    
    .PARAMETER Name
        The name to validate.
    
    .PARAMETER CheckExists
        Whether to check if the environment already exists.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$CheckExists
    )
    
    # Check for invalid characters
    if ($Name -match '[<>:"/\\|?*]') {
        Write-Error "Environment name contains invalid characters. Please use only letters, numbers, hyphens, and underscores."
        return $false
    }
    
    # Check length
    if ($Name.Length -lt 1 -or $Name.Length -gt 50) {
        Write-Error "Environment name must be between 1 and 50 characters."
        return $false
    }
    
    # Check if exists
    if ($CheckExists) {
        $registry = Get-EnvironmentRegistry
        if ($registry | Where-Object { $_.name -eq $Name }) {
            Write-Error "Environment '$Name' already exists. Use -Force to overwrite."
            return $false
        }
    }
    
    return $true
}

function Test-EnvironmentPath {
    <#
    .SYNOPSIS
        Validates an environment path.
    
    .DESCRIPTION
        Checks if the path is valid for creating an environment.
    
    .PARAMETER Path
        The path to validate.
    
    .PARAMETER CreateIfNotExist
        Whether to create the path if it doesn't exist.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [switch]$CreateIfNotExist
    )
    
    try {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        
        if (Test-Path $resolvedPath) {
            $item = Get-Item $resolvedPath
            if (-not $item.PSIsContainer) {
                Write-Error "Path '$Path' exists but is not a directory."
                return $false
            }
            
            # Check if directory is empty
            if ((Get-ChildItem $resolvedPath -Force | Measure-Object).Count -gt 0) {
                Write-Error "Directory '$Path' is not empty. Use -Force to overwrite."
                return $false
            }
        } elseif ($CreateIfNotExist) {
            try {
                New-Item -Path $resolvedPath -ItemType Directory -Force | Out-Null
            } catch {
                Write-Error "Failed to create directory '$Path': $_"
                return $false
            }
        } else {
            Write-Error "Path '$Path' does not exist."
            return $false
        }
        
        return $true
    } catch {
        Write-Error "Invalid path '$Path': $_"
        return $false
    }
}

function Test-EnvironmentActive {
    <#
    .SYNOPSIS
        Checks if a virtual environment is currently active.
    
    .DESCRIPTION
        Returns true if an environment is active, false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    return $null -ne $script:ActiveEnvironment
}

function Get-ActiveEnvironment {
    <#
    .SYNOPSIS
        Gets the currently active environment.
    
    .DESCRIPTION
        Returns the active environment object or null if none is active.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    return $script:ActiveEnvironment
}