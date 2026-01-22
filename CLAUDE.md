# PSVergeOS

> *Purpose: PowerShell module for automating VergeOS infrastructure management, targeting administrators migrating from VMware PowerCLI or building automation pipelines.*

A PowerShell module wrapping the VergeOS REST API (v4) with idiomatic cmdlets for VM lifecycle, networking, storage, and multi-tenant management.

## Tech Stack

- **Language**: PowerShell 7.4+ (LTS) - cross-platform (Windows, macOS, Linux)
- **Package Manager**: PowerShell Gallery
- **Dependencies**: Standard PowerShell modules only (no external dependencies)
- **Authentication**: Bearer token or session cookie via VergeOS API
- **Testing**: Pester (>90% code coverage target)

## Project Structure

```text
PSVergeOS/
├── PSVergeOS.psd1           # Module manifest
├── PSVergeOS.psm1           # Root module loader
│
├── Public/                   # Exported cmdlets (user-facing)
│   ├── Connect-VergeOS.ps1
│   ├── Disconnect-VergeOS.ps1
│   ├── VM/
│   │   ├── Get-VergeVM.ps1
│   │   ├── New-VergeVM.ps1
│   │   └── ...
│   ├── Network/
│   └── ...
├── Private/                  # Internal functions
│   ├── Invoke-VergeAPI.ps1  # Core API wrapper
│   └── ConvertTo-VergeFilter.ps1
├── Classes/                  # PowerShell classes
│   ├── VergeConnection.ps1
│   └── VergeVM.ps1
│
├── Tests/
│   ├── Unit/
│   └── Integration/
├── Examples/                 # Runnable example scripts
├── docs/cmdlets/            # Generated help documentation
│
├── PRD.md                   # Product requirements
└── README.md                # User-facing documentation
```

## Commands

```bash
# Run all tests
Invoke-Pester -Path ./Tests

# Run single test file
Invoke-Pester -Path ./Tests/Unit/Get-VergeVM.Tests.ps1

# Run tests with coverage
Invoke-Pester -Path ./Tests -CodeCoverage ./Public/**/*.ps1

# Import module locally for development
Import-Module ./PSVergeOS.psd1 -Force

# Analyze code quality
Invoke-ScriptAnalyzer -Path ./Public -Recurse
```

## Reference Documentation

| Document | When to Read |
|----------|--------------|
| `.claude/PRD.md` | Understanding requirements, API mappings, and cmdlet specifications |
| `.claude/reference/api-schema/endpoints/` | VergeOS API field definitions, actions, and validation rules |
| `.claude/TESTENV.md` | creds, names, etc for testing against a live system |
| `Examples/` | Copy-pasteable scripts for common automation scenarios |

## Architecture

### API Wrapper Pattern

All cmdlets use `Invoke-VergeAPI` (Private) for HTTP requests:
- Handles authentication (Bearer token or session cookie)
- Manages TLS 1.2+ connections
- Supports `-SkipCertificateCheck` for self-signed certs
- Returns strongly-typed `[PSCustomObject]` with `PSTypeName`

### Component Design

The module exposes cmdlets organized by resource type:

```powershell
# Connection management
Connect-VergeOS -Server "vergeos.local" -Credential $cred
Get-VergeConnection

# Resource operations follow Verb-VergeNoun pattern
Get-VergeVM -Name "Web*" -PowerState Running
Start-VergeVM -Name "WebServer01"
New-VergeVMSnapshot -VM "WebServer01" -Name "Pre-Update"
```

### Key Files

- `Private/Invoke-VergeAPI.ps1` - Core HTTP client with auth, error handling, pagination
- `Classes/VergeConnection.ps1` - Session state management for multi-server support
- `Public/VM/*.ps1` - VM lifecycle cmdlets (Get, New, Set, Remove, Start, Stop, etc.)

## Code Conventions

### Cmdlet Structure

Every cmdlet follows this pattern:

```powershell
function Get-VergeVM {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(ValueFromPipeline)]
        [string]$Name,

        [ValidateSet('Running', 'Stopped', 'Suspended')]
        [string]$PowerState,

        [VergeConnection]$Server = (Get-VergeConnection -Default)
    )

    process {
        # Implementation
    }
}
```

### Error Handling

Use PowerShell standard error handling:

```powershell
# Non-terminating (continue processing pipeline)
Write-Error -Message "VM not found: $Name" -ErrorId 'VMNotFound'

# Terminating (stop execution)
throw [System.InvalidOperationException]::new("Not connected to VergeOS")
```

### Naming Conventions

- `PascalCase` for cmdlet names: `Get-VergeVM`, `New-VergeVMSnapshot`
- `camelCase` for internal variables
- `$script:` scope for module-level state
- Approved verbs only: Get, Set, New, Remove, Start, Stop, Restart, etc.

## Adding a New Cmdlet

### Step 0: Review Requirements

Check `PRD.md` for the API mapping and priority level (P0-P3).

### Step 1: Create Cmdlet File

Create `Public/[Category]/[Verb]-Verge[Noun].ps1`:

```powershell
function Verb-VergeNoun {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        # Parameters with validation
    )

    begin { }
    process { }
    end { }
}
```

### Step 2: Implement API Call

Use `Invoke-VergeAPI` for all HTTP operations:

```powershell
$response = Invoke-VergeAPI -Method GET -Endpoint "vms" -Filter "name eq '$Name'"
```

### Step 3: Export in Module Manifest

Add to `FunctionsToExport` in `PSVergeOS.psd1`.

### Step 4: Verify

Ensure:
- `-WhatIf` and `-Confirm` work for destructive operations
- `-Verbose` provides detailed logging
- `Get-Help Verb-VergeNoun -Full` shows documentation
- Pester tests pass

## Testing Strategy

- **Location**: `Tests/Unit/` and `Tests/Integration/`
- **Unit Tests**: Mock `Invoke-VergeAPI` to test cmdlet logic
- **Integration Tests**: Run against live VergeOS instance (requires credentials)
- **Coverage**: >90% on Public cmdlets

## API Schema Reference

336 endpoint schemas in `.claude/reference/api-schema/endpoints/`:

| Schema | Purpose |
|--------|---------|
| `vms.json` | VM fields, actions (poweron, clone, snapshot), views |
| `vnets.json` | Network config, DHCP, DNS, firewall rules |
| `machine_drives.json` | VM disk configuration |
| `machine_nics.json` | VM network interface configuration |
| `tasks.json` | Async operation tracking |
| `tenants.json` | Multi-tenant environment management |

Use schemas to understand field types, defaults, validation, and available actions.
