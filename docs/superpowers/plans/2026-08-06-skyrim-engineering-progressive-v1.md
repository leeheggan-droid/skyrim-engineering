# Skyrim Engineering Progressive V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, install, test, and publish a useful `v0.1 provisional` Skyrim Engineering skill first, then complete live qualification and publish `v1.0 qualified`.

**Architecture:** The canonical skill lives under `skill/skyrim-engineering` and is installed through a verified Windows junction. Automated repository, reference, script, privacy, and CI gates qualify the provisional release; separate fail-closed qualification records govern live CK, xEdit, Papyrus, and Skyrim Together evidence for V1.

**Tech Stack:** Markdown, PowerShell 7/Windows PowerShell-compatible scripts, Pester 5.9, Python skill tooling, JSON/YAML schemas, Git, GitHub CLI, GitHub Actions on `windows-2022`.

## Global Constraints

- Target Windows 11, Steam Skyrim Special Edition runtime `1.6.1170.0`, and the licensed complete Anniversary Creation Club library.
- Support Skyrim SE/AE engineering; exclude lore, walkthrough, cheat, console, VR, Game Pass, Epic, GOG, and Verified Creations work from V1.
- Default scripts to read-only operation, explicit paths, deterministic JSON, non-zero actionable failures, and concise human output.
- Never download paid content, bypass licences, alter Bethesda plugins, edit saves, change firewall rules, or install software implicitly.
- Never commit Bethesda assets, Nexus packages, Skyrim Together binaries, saves, PEX files, executables, dumps, private logs, credentials, Steam IDs, network addresses, usernames, or personal absolute paths.
- Synthetic fixtures test parsers and refusal behavior only; they never satisfy a live practical.
- A missing live practical records `blocked` or `untested`, never PASS.
- Keep Skyrim Together derivatives in a separate GPLv3 fork; do not copy upstream source here.
- Use LF generally and CRLF for `.ps1`/`.psm1`; scripts must parse under PowerShell 7 and Windows PowerShell 5.1 where available.
- Every completed task receives a focused independent review and a feature-branch commit.

---

### Task 0: History and Qualification Reconciliation

**Files:**
- Modify: `docs/expertise/*.md`
- Modify: `tests/Expertise.Tests.ps1`
- Modify: `tests/fixtures/evidence/*.json`
- Create: `qualification/README.md`
- Create: `tests/QualificationState.Tests.ps1`

**Interfaces:**
- Produces qualification schema `skyrim-engineering.qualification/v1` with track IDs `creation-kit`, `xedit`, `papyrus-runtime`, and `together-production`; status is `verified|blocked|untested`.
- Does not gate Tasks 1–8; gates only Task 10 and `v1.0 qualified`.

- [ ] **Step 1: Write the failing qualification-boundary test**

```powershell
Describe 'Progressive qualification boundary' {
    It 'keeps live tracks explicit without blocking provisional construction' {
        $state = Get-Content -Raw 'qualification/state.json' | ConvertFrom-Json
        $state.schema | Should -Be 'skyrim-engineering.qualification/v1'
        @($state.tracks.id) | Should -Be @('creation-kit','xedit','papyrus-runtime','together-production')
        @($state.tracks | Where-Object status -NotIn @('verified','blocked','untested')).Count | Should -Be 0
        $state.provisionalReleaseBlocked | Should -BeFalse
        $state.qualifiedReleaseBlocked | Should -BeTrue
    }
}
```

- [ ] **Step 2: Run the test and verify failure**

Run: `pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 5.9.0; Invoke-Pester tests/QualificationState.Tests.ps1 -Output Detailed"`
Expected: FAIL because `qualification/state.json` does not exist.

- [ ] **Step 3: Implement the boundary**

Create `qualification/state.json`, preserve every existing evidence file, label live tracks honestly, and update prose/tests so the expertise score controls only qualified release status. Remove any `CAPTURE_VERIFIED` claim produced solely from synthetic data; call such output `UNVERIFIED_SUBMISSION`.

