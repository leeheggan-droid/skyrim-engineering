# TiltedEvolution architecture traces

Trace target: isolated checkout at branch `dev`, commit `9d81ef07d68e4bb2bd94fca246e798a564b7fb92`, with required submodules initialized.
Method: read-only source inspection plus isolated configure/build/install/test. Runtime game behavior is not claimed from source inspection or unit tests alone.

## Identity and mod mapping

The server does not transmit a client's raw load-order FormID as a universal identity.

1. `Code/server/GameServer.cpp`, authentication/mod-list handling, iterates the client's `UserMods.ModList`. It calls `ModsComponent::AddLite(filename)` or `AddStandard(filename)`, returns a server-stable entry ID, preserves `IsLite`, and records each player's server mod IDs.
2. `Code/server/Components/ModsComponent.cpp::{AddLite,AddStandard}` de-duplicates by filename and assigns from one seed. Thus the server identity is filename-derived within that running server, not the client's local load slot.
3. `Code/client/Systems/ModSystem.cpp::HandleMods` resolves each server entry to the local `ModManager` entry by filename. It builds server-to-game, lite-to-server and standard-to-server maps.
4. `ModSystem::GetServerModId` decomposes a normal ID into high-byte local index plus 24-bit base. For `0xFE` it extracts `liteId = (id & 0x00FFF000) >> 12` and `BaseId = id & 0xFFF`.
5. `ModSystem::GetGameId` performs the inverse: light IDs become `0xFE000000 | (localLiteId << 12) | (BaseId & 0xFFF)`; standard IDs become `(localIndex << 24) | (BaseId & 0xFFFFFF)`.
6. `Code/encoding/Structs/GameId.cpp::{Serialize,Deserialize}` writes `BaseId` then `ModId` as variable integers. This field order matters when diagnosing packet captures.

Consequence: two clients can use different local load indices yet resolve the same server `GameId` if filenames and light/standard classification match. Filename parity alone does not establish byte/content parity; that is why the applied project also requires hashes and order manifests.

## Representative lite-plugin FormID

For runtime ID `0xFE123ABC`, client capture in `GetServerModId` observes prefix `FE`, local light index `0x123`, and base `0xABC`. `m_liteToServer[0x123]` supplies the server mod ID; `{serverModId, 0xABC}` is serialized. On the receiver, `m_serverToGame[serverModId]` supplies that receiver's local light index, and `GetGameId` reconstructs its local `FE…` ID. A missing filename mapping makes reconstruction return zero and callers generally log a missing-mod/form error.

## Actor capture, ownership, state and remote application

1. `Code/client/Services/Generic/CharacterService.cpp::RequestServerAssignment` starts from a local entity's `FormIdComponent`, resolves the actor reference, cell, optional worldspace and base NPC through `ModSystem::GetServerModId`, captures position/rotation and actor state, then sends `AssignCharacterRequest`.
2. `Code/encoding/Messages/AssignCharacterRequest.cpp` is the wire encoder; `ClientMessageFactory.h` registers its opcode.
3. `Code/server/Services/CharacterService.cpp::OnAssignCharacterRequest` searches server entities by `FormIdComponent`. An existing entity returns ownership/state or transfers ownership under party rules; otherwise it calls `CreateCharacter`.
4. `CreateCharacter` creates the server entity and attaches `OwnerComponent`, `CellIdComponent`, `CharacterComponent`, `InventoryComponent`, `ActorValuesComponent`, `MovementComponent` and `AnimationComponent`. This makes the server authoritative store/relay for the accepted snapshot while an owning client drives relevant updates.
5. `CharacterService::Serialize` copies server components into `CharacterSpawnRequest`; `ServerMessageFactory.h` registers the message.
6. `Code/client/Services/Generic/CharacterService.cpp::OnCharacterSpawn` uses `ModSystem::GetGameId` to resolve the remote form/base, reuses or creates the local entity/actor, moves it, applies actor values and marks it remote. Missing mappings are logged and the actor is not spawned.

Ownership is not absolute server simulation: source paths show server components and enforcement/transfer decisions, while clients capture and apply much game-engine state. This distinction must be tested under disconnect, transfer and reconnect.

## Inventory item flow

