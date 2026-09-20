#Requires -Version 7.0

# Convenience wrapper around Write-ToLog for ErrorRecord objects.
# Logs the main message at ERROR level; exception type, category, location, and inner exception at DEBUG.
# -IncludeStackTrace appends the PowerShell script stack trace at DEBUG.
function Write-ErrorLog {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter()]
        [string]$Message,

        [Parameter()]
        [switch]$IncludeStackTrace
    )

    # If a custom message prefix is provided, log it before the error details
    if ($Message) {
        Write-ToLog -Message "$Message $($ErrorRecord.Exception.Message)" -Level 'ERROR'
        # Log remaining details as DEBUG
        Write-ToLog -Message "Error Type: $($ErrorRecord.Exception.GetType().FullName)" -Level 'DEBUG'
        Write-ToLog -Message "Error Category: $($ErrorRecord.CategoryInfo.Category)" -Level 'DEBUG'

        if ($ErrorRecord.CategoryInfo.TargetName) {
            Write-ToLog -Message "Target: $($ErrorRecord.CategoryInfo.TargetName)" -Level 'DEBUG'
        }

        if ($ErrorRecord.InvocationInfo) {
            Write-ToLog -Message "Location: $($ErrorRecord.InvocationInfo.ScriptName):$($ErrorRecord.InvocationInfo.ScriptLineNumber)" -Level 'DEBUG'
            Write-ToLog -Message "Command: $($ErrorRecord.InvocationInfo.Line.Trim())" -Level 'DEBUG'
        }

        if ($ErrorRecord.Exception.InnerException) {
            Write-ToLog -Message "Inner Exception: $($ErrorRecord.Exception.InnerException.Message)" -Level 'DEBUG'
        }
    } else {
        # No custom prefix — delegate entirely to Write-ToLog's ErrorRecord parameter set
        Write-ToLog -ErrorRecord $ErrorRecord
    }

    # Stack trace is a unique feature of Write-ErrorLog — only logged when explicitly requested
    if ($IncludeStackTrace -and $ErrorRecord.ScriptStackTrace) {
        Write-ToLog -Message "Stack Trace:`n$($ErrorRecord.ScriptStackTrace)" -Level 'DEBUG'
    }
}