- [ ] **Step 4: Verify and reconcile history**

Run the focused test, `tests/Expertise.Tests.ps1`, `git diff --check`, and `rg -n "CAPTURE_VERIFIED" tests/fixtures/preparation qualification docs/expertise`.
Expected: qualification-boundary PASS; expertise may remain BLOCKED only for live evidence/reviews; no synthetic acceptance claim.

- [ ] **Step 5: Commit**

```powershell
git add qualification docs/expertise tests
git commit -m "refactor: separate provisional and live qualification gates"
```

### Task 1: Repository Foundation and Discoverable Skill

**Files:**
- Create: `.gitattributes`, `LICENSE`, `tests/Repository.Tests.ps1`
- Modify: `.gitignore`
- Create: `skill/skyrim-engineering/SKILL.md`
- Create: `skill/skyrim-engineering/agents/openai.yaml`
- Create directories: `skill/skyrim-engineering/references`, `skill/skyrim-engineering/scripts`, `projects/anniversary-together`

**Interfaces:**
- Produces a structurally valid skill named `skyrim-engineering`.

- [ ] **Step 1: Write the failing repository test**

```powershell
Describe 'Repository foundation' {
    It 'contains a discoverable skill and private-artifact ignores' {
        'skill/skyrim-engineering/SKILL.md' | Should -Exist
        'skill/skyrim-engineering/agents/openai.yaml' | Should -Exist
        $ignore = Get-Content -Raw '.gitignore'
        @('*.dmp','*.ess','*.skse','*.pex','diagnostics-private/','manifests-private/') |
            ForEach-Object { $ignore | Should -Match ([regex]::Escape($_)) }
    }
}
```

- [ ] **Step 2: Verify RED**

Run the test; expect missing skill files.

- [ ] **Step 3: Initialize and configure**

Run `init_skill.py skyrim-engineering --path .\skill --resources scripts,references` with the approved display name, description, and default prompt. Add GPL-3.0-or-later, LF/PowerShell line-ending rules, and private artifact ignores. Remove initializer placeholders.

- [ ] **Step 4: Verify GREEN**

Run the repository test and `quick_validate.py .\skill\skyrim-engineering`; expect PASS.

- [ ] **Step 5: Commit**

```powershell
git add .gitattributes .gitignore LICENSE skill tests/Repository.Tests.ps1
git commit -m "chore: initialize Skyrim engineering skill"
```

### Task 2: Core Workflow and Versioned References

**Files:**
- Modify: `skill/skyrim-engineering/SKILL.md`, `skill/skyrim-engineering/agents/openai.yaml`
- Create: `skill/skyrim-engineering/references/{ecosystem,plugins-and-formids,diagnostics,together-reborn,anniversary-creations,build-and-release,research-ledger}.md`
- Create: `tests/Skill.Tests.ps1`, `tests/References.Tests.ps1`

**Interfaces:**
- Routes every engineering task directly to one reference or script.
- Unstable claims include `Claim`, `Source`, `Accessed`, `Applies to`, `Confidence`, and `Reproduced`.

- [ ] **Step 1: Write failing routing/reference tests**

```powershell
Describe 'Skyrim engineering skill' {
    BeforeAll { $skill = Get-Content -Raw 'skill/skyrim-engineering/SKILL.md' }
    It 'triggers and routes core surfaces' {
        @('Skyrim Together','Anniversary','FormID','Papyrus','crash','load order') |
            ForEach-Object { $skill | Should -Match ([regex]::Escape($_)) }
        Get-ChildItem 'skill/skyrim-engineering/references' -Filter '*.md' |
            ForEach-Object { $skill | Should -Match ([regex]::Escape("references/$($_.Name)")) }
    }
}
```

- [ ] **Step 2: Verify RED**

Run both tests; expect missing routes/references.

- [ ] **Step 3: Implement workflow and references**

