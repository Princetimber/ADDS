# Changelog for {{MODULE_NAME}}

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Export-Greeting public function demonstrating correct ShouldProcess usage for
  state-changing operations (file writes with -WhatIf, -Confirm, -Force, -Append,
  -PassThru support).
- Clear-LogFile private function — clears the active log file with optional
  timestamped archive backup before clearing. ConfirmImpact=High always prompts
  unless -Force or -Confirm:$false is passed.
- Get-LogFilePath private function — returns the current module-scoped log file
  path ($script:LogFile) for inspection or use in external scripts.
- Get-LogFileSize private function — returns the current log file size in bytes;
  returns 0 if the log file does not yet exist.
- Invoke-LogRotation private function — rotates log files by shifting numbered
  backups up (log.4 removed, log.3 → log.4, …, log → log.1). Called inside the
  Write-ToLog mutex; not intended for direct use.
- Set-LogFilePath private function — sets the module-scoped log file path with
  absolute-path validation; -Force creates the destination directory on demand.
  Also updates $Global:LogFile for backward compatibility.
- Write-ErrorLog private function — convenience wrapper around Write-ToLog for
  ErrorRecord objects. Logs the main message at ERROR level; exception type,
  category, location, and inner exception at DEBUG. -IncludeStackTrace appends
  the PowerShell script stack trace.

### Changed

- Rebuilt Write-ToLog as a production-grade, thread-safe logging framework:
  - Named mutex (Global\Invoke-ADDSDomainControllerLog) prevents concurrent write
    corruption across threads and runspaces.
  - Auto-rotates at 10 MB, keeping up to 5 numbered backup files.
  - Redacts passwords, tokens, keys, and secrets in key=value, JSON, and XML/HTML
    formats before writing.
  - ANSI colour console output via PSStyle (7.2+) with escape-code fallback.
  - Dedicated ErrorRecord parameter set for structured exception logging.
  - Wrapper functions (Test-PathWrapper, Add-ContentWrapper, Get-ItemWrapper,
    New-ItemDirectoryWrapper) isolate I/O calls for Pester mockability.
  - Mutex is disposed on PowerShell exit via Register-EngineEvent.
- Removed ShouldProcess from Get-Greeting — read-only functions should not use
  SupportsShouldProcess. Removed Force parameter accordingly.
- Replaced string-throw error handling in Get-Greeting with proper ErrorRecord
  construction via ThrowTerminatingError.
- Replaced AllowEmptyString with ValidateNotNullOrEmpty and ValidatePattern on
  Format-GreetingMessage Name parameter.
- Pinned dependency versions in RequiredModules.psd1 using version ranges instead
  of 'latest'.
- Consolidated AI agent documentation: removed .github/instructions/ directory
  (5 files) and tests/tests.instructions.md, trimmed copilot-instructions.md.
- Updated README, CLAUDE.md, and help text to reflect all changes.

### Removed

- Windows PowerShell 5.1 test job from azure-pipelines.yml (contradicts PS 7.0
  requirement in #Requires).
- .github/instructions/ directory and tests/tests.instructions.md.
- Classes/ directory reference from documentation (directory did not exist).
