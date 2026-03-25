# Changelog for Invoke-ADDS

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `Write-ToLog`: replaced `Write-Host` calls with native PowerShell streams
  (`Write-Verbose`, `Write-Warning`, `Write-Error`, `Write-Information`) so
  output respects `-Verbose`/`-WarningAction` preference variables.
- `source/Invoke-ADDS.psm1`: dot-source failures now `throw` instead of
  `Write-Warning`, surfacing broken function files immediately at import time.
- `Resolve-Dependency.psd1`: set `UsePSResourceGet = $true` to use the modern
  `Microsoft.PowerShell.PSResourceGet` module for dependency resolution.
- `GitVersion.yml`: replaced deprecated `{NuGetVersionV2}` token with `{SemVer}`
  for assembly versioning.

### Fixed

- Renamed `Clear-Logfile.ps1` to `Clear-LogFile.ps1` to match PascalCase function
  name and prevent dot-source failures on case-sensitive file systems (Linux/macOS).
- Renamed `Test-IfPathExistsOrNot.ps1` to `Test-IfPathExistOrNot.ps1` to match the
  actual function name declared inside the file.
- `New-ADDSForest.ps1`: corrected parameter variable `$DomainNetbiosName` to
  `$DomainNetBiosName` to match the declared parameter name (PascalCase).
- `New-ADDomainController.ps1`: renamed parameters `$DataBasePath`/`$SYSVOLPath` to
  `$DatabasePath`/`$SysvolPath` for consistent PascalCase; updated caller
  `Invoke-ADDomainController.ps1` and corresponding unit tests.
- Removed all residual `Invoke-ADDSDomainController` references (replaced with
  `Invoke-ADDomainController`) in source, tests, and module manifest.

## [0.0.2] - 2026-03-24

### Changed

- Renamed `Invoke-ADDSDomainController.ps1` to `Invoke-ADDomainController.ps1` to match the function name it contains.

## [0.0.1] - 2026-03-24

### Added

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

### Fixed

- All source `.ps1` files re-encoded to UTF-8-BOM to resolve
  `PSUseBOMForUnicodeEncodedFile` ScriptAnalyzer warnings in QA tests.
- Bug in `New-ADDomainController`: parameter body referenced `$DatabasePath`
  and `$SysvolPath` instead of the declared `$DataBasePath` and `$SYSVOLPath`,
  causing `New-EnvPath` to throw on empty input and silently skipping those
  paths in preflight validation.
- Pester unit tests for `Add-RegisteredSecretVault`, `Connect-ToAzure`,
  `Disconnect-FromAzure`, `Install-ADModule`, `Invoke-ResourceModule`, and
  `Remove-RegisteredSecretVault`: replaced `$callCount++` pattern (which
  creates a local variable and never mutates the outer value) with a
  `$script:` scoped boolean flag shared across mock scriptblocks.
- `Write-ErrorLog` tests: replaced `$script:BuildErrorRecord` helper (invisible
  inside `InModuleScope`) with inline `ErrorRecord` construction.
- Module manifest `FunctionsToExport`, `Tags`, and `ReleaseNotes` populated.
- Added `Mock Write-ToLog` to `BeforeEach` in six test files to prevent real
  log output during unit test runs.

### Published

- Initial release to PowerShell Gallery as `Invoke-ADDS` v0.0.1.