Keep `SKILL.md` under 250 lines. Require version discovery, isolated reproduction, stock control, minimal sanitized evidence, observation/hypothesis separation, upstream inspection, focused tests, staged single/multi-client verification, legal packaging, and reviewed knowledge promotion. Author seven primary-source-led references dated `2026-08-06`; enumerate the 74 Anniversary creations by display name/plugin identifiers without assets.

- [ ] **Step 4: Verify GREEN**

Run `quick_validate.py`, both tests, and privacy/placeholder scan. Expect no unresolved/private matches.

- [ ] **Step 5: Commit**

```powershell
git add skill/skyrim-engineering tests/Skill.Tests.ps1 tests/References.Tests.ps1
git commit -m "feat: add Skyrim workflow and sourced references"
```

### Task 3: Shared Module and Installation Inspection

**Files:**
- Create: `skill/skyrim-engineering/scripts/SkyrimEngineering.Common.psm1`, `inspect-skyrim.ps1`
- Create: `tests/Common.Tests.ps1`, `tests/InspectSkyrim.Tests.ps1`
- Create: `tests/fixtures/steam/steamapps/appmanifest_489830.acf`, `tests/fixtures/game/SkyrimSE.exe.version.json`

**Interfaces:**
- Produces `Resolve-SkyrimInstall`, `Get-RelativeSafePath`, `Get-StableSha256`, `Protect-DiagnosticText`, and schema `skyrim-engineering.inspect/v1`.

- [ ] **Step 1: Write failing tests** for explicit Steam resolution, missing manifests, SHA-256, safe paths, redaction, and JSON runtime/store output.
- [ ] **Step 2: Verify RED** with focused Pester invocation.
- [ ] **Step 3: Implement minimal ordered-object functions and inspector**; permit synthetic version JSON only beneath `tests/fixtures` when the executable is absent.
- [ ] **Step 4: Verify GREEN and run read-only live inspection**; expect Steam runtime `1.6.1170.0` without account identifiers.
- [ ] **Step 5: Commit** with `git commit -m "feat: inspect Skyrim installations safely"`.

### Task 4: Creation Inventory and Cross-Machine Comparison

**Files:**
- Create: `skill/skyrim-engineering/scripts/inventory-creations.ps1`, `compare-installations.ps1`
- Create: `tests/InventoryCreations.Tests.ps1`, `tests/CompareInstallations.Tests.ps1`
- Create: synthetic text fixtures under `tests/fixtures/creations` and `tests/fixtures/manifests`

**Interfaces:**
- Inventory schema `skyrim-engineering.creations/v1`; comparison schema `skyrim-engineering.comparison/v1`.
- Comparison exits `0` parity, `2` differences, `1` malformed input.

- [ ] **Step 1: Write failing tests** for stable ordering, lowercase hashes, relative paths, `notInspected` flags, parity, and difference categories.
- [ ] **Step 2: Verify RED** because entrypoints are missing.
- [ ] **Step 3: Implement inventory and comparison** for `cc*.esl|esm|esp|bsa` plus four free Creation identifiers.
- [ ] **Step 4: Verify GREEN and inventory the live Data directory** without emitting absolute paths or content.
- [ ] **Step 5: Commit** with `git commit -m "feat: inventory and compare Anniversary installations"`.

### Task 5: Sanitized Diagnostics and Compatibility Schemas

**Files:**
- Create: `skill/skyrim-engineering/scripts/collect-diagnostics.ps1`
- Create: `tests/CollectDiagnostics.Tests.ps1`, `tests/ProjectSchemas.Tests.ps1`
- Create: `projects/anniversary-together/test-cases.yaml`, `result.schema.json`, `manifest.schema.json`, `decisions.md`, `results/.gitkeep`

**Interfaces:**
- Diagnostic schema `skyrim-engineering.diagnostics/v1`; allow `.log|txt|ini|json|toml`, maximum 25 MiB each.
- Result status `pass|partial|host-only|desync|crash|blocked|untested`; public clients `client-a|b|c`.

