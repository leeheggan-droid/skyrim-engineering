---
name: skyrim-engineering
description: Diagnose and engineer version-specific Skyrim Special Edition, Anniversary Edition, and Skyrim Together issues. Use for mod and plugin compatibility, load order and FormID analysis, Papyrus or crash diagnostics, SKSE ecosystem work, and safe build or release workflows.
---

# Skyrim Engineering

## Scope

Target Windows 11, Steam Skyrim Special Edition runtime `1.6.1170.0`, and a licensed complete Anniversary Creation Club library. Support SE/AE engineering and Skyrim Together Reborn. Exclude lore, walkthroughs, cheats, console commands, VR, Game Pass, Epic, GOG, consoles, and post-Anniversary Verified Creations.

Treat the game tree, mods, saves, logs, dumps, manifests, and diagnostic archives as private. Inspect in place. Never commit or redistribute Bethesda assets, third-party packages, binaries, PEX files, saves, dumps, credentials, Steam IDs, network addresses, usernames, or personal absolute paths.

## Route first

Load the one reference that owns the task before investigating:

| Task surface | Load |
|---|---|
| Runtime, SKSE, Address Library, Creation Kit, xEdit, Papyrus, or tool-version relationships | [references/ecosystem.md](references/ecosystem.md) |
| Plugin structure, masters, load order, records, overrides, ESL/light plugins, or FormID mapping | [references/plugins-and-formids.md](references/plugins-and-formids.md) |
| Crash, hang, Papyrus error, log, dump, desync evidence, or reproducibility triage | [references/diagnostics.md](references/diagnostics.md) |
| Skyrim Together architecture, synchronization, prior art, build surface, or upstream contribution | [references/together-reborn.md](references/together-reborn.md) |
| Anniversary catalogue, plugin identifier, licensed baseline, or Creation-level compatibility | [references/anniversary-creations.md](references/anniversary-creations.md) |
| Reproducible build, package provenance, licensing, release, or rollback | [references/build-and-release.md](references/build-and-release.md) |
| New, unstable, disputed, or superseded technical claim | [references/research-ledger.md](references/research-ledger.md) |

If a task crosses surfaces, start with the failing boundary, then load only the directly linked secondary reference. Do not preload all references.

## Integration-first workflow

1. **Discover versions.** Record store, `SkyrimSE.exe` product/file version, SKSE, Address Library, tool versions, Together commit/release, Creation state, plugin order, mod-manager profile, and whether the save is disposable.
2. **Preserve stock control.** Hash or inventory protected inputs without copying content. Never alter Bethesda plugins or edit saves.
3. **Create an isolated reproduction.** Use a disposable profile or original synthetic fixture; change one boundary at a time. Synthetic fixtures test tooling, never prove live game behavior.
4. **Minimize and sanitize evidence.** Retain the smallest useful steps, relative identifiers, versions, hashes, and excerpts. Remove private paths, account IDs, credentials, addresses, saves, and dumps.
5. **Separate Observation from Hypothesis.** State what the evidence directly shows, then the proposed explanation and the next falsifying check. Preserve conflicting evidence.
6. **Inspect prior art and upstream behavior.** Read official documentation, owning source, history, issues, tests, and licenses before designing a mechanism.
7. **Add focused tests.** Reproduce the defect in the smallest owning test surface before changing code. Record blocked live checks as `blocked` or `untested`, never PASS.
8. **Verify in stages.** For ordinary mods, validate parse/build then a disposable single-client run. For Together, progress through stock single-client, server connection, two-client, multi-client synchronization, reconnect, and save continuity.
9. **Package legally.** Include only original or legally redistributable work, with source provenance, versions, hashes where appropriate, notices, known limits, and rollback steps.
10. **Promote reviewed knowledge.** Move a reusable finding into its canonical reference only after evidence and an independent review; project-specific results stay with the project.

## Anniversary Together patch gate

Anniversary executable support is not proof that 74 Creation behaviors synchronize. For Anniversary Together work, inspect prior art and current upstream behavior, then **reproduce before patch** with matching runtime, content hashes, filenames, plugin classification, and load order. Demonstrate the defect in an unmodified upstream control and identify the owning integration boundary.

Patch Skyrim Together only for that reproduced compatibility defect. Extend the existing architecture; do not build a parallel replacement or pre-emptive compatibility layer. Keep derivatives in a separate GPL-3.0-or-later compliant fork and do not copy upstream source into this repository.

## Evidence response

Report exact versions and scope, sanitized Observation, Hypothesis, evidence and confidence, tests run, remaining uncertainty, and the next safe action. Do not claim compatibility from source inspection, a synthetic model, a successful build, or a single client alone.
