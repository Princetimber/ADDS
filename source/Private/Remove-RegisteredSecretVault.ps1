#Requires -Version 7.0

# Unregisters a SecretManagement vault and verifies removal.
# Idempotent — skips if the vault is not currently registered. Metrics in end block.
# No platform/elevation checks — owned by Test-PreflightCheck (DRY).
function Remove-RegisteredSecretVault {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    begin {
        Write-ToLog -Message 'Starting secret vault unregistration process...' -Level INFO

        $vaultsAttempted  = 0
        $vaultsRemoved    = 0
        $vaultsSkipped    = 0
        $vaultsFailed     = 0
        $lastError        = $null
    }

    process {
        try {
            # Resolve Name from current vault if not supplied
            if (-not $PSBoundParameters.ContainsKey('Name')) {
                $vaultInfo = Get-Vault
                if (-not $vaultInfo) {
                    $errorMsg = 'No -Name supplied and Get-Vault returned no Key Vaults in the current context.'
                    Write-ToLog -Message $errorMsg -Level ERROR
                    $vaultsFailed++
                    $lastError = [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new($errorMsg),
                        'NoKeyVaultFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $null
                    )
                    return
                }
                $Name = $vaultInfo.VaultName
            }

            Write-ToLog -Message "Processing secret vault unregistration for '$Name'..." -Level DEBUG
            $vaultsAttempted++

            # Check whether the vault is currently registered — idempotent
            $existingVault = Get-SecretVaultWrapper -Name $Name
            if (-not $existingVault) {
                Write-ToLog -Message "Secret vault '$Name' is not currently registered. Skipping." -Level DEBUG
                $vaultsSkipped++
                return
            }

            # Unregister the vault
            Write-ToLog -Message "Unregistering secret vault '$Name'..." -Level INFO

            if ($PSCmdlet.ShouldProcess($Name, 'Unregister-SecretVault')) {
                Unregister-SecretVaultWrapper -Name $Name

                # Post-unregister verification
                $remainingVault = Get-SecretVaultWrapper -Name $Name
                if (-not $remainingVault) {
                    Write-ToLog -Message "Secret vault '$Name' unregistered successfully." -Level SUCCESS
                    $vaultsRemoved++
                }
                else {
                    $bullet = if ($PSStyle) { "$($PSStyle.Foreground.Red)•$($PSStyle.Reset)" } else { "`e[31m•`e[0m" }
                    $tip    = if ($PSStyle) { "$($PSStyle.Foreground.Yellow)ℹ$($PSStyle.Reset)" } else { "`e[33mℹ`e[0m" }

                    $errorMsg  = "Post-unregister verification failed: vault '$Name' still present after Unregister-SecretVault."
                    $errorMsg += "`n`n${tip} Tips:"
                    $errorMsg += "`n  ${bullet} Retry Remove-RegisteredSecretVault"
                    $errorMsg += "`n  ${bullet} Run Unregister-SecretVault -Name '$Name' manually"
                    $errorMsg += "`n  ${bullet} Run Get-SecretVault to inspect registered vaults"

                    Write-ToLog -Message "Post-unregister verification failed for '$Name'." -Level ERROR
                    $vaultsFailed++
                    $lastError = [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new($errorMsg),
                        'SecretVaultUnregisterVerificationFailed',
                        [System.Management.Automation.ErrorCategory]::InvalidResult,
                        $null
                    )
                }
            }
        }
        catch {
            Write-ToLog -Message "Failed to unregister secret vault '$Name': $($_.Exception.Message)" -Level ERROR
            $vaultsFailed++
            $lastError = $_
        }
    }

    end {
        $successRate = if ($vaultsAttempted -gt 0) {
            [Math]::Round((($vaultsRemoved + $vaultsSkipped) / $vaultsAttempted) * 100, 2)
        }
        else { 0 }

        Write-ToLog -Message "Secret vault unregistration completed - Total: $vaultsAttempted, Removed: $vaultsRemoved, Skipped: $vaultsSkipped, Failed: $vaultsFailed, Success Rate: $successRate%" -Level INFO

        if ($vaultsFailed -gt 0) {
            Write-ToLog -Message "Secret vault unregistration completed with $vaultsFailed failure(s)." -Level WARN
        }
        elseif ($vaultsRemoved -gt 0) {
            Write-ToLog -Message 'Secret vault unregistration completed successfully.' -Level SUCCESS
        }

        if ($lastError) {
            $PSCmdlet.ThrowTerminatingError($lastError)
        }
    }
}

# ============================================================================
# WRAPPER FUNCTIONS FOR MOCKABILITY
# ============================================================================

# Wraps Get-SecretVault for Pester mocking.
function Get-SecretVaultWrapper {
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter()]
        [string]$Name
    )

    if ($Name) {
        return Get-SecretVault -Name $Name -ErrorAction SilentlyContinue
    }
    else {
        return Get-SecretVault -ErrorAction SilentlyContinue
    }
}

# Wraps Unregister-SecretVault for Pester mocking.
function Unregister-SecretVaultWrapper {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function; ShouldProcess handled by calling function Remove-RegisteredSecretVault.')]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    Unregister-SecretVault -Name $Name -Confirm:$false
}
