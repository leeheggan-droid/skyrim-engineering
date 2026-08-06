# Skyrim Engineering Skill V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, validate, publish, and locally install a reusable Codex Skyrim engineering skill with sourced references, read-only Windows diagnostics, CI, and an Anniversary Together compatibility-project foundation.

**Architecture:** Keep the canonical skill under `skill/skyrim-engineering` in a public Git repository and expose it to Codex through a verified Windows directory junction. Route tasks from a concise `SKILL.md` into focused references and deterministic PowerShell scripts; keep family-project observations separate under `projects/anniversary-together`.

**Tech Stack:** Markdown, PowerShell 7/Windows PowerShell 5.1-compatible syntax, Pester 5, GitHub Actions on `windows-2022`, Codex skill tooling, Git/GitHub CLI.

## Global Constraints

- Target Windows 11, Steam Skyrim Special Edition runtime `1.6.1170.0`, and the licensed complete Anniversary Creation Club library.
- Support Skyrim SE/AE engineering; do not become a lore, walkthrough, or cheat skill.
- Default all scripts to read-only operation and accept explicit input paths.
- Emit deterministic structured JSON plus concise human-readable output.
- Never download paid content, bypass licences, alter Bethesda plugins, edit saves, change firewall rules, or install software implicitly.
- Never commit Bethesda assets, Nexus packages, Skyrim Together binaries, saves, unsanitized dumps, credentials, Steam IDs, IP addresses, personal usernames, or personal absolute paths.
- Treat direct observation and upstream primary sources as stronger evidence than community reports.
- Store source URL/reference, access date, affected version, confidence, and reproduction status for unstable claims.
- Keep Skyrim Together derivatives in a separate GPLv3 fork; do not copy upstream source into this repository.
- Do not pre-emptively patch Skyrim Together before reproducing an upstream defect.
- Support only Windows Steam clients in V1; exclude console, VR, Game Pass, Epic, GOG, Verified Creations, and non-Windows clients.
- Use LF in the repository; PowerShell scripts must parse under both PowerShell 7 and Windows PowerShell 5.1 where available.

---

## File Map

- `skill/skyrim-engineering/SKILL.md`: trigger-time routing, evidence workflow, and safety rules.
- `skill/skyrim-engineering/agents/openai.yaml`: UI display name, description, and default prompt.
- `skill/skyrim-engineering/references/*.md`: selectively loaded domain knowledge with dated primary sources.
- `skill/skyrim-engineering/scripts/SkyrimEngineering.Common.psm1`: shared path, hashing, normalization, and redaction functions.
- `skill/skyrim-engineering/scripts/*.ps1`: four public read-only command entrypoints plus safe junction installer.
- `tests/*.Tests.ps1`: Pester unit and fixture tests.
- `tests/fixtures/`: synthetic Steam, Skyrim, plugin, log, and manifest trees.
- `projects/anniversary-together/`: schemas, test cases, sanitized results, and project decisions.
- `.github/workflows/validate.yml`: Windows validation without proprietary dependencies.
- `.gitattributes`, `.gitignore`, `LICENSE`: repository hygiene and licensing.

### Task 0: Skyrim Design-and-Build Expertise Gate

**Files:**
- Create: `docs/expertise/syllabus.md`
- Create: `docs/expertise/source-register.md`
- Create: `docs/expertise/toolchain-audit.md`
- Create: `docs/expertise/architecture-traces.md`
- Create: `docs/expertise/practicals.md`
- Create: `docs/expertise/assessment-rubric.md`
- Create: `docs/expertise/assessment-results.md`
- Create: `docs/expertise/package-intake.md`
- Create: `tests/Expertise.Tests.ps1`

**Interfaces:**
- Consumes: official Bethesda/Creation Kit material, xEdit primary documentation and source, SKSE/Address Library primary material, Steam runtime facts, Tilted Phoques documentation and source, sanitized local observations, and user-supplied licensed packages that pass intake.
- Produces: a versioned body of evidence demonstrating Skyrim data, design, tooling, runtime, diagnostics, packaging, and multiplayer architecture competence before Task 1 begins.

- [ ] **Step 1: Write the expertise acceptance test**

Create `tests/Expertise.Tests.ps1` to require all eight evidence files, reject unresolved markers, require at least two primary sources per critical domain, and fail any assessment domain below its threshold:

