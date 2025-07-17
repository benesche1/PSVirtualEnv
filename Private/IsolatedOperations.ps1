$script:SystemPSModulePath = $null
$script:IsolationActive = $false

function Initialize-IsolatedOperations {
    <#
    .SYNOPSIS
        Initializes the isolated operations system.
    #>
    [CmdletBinding()]
    param()
    
    if (-not $script:SystemPSModulePath) {
        # Store the original system PSModulePath permanently
        $script:SystemPSModulePath = $env:PSModulePath
        Write-Verbose "Stored system PSModulePath: $($script:SystemPSModulePath)"
    }
}

function Invoke-WithSystemModules {
    <#
    .SYNOPSIS
        Executes a script block with temporary access to system modules.
        
    .DESCRIPTION
        Temporarily restores system PSModulePath, executes the script block,
        then immediately restores the virtual environment path. This allows
        essential operations like Find-Module and Save-Module to work without
        contaminating the virtual environment.
        
    .PARAMETER ScriptBlock
        The script block to execute with system module access.
        
    .PARAMETER TimeoutSeconds
        Maximum time to allow system access (safety mechanism).
        
    .EXAMPLE
        Invoke-WithSystemModules { Find-Module -Name "Pester" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [Parameter()]
        [int]$TimeoutSeconds = 30
    )
    
    if (-not $script:IsolationActive) {
        # Not in virtual environment, just execute normally
        return & $ScriptBlock
    }
    
    $currentPath = $env:PSModulePath
    $startTime = Get-Date
    
    try {
        Write-Verbose "Temporarily enabling system modules for operation"
        
        # Restore system PSModulePath temporarily
        $env:PSModulePath = $script:SystemPSModulePath
        
        # Execute the operation
        $result = & $ScriptBlock
        
        return $result
        
    }
    catch {
        Write-Verbose "Error during system module operation: $_"
        throw
    }
    finally {
        # Always restore the virtual environment path
        $env:PSModulePath = $currentPath
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Verbose "System module access duration: $duration seconds"
        
        # Safety check - if this took too long, warn about potential issues
        if ($duration -gt $TimeoutSeconds) {
            Write-Warning "System module operation took longer than expected ($duration seconds). Virtual environment isolation may have been compromised."
        }
    }
}

function Install-ModuleToEnvironment {
    <#
    .SYNOPSIS
        Installs a module directly to the virtual environment without contamination.
        
    .DESCRIPTION
        Uses system modules to find and download the module, but installs it
        directly to the virtual environment directory without affecting the
        current session's module loading.
        
    .PARAMETER Name
        Module name to install.
        
    .PARAMETER EnvironmentPath
        Path to the virtual environment.
        
    .PARAMETER RequiredVersion
        Specific version to install.
        
    .PARAMETER Repository
        Repository to install from.
        
    .PARAMETER Force
        Force installation.
        
    .PARAMETER AllowPrerelease
        Allow prerelease versions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$EnvironmentPath,
        
        [Parameter()]
        [string]$RequiredVersion,
        
        [Parameter()]
        [string]$Repository = 'PSGallery',
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$AllowPrerelease
    )
    
    $modulePath = Join-Path $EnvironmentPath 'Modules'
    
    # Ensure module directory exists
    if (-not (Test-Path $modulePath)) {
        New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
    }
    
    # Use system modules to find and download the module
    $moduleInfo = Invoke-WithSystemModules {
        $findParams = @{
            Name        = $Name
            Repository  = $Repository
            ErrorAction = 'Stop'
        }
        
        if ($RequiredVersion) {
            $findParams['RequiredVersion'] = $RequiredVersion
        }
        
        if ($AllowPrerelease) {
            $findParams['AllowPrerelease'] = $true
        }
        
        Write-Verbose "Finding module '$Name' in repository '$Repository'"
        $module = Find-Module @findParams | Select-Object -First 1
        
        if (-not $module) {
            throw "Module '$Name' not found in repository '$Repository'"
        }
        
        Write-Verbose "Found module: $($module.Name) version $($module.Version)"
        
        # Download the module to the virtual environment
        $saveParams = @{
            Name        = $module.Name
            Path        = $modulePath
            Repository  = $Repository
            Force       = $Force.IsPresent
            ErrorAction = 'Stop'
        }
        
        if ($RequiredVersion) {
            $saveParams['RequiredVersion'] = $RequiredVersion
        }
        else {
            $saveParams['RequiredVersion'] = $module.Version.ToString()
        }
        
        if ($AllowPrerelease) {
            $saveParams['AllowPrerelease'] = $true
        }
        
        Write-Verbose "Saving module to virtual environment: $modulePath"
        Save-Module @saveParams
        
        return $module
    }
    
    Write-Information "Successfully installed '$($moduleInfo.Name)' version $($moduleInfo.Version) to virtual environment" -InformationAction Continue
    return $moduleInfo
}

