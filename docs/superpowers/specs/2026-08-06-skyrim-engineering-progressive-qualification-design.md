# Skyrim Engineering Progressive Qualification Design

Date: 2026-08-06
Status: Approved for implementation planning

## Purpose

Build, install, test, and publish a useful Skyrim Engineering skill before
requiring live Creation Kit, Skyrim runtime, or multi-laptop qualification.
Preserve the existing expertise evidence and strict release standard, but move
those checks to the stage where a completed skill can help execute them.

The capability is integration-first. It must reuse and cite the strongest
existing Skyrim knowledge available—official Bethesda and Creation Kit
documentation, xEdit/SKSE/Address Library material, Tilted Evolution source and
documentation, established tool behavior, and versioned community reproduction
evidence—before creating new mechanisms. Original work focuses on closing
demonstrated Skyrim Together Anniversary compatibility gaps, not replacing the
existing Skyrim modding ecosystem or pre-emptively rewriting upstream code.

The release sequence has two explicit milestones:

- `v0.1 provisional`: a public, locally installed, safe engineering skill whose
  repository, references, scripts, schemas, tests, security gates, and forward
  tests pass without claiming completion of unavailable live practicals.
- `v1.0 qualified`: the same capability after all mandatory live practicals,
  scoring thresholds, and independent reviews pass.

“Provisional” describes qualification state, not disposable quality. All code,
privacy, licensing, deterministic-output, and automated-test requirements apply
to both milestones.

## Problem With the Original Sequence

The original Task 0 made complete live expertise qualification a prerequisite
for creating the skill. That created a circular dependency: the skill's
references, diagnostics, manifests, and test workflows were needed to conduct
the practicals that blocked the skill from being built.

It also combined three different gates:

1. repository and software safety;
2. useful skill capability; and
3. live human/hardware qualification.

The revised sequence separates these concerns. Missing hardware or GUI evidence
must remain visible and fail closed, but it cannot prevent construction of the
tools needed to gather that evidence.

## Release Architecture

### Provisional capability gate

The `v0.1 provisional` gate requires:

- a structurally valid `skyrim-engineering` skill and generated UI metadata;
- all seven versioned reference files with explicit evidence fields;
- read-only installation inspection;
- Creation inventory and cross-machine comparison;
- allowlisted, sanitized diagnostic collection;
- Anniversary Together test/result schemas;
- safe, verified local junction installation;
- Windows CI, PowerShell parsing, Pester tests, link/placeholder scans, public
  artifact safety checks, and a clean diff check;
- five clean-context forward tests;
- a public GitHub repository with green CI; and
- explicit qualification status showing each live track as `verified`,
  `blocked`, or `untested`.

The provisional gate must not award live-practical credit from synthetic data.
Synthetic fixtures may validate parsers and fail-closed behavior only.

### Qualified capability gate

The `v1.0 qualified` gate additionally requires:

- an original Creation Kit plugin round-trip containing the required quest,
  alias, objective, condition, package, and navmesh work;
- a real xEdit minimal patch/save/reopen inspection with protected-input hashes;
- a real Skyrim `1.6.1170.0` Papyrus V1-to-V2 save/load migration capture;
- a real Skyrim Together production process-boundary divergence/recovery test
  using at least two independent clients on two laptops;
- at least 80 percent in every expertise domain and 90/100 overall;
- two fresh independent PASS reviews covering the required review scopes;
- a deterministic release manifest derived from committed bytes; and
- the complete automated, privacy, licensing, and CI gates from `v0.1`.

No waiver converts missing live evidence into a qualified PASS.

## Codex-Led Laptop Bootstrap

The provisional skill will include a terminal-led setup workflow that Codex can
run independently on each family laptop after Steam Skyrim Anniversary is
installed. The workflow must understand that machines may already contain
different add-ons and profiles.

Before changing anything it inventories the Skyrim runtime, complete Creation
set, plugins, archives, SKSE components, Address Library, Skyrim Together, mod
manager, profiles, load order, and relevant tool versions. It classifies items
as canonical Anniversary baseline, approved shared multiplayer component,
machine-specific add-on, or unknown/incompatible item.

The workflow exposes five explicit modes:

- `-AuditOnly`: read-only discovery and sanitized inventory;
- `-Plan`: deterministic proposed actions without mutation;
- `-Apply`: install only approved free components and create an isolated
  `Anniversary Together` profile after confirmation;
- `-Verify`: compare the resulting anonymous client manifest with the canonical
  baseline; and
- `-Rollback`: reverse only changes recorded by the workflow.

Codex may install pinned, hash-verified free tooling and approved free Skyrim
components such as SKSE, Address Library, and Skyrim Together after a separate
confirmation. It must not install Steam, authenticate accounts, purchase or
download licensed Bethesda content, copy saves, change firewall rules, delete
or overwrite existing add-ons, or install unapproved Nexus packages.