```powershell
Describe 'Step zero expertise gate' {
    $domains = @('data-model','creation-kit','xedit','papyrus','runtime-extensibility','diagnostics','packaging','together-architecture')
    It 'has complete evidence files' {
        @('syllabus','source-register','toolchain-audit','architecture-traces','practicals','assessment-rubric','assessment-results','package-intake') |
            ForEach-Object { "docs/expertise/$_.md" | Should -Exist }
    }
    It 'has no unresolved content' {
        Get-ChildItem docs/expertise -Filter '*.md' |
            ForEach-Object { Get-Content -Raw $_ | Should -Not -Match '\b(TBD|TODO|FIXME|UNKNOWN)\b' }
    }
    It 'passes every critical domain' {
        $results = Get-Content -Raw docs/expertise/assessment-results.md
        $domains | ForEach-Object { $results | Should -Match "(?m)^\| $_ \| [0-9]+ \| [0-9]+ \| PASS \|" }
        $results | Should -Not -Match '(?m)^\| .* \| .* \| .* \| (FAIL|WAIVED) \|'
    }
}
```

- [ ] **Step 2: Run the gate and verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Expertise.Tests.ps1 -Output Detailed"`

Expected: FAIL because expertise evidence and results do not exist.

- [ ] **Step 3: Build the primary-source syllabus and source register**

Cover these critical domains with applicable-version boundaries and at least two primary sources each: Skyrim plugin/record data model; masters, overrides, ESL flags and compacted FormIDs; assets/archives/localization; Creation Kit world, quest, dialogue, actor, package, cell, navmesh, and Papyrus workflows; xEdit inspection, conflict analysis, cleaning, scripting, and safe patch creation; Papyrus VM/events/persistence; SKSE, Address Library, runtime relocation and ABI risk; crash logs/minidumps/save and load-order diagnosis; mod packaging/deployment/licensing; and Skyrim Together client/server ownership, serialization, mod mapping, quest/actor/inventory synchronization, build, test, and contribution paths.

Every entry in `source-register.md` must include title, canonical URL or repository path, publisher/maintainer, source type, accessed date, applicable versions, licence/access constraint, and the precise claim or workflow it supports. Community sources may identify leads but cannot satisfy the two-primary-source threshold.

- [ ] **Step 4: Audit the complete local toolchain before acquiring anything**

Record installed version, discovery path with username removed, licence, source, purpose, and readiness for: Steam Skyrim SE/AE, Creation Kit, xEdit/SSEEdit, Mod Organizer 2, Vortex, SKSE, Address Library, Visual Studio 2022 C++ workload/Build Tools, CMake, xmake, Git, Git LFS, PowerShell 7, Python, Node.js, 7-Zip, WinDbg, Crash Logger SSE AE VR, upstream TiltedEvolution source, and its submodule/dependency prerequisites.

Classify each as `ready`, `missing-free`, `missing-user-supplied`, `not-required-v1`, or `blocked`. Do not install or execute an untrusted package during the audit. In `package-intake.md`, define checks for origin, signature/hash, licence, malware scan, version, supported runtime, redistribution rights, secrets, binary execution risk, and destination. List the exact missing packages the authorized operator can supply or authorize only after the audit proves they are needed.

- [ ] **Step 5: Complete hands-on design and build practicals**

Use original/synthetic fixtures or locally licensed content without committing it. Record commands, versions, observations, and sanitized outputs for all of the following:

1. Decode standard and `0xFE` light-plugin FormIDs in both directions and trace master-relative to load-order-resolved IDs.
2. Inspect a plugin header, masters, flags, overrides, scripts, archives, and conflicts in xEdit without saving changes.
3. Create a tiny original Creation Kit test plugin containing a cell object, actor, dialogue/quest stage, package, inventory item, and Papyrus event; package only the original source/fixture where licensing allows.
4. Compile Papyrus, inspect logs, deliberately trigger a safe synthetic error, and explain persistence/save implications.
5. Trace a representative actor, inventory item, quest stage, and lite-plugin FormID through TiltedEvolution client capture, encoding, server state, and remote application using exact source paths/functions.
6. Configure and build current TiltedEvolution in an isolated checkout, or document an exact reproducible blocker with the failing command and full non-secret output; a missing freely obtainable prerequisite is not a pass.
7. Triage sanitized crash, plugin-parity, missing-master, and desynchronization fixtures and distinguish observation, hypothesis, reproduction, and fix.
8. Produce a legally safe release manifest containing only original/GPL-compatible code, hashes, provenance, supported versions, and rollback instructions.

