#Requires -Version 7.0

function Invoke-ADDomainController {
    <#
    .SYNOPSIS
        Promotes a server to an additional domain controller in an existing AD DS domain.

    .DESCRIPTION
        Invoke-ADDomainController is the PUBLIC wrapper function for promoting a server to an
        additional domain controller in an existing Active Directory domain. This is a critical,
        state-changing operation that orchestrates the complete DC promotion process.

        This function serves as the user-facing API and provides:
        - Comprehensive parameter validation at the API boundary
        - Support for -WhatIf and -Confirm to test operations safely
        - PassThru support for pipeline scenarios and automation tracking
        - Complete logging of operations and outcomes
        - Delegation to New-ADDomainController for actual implementation

        WORKFLOW:
        1. Validates all input parameters
        2. Calls New-ADDomainController (private function) which:
           - Runs Test-PreflightCheck (platform, elevation, features, disk space)
           - Installs required modules (Invoke-ResourceModule)
           - Installs AD features (Install-ADModule)
           - Ensures target directories exist
           - Retrieves or prompts for DSRM password (Get-SafeModePassword)
           - Prompts for domain admin credential if not supplied
           - Promotes the server (Install-ADDSDomainController)
        3. Returns operation summary if PassThru requested

        SAFE MODE PASSWORD RESOLUTION ORDER:
        1. -SafeModeAdministratorPassword supplied directly (no prompting)
        2. Azure Key Vault: -ResourceGroupName + -KeyVaultName + -SecretName
        3. Pre-registered SecretManagement vault: -VaultName + -SecretName
        4. Interactive prompt (Get-SafeModePassword prompts securely)

        SAFETY: This function supports -WhatIf and -Confirm parameters. Always test with
        -WhatIf first before executing in production.

        All validation (platform, elevation, features) is performed by Test-PreflightCheck
        (called by New-ADDomainController) following the DRY principle.

    .PARAMETER DomainName
        The fully qualified domain name (FQDN) of the existing domain to join as a domain controller.

        The domain must already exist and be reachable from this server. This is not for
        creating a new domain — use Invoke-ADDSForest for that.

        Example: "contoso.com", "corp.example.com"

        This parameter is mandatory and cannot be null or empty.

    .PARAMETER SiteName
        The Active Directory site in which to register the new domain controller.

        AD sites are used to control replication topology and client logon traffic routing.
        The site must already exist in Active Directory before promotion.

        Default: "Default-First-Site-Name" (the automatically created first site)

        Example: "London-Site", "HQ-Site"

    .PARAMETER SafeModeAdministratorPassword
        The Directory Services Restore Mode (DSRM) administrator password as a SecureString.

        This password is critical for disaster recovery operations and must meet domain
        complexity requirements. Store this password securely as it's required to restore
        Active Directory from backup.

        If not provided, the function will prompt interactively for the password.

        For automation scenarios, create a SecureString:
        $pass = ConvertTo-SecureString 'YourPassword' -AsPlainText -Force

    .PARAMETER DomainAdminCredential
        Credentials for an existing domain administrator account in the target domain.

        Required to join the domain during promotion. The account must have rights to
        add domain controllers to the domain (typically Domain Admins or equivalent).

        If not provided, the function will prompt interactively for credentials.

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

        If not specified, uses module default: $env:SYSTEMDRIVE\Windows\NTDS

        Example: "E:\ADLogs", "C:\Windows\NTDS\Logs"

    .PARAMETER ResourceGroupName
        The Azure Resource Group that contains the Key Vault holding the DSRM password secret.

        When specified together with -KeyVaultName and -SecretName, the DSRM password is
        retrieved from Azure Key Vault instead of being supplied directly or prompted interactively.

        Requires the Az.KeyVault module and an active Azure connection (handled internally by
        New-ADDomainController via Connect-ToAzure).

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
        If specified, installs and configures the DNS server role as part of DC promotion.

        Recommended in branch-office scenarios or when deploying a new DNS zone. If the domain
        already has DNS servers that will handle this site's resolution, this may be omitted.

        If not specified, DNS must already be configured and reachable for AD to function.

    .PARAMETER Force
        If specified, suppresses confirmation prompts.

        When Force is used, the function bypasses the ShouldProcess prompt of this function
        and passes -Confirm:$false to New-ADDomainController, preventing a double-prompt in
        interactive sessions.

        WARNING: Use with extreme caution in production. This bypasses all safety checks
        and will execute the operation immediately without prompting.

        Recommended for:
        - Automation scripts where parameters have been validated
        - Non-interactive scenarios (scheduled tasks, CI/CD)

        Always test with -WhatIf before using -Force in production.

    .PARAMETER PassThru
        If specified, returns a detailed object containing DC promotion information.

        The returned object includes:
        - DomainName: The FQDN of the domain joined
        - SiteName: The AD site the DC was registered in
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

        Example: $result = Invoke-ADDomainController ... -PassThru | Export-Csv config.csv

    .OUTPUTS
        None (default)
            By default, the function returns no output. Status is logged.

        PSCustomObject (when -PassThru is specified)
            Returns a custom object with DC promotion details:
            - PSTypeName: 'Invoke-ADDomainController.ADDSDomainController'
            - DomainName: [string]
            - SiteName: [string]
            - DatabasePath: [string]
            - LogPath: [string]
            - SysvolPath: [string]
            - InstallDNS: [bool]
            - Status: [string]
            - Timestamp: [datetime]

    .EXAMPLE
        Invoke-ADDomainController -DomainName "contoso.com" -WhatIf

        Tests what would happen if promoting this server to a DC in contoso.com without
        actually executing the operation. Always run -WhatIf first to validate parameters
        and verify prerequisites before committing to the operation.

    .EXAMPLE
        Invoke-ADDomainController -DomainName "contoso.com" -InstallDNS

        Promotes this server to an additional domain controller in contoso.com with DNS.

        The function will:
        - Prompt for Safe Mode administrator password
        - Prompt for domain administrator credentials
        - Prompt for confirmation before proceeding
        - Register the DC in Default-First-Site-Name
        - Install the DNS server role
        - Use default paths for database, logs, and SYSVOL

    .EXAMPLE
        $cred = Get-Credential -Message "Enter domain admin credentials"
        $securePass = Read-Host "Enter DSRM Password" -AsSecureString
        Invoke-ADDomainController -DomainName "corp.example.com" `
                                  -SiteName "London-Site" `
                                  -SafeModeAdministratorPassword $securePass `
                                  -DomainAdminCredential $cred `
                                  -DatabasePath "D:\NTDS" `
                                  -LogPath "E:\ADLogs" `
                                  -SysvolPath "D:\SYSVOL" `
                                  -InstallDNS `
                                  -Confirm:$false

        Promotes to a DC in a specific site with dedicated storage volumes.
        Explicit credentials and passwords are supplied so no interactive prompts appear.

    .EXAMPLE
        $config = Invoke-ADDomainController -DomainName "contoso.com" `
                                            -SiteName "HQ-Site" `
                                            -DatabasePath "D:\NTDS" `
                                            -LogPath "E:\ADLogs" `
                                            -SysvolPath "D:\SYSVOL" `
                                            -InstallDNS `
                                            -PassThru

        $config | Export-Csv -Path "dc-config.csv" -NoTypeInformation

        Promotes the server and captures all configuration details. The PassThru object is
        exported to CSV for documentation and audit purposes.

        Recommended for enterprise deployments to maintain configuration records.

    .EXAMPLE
        # Automation scenario with error handling
        try {
            $params = @{
                DomainName                    = "automation.corp.com"
                SiteName                      = "DataCenter-Site"
                SafeModeAdministratorPassword = $vaultPassword
                DomainAdminCredential         = $adminCred
                DatabasePath                  = "D:\NTDS"
                LogPath                       = "E:\Logs"
                SysvolPath                    = "D:\SYSVOL"
                InstallDNS                    = $true
                Force                         = $true
                PassThru                      = $true
            }

            $result = Invoke-ADDomainController @params

            if ($result.Status -eq 'Completed') {
                Send-Notification -Message "DC promotion completed successfully"
            }
        }
        catch {
            Write-Error "DC promotion failed: $_"
            Send-Alert -Message "CRITICAL: Domain controller promotion failed"
        }

        Complete automation example with:
        - Parameter splatting for readability
        - Secure password from vault
        - Custom paths on dedicated volumes
        - Force (non-interactive)
        - PassThru for status verification
        - Comprehensive error handling and alerting

    .EXAMPLE
        Invoke-ADDomainController -DomainName "contoso.com" -VaultName "LocalStore" -SecretName "DSRMPassword"

        Promotes the server to a DC. The DSRM password is retrieved from a pre-registered
        SecretManagement vault named 'LocalStore'. No Azure connection is made.

        The vault must be registered first:
        Register-SecretVault -Name 'LocalStore' -ModuleName 'Microsoft.PowerShell.SecretStore'

    .NOTES
        Prerequisites:
        - Administrative privileges (enforced by Test-PreflightCheck)
        - Windows Server operating system (enforced by Test-PreflightCheck)
        - AD-Domain-Services feature available (enforced by Test-PreflightCheck)
        - The target domain must exist and be reachable over the network
        - PowerShell 7.0+
        - Network connectivity for module downloads
        - Az.KeyVault and Microsoft.PowerShell.SecretManagement modules (only when using
          -ResourceGroupName / -KeyVaultName / -SecretName for Azure vault retrieval)
        - Microsoft.PowerShell.SecretManagement module + registered vault (when using -VaultName)

        CRITICAL WARNINGS:
        - This operation promotes the server to a domain controller
        - Changes are PERMANENT — demotion is a multi-step, disruptive process
        - System WILL REBOOT after completion
        - Affects domain infrastructure for all users in the domain
        - Ensure you have valid system and domain backups before proceeding
        - Test thoroughly with -WhatIf before production execution

        Security Considerations:
        - Safe Mode password is never logged (security-safe logging)
        - Domain Admin credentials are never logged
        - Requires administrative privileges
        - Operation is logged for audit purposes
        - All changes are made through official Microsoft cmdlets

        Validation Delegation (DRY Principle):
        This function does NOT perform platform or elevation validation directly.
        All validation is delegated to Test-PreflightCheck (called by New-ADDomainController):
        - Platform validation (Windows Server ProductType)
        - Elevation checks (Administrator privileges)
        - Feature availability (AD-Domain-Services)
        - Disk space validation
        - Path validation

        Troubleshooting:
        - If operation fails, check Windows Event Logs (System, Directory Services)
        - Verify all prerequisites with: Test-PreflightCheck
        - Ensure the target domain is reachable (ping, nslookup)
        - Verify the specified AD site exists before promotion
        - Ensure NTFS volumes for all paths
        - Check network connectivity for module downloads
        - Review logs in module log directory

        Related Commands:
        - Invoke-ADDSForest: Creates a new AD DS forest
        - Test-PreflightCheck: Validates prerequisites
        - New-ADDomainController: Private implementation function
        - Get-ADDomainController: Query DC information post-promotion

    .LINK
        https://docs.microsoft.com/en-us/powershell/module/addsdeployment/install-addsdomaincontroller
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void], [PSCustomObject])]
    param(
        [Parameter(Position = 0, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $DomainName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $SiteName = 'Default-First-Site-Name',

        [Parameter()]
        [securestring]
        $SafeModeAdministratorPassword,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [pscredential]
        $DomainAdminCredential,

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
        Write-ToLog -Message "Starting Invoke-ADDomainController operation" -Level INFO
        Write-ToLog -Message "Target domain: $DomainName, Site: $SiteName" -Level INFO

        if ($Force) {
            Write-ToLog -Message "Force specified - suppressing confirmation prompts" -Level WARN
        }
    }

    process {
        try {
            $target = "Server '$($env:COMPUTERNAME)' in domain '$DomainName'"
            $operation = "Promote to additional domain controller in site '$SiteName'"

            if ($PSCmdlet.ShouldProcess($target, $operation)) {
                Write-ToLog -Message "User confirmed operation (or -Confirm bypassed)" -Level INFO

                # Build parameter set for New-ADDomainController — mandatory/defaulted params first
                $params = @{
                    DomainName = $DomainName
                    SiteName   = $SiteName
                }

                # Add optional params only when explicitly bound
                foreach ($p in @('SafeModeAdministratorPassword', 'DomainAdminCredential',
                        'ResourceGroupName', 'KeyVaultName', 'SecretName', 'VaultName',
                        'DatabasePath', 'LogPath', 'SysvolPath')) {
                    if ($PSBoundParameters.ContainsKey($p)) {
                        $params[$p] = $PSBoundParameters[$p]
                    }
                }

                if ($InstallDNS.IsPresent) {
                    $params['InstallDNS'] = $true
                }

                if ($Force.IsPresent) {
                    $params['Force'] = $true
                    # Bypass New-ADDomainController's own ShouldProcess to prevent double-prompt
                    $params['Confirm'] = $false
                }

                # Log parameter summary (excluding secrets and credentials)
                $paramSummary = $params.Keys |
                    Where-Object { $_ -notin @('SafeModeAdministratorPassword', 'DomainAdminCredential') } |
                        ForEach-Object { "$_=$($params[$_])" }
                Write-ToLog -Message "Parameters: $($paramSummary -join ', ')" -Level INFO

                # Call private implementation function
                Write-ToLog -Message "Calling New-ADDomainController" -Level INFO
                New-ADDomainController @params

                Write-ToLog -Message "New-ADDomainController completed successfully" -Level SUCCESS

                # Metrics reporting
                $dnsStatus = if ($InstallDNS.IsPresent) { "with DNS" } else { "without DNS" }
                Write-ToLog -Message "DC promotion metrics - Domain: $DomainName, Site: $SiteName, DNS: $dnsStatus" -Level INFO

                # Return rich object if PassThru requested
                if ($PassThru) {
                    Write-ToLog -Message "PassThru specified - returning configuration object" -Level INFO

                    return [PSCustomObject]@{
                        PSTypeName   = 'Invoke-ADDomainController.ADDSDomainController'
                        DomainName   = $DomainName
                        SiteName     = $SiteName
                        DatabasePath = if ($PSBoundParameters.ContainsKey('DatabasePath')) { $DatabasePath } else { "$env:SYSTEMDRIVE\Windows" }
                        LogPath      = if ($PSBoundParameters.ContainsKey('LogPath')) { $LogPath }      else { "$env:SYSTEMDRIVE\Windows\NTDS" }
                        SysvolPath   = if ($PSBoundParameters.ContainsKey('SysvolPath')) { $SysvolPath }   else { "$env:SYSTEMDRIVE\Windows" }
                        InstallDNS   = $InstallDNS.IsPresent
                        Status       = 'Completed'
                        Timestamp    = [System.DateTimeOffset]::UtcNow.UtcDateTime
                    }
                }
            } else {
                Write-ToLog -Message "Operation cancelled by user (ShouldProcess returned false)" -Level INFO
            }
        } catch {
            $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)✗$($PSStyle.Reset)" } else { "✗" }
            $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "ℹ" }

            $errorMsg = "Failed to promote '$($env:COMPUTERNAME)' to domain controller in '$DomainName'."
            $errorMsg += "`n`n${bullet} Error: $($_.Exception.Message)"
            $errorMsg += "`n`n${tip} Troubleshooting Tips:"
            $errorMsg += "`n  • Verify prerequisites with: Test-PreflightCheck"
            $errorMsg += "`n  • Ensure the target domain '$DomainName' is reachable over the network"
            $errorMsg += "`n  • Verify that AD site '$SiteName' exists in Active Directory"
            $errorMsg += "`n  • Check domain admin credentials have rights to add domain controllers"
            $errorMsg += "`n  • Ensure all paths are on NTFS volumes with adequate free space"
            $errorMsg += "`n  • Check Windows Event Logs (System, Directory Services)"
            $errorMsg += "`n  • Review module logs for detailed diagnostics"
            $errorMsg += "`n  • Test operation with -WhatIf before retrying"

            Write-ToLog -Message "DC promotion failed: $($_.Exception.Message)" -Level ERROR
            Write-ToLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR

            throw $errorMsg
        }
    }

    end {
        Write-ToLog -Message "Invoke-ADDomainController operation completed" -Level INFO
    }
}