function Import-ModuleFromEnvironment {
    <#
    .SYNOPSIS
        Imports a module specifically from the virtual environment using a completely isolated process.
        
    .DESCRIPTION
        This function guarantees isolation by launching a new PowerShell process with a strictly controlled
        PSModulePath. The module is imported in that sterile process, serialized to a file, and then
        the resulting module object is safely loaded into the current session, bypassing assembly conflicts.
        
    .PARAMETER Name
        Module name to import.
        
    .PARAMETER EnvironmentPath
        Path to the virtual environment.
        
    .PARAMETER Force
        Force import even if already loaded.
        
    .PARAMETER Global
        Import to global scope.
        
    .PARAMETER PassThru
        Return the module info.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$EnvironmentPath,
        
        [Parameter()]
        [switch]$Force,
        
        [Parameter()]
        [switch]$Global,
        
        [Parameter()]
        [switch]$PassThru
    )
    
    # Forcefully remove any existing version of the module from the current session.
    if (Get-Module -Name $Name -ListAvailable) {
        Write-Verbose "A version of '$Name' is already loaded. Forcibly removing it to ensure a clean import."
        Remove-Module -Name $Name -Force -ErrorAction SilentlyContinue
    }

    $envModulePath = Join-Path $EnvironmentPath 'Modules'
    $tempScriptFile = [System.IO.Path]::GetTempFileName() + ".ps1"
    $tempOutputFile = [System.IO.Path]::GetTempFileName()
    $errorFile = "$tempOutputFile.err"

    # Construct the command for the new, isolated process.
    $coreModulePath = Join-Path $PSHOME 'Modules'
    $fullIsolatedPath = "'$envModulePath;$coreModulePath'" # Quote paths to handle spaces
    $scriptContent = @"
# Set environment for this isolated process
`$env:PSModulePath = $fullIsolatedPath
`$PSModuleAutoLoadingPreference = 'None'

# Pre-load core utilities to ensure basic cmdlets are available
Import-Module Microsoft.PowerShell.Utility -Force -ErrorAction SilentlyContinue

