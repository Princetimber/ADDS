#Requires -Version 7.0

function Invoke-ADDSForest {
    <#
    .SYNOPSIS
        Creates a new Active Directory Domain Services (AD DS) forest.

    .DESCRIPTION
        Invoke-ADDSForest is the PUBLIC wrapper function for creating a new Active Directory
        forest. This is a critical, state-changing operation that orchestrates the complete
        forest creation process.

        This function serves as the user-facing API and provides:
        - Comprehensive parameter validation at the API boundary
        - Support for -WhatIf and -Confirm to test operations safely
        - PassThru support for pipeline scenarios and automation tracking
        - Complete logging of operations and outcomes
        - Delegation to New-ADDSForest for actual implementation

        WORKFLOW:
        1. Validates all input parameters
        2. Calls New-ADDSForest (private function) which:
           - Runs Test-PreflightCheck (platform, elevation, features, disk space)
           - Installs required modules (Invoke-ResourceModule)
           - Installs AD features (Install-ADModule)
           - Validates paths (Test-IfPathExistOrNot)
           - Prompts for safe mode password if needed (Get-SafeModePassword)
           - Creates the forest (Install-ADDSForest)
        3. Returns operation summary if PassThru requested

        SAFETY: This function supports -WhatIf and -Confirm parameters. Always test with
        -WhatIf first before executing in production.

        All validation (platform, elevation, features) is performed by Test-PreflightCheck
        (called by New-ADDSForest) following the DRY principle.

    .PARAMETER DomainName
        The fully qualified domain name (FQDN) for the new forest root domain.

        This is the DNS name for your new Active Directory forest and must be a valid,
        unique DNS name. It should not conflict with existing network domains.

        Example: "contoso.com", "corp.example.com"

        This parameter is mandatory and cannot be null or empty.

    .PARAMETER SafeModeAdministratorPassword
        The Directory Services Restore Mode (DSRM) administrator password as a SecureString.

        This password is critical for disaster recovery operations and must meet domain
        complexity requirements. Store this password securely as it's required to restore
        Active Directory from backup.

        If not provided, the function will prompt interactively for the password.

        For automation scenarios, create a SecureString:
        $pass = ConvertTo-SecureString 'YourPassword' -AsPlainText -Force

    .PARAMETER DomainNetBiosName
        The NetBIOS name for the domain (maximum 15 characters).

        This is the pre-Windows 2000 domain name used for backward compatibility.
        Must be unique in your network.

        If not specified, defaults to the first label of the FQDN.
        Example: For "contoso.com", defaults to "CONTOSO"

        Must contain only alphanumeric characters and hyphens.

    .PARAMETER DomainMode
        The functional level for the domain.

        Determines which Active Directory features are available within the domain.
        Higher functional levels provide more features but require all domain controllers
        to run supported Windows Server versions.

        Valid values:
        - Win2008: Windows Server 2008
        - Win2008R2: Windows Server 2008 R2
        - Win2012: Windows Server 2012
        - Win2012R2: Windows Server 2012 R2
        - Win2025: Windows Server 2025 (latest)
        - WinThreshold: Windows Server preview builds
        - Default: Uses system default (typically latest)

        Default: Win2025 (recommended for new deployments)

    .PARAMETER ForestMode
        The functional level for the forest.

        Determines which Active Directory features are available across the entire forest.
        Must be equal to or higher than the domain functional level.

        Valid values:
        - Win2008: Windows Server 2008
        - Win2008R2: Windows Server 2008 R2
        - Win2012: Windows Server 2012
        - Win2012R2: Windows Server 2012 R2
        - Win2025: Windows Server 2025 (latest)
        - WinThreshold: Windows Server preview builds
        - Default: Uses system default (typically latest)

        Default: Win2025 (recommended for new deployments)

    .PARAMETER DatabasePath
        The full path for the Active Directory database (NTDS.dit).

        Requirements:
        - Must be on an NTFS volume
        - Recommended: Dedicated volume separate from OS for performance and reliability
        - Ensure adequate space (minimum 500MB, more for large environments)

        If not specified, uses module default: $env:SYSTEMDRIVE\Windows

        Example: "D:\NTDS", "C:\Windows\NTDS"

    .PARAMETER SysvolPath
        The full path for the SYSVOL folder.

        SYSVOL stores Group Policy templates, logon scripts, and other domain-wide data.
        This folder is replicated to all domain controllers.

        Requirements:
        - Must be on an NTFS volume
        - Ensure adequate space (minimum 100MB)

        If not specified, uses module default: $env:SYSTEMDRIVE\Windows

        Example: "D:\SYSVOL", "C:\Windows\SYSVOL"

    .PARAMETER LogPath
        The full path for Active Directory log files.

        Requirements:
        - Must be on an NTFS volume
        - Recommended: Dedicated volume separate from database for performance
        - Ensure adequate space for transaction logs

        If not specified, uses module default: $env:SYSTEMDRIVE\Windows\NTDS\

        Example: "E:\ADLogs", "C:\Windows\NTDS\Logs"

    .PARAMETER ResourceGroupName
        The Azure Resource Group that contains the Key Vault holding the DSRM password secret.

        When specified together with -KeyVaultName and -SecretName, the DSRM password is
        retrieved from Azure Key Vault instead of being supplied directly or prompted interactively.

        Requires the Az.KeyVault module and an active Azure connection (handled internally by
        New-ADDSForest via Connect-ToAzure).

    .PARAMETER KeyVaultName
        The name of the Azure Key Vault that stores the DSRM password secret.

        Must be specified together with -ResourceGroupName and -SecretName.

    .PARAMETER SecretName
        The name of the secret that holds the DSRM password value.

        Used with -KeyVaultName (Azure Key Vault path) or with -VaultName (pre-registered
        vault path).

    .PARAMETER VaultName
        The registered name of a SecretManagement vault to retrieve the DSRM password from.

        Use this for any pre-registered vault backend — local SecretStore, HashiCorp Vault,
        Bitwarden, 1Password, or any module that implements the SecretManagement extension API.
        The vault must already be registered (via Register-SecretVault) before calling this function.
        No Azure connection is made when this parameter is used.

        Must be specified together with -SecretName.
        Cannot be combined with -ResourceGroupName or -KeyVaultName.

    .PARAMETER InstallDNS
        If specified, installs and configures DNS server role as part of forest creation.

        Recommended for most scenarios as Active Directory requires DNS for name resolution.
        The DNS server will be configured with the appropriate zones for the new domain.

        If not specified, DNS must be configured separately before AD can function properly.

    .PARAMETER Force
        If specified, suppresses confirmation prompts.

        When Force is used, the function bypasses the ShouldProcess prompt of this function
        and passes -Confirm:$false to New-ADDSForest, preventing a double-prompt in
        interactive sessions.

        WARNING: Use with extreme caution in production. This bypasses all safety checks
        and will execute the operation immediately without prompting.

        Recommended for:
        - Automation scripts where parameters have been validated
        - Non-interactive scenarios (scheduled tasks, CI/CD)

        Always test with -WhatIf before using -Force in production.

    .PARAMETER PassThru
        If specified, returns a detailed object containing forest creation information.

        The returned object includes:
        - DomainName: The FQDN of the created forest
        - DomainNetBiosName: The NetBIOS name
        - ForestMode: The forest functional level
        - DomainMode: The domain functional level
        - DatabasePath: Path to AD database
        - LogPath: Path to AD logs
        - SysvolPath: Path to SYSVOL
        - InstallDNS: Whether DNS was installed
        - Status: Operation status ('Completed')
        - Timestamp: When operation completed

        Useful for:
        - Pipeline scenarios
        - Automation tracking and logging
        - Exporting configuration details

        Example: $result = Invoke-ADDSForest ... -PassThru | Export-Csv config.csv

    .OUTPUTS
        None (default)
            By default, the function returns no output. Status is logged.

        PSCustomObject (when -PassThru is specified)
            Returns a custom object with forest configuration details:
            - PSTypeName: 'Invoke-ADDSForest.ADDSForest'
            - DomainName: [string]
            - DomainNetBiosName: [string]
            - ForestMode: [string]
            - DomainMode: [string]
            - DatabasePath: [string]
            - LogPath: [string]
            - SysvolPath: [string]
            - InstallDNS: [bool]
            - Status: [string]
            - Timestamp: [datetime]

    .EXAMPLE
        Invoke-ADDSForest -DomainName "contoso.com" -WhatIf

        Tests what would happen if creating a new forest for contoso.com without actually
        executing the operation. This is the safest way to validate parameters and verify
        prerequisites before committing to the operation.

        Output will show all steps that would be performed without making any changes.

    .EXAMPLE
        Invoke-ADDSForest -DomainName "corp.example.com" -InstallDNS

        Creates a new AD forest with domain corp.example.com and installs DNS.

        The function will:
        - Prompt for Safe Mode administrator password
        - Prompt for confirmation before proceeding
        - Use default NetBIOS name "CORP"
        - Use default paths for database, logs, and SYSVOL
        - Install DNS server role
        - Use latest functional levels (Win2025)

    .EXAMPLE
        $securePass = Read-Host "Enter DSRM Password" -AsSecureString
        Invoke-ADDSForest -DomainName "contoso.com" `
                          -DomainNetBiosName "CONTOSO" `
                          -SafeModeAdministratorPassword $securePass `
                          -DomainMode "Win2012R2" `
                          -ForestMode "Win2012R2" `
                          -InstallDNS `
                          -Confirm:$false

        Creates a forest with Windows Server 2012 R2 functional levels.

        Prompts interactively for password, then creates the forest with:
        - Explicit NetBIOS name
        - Windows Server 2012 R2 functional levels
        - DNS installation
        - Confirmation bypassed (skips prompt)

    .EXAMPLE
        $config = Invoke-ADDSForest -DomainName "contoso.com" `
                                     -DatabasePath "D:\NTDS" `
                                     -LogPath "E:\ADLogs" `
                                     -SysvolPath "D:\SYSVOL" `
                                     -InstallDNS `
                                     -PassThru

        $config | Export-Csv -Path "forest-config.csv" -NoTypeInformation

        Creates a forest with custom paths on dedicated volumes and captures the
        configuration details.

        The PassThru parameter returns an object containing all forest settings,
        which is then exported to CSV for documentation and audit purposes.

        Recommended for enterprise deployments to maintain configuration records.

    .EXAMPLE
        # Automation scenario with error handling
        try {
            $params = @{
                DomainName = "automation.corp.com"
                SafeModeAdministratorPassword = $vaultPassword
                DatabasePath = "D:\NTDS"
                LogPath = "E:\Logs"
                SysvolPath = "D:\SYSVOL"
                InstallDNS = $true
                Force = $true
                PassThru = $true
            }

            $result = Invoke-ADDSForest @params

            if ($result.Status -eq 'Completed') {
                Send-Notification -Message "Forest created successfully"
            }
        }
        catch {
            Write-Error "Forest creation failed: $_"
            Send-Alert -Message "CRITICAL: AD forest creation failed"
        }

        Complete automation example with:
        - Parameter splatting for readability
        - Secure password from vault
        - Custom paths on dedicated volumes
        - Force (non-interactive)
        - PassThru for status verification
        - Comprehensive error handling
        - Integration with notification system

    .EXAMPLE
        Invoke-ADDSForest -DomainName "contoso.com" -VaultName "LocalStore" -SecretName "DSRMPassword"

        Creates a new AD forest. The DSRM password is retrieved from a pre-registered
        SecretManagement vault named 'LocalStore'. No Azure connection is made.

        The vault must be registered first:
        Register-SecretVault -Name 'LocalStore' -ModuleName 'Microsoft.PowerShell.SecretStore'

    .EXAMPLE
        Invoke-ADDSForest -DomainName "contoso.com" -VaultName "HashiCorpVault" -SecretName "ad/dsrm" -InstallDNS

        Creates a new AD forest, retrieving the DSRM password from a pre-registered HashiCorp Vault
        instance. Any SecretManagement-compatible backend works with -VaultName.

    .NOTES
        Prerequisites:
        - Administrative privileges (enforced by Test-PreflightCheck)
        - Windows Server operating system (enforced by Test-PreflightCheck)
        - AD-Domain-Services feature available (enforced by Test-PreflightCheck)
        - PowerShell 7.0+
        - Network connectivity for module downloads
        - Az.KeyVault and Microsoft.PowerShell.SecretManagement modules (only when using
          -ResourceGroupName / -KeyVaultName / -SecretName for Azure vault retrieval)
        - Microsoft.PowerShell.SecretManagement module + registered vault (when using -VaultName)

        CRITICAL WARNINGS:
        - This operation creates an entire Active Directory forest
        - Changes are PERMANENT and cannot be easily reversed
        - System WILL REBOOT after completion
        - Affects domain infrastructure and authentication for all systems
        - Ensure you have valid system backups before proceeding
        - Test thoroughly with -WhatIf before production execution

        Security Considerations:
        - Safe Mode password is never logged (security-safe logging)
        - Requires administrative privileges
        - Operation is logged for audit purposes
        - All changes are made through official Microsoft cmdlets

        Performance Notes:
        - Forest creation typically takes 5-15 minutes
        - Time varies based on system performance and configuration
        - System will reboot automatically after completion
        - Dedicated volumes for database/logs improve performance

        Validation Delegation (DRY Principle):
        This function does NOT perform platform or elevation validation directly.
        All validation is delegated to Test-PreflightCheck (called by New-ADDSForest):
        - Platform validation (Windows Server ProductType)
        - Elevation checks (Administrator privileges)
        - Feature availability (AD-Domain-Services)
        - Disk space validation
        - Path validation

        Troubleshooting:
        - If operation fails, check Windows Event Logs (System, Directory Services)
        - Verify all prerequisites with: Test-PreflightCheck
        - Ensure NTFS volumes for all paths
        - Check network connectivity for module downloads
        - Review logs in module log directory

        Related Commands:
        - Test-PreflightCheck: Validates prerequisites
        - New-ADDSForest: Private implementation function
        - Get-ADForest: Query forest information post-creation
        - Get-ADDomain: Query domain information post-creation

    .LINK
        https://docs.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void], [PSCustomObject])]
    param(
        [Parameter(Position = 0, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $DomainName,

        [Parameter()]
        [securestring]
        $SafeModeAdministratorPassword,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $DomainNetBiosName,

        [Parameter()]
        [ValidateSet('Win2008', 'Win2008R2', 'Win2012', 'Win2012R2', 'Win2025', 'Default', 'WinThreshold')]
        [string]
        $DomainMode = 'Win2025',

        [Parameter()]
        [ValidateSet('Win2008', 'Win2008R2', 'Win2012', 'Win2012R2', 'Win2025', 'Default', 'WinThreshold')]
        [string]
        $ForestMode = 'Win2025',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $DatabasePath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $SysvolPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $LogPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ResourceGroupName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $KeyVaultName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $SecretName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $VaultName,

        [Parameter()]
        [switch]
        $InstallDNS,

        [Parameter()]
        [switch]
        $Force,

        [Parameter()]
        [switch]
        $PassThru
    )

    begin {
        Write-ToLog -Message "Starting Invoke-ADDSForest operation" -Level INFO
        Write-ToLog -Message "Target domain: $DomainName" -Level INFO

        # Handle Force parameter - log intent; confirmation suppression handled in process block
        if ($Force) {
            Write-ToLog -Message "Force specified - suppressing confirmation prompts" -Level WARN
        }
    }

    process {
        try {
            # Define the target and operation for ShouldProcess
            $target = "Active Directory Forest '$DomainName'"
            $operation = "Create new AD DS forest with functional levels Domain=$DomainMode, Forest=$ForestMode"

            if ($PSCmdlet.ShouldProcess($target, $operation)) {
                Write-ToLog -Message "User confirmed operation (or -Confirm bypassed)" -Level INFO

                # Build parameter set for New-ADDSForest
                $params = @{
                    DomainName = $DomainName
                    DomainMode = $DomainMode
                    ForestMode = $ForestMode
                }

                # Add optional parameters if provided
                if ($PSBoundParameters.ContainsKey('SafeModeAdministratorPassword')) {
                    $params['SafeModeAdministratorPassword'] = $SafeModeAdministratorPassword
                }

                if ($PSBoundParameters.ContainsKey('DomainNetBiosName')) {
                    $params['DomainNetBiosName'] = $DomainNetBiosName
                }

                if ($PSBoundParameters.ContainsKey('DatabasePath')) {
                    $params['DatabasePath'] = $DatabasePath
                }

                if ($PSBoundParameters.ContainsKey('SysvolPath')) {
                    $params['SysvolPath'] = $SysvolPath
                }

                if ($PSBoundParameters.ContainsKey('LogPath')) {
                    $params['LogPath'] = $LogPath
                }

                foreach ($kvParam in 'ResourceGroupName', 'KeyVaultName', 'SecretName', 'VaultName') {
                    if ($PSBoundParameters.ContainsKey($kvParam)) {
                        $params[$kvParam] = $PSBoundParameters[$kvParam]
                    }
                }

                if ($InstallDNS.IsPresent) {
                    $params['InstallDNS'] = $true
                }

                if ($Force.IsPresent) {
                    $params['Force'] = $true
                    # Bypass New-ADDSForest's own ShouldProcess to prevent double-prompt
                    $params['Confirm'] = $false
                }

                # Log parameter summary (excluding password)
                $paramSummary = $params.Keys | Where-Object { $_ -ne 'SafeModeAdministratorPassword' } | ForEach-Object {
                    "$_=$($params[$_])"
                }
                Write-ToLog -Message "Parameters: $($paramSummary -join ', ')" -Level INFO

                # Call private implementation function
                Write-ToLog -Message "Calling New-ADDSForest" -Level INFO
                New-ADDSForest @params

                Write-ToLog -Message "New-ADDSForest completed successfully" -Level SUCCESS

                # Metrics reporting
                $dnsStatus = if ($InstallDNS.IsPresent) { "with DNS" } else { "without DNS" }
                Write-ToLog -Message "Forest creation metrics - Domain: $DomainName, Functional Levels: Domain=$DomainMode/Forest=$ForestMode, DNS: $dnsStatus" -Level INFO

                # Return rich object if PassThru requested
                if ($PassThru) {
                    Write-ToLog -Message "PassThru specified - returning configuration object" -Level INFO

                    return [PSCustomObject]@{
                        PSTypeName        = 'Invoke-ADDSForest.ADDSForest'
                        DomainName        = $DomainName
                        DomainNetBiosName = if ($PSBoundParameters.ContainsKey('DomainNetBiosName')) { $DomainNetBiosName } else { $DomainName.Split('.')[0].ToUpper() }
                        ForestMode        = $ForestMode
                        DomainMode        = $DomainMode
                        DatabasePath      = if ($PSBoundParameters.ContainsKey('DatabasePath')) { $DatabasePath } else { "$env:SYSTEMDRIVE\Windows" }
                        LogPath           = if ($PSBoundParameters.ContainsKey('LogPath')) { $LogPath } else { "$env:SYSTEMDRIVE\Windows\NTDS\" }
                        SysvolPath        = if ($PSBoundParameters.ContainsKey('SysvolPath')) { $SysvolPath } else { "$env:SYSTEMDRIVE\Windows" }
                        InstallDNS        = $InstallDNS.IsPresent
                        Status            = 'Completed'
                        Timestamp         = [System.DateTimeOffset]::UtcNow.UtcDateTime
                    }
                }
            } else {
                # User declined the operation via ShouldProcess prompt
                Write-ToLog -Message "Operation cancelled by user (ShouldProcess returned false)" -Level INFO
            }
        } catch {
            # Enhanced error message with context
            $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)✗$($PSStyle.Reset)" } else { "✗" }
            $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

            $errorMsg = "Failed to create AD DS forest '$DomainName'."
            $errorMsg += "`n`n${bullet} Error: $($_.Exception.Message)"
            $errorMsg += "`n`n${tip} Troubleshooting Tips:"
            $errorMsg += "`n  • Verify prerequisites with: Test-PreflightCheck"
            $errorMsg += "`n  • Check Windows Event Logs (System, Directory Services)"
            $errorMsg += "`n  • Ensure all paths are on NTFS volumes"
            $errorMsg += "`n  • Verify network connectivity for module downloads"
            $errorMsg += "`n  • Review module logs for detailed diagnostics"
            $errorMsg += "`n  • Test operation with -WhatIf before retrying"

            Write-ToLog -Message "Forest creation failed: $($_.Exception.Message)" -Level ERROR
            Write-ToLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR

            throw $errorMsg
        }
    }

    end {
        Write-ToLog -Message "Invoke-ADDSForest operation completed" -Level INFO
    }
}
