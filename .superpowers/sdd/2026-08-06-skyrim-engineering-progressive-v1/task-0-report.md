# Task 0: History and Qualification Reconciliation

Date: 2026-08-06

## Outcome

Task 0 separates construction of the `v0.1 provisional` skill from the live
qualification required for Task 10 and `v1.0 qualified`.

- Added `qualification/state.json` using
  `skyrim-engineering.qualification/v1`.
- Recorded `creation-kit`, `xedit`, and `papyrus-runtime` as `blocked`; recorded
  `together-production` as `untested`.
- Set `provisionalReleaseBlocked` to `false` and
  `qualifiedReleaseBlocked` to `true`.
- Retained the existing assessment, review, artefact, practical, source, and
  toolchain evidence. The 76/100 assessment and unresolved reviews now apply
  only to the qualified release gate.
- Replaced the synthetic Papyrus capture result
  `CAPTURE_VERIFIED` with `UNVERIFIED_SUBMISSION`. The record still checks
  staged bytes, phase-separated markers, and save hashes, but no longer claims
  runtime provenance.
- Re-baselined the deterministic original-only release manifest after the
  documentation and test changes.

## TDD record

1. Added `tests/QualificationState.Tests.ps1` before creating
   `qualification/state.json`.
2. Ran it with Pester 5.9.0 through `pwsh`; both assertions failed because the
   state file did not exist.
3. Added the minimal qualification state and boundary metadata.
4. Reran the focused test: 2 passed.

## Verification

- `pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 5.9.0; Invoke-Pester tests/QualificationState.Tests.ps1, tests/Expertise.Tests.ps1 -Output Detailed"`
  - PASS: 10 tests.
- `git diff --check`
  - PASS.
- `rg -n "CAPTURE_VERIFIED" tests/fixtures/preparation qualification docs/expertise`
  - PASS: no matches.
- The broader scan intentionally retains `CAPTURE_VERIFIED` only in the xEdit
  full external-tool execution path; its `-PrepareOnly` synthetic-plan path
  emits `PREPARED`, not a capture claim. No xEdit capture has been committed or
  promoted.

## Review

Self-review confirmed that all track IDs and allowed status values match the
approved interface, that blocked/untested tracks name their exact dependency,
reproduction and cleanup boundaries, and that no live practical was fabricated
or promoted. The approved Task 6 Codex-led laptop-bootstrap updates to the
progressive design and plan are included as documentation only; no bootstrap
implementation is part of this task.

## Remaining qualification work

`v1.0 qualified` remains blocked pending original Creation Kit and xEdit
round-trips, the live Papyrus V1-to-V2 save/load capture, a two-laptop Skyrim
Together production divergence/recovery capture, sufficient scoring, and two
independent PASS reviews.