Machine-specific add-ons remain preserved in their existing profiles and are
excluded from the multiplayer profile until compatibility is explicitly
approved. Comparison reports distinguish missing, extra, hash-different,
version-different, and order-different content. Public artifacts use only
`client-a`, `client-b`, and `client-c` identifiers and contain no personal
paths, account IDs, credentials, network addresses, or copied game assets.

## Repository Layout and State

The canonical skill remains under `skill/skyrim-engineering` and is installed
through a verified junction from the Codex skills directory.

Existing Step Zero material will be retained as qualification evidence and
contracts. Human-readable and machine-readable qualification state must agree.
The exact folder placement may remain under `docs/expertise` and
`tests/fixtures` in the first implementation if moving it would create needless
history churn; routing and naming must make clear that it governs `v1.0`, not
the existence of `v0.1`.

Live or proprietary outputs remain outside Git, including game plugins,
archives, saves, PEX files, executables, dumps, raw private logs, and licensed
mod packages. Only sanitized original text, hashes, schemas, scripts, and
legally redistributable patches may enter the public repository.

## Revised Phase Order

1. **Plan and history reconciliation** — replace the original blocking sequence
   with this progressive plan and ensure intermediate history is reproducible.
2. **Repository foundation** — hygiene, licence, skill skeleton, and repository
   structure tests.
3. **Core skill routing** — concise workflow, metadata, task/reference routes,
   and validator tests.
4. **Reference baseline** — seven sourced, versioned references.
5. **Inspection and parity tooling** — shared PowerShell module, installation
   inspection, Creation inventory, and cross-machine comparison.
6. **Diagnostics and project schemas** — sanitized collection plus Anniversary
   Together control/result definitions.
7. **Local installation and laptop bootstrap** — safe junction installer,
   Codex-led audit/plan/apply/verify/rollback workflow, add-on-preserving profile
   isolation, and verified discovery.
8. **CI and public safety** — complete automated validation.
9. **Provisional forward tests and publication** — five clean-context tests,
   public repository, green CI, and `v0.1 provisional` handoff.
10. **Local live qualification** — CK, xEdit, and Papyrus practicals using the
    installed skill and fail-closed capture tooling.
11. **Multi-laptop qualification and V1 release** — production Skyrim Together
    reproduction, rescoring, two independent reviews, final validation, and
    `v1.0 qualified` publication.

Each phase follows test-first implementation, focused verification, independent
review, and a durable feature-branch commit. A phase commit represents that
phase only; it does not imply later qualification. The completed provisional
capability is merged to `main` and published before live hardware qualification.
Qualification work then continues through reviewed commits and a qualified tag.

## Qualification State Model

Each live track records:

- stable track identifier;
- status: `verified`, `blocked`, or `untested`;
- exact required runtime/tool version;
- capture schema and artifact hashes when verified;
- observation versus hypothesis boundaries;
- reproduction and cleanup commands;
- sanitized reviewer findings; and
- blocking dependency when not verified.

Only a validator that rechecks the underlying committed capture metadata may
derive `verified`. Editable prose or a self-declared Boolean is insufficient.
Where automation cannot prove runtime provenance, the record must say so and
require named human review rather than output `CAPTURE_VERIFIED`.

## Testing and Review

Automated tests use synthetic fixtures to prove deterministic behavior,
sanitization, validation, negative paths, and refusal rules. They never stand in
for a real Skyrim, Creation Kit, xEdit, or multi-client run.

Every implementation phase receives:

1. an observed failing test;
2. the minimal implementation;
3. focused and regression verification;
4. an independent spec-and-quality review; and
5. a phase commit only after findings are resolved.

Before `v0.1`, a whole-branch review checks the skill, scripts, public safety,
and release claims. Before `v1.0`, two domain reviewers independently assess the
raw qualification evidence and scoring in addition to the final code review.

For any proposed Skyrim Together change, the evidence package must first show
the current upstream behavior, applicable Anniversary content/runtime, prior
art searched, and a reproducible compatibility defect. Prefer configuration,
profile parity, documented upstream capabilities, or a focused upstream-quality
fix over a parallel bespoke implementation. No fork or patch is justified by
the mere presence of Anniversary content.

## Error Handling and Safety

- Missing live evidence yields `blocked` or `untested`, never an inferred PASS.
- Invalid, stale, mismatched, or untrusted capture inputs fail without writing an
  acceptance record.
- Scripts prefer explicit paths, refuse unsafe overwrite, and default to
  read-only behavior.
- External processes receive bounded timeouts and scoped cleanup.
- No script installs software, modifies Bethesda content, edits saves, changes
  firewall rules, or downloads licensed content implicitly.
- Public checks reject credentials, personal paths, Steam identifiers, private
  network data, and prohibited binary/game artifacts.

## Completion Criteria

The project goal is complete only when both milestones are evidenced:

- `v0.1 provisional` exists publicly, has green CI, is installed locally, and
  passes all five forward tests; and
- `v1.0 qualified` satisfies every live track, scoring threshold, independent
  review, deterministic release, and CI requirement.

Publishing `v0.1` is meaningful progress but does not redefine or complete the
full V1 objective.
