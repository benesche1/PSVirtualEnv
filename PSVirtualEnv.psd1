# PSVirtualEnv/PSVirtualEnv.psd1
@{
    # Module manifest for PSVirtualEnv
    RootModule = 'PSVirtualEnv.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a8b9c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d'
    Author = 'PSVirtualEnv Development Team'
    CompanyName = 'Community'
    Copyright = '(c) 2024 PSVirtualEnv Development Team. All rights reserved.'
    Description = 'PowerShell Virtual Environment Manager - Create isolated PowerShell module environments'
    PowerShellVersion = '5.1'
    
    # Scripts to run before module import. This is the correct place to load classes. Gemini suggestion
    ScriptsToProcess = @('Classes\PSVirtualEnvironment.ps1')


    # Functions to export
    FunctionsToExport = @(
        'New-PSVirtualEnv',
        'Remove-PSVirtualEnv',
        'Activate-PSVirtualEnv',
        'Deactivate-PSVirtualEnv',
        'Get-PSVirtualEnv',
        'Install-PSModuleInEnv',
        'Uninstall-PSModuleInEnv',
        'Get-PSModuleInEnv',
        'Update-PSModuleInEnv'
    )
    
    # Cmdlets to export
    CmdletsToExport = @()
    
    # Variables to export
    VariablesToExport = @()
    
    # Aliases to export
    AliasesToExport = @()
    
    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('VirtualEnvironment', 'ModuleManagement', 'Development', 'Isolation')
            LicenseUri = 'https://github.com/psvirtualenv/psvirtualenv/blob/main/LICENSE'
            ProjectUri = 'https://github.com/psvirtualenv/psvirtualenv'
            IconUri = ''
            ReleaseNotes = 'Initial release of PSVirtualEnv module'
        }
    }
}