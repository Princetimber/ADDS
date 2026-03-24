#Requires -Version 7.0

# Orchestrates DC promotion into an existing AD DS domain: runs preflight, installs features/modules, then promotes.
# Password resolution order: (1) -SafeModeAdministratorPassword, (2) Azure KV (-ResourceGroupName + -KeyVaultName + -SecretName),
# (3) pre-registered vault (-VaultName + -SecretName), (4) interactive prompt via Get-SafeModePassword.
# No platform/elevation checks — owned by Test-PreflightCheck (DRY). Permanent operation — always test with -WhatIf first.
function New-ADDomainController {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [Parameter(Position = 0, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteName = "Default-First-Site-Name",

        [Parameter(Position = 2)]
        [securestring]
        $SafeModeAdministratorPassword,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [pscredential]
        $DomainAdminCredential,

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
        [ValidateNotNullOrEmpty()]
        [string]
        $DataBasePath = "$env:SYSTEMDRIVE\Windows",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $LogPath = "$env:SYSTEMDRIVE\Windows\NTDS",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $SYSVOLPath = "$env:SYSTEMDRIVE\Windows",

        [Parameter()]
        [switch]
        $InstallDNS,

        [Parameter()]
        [switch]
        $Force
    )

    begin {
        Write-ToLog -Message "==== Promoting $($env:COMPUTERNAME) to domain controller in forest $DomainName" -Level INFO
        Write-ToLog -Message " Domain Name: $DomainName" -Level INFO

        # Tracking whether this invokation is connected to Azure (for cleanup in finally block)
        $azureConnected = $false
    }
    process {
      try {
            # log bound parameters (safely - never log passwords or secrets)
            $paramLog = $PSBoundParameters.Keys | Where-Object { $_ -notin @('SafeModeAdministratorPassword', 'DomainAdminCredential', 'SecretName') } | ForEach-Object { "$_=$($PSBoundParameters[$_])"}
            Write-ToLog -Message "Bound parameters: $($paramLog -join ', ')" -Level DEBUG

            # Pre-flight validation
            Write-ToLog -Message 'Running pre-flight checks...' -Level INFO
            $pathsToValidate = @($DataBasePath, $LogPath, $SYSVOLPath) |
                Where-Object { -not [string]::IsNullOrEmpty($_) } |
                    ForEach-Object { Split-Path -Path $_ -Parent } |
                        Where-Object { -not [string]::IsNullOrEmpty($_) } |
                            Select-Object -Unique
            Test-PreflightCheck -RequiredFeatures @('AD-Domain-Services') -RequiredPaths $pathsToValidate

            # Install required modules and features
            Write-ToLog -Message 'Installing required AD module...' -Level INFO
            Install-ADModule

            Write-ToLog -Message 'Installing required PowerShell modules...' -Level INFO
            Invoke-ResourceModule

            # Retrieve Safe Mode password — four paths in priority order:
            #   1. Directly supplied via -SafeModeAdministratorPassword  (skip this block)
            #   2. Azure Key Vault  (all three KV params present)
            #   3. Pre-registered SecretManagement vault  (-VaultName + -SecretName)
            #   4. Interactive prompt  (no password, no vault params — Get-SafeModePassword prompts)
            if (-not $SafeModeAdministratorPassword) {
                if ($ResourceGroupName -and $KeyVaultName -and $SecretName) {
                    Write-ToLog -Message 'Connecting to Azure to retrieve Safe Mode password...' -Level INFO
                    Connect-ToAzure
                    $azureConnected = $true

                    Write-ToLog -Message "Retrieving Key Vault '$KeyVaultName' (Resource Group: '$ResourceGroupName')..." -Level INFO
                    Get-Vault -KeyVaultName $KeyVaultName -ResourceGroupName $ResourceGroupName

                    Add-RegisteredSecretVault -Name $KeyVaultName

                    Write-ToLog -Message "Retrieving Safe Mode password from Key Vault '$KeyVaultName', secret '$SecretName'..." -Level INFO
                    $SafeModeAdministratorPassword = Get-SecretWrapper -Name $SecretName -Vault $KeyVaultName
                } elseif ($VaultName -and $SecretName) {
                    # Validate the vault is registered before attempting retrieval
                    $registeredVault = Get-SecretVaultWrapper -Name $VaultName
                    if (-not $registeredVault) {
                        $availableVaults = Get-SecretVaultWrapper
                        $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)•$($PSStyle.Reset)" } else { '•' }
                        $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { 'ℹ' }

                        $errorMsg = "SecretManagement vault '$VaultName' is not registered."
                        if ($availableVaults) {
                            $vaultList = @($availableVaults) | ForEach-Object { "  ${bullet} $($_.Name) (Module: $($_.ModuleName))" }
                            $errorMsg += "`n`nRegistered vaults:`n$($vaultList -join "`n")"
                        } else {
                            $errorMsg += "`n`n${tip} No vaults are currently registered."
                        }
                        $errorMsg += "`n`n${tip} Register a vault first, for example:"
                        $errorMsg += "`n  ${bullet} SecretStore:    Register-SecretVault -Name '$VaultName' -ModuleName 'Microsoft.PowerShell.SecretStore'"
                        $errorMsg += "`n  ${bullet} HashiCorp:      Register-SecretVault -Name '$VaultName' -ModuleName 'SecretManagement.HashiCorp.Vault.Extension' -VaultParameters @{...}"
                        $errorMsg += "`n  ${bullet} Bitwarden:      Register-SecretVault -Name '$VaultName' -ModuleName 'SecretManagement.BitWarden'"

                        Write-ToLog -Message "Vault '$VaultName' is not registered. Available vaults: $((@($availableVaults) | ForEach-Object { $_.Name }) -join ', ')" -Level ERROR
                        throw $errorMsg
                    }

                    Write-ToLog -Message "Retrieving Safe Mode password from pre-registered vault '$VaultName' (Module: $($registeredVault.ModuleName)), secret '$SecretName'..." -Level INFO
                    $SafeModeAdministratorPassword = Get-SecretWrapper -Name $SecretName -Vault $VaultName
                } else {
                    if ($ResourceGroupName -or $KeyVaultName -or $SecretName) {
                        Write-ToLog -Message 'Incomplete Key Vault parameters: all three of -ResourceGroupName, -KeyVaultName, and -SecretName are required to use Key Vault. Falling back to interactive password prompt.' -Level WARN
                    } elseif ($VaultName) {
                        Write-ToLog -Message '-VaultName was provided without -SecretName. Falling back to interactive password prompt.' -Level WARN
                    } else {
                        Write-ToLog -Message 'No password or vault parameters provided. User will be prompted to enter the Safe Mode password interactively.' -Level INFO
                    }
                    # $SafeModeAdministratorPassword remains $null;
                    # Get-SafeModePassword (below) will prompt the user securely.
                }
            }

            # Retieve Domain Admin credential (if not already supplied)
            if (-not $DomainAdminCredential) {
                Write-ToLog -Message 'No Domain Admin credential supplied. Prompting user to enter credentials...' -Level INFO
                $UserNamePrompt = "Enter username for an existing domain admin in the $DomainName domain"
                $DomainAdminCredential = Get-Credential -Message "Enter credentials for an existing domain admin in the $DomainName domain" -UserName $UserNamePrompt
            }

            # Build final ADDS directory paths
            $LOG_PATH = New-EnvPath -Path $LogPath      -ChildPath 'logs'
            $DATABASE_PATH = New-EnvPath -Path $DataBasePath -ChildPath 'ntds'
            $SYSVOL_PATH = New-EnvPath -Path $SYSVOLPath   -ChildPath 'sysvol'

            Write-ToLog -Message "Database Path: $DATABASE_PATH" -Level INFO
            Write-ToLog -Message "Log Path: $LOG_PATH" -Level INFO
            Write-ToLog -Message "SYSVOL Path: $SYSVOL_PATH" -Level INFO

            # Ensure target directories exist (output directories may not pre-exist)
            foreach ($targetPath in @($DATABASE_PATH, $LOG_PATH, $SYSVOL_PATH)) {
                if (-not (Test-PathWrapper -LiteralPath $targetPath)) {
                    New-ItemDirectoryWrapper -Path $targetPath
                    Write-ToLog -Message "Created target directory: $targetPath" -Level INFO
                } else {
                    Write-ToLog -Message "Target directory already exists: $targetPath" -Level DEBUG
                }
            }

            # Obtain validated Safe Mode password (prompts if not yet set)
            $SafePwd = Get-SafeModePassword -Password $SafeModeAdministratorPassword

            # Build parameters for Install-ADDSDomainController
            $installParams = @{
                DomainName                    = $DomainName
                SiteName                      = $SiteName
                SafeModeAdministratorPassword = $SafePwd
                DatabasePath                  = $DATABASE_PATH
                LogPath                       = $LOG_PATH
                SYSVOLPath                    = $SYSVOL_PATH
                InstallDNS                    = $InstallDNS.IsPresent
            }

            # Always add credential (either supplied via param or collected via prompt above)
            if ($DomainAdminCredential) {
                $installParams['Credential'] = $DomainAdminCredential
            }

            # Pass Force through only if the switch was explicitly provided
            if ($Force.IsPresent) {
                $installParams['Force'] = $true
            }

            # ShouldProcess check - CRITICAL safety gate before making any system changes
            if ($PSCmdlet.ShouldProcess("Promote $($env:COMPUTERNAME) to domain controller in the forest $DomainName")) {
                Write-ToLog -Message "User confirmed action. Proceeding with domain controller promotion..." -Level INFO
                Write-ToLog -Message "Installing Active Directory Domain Services role, and then promoting to domain controller..." -Level INFO

                Install-ADDomainControllerWrapper -Parameters $installParams

                Write-ToLog -Message "Domain controller promotion process has completed. A reboot may be required to finalize the promotion." -Level INFO
                Write-ToLog -Message "Operation Summary - Domain: $DomainName, Site: $SiteName, InstallDNS: $($InstallDNS.IsPresent), DatabasePath: $DATABASE_PATH, LogPath: $LOG_PATH, SYSVOLPath: $SYSVOL_PATH" -Level INFO
            } else {
                Write-ToLog -Message "User cancelled the domain controller promotion process.(Whatif or Confirm declined)" -Level WARN
                Write-ToLog -Message "No changes have been made to the system." -Level INFO
            }
      }
      catch {
            $errorMsg = $_.Exception.Message
            Write-ToLog -Message "Failed to promote domain controller: $errorMsg" -Level ERROR

            $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)✗$($PSStyle.Reset)" } else { '✗' }
            $tip = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { 'ℹ' }

            $enhancedError = "Domain controller promotion failed for domain '$DomainName'."
            $enhancedError += "`n`nError Details:"
            $enhancedError += "`n  ${bullet} $errorMsg"
            $enhancedError += "`n`n${tip} Troubleshooting Tips:"
            $enhancedError += "`n  • Verify all pre-requisites are met (use Test-PreflightCheck)"
            $enhancedError += "`n  • Ensure paths are valid and accessible"
            $enhancedError += "`n  • Check that domain name is valid and not already in use"
            $enhancedError += "`n  • Review event logs for detailed error information"
            $enhancedError += "`n  • Ensure Safe Mode password meets complexity requirements"
            Write-ToLog -Message $enhancedError -Level ERROR

            throw $enhancedError

      }
      finally {
            Write-ToLog -Message 'Domain controller promotion process completed (success or failure)' -Level INFO
            Write-ToLog -Message 'Performing cleanup...' -Level DEBUG

            # Only clean up Azure resources if this invocation established the connection
            if ($azureConnected) {
                Remove-RegisteredSecretVault -Name $KeyVaultName
                Disconnect-FromAzure
                $azureConnected = $false
            }
      }
    }

    end {
        Write-ToLog -Message "Finished processing New-ADDomainController for domain '$DomainName'." -Level INFO
    }
}

# ============================================================================
# WRAPPER FUNCTIONS FOR MOCKABILITY
# ============================================================================

# Wraps Install-ADDSDomainController for Pester mocking.
function Install-ADDomainControllerWrapper {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function New-ADDomainController.')]
    param(
        [Parameter(Mandatory)]
        [hashtable]
        $Parameters
    )

    Install-ADDSDomainController @Parameters
}
