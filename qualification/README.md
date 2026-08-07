# Live qualification state

`state.json` is the authoritative routing record for live qualification. It
does not authorize a release and cannot turn a fixture result into live
evidence.

The `v0.1 provisional` construction gate is intentionally separate: its
repository, safety, capability, and automated checks do not require a Creation
Kit GUI run, a Skyrim runtime run, or two laptops. This record gates Task 10
and the `v1.0 qualified` release only.

The human-approved v0.1 laptop boundary is also intentionally separate from
this live state: `setup-laptop.ps1` supports read-only AuditOnly, Plan, and
Verify. Apply and Rollback are delegated to a pinned MO2 or Wabbajack workflow
with profile isolation and tool-owned rollback. That deferral does not change
or waive any live qualification track below.

Each live track is one of:

- `verified`: a later validator has rechecked committed, sanitized capture
  metadata and hashes against the track schema, with required human review.
- `blocked`: a required live capture or review is known to be absent.
- `untested`: the production practical has not been attempted.

Synthetic fixtures, prepared plans, compiler output, and ordinary unit tests
may test parsing and refusal behavior. They are not runtime provenance and
must use `UNVERIFIED_SUBMISSION` when they emit a capture-shaped record. A
status field edited by hand is never sufficient to produce `verified`.

When a track becomes verified, retain only legally redistributable, sanitized
metadata, exact tool/runtime versions, capture and protected-input hashes,
observation/hypothesis boundaries, reproduction/cleanup commands, and named
review findings. Keep plugins, saves, PEX files, executables, dumps, raw logs,
and licensed content outside Git.