- [ ] **Step 6: Run a scored expertise assessment**

Define a 100-point rubric before answering: data model 15, Creation Kit/design 15, xEdit 10, Papyrus 10, runtime extensibility 10, diagnostics 10, packaging/legal 10, and Skyrim Together architecture/build 20. Require at least 80% in every domain and 90% overall; prohibit waivers.

Assessment prompts must use raw fixtures and source code locations rather than answers from the syllabus. Include explanation, diagnosis, design, and build tasks. Record each score, evidence link, assessor finding, and remediation. A failed domain triggers additional practical work and a fresh equivalent assessment; do not average a failure away.

- [ ] **Step 7: Have independent agents review the evidence and assessment**

Dispatch one reviewer for Skyrim data/Creation Kit/Papyrus and another for Skyrim Together/runtime/build. Give each only the evidence files, raw fixtures, rubric, and relevant primary sources—not intended conclusions. Require explicit verdicts on source accuracy, practical reproducibility, assessment scoring, blind spots, and whether the gate should pass. Resolve all Critical/Important findings through the standard task fix loop.

- [ ] **Step 8: Run the gate and commit only on a genuine pass**

```powershell
pwsh -NoProfile -Command "Invoke-Pester tests/Expertise.Tests.ps1 -Output Detailed"
rg -n "\b(TBD|TODO|FIXME|UNKNOWN)\b|C:\\Users\\|7656119|gho_" docs/expertise
git diff --check
```

Expected: Pester PASS; every domain is at least 80%, overall score is at least 90%, both independent reviews approve, `rg` finds no unresolved/private content, and the build practical either succeeds or the gate remains open.

Only after all expectations pass:

```powershell
git add docs/expertise tests/Expertise.Tests.ps1
git commit -m "docs: establish Skyrim engineering expertise baseline"
```

### Task 1: Repository Foundation and Skill Skeleton

**Files:**
- Create: `.gitattributes`
- Modify: `.gitignore`
- Create: `LICENSE`
- Create: `skill/skyrim-engineering/SKILL.md`
- Create: `skill/skyrim-engineering/agents/openai.yaml`
- Create directories: `skill/skyrim-engineering/references`, `skill/skyrim-engineering/scripts`, `tests/fixtures`, `projects/anniversary-together`

**Interfaces:**
- Consumes: approved design at `docs/superpowers/specs/2026-08-06-skyrim-engineering-skill-design.md`.
- Produces: a structurally valid skill folder named `skyrim-engineering`.

- [ ] **Step 1: Add repository hygiene assertions**

Create `tests/Repository.Tests.ps1` with tests that require LF-oriented `.gitattributes`, exclude private artefacts, and require the planned directories:

```powershell
Describe 'Repository structure' {
    It 'contains the discoverable skill' {
        'skill/skyrim-engineering/SKILL.md' | Should -Exist
        'skill/skyrim-engineering/agents/openai.yaml' | Should -Exist
    }
    It 'excludes private Skyrim artifacts' {
        $ignore = Get-Content -Raw '.gitignore'
        @('*.dmp', '*.ess', '*.skse', 'diagnostics-private/', 'manifests-private/') |
            ForEach-Object { $ignore | Should -Match ([regex]::Escape($_)) }
    }
}
```

- [ ] **Step 2: Run the test and verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Repository.Tests.ps1 -Output Detailed"`

Expected: FAIL because the skill and hygiene files do not exist.

- [ ] **Step 3: Initialize the skill and hygiene files**

Run the official initializer:

```powershell
python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\init_skill.py" skyrim-engineering `
  --path .\skill `
  --resources scripts,references `
  --interface "display_name=Skyrim Engineering" `
  --interface "short_description=Diagnose and engineer Skyrim SE/AE and Skyrim Together" `
  --interface "default_prompt=Use the Skyrim engineering workflow to inspect evidence, diagnose the exact versioned problem, and produce a safe tested result."
```

Set `.gitattributes` to `* text=auto eol=lf` with `*.ps1 text eol=crlf` and `*.psm1 text eol=crlf`. Ignore the private patterns asserted by the test plus `TestResults/`, `.pester/`, and local diagnostic archives. Add the MIT licence for this repository's original documentation and scripts.

- [ ] **Step 4: Run the repository test**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Repository.Tests.ps1 -Output Detailed"`

