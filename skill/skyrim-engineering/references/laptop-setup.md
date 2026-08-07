# Codex laptop assessment

For the human-approved `v0.1 provisional` boundary, `setup-laptop.ps1` is read-only. It supports `-AuditOnly`, `-Plan`, and `-Verify`. Component `-Apply` and `-Rollback` are reserved interface names that always fail nonzero with schema `skyrim-engineering.laptop-deferred/v1`. They remain deferred until the workflow has both a native Windows handle-relative writer and an OS-protected journal.

The separate `install-skill.ps1` junction installer remains enabled. It installs only the repository skill junction; it does not install or change Skyrim components.

## Safety and evidence model

Every assessment requires explicit game, profile, canonical-manifest, and state roots. Public output identifies a machine only as `client-a`, `client-b`, or `client-c`; never substitute a person's name, Windows account, Steam ID, hostname, or network address. Audit, Plan, and Verify do not create profiles, state journals, staging directories, or game files.

The canonical manifest separates licensed `anniversaryBaseline` content from `approvedShared` evidence. The repository-controlled `laptop-package-catalog.json` retains verified intake knowledge for official SKSE AE 2.2.6: archive provenance, SHA-256, size, entry count, two game-root payloads, and all 62 `Data/Scripts/*.pex` records. That catalog is evidence for comparison only in v0.1; it is not installation authorization. Address Library and Skyrim Together remain `unsupportedPendingIntake`.

Reports distinguish `missing`, `extra`, `hashDifferent`, `versionDifferent`, and `orderDifferent`. Runtime, Creation, plugin, archive, SKSE, Address Library, Skyrim Together, mod-manager, profile, and load-order domains remain separate. Unknown names and untrusted metadata are represented by opaque identifiers.

If `-Apply` or `-Rollback` is requested, the error record includes:

- schema `skyrim-engineering.laptop-deferred/v1`;
- the requested mode and `deferred` status;
- supported modes `AuditOnly`, `Plan`, and `Verify`; and
- the two missing safety capabilities: `nativeWindowsHandleRelativeWriter` and `osProtectedJournal`.

Use an owning installer or a separately reviewed manual procedure for component changes. This workflow provides no operational installation or rollback instructions.

## Terminal sequence

Open PowerShell and set explicit local paths. Do not publish their resolved values.

```powershell
$repo = 'C:\path\to\skyrim-engineering'
$game = 'C:\explicit\Steam\Skyrim Special Edition'
$profiles = 'C:\explicit\ModManager\Profiles'
$canonical = 'C:\explicit\approved-baseline\manifest.json'
$state = 'C:\explicit\SkyrimEngineeringState'
$tools = 'C:\explicit\ModManager'
$setup = Join-Path $repo 'skill\skyrim-engineering\scripts\setup-laptop.ps1'
```

Audit the current machine without mutation:

```powershell
pwsh -NoProfile -File $setup -AuditOnly -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state -ToolRoot $tools
```

Produce a deterministic read-only plan. Its `actions` array is empty; differences and verified package-intake evidence remain available for review.

```powershell
pwsh -NoProfile -File $setup -Plan -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state
```

Verify the current observed installation against the canonical evidence:

```powershell
pwsh -NoProfile -File $setup -Verify -ClientId client-a `
  -GameRoot $game -ProfileRoot $profiles `
  -CanonicalManifest $canonical -StateDirectory $state
```

Use `client-b` and `client-c` on the other laptops. A clean audit is tooling evidence only; it is not a live Anniversary or multiplayer qualification result.

## Install the Codex skill junction

The local installer creates one verified junction and never replaces a directory or a junction pointing elsewhere:

```powershell
pwsh -NoProfile -File (Join-Path $repo 'skill\skyrim-engineering\scripts\install-skill.ps1') `
  -RepositoryRoot $repo -CodexSkillsRoot 'C:\explicit\codex-skills' -WhatIf

pwsh -NoProfile -File (Join-Path $repo 'skill\skyrim-engineering\scripts\install-skill.ps1') `
  -RepositoryRoot $repo -CodexSkillsRoot 'C:\explicit\codex-skills'
```
