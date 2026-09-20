# Changelog for Invoke-ADDS

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `New-ADDSForest` and `New-ADDomainController` no longer install the AD-Domain-Services
  feature or required PowerShell modules before their `ShouldProcess` check — those
  state-changing calls now run inside the gate, so `-WhatIf` no longer leaks real side
  effects.
- Renamed `Write-ErroLog.ps1` to `Write-ErrorLog.ps1`, `Test-IfPathExistsOrNot.ps1` to
  `Test-IfPathExistOrNot.ps1`, and `Clear-Logfile.ps1` to `Clear-LogFile.ps1` so each
  private function's filename matches the function it contains.
- `tests/QA/module.tests.ps1` scoped its comment-based-help/example/parameter-description
  checks to exported (Public) functions only. It previously enumerated every function
  including private wrappers, which have no comment-based help by design.
- Manifest: uncommented `CompatiblePSEditions = @('Core')`.
- Replaced the plaintext `ConvertTo-SecureString 'YourPassword' -AsPlainText -Force`
  placeholder in `Invoke-ADDSForest`/`Invoke-ADDomainController` help examples with a
  `Get-Secret ... -AsSecureString` example.

### Added

- `Connect-ToAzure` now supports Managed Identity (`-UseManagedIdentity`), workload
  identity federation (`-FederatedToken`/`-ApplicationId`/`-TenantId`), app-only
  certificate (`-CertificateThumbprint`/`-CertificateApplicationId`/`-TenantId`), and
  client secret (`-ServicePrincipalCredential`/`-TenantId`) authentication, in addition
  to interactive browser and device code. Device code remains the default when no
  credential is supplied, but is now treated as a last resort: it logs a warning naming
  the stronger alternatives, and a Conditional-Access block is detected and rethrown as
  an actionable error pointing at those alternatives instead of a raw MSAL error.
- `Connect-ToAzure -UseExistingContext` makes reuse of an already-active Az context an
  explicit, checkable request: it throws an actionable error naming the other
  authentication parameter sets when no context is currently active, instead of
  silently falling through to a device-code sign-in attempt.

### Changed

- Pester pinned to `[6.0.0,7.0)` (was `[5.6,6.0)`); all test files pin
  `ModuleVersion = '6.0.0'` via `#Requires -Modules`.

### Fixed

- `RequiredModules.psd1`: `Sampler.GitHubTasks` was pinned to `[0.6,1.0)`, a range
  never published to PSGallery (latest is `0.4.1`), so CI's dependency resolution
  failed on every build with "No version of [Sampler.GitHubTasks] in [PSGallery]
  satisfies range". Repinned to `[0.4.1,1.0)`. Also bumped `InvokeBuild`'s lower
  bound to `5.10.5` to avoid a `ProgressAction` parameter collision on PowerShell
  7.4+ if an older cached version is ever picked up.
- `Resolve-Dependency.psd1`: dependency bootstrap had both `UsePSResourceGet` and
  `UseModuleFast` disabled, forcing the legacy PowerShellGet fallback path, which
  calls `Install-PackageProvider`/`Install-Package` and requires elevation. This
  failed the "Build Module" CI job on every push to `main` since CI was created,
  with "Administrator rights are required... or install by adding -Scope
  CurrentUser" on the unelevated `ubuntu-latest` runner. Enabled
  `UsePSResourceGet` and bumped `PSResourceGetVersion` from `1.0.1` to `1.2.0`
  (the pinned version could not reliably resolve PSGallery V2 metadata);
  `Save-PSResource` installs to the user scope without elevation. Verified with
  `pwsh -NoProfile -File ./Resolve-Dependency.ps1`, which resolved and installed
  every dependency cleanly.
- `RequiredModules.psd1`: `ModuleBuilder` depends on `Configuration`, but it was
  never listed as a direct dependency, so `Save-PSResource` never fetched it.
  This surfaced only after the fix above, as `Import-Module -Name ModuleBuilder`
  failing with "The required module 'Configuration' is not loaded." during the
  `Build_ModuleOutput_ModuleBuilder` task. Added `Configuration = '[1.3.1,2.0)'`.
- `.github/workflows/ci.yml`: with the build job now succeeding, the `test`
  job's `[ubuntu-latest, windows-latest, macos-latest]` matrix ran for the
  first time and failed on the two non-Windows runners — this module targets
  Windows Server only, and the test suite intentionally hardcodes Windows
  paths/`Get-CimInstance` rather than mocking for cross-platform. Restricted
  the `test` job to `windows-latest` only.
- With the `test` job now reachable, it also failed its own 85% code-coverage
  gate at 79.07%. Added tests exercising previously-unexercised branches:
  the outer error-handling `catch` in `Invoke-ADDSForest`/
  `Invoke-ADDomainController` (mocking the private implementation function to
  throw), the pre-registered-vault "list other registered vaults" branch in
  `New-ADDSForest`/`New-ADDomainController`, the "list available repositories"
  and "module not found in PSGallery" branches in `Invoke-ResourceModule`, and
  direct calls to the thin wrapper functions that front built-in cmdlets
  (`Test-PathWrapper`, `New-ItemDirectoryWrapper`, `Get-ItemWrapper`,
  `Add-ContentWrapper`, `Move-ItemWrapper`, `Remove-ItemWrapper`,
  `Read-HostWrapper`, `Copy-ItemWrapper`, `Clear-ContentWrapper`,
  `Get-ModuleWrapper`) — these were previously only ever mocked by callers,
  never tested themselves. Measured locally via
  `Invoke-Pester -CodeCoverage` (macOS delta, used as a relative signal since
  16 Windows-only tests always fail there): missed commands dropped from 449
  to 348, a larger reduction than the 86 needed to clear 85% against the
  Windows-runner baseline of 1145/1448 (79.07%).

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
