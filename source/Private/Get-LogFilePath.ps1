#Requires -Version 7.0

# Returns the current module-scoped log file path ($script:LogFilePath).
function Get-LogFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $script:LogFile
}
