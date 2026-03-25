# AGENTS.md

Universal context for AI agents (Cursor, Copilot, Claude, etc.) working in this repository.

## Project

**Invoke-ADDS** — a PowerShell module built with the [Sampler](https://github.com/gaelcolas/Sampler) framework.
Target runtime: **PowerShell 7.0+**.

## Build / Test / Lint

```powershell
# First build (resolves dependencies)
./build.ps1 -ResolveDependency -tasks build

# Subsequent builds
./build.ps1 -tasks build

# Run tests
./build.ps1 -tasks test
# or directly:
Invoke-Pester

# Lint
Invoke-ScriptAnalyzer -Path source/ -Recurse

# Package
./build.ps1 -tasks pack
```

Always run `Invoke-ScriptAnalyzer` after modifying `.ps1`/`.psm1` files and fix all warnings
before committing. Always run the full test suite after code changes, not just tests for
modified files.

## Directory Structure

```
source/
  Public/           # Exported functions (one per file)
  Private/          # Internal helpers (one per file)
  en-US/            # Help files
  Invoke-ADDS.psm1   # Root module (dot-sources Public/ and Private/)
  Invoke-ADDS.psd1   # Module manifest
tests/
  QA/               # ScriptAnalyzer compliance, changelog, help quality
    module.tests.ps1
  Unit/
    Public/          # Tests mirror source/Public/
    Private/         # Tests mirror source/Private/
```

## Code Style

### Functions

- **One function per file**; filename matches function name exactly (e.g. `Get-Greeting.ps1`).
- Always use `[CmdletBinding()]` on advanced functions.
- `SupportsShouldProcess` **only** on state-changing operations (`Set-`, `New-`, `Remove-`, `Export-`).
  Read-only functions (`Get-`, `Test-`, `Find-`) must **never** use `ShouldProcess`.
- Every public function requires comment-based help: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`.
- Input validation is mandatory: `ValidateNotNullOrEmpty`, `ValidateSet`, `ValidatePattern`.

### Naming

- **Functions**: PascalCase with approved Verb-Noun (e.g. `Get-Greeting`, `Export-Greeting`).
- **Parameters**: PascalCase (e.g. `$FilePath`, `$Style`).
- **Local variables**: camelCase (e.g. `$resolvedPath`, `$trimmedName`).

### Error Handling

- Use structured `try/catch/finally`. Never swallow exceptions.
- Construct proper `ErrorRecord` objects with `ThrowTerminatingError` for critical failures.
- Non-terminating errors: `Write-Error -ErrorAction Continue`.

### Logging

- Use `Write-ToLog` (not `Write-Log`) as the standard logging function.
- `Write-ToLog` maps levels to native PowerShell streams:
  - `INFO` / `DEBUG` -> `Write-Verbose`
  - `WARN` -> `Write-Warning`
  - `ERROR` -> `Write-Error`
  - `SUCCESS` -> `Write-Information`

### Prohibited

- Never use `Invoke-Expression`.
- Never hardcode secrets, tokens, or credentials.
- Never suppress exceptions with empty `catch {}` blocks.
- Never add telemetry or background network calls without explicit documentation.

## Testing

- **Framework**: Pester v5+ with `BeforeDiscovery`/`BeforeAll`/`Describe`/`It` structure.
- **Coverage threshold**: 85% (configured in `build.yaml`).
- **Cross-platform**: all tests must run on macOS, Linux, and Windows. Mock Windows-only
  cmdlets (`Get-Service`, `Get-EventLog`, etc.) when needed.
- Test files mirror the source layout: `tests/Unit/Public/Get-Greeting.tests.ps1` tests
  `source/Public/Get-Greeting.ps1`.
- Mock all external dependencies including `Write-ToLog` in unit tests.

### Test Template

```powershell
#Requires -Version 7.0

BeforeAll {
    $script:dscModuleName = 'Invoke-ADDS'
    Import-Module -Name $script:dscModuleName
}

AfterAll {
    Get-Module -Name $script:dscModuleName -All | Remove-Module -Force
}

Describe 'FunctionName' -Tag 'Unit' {
    BeforeAll {
        Mock -ModuleName $script:dscModuleName -CommandName Write-ToLog -MockWith {}
    }

    Context 'When <scenario>' {
        It 'Should <expected behavior>' {
            # Arrange, Act, Assert
        }
    }
}
```

## Dependencies

Defined in `RequiredModules.psd1` (pinned version ranges):

| Module               | Version Range  |
|----------------------|--------------- |
| InvokeBuild          | `[5.0, 6.0)`   |
| PSScriptAnalyzer     | `[1.22, 2.0)`  |
| Pester               | `[5.6, 6.0)`   |
| ModuleBuilder        | `[3.0, 4.0)`   |
| ChangelogManagement  | `[3.0, 4.0)`   |
| Sampler              | `[0.118, 1.0)` |
| Sampler.GitHubTasks  | `[0.6, 1.0)`   |

## CI/CD

- **GitHub Actions**: `.github/workflows/ci.yml` (push to main + PRs, matrix: Linux/Windows/macOS)
  and `.github/workflows/release.yml` (tags `v*`, publishes to PSGallery + GitHub Releases).
- **Azure Pipelines**: `azure-pipelines.yml` (Build -> Test multi-platform -> Coverage -> Deploy).

## Git Workflow

- Make fixes -> run all tests -> run ScriptAnalyzer -> commit to feature branch -> create PR -> merge -> clean up branch.
- Before deleting a branch, switch HEAD away from it first.
- Perform file writes sequentially to avoid cascade failures.

## Agent Principles

- Make the smallest safe change that achieves the goal.
- Follow existing patterns before introducing new architecture.
- Never assume access to live systems or production environments.
- If requirements are unclear, ask rather than guess.
- See `CLAUDE.md` for Claude Code-specific conventions and `.github/copilot-instructions.md`
  for GitHub Copilot instructions.

# context-mode — MANDATORY routing rules

You have context-mode MCP tools available. These rules are NOT optional — they protect your context window from flooding. A single unrouted command can dump 56 KB into context and waste the entire session.

## BLOCKED commands — do NOT attempt these

### curl / wget — BLOCKED
Any shell command containing `curl` or `wget` will be intercepted and blocked by the context-mode plugin. Do NOT retry.
Instead use:
- `context-mode_ctx_fetch_and_index(url, source)` to fetch and index web pages
- `context-mode_ctx_execute(language: "javascript", code: "const r = await fetch(...)")` to run HTTP calls in sandbox

### Inline HTTP — BLOCKED
Any shell command containing `fetch('http`, `requests.get(`, `requests.post(`, `http.get(`, or `http.request(` will be intercepted and blocked. Do NOT retry with shell.
Instead use:
- `context-mode_ctx_execute(language, code)` to run HTTP calls in sandbox — only stdout enters context

### Direct web fetching — BLOCKED
Do NOT use any direct URL fetching tool. Use the sandbox equivalent.
Instead use:
- `context-mode_ctx_fetch_and_index(url, source)` then `context-mode_ctx_search(queries)` to query the indexed content

## REDIRECTED tools — use sandbox equivalents

### Shell (>20 lines output)
Shell is ONLY for: `git`, `mkdir`, `rm`, `mv`, `cd`, `ls`, `npm install`, `pip install`, and other short-output commands.
For everything else, use:
- `context-mode_ctx_batch_execute(commands, queries)` — run multiple commands + search in ONE call
- `context-mode_ctx_execute(language: "shell", code: "...")` — run in sandbox, only stdout enters context

### File reading (for analysis)
If you are reading a file to **edit** it → reading is correct (edit needs content in context).
If you are reading to **analyze, explore, or summarize** → use `context-mode_ctx_execute_file(path, language, code)` instead. Only your printed summary enters context.

### grep / search (large results)
Search results can flood context. Use `context-mode_ctx_execute(language: "shell", code: "grep ...")` to run searches in sandbox. Only your printed summary enters context.

## Tool selection hierarchy

1. **GATHER**: `context-mode_ctx_batch_execute(commands, queries)` — Primary tool. Runs all commands, auto-indexes output, returns search results. ONE call replaces 30+ individual calls.
2. **FOLLOW-UP**: `context-mode_ctx_search(queries: ["q1", "q2", ...])` — Query indexed content. Pass ALL questions as array in ONE call.
3. **PROCESSING**: `context-mode_ctx_execute(language, code)` | `context-mode_ctx_execute_file(path, language, code)` — Sandbox execution. Only stdout enters context.
4. **WEB**: `context-mode_ctx_fetch_and_index(url, source)` then `context-mode_ctx_search(queries)` — Fetch, chunk, index, query. Raw HTML never enters context.
5. **INDEX**: `context-mode_ctx_index(content, source)` — Store content in FTS5 knowledge base for later search.

## Output constraints

- Keep responses under 500 words.
- Write artifacts (code, configs, PRDs) to FILES — never return them as inline text. Return only: file path + 1-line description.
- When indexing content, use descriptive source labels so others can `search(source: "label")` later.

## ctx commands

| Command | Action |
|---------|--------|
| `ctx stats` | Call the `stats` MCP tool and display the full output verbatim |
| `ctx doctor` | Call the `doctor` MCP tool, run the returned shell command, display as checklist |
| `ctx upgrade` | Call the `upgrade` MCP tool, run the returned shell command, display as checklist |
