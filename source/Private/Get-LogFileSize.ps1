#Requires -Version 7.0

# Returns the current log file size in bytes. Returns 0 if the file does not exist.
function Get-LogFileSize {
    [CmdletBinding()]
    [OutputType([long])]
    param()

    if (Test-PathWrapper -LiteralPath $script:LogFile) {
        return (Get-ItemWrapper -LiteralPath $script:LogFile).Length
    }
    return [long]0
}
