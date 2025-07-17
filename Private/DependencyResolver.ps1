class ModuleDependency {
    [string]$Name
    [version]$RequiredVersion
    [version]$MinimumVersion
    [version]$MaximumVersion
    [string]$ModulePath
    [string]$ManifestPath
    [array]$Dependencies
    [array]$RequiredAssemblies
    [hashtable]$AssemblyInfo
    [int]$DependencyDepth
    [bool]$IsResolved
    [string]$ConflictReason
}

class AssemblyConflict {
    [string]$AssemblyName
    [version]$LoadedVersion
    [version]$RequiredVersion
    [string]$LoadedPath
    [string]$RequiredPath
    [string]$PublicKeyToken
    [string]$ConflictType
}

function Get-ModuleDependencyTree {
    <#
    .SYNOPSIS
        Analyzes a module and builds a complete dependency tree.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter(Mandatory)]
        [string]$EnvironmentPath,
        
        [Parameter()]
        [int]$MaxDepth = 10
    )
    
    $visited = @{}
    $allDependencies = @{}
    
    function Analyze-ModuleRecursive {
        param(
            [string]$Name,
            [string]$EnvPath,
            [int]$Depth = 0,
            [string]$ParentModule = ""
        )
        
        if ($Depth -gt $MaxDepth) {
            Write-Warning "Maximum dependency depth reached for module '$Name'. Possible circular dependency."
            return $null
        }
        
        $key = "$Name-$Depth"
        if ($visited.ContainsKey($key)) {
            return $visited[$key]
        }
        
        Write-Verbose "Analyzing module: $Name (depth: $Depth, parent: $ParentModule)"
        
        # Find module in environment
        $modulePath = Join-Path $EnvPath 'Modules'
        $moduleDir = Join-Path $modulePath $Name
        
        if (-not (Test-Path $moduleDir)) {
            Write-Warning "Module '$Name' not found in environment. Required by: $ParentModule"
            return $null
        }
        
        # Find module manifest
        $manifestPath = $null
        $versionDirs = Get-ChildItem -Path $moduleDir -Directory -ErrorAction SilentlyContinue | 
                      Sort-Object -Property { [version]$_.Name } -Descending -ErrorAction SilentlyContinue
        
        foreach ($versionDir in $versionDirs) {
            $testManifest = Join-Path $versionDir.FullName "$Name.psd1"
            if (Test-Path $testManifest) {
                $manifestPath = $testManifest
                break
            }
        }
        
        if (-not $manifestPath) {
            $testManifest = Join-Path $moduleDir "$Name.psd1"
            if (Test-Path $testManifest) {
                $manifestPath = $testManifest
            }
        }
        
        if (-not $manifestPath) {
            Write-Warning "No manifest found for module '$Name'"
            return $null
        }
        
        # Parse manifest
        try {
            $manifest = Import-PowerShellDataFile -Path $manifestPath
        } catch {
            Write-Warning "Failed to parse manifest for '$Name': $_"
            return $null
        }
        
        # Create dependency object
        $dependency = [ModuleDependency]@{
            Name = $Name
            ModulePath = (Split-Path $manifestPath -Parent)
            ManifestPath = $manifestPath
            DependencyDepth = $Depth
            IsResolved = $false
            Dependencies = @()
            RequiredAssemblies = @()
            AssemblyInfo = @{}
        }
        
        # Extract version requirements
        if ($manifest.ModuleVersion) {
            $dependency.RequiredVersion = [version]$manifest.ModuleVersion
        }
        
        # Extract required assemblies
        if ($manifest.RequiredAssemblies) {
            $dependency.RequiredAssemblies = $manifest.RequiredAssemblies
            $dependency.AssemblyInfo = Get-AssemblyInformation -AssemblyPaths $manifest.RequiredAssemblies -ModulePath $dependency.ModulePath
        }
        
        $visited[$key] = $dependency
        $allDependencies[$Name] = $dependency
        
        # Analyze required modules
        if ($manifest.RequiredModules) {
            foreach ($reqModule in $manifest.RequiredModules) {
                $reqName = if ($reqModule -is [string]) { $reqModule } else { $reqModule.ModuleName }
                
                Write-Verbose "  Found required module: $reqName"
                $childDep = Analyze-ModuleRecursive -Name $reqName -EnvPath $EnvPath -Depth ($Depth + 1) -ParentModule $Name
                if ($childDep) {
                    $dependency.Dependencies += $childDep
                }
            }
        }
        
        # Analyze nested modules
        if ($manifest.NestedModules) {
            foreach ($nestedModule in $manifest.NestedModules) {
                $nestedName = if ($nestedModule -is [string]) { 
                    [System.IO.Path]::GetFileNameWithoutExtension($nestedModule)
                } else { 
                    $nestedModule.ModuleName 
                }
                
                Write-Verbose "  Found nested module: $nestedName"
                # Nested modules are typically in the same directory, so check locally first
                $localNested = Join-Path $dependency.ModulePath "$nestedName.psd1"
                if (Test-Path $localNested) {
                    # Parse local nested module
                    try {
                        $nestedManifest = Import-PowerShellDataFile -Path $localNested
                        if ($nestedManifest.RequiredModules) {
                            foreach ($reqModule in $nestedManifest.RequiredModules) {
                                $reqName = if ($reqModule -is [string]) { $reqModule } else { $reqModule.ModuleName }
                                $childDep = Analyze-ModuleRecursive -Name $reqName -EnvPath $EnvPath -Depth ($Depth + 1) -ParentModule "$Name (nested: $nestedName)"
                                if ($childDep) {
                                    $dependency.Dependencies += $childDep
                                }
                            }
                        }
                    } catch {
                        Write-Verbose "Could not parse nested module manifest: $localNested"
                    }
                }
            }
        }
        
        return $dependency
    }
    
    $rootDependency = Analyze-ModuleRecursive -Name $ModuleName -EnvPath $EnvironmentPath
    
    return @{
        RootModule = $rootDependency
        AllDependencies = $allDependencies
        DependencyCount = $allDependencies.Count
    }
}

