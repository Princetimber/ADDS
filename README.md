# Invoke-ADDS

A production-ready PowerShell 7.0+ module for automating **Active Directory Domain Services (AD DS)** deployment on Windows Server. Built with the [Sampler](https://github.com/gaelcolas/Sampler) framework.

## What It Does

Two exported functions cover the full AD DS deployment lifecycle:

| Function | Purpose |
|---|---|
| `Invoke-ADDSForest` | Creates a new AD DS forest — first domain controller and root domain |
| `Invoke-ADDomainController` | Promotes a server to an additional domain controller in an existing domain |

Both operations are **irreversible** and **trigger a system reboot**. Always test with `-WhatIf` first.

## Requirements

- PowerShell 7.0+
- Windows Server (ProductType = 3) — validated automatically
- Administrative privileges — validated automatically
- AD-Domain-Services Windows feature available on the server
- Network access to PSGallery (for automatic module installation)

## Quick Start

```powershell
# Install the module
Install-Module -Name Invoke-ADDS

# Always test first
Invoke-ADDSForest -DomainName 'contoso.com' -WhatIf

# Create a new forest with DNS
Invoke-ADDSForest -DomainName 'contoso.com' -InstallDNS

# Promote an additional domain controller
Invoke-ADDomainController -DomainName 'contoso.com' -InstallDNS
```

## DSRM Password Resolution

Both functions resolve the Directory Services Restore Mode (DSRM) password using this priority order — first match wins:

1. **`-SafeModeAdministratorPassword`** — SecureString supplied directly
2. **Azure Key Vault** — `-ResourceGroupName` + `-KeyVaultName` + `-SecretName`
3. **Pre-registered SecretManagement vault** — `-VaultName` + `-SecretName`
4. **Interactive prompt** — secure `Read-Host` when no other source is given

The password is never written to any log file.

## Usage Examples

### Forest with interactive password prompt

```powershell
Invoke-ADDSForest -DomainName 'contoso.com' -InstallDNS
```

### Forest with custom paths and explicit password

```powershell
$dsrmPass = Read-Host 'DSRM Password' -AsSecureString

Invoke-ADDSForest -DomainName 'contoso.com' `
    -SafeModeAdministratorPassword $dsrmPass `
    -DatabasePath 'D:\NTDS' `
    -LogPath      'E:\ADLogs' `
    -SysvolPath   'D:\SYSVOL' `
    -InstallDNS
```

### Forest using Azure Key Vault for the DSRM password

```powershell
Invoke-ADDSForest -DomainName 'contoso.com' `
    -ResourceGroupName 'MyRG' `
    -KeyVaultName      'MyKV' `
    -SecretName        'DSRMPassword' `
    -InstallDNS
```

### Forest using a pre-registered SecretManagement vault

```powershell
# Register the vault once
Register-SecretVault -Name 'LocalStore' -ModuleName 'Microsoft.PowerShell.SecretStore'

Invoke-ADDSForest -DomainName 'contoso.com' `
    -VaultName  'LocalStore' `
    -SecretName 'DSRMPassword' `
    -InstallDNS
```

### Capture forest configuration for auditing

```powershell
$config = Invoke-ADDSForest -DomainName 'contoso.com' -InstallDNS -PassThru
$config | Export-Csv -Path 'forest-config.csv' -NoTypeInformation
```

### Promote an additional DC in a specific site

```powershell
$cred     = Get-Credential
$dsrmPass = Read-Host 'DSRM Password' -AsSecureString

Invoke-ADDomainController -DomainName 'contoso.com' `
    -SiteName                      'London-Site' `
    -SafeModeAdministratorPassword $dsrmPass `
    -DomainAdminCredential         $cred `
    -DatabasePath 'D:\NTDS' `
    -LogPath      'E:\ADLogs' `
    -SysvolPath   'D:\SYSVOL' `
    -InstallDNS
```

### Non-interactive automation

```powershell
try {
    $result = Invoke-ADDSForest -DomainName 'corp.contoso.com' `
                  -VaultName  'CorpVault' `
                  -SecretName 'DSRMPassword' `
                  -InstallDNS -Force -PassThru

    Write-Output "Forest created: $($result.DomainName) at $($result.Timestamp)"
}
catch {
    Write-Error "Forest creation failed: $_"
}
```

## Module Default Paths

These defaults are set when the module loads and can be overridden by supplying the parameter explicitly:

| Parameter | Default |
|---|---|
| `Invoke-ADDSForest -DatabasePath` | `$env:SYSTEMDRIVE\Windows` |
| `Invoke-ADDSForest -LogPath` | `$env:SYSTEMDRIVE\Windows\NTDS\` |
| `Invoke-ADDSForest -SYSVOLPath` | `$env:SYSTEMDRIVE\Windows` |
| `Invoke-ADDSDomainController -SiteName` | `Default-First-Site-Name` |
| `Invoke-ADDSDomainController -DatabasePath` | `$env:SYSTEMDRIVE\Windows` |
| `Invoke-ADDSDomainController -LogPath` | `$env:SYSTEMDRIVE\Windows\NTDS\` |
| `Invoke-ADDSDomainController -SYSVOLPath` | `$env:SYSTEMDRIVE\Windows` |

## Architecture

### Public functions

Both public functions validate parameters and delegate to private orchestration functions. They support `-WhatIf`, `-Confirm`, `-Force`, and `-PassThru`.

### Private orchestration

| Function | Role |
|---|---|
| `New-ADDSForest` | Runs preflight → installs features/modules → resolves DSRM password → builds paths → calls `Install-ADDSForest` |
| `New-ADDomainController` | Same flow for DC promotion; also prompts for domain admin credential if not supplied → calls `Install-ADDSDomainController` |
| `Test-PreflightCheck` | Single validation source: Windows Server platform, admin elevation, Windows features, required paths, and disk space |
| `Install-ADModule` | Installs AD-Domain-Services Windows feature (idempotent) |
| `Invoke-ResourceModule` | Installs required PowerShell modules from PSGallery (idempotent) |
| `Get-SafeModePassword` | Resolves DSRM password across the four-path chain |
| `Connect-ToAzure` / `Disconnect-FromAzure` | Azure session management for Key Vault retrieval |
| `Add-RegisteredSecretVault` / `Remove-RegisteredSecretVault` | SecretManagement vault registration lifecycle |
| `Write-ToLog` | Thread-safe, auto-rotating logger. Redacts passwords, tokens, keys, and secrets before any write |

### Mockability

All external calls (filesystem, OS cmdlets, Azure, AD) go through thin wrapper functions (`Get-WindowsFeatureWrapper`, `Install-WindowsFeatureWrapper`, `Test-PathWrapper`, `Get-AzContextWrapper`, etc.) so every code path can be tested in Pester without touching the real system.

## Development

```powershell
# First build (resolves dependencies)
./build.ps1 -ResolveDependency -tasks build

# Subsequent builds
./build.ps1 -tasks build

# Run all tests
Invoke-Pester

# Run a single test file
Invoke-Pester tests/Unit/Private/Write-ToLog.tests.ps1

# Lint
Invoke-ScriptAnalyzer -Path source/ -Recurse

# Package
./build.ps1 -tasks pack
```

## Publishing

Load credentials first, then publish to the desired target:

```powershell
# Store credentials (gitignored)
Copy-Item secrets.local.ps1.example secrets.local.ps1
# Edit secrets.local.ps1 with your API key(s), then:
. ./secrets.local.ps1

# Sampler reads $GalleryApiToken — bridge from the secrets file variable
$env:GalleryApiToken = $env:PSGALLERY_API_KEY

./build.ps1 -tasks publish_psgallery   # PowerShell Gallery
./build.ps1 -tasks publish_github      # GitHub Release
```

> **Note:** Without `$env:GalleryApiToken` set, the `publish_module_to_gallery` task silently skips with no error.

## CI/CD

### GitHub Actions

| Workflow | Trigger | Platforms | Steps |
|---|---|---|---|
| `ci.yml` | Push to `main`, pull requests | Linux, Windows, macOS | Build → Test → ScriptAnalyzer → Code Coverage |
| `release.yml` | Tag `v*` | Windows | Build → Test → Publish to PSGallery → GitHub Release |

Required secret: `PSGALLERY_API_KEY`

### Azure Pipelines

Stages: **Build → Test** (Linux, Windows PS7, macOS) **→ Code Coverage → Deploy**

Deploy publishes to PSGallery and GitHub Releases on `main`.

Required variables: `GalleryApiToken`, `GitHubToken`

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgements

Built with:
- [Sampler](https://github.com/gaelcolas/Sampler) — PowerShell module build framework
- [Pester](https://github.com/pester/Pester) — PowerShell testing framework
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) — PowerShell linter
- [GitVersion](https://gitversion.net/) — semantic versioning
