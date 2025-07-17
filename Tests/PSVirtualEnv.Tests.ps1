# PSVirtualEnv/Tests/PSVirtualEnv.Tests.ps1
#Requires -Module Pester

BeforeAll {

    $ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'PSVirtualEnv.psd1'
    $ModuleDir = Split-Path -Path $ModulePath -Parent 
    

    # Explicitly dot-source the class file BEFORE importing the module.
    # This ensures the [PSVirtualEnvironment] type is always available to the Pester test runner,
    # preventing "Unable to find type" errors in isolated test scopes.
    . (Join-Path $ModuleDir 'Classes\PSVirtualEnvironment.ps1')

    # Now, import the module itself
    Import-Module $ModulePath -Force
    
    # Set up a unique, temporary path for all test environments
    $script:TestEnvironmentPath = Join-Path $env:TEMP "PSVirtualEnvTests_$(New-Guid)"
    $script:BaseTestEnvironmentName = "TestEnv_$(Get-Random -Maximum 9999)"
    $script:RegistryPath = Join-Path $script:TestEnvironmentPath 'registry.json'

    # Store original values to restore later
    $script:OriginalPSModulePath = $env:PSModulePath
    
    # Mock the home directory to redirect .psvirtualenv to our temporary test path
    Mock -ModuleName PSVirtualEnv Join-Path -ParameterFilter {
        $Path -eq $env:USERPROFILE -and $ChildPath -eq '.psvirtualenv'
    } -MockWith {
        return $script:TestEnvironmentPath
    }
}