function Get-AssemblyInformation {
    <#
    .SYNOPSIS
        Extracts detailed information about assemblies.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$AssemblyPaths,
        
        [Parameter(Mandatory)]
        [string]$ModulePath
    )
    
    $assemblyInfo = @{}
    
    foreach ($assemblyPath in $AssemblyPaths) {
        try {
            # Resolve relative paths
            $fullPath = if ([System.IO.Path]::IsPathRooted($assemblyPath)) {
                $assemblyPath
            } else {
                Join-Path $ModulePath $assemblyPath
            }
            
            if (Test-Path $fullPath) {
                $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($fullPath)
                $name = $assembly.GetName()
                
                $assemblyInfo[$assembly.GetName().Name] = @{
                    FullName = $assembly.FullName
                    Version = $name.Version
                    PublicKeyToken = if ($name.GetPublicKeyToken()) { 
                        [System.BitConverter]::ToString($name.GetPublicKeyToken()).Replace('-', '').ToLower()
                    } else { 
                        $null 
                    }
                    Location = $fullPath
                    LoadedAssembly = $null
                }
            }
        } catch {
            Write-Verbose "Could not analyze assembly '$assemblyPath': $_"
        }
    }
    
    return $assemblyInfo
}

function Test-AssemblyConflicts {
    <#
    .SYNOPSIS
        Detects assembly conflicts between loaded and required assemblies.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DependencyTree
    )
    
    $conflicts = @()
    $loadedAssemblies = [System.AppDomain]::CurrentDomain.GetAssemblies()
    
    foreach ($module in $DependencyTree.AllDependencies.Values) {
        foreach ($assemblyName in $module.AssemblyInfo.Keys) {
            $requiredAssembly = $module.AssemblyInfo[$assemblyName]
            
            # Find if this assembly is already loaded
            $loadedAssembly = $loadedAssemblies | Where-Object { 
                $_.GetName().Name -eq $assemblyName 
            } | Select-Object -First 1
            
            if ($loadedAssembly) {
                $loadedName = $loadedAssembly.GetName()
                $requiredVersion = $requiredAssembly.Version
                $loadedVersion = $loadedName.Version
                
                # Check version conflict
                if ($loadedVersion -ne $requiredVersion) {
                    $conflict = [AssemblyConflict]@{
                        AssemblyName = $assemblyName
                        LoadedVersion = $loadedVersion
                        RequiredVersion = $requiredVersion
                        LoadedPath = $loadedAssembly.Location
                        RequiredPath = $requiredAssembly.Location
                        ConflictType = "VersionMismatch"
                    }
                    
                    # Check public key token if available
                    $loadedToken = if ($loadedName.GetPublicKeyToken()) {
                        [System.BitConverter]::ToString($loadedName.GetPublicKeyToken()).Replace('-', '').ToLower()
                    } else { $null }
                    
                    $requiredToken = $requiredAssembly.PublicKeyToken
                    
                    if ($loadedToken -ne $requiredToken) {
                        $conflict.ConflictType = "PublicKeyMismatch"
                    }
                    
                    $conflict.PublicKeyToken = "Loaded: $loadedToken, Required: $requiredToken"
                    $conflicts += $conflict
                    
                    Write-Warning "Assembly conflict detected: $assemblyName"
                    Write-Warning "  Loaded: v$loadedVersion from $($loadedAssembly.Location)"
                    Write-Warning "  Required: v$requiredVersion from $($requiredAssembly.Location)"
                }
            }
        }
    }
    
    return $conflicts
}

