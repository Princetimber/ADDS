# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Invoke-ADDS** is a production PowerShell module (PowerShell 7.0+) for automating Active Directory Domain Services installation in enterprise environments. Built with the **Sampler** framework.

Two public functions are exported:

| Function | Purpose |
|---|---|
| `Invoke-ADDSForest` | Creates a new AD DS forest (first DC, new domain) |
| `Invoke-ADDomainController` | Promotes a server to an additional DC in an existing domain |

Both are state-changing, irreversible, and cause a system reboot. Always test with `-WhatIf` first.

## PowerShell Development Standards

- Always run `Invoke-ScriptAnalyzer` after modifying any `.ps1` or `.psm1` files and fix all warnings before committing.
- After writing or editing any source file, re-encode with UTF-8-BOM or the QA `PSUseBOMForUnicodeEncodedFile` check fails:
  ```powershell
  Get-ChildItem source/ -Recurse -Include '*.ps1','*.psm1','*.psd1' | ForEach-Object {
      $c = Get-Content $_.FullName -Raw
      [System.IO.File]::WriteAllText($_.FullName, $c, (New-Object System.Text.UTF8Encoding $true))
  }
  ```
- Use `Write-ToLog` (not `Write-Log`) as the standard logging function across all modules.
- All tests must be cross-platform compatible (macOS and Windows). Avoid Windows-only cmdlets without mocking, hardcoded Windows paths, or reliance on Windows-specific environment variables.

## Git & PR Workflow

- When asked to fix and commit, always: (1) make fixes, (2) run all tests, (3) run ScriptAnalyzer, (4) commit to a feature branch, (5) create PR, (6) merge PR, (7) clean up branch.
- Before deleting a branch, ensure HEAD is not checked out on that branch (switch to main first).
- Perform file writes sequentially, not in parallel, to avoid cascade failures.

## Testing

- Always run the full test suite (`Invoke-Pester`) after any code changes, not just the tests for modified files.
- When tests fail, fix and re-run iteratively until all pass before committing.
- Mock Windows-only cmdlets (e.g., `Get-Service`, `Get-EventLog`) when writing tests that need to run cross-platform.
- Always add `Mock Write-ToLog` in a `BeforeEach` block for any function that calls `Write-ToLog`, to suppress log output in tests.

### Pester mock scoping inside InModuleScope

`$callCount++` inside a mock scriptblock creates a **local copy** and never mutates the outer variable. Use a `$script:` scoped boolean flag instead — `$script:` inside `InModuleScope` refers to the module scope, shared across all mock scriptblocks:

```powershell
# WRONG — $callCount never increments
$callCount = 0
Mock Get-StateWrapper { $callCount++; if ($callCount -eq 1) { $null } else { $result } }

# CORRECT
$script:_actionDone = $false
Mock Get-StateWrapper { if ($script:_actionDone) { $result } else { $null } }
Mock Do-ActionWrapper { $script:_actionDone = $true }
```

Helper scriptblocks defined in `BeforeAll` (e.g. `$script:BuildHelper = { ... }`) are also invisible inside `InModuleScope` for the same reason — inline the construction instead.

## Architecture

### Private Function Groups

**Logging system** (7 functions — always available after module load):

| Function | Role |
|---|---|
| `Write-ToLog` | Core entry point. Thread-safe (named mutex), timestamped, INFO/DEBUG/WARN/ERROR/SUCCESS levels, ANSI color, auto-redacts passwords/tokens/keys in key=value, JSON, XML formats |
| `Set-LogFilePath` | Sets `$script:LogFile` (and `$Global:LogFile`). `-Force` creates the directory |
| `Get-LogFilePath` | Returns current log path for inspection |
| `Get-LogFileSize` | Returns size in bytes; `0` if file doesn't exist |
| `Invoke-LogRotation` | Shifts numbered backups (`.1`–`.5`); called inside the mutex by `Write-ToLog`, not for direct use |
| `Clear-LogFile` | Clears log. `ConfirmImpact=High`. `-Archive` saves a `.bak` first |
| `Write-ErrorLog` | Wraps `[ErrorRecord]`: logs message at ERROR, exception type/category/location at DEBUG. `-IncludeStackTrace` appends PS stack |

All file I/O in private functions goes through thin wrapper functions (`Add-ContentWrapper`, `Test-PathWrapper`, `Get-WindowsFeatureWrapper`, etc.) so Pester can mock filesystem and OS calls without touching the real system.

**AD orchestration** (private):

| Function | Role |
|---|---|
| `Test-PreflightCheck` | Single validation source (DRY). Checks: Windows Server ProductType=3, admin elevation, Windows features, required paths, disk space. Throws on first failure. |
| `New-ADDSForest` | Orchestrates forest creation: preflight → module install → feature install → path validation → password resolution → `Install-ADDSForest` |
| `New-ADDomainController` | Orchestrates DC promotion: preflight → module install → feature install → path creation → password resolution → credential prompt → `Install-ADDSDomainController` |
| `Install-ADModule` | Installs AD-Domain-Services Windows feature |
| `Invoke-ResourceModule` | Installs required PowerShell modules |
| `Get-SafeModePassword` | Resolves DSRM password (see order below) |
| `Connect-ToAzure` / `Disconnect-FromAzure` | Azure session management for Key Vault retrieval |
| `Get-Vault` / `Add-RegisteredSecretVault` / `Remove-RegisteredSecretVault` | SecretManagement vault helpers |
| `Test-IfPathExistsOrNot` | Path validation helper |
| `New-EnvPath` | Creates required directories |

### DSRM Password Resolution Order

Both public functions resolve the Safe Mode password in this order (first match wins):