Expected: PASS.

- [ ] **Step 5: Commit the foundation**

```powershell
git add .gitattributes .gitignore LICENSE skill tests/Repository.Tests.ps1
git commit -m "chore: initialize Skyrim engineering skill"
```

### Task 2: Core Skill Routing and Metadata

**Files:**
- Modify: `skill/skyrim-engineering/SKILL.md`
- Modify: `skill/skyrim-engineering/agents/openai.yaml`
- Create: `tests/Skill.Tests.ps1`

**Interfaces:**
- Consumes: reference filenames and script entrypoints from the File Map.
- Produces: valid frontmatter containing only `name` and `description`, plus explicit routing to every reference and script.

- [ ] **Step 1: Write failing metadata and routing tests**

```powershell
Describe 'Skyrim engineering skill' {
    BeforeAll { $skill = Get-Content -Raw 'skill/skyrim-engineering/SKILL.md' }
    It 'has the exact skill name' { $skill | Should -Match '(?m)^name: skyrim-engineering$' }
    It 'triggers for core engineering surfaces' {
        @('Skyrim Together', 'Anniversary', 'FormID', 'Papyrus', 'crash', 'load order') |
            ForEach-Object { $skill | Should -Match ([regex]::Escape($_)) }
    }
    It 'routes every reference without nesting' {
        Get-ChildItem 'skill/skyrim-engineering/references' -Filter '*.md' |
            ForEach-Object { $skill | Should -Match ([regex]::Escape("references/$($_.Name)")) }
    }
}
```

- [ ] **Step 2: Verify the generated template fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Skill.Tests.ps1 -Output Detailed"`

Expected: FAIL because the template lacks final triggers and routes.

- [ ] **Step 3: Write the concise core workflow**

Replace the template with frontmatter whose description names all trigger domains. In the body require: exact-version discovery; isolated reproduction; stock control; minimal sanitized evidence; observation/hypothesis separation; upstream inspection; focused tests; single-client then multi-client verification; legally redistributable packaging; reviewed knowledge promotion. Route each task class directly to its reference and each deterministic operation to its script. Keep the file under 250 lines and remove every initializer placeholder.

- [ ] **Step 4: Regenerate UI metadata and validate**

```powershell
python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\generate_openai_yaml.py" .\skill\skyrim-engineering `
  --interface "display_name=Skyrim Engineering" `
  --interface "short_description=Diagnose and engineer Skyrim SE/AE and Skyrim Together" `
  --interface "default_prompt=Use the Skyrim engineering workflow to inspect evidence, diagnose the exact versioned problem, and produce a safe tested result."
python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\quick_validate.py" .\skill\skyrim-engineering
pwsh -NoProfile -Command "Invoke-Pester tests/Skill.Tests.ps1 -Output Detailed"
```

Expected: validator success and all Pester tests PASS.

- [ ] **Step 5: Commit the skill workflow**

```powershell
git add skill/skyrim-engineering tests/Skill.Tests.ps1
git commit -m "feat: define Skyrim engineering workflow"
```

### Task 3: Versioned Reference Baseline

**Files:**
- Create: all seven files under `skill/skyrim-engineering/references/`
- Create: `tests/References.Tests.ps1`

**Interfaces:**
- Consumes: primary sources from Bethesda, Steam, xEdit, SKSE, Address Library, Creation Kit, Tilted Phoques documentation/source, and directly observed sanitized facts.
- Produces: Markdown references with `Claim`, `Source`, `Accessed`, `Applies to`, `Confidence`, and `Reproduced` fields for unstable claims.

- [ ] **Step 1: Write failing reference-quality tests**

```powershell
Describe 'Reference baseline' {
    $expected = @('ecosystem','plugins-and-formids','diagnostics','together-reborn','anniversary-creations','build-and-release','research-ledger')
    It 'contains every routed reference' {
        $expected | ForEach-Object { "skill/skyrim-engineering/references/$_.md" | Should -Exist }
    }
    It 'contains no unresolved markers' {
        Get-ChildItem 'skill/skyrim-engineering/references' -Filter '*.md' |
            ForEach-Object { (Get-Content -Raw $_.FullName) | Should -Not -Match '\b(TBD|TODO|FIXME)\b' }
    }
}
```

- [ ] **Step 2: Verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/References.Tests.ps1 -Output Detailed"`

