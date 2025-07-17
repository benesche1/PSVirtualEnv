# Module variables
$script:ActiveEnvironment = $null
$script:OriginalPSModulePath = $null
$script:OriginalPromptFunction = $null
$script:RegistryPath = $null

# Set cross-platform home directory
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -eq 'Unix') {
    $script:PSVirtualEnvHome = Join-Path $HOME '.psvirtualenv'
} else {
    $script:PSVirtualEnvHome = Join-Path $env:USERPROFILE '.psvirtualenv'
}

# Import classes first (before using them)
#. $PSScriptRoot\Classes\PSVirtualEnvironment.ps1

# Import private functions
Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# Import public functions and collect their names
$publicFunctions = @()
Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
    # Extract function name from file name
    $publicFunctions += [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
}

# Initialize module
if (-not (Test-Path $script:PSVirtualEnvHome)) {
    New-Item -Path $script:PSVirtualEnvHome -ItemType Directory -Force | Out-Null
}

$script:RegistryPath = Join-Path $script:PSVirtualEnvHome 'registry.json'
if (-not (Test-Path $script:RegistryPath)) {
    @() | ConvertTo-Json | Set-Content -Path $script:RegistryPath -Encoding UTF8
}

# Export module members - use the actual function names
Export-ModuleMember -Function $publicFunctions