1. `-SafeModeAdministratorPassword` supplied directly as `[securestring]`
2. Azure Key Vault: `-ResourceGroupName` + `-KeyVaultName` + `-SecretName` (triggers `Connect-ToAzure`)
3. Pre-registered SecretManagement vault: `-VaultName` + `-SecretName` (no Azure connection)
4. Interactive `Read-Host` prompt via `Get-SafeModePassword`

### Module Default Paths (set in `Invoke-ADDS.psm1`)

```powershell
$PSDefaultParameterValues = @{
    'Invoke-ADDSForest:DatabasePath'           = "$env:SYSTEMDRIVE\Windows"
    'Invoke-ADDSForest:LogPath'                = "$env:SYSTEMDRIVE\Windows\NTDS\"
    'Invoke-ADDSForest:SYSVOLPATH'             = "$env:SYSTEMDRIVE\Windows"
    'Invoke-ADDSDomainController:SiteName'     = 'Default-First-Site-Name'
    'Invoke-ADDSDomainController:DatabasePath' = "$env:SYSTEMDRIVE\Windows"
    'Invoke-ADDSDomainController:LogPath'      = "$env:SYSTEMDRIVE\Windows\NTDS\"
    'Invoke-ADDSDomainController:SYSVOLPath'   = "$env:SYSTEMDRIVE\Windows"
}
```

## Common Commands

```powershell
# First build (resolves dependencies)
./build.ps1 -ResolveDependency -tasks build

# Subsequent builds
./build.ps1 -tasks build

# Run full test suite
Invoke-Pester

# Run a single test file
Invoke-Pester tests/Unit/Private/Write-ToLog.tests.ps1

# Run tests with coverage
Invoke-Pester -CodeCoverage source/**/*.ps1

# Lint
Invoke-ScriptAnalyzer -Path source/ -Recurse

# Package
./build.ps1 -tasks pack

# Publish (Sampler expects $GalleryApiToken, not $PSGALLERY_API_KEY)
. ./secrets.local.ps1
$env:GalleryApiToken = $env:PSGALLERY_API_KEY
./build.ps1 -tasks publish_psgallery   # or publish_github
```

## Coding Conventions

- **One function per file**, filename matches function name exactly (e.g., `Get-Greeting.ps1`)
- **Advanced functions**: always use `[CmdletBinding()]`
- **SupportsShouldProcess**: required for state-changing operations only (Set-, New-, Remove-, Export-). Never on read-only functions (Get-, Test-, Find-)
- **Comment-based help**: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` on all public functions
- **Input validation**: mandatory — use `ValidateSet`, `ValidatePattern`, `ValidateNotNullOrEmpty`
- **Error handling**: `try/catch/finally`, throw actionable errors, never swallow exceptions
- **Naming**: PascalCase for functions (approved Verb-Noun), PascalCase for parameters, camelCase for local variables
- **No hardcoded secrets** — use SecretManagement module or environment variables
- **Never use `Invoke-Expression`**
- **Graph API** (if applicable): handle throttling (429), transient retries (5xx) with backoff, and pagination (`@odata.nextLink`)

## Testing Conventions

- **Pester v5+** with `BeforeDiscovery`/`BeforeAll`/`Describe`/`It` structure
- Test file structure mirrors source structure
- Mock all external dependencies (Graph API, OS commands, etc.)
- QA tests validate: changelog format, ScriptAnalyzer compliance, help documentation quality
- **85% code coverage threshold** (configured in `build.yaml`)

## CI/CD

- **GitHub Actions** (`.github/workflows/ci.yml` and `release.yml`)
  - CI: Runs on push to main and PRs
  - Matrix testing: Linux, Windows, macOS
  - Release: Publishes to PSGallery and GitHub Releases on tag `v*`

- **Azure Pipelines** (`azure-pipelines.yml`)
  - Stages: Build → Test (multi-platform: Linux, Windows PS7, macOS) → Code Coverage → Deploy
  - Deploy publishes to PSGallery and GitHub Releases on `main` branch

## AI Agent Operating Principles

- Make the smallest safe change that achieves the goal
- Prefer extending existing patterns over introducing new architecture
- Maintain security-first defaults at all times
- Never introduce secrets, tokens, or credentials into code or tests
- Avoid collecting, logging, or exporting sensitive data by default

## AI Agent Workflow Rules

1. **Discover**
   - Read `README.md`, existing module docs, and relevant scripts
   - Identify existing patterns for logging, error handling, auth, retries, and tests

2. **Plan**
   - State proposed approach and affected files
   - Identify required permissions/scopes if Graph/M365 changes are involved
   - Identify tests that should be added/updated

3. **Implement**
   - Follow PowerShell advanced function patterns
   - Use `SupportsShouldProcess` for change operations
   - Add safe input validation and clear error messages
   - Handle Graph throttling (429), transient failures (5xx), and pagination (if applicable)

4. **Validate**
   - Run lint and tests:
     - `Invoke-ScriptAnalyzer -Path source/ -Recurse`
     - `Invoke-Pester`
   - If integration tests exist, they must be opt-in and clearly labeled

5. **Document**
   - Update help/examples when behavior changes
   - Document required Graph scopes/permissions and any operational caveats

## Prohibited Actions

- Do not add or request broad Graph scopes by default
- Do not use `Invoke-Expression` or unsafe string execution
- Do not assume the agent has access to live systems or production environments
- Do not add telemetry, background network calls, or external dependencies without explicit documentation

## Output Expectations

- Produce review-ready PowerShell: readable, testable, idempotent
- Keep changes minimal; avoid drive-by refactors
- If requirements are unclear, ask concise clarifying questions rather than guessing

## Further Reference

- `.github/copilot-instructions.md` — GitHub Copilot-specific instructions
