#Requires -Version 7.0

# Sets the module-scoped log file path ($script:LogFilePath and $Global:LogFile).
# Requires a rooted absolute path. -Force creates the directory if it does not exist.
function Set-LogFilePath {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '',
        Justification = 'Maintains backward compatibility with $Global:LogFile usage pattern.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if ([System.IO.Path]::IsPathRooted($_)) { return $true }
                throw "'$_' is not an absolute path. Provide a rooted path (e.g., C:\Logs\module.log)."
            })]
        [string]$Path,

        [Parameter()]
        [switch]$Force
    )

    if ($PSCmdlet.ShouldProcess($Path, "Set log file path")) {
        $logDir = Split-Path -Path $Path -Parent

        if ($Force -and $logDir -and -not ([System.IO.Directory]::Exists($logDir))) {
            $null = New-Item -Path $logDir -ItemType Directory -Force
        }

        $script:LogFile = $Path
        $Global:LogFile = $Path  # Maintain backward compatibility
        $script:LogDirectoryCreated = $false  # Force directory check on next write
        Write-Verbose "Log file path set to: $Path"
    }
}
