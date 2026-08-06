# Skyrim Together Reborn engineering

Baseline: 2026-08-06. Primary target: [TiltedEvolution](https://github.com/tiltedphoques/TiltedEvolution/tree/9d81ef07d68e4bb2bd94fca246e798a564b7fb92) `dev` commit `9d81ef07d68e4bb2bd94fca246e798a564b7fb92`. Its GPL-3.0-or-later [license](https://github.com/tiltedphoques/TiltedEvolution/blob/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/LICENSE) governs derivatives; keep any fork separate from this skill repository.

## Owning architecture

The client captures game events, converts local plugin/FormID identity through `ModSystem`, sends typed messages, and applies remote updates under feedback-suppression guards. The server owns entities, party/range routing, accepted snapshots, and service-specific state, while owning clients still drive substantial game-engine state. Inspect the specific client service, message encoder/decoder, server service/component, and tests together; never infer full synchronization from one layer.

Useful upstream anchors:

- [`ModSystem.cpp`](https://github.com/tiltedphoques/TiltedEvolution/blob/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/Code/client/Systems/ModSystem.cpp) for standard/light plugin mapping;
- [`Code/client/Services/Generic`](https://github.com/tiltedphoques/TiltedEvolution/tree/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/Code/client/Services/Generic) and [`Code/server/Services`](https://github.com/tiltedphoques/TiltedEvolution/tree/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/Code/server/Services) for end-to-end ownership;
- [Windows CI](https://github.com/tiltedphoques/TiltedEvolution/blob/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/.github/workflows/windows.yml), the [maintainer build guide](https://wiki.tiltedphoques.com/tilted-online/technical-documentation/build-guide), and repository tests for build/test truth.

## Anniversary Together gate

Inspect upstream behavior, issues/history, tests, and prior art first. Establish identical runtime, Creation/plugin filenames, light/standard classification, content hashes, load order, Together build, and disposable characters. Run stock single-client, connection, two-client, then three-client cases for inventory, combat, quests, world objects, homes/pets/horses, Survival, death, reconnect, and save continuity.

**Reproduce before patch.** A demonstrated unmodified-upstream failure must identify an owning integration boundary and a falsifiable expected result. Add the smallest focused test, extend the existing architecture, and rerun staged clients. Do not build a parallel replacement or an unproven Anniversary compatibility layer. A successful build, synthetic model, or source trace does not prove multiplayer behavior.

## Architectural prior art: SkyMP

[SkyMP](https://github.com/skyrim-multiplayer/skymp/tree/d85f18d808f877401c4e20484d2c2f6f73cf9caa) at commit `d85f18d808f877401c4e20484d2c2f6f73cf9caa` is useful architectural prior art, not the selected replacement. Relevant upstream surfaces include [`libespm`](https://github.com/skyrim-multiplayer/skymp/tree/d85f18d808f877401c4e20484d2c2f6f73cf9caa/libespm) for plugin parsing, [`skymp5-server`](https://github.com/skyrim-multiplayer/skymp/tree/d85f18d808f877401c4e20484d2c2f6f73cf9caa/skymp5-server) for server-managed world state and persistence, [`papyrus-vm`](https://github.com/skyrim-multiplayer/skymp/tree/d85f18d808f877401c4e20484d2c2f6f73cf9caa/papyrus-vm), the TypeScript/C++ server boundary, [`unit`](https://github.com/skyrim-multiplayer/skymp/tree/d85f18d808f877401c4e20484d2c2f6f73cf9caa/unit) synchronization tests, and [`skyrim-platform`](https://github.com/skyrim-multiplayer/skymp/tree/d85f18d808f877401c4e20484d2c2f6f73cf9caa/skyrim-platform). Its persistent-server/MMO-oriented architecture differs materially from Skyrim Together's family co-op ownership and relay model, so reuse ideas only after validating the local boundary.

SkyMP's [terms](https://github.com/skyrim-multiplayer/skymp/blob/d85f18d808f877401c4e20484d2c2f6f73cf9caa/TERMS.md) say the repository is primarily GPLv3/AGPLv3 and that subprojects carry their own licenses. Inspect the exact subproject license and third-party notices before reuse; do not copy source into this repository.

## High-priority experimental prior art: SkyrimCoop

[`blockheads/SkyrimCoop`](https://github.com/blockheads/SkyrimCoop/tree/6a0c293a97892f83be0672c1ac4a9e0487a19503) default branch `dev`, observed head `6a0c293a97892f83be0672c1ac4a9e0487a19503` (2026-03-28), is a TiltedEvolution fork exploring a host-based peer-to-peer/listen-server model. Its [README](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/README.md) calls it a work in progress and describes the host as owner of NPCs/world state, loaded cells, quest progression, and combat decisions. [`HostService.h`](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/Code/client/Services/HostService.h) embeds `GameServer` in the host client, while [`Code/client/xmake.lua`](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/Code/client/xmake.lua) explicitly adds the server include path and `SkyrimTogetherServer` dependency.

This makes the fork high-priority prior art for host-owned NPC/world/quest synchronization and embedded-server design. It has no proven release or Anniversary validation in the evidence reviewed here. Do not recommend adoption until a clean pinned build, focused and upstream tests, and a code-delta audit against its TiltedEvolution base establish what is implemented rather than planned. Treat README/headers as design evidence, not runtime proof. Its pinned [license](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/LICENSE) is GPL-3.0-or-later with a noted LGPLv2 launcher component; inspect inherited notices before any reuse and never copy code into this repository.

## Versioned claims

| Claim | Source | Accessed | Applies to | Confidence | Reproduced |
|---|---|---|---|---|---|
| TiltedEvolution maps client-local standard/light FormIDs through server mod identity and receiver-local mapping. | [`ModSystem.cpp` at `9d81ef07`](https://github.com/tiltedphoques/TiltedEvolution/blob/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/Code/client/Systems/ModSystem.cpp) | 2026-08-06 | Pinned commit only | High | Yes; source inspected, production multi-client run untested |
| SkyMP exposes the listed parsing, server, VM, TypeScript/C++, test, and Skyrim Platform surfaces and is primarily GPLv3/AGPLv3 with per-subproject terms. | [Pinned tree](https://github.com/skyrim-multiplayer/skymp/tree/d85f18d808f877401c4e20484d2c2f6f73cf9caa) and [terms](https://github.com/skyrim-multiplayer/skymp/blob/d85f18d808f877401c4e20484d2c2f6f73cf9caa/TERMS.md) | 2026-08-06 | SkyMP commit `d85f18d8`; architectural comparison only | High | Yes; source-tree inspection, not runtime evaluation |
| SkyrimCoop declares a host-based embedded-server fork and exposes `HostService`, but remains early experimental prior art. | [Pinned README](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/README.md), [`HostService.h`](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/Code/client/Services/HostService.h), and [license](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/LICENSE) | 2026-08-06 | Commit `6a0c293a`; design/code inspection only | Medium | Partial; source surfaces observed, clean build/tests and runtime unverified |
