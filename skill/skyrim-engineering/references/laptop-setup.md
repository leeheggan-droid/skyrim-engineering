# Codex laptop setup

Use this workflow independently on each Windows 11 family laptop only after its owner has installed Steam Skyrim Special Edition/Anniversary Edition and the complete licensed Anniversary content. The workflow does not install Steam, authenticate an account, purchase or download Bethesda content, copy saves, change firewall rules, or fetch Nexus packages.

## Safety model

Every invocation requires explicit game, profile, canonical-manifest, and state roots. Public output identifies a machine only as `client-a`, `client-b`, or `client-c`; never substitute a person's name, Windows account, Steam ID, hostname, or network address. Keep `StateDirectory` outside both the game and profile roots.

The canonical manifest separates the licensed `anniversaryBaseline` from `approvedShared` entries. Package policy does not come from that caller-supplied manifest: each shared entry must exactly match the repository-controlled `laptop-package-catalog.json`, including component, version, hash, source, destination, publisher, provenance, licence, and package type. Existing profile content is projected through opaque identifiers; mismatched known paths and unexpected isolated-profile content are `unknownOrIncompatible`.

Apply currently installs only the officially qualified SKSE AE 2.2.6 package for Skyrim 1.6.1170. Address Library and Skyrim Together are explicitly `unsupportedPendingIntake`; they cannot be installed until real user-supplied packages complete independent intake. The user or Codex must place the official `skse64_2_02_06.7z` from `https://skse.silverlock.org/beta/skse64_2_02_06.7z` in an explicit local `PackageCache`. The immutable catalog pins its 751,136-byte SHA-256 and 551-entry layout, the two exact game-root executable/DLL mappings, and a reviewed exact name/size/SHA-256 inventory for all 62 direct `Data/Scripts/*.pex` entries. This implements the archive readme's runtime installation layout: `skse64_loader.exe` and `skse64_1_6_1170.dll` beside `SkyrimSE.exe`, and every required PEX under `GameRoot\Data\Scripts`. The script never downloads, authenticates, executes extracted payloads, changes firewall rules, or handles saves or Bethesda content.

`Apply` refuses any pre-existing `Anniversary Together` directory rather than merging into it. After confirmation and `ShouldProcess`, every SKSE destination is checked again: a missing destination is eligible for exclusive publication, an exact existing size/hash is reused and marked `preExisting`, and every other existing object refuses the whole transaction before its journal is created. Existing add-ons are never replaced. Each new file is extracted into a fresh same-volume ownership-marked staging directory, hash-verified, assigned a physical file identity, and durably marked `publishing` before its atomic move. The profile directory receives the same durable intent before publication. A crash immediately before or after a move is therefore recoverable; rollback removes only a journaled file whose expected hash and pre-move physical identity still match, skips `preExisting` files, preserves non-empty directories, and removes staging only after its random ownership marker and reparse-free tree are verified.

Immediately before each create, move, replace, or delete, the script opens the direct parent with a Windows handle that requests delete access without delete sharing. It keeps that handle open through the operation, then reopens the path and compares volume/file identity and final path before releasing the lease. Direct parent rename/replacement is thereby blocked during the mutation window, and reparse or identity changes are refused. This is a strong mitigation, not a claim that arbitrary same-user or administrator races are eliminated: the actual rename remains a path-based .NET call rather than an NT handle-relative rename, so an attacker who can manipulate a higher ancestor or descendants at just the right instant may force a detected failure or leave an output requiring manual review. Automated cleanup intentionally refuses any output whose recorded ownership identity cannot be proved.

Reports distinguish `missing`, `extra`, `hashDifferent`, `versionDifferent`, and `orderDifferent`, with expected and actual evidence for known canonical paths. Unknown discovered names and untrusted metadata are never emitted; public output uses opaque identifiers. Runtime, Creation, plugin, archive, SKSE, Address Library, Skyrim Together, mod-manager, profile, and load-order domains are reported separately. Resolve baseline differences through the owning licensed installer or explicit manual review; do not use this workflow to replace Bethesda files.

## Terminal sequence

Open PowerShell, set explicit local paths, and run each mode separately. These example variables are placeholders and must be replaced locally; do not paste their resolved values into issues or commits.

```powershell
$repo = 'C:\path\to\skyrim-engineering'
$game = 'C:\explicit\Steam\Skyrim Special Edition'
$profiles = 'C:\explicit\ModManager\Profiles'
$canonical = 'C:\explicit\approved-baseline\manifest.json'
$state = 'C:\explicit\SkyrimEngineeringState'
$packageCache = 'C:\explicit\SkyrimEngineeringPackageCache'
$tools = 'C:\explicit\ModManager'
$setup = Join-Path $repo 'skill\skyrim-engineering\scripts\setup-laptop.ps1'
```

First, audit without mutation:

```powershell
pwsh -NoProfile -File $setup -AuditOnly -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state -ToolRoot $tools
```

Then inspect the deterministic proposed actions:

```powershell
pwsh -NoProfile -File $setup -Plan -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state
```

Apply is a distinct, separately confirmed installation step. Review every plan action, catalog provenance record, archive hash, and payload hash first. `-ConfirmApply` is mandatory, and PowerShell `ShouldProcess` still presents its normal confirmation unless `-Confirm:$false` is deliberately supplied by an already-authorized operator. Previewing with `-WhatIf` never creates a profile, installed file, or state journal.

```powershell
pwsh -NoProfile -File $setup -Apply -ConfirmApply -WhatIf -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state -PackageCache $packageCache

pwsh -NoProfile -File $setup -Apply -ConfirmApply -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state -PackageCache $packageCache
```

Verify the anonymous client manifest after Apply. The SKSE domain is exact only when all 64 catalogued runtime files are present with their trusted hashes:

```powershell
pwsh -NoProfile -File $setup -Verify -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state
```

Rollback recomputes the exact mutation allowlist from the trusted catalog and the hash-bound canonical manifest. It rejects altered, duplicate, wrong-root, or extra journal entries; accepts recoverable `applying` state; quarantines and rehashes a file before deletion; and leaves unjournaled files and non-empty directories untouched.

```powershell
pwsh -NoProfile -File $setup -Rollback -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state
```

Use `client-b` and `client-c` on the other laptops. A clean synthetic audit verifies the tool contract only; it is not evidence that a live Anniversary or multiplayer practical passed.

## Install the Codex skill junction

The local installer creates one verified junction and never replaces a directory or a junction pointing elsewhere. Preview and install into an explicit skills root:

```powershell
pwsh -NoProfile -File (Join-Path $repo 'skill\skyrim-engineering\scripts\install-skill.ps1') `
  -RepositoryRoot $repo -CodexSkillsRoot 'C:\explicit\codex-skills' -WhatIf

pwsh -NoProfile -File (Join-Path $repo 'skill\skyrim-engineering\scripts\install-skill.ps1') `
  -RepositoryRoot $repo -CodexSkillsRoot 'C:\explicit\codex-skills'
```