function Resolve-DependencyConflicts {
    <#
    .SYNOPSIS
        Attempts to resolve dependency conflicts by analyzing the dependency tree.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DependencyTree
    )
    
    Write-Information "Analyzing dependency conflicts..." -InformationAction Continue
    
    # Test for assembly conflicts
    $assemblyConflicts = Test-AssemblyConflicts -DependencyTree $DependencyTree
    
    if ($assemblyConflicts.Count -gt 0) {
        Write-Warning "Found $($assemblyConflicts.Count) assembly conflicts:"
        foreach ($conflict in $assemblyConflicts) {
            Write-Warning "  $($conflict.AssemblyName): Loaded v$($conflict.LoadedVersion), Required v$($conflict.RequiredVersion)"
        }
        
        # Provide suggestions
        Write-Information "`nSuggested resolution steps:" -InformationAction Continue
        Write-Information "1. Remove conflicting modules from current session:" -InformationAction Continue
        
        $conflictingModules = @()
        foreach ($conflict in $assemblyConflicts) {
            $loadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() | 
                Where-Object { $_.GetName().Name -eq $conflict.AssemblyName } | 
                Select-Object -First 1
            
            if ($loadedAssembly.Location) {
                $moduleName = Split-Path (Split-Path $loadedAssembly.Location -Parent) -Leaf
                $conflictingModules += $moduleName
            }
        }
        
        $uniqueModules = $conflictingModules | Select-Object -Unique
        foreach ($module in $uniqueModules) {
            Write-Information "   Remove-Module '$module' -Force" -InformationAction Continue
        }
        
        Write-Information "2. Restart PowerShell session for clean state" -InformationAction Continue
        Write-Information "3. Install required versions in virtual environment:" -InformationAction Continue
        
        foreach ($conflict in $assemblyConflicts) {
            $requiredModule = $DependencyTree.AllDependencies.Values | 
                Where-Object { $_.AssemblyInfo.ContainsKey($conflict.AssemblyName) } | 
                Select-Object -First 1
            
            if ($requiredModule) {
                Write-Information "   Install-PSModuleInEnv '$($requiredModule.Name)' -RequiredVersion '$($requiredModule.RequiredVersion)'" -InformationAction Continue
            }
        }
        
        return @{
            Success = $false
            Conflicts = $assemblyConflicts
            LoadOrder = @()
            SuggestedActions = $uniqueModules
        }
    }
    
    # Build load order (deepest dependencies first)
    $loadOrder = Get-ModuleLoadOrder -DependencyTree $DependencyTree
    
    return @{
        Success = $true
        Conflicts = @()
        LoadOrder = $loadOrder
        SuggestedActions = @()
    }
}