Expected: FAIL because the references do not exist.

- [ ] **Step 3: Author the seven focused references**

Use direct links and access date `2026-08-06`. Record the observed reference machine as an anonymized hardware class, not a user path. In `together-reborn.md`, document current native lite-plugin translation (`0xFE`, 12-bit light index/base FormID mapping) with source file links and distinguish executable 1.6.117x support from full Creation behavioural support. In `anniversary-creations.md`, enumerate the 74 Anniversary creations by official display name and plugin identifiers without copying assets. Put the historical ESL-to-ESP workaround only in `research-ledger.md` as low-confidence, obsolete-risk community prior art.

- [ ] **Step 4: Run reference tests and link scan**

```powershell
pwsh -NoProfile -Command "Invoke-Pester tests/References.Tests.ps1 -Output Detailed"
rg -n "\b(TBD|TODO|FIXME)\b|C:\\Users\\|7656119|gho_" skill/skyrim-engineering/references
```

Expected: Pester PASS; `rg` returns no matches.

- [ ] **Step 5: Commit the knowledge baseline**

```powershell
git add skill/skyrim-engineering/references tests/References.Tests.ps1
git commit -m "docs: add sourced Skyrim engineering baseline"
```

### Task 4: Shared PowerShell Module and Skyrim Inspection

**Files:**
- Create: `skill/skyrim-engineering/scripts/SkyrimEngineering.Common.psm1`
- Create: `skill/skyrim-engineering/scripts/inspect-skyrim.ps1`
- Create: `tests/Common.Tests.ps1`
- Create: `tests/InspectSkyrim.Tests.ps1`
- Create: `tests/fixtures/steam/steamapps/appmanifest_489830.acf`
- Create: `tests/fixtures/game/SkyrimSE.exe.version.json`

**Interfaces:**
- Produces: `Resolve-SkyrimInstall -SteamRoot <string> -> DirectoryInfo`; `Get-RelativeSafePath`; `Get-StableSha256`; `Protect-DiagnosticText`; and inspection JSON schema `skyrim-engineering.inspect/v1`.

- [ ] **Step 1: Write failing unit tests**

Test explicit Steam-root resolution, missing manifest failure, stable SHA-256, relative path normalization, and redaction of usernames, Steam IDs, IPv4 addresses, tokens, and passwords. Test `inspect-skyrim.ps1 -SteamRoot tests/fixtures/steam -GameRoot tests/fixtures/game -Json` returns schema, runtime, store `Steam`, and no absolute fixture root.

- [ ] **Step 2: Verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/Common.Tests.ps1,tests/InspectSkyrim.Tests.ps1 -Output Detailed"`

Expected: FAIL because functions and entrypoint do not exist.

- [ ] **Step 3: Implement minimal shared functions and inspector**

Use `[CmdletBinding()] param([string]$SteamRoot,[string]$GameRoot,[switch]$Json)`. Prefer explicit paths, then Steam registry discovery. Read the ACF as text without changing it. Read the real executable version with `(Get-Item $exe).VersionInfo.FileVersion`; allow the synthetic `.version.json` fixture only when the executable is absent and the path is under `tests/fixtures`. Return ordered objects so JSON property order is stable.

- [ ] **Step 4: Run focused tests and a read-only live check**

```powershell
pwsh -NoProfile -Command "Invoke-Pester tests/Common.Tests.ps1,tests/InspectSkyrim.Tests.ps1 -Output Detailed"
pwsh -NoProfile -File skill/skyrim-engineering/scripts/inspect-skyrim.ps1 -Json
```

Expected: tests PASS; live JSON reports Steam runtime `1.6.1170.0` and contains no Steam account ID.

- [ ] **Step 5: Commit inspection tooling**

```powershell
git add skill/skyrim-engineering/scripts tests
git commit -m "feat: add safe Skyrim installation inspection"
```

### Task 5: Creation Inventory and Cross-Machine Comparison

**Files:**
- Create: `skill/skyrim-engineering/scripts/inventory-creations.ps1`
- Create: `skill/skyrim-engineering/scripts/compare-installations.ps1`
- Create: `tests/InventoryCreations.Tests.ps1`
- Create: `tests/CompareInstallations.Tests.ps1`
- Create: synthetic plugin/archive fixtures and expected manifests under `tests/fixtures/creations/` and `tests/fixtures/manifests/`

