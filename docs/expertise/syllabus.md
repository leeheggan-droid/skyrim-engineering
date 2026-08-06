# Skyrim engineering expertise syllabus

Version: 1.0-review-pending
Evidence date: 2026-08-06
Target: Steam Skyrim Special Edition executable `1.6.1170.0` on Windows 11 and TiltedEvolution `dev` commit `9d81ef07d68e4bb2bd94fca246e798a564b7fb92`

## Evidence rules

Each claim is bounded to the versions above unless its source states a wider range. Direct observation and source code outrank maintainer documentation; maintainer documentation outranks community material. Community material can identify leads but cannot satisfy the primary-source minimum. Licensed game, Creation, mod, save, and dump data stays outside this repository. Observations, hypotheses, reproductions, and fixes are labelled separately.

## Domain syllabus

### Data model

- TES4 plugin headers, HEDR metadata, MAST/DATA master lists, record/subrecord structure, groups, flags, EditorIDs, FormIDs, references, overrides, injected records, and winning-override semantics.
- Master-relative IDs versus runtime load-order IDs. Standard runtime IDs use an 8-bit load index plus a 24-bit object ID. Light-plugin runtime IDs use `FE` plus a 12-bit light index and 12-bit object ID.
- ESM/ESP/ESL filename extensions versus header flags; ESL flagging, object-ID limits, compaction hazards, dependent-plugin breakage, and the rule that existing IDs are never compacted casually.
- Loose assets, BSA archives, script source/bytecode, voice paths, and localized string tables. A plugin alone is not necessarily a complete mod.

Version boundary: the `0xFE` treatment is verified here against TiltedEvolution's Skyrim SE path at the pinned commit and is intended for the installed `1.6.1170.0` runtime. It is not asserted for Skyrim VR, GOG, Epic, Game Pass, or future runtimes.

### Creation Kit and game design

- Active file/master selection, object window, render window, cell/worldspace construction, object placement, actor bases and references, inventory, AI packages, navmesh creation/finalization, quests, aliases, dialogue views/topics, stages/objectives, and Papyrus attachment.
- Design checks: unique namespace, smallest necessary override surface, deterministic quest state, alias fill behavior, dialogue conditions, package interruption, navmesh ownership, persistence, and rollback.
- Packaging checks: plugin, scripts, voice, meshes, textures, localization, archives, provenance, and clean-room/original-content boundary.

Version boundary: Steam Creation Kit app `1946180` for Skyrim Special Edition is the required practical tool. No Creation Kit practical is accepted from the older Legendary Edition tool.

### xEdit

- Read-only loading; plugin header, masters, flags, VMAD/script metadata, archives and asset-name inspection; conflict colouring and override chains; referenced-by navigation; filtering and error checks.
- Cleaning is a separate, version-sensitive workflow. Never save while inspecting and never clean Bethesda or third-party files from assumptions. A safe patch copies only intended winning records into a new original plugin, adds required masters, checks errors, and is re-opened for verification.
- xEdit scripting is evaluated on a synthetic fixture with bounded output and no writes outside an isolated working directory.

Version boundary: use the maintainer's current xEdit/SSEEdit release acquired from the canonical repository, record its exact version and hash, and do not substitute obsolete pre-4.0 cleaning instructions.

### Papyrus

- Script/object model, properties, events, functions, states, latent calls, compiler inputs/outputs, logs, runtime errors, VM scheduling, persistence, save serialization, script attachment and fragment generation.
- A compile success is not runtime proof. The practical must compile original source, deliberately produce a safe compiler error, inspect compiler and runtime logs, then explain how persistent references and changed script state can survive in a save.

Version boundary: compiler, flags, import paths, and base sources must come from the Steam SE Creation Kit matching the installed environment.

### Runtime extensibility

- SKSE loader/runtime matching, plugin query/load boundaries, native ABI risk, relocation/address databases, hooks, serialization, messaging, Papyrus registration, and update breakage.
- Address Library reduces hard-coded-address coupling but does not eliminate ABI, data-layout, calling-convention, or game-behavior risk. Every DLL and database must explicitly support `1.6.1170.0`.

### Diagnostics

- Establish exact runtime and load order first; preserve originals; reproduce in an isolated profile; collect plugin list, missing-master evidence, Papyrus logs, crash log/minidump, symbols and STR logs; separate observation from hypothesis.
- Crash triage: exception/thread/module, call stack quality, probable plugin ownership, reproduction, symbol limitations, and a minimally scoped fix. Plugin-parity and desynchronization triage compare manifests, hashes, order, settings, server version, ownership, packet path, and reproduction timing.
- Save analysis is read-only and privacy-sensitive. A save or dump is never committed unless irreversibly sanitized and legally safe.

### Packaging and legal safety

- Release only original code/content or material whose licence permits redistribution. Record file hashes, provenance, licence, supported runtime/tool versions, build inputs, install destination, rollback, and known limitations.
- Never redistribute Bethesda game/Creation assets, Nexus binaries without permission, secrets, personal paths, Steam identifiers, saves, or raw dumps. Preserve GPL-compatible source and notices for TiltedEvolution derivatives in a separate GPLv3-compliant fork.

### Skyrim Together architecture and build

- Mod-list negotiation maps client load indices to server-stable `GameId { ModId, BaseId }`; standard and lite IDs are reconstructed per client.
- Actor ownership and server entities; character spawn/state; inventory capture, server component update and range broadcast; quest event capture, server party log and remote application; encoding/message factories; serialization boundaries.
- Build path: recursive submodules, VS2022 Community with Desktop and Game development C++ workloads, xmake, Node.js and pnpm, `releasedbg` for a debuggable client, install to an isolated `distrib`, then UI deployment. Current CI pins xmake `3.0.9`.
- Contribution path: reproduce on pinned source, add focused tests, format, verify server and client, exercise multi-client reconnect/save continuity, preserve GPLv3 obligations, and submit a narrow upstream change.

Version boundary: architecture statements are source traces at `9d81ef07…`; the upstream build guide may lag current CI, so repository workflow files control exact pins.

## Gate state

The data-model cases, Papyrus compile/error exercise, exact isolated runtime selection, matching-symbol diagnosis, and pinned Together configure/build/install/tests were executed. The earlier CK fixture is not original-only, the xEdit replay is not freshly frozen, no Papyrus runtime-save exercise exists, and the desync script is not production evidence. The assessment is 76/100 with blocked domains. This evidence and its score govern Task 10 and `v1.0 qualified`, not construction of the `v0.1 provisional` skill. Live-track status remains explicit in [`qualification/state.json`](../../qualification/state.json).
