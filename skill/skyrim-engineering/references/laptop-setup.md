# Codex laptop setup

Use this workflow independently on each Windows 11 family laptop only after its owner has installed Steam Skyrim Special Edition/Anniversary Edition and the complete licensed Anniversary content. The workflow does not install Steam, authenticate an account, purchase or download Bethesda content, copy saves, change firewall rules, or fetch Nexus packages.

## Safety model

Every invocation requires explicit game, profile, canonical-manifest, and state roots. Public output identifies a machine only as `client-a`, `client-b`, or `client-c`; never substitute a person's name, Windows account, Steam ID, hostname, or network address. Keep `StateDirectory` outside both the game and profile roots.

The canonical manifest separates the licensed `anniversaryBaseline` from pinned, hash-verified `approvedShared` free components. Existing profile files are `machineSpecific`; unexpected game-tree files are `unknownOrIncompatible`. They remain in place. `Apply` creates only the isolated `Anniversary Together` profile and refuses to overwrite any existing file. It can install only packages already staged beside the canonical manifest and marked both approved and free. It does not perform live downloads.

Reports distinguish `missing`, `extra`, `hashDifferent`, `versionDifferent`, and `orderDifferent`. Resolve baseline differences through the owning licensed installer or explicit manual review; do not use this workflow to replace Bethesda files.

## Terminal sequence

Open PowerShell, set explicit local paths, and run each mode separately. These example variables are placeholders and must be replaced locally; do not paste their resolved values into issues or commits.

```powershell
$repo = 'C:\path\to\skyrim-engineering'
$game = 'C:\explicit\Steam\Skyrim Special Edition'
$profiles = 'C:\explicit\ModManager\Profiles'
$canonical = 'C:\explicit\approved-baseline\manifest.json'
$state = 'C:\explicit\SkyrimEngineeringState'
$setup = Join-Path $repo 'skill\skyrim-engineering\scripts\setup-laptop.ps1'
```

First, audit without mutation:

```powershell
pwsh -NoProfile -File $setup -AuditOnly -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state
```

Then inspect the deterministic proposed actions:

```powershell
pwsh -NoProfile -File $setup -Plan -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state
```

Apply is a distinct, separately confirmed step. Review every plan action and package hash first. `-ConfirmApply` is mandatory, and PowerShell `ShouldProcess` still presents its normal confirmation unless `-Confirm:$false` is deliberately supplied by an already-authorized operator. Previewing with `-WhatIf` never creates a profile, package, or state journal.

```powershell
pwsh -NoProfile -File $setup -Apply -ConfirmApply -WhatIf -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state

pwsh -NoProfile -File $setup -Apply -ConfirmApply -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state
```

Verify the anonymous client manifest after Apply:

```powershell
pwsh -NoProfile -File $setup -Verify -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state
```

Rollback removes only files and empty directories recorded in that client's state journal. It refuses a journaled file whose hash changed and leaves all unjournaled files, existing profiles, add-ons, and non-empty directories untouched.

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