function Get-ModuleLoadOrder {
    <#
    .SYNOPSIS
        Determines the correct loading order for modules based on dependency depth.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DependencyTree
    )
    
    # Sort by dependency depth (deepest first), then by name for consistency
    $sortedModules = $DependencyTree.AllDependencies.Values | 
        Sort-Object @{Expression = "DependencyDepth"; Descending = $true}, Name
    
    Write-Information "Determined load order:" -InformationAction Continue
    for ($i = 0; $i -lt $sortedModules.Count; $i++) {
        $module = $sortedModules[$i]
        Write-Information "  $($i + 1). $($module.Name) (depth: $($module.DependencyDepth))" -InformationAction Continue
    }
    
    return $sortedModules
}

function Import-ModuleWithDependencies {
    <#
    .SYNOPSIS
        Imports a module and all its dependencies in the correct order using exact paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [Parameter(Mandatory)]
        [string]$EnvironmentPath,
        
        [Parameter()]
        [switch]$Force
    )
    
    Write-Information "Starting dependency-resolved import of '$ModuleName'..." -InformationAction Continue
    
    # Step 1: Analyze dependencies
    Write-Information "Step 1: Analyzing dependency tree..." -InformationAction Continue
    $dependencyTree = Get-ModuleDependencyTree -ModuleName $ModuleName -EnvironmentPath $EnvironmentPath
    
    if (-not $dependencyTree.RootModule) {
        throw "Failed to analyze dependencies for module '$ModuleName'"
    }
    
    Write-Information "Found $($dependencyTree.DependencyCount) total dependencies" -InformationAction Continue
    
    # Step 2: Resolve conflicts
    Write-Information "Step 2: Checking for conflicts..." -InformationAction Continue
    $resolution = Resolve-DependencyConflicts -DependencyTree $dependencyTree
    
    if (-not $resolution.Success) {
        throw "Dependency conflicts detected. Please resolve conflicts and try again."
    }
    
    # Step 3: Load modules in correct order
    Write-Information "Step 3: Loading modules in dependency order..." -InformationAction Continue
    
    $loadedModules = @()
    $failed = @()
    
    foreach ($module in $resolution.LoadOrder) {
        try {
            Write-Information "Loading: $($module.Name)" -InformationAction Continue
            
            # Import by exact manifest path to avoid auto-loading
            $importResult = Import-ModuleByExactPath -ManifestPath $module.ManifestPath -Force:$Force
            
            if ($importResult) {
                $loadedModules += $module.Name
                Write-Verbose "Successfully loaded: $($module.Name)"
            }
            
        } catch {
            $failed += @{
                Module = $module.Name
                Error = $_
            }
            Write-Warning "Failed to load $($module.Name): $_"
        }
    }
    
    Write-Information "Import completed:" -InformationAction Continue
    Write-Information "  Loaded: $($loadedModules.Count) modules" -InformationAction Continue
    Write-Information "  Failed: $($failed.Count) modules" -InformationAction Continue
    
    if ($failed.Count -gt 0) {
        Write-Warning "Some modules failed to load:"
        foreach ($failure in $failed) {
            Write-Warning "  $($failure.Module): $($failure.Error)"
        }
    }
    
    return @{
        LoadedModules = $loadedModules
        FailedModules = $failed
        Success = ($failed.Count -eq 0)
    }
}

function Import-ModuleByExactPath {
    <#
    .SYNOPSIS
        Imports a module by its exact manifest path, bypassing auto-loading.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,
        
        [Parameter()]
        [switch]$Force
    )
    
    if (-not (Test-Path $ManifestPath)) {
        throw "Module manifest not found: $ManifestPath"
    }
    
    # Store current state
    $currentPath = $env:PSModulePath
    $currentAutoLoading = $PSModuleAutoLoadingPreference
    
    try {
        # Disable auto-loading and restrict path
        $PSModuleAutoLoadingPreference = 'None'
        $env:PSModulePath = Split-Path $ManifestPath -Parent
        
        # Import by exact path
        $importParams = @{
            Name = $ManifestPath
            Force = $Force.IsPresent
            PassThru = $true
            ErrorAction = 'Stop'
        }
        
        $result = Import-Module @importParams
        return $result
        
    } finally {
        # Restore state
        $PSModuleAutoLoadingPreference = $currentAutoLoading
        $env:PSModulePath = $currentPath
    }
}