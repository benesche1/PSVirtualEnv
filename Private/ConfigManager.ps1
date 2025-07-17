# This helper function recursively converts a PSCustomObject (from ConvertFrom-Json)
# into a proper Hashtable, which prevents the "duplicate key" error.
function Convert-PSCustomObjectToHashtable {
    param($object)

    # Handle arrays of objects
    if ($object -is [System.Collections.IEnumerable] -and $object -isnot [string]) {
        $collection = [System.Collections.ArrayList]::new()
        foreach ($item in $object) {
            $null = $collection.Add((Convert-PSCustomObjectToHashtable -object $item))
        }
        return $collection
    }

    # Handle nested objects
    if ($object -is [psobject] -and $object.GetType().Name -eq 'PSCustomObject') {
        $hash = [hashtable]::new()
        foreach ($property in $object.PSObject.Properties) {
            $hash[$property.Name] = (Convert-PSCustomObjectToHashtable -object $property.Value)
        }
        return $hash
    }

    # Return primitive types as-is
    return $object
}

function Get-EnvironmentRegistry {
    <#
    .SYNOPSIS
        Gets the global environment registry.
    
    .DESCRIPTION
        Reads and returns the global registry of all virtual environments.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param()
    
    $registryPath = $script:RegistryPath
    
    if (Test-Path $registryPath) {
        try {
            $content = Get-Content -Path $registryPath -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($content)) {
                return @()
            }
            
            $jsonData = $content | ConvertFrom-Json
            
            # Use the robust, recursive helper function to guarantee a true
            # hashtable structure, which is critical for PowerShell 5.1.
            return (Convert-PSCustomObjectToHashtable -object $jsonData)
            
        } catch {
            Write-Warning "Failed to read environment registry: $_"
            return @()
        }
    }
    
    return @()
}

function Set-EnvironmentRegistry {
    <#
    .SYNOPSIS
        Sets the global environment registry.
    
    .DESCRIPTION
        Writes the global registry of all virtual environments.
    
    .PARAMETER Registry
        The registry data to write.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.ArrayList]$Registry
    )
    
    try {
        $Registry | ConvertTo-Json -Depth 10 | Set-Content -Path $script:RegistryPath -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Error "Failed to write environment registry: $_"
    }
}

function Add-EnvironmentToRegistry {
    <#
    .SYNOPSIS
        Adds an environment to the global registry.
    
    .PARAMETER Environment
        The environment object to add.
    #>
    [CmdletBinding()]
    param(
        # FIX: Removed the [PSVirtualEnvironment] type constraint to prevent the scoping/type conversion error.
        # The object will still contain all the correct properties and methods.
        [Parameter(Mandatory)]
        $Environment
    )
    
    $registry = Get-EnvironmentRegistry
    
    # Remove existing entry if present
    $registry = [System.Collections.ArrayList]($registry | Where-Object { $_.name -ne $Environment.Name })
    
    # Add new entry
    $null = $registry.Add($Environment.ToHashtable())
    
    Set-EnvironmentRegistry -Registry $registry
}

function Remove-EnvironmentFromRegistry {
    <#
    .SYNOPSIS
        Removes an environment from the global registry.
    
    .PARAMETER Name
        The name of the environment to remove.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    $registry = Get-EnvironmentRegistry
    $updatedRegistry = [System.Collections.ArrayList]($registry | Where-Object { $_.name -ne $Name })
    Set-EnvironmentRegistry -Registry $updatedRegistry
}

function Get-EnvironmentFromRegistry {
    <#
    .SYNOPSIS
        Gets a specific environment from the registry by name.
    
    .PARAMETER Name
        The name of the environment to retrieve.
    #>
    [CmdletBinding()]
    [OutputType([PSVirtualEnvironment])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    $registry = Get-EnvironmentRegistry
    $envData = $registry | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    
    if ($envData) {
        # Ensure the data passed is a hashtable
        return [PSVirtualEnvironment]::FromHashtable([hashtable]$envData)
    }
    
    return $null
}

function Get-EnvironmentConfig {
    <#
    .SYNOPSIS
        Gets the configuration for a specific environment.
    
    .PARAMETER Path
        The path to the environment.
    #>
    [CmdletBinding()]
    [OutputType([PSVirtualEnvironment])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $configPath = Join-Path $Path 'config.json'
    
    if (Test-Path $configPath) {
        try {
            $content = Get-Content -Path $configPath -Raw -ErrorAction Stop
            $jsonData = $content | ConvertFrom-Json
            
            # Use the same robust conversion for individual config files
            $data = Convert-PSCustomObjectToHashtable -object $jsonData
            return [PSVirtualEnvironment]::FromHashtable($data)
        } catch {
            Write-Error "Failed to read environment configuration: $_"
            return $null
        }
    }
    
    return $null
}

function Set-EnvironmentConfig {
    <#
    .SYNOPSIS
        Sets the configuration for a specific environment.
    
    .PARAMETER Environment
        The environment object to save.
    #>
    [CmdletBinding()]
    param(
        # FIX: Removed the [PSVirtualEnvironment] type constraint to prevent the scoping/type conversion error.
        [Parameter(Mandatory)]
        $Environment
    )
    
    $configPath = Join-Path $Environment.Path 'config.json'
    
    try {
        $Environment.ToHashtable() | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Error "Failed to write environment configuration: $_"
    }
}