- [ ] **Step 1: Write failing sanitization/schema tests** including username, home path, Steam ID, IPv4, password, token, FormID preservation, refused binaries, unique cases, evidence, and cleanup.
- [ ] **Step 2: Verify RED**.
- [ ] **Step 3: Implement collector and schemas**; reject output inside source, refuse overwrite without `-Force`, and add stock/party/inventory/combat/quest/horse/pet/home/Survival/death/reconnect/save cases.
- [ ] **Step 4: Verify GREEN and scan output for fixture secrets**.
- [ ] **Step 5: Commit** with `git commit -m "feat: add sanitized diagnostics and compatibility lab"`.

### Task 6: Safe Local Skill Installation and Codex Laptop Bootstrap

**Files:**
- Create: `skill/skyrim-engineering/scripts/install-skill.ps1`
- Create: `skill/skyrim-engineering/scripts/setup-laptop.ps1`
- Create: `skill/skyrim-engineering/references/laptop-setup.md`
- Create: `tests/InstallSkill.Tests.ps1`, `tests/SetupLaptop.Tests.ps1`
- Create: `tests/fixtures/laptop/{canonical,client-extra,client-mismatch}/`

**Interfaces:**
- Consumes `-RepositoryRoot`, optional `-CodexSkillsRoot`, `-WhatIf`; creates only an exact verified junction.
- `setup-laptop.ps1` consumes exactly one mode from `-AuditOnly|-Plan|-Apply|-Verify|-Rollback`, `-ClientId client-a|client-b|client-c`, explicit `-GameRoot`, `-ProfileRoot`, `-CanonicalManifest`, and `-StateDirectory`.
- Produces sanitized schemas `skyrim-engineering.laptop-audit/v1`, `skyrim-engineering.laptop-plan/v1`, and `skyrim-engineering.laptop-state/v1` with categories `anniversaryBaseline|approvedShared|machineSpecific|unknownOrIncompatible`.

- [ ] **Step 1: Write failing tests** for dry-run, junction success/idempotence/refusals, mutually exclusive modes, anonymous client IDs, deterministic audit/plan output, missing/extra/hash/version/order differences, preservation of existing profiles/add-ons, confirmation-required Apply, state-scoped rollback, and secret/personal-path rejection.
- [ ] **Step 2: Verify RED**.
- [ ] **Step 3: Implement with `SupportsShouldProcess`**, full-path checks, source `SKILL.md` requirement, no recursive deletion, read-only audit/plan/verify defaults, pinned/hash-verified approved free packages, an isolated `Anniversary Together` profile, recorded mutation journal, and rollback limited to that journal. Never install Steam, authenticate accounts, download licensed Bethesda content, copy saves, alter firewall rules, overwrite/delete add-ons, or install unapproved Nexus packages.
- [ ] **Step 4: Author the Codex terminal guide** with exact audit, plan, separately confirmed apply, verify, and rollback commands; explain canonical baseline versus machine-specific add-ons and require existing Steam Anniversary installation.
- [ ] **Step 5: Verify GREEN**, install into `C:\Users\jacks\.codex\skills`, run `-AuditOnly` on the reference laptop, inspect junction target, and confirm output contains no personal paths/account IDs/network data.
- [ ] **Step 6: Commit** with `git commit -m "feat: install Skyrim skill and bootstrap laptops safely"`.

### Task 7: CI and Public Safety

**Files:**
- Create: `.github/workflows/validate.yml`, `tests/PublicSafety.Tests.ps1`
- Modify: `tests/Repository.Tests.ps1`

**Interfaces:**
- Produces a credential-free `windows-2022` workflow with `contents: read`.

- [ ] **Step 1: Write failing public-safety tests** rejecting prohibited binaries/game files, token patterns, Steam IDs, personal paths, private keys, and private result IPs.
- [ ] **Step 2: Verify RED** because workflow is absent.
- [ ] **Step 3: Add CI**: checkout, Python, Pester 5.9, quick validator, parser API, full Pester, `git diff --check`, and failure-only Pester XML artifact.
- [ ] **Step 4: Run full local validation** and require validator, parser, Pester, privacy scan, and diff check PASS.
- [ ] **Step 5: Commit** with `git commit -m "ci: validate provisional Skyrim skill"`.

