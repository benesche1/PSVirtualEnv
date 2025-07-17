class PSVirtualEnvironment {
    [string]$Name
    [string]$Path
    [datetime]$Created
    [string]$Description
    [bool]$IsActive
    [hashtable]$Settings
    [System.Collections.ArrayList]$Modules

    # Constructor for creating a NEW environment.
    PSVirtualEnvironment([string]$name, [string]$path) {
        $this.Name = $name
        $this.Path = $path
        $this.Created = Get-Date
        $this.IsActive = $false
        $this.Modules = [System.Collections.ArrayList]::new()
        $this.Settings = @{
            includeSystemModules = $false
            autoActivate = $false
        }
    }

    # Private, parameterless constructor for internal use (e.g., deserialization).
    PSVirtualEnvironment() {}

    [void] AddModule([string]$name, [string]$version) {
        $moduleInfo = @{
            name = $name
            version = $version
            installed = Get-Date
        }
        $this.Modules.Add($moduleInfo) | Out-Null
    }

    [void] RemoveModule([string]$name) {
        $modulesToKeep = [System.Collections.ArrayList]::new()
        foreach ($module in $this.Modules) {
            if ($module.name -ne $name) {
                $modulesToKeep.Add($module) | Out-Null
            }
        }
        $this.Modules = $modulesToKeep
    }

    [hashtable] ToHashtable() {
        $output = @{
            name        = $this.Name
            path        = $this.Path
            created     = $this.Created.ToString('o') # Culture-independent round-trip format
            description = $this.Description
            modules     = [System.Collections.ArrayList]::new($this.Modules)
            settings    = [hashtable]::new()
        }
        
        if ($null -ne $this.Settings) {
            $this.Settings.GetEnumerator() | ForEach-Object {
                $output.settings[$_.Name] = $_.Value
            }
        }
        
        return $output
    }

    static [PSVirtualEnvironment] FromHashtable([hashtable]$data) {
        # Use the private constructor to create a blank object.
        $env = [PSVirtualEnvironment]::new()
        $env.Name = $data.name
        $env.Path = $data.path
        $env.Created = [datetime]$data.created
        $env.Description = $data.description
        
        $env.Settings = [hashtable]::new()
        if ($null -ne $data.settings) {
            # FIX: Use GetEnumerator() which works reliably on both Hashtable and PSCustomObject types.
            # This prevents type ambiguity across different PowerShell versions and is the most
            # robust way to iterate through key-value pairs.
            $data.settings.GetEnumerator() | ForEach-Object {
                $env.Settings[$_.Name] = $_.Value
            }
        }
        
        $env.Modules = [System.Collections.ArrayList]::new()
        if ($data.modules) {
            foreach ($module in $data.modules) {
                $env.Modules.Add([hashtable]$module) | Out-Null
            }
        }
        return $env
    }
}
