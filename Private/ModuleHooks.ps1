$script:OriginalImportModule = $null
$script:OriginalInstallModule = $null
$script:OriginalSaveModule = $null
$script:HooksActive = $false

function Enable-ModuleImportHooks {
    <#
    .SYNOPSIS
        Enables smart module hooks that temporarily allow system access.
    #>
    [CmdletBinding()]
    param()
    
    if ($script:HooksActive) {
        Write-Verbose "Module import hooks already active"
        return
    }
    
    # Store original commands
    $script:OriginalImportModule = Get-Command Import-Module -CommandType Cmdlet
    $script:OriginalInstallModule = Get-Command Install-Module -CommandType Function -ErrorAction SilentlyContinue
    $script:OriginalSaveModule = Get-Command Save-Module -CommandType Function -ErrorAction SilentlyContinue
    
    # Create smart Import-Module wrapper with proper parameter handling
    $importWrapper = {
        [CmdletBinding(DefaultParameterSetName='Name')]
        param(
            [Parameter(ParameterSetName='Name', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='PSSession', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='CimSession', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
            [string[]]$Name,

            [Parameter(ParameterSetName='FullyQualifiedName', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
            [Parameter(ParameterSetName='FullyQualifiedNameAndPSSession', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
            [Microsoft.PowerShell.Commands.ModuleSpecification[]]$FullyQualifiedName,

            [Parameter(ParameterSetName='Assembly', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
            [System.Reflection.Assembly[]]$Assembly,

            [Parameter(ParameterSetName='ModuleInfo', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
            [System.Management.Automation.PSModuleInfo[]]$ModuleInfo,

            [Parameter(ParameterSetName='PSSession', Mandatory=$true)]
            [Parameter(ParameterSetName='FullyQualifiedNameAndPSSession', Mandatory=$true)]
            [System.Management.Automation.Runspaces.PSSession]$PSSession,

            [Parameter(ParameterSetName='CimSession', Mandatory=$true)]
            [Microsoft.Management.Infrastructure.CimSession]$CimSession,

            [Parameter(ParameterSetName='WinCompat', Mandatory=$true)]
            [switch]$UseWindowsPowerShell,

            [switch]$Force,
            [switch]$Global,
            [switch]$PassThru,
            [switch]$AsCustomObject,
            [switch]$NoClobber,
            [switch]$DisableNameChecking,
            [switch]$SkipEditionCheck,
            [Alias('Version')]
            [version]$MinimumVersion,
            [string]$MaximumVersion,
            
            [version]$RequiredVersion,
            [object[]]$ArgumentList,
            [string]$Scope,
            [string]$Prefix,
            [string[]]$Function,
            [string[]]$Cmdlet,
            [string[]]$Variable,
            [string[]]$Alias
        )
        
        # Request temporary bypass for Import-Module operations
        if (Test-PSModulePathProtection) {
            Request-TemporaryPathBypass -DurationSeconds 15
        }
        
        try {
            # Build parameters carefully, only including valid Import-Module parameters
            $importParams = $PSBoundParameters
            <#
            # Handle positional parameter sets
            if ($PSCmdlet.ParameterSetName -eq 'Name' -and $Name) {
                $importParams['Name'] = $Name
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'FullyQualifiedName' -and $FullyQualifiedName) {
                $importParams['FullyQualifiedName'] = $FullyQualifiedName
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'Assembly' -and $Assembly) {
                $importParams['Assembly'] = $Assembly
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ModuleInfo' -and $ModuleInfo) {
                $importParams['ModuleInfo'] = $ModuleInfo
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'PSSession' -and $PSSession) {
                $importParams['PSSession'] = $PSSession
                if ($Name) { $importParams['Name'] = $Name }
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'CimSession' -and $CimSession) {
                $importParams['CimSession'] = $CimSession
                if ($Name) { $importParams['Name'] = $Name }
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'FullyQualifiedNameAndPSSession') {
                $importParams['FullyQualifiedName'] = $FullyQualifiedName
                $importParams['PSSession'] = $PSSession
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'WinCompat') {
                $importParams['UseWindowsPowerShell'] = $UseWindowsPowerShell
                if ($Name) { $importParams['Name'] = $Name }
            }
            
            # Add optional parameters if they were specified
            if ($PSBoundParameters.ContainsKey('Force')) { $importParams['Force'] = $Force }
            if ($PSBoundParameters.ContainsKey('Global')) { $importParams['Global'] = $Global }
            if ($PSBoundParameters.ContainsKey('PassThru')) { $importParams['PassThru'] = $PassThru }
            if ($PSBoundParameters.ContainsKey('AsCustomObject')) { $importParams['AsCustomObject'] = $AsCustomObject }
            if ($PSBoundParameters.ContainsKey('NoClobber')) { $importParams['NoClobber'] = $NoClobber }
            if ($PSBoundParameters.ContainsKey('DisableNameChecking')) { $importParams['DisableNameChecking'] = $DisableNameChecking }
            if ($PSBoundParameters.ContainsKey('SkipEditionCheck')) { $importParams['SkipEditionCheck'] = $SkipEditionCheck }
            if ($PSBoundParameters.ContainsKey('MinimumVersion')) { $importParams['MinimumVersion'] = $MinimumVersion }
            if ($PSBoundParameters.ContainsKey('MaximumVersion')) { $importParams['MaximumVersion'] = $MaximumVersion }
            if ($PSBoundParameters.ContainsKey('RequiredVersion')) { $importParams['RequiredVersion'] = $RequiredVersion }
            if ($PSBoundParameters.ContainsKey('ArgumentList')) { $importParams['ArgumentList'] = $ArgumentList }
            if ($PSBoundParameters.ContainsKey('Scope')) { $importParams['Scope'] = $Scope }
            if ($PSBoundParameters.ContainsKey('Prefix')) { $importParams['Prefix'] = $Prefix }
            if ($PSBoundParameters.ContainsKey('Function')) { $importParams['Function'] = $Function }
            if ($PSBoundParameters.ContainsKey('Cmdlet')) { $importParams['Cmdlet'] = $Cmdlet }
            if ($PSBoundParameters.ContainsKey('Variable')) { $importParams['Variable'] = $Variable }
            if ($PSBoundParameters.ContainsKey('Alias')) { $importParams['Alias'] = $Alias }
            #>
            # Call original Import-Module with validated parameters
            return & $script:OriginalImportModule @importParams
            
        } catch {
            Write-Verbose "Import-Module hook error: $_"
            throw
        }
    }
    
    # Create smart Install-Module wrapper with proper parameter handling
    $installWrapper = {
        [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
        param(
            [Parameter(Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
            [ValidateNotNullOrEmpty()]
            [string[]]$Name,

            [ValidateNotNull()]
            [string]$MinimumVersion,

            [ValidateNotNull()]
            [string]$MaximumVersion,

            
            [ValidateNotNull()]
            [string]$RequiredVersion,

            [ValidateNotNullOrEmpty()]
            [string[]]$Repository,

            [PSCredential]
            [System.Management.Automation.CredentialAttribute()]
            $Credential,

            [ValidateSet('CurrentUser', 'AllUsers')]
            [string]$Scope,

            [ValidateNotNullOrEmpty()]
            [uri]$Proxy,

            [PSCredential]
            [System.Management.Automation.CredentialAttribute()]
            $ProxyCredential,

            [switch]$AllowClobber,
            [switch]$SkipPublisherCheck,
            [switch]$Force,
            [switch]$AllowPrerelease,
            [switch]$AcceptLicense,
            [switch]$PassThru
        )
        
        # Request longer bypass for Install-Module operations
        if (Test-PSModulePathProtection) {
            Request-TemporaryPathBypass -DurationSeconds 30
        }
        
        try {
            # Build parameters carefully
            $installParams = @{
                Name = $Name
            }
            
            if ($PSBoundParameters.ContainsKey('MinimumVersion')) { $installParams['MinimumVersion'] = $MinimumVersion }
            if ($PSBoundParameters.ContainsKey('MaximumVersion')) { $installParams['MaximumVersion'] = $MaximumVersion }
            if ($PSBoundParameters.ContainsKey('RequiredVersion')) { $installParams['RequiredVersion'] = $RequiredVersion }
            if ($PSBoundParameters.ContainsKey('Repository')) { $installParams['Repository'] = $Repository }
            if ($PSBoundParameters.ContainsKey('Credential')) { $installParams['Credential'] = $Credential }
            if ($PSBoundParameters.ContainsKey('Scope')) { $installParams['Scope'] = $Scope }
            if ($PSBoundParameters.ContainsKey('Proxy')) { $installParams['Proxy'] = $Proxy }
            if ($PSBoundParameters.ContainsKey('ProxyCredential')) { $installParams['ProxyCredential'] = $ProxyCredential }
            if ($PSBoundParameters.ContainsKey('AllowClobber')) { $installParams['AllowClobber'] = $AllowClobber }
            if ($PSBoundParameters.ContainsKey('SkipPublisherCheck')) { $installParams['SkipPublisherCheck'] = $SkipPublisherCheck }
            if ($PSBoundParameters.ContainsKey('Force')) { $installParams['Force'] = $Force }
            if ($PSBoundParameters.ContainsKey('AllowPrerelease')) { $installParams['AllowPrerelease'] = $AllowPrerelease }
            if ($PSBoundParameters.ContainsKey('AcceptLicense')) { $installParams['AcceptLicense'] = $AcceptLicense }
            if ($PSBoundParameters.ContainsKey('PassThru')) { $installParams['PassThru'] = $PassThru }
            
            # Call original Install-Module
            if ($script:OriginalInstallModule) {
                return & $script:OriginalInstallModule @installParams
            } else {
                # Fallback: temporarily remove our function and call the original
                Remove-Item function:Install-Module -Force
                try {
                    return Install-Module @installParams
                } finally {
                    # Restore our wrapper
                    Set-Item -Path function:global:Install-Module -Value $installWrapper -Force
                }
            }
            
        } catch {
            Write-Verbose "Install-Module hook error: $_"
            throw
        }
    }
    
    # Replace functions
    Set-Item -Path function:global:Import-Module -Value $importWrapper -Force
    
    # Only hook Install-Module if it exists and is a function (not in all PowerShell versions)
    if (Get-Command Install-Module -ErrorAction SilentlyContinue) {
        Set-Item -Path function:global:Install-Module -Value $installWrapper -Force
    }
    
    $script:HooksActive = $true
    Write-Verbose "Smart module hooks enabled"
}

function Disable-ModuleImportHooks {
    <#
    .SYNOPSIS
        Disables module import hooks safely.
    #>
    [CmdletBinding()]
    param()
    
    if (-not $script:HooksActive) {
        Write-Verbose "Module import hooks already inactive"
        return
    }
    
    # Remove our custom functions to let originals take precedence
    Remove-Item -Path function:global:Import-Module -Force -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Install-Module -Force -ErrorAction SilentlyContinue
    
    # Clear stored references
    $script:OriginalImportModule = $null
    $script:OriginalInstallModule = $null
    $script:OriginalSaveModule = $null
    $script:HooksActive = $false
    
    Write-Verbose "Module import hooks disabled"
}

function Test-ModuleHooksActive {
    <#
    .SYNOPSIS
        Tests if module hooks are currently active.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    return $script:HooksActive
}