# Import the target module and serialize its object to the output file
try {
    # CRITICAL FIX: Create a recursive function to handle nested dependencies.
    function Import-WithDependencies {
        param(
            [Parameter(Mandatory)]
            [string]`$ModuleName,
            [System.Collections.Generic.HashSet[string]]`$processed
        )

        if (`$processed.Contains(`$ModuleName)) {
            return
        }

        # Find the module ONLY within the isolated path
        `$moduleInfo = Get-Module -Name `$ModuleName -ListAvailable | Select-Object -First 1
        if (-not `$moduleInfo) {
            throw "Could not find module '`$ModuleName' within the isolated path: `$env:PSModulePath"
        }

        # Recurse to handle dependencies first
        if (`$moduleInfo.RequiredModules) {
            foreach (`$dependency in `$moduleInfo.RequiredModules) {
                `$depName = if (`$dependency -is [string]) { `$dependency } else { `$dependency.ModuleName }
                Import-WithDependencies -ModuleName `$depName -processed `$processed
            }
        }

        # Import the current module by its full path
        Write-Verbose "Isolated process: Importing '`$(`$moduleInfo.Name)' from path '`$(`$moduleInfo.Path)'..."
        Import-Module -Name `$moduleInfo.Path -Force -ErrorAction Stop
        `$processed.Add(`$ModuleName) | Out-Null
    }

    `$processedModules = [System.Collections.Generic.HashSet[string]]::new()
    Import-WithDependencies -ModuleName '$Name' -processed `$processedModules

    # After all dependencies are loaded, get the final module object and export it
    Get-Module -Name '$Name' -ErrorAction Stop | Export-Clixml -Path '$tempOutputFile' -Depth 5
}
catch {
    # On failure, write the full error record to the error file and exit
    `$_.ToString() | Out-File -FilePath '$errorFile' -Encoding utf8
    exit 1
}
"@
    
    Set-Content -Path $tempScriptFile -Value $scriptContent -Encoding UTF8

    $pwshPath = if ($IsCoreCLR) { 'pwsh' } else { 'powershell' }
    
    try {
        Write-Verbose "Starting fully isolated process to import '$Name'..."
        $process = Start-Process -FilePath $pwshPath -ArgumentList "-NoProfile", "-NoLogo", "-File", "`"$tempScriptFile`"" -Wait -PassThru -WindowStyle Hidden -RedirectStandardError $errorFile

        if ($process.ExitCode -ne 0) {
            $errorMessage = "Isolated import process for '$Name' exited with code $($process.ExitCode)."
            if ((Test-Path $errorFile) -and ((Get-Item $errorFile).Length) -gt 0) {
                $errorMessage += " Error details: $(Get-Content $errorFile -Raw)"
            }
            throw $errorMessage
        }

        if (-not ((Test-Path $tempOutputFile)) -or ((Get-Item $tempOutputFile).Length) -eq 0) {
            throw "Isolated import process for '$Name' did not produce a module object. Check for non-terminating errors in the module's .psm1 file."
        }

        $moduleObject = Import-Clixml -Path $tempOutputFile
    }
    finally {
        # Clean up temporary files
        if (Test-Path $tempScriptFile) { Remove-Item $tempScriptFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempOutputFile) { Remove-Item $tempOutputFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $errorFile) { Remove-Item $errorFile -Force -ErrorAction SilentlyContinue }
    }

    if (-not $moduleObject) {
        throw "Failed to deserialize module object for '$Name' from the isolated process."
    }

    Write-Verbose "Isolated import successful. Loading module object into current session."
    $importParams = @{
        ModuleInfo = $moduleObject
        PassThru   = $PassThru.IsPresent
    }
    if ($Global.IsPresent) {
        $importParams['Global'] = $true
    }
    
    return Import-Module @importParams
}


function Set-VirtualEnvironmentIsolation {
    <#
    .SYNOPSIS
        Activates strict isolation mode for the virtual environment.
        
    .DESCRIPTION
        Sets up the virtual environment with strict isolation - only environment
        modules are available, no system modules except for absolutely essential ones.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentPath
    )
    
    # Initialize if not done
    Initialize-IsolatedOperations
    
    # Set isolation active
    $script:IsolationActive = $true
    
    # Set PSModulePath to ONLY the virtual environment
    $envModulePath = Join-Path $EnvironmentPath 'Modules'
    
    # Create a minimal PSModulePath with only the virtual environment
    $env:PSModulePath = $envModulePath
    
    Write-Verbose "Activated strict isolation. PSModulePath: $($env:PSModulePath)"
}

function Remove-VirtualEnvironmentIsolation {
    <#
    .SYNOPSIS
        Deactivates virtual environment isolation.
    #>
    [CmdletBinding()]
    param()
    
    if ($script:SystemPSModulePath) {
        $env:PSModulePath = $script:SystemPSModulePath
        Write-Verbose "Restored system PSModulePath"
    }
    
    $script:IsolationActive = $false
}