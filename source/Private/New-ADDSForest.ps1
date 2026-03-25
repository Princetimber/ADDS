#Requires -Version 7.0

# Orchestrates AD DS forest creation: runs preflight, installs features/modules, then creates the forest.
# Password resolution order: (1) -SafeModeAdministratorPassword, (2) Azure KV (-ResourceGroupName + -KeyVaultName + -SecretName),
# (3) pre-registered vault (-VaultName + -SecretName), (4) interactive Read-Host prompt.
# No platform/elevation checks — owned by Test-PreflightCheck (DRY). Permanent operation — always test with -WhatIf first.
function New-ADDSForest {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $DomainName,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $DomainNetBiosName,

        [Parameter(Position = 2)]
        [SecureString]
        $SafeModeAdministratorPassword,

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
        $DatabasePath = "$env:SYSTEMDRIVE\Windows",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $LogPath = "$env:SYSTEMDRIVE\Windows\NTDS",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $SysvolPath = "$env:SYSTEMDRIVE\Windows",

        [Parameter()]
        [switch]
        $InstallDNS,

        [Parameter()]
        [switch]
        $Force
    )

    begin {
        Write-ToLog -Message '=== AD DS Forest Creation Starting ===' -Level INFO
        Write-ToLog -Message "Domain Name: $DomainName" -Level INFO
        Write-ToLog -Message "Domain Mode: $DomainMode, Forest Mode: $ForestMode" -Level INFO

        # Track whether this invocation connected to Azure (for cleanup in finally)
        $azureConnected = $false
    }

    process {
        try {
            # Log bound parameters (safely — never log the password)
            $paramLog = $PSBoundParameters.Keys |
                Where-Object { $_ -ne 'SafeModeAdministratorPassword' } |
                ForEach-Object { "$_=$($PSBoundParameters[$_])" }
            Write-ToLog -Message "Parameters: $($paramLog -join ', ')" -Level DEBUG

            # Pre-flight validation (platform, elevation, features, parent path disk space)
            Write-ToLog -Message 'Running pre-flight checks...' -Level INFO
            $pathsToValidate = @($DatabasePath, $LogPath, $SysvolPath) |
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
                }
                elseif ($VaultName -and $SecretName) {
                    # Validate the vault is registered before attempting retrieval
                    $registeredVault = Get-SecretVaultWrapper -Name $VaultName
                    if (-not $registeredVault) {
                        $availableVaults = Get-SecretVaultWrapper
                        $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)•$($PSStyle.Reset)" } else { '•' }
                        $tip    = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { 'ℹ' }

                        $errorMsg  = "SecretManagement vault '$VaultName' is not registered."
                        if ($availableVaults) {
                            $vaultList = @($availableVaults) | ForEach-Object { "  ${bullet} $($_.Name) (Module: $($_.ModuleName))" }
                            $errorMsg += "`n`nRegistered vaults:`n$($vaultList -join "`n")"
                        }
                        else {
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
                }
                else {
                    if ($ResourceGroupName -or $KeyVaultName -or $SecretName) {
                        Write-ToLog -Message 'Incomplete Key Vault parameters: all three of -ResourceGroupName, -KeyVaultName, and -SecretName are required to use Key Vault. Falling back to interactive password prompt.' -Level WARN
                    }
                    elseif ($VaultName) {
                        Write-ToLog -Message '-VaultName was provided without -SecretName. Falling back to interactive password prompt.' -Level WARN
                    }
                    else {
                        Write-ToLog -Message 'No password or vault parameters provided. User will be prompted to enter the Safe Mode password interactively.' -Level INFO
                    }
                    # $SafeModeAdministratorPassword remains $null;
                    # Get-SafeModePassword (below) will prompt the user securely.
                }
            }

            # Build final ADDS directory paths
            $LOG_PATH      = New-EnvPath -Path $LogPath      -ChildPath 'logs'
            $DATABASE_PATH = New-EnvPath -Path $DatabasePath -ChildPath 'ntds'
            $SYSVOL_PATH   = New-EnvPath -Path $SysvolPath   -ChildPath 'sysvol'

            Write-ToLog -Message "Database Path: $DATABASE_PATH" -Level INFO
            Write-ToLog -Message "Log Path: $LOG_PATH" -Level INFO
            Write-ToLog -Message "SYSVOL Path: $SYSVOL_PATH" -Level INFO

            # Ensure target directories exist (output directories may not pre-exist)
            foreach ($targetPath in @($DATABASE_PATH, $LOG_PATH, $SYSVOL_PATH)) {
                if (-not (Test-PathWrapper -LiteralPath $targetPath)) {
                    New-ItemDirectoryWrapper -Path $targetPath
                    Write-ToLog -Message "Created target directory: $targetPath" -Level INFO
                }
                else {
                    Write-ToLog -Message "Target directory already exists: $targetPath" -Level DEBUG
                }
            }

            # Obtain validated Safe Mode password (prompts if not yet set)
            $SafePwd = Get-SafeModePassword -Password $SafeModeAdministratorPassword

            # Build parameters for Install-ADDSForest
            $CommonParams = @{
                DomainName                    = $DomainName
                DatabasePath                  = $DATABASE_PATH
                LogPath                       = $LOG_PATH
                SysvolPath                    = $SYSVOL_PATH
                SafeModeAdministratorPassword = $SafePwd
                InstallDNS                    = $InstallDNS.IsPresent
            }

            # Add optional parameters only when explicitly bound
            foreach ($p in 'DomainMode', 'ForestMode', 'DomainNetBiosName', 'Force') {
                if ($PSBoundParameters.ContainsKey($p)) {
                    $CommonParams[$p] = $PSBoundParameters[$p]
                }
            }

            # ShouldProcess check — CRITICAL safety gate
            if ($PSCmdlet.ShouldProcess($DomainName, 'Create new Active Directory forest')) {
                Write-ToLog -Message "User confirmed forest creation for domain: $DomainName" -Level INFO
                Write-ToLog -Message 'Initiating AD DS Forest creation...' -Level INFO

                Install-ADDSForestWrapper -Parameters $CommonParams

                Write-ToLog -Message 'AD DS Forest creation command completed successfully' -Level SUCCESS
                Write-ToLog -Message 'System will reboot to complete installation' -Level INFO

                Write-ToLog -Message "Operation Summary - Domain: $DomainName, DNS: $($InstallDNS.IsPresent), Paths: DB=$DATABASE_PATH, Log=$LOG_PATH, SYSVOL=$SYSVOL_PATH" -Level INFO
            }
            else {
                Write-ToLog -Message 'AD DS Forest creation cancelled by user (WhatIf or Confirm declined)' -Level INFO
                Write-ToLog -Message 'No changes were made to the system' -Level INFO
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-ToLog -Message "Failed to create AD DS Forest: $errorMsg" -Level ERROR

            $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)✗$($PSStyle.Reset)" } else { '✗' }
            $tip    = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { 'ℹ' }

            $enhancedError  = "AD DS Forest creation failed for domain '$DomainName'."
            $enhancedError += "`n`nError Details:"
            $enhancedError += "`n  ${bullet} $errorMsg"
            $enhancedError += "`n`n${tip} Troubleshooting Tips:"
            $enhancedError += "`n  • Verify all pre-requisites are met (use Test-PreflightCheck)"
            $enhancedError += "`n  • Ensure paths are valid and accessible"
            $enhancedError += "`n  • Check that domain name is valid and not already in use"
            $enhancedError += "`n  • Review event logs for detailed error information"
            $enhancedError += "`n  • Ensure Safe Mode password meets complexity requirements"

            throw $enhancedError
        }
        finally {
            Write-ToLog -Message 'AD DS Forest creation process completed (success or failure)' -Level INFO
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
        Write-ToLog -Message '=== AD DS Forest Creation Process Ended ===' -Level INFO
    }
}

# ============================================================================
# WRAPPER FUNCTIONS FOR MOCKABILITY
# ============================================================================

# Wraps Install-ADDSForest for Pester mocking.
function Install-ADDSForestWrapper {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function New-ADDSForest.')]
    param(
        [Parameter(Mandatory)]
        [hashtable]
        $Parameters
    )

    Install-ADDSForest @Parameters
}

# Wraps Get-Secret for Pester mocking.
function Get-SecretWrapper {
    [CmdletBinding()]
    [OutputType([SecureString])]
    param(
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [string]
        $Vault
    )

    return Get-Secret -Name $Name -Vault $Vault -AsSecureString
}

# Wraps New-Item -ItemType Directory for Pester mocking.
function New-ItemDirectoryWrapper {
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function New-ADDSForest.')]
    param(
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}
