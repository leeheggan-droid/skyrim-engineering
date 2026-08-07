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
`skill/skyrim-engineering/scripts/inventory-creations.ps1 -DataPath <host-data> -Json` and save its reviewed
output outside Git as `manifests-private/canonical.json`; record that file's
SHA-256 in the project manifest. Generate a fresh inventory for `host`,
`client-a`, and `client-b`, then run
`skill/skyrim-engineering/scripts/compare-installations.ps1 -ManifestPath <canonical>,<participant> -Json`
for each participant. Hash all three comparison reports.

This reconciliation is read-only. Every report must match before any test case
runs. A missing report, changed hash, missing or extra file, hash/size/order
difference, or malformed manifest leaves the run provisional and the mismatch
blocked. Set `mismatchDisposition` to `blocked-read-only` and
`publicationStatus` to `provisional-blocked`. Only when all three reports match
may those fields be `ready` and `eligible-for-live-record`. Do not copy, delete,
reorder, download, or otherwise repair game or
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
`skill/skyrim-engineering/scripts/collect-diagnostics.ps1 -InputPath <raw-log> -OutputDirectory <case-evidence-root>`,
and each retained file is bound by SHA-256.

## Deterministic case logs and fixture pins

Before a case, record every operator-selected fixture in `fixture-pins.json`:
case ID, relative plugin filename, local FormID as a hexadecimal string when
available, cell/editor identifier, item/actor/quest identifier, and the
canonical plugin SHA-256. Use stable synthetic labels only for character names.
If an identifier cannot be pinned before the run, mark the case `blocked`; do
not substitute an improvised target.

Each participant creates its case log locally as UTF-8 without BOM, one compact
JSON object per line (JSON Lines). Keys are emitted in this order: `schema`
(`skyrim-engineering.anniversary-together.case-log/v1`), `caseId`,
`participant`, `relativeSecond` (integer relative to T0), `event`, and
`observed`. `event` is a lowercase hyphenated public label; `observed` contains
only relative identifiers and bounded state, never free-form player data.
Operators append one record at every timing point named by the case, then run
the diagnostic collector on the local log and `fixture-pins.json`. Manual
privacy review remains mandatory before a hash or excerpt is published.

For `SYNC-010`, each participant creates its own authorized local test save at
the named T0 checkpoint, exits, then loads that same local save before
reconnecting in role order. Never copy or redistribute a save between
participants. The three local saves share a public checkpoint label only; they
are not assumed byte-identical and are deleted only after evidence hashes are
recorded.

The repository remains a provisional test contract until those live artifacts
exist. Its schemas and empty results directory do not claim multiplayer
qualification.