**Interfaces:**
- Produces inventory schema `skyrim-engineering.creations/v1` with `name`, `kind`, `size`, `sha256`, `pluginType`, and `relativePath`.
- Consumes one or more inventory manifests and produces comparison schema `skyrim-engineering.comparison/v1` with `missing`, `extra`, `hashDifferent`, `sizeDifferent`, and `orderDifferent` arrays.

- [ ] **Step 1: Write failing manifest and comparison tests**

Use tiny synthetic `.esl`, `.esm`, `.esp`, and `.bsa` files. Assert stable alphabetical ordering, lowercase SHA-256, relative paths only, correct extension-based plugin type, identical-manifest success, and categorized differences. Do not claim that extension alone proves an internal ESL flag; expose that field as `notInspected` until a real parser exists.

- [ ] **Step 2: Verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/InventoryCreations.Tests.ps1,tests/CompareInstallations.Tests.ps1 -Output Detailed"`

Expected: FAIL because both entrypoints are absent.

- [ ] **Step 3: Implement inventory and comparison**

Inventory accepts `-DataPath`, optional `-LoadOrderPath`, and `-Json`. Include only `cc*.esl|esm|esp|bsa` plus the four free-Creation identifiers when present. Comparison accepts `-ManifestPath <string[]> -Json`, validates schema versions, and exits `0` for parity, `2` for differences, and `1` for malformed input.

- [ ] **Step 4: Run tests and inventory the live reference installation**

```powershell
pwsh -NoProfile -Command "Invoke-Pester tests/InventoryCreations.Tests.ps1,tests/CompareInstallations.Tests.ps1 -Output Detailed"
pwsh -NoProfile -File skill/skyrim-engineering/scripts/inventory-creations.ps1 `
  -DataPath 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data' -Json
```

Expected: tests PASS; live output contains Creation filenames and hashes but no personal paths or game data.

- [ ] **Step 5: Commit parity tooling**

```powershell
git add skill/skyrim-engineering/scripts tests
git commit -m "feat: inventory and compare Anniversary installations"
```

### Task 6: Sanitized Diagnostic Collection

**Files:**
- Create: `skill/skyrim-engineering/scripts/collect-diagnostics.ps1`
- Create: `tests/CollectDiagnostics.Tests.ps1`
- Create: `tests/fixtures/diagnostics/` synthetic logs/configuration

**Interfaces:**
- Consumes: explicit `-InputPath <string[]>`, `-OutputDirectory`, and optional `-IncludeDump` (default false).
- Produces: timestamp-free deterministic folder content plus `diagnostic-manifest.json` schema `skyrim-engineering.diagnostics/v1`; archive creation is opt-in.

- [ ] **Step 1: Write failing sanitization tests**

Fixture content must include a synthetic username, home path, Steam ID, IPv4 address, `password=`, bearer token, and benign FormIDs. Assert every secret is replaced with typed markers while FormIDs and stack lines remain. Assert `.dmp`, `.ess`, `.skse`, and unknown binaries are refused by default.

- [ ] **Step 2: Verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/CollectDiagnostics.Tests.ps1 -Output Detailed"`

Expected: FAIL because the collector does not exist.

- [ ] **Step 3: Implement allowlisted collection**

Allow `.log`, `.txt`, `.ini`, `.json`, and `.toml`. Read text with bounded file size (25 MiB each), sanitize through `Protect-DiagnosticText`, write UTF-8 without BOM, hash sanitized outputs, and preserve only sanitized relative filenames. Reject output paths inside the source tree and refuse overwrite unless `-Force` is passed.

- [ ] **Step 4: Run tests and inspect the synthetic bundle**

```powershell
pwsh -NoProfile -Command "Invoke-Pester tests/CollectDiagnostics.Tests.ps1 -Output Detailed"
rg -n "TestUser|7656119|192\.168\.|password=secret|Bearer ey" TestResults/diagnostics
```

Expected: tests PASS; `rg` returns no matches.

- [ ] **Step 5: Commit diagnostic tooling**

```powershell
git add skill/skyrim-engineering/scripts tests
git commit -m "feat: collect sanitized Skyrim diagnostics"
```

