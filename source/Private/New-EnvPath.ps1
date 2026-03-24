#Requires -Version 7.0

# Joins two path segments into a single path string using Join-Path.
# Pure string operation — no file system access or state changes.
# No platform/elevation checks — those are owned by Test-PreflightCheck (DRY).
function New-EnvPath {
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    # Reason: Pure string helper — constructs a path object only; no system state is modified.
    param (
        [Parameter(Position = 0, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Position = 1, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ChildPath
    )

    try {
        Join-Path -Path $Path -ChildPath $ChildPath
    } catch {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Failed to join paths '$Path' and '$ChildPath': $($_.Exception.Message)", $_.Exception),
            'JoinPathFailed',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            @($Path, $ChildPath)
        )
        $PSCmdlet.ThrowTerminatingError($record)
    }
}