### Task 8: Provisional Publication and Forward Tests

**Files:**
- Create: `projects/anniversary-together/results/example-sanitized.json`
- Modify only demonstrated defects in skill/references/scripts/tests.

**Interfaces:**
- Produces public `leeheggan-droid/skyrim-engineering`, green CI, installed skill, five forward-test records, and tag `v0.1.0` labelled provisional.

- [ ] **Step 1: Run five clean-context prompts** for Anniversary catalogue, light FormID, Windows upstream build, sanitized crash triage, and three-client reproduction; save sanitized evaluations.
- [ ] **Step 2: Fix demonstrated failures test-first**, then rerun focused/full validation.
- [ ] **Step 3: Complete whole-branch review** and resolve Critical/Important findings.
- [ ] **Step 4: Merge to `main`, create/push public repository, push `v0.1.0`, and watch GitHub Actions to success**.
- [ ] **Step 5: Verify public state** with `gh repo view`, `gh run list`, junction inspection, tag inspection, and clean worktree; commit example result before merge with `git commit -m "release: prepare provisional Skyrim skill"`.

### Task 9: Local Live Qualification

**Files:**
- Modify: `qualification/state.json`, `docs/expertise/*`, qualification contracts/captures using sanitized text and hashes only.
- Test: `tests/QualificationState.Tests.ps1`, `tests/Expertise.Tests.ps1`

**Interfaces:**
- Verifies `creation-kit`, `xedit`, and `papyrus-runtime` tracks against exact live schemas; no synthetic promotion.

- [ ] **Step 1: Strengthen adversarial gate tests** so editable booleans, arbitrary bytes, stale logs, wrong runtime/tool versions, and missing captures remain blocked; verify RED against existing flawed paths.
- [ ] **Step 2: Implement fail-closed validators and deterministic preparation tooling**, with bounded external processes and protected-input hashes after every phase.
- [ ] **Step 3: Execute guided CK, xEdit, and Papyrus practicals** on disposable profiles; retain only sanitized metadata/hashes.
- [ ] **Step 4: Run focused gates and independent domain review**; require all three tracks `verified` or keep Task 9 open.
- [ ] **Step 5: Commit** with `git commit -m "test: qualify local Skyrim engineering workflows"`.

### Task 10: Multiplayer Qualification and V1 Release

**Files:**
- Modify: `qualification/state.json`, `docs/expertise/assessment-results.md`, machine-readable assessment/review state.
- Create: sanitized production test result under `projects/anniversary-together/results/`.

**Interfaces:**
- Verifies `together-production`; produces every domain >=80%, overall >=90/100, two named independent PASS scopes, tag `v1.0.0`.

- [ ] **Step 1: Inventory two laptops with Task 4 tooling** and require runtime/content/load-order parity before launch.
- [ ] **Step 2: Run server plus two independent clients**, reproduce a controlled inventory divergence/recovery across the real production process boundary, and retain sanitized logs/manifests.
- [ ] **Step 3: Recompute assessment from atomic evidence**; require all domain thresholds, zero automatic blocks, deterministic committed-byte package, and consistent human/machine state.
- [ ] **Step 4: Dispatch two fresh independent evidence reviewers** for data/CK/Papyrus and Together/runtime/build; resolve every Critical/Important finding and rerun all local/CI gates.
- [ ] **Step 5: Complete final whole-branch review, push reviewed commits, tag/push `v1.0.0`, watch green CI, verify clean worktree and installed junction, and deliver exact V1 evidence.**

## Completion Rule

The project is complete only after Task 10 and `v1.0.0` are verified. Task 8 publishes a useful provisional skill but does not redefine the full objective.