### Task 7: Anniversary Together Project Foundation

**Files:**
- Create: `projects/anniversary-together/test-cases.yaml`
- Create: `projects/anniversary-together/result.schema.json`
- Create: `projects/anniversary-together/manifest.schema.json`
- Create: `projects/anniversary-together/decisions.md`
- Create: `projects/anniversary-together/results/.gitkeep`
- Create: `tests/ProjectSchemas.Tests.ps1`

**Interfaces:**
- Produces test IDs `CONTROL-*`, `SYNC-*`, and `AE-*`; result statuses `pass`, `partial`, `host-only`, `desync`, `crash`, `blocked`, `untested`.

- [ ] **Step 1: Write failing schema tests**

Test that every case has unique `id`, `preconditions`, `steps`, `expected`, `evidence`, and `cleanup`; validate permitted status values and require anonymous private client slots, while public result schemas use `client-a|b|c` identifiers.

- [ ] **Step 2: Verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/ProjectSchemas.Tests.ps1 -Output Detailed"`

Expected: FAIL because schemas and cases do not exist.

- [ ] **Step 3: Implement schemas and control cases**

Add exact short cases for stock launch, local server connection, party creation, inventory, combat, quest stage, horse mount, pet command, home entry/container, Survival Mode, death, reconnect, and save continuity. Each case must reset or identify its save checkpoint and specify which logs/manifests to retain.

- [ ] **Step 4: Run schema tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/ProjectSchemas.Tests.ps1 -Output Detailed"`

Expected: PASS.

- [ ] **Step 5: Commit the project foundation**

```powershell
git add projects/anniversary-together tests/ProjectSchemas.Tests.ps1
git commit -m "feat: define Anniversary Together compatibility lab"
```

### Task 8: Safe Local Installation

**Files:**
- Create: `skill/skyrim-engineering/scripts/install-skill.ps1`
- Create: `tests/InstallSkill.Tests.ps1`

**Interfaces:**
- Consumes: `-RepositoryRoot`, optional `-CodexSkillsRoot`, and `-WhatIf`.
- Produces: junction `<CodexSkillsRoot>/skyrim-engineering` resolving exactly to `<RepositoryRoot>/skill/skyrim-engineering`.

- [ ] **Step 1: Write failing junction safety tests**

Test dry-run output, successful junction in a temporary directory, idempotence, refusal to replace a real directory, refusal to replace a link targeting elsewhere, and success when the correct junction already exists.

- [ ] **Step 2: Verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/InstallSkill.Tests.ps1 -Output Detailed"`

Expected: FAIL because the installer does not exist.

- [ ] **Step 3: Implement verified junction creation**

Resolve both roots with `[IO.Path]::GetFullPath()`. Require source `SKILL.md`. Inspect existing targets using `Get-Item -Force` and `LinkType/Target`; never call recursive deletion. Create only with `New-Item -ItemType Junction -Path $target -Target $source`. Support `ShouldProcess` for `-WhatIf`.

- [ ] **Step 4: Run tests and install locally**

```powershell
pwsh -NoProfile -Command "Invoke-Pester tests/InstallSkill.Tests.ps1 -Output Detailed"
pwsh -NoProfile -File skill/skyrim-engineering/scripts/install-skill.ps1 `
  -RepositoryRoot '<repository-root>' `
  -CodexSkillsRoot "$env:USERPROFILE\.codex\skills"
Get-Item -Force "$env:USERPROFILE\.codex\skills\skyrim-engineering" | Format-List LinkType,Target
```

Expected: tests PASS; `LinkType` is `Junction` and target is the canonical checkout skill directory.

- [ ] **Step 5: Commit installation tooling**

```powershell
git add skill/skyrim-engineering/scripts/install-skill.ps1 tests/InstallSkill.Tests.ps1
git commit -m "feat: safely install local Skyrim skill"
```

### Task 9: CI, Security Gates, and Full Verification

**Files:**
- Create: `.github/workflows/validate.yml`
- Create: `tests/PublicSafety.Tests.ps1`
- Modify: `tests/Repository.Tests.ps1`

**Interfaces:**
- Produces: one `validate` workflow that requires no proprietary files or credentials.

- [ ] **Step 1: Write failing public-safety tests**

