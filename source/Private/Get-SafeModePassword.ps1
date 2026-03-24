#Requires -Version 7.0

# Returns the DSRM password as a SecureString.
# Uses -Password if supplied; otherwise prompts interactively via Read-Host -AsSecureString.
# Never logs the password value.
function Get-SafeModePassword {
    [CmdletBinding()]
    [OutputType([SecureString])]
    param (
        [Parameter(Position = 0)]
        [SecureString]
        $Password
    )

    if ($Password) {
        Write-ToLog -Message "Safe Mode password provided via parameter (secure)" -Level DEBUG
        return $Password
    }

    Write-ToLog -Message "Prompting user for Safe Mode Administrator password" -Level INFO

    try {
        $securePassword = Read-HostWrapper -Prompt "Enter Safe Mode Administrator password" -AsSecureString

        if (-not $securePassword) {
            throw "Safe Mode password cannot be empty"
        }

        Write-ToLog -Message "Safe Mode password obtained from interactive prompt (secure)" -Level DEBUG
        return $securePassword
    } catch {
        Write-ToLog -Message "Failed to obtain Safe Mode password: $($_.Exception.Message)" -Level ERROR
        throw "Failed to obtain Safe Mode Administrator password. User may have cancelled the operation or provided invalid input."
    }
}

# Helper function for mockability in tests
function Read-HostWrapper {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingReadHost', '',
        Justification = 'Wrapper function for Read-Host to enable mocking in unit tests. Read-Host is required for secure password prompts.')]
    param(
        [Parameter(Mandatory)]
        [string]
        $Prompt,

        [Parameter()]
        [switch]
        $AsSecureString
    )

    return Read-Host -Prompt $Prompt -AsSecureString:$AsSecureString
}