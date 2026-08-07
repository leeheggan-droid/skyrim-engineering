# Skyrim Engineering

Reusable Codex guidance and read-only tooling for Skyrim Special Edition,
Anniversary Edition, Creation/plugin analysis, diagnostics, and Skyrim Together
Reborn compatibility investigations.

> **Release status:** `v0.1.0` is provisional. The skill and its contracts are
> validated, but live Creation Kit, xEdit, Papyrus, and multi-laptop gameplay
> qualification is still pending. Do not interpret this repository as a claim
> that every Anniversary Creation works with Skyrim Together.

## What it provides

- A Codex skill that routes Skyrim work to versioned, sourced references.
- Read-only Skyrim installation and 2021 Anniversary catalogue inspection.
- Portable Creation inventory and cross-laptop parity comparison.
- Privacy-conscious diagnostic collection with mandatory manual review.
- A fail-closed host-plus-two-client reproduction contract and 13 test cases.
- Codex-led laptop audit, planning, and verification commands.
- Windows CI covering Pester, PowerShell parsing, JSON schemas, privacy, and
  prohibited public artefacts.

The Anniversary baseline contains the 74 bundled 2021 Creation plugin
identifiers. Later or optional add-ons are recorded separately as
`unknown/out-of-scope` until explicitly classified. No Bethesda or mod assets
are included or redistributed.

## Install the Codex skill

Clone the repository to a stable local directory, then run:

```powershell
& .\skill\skyrim-engineering\scripts\install-skill.ps1 `
  -RepositoryRoot (Get-Location).Path
```

The installer creates and verifies only this junction:

```text
%USERPROFILE%\.codex\skills\skyrim-engineering
  -> <repository>\skill\skyrim-engineering
```

It refuses to replace a real directory, a junction pointing elsewhere, or a
path reached through a reparse-point ancestor.

## Set up the second laptop

Use this end-to-end sequence:

1. Install the Steam edition of Skyrim Special Edition plus the Anniversary
   Upgrade and allow the owned 2021 Anniversary Creations to finish downloading.
2. Launch Skyrim once through Steam, reach the main menu, then exit normally.
   This establishes the standard installation and user configuration.
3. Install Git and Codex from their official distribution channels, open a new
   PowerShell terminal, and clone this repository:

   ```powershell
   New-Item -ItemType Directory -Path 'C:\repos' -Force | Out-Null
   Set-Location 'C:\repos'
   git clone https://github.com/leeheggan-droid/skyrim-engineering.git
   Set-Location '.\skyrim-engineering'
   ```

4. Install the Codex skill junction from that stable checkout:

   ```powershell
   & .\skill\skyrim-engineering\scripts\install-skill.ps1 `
     -RepositoryRoot (Get-Location).Path
   ```

5. Continue directly to the Reborn installation below. Use the public machine
   identifier `client-b` in any generated records.

Do not remove existing Anniversary content or add-ons to manufacture a clean
baseline. Install the standard multiplayer stack first; inventory and diagnose
differences afterward if launch or cross-machine parity fails.

## Install the standard Skyrim Together Reborn stack

Use the official Skyrim Together Reborn MO2 route on each laptop immediately
after the one-time stock Skyrim launch:

1. Read the official [Getting Started guide](https://wiki.tiltedphoques.com/tilted-online/guides/getting-started),
   then install and configure a portable MO2 instance using the official
   [MO2 client guide](https://wiki.tiltedphoques.com/tilted-online/guides/client-setup/using-modorganizer2-mo2/installing-modorganizer2/initial-mo2-setup).
   Select **Skyrim Special Edition** and create a dedicated profile named
   `Skyrim Together Reborn`; do not reuse a personal modded profile.
2. In that profile, download and enable **Address Library for SKSE Plugins — All
   in one (1.6.X)** by following the official
   [Address Library step](https://wiki.tiltedphoques.com/tilted-online/guides/client-setup/using-modorganizer2-mo2/utilities/address-library-for-skse).
   Skyrim Script Extender itself is not required for Skyrim Together Reborn and
   must not be added to the stock control profile.
3. Download **Skyrim Together Reborn** from its linked Nexus page using **Mod
   Manager Download**, following the official
   [download](https://wiki.tiltedphoques.com/tilted-online/guides/client-setup/using-modorganizer2-mo2/skyrim-together-reborn/downloading-skyrim-together-reborn)
   and [installation](https://wiki.tiltedphoques.com/tilted-online/guides/client-setup/using-modorganizer2-mo2/skyrim-together-reborn/installing-skyrim-together-reborn)
   pages. Install and enable it in MO2; do not manually copy its archive into
   the live Skyrim directory.
4. Add `SkyrimTogether.exe` to MO2 using the official
   [executable-location step](https://wiki.tiltedphoques.com/tilted-online/guides/client-setup/using-modorganizer2-mo2/skyrim-together-reborn/locating-skyrim-together-reborn-through-mo2).
   On its first launch, select the installed `SkyrimSE.exe` when prompted.
5. Launch `SkyrimTogether.exe` once through MO2 to confirm that it reaches its
   menu without an Address Library or executable-selection error, then exit.
   Report **`reborn installed — client-b`**. Record and compare versions/hashes
   afterward; investigate only if the laptops differ or the standard launch
   fails.

The upstream guide recommends a minimal setup and does not require the paid
Anniversary Upgrade. These family laptops intentionally retain their licensed
Anniversary content. Do not remove it pre-emptively; record an actual failure
before diagnosing or proposing compatibility changes.

## Inspect a laptop

The provisional laptop helper is deliberately read-only. Choose exactly one
mode and use an anonymous client identifier:

```powershell
$setup = '.\skill\skyrim-engineering\scripts\setup-laptop.ps1'

& $setup -AuditOnly -ClientId client-a `
  -GameRoot 'D:\Games\Skyrim Special Edition' `
  -ProfileRoot 'D:\SkyrimProfiles\client-a' `
  -CanonicalManifest 'D:\SkyrimLab\canonical\manifest.json' `
  -StateDirectory 'D:\SkyrimLab\state\client-a'

# Replace -AuditOnly with -Plan or -Verify for those read-only modes.
```

Use `Get-Help $setup -Full` for the required path and manifest parameters.
Component `Apply` and `Rollback` are deferred in v0.1 to a pinned MO2 or
Wabbajack workflow with tool-owned rollback. The helper will fail closed if
those modes are requested; it does not mutate the live game tree.

## Inventory and compare Anniversary installations

Inventory licensed files locally:

```powershell
& .\skill\skyrim-engineering\scripts\inventory-creations.ps1 `
  -DataPath 'D:\SteamLibrary\steamapps\common\Skyrim Special Edition\Data' `
  -LoadOrderPath 'D:\SkyrimProfiles\client-a\plugins.txt' `
  -Json | Set-Content -Encoding utf8 '.\client-a-creations.json'
```

Then compare two sanitized manifests:

```powershell
& .\skill\skyrim-engineering\scripts\compare-installations.ps1 `
  -ManifestPath '.\host-creations.json', '.\client-a-creations.json' `
  -Json
```

Inventory proves observed presence and parity only. It does not prove ownership,
completeness, internal plugin flags, compatibility, or runtime synchronization.

## Collect diagnostics

```powershell
& .\skill\skyrim-engineering\scripts\collect-diagnostics.ps1 `
  -InputPath '.\private-raw-logs' `
  -OutputDirectory '.\sanitized-diagnostics'
```

Raw crash dumps, saves, binaries, plugins, archives, addresses, account data,
and credentials must remain private. Automated redaction reduces risk; it is
not a publication guarantee. Manually inspect every output and manifest before
sharing it.

## Validation

```powershell
python .github\scripts\quick_validate.py skill\skyrim-engineering

pwsh -NoProfile -Command @'
Import-Module Pester -RequiredVersion 5.9.0 -Force
$config = New-PesterConfiguration
$config.Run.Path = 'tests'
$config.Run.Exit = $true
Invoke-Pester -Configuration $config
'@
```

Host-bound qualification checks run only when their protected local evidence is
available and `SKYRIM_ENGINEERING_LIVE_QUALIFICATION=1` is explicitly set.
Ordinary public CI validates the provisional release without promoting those
checks to PASS.

## Project layout

- `skill/skyrim-engineering/` — Codex skill, references, and scripts.
- `projects/anniversary-together/` — test cases and evidence schemas.
- `qualification/` — fail-closed qualification state.
- `docs/expertise/` — evidence boundaries and practical specifications.
- `docs/forward-tests-v0.1.md` — clean-context provisional evaluations.
- `tests/` — Pester and synthetic fixtures; no proprietary game assets.

## Prior art and licensing

The project improves the shared Anniversary/Skyrim Together engineering process
only where evidence demonstrates a defect. Skyrim Together Reborn is the target;
SkyMP and Blockhead's SkyrimCoop are evaluated as prior art, not represented as
drop-in replacements. Exact revisions, applicability notes, and upstream
licences are recorded in the research ledger and source register.

Repository-authored material is licensed under GPL-3.0-or-later; see
[LICENSE](LICENSE). Upstream projects and game content retain their own licences.
