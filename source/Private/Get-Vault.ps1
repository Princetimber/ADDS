#Requires -Version 7.0

# Retrieves Azure Key Vault metadata. Thin wrapper over Get-AzKeyVaultWrapper.
# No platform/elevation checks — owned by Test-PreflightCheck (DRY).
function Get-Vault {
    [CmdletBinding()]
    [OutputType('Microsoft.Azure.Commands.KeyVault.Models.PSKeyVault')]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$KeyVaultName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName
    )

    begin {
        Write-ToLog -Message 'Retrieving Azure Key Vault information...' -Level DEBUG
    }

    process {
        Get-AzKeyVaultWrapper @PSBoundParameters
    }

    end {}
}

# ============================================================================
# WRAPPER FUNCTIONS FOR MOCKABILITY
# ============================================================================

# Wraps Get-AzKeyVault for Pester mocking.
function Get-AzKeyVaultWrapper {
    [CmdletBinding()]
    [OutputType('Microsoft.Azure.Commands.KeyVault.Models.PSKeyVault')]
    param (
        [Parameter()]
        [string]$KeyVaultName,

        [Parameter()]
        [string]$ResourceGroupName
    )

    Get-AzKeyVault @PSBoundParameters
}