AfterAll {
    # Clean up the entire test environment directory
    if (Test-Path $script:TestEnvironmentPath) {
        Remove-Item -Path $script:TestEnvironmentPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Restore original environment state
    $env:PSModulePath = $script:OriginalPSModulePath
    
    # Remove the module from the session
    Remove-Module PSVirtualEnv -Force -ErrorAction SilentlyContinue
}

Describe 'PSVirtualEnv Module' {
    Context 'Module Import' {
        It 'Should import successfully' {
            Get-Module PSVirtualEnv | Should -Not -BeNullOrEmpty
        }
        
        It 'Should export only the expected commands' {
            $commands = Get-Command -Module PSVirtualEnv
            $expectedCommands = @(
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
            
            ($commands.Name | Sort-Object) | Should -Be ($expectedCommands | Sort-Object)
        }
    }
}

Describe 'New-PSVirtualEnv' {
    # This block runs before each test in this 'Describe' block
    BeforeEach {
        # Ensure the parent test directory exists and the registry is clean
        if (-not (Test-Path $script:TestEnvironmentPath)) {
            New-Item -Path $script:TestEnvironmentPath -ItemType Directory -Force | Out-Null
        }
        @() | ConvertTo-Json | Set-Content -Path $script:RegistryPath -Encoding UTF8
    }
    
    # FIX: This block now cleans up all created environments after each test,
    # ensuring test isolation.
    AfterEach {
        $envPath = Join-Path $script:TestEnvironmentPath '*'
        if (Test-Path $envPath) {
            Get-ChildItem -Path $envPath | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context 'Creating new environments' {
        It 'Should create a new environment with default settings' {
            $testName = "$($script:BaseTestEnvironmentName)_Default"
            $result = New-PSVirtualEnv -Name $testName
            
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $testName
            $result.Path | Should -BeLike "*$testName"
            Test-Path $result.Path | Should -BeTrue
            Test-Path (Join-Path $result.Path 'Modules') | Should -BeTrue
        }
        
        It 'Should create environment with custom description' {
            $testName = "$($script:BaseTestEnvironmentName)_Description"
            $description = "Test environment for Pester"
            $result = New-PSVirtualEnv -Name $testName -Description $description
            
            $result.Description | Should -Be $description
        }
        
        It 'Should fail when environment already exists without Force' {
            $testName = "$($script:BaseTestEnvironmentName)_Exists"
            New-PSVirtualEnv -Name $testName # Create it once
            
            $expectedErrorMessage = "Environment '$testName' already exists. Use -Force to overwrite."
            { New-PSVirtualEnv -Name $testName -ErrorAction Stop } | Should -Throw $expectedErrorMessage
        }
        
        It 'Should overwrite existing environment with Force' {
            $testName = "$($script:BaseTestEnvironmentName)_Force"
            New-PSVirtualEnv -Name $testName # Create it once
            
            $result = $null
            { $result = New-PSVirtualEnv -Name $testName -Force } | Should -Not -Throw
            #$result | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Activate-PSVirtualEnv and Deactivate-PSVirtualEnv' {


    BeforeAll {

        # Define variables specific to this test block for better isolation.
        $script:activationTestName = "$($script:BaseTestEnvironmentName)_ActivDeactiv"
        $script:activationTestPath = "$($script:TestEnvironmentPath)/$($activationTestName)"
        # Create a dedicated environment for this test block.
        New-PSVirtualEnv -Name $activationTestName -Force
        $script:OriginalPrompt = (Get-Command prompt -ErrorAction SilentlyContinue).ScriptBlock
    }
    
    AfterAll {
        # Clean up the dedicated environment.
        Deactivate-PSVirtualEnv -ErrorAction SilentlyContinue
        Remove-PSVirtualEnv -Name $script:activationTestName -Force
        if ($script:OriginalPrompt) {
            Set-Item -Path function:prompt -Value $script:OriginalPrompt
        }
    }

    
    Context 'Activating environments' {
        It 'Should activate an existing environment' {
            { Activate-PSVirtualEnv -Name $script:activationTestName } | Should -Not -Throw
            
            # Check if environment is active
            InModuleScope PSVirtualEnv {
                $script:ActiveEnvironment | Should -Not -BeNullOrEmpty
            }
            InModuleScope PSVirtualEnv { $script:ActiveEnvironment.Name } | Should -Be $script:activationTestName

        }
        
        It 'Should modify PSModulePath when activated' {
            Activate-PSVirtualEnv -Name $script:activationTestName
            
            $env:PSModulePath | Should -BeLike "*$script:activationTestName\Modules*"
        }
        
        It 'Should update prompt to show active environment' {
            Activate-PSVirtualEnv -Name $script:activationTestName
            
            $promptOutput = & prompt
            $promptOutput | Should -BeLike "$($script:activationTestName)*"
        }
        
        It 'Should fail when environment does not exist' {
            { Activate-PSVirtualEnv -Name 'NonExistentEnv' -ErrorAction Stop } | Should -Throw
        }
    }
    
    Context 'Deactivating environments' {
        BeforeEach {
            Activate-PSVirtualEnv -Name $script:activationTestName
        }

        It 'Should deactivate the active environment' {
            { Deactivate-PSVirtualEnv } | Should -Not -Throw
            
            # Check if environment is deactivated
            InModuleScope PSVirtualEnv {
                $script:ActiveEnvironment | Should -BeNullOrEmpty
            }
        }
        
        It 'Should restore original PSModulePath' {

            Deactivate-PSVirtualEnv

            $originalPath = $env:PSModulePath

            $originalPath | Should -Not -BeLike "*psvirtualenv*"

            Activate-PSVirtualEnv -Name $script:activationTestName
            $activePath = $env:PSModulePath
            
            $activePath | Should -Not -Be $originalPath
            
            Deactivate-PSVirtualEnv
            
            $env:PSModulePath | Should -Not -BeLike "*$script:activationTestName*"
        }
        
        It 'Should warn when no environment is active' {
            Deactivate-PSVirtualEnv  # First deactivation
            $output = Deactivate-PSVirtualEnv -WarningAction SilentlyContinue -WarningVariable warning
            
            $warning | Should -Not -BeNullOrEmpty
        }
    }


}

Describe 'Get-PSVirtualEnv' {
    BeforeAll {
        # Create multiple test environments
        $script:TestEnvNames = @('TestEnv1', 'TestEnv2', 'WebProject')
        foreach ($name in $script:TestEnvNames) {
            New-PSVirtualEnv -Name $name -Force
        }
    }
    
    AfterAll {
        # Clean up test environments
        foreach ($name in $script:TestEnvNames) {
            Remove-PSVirtualEnv -Name $name -Force -ErrorAction SilentlyContinue
        }
    }
    
    Context 'Listing environments' {
        It 'Should list all environments' {
            $environments = Get-PSVirtualEnv
            
            $environments | Should -Not -BeNullOrEmpty
            $environments.Count | Should -BeGreaterOrEqual 3
            $environments.Name | Should -Contain 'TestEnv1'
            $environments.Name | Should -Contain 'TestEnv2'
            $environments.Name | Should -Contain 'WebProject'
        }
        
        It 'Should filter by name with wildcards' {
            $environments = Get-PSVirtualEnv -Name 'Test*'
            
            $environments.Count | Should -BeGreaterOrEqual 2
            $environments.Name | Should -Contain 'TestEnv1'
            $environments.Name | Should -Contain 'TestEnv2'
            $environments.Name | Should -Not -Contain 'WebProject'
        }
        
        It 'Should show active environment' {
            Activate-PSVirtualEnv -Name 'TestEnv1'
            
            try {
                $activeEnv = Get-PSVirtualEnv -Active
                
                $activeEnv | Should -Not -BeNullOrEmpty
                $activeEnv.Name | Should -Be 'TestEnv1'
                $activeEnv.IsActive | Should -BeTrue
            }
            finally {
                Deactivate-PSVirtualEnv
            }
        }
        
        It 'Should show detailed information' {
            $environments = Get-PSVirtualEnv -Detailed
            
            $environments[0].GetType().Name | Should -Be 'PSVirtualEnvironment'
            $environments[0] | Should -HaveProperty 'Modules'
            $environments[0] | Should -HaveProperty 'Settings'
        }
    }
}

Describe 'Install-PSModuleInEnv' {
    BeforeAll {
        # Create and activate test environment
        New-PSVirtualEnv -Name $script:TestEnvironmentName -Force
        Activate-PSVirtualEnv -Name $script:TestEnvironmentName
        
        # Mock Find-Module and Save-Module to avoid actual downloads
        Mock -ModuleName PSVirtualEnv Find-Module {
            [PSCustomObject]@{
                Name       = $Name
                Version    = [Version]'1.0.0'
                Repository = 'PSGallery'
            }
        }
        
        Mock -ModuleName PSVirtualEnv Save-Module {
            # Create a dummy module structure
            $modulePath = Join-Path $Path "$Name\1.0.0"
            New-Item -Path $modulePath -ItemType Directory -Force | Out-Null
            
            # Create a minimal module manifest
            $manifestPath = Join-Path $modulePath "$Name.psd1"
            $manifestContent = @"
@{
    ModuleVersion = '1.0.0'
    RootModule = '$Name.psm1'
    FunctionsToExport = @()
}
"@
            Set-Content -Path $manifestPath -Value $manifestContent
        }
    }
    
    AfterAll {
        Deactivate-PSVirtualEnv -ErrorAction SilentlyContinue
        Remove-PSVirtualEnv -Name $script:TestEnvironmentName -Force
    }
    
    Context 'Installing modules' {
        It 'Should install a module in the active environment' {
            { Install-PSModuleInEnv -Name 'TestModule' } | Should -Not -Throw
            
            # Verify module was added to configuration
            $env = InModuleScope PSVirtualEnv {
                Get-EnvironmentFromRegistry -Name $using:script:TestEnvironmentName
            }
            
            $env.Modules | Where-Object { $_.name -eq 'TestModule' } | Should -Not -BeNullOrEmpty
        }
        
        It 'Should fail when no environment is active' {
            Deactivate-PSVirtualEnv
            
            { Install-PSModuleInEnv -Name 'TestModule' -ErrorAction Stop } | Should -Throw
            
            # Reactivate for other tests
            Activate-PSVirtualEnv -Name $script:TestEnvironmentName
        }
        
        It 'Should support version specification' {
            { Install-PSModuleInEnv -Name 'VersionedModule' -RequiredVersion '2.0.0' } | Should -Not -Throw
        }
    }
}

Describe 'Remove-PSVirtualEnv' {
    Context 'Removing environments' {
        BeforeEach {
            New-PSVirtualEnv -Name $script:TestEnvironmentName -Force
        }
        
        It 'Should remove an existing environment' {
            { Remove-PSVirtualEnv -Name $script:TestEnvironmentName -Force } | Should -Not -Throw
            
            # Verify environment is gone
            $envPath = Join-Path $script:TestEnvironmentPath $script:TestEnvironmentName
            Test-Path $envPath | Should -BeFalse
            
            Get-PSVirtualEnv -Name $script:TestEnvironmentName | Should -BeNullOrEmpty
        }
        
        It 'Should fail when environment does not exist' {
            Remove-PSVirtualEnv -Name $script:TestEnvironmentName -Force
            { Remove-PSVirtualEnv -Name $script:TestEnvironmentName -ErrorAction Stop } | Should -Throw
        }
        
        It 'Should not remove active environment' {
            Activate-PSVirtualEnv -Name $script:TestEnvironmentName
            
            try {
                { Remove-PSVirtualEnv -Name $script:TestEnvironmentName -ErrorAction Stop } | Should -Throw
            }
            finally {
                Deactivate-PSVirtualEnv
            }
        }
    }
}