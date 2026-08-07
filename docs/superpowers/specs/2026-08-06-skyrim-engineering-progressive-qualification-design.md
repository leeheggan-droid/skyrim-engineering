# Skyrim Engineering Progressive Qualification Design

Date: 2026-08-06
Status: Approved for implementation planning

Scope amendment approved by the human owner on 2026-08-07: the `v0.1
provisional` laptop workflow is read-only. Component mutation remains deferred
until a native Windows handle-relative writer and OS-protected journal exist.

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

- a real Skyrim Together production process-boundary divergence/recovery test
  using at least two independent clients on two laptops;
- runtime, content, load-order, and tool parity before the multiplayer run;
- complete required control/result records, with omissions and unsupported cases
  recorded as `blocked` or `untested` rather than silently promoted;
- live CK, xEdit patch, or Papyrus migration evidence only when the release ships
  a change that uses that capability; read-only xEdit diagnostic readiness is
  retained independently;
- one fresh independent multiplayer/evidence PASS review and one fresh
  independent release/privacy PASS review;
- a deterministic release manifest derived from committed bytes; and
- the complete automated, privacy, licensing, and CI gates from `v0.1`.

No score or waiver converts missing applicable live evidence into a qualified
PASS. The former 80-percent-per-domain and 90/100 aggregate thresholds are not
release gates: their numerical precision did not map reliably to the family
laptop outcome.

## Codex-Led Laptop Bootstrap

The provisional skill includes a terminal-led assessment workflow that Codex
can run independently on each family laptop after Steam Skyrim Anniversary is
installed. The workflow understands that machines may already contain
different add-ons and profiles, but v0.1 does not mutate them.

Before changing anything it inventories the Skyrim runtime, complete Creation
set, plugins, archives, SKSE components, Address Library, Skyrim Together, mod
manager, profiles, load order, and relevant tool versions. It classifies items
as canonical Anniversary baseline, approved shared multiplayer component,
machine-specific add-on, or unknown/incompatible item.

The workflow exposes five explicit mode names with a deliberately narrower
v0.1 capability boundary:

- `-AuditOnly`: read-only discovery and sanitized inventory;
- `-Plan`: deterministic read-only assessment with an empty mutation action set;
- `-Verify`: compare the current anonymous client manifest with the canonical
  baseline;
- `-Apply`: fail nonzero with `skyrim-engineering.laptop-deferred/v1`; and
- `-Rollback`: fail nonzero with the same deferred schema.

The deferred response directs the operator to `AuditOnly`, `Plan`, or `Verify`.
Future mutation is delegated to a pinned MO2 or Wabbajack workflow: Codex emits
the profile/mod-list plan, verified package hashes, provenance, and post-install
parity checks, while the established tool owns installation and rollback. A
bespoke native writer is out of scope unless a demonstrated operation cannot be
expressed safely through those tools. The package catalog retains verified
intake hashes, layouts, versions, and provenance for comparison; it
does not authorize component installation in v0.1. Codex must not use this
workflow to install tooling or Skyrim components, create a multiplayer profile,
or remove prior workflow state. The separate exact-junction skill installer
remains enabled because it does not mutate a game or profile.

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
7. **Local installation and laptop assessment** — safe skill junction installer;
   Codex-led audit/plan/verify; explicit fail-closed Apply/Rollback deferral; and
   verified, privacy-safe discovery.
8. **CI and public safety** — complete automated validation.
9. **Provisional forward tests and publication** — five clean-context tests,
   public repository, green CI, and `v0.1 provisional` handoff.
10. **Multi-laptop defect discovery** — establish parity, then run stock Skyrim
    Together controls and Anniversary reproduction before designing a patch.
11. **Conditional patch qualification and V1 release** — use prepared CK,
    xEdit, or Papyrus practicals only for capabilities exercised by a
    demonstrated fix; complete scoped reviews, deterministic packaging, final
    validation, and `v1.0 qualified` publication.

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
