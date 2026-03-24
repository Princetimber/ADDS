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

### `Invoke-ADDSForest`

#### Forest with interactive password prompt

```powershell
Invoke-ADDSForest -DomainName 'contoso.com' -InstallDNS
```

#### Forest with custom paths and explicit password

```powershell
$dsrmPass = Read-Host 'DSRM Password' -AsSecureString

Invoke-ADDSForest -DomainName 'contoso.com' `
    -SafeModeAdministratorPassword $dsrmPass `
    -DatabasePath 'D:\NTDS' `
    -LogPath      'E:\ADLogs' `
    -SysvolPath   'D:\SYSVOL' `
    -InstallDNS
```

#### Forest using Azure Key Vault for the DSRM password

```powershell
Invoke-ADDSForest -DomainName 'contoso.com' `
    -ResourceGroupName 'MyRG' `
    -KeyVaultName      'MyKV' `
    -SecretName        'DSRMPassword' `
    -InstallDNS
```

#### Forest using a pre-registered SecretManagement vault

```powershell
# Register the vault once
Register-SecretVault -Name 'LocalStore' -ModuleName 'Microsoft.PowerShell.SecretStore'

Invoke-ADDSForest -DomainName 'contoso.com' `
    -VaultName  'LocalStore' `
    -SecretName 'DSRMPassword' `
    -InstallDNS
```

#### Capture forest configuration for auditing

```powershell
$config = Invoke-ADDSForest -DomainName 'contoso.com' -InstallDNS -PassThru
$config | Export-Csv -Path 'forest-config.csv' -NoTypeInformation
```

#### Non-interactive forest automation

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

---

### `Invoke-ADDomainController`

Promotes an existing Windows Server to an **additional domain controller** in an already-running AD DS domain. The domain must exist and be reachable before running this command.

#### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `DomainName` | `string` | Yes | FQDN of the existing domain to join (e.g. `contoso.com`) |
| `SiteName` | `string` | No | AD site to register the DC in. Default: `Default-First-Site-Name` |
| `SafeModeAdministratorPassword` | `securestring` | No | DSRM password. Prompted interactively if omitted |
| `DomainAdminCredential` | `pscredential` | No | Domain admin account. Prompted interactively if omitted |
| `DatabasePath` | `string` | No | Path for `NTDS.dit`. Default: `$env:SYSTEMDRIVE\Windows` |
| `LogPath` | `string` | No | Path for AD transaction logs. Default: `$env:SYSTEMDRIVE\Windows\NTDS` |
| `SysvolPath` | `string` | No | Path for SYSVOL. Default: `$env:SYSTEMDRIVE\Windows` |
| `ResourceGroupName` | `string` | No | Azure Resource Group containing the Key Vault |
| `KeyVaultName` | `string` | No | Azure Key Vault name holding the DSRM secret |
| `SecretName` | `string` | No | Secret name in Key Vault or SecretManagement vault |
| `VaultName` | `string` | No | Pre-registered SecretManagement vault name (no Azure connection) |
| `InstallDNS` | `switch` | No | Install the DNS Server role as part of DC promotion |
| `Force` | `switch` | No | Suppress all confirmation prompts (use with caution) |
| `PassThru` | `switch` | No | Return a configuration object after completion |
| `-WhatIf` | `switch` | No | Preview the operation without executing |
| `-Confirm` | `switch` | No | Prompt before each state-changing action |

**`-PassThru` output object properties:** `DomainName`, `SiteName`, `DatabasePath`, `LogPath`, `SysvolPath`, `InstallDNS`, `Status`, `Timestamp`

#### Test before you run

```powershell
# Always validate parameters and prerequisites first — no changes are made
Invoke-ADDomainController -DomainName 'contoso.com' -WhatIf
```

#### Basic promotion with interactive prompts

```powershell
# Prompts for DSRM password and domain admin credentials interactively
Invoke-ADDomainController -DomainName 'contoso.com' -InstallDNS
```

The function will:
- Prompt for the Safe Mode Administrator (DSRM) password
- Prompt for domain administrator credentials
- Prompt for confirmation before proceeding
- Register the DC in `Default-First-Site-Name`
- Install the DNS Server role
- Use default paths for the database, logs, and SYSVOL

