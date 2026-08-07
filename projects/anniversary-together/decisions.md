# Anniversary Together compatibility lab

This repository contains repeatable compatibility contracts, not player data.
Actual participant identities stay in a private, untracked local roster. Tracked
artifacts map private `slot-1`, `slot-2`, and `slot-3` to the public roles `host`,
`client-a`, and `client-b`, respectively. The mapping is fixed for a run so logs,
results, and operator instructions cannot disagree about authority.

The host is the authority for irreversible quest, world, dialogue, and scene
state. Clients exercise bounded combat and loot actions, then record whether
the host commit converges. Each case names its checkpoint, retained sanitized
diagnostic evidence, and cleanup before it is run.

Only clean campaign saves are used locally. Saves, dumps, binaries, licensed
assets, Steam IDs, network addresses, and real names are never committed.

## Canonical manifest creation and parity gate

Before opening the server, choose the host's already-authorized Anniversary
installation as the run's canonical profile. Run
`tools/inventory-creations.ps1 -DataPath <host-data> -Json` and save its sanitized
output outside Git as `manifests-private/canonical.json`; record that file's
SHA-256 in the project manifest. Generate a fresh inventory for `host`,
`client-a`, and `client-b`, then run `tools/compare-installations.ps1` against
the canonical manifest for each participant. Hash all three comparison reports.

This reconciliation is read-only. Every report must match before any test case
runs. A missing report, changed hash, missing or extra file, hash/size/order
difference, or malformed manifest leaves the run provisional and the mismatch
blocked. Do not copy, delete, reorder, download, or otherwise repair game or
Creation files through this workflow. Correct the authorized installation with
its normal owner-controlled tooling, generate all manifests again, and restart
the gate.

## Result discipline

Create all 13 result files in the schema's canonical order, including blocked or
untested results; omission is not success. Each result pins Skyrim, Skyrim
Together Reborn, and server versions; identifies all three public participants;
records expected versus actual observations; separates Observation from
Hypothesis; states confidence, uncertainty, tests, and a falsifying check; and
attributes each relevant Anniversary Creation as implicated, not implicated, or
unknown with a basis. Evidence is sanitized with
`tools/collect-diagnostics.ps1`, and each retained file is bound by SHA-256.

The repository remains a provisional test contract until those live artifacts
exist. Its schemas and empty results directory do not claim multiplayer
qualification.
