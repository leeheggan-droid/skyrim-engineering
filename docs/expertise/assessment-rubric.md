# Skyrim engineering assessment rubric

Version: 1.0
Established: 2026-08-06 before any scored assessment response.
Rules: 100 points total; each domain requires at least 80% of its own maximum; overall requires at least 90/100; no waiver is permitted. A domain that misses threshold requires remediation practicals and a fresh equivalent assessment. Scores are never averaged across attempts.

Assessment answers must be produced from the raw synthetic snippets in [practicals.md](practicals.md), the audited source at commit `9d81ef07…`, and the primary sources in [source-register.md](source-register.md). The syllabus is not an answer key. Every assessor records the evidence link, concrete finding and remediation.

## Data model — 15 points; pass at 12

- 4: Decode and re-encode the literal standard and `FE` FormIDs; show masks/shifts and bounds without using a helper that mirrors the answer.
- 4: Given a TES4 header/master-table fixture, trace master-relative to runtime identity and identify missing-master behavior.
- 4: Diagnose a three-record override chain and design the smallest safe patch, including ESL/compaction risks.
- 3: Explain plugin versus assets/archives/localization completeness and produce a no-copy inspection plan.

Automatic domain block: either FormID direction wrong, compaction proposed without dependent-plugin migration, or proprietary data included.

## Creation Kit / design — 15 points; pass at 12

- 5: Build and demonstrate the original practical containing cell object, actor, package, inventory item, quest stage/dialogue and event.
- 4: Explain alias, dialogue condition, stage/objective, package and persistence interactions from the created fixture.
- 3: Validate cell/navmesh ownership and finalization without dirtying unrelated masters.
- 3: Produce original-only package contents and rollback.

Automatic domain block: no current SE Creation Kit practical, save to live/master content, or copied Bethesda/third-party asset.

## xEdit — 10 points; pass at 8

- 3: Read-only inspect header, masters, flags, VMAD, archives and conflict chain; prove no save.
- 3: Diagnose winning/losing overrides and missing master from raw fixture.
- 2: Design a minimal new patch with required masters and post-save re-open/error check.
- 2: Explain cleaning and scripting boundaries using current maintainer documentation.

Automatic domain block: tool absent, unintended save, unsafe cleaning, or obsolete guidance used as authority.

## Papyrus — 10 points; pass at 8

- 3: Compile the original event and record exact compiler inputs/output.
- 2: Trigger and diagnose the deliberate safe compile error.
- 3: Explain events, VM scheduling, latent work, logs, persistence and save-baked state using the fixture.
- 2: Design a disposable-save migration/retest plan.

Automatic domain block: no real compiler evidence or live/personal save risk.

## Runtime extensibility — 10 points; pass at 8

- 3: Match runtime `1.6.1170.0`, SKSE build and Address Library data exactly.
- 3: Trace loader/plugin API, relocation and one hook/serialization boundary from primary source.
- 2: Diagnose ABI/address/update risks that Address Library does and does not mitigate.
- 2: Design isolated runtime verification and rollback.

Automatic domain block: mismatched DLL/runtime executed or compatibility inferred solely from a launch.

## Diagnostics — 10 points; pass at 8

- 3: Triage the raw crash snippet with matching symbols/tool output and distinguish observation/hypothesis.
- 2: Diagnose missing-master and parity fixtures without destructive edits.
- 3: Reproduce the desynchronization fixture across the client/server edge and identify the first missing edge.
- 2: Propose a minimally scoped fix, verification matrix and privacy-safe evidence bundle.

Automatic domain block: blame from a stack mention alone, no reproduction, or personal/licensed artefact leak.

## Packaging / legal — 10 points; pass at 8

- 3: Produce exact hashes/provenance/version/licence for every released file.
- 3: Justify redistribution rights and GPL obligations; exclude proprietary/unauthorized content.
- 2: Verify supported versions, install destination and deterministic package contents.
- 2: Demonstrate rollback and intake rejection/quarantine handling.

Automatic domain block: missing provenance/hash, incompatible licence, or unauthorized binary/asset.

## Skyrim Together architecture / build — 20 points; pass at 16

- 4: Trace standard/lite mod mapping and `GameId` wire order with exact source functions.
- 4: Trace actor ownership/capture/server components/remote application and state authority boundaries.
- 4: Trace inventory and quest stage capture, encoding, server update/broadcast and remote application, including default feature gates.
- 5: Reproducibly configure/build/test/install the pinned source with initialized submodules and recorded tool versions.
- 3: Design focused tests and an upstream GPL-compliant contribution/three-client verification path.

Automatic domain block: build absent, source path/function materially wrong, default experimental setting omitted, or source-only inference presented as runtime proof.

## Assessment protocol

This rubric controls the `v1.0 qualified` gate. Synthetic fixtures test
reasoning and refusal behavior only; they cannot earn live-practical credit or
verify a qualification track. It does not block construction of the safe `v0.1
provisional` skill.

1. Freeze raw fixtures and source commit; record hashes/commit.
2. Give the candidate only raw fixtures, source locations and primary sources, not model answers or intended conclusions.
3. Candidate submits explanation, diagnosis, design and executed build/practical evidence.
4. Primary assessor scores each atomic item and documents deductions.
5. Two independent reviewers separately cover (a) data/Creation Kit/Papyrus and (b) Together/runtime/build. Each checks source accuracy, reproducibility, scoring, blind spots and gate verdict.
6. Resolve every Critical or Important finding, then run an equivalent fresh attempt for any failed or blocked domain.
7. Pass only when every row meets its domain threshold, overall is at least 90, both reviewers approve, all practicals pass, and automated/privacy gates pass.