#### Promote to a specific site with dedicated storage

```powershell
$cred     = Get-Credential -Message 'Enter domain admin credentials'
$dsrmPass = Read-Host 'DSRM Password' -AsSecureString

Invoke-ADDomainController -DomainName 'corp.example.com' `
    -SiteName                      'London-Site' `
    -SafeModeAdministratorPassword $dsrmPass `
    -DomainAdminCredential         $cred `
    -DatabasePath                  'D:\NTDS' `
    -LogPath                       'E:\ADLogs' `
    -SysvolPath                    'D:\SYSVOL' `
    -InstallDNS `
    -Confirm:$false
```

Explicit credentials and password are supplied — no interactive prompts appear.

#### Retrieve DSRM password from Azure Key Vault

```powershell
Invoke-ADDomainController -DomainName 'contoso.com' `
    -ResourceGroupName 'MyRG' `
    -KeyVaultName      'MyKV' `
    -SecretName        'DSRMPassword' `
    -InstallDNS
```

Connects to Azure (handled automatically), retrieves the secret, then disconnects. Domain admin credentials are still prompted interactively.

#### Retrieve DSRM password from a pre-registered SecretManagement vault

```powershell
# Register the vault once (no Azure connection required)
Register-SecretVault -Name 'LocalStore' -ModuleName 'Microsoft.PowerShell.SecretStore'

Invoke-ADDomainController -DomainName 'contoso.com' `
    -VaultName  'LocalStore' `
    -SecretName 'DSRMPassword' `
    -InstallDNS
```

#### Capture DC configuration for auditing

```powershell
$config = Invoke-ADDomainController -DomainName 'contoso.com' `
    -SiteName     'HQ-Site' `
    -DatabasePath 'D:\NTDS' `
    -LogPath      'E:\ADLogs' `
    -SysvolPath   'D:\SYSVOL' `
    -InstallDNS `
    -PassThru

$config | Export-Csv -Path 'dc-config.csv' -NoTypeInformation
```

#### Non-interactive automation with error handling

```powershell
try {
    $params = @{
        DomainName                    = 'automation.corp.com'
        SiteName                      = 'DataCenter-Site'
        SafeModeAdministratorPassword = $vaultPassword   # SecureString from vault
        DomainAdminCredential         = $adminCred       # PSCredential from vault
        DatabasePath                  = 'D:\NTDS'
        LogPath                       = 'E:\Logs'
        SysvolPath                    = 'D:\SYSVOL'
        InstallDNS                    = $true
        Force                         = $true
        PassThru                      = $true
    }

    $result = Invoke-ADDomainController @params

    if ($result.Status -eq 'Completed') {
        Write-Output "DC promotion completed: $($result.DomainName) / $($result.SiteName) at $($result.Timestamp)"
    }
}
catch {
    Write-Error "DC promotion failed: $_"
    # Send alert to your monitoring system here
}
```

Uses parameter splatting for readability. Passwords and credentials come from a vault — nothing is hardcoded. `-Force` skips all confirmation prompts for fully unattended execution.

## Module Default Paths

These defaults are set when the module loads and can be overridden by supplying the parameter explicitly:

| Parameter | Default |
|---|---|
| `Invoke-ADDSForest -DatabasePath` | `$env:SYSTEMDRIVE\Windows` |
| `Invoke-ADDSForest -LogPath` | `$env:SYSTEMDRIVE\Windows\NTDS\` |
| `Invoke-ADDSForest -SYSVOLPath` | `$env:SYSTEMDRIVE\Windows` |
| `Invoke-ADDomainController -SiteName` | `Default-First-Site-Name` |
| `Invoke-ADDomainController -DatabasePath` | `$env:SYSTEMDRIVE\Windows` |
| `Invoke-ADDomainController -LogPath` | `$env:SYSTEMDRIVE\Windows\NTDS\` |
| `Invoke-ADDomainController -SYSVOLPath` | `$env:SYSTEMDRIVE\Windows` |

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