1. Skyrim hooks in `Code/client/Games/Skyrim/{TESObjectREFR,PlayerCharacter,Actor}.cpp` trigger `InventoryChangeEvent` with a target form and an `Inventory::Entry` whose base item identity is a `GameId`.
2. `Code/client/Services/Generic/InventoryService.cpp::OnInventoryChangeEvent` locates the synchronized entity, obtains its server entity ID, and sends `RequestInventoryChanges { ServerId, Item, Drop, UpdateClients }`.
3. `Code/encoding/Messages/RequestInventoryChanges.cpp` serializes the server entity ID, inventory entry and booleans; `ClientMessageFactory.h` registers it.
4. `Code/server/Services/InventoryService.cpp::OnInventoryChanges` updates the entity's `InventoryComponent.Content`. If `UpdateClients` is false it stops; otherwise it emits `NotifyInventoryChanges` to players in range, excluding the sender. Item-drop propagation is gated by server setting `Gameplay:bEnableItemDrops` and defaults off at this commit.
5. `Code/client/Services/Generic/InventoryService.cpp::OnNotifyInventoryChanges` finds the actor/object by server ID, enters `ScopedInventoryOverride` to prevent feedback capture, then calls `DropOrPickUpObject` or `AddOrRemoveItem`.

## Quest-stage flow

1. `Code/client/Services/Generic/QuestService.cpp` registers for `TESQuestStartStopEvent` and `TESQuestStageEvent`. It ignores events during `ScopedQuestOverride` or outside a party and rejects `IsNonSyncableQuest` entries.
2. `QuestService::OnEvent(TESQuestStageEvent…)` resolves the quest through `ModSystem::GetServerModId`, captures the 16-bit stage, status `StageUpdate`, and client quest type, then sends `RequestQuestUpdate`.
3. `Code/encoding/Messages/RequestQuestUpdate.cpp` serializes `GameId`, 16-bit stage, 8-bit status and 8-bit quest type; `ClientMessageFactory.h` registers it.
4. `Code/server/Services/QuestService.cpp::OnQuestChanges` stores/removes the entry in the sending player's `QuestLogComponent`, normalizes notification status, and sends `NotifyQuestUpdate` to the party excluding the sender.
5. At this commit, types None and Miscellaneous return early unless experimental server setting `Gameplay:bEnableMiscQuestSync` is enabled; it defaults false. This is an explicit behavior boundary, not general quest compatibility.
6. `Code/client/Services/Generic/QuestService.cpp::OnQuestUpdate` reconstructs the local quest ID, finds `TESQuest`, then calls `ScriptSetStage`, `SetActive`, or `StopQuest`. Remote overrides avoid recapturing the same change.

Quest scripts, aliases, scenes, objectives and externally visible world effects are not serialized merely because a stage number is. Creation compatibility therefore requires scenario-level three-client tests, not a source-level claim.

## Build and contribution trace

- Root `README.md` points to the maintainer build guide; `Build.bat` runs `xmake project`, configures `releasedbg`, builds, installs, and builds the UI.
- `.github/workflows/windows.yml` checks out full history, initializes recursive submodules, pins xmake `3.0.9`, configures `x64`, runs `xmake -y`, and installs to `distrib`.
- The guide requires VS2022 Community with Desktop and Game development C++ workloads, xmake, Node.js, pnpm, a path without spaces, and Address Library to launch the game instance. It says debug client builds are unsupported; use `releasedbg`.
- `Code/tests/encoding.cpp` provides protocol/round-trip test surfaces; changes should add focused coverage there or alongside the owning service. `CODE_GUIDELINES.md` and `.clang-format` control contribution style.
- A derivative or distributed binary must comply with the root GPL-3.0-or-later licence and provide corresponding source as applicable.

The pinned checkout configured, built and installed with xmake `3.0.9` and VS2022 `17.14.37`. `TPTests` passed 28/28 assertions. Matching-symbol CDB diagnosis showed `TiltedReverse_Tests` executed a null export because its release fixture `DLL_r.dll` was never built by the migrated xmake file. An isolated patch added the omitted shared-library target/dependency and null assertions; the fresh reverse suite passed 9/9 assertions. See [practicals.md](practicals.md). This proves the build/unit-test boundary, not multiplayer runtime behavior.

The separate [executable desync fixture](../../tests/fixtures/together/Test-DesyncEdge.ps1) exercises an independently authored model only. Its cases assert modeled mutation, gating, sender exclusion and modeled remote application, but do not exercise production activation, messages, transport, client/server processes, or prove a real absent edge. Production desync credit remains zero.

Address Library maps version-specific identifiers to addresses; it reduces hard-coded address coupling. It does not validate C++ ABI, structure layout, calling convention, ownership/lifetime, thread safety, hook ordering, or behavioral compatibility after a game update. The pinned SKSE loader's structure-compatibility checks and exact database lookup are traced in `tests/fixtures/runtime/skse-source-trace.txt`; every native plugin still needs exact-runtime testing.