Enumerate tracked files with `git ls-files`. Reject prohibited extensions (`.bsa`, `.esm`, `.esp`, `.esl`, `.ess`, `.skse`, `.dmp`, `.exe`, `.dll`, `.7z`, `.zip`) outside synthetic text fixtures; reject patterns for GitHub tokens, Steam IDs, personal absolute paths, IPv4 addresses in result data, and private-key headers.

- [ ] **Step 2: Verify failure before workflow creation**

Run: `pwsh -NoProfile -Command "Invoke-Pester tests/PublicSafety.Tests.ps1 -Output Detailed"`

Expected: FAIL because the required workflow is absent.

- [ ] **Step 3: Add the Windows validation workflow**

Pin `runs-on: windows-2022`; checkout the repository; install Pester 5 for CurrentUser; run `quick_validate.py`; parse all `.ps1`/`.psm1` files using the PowerShell parser API; run all Pester tests; run `git diff --check`; and upload only Pester XML on failure. Grant `contents: read` permissions.

- [ ] **Step 4: Run complete local verification**

```powershell
python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\quick_validate.py" .\skill\skyrim-engineering
pwsh -NoProfile -Command "$errors=$null; Get-ChildItem -Recurse -Include *.ps1,*.psm1 | ForEach-Object { [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$errors); if($errors){$errors; exit 1} }"
pwsh -NoProfile -Command "Invoke-Pester tests -Output Detailed"
git diff --check
```

Expected: validator success, parser success, all tests PASS, and clean diff check.

- [ ] **Step 5: Commit CI and gates**

```powershell
git add .github tests
git commit -m "ci: validate skill and public artifacts"
```

### Task 10: Public Repository, Forward Tests, and V1 Handoff

**Files:**
- Modify only if a forward test exposes a defect: skill, references, scripts, or tests directly responsible.
- Create: `projects/anniversary-together/results/example-sanitized.json`

**Interfaces:**
- Consumes: complete locally validated repository.
- Produces: public `leeheggan-droid/skyrim-engineering`, passing CI, locally linked skill, and five clean-context forward-test results.

- [ ] **Step 1: Create the public GitHub repository and push**

```powershell
gh repo create leeheggan-droid/skyrim-engineering --public --source . --remote origin --description "Reusable Skyrim SE/AE and Skyrim Together engineering skill, diagnostics, and compatibility research"
git push -u origin main
gh repo view leeheggan-droid/skyrim-engineering --json nameWithOwner,visibility,url,defaultBranchRef
```

Expected: public repository URL and default branch `main`.

- [ ] **Step 2: Verify GitHub Actions**

Run: `gh run list --repo leeheggan-droid/skyrim-engineering --workflow validate.yml --limit 1`

If queued or running, wait with `gh run watch <run-id> --repo leeheggan-droid/skyrim-engineering --exit-status`.

Expected: completed success. If it fails, inspect with `gh run view <run-id> --log-failed`, fix only the demonstrated defect, rerun all local checks, commit, and push.

- [ ] **Step 3: Forward-test five representative prompts in clean contexts**

Use the installed `$skyrim-engineering` skill with raw sanitized fixtures for: installed Anniversary catalogue identification; light-plugin FormID explanation; current upstream Windows build planning; sanitized crash triage; and three-client synchronization reproduction design. Do not include expected answers or this plan in the prompts.

Expected: each output selects the correct references, preserves fact/hypothesis boundaries, avoids private data, and proposes no Bethesda-file redistribution.

- [ ] **Step 4: Correct demonstrated skill defects and revalidate**

For each actual forward-test failure, add a focused test first, verify it fails, make the smallest skill/reference/script correction, rerun the focused test and full validation, then commit with `fix: <demonstrated behavior>`.

- [ ] **Step 5: Publish final commits and report V1 evidence**

```powershell
git push origin main
gh run list --repo leeheggan-droid/skyrim-engineering --workflow validate.yml --limit 1
git status --short
```

Expected: push succeeds, CI is green, worktree is clean, local junction resolves correctly, and the handoff reports exact validator/test/CI results plus any non-blocking limitations.

## Deferred Follow-Up Plans

After V1 is complete, create separate specifications and plans for:

1. Running the three-laptop Anniversary control matrix and recording sanitized results.
2. Forking/building Skyrim Together Reborn only after a reproducible upstream-code defect is isolated.
3. Packaging a family installation repository after the compatibility baseline is known.
