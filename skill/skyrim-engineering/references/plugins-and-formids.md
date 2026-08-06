# Plugins, load order, and FormIDs

Baseline: 2026-08-06. Use [xEdit 4.1.5f source](https://github.com/TES5Edit/TES5Edit/tree/xedit-4.1.5f) and the [Tome of xEdit](https://tes5edit.github.io/docs/) as the parser and conflict-analysis authorities. Work read-only until the defect and winning override are understood.

## Identity layers

- A standard runtime FormID is conventionally read as an 8-bit load index and a 24-bit object value.
- A light-plugin runtime FormID uses prefix `0xFE`, a 12-bit light index, and a 12-bit object value. The light index is local to a resolved load order; it is not a portable content identity.
- On-disk record identity, master-relative identity, and runtime identity are different contexts. Preserve the plugin filename, light/standard classification, master list, and load order with every reported ID.
- In Together, the upstream client maps a local FormID to `{server ModId, BaseId}` by filename/classification and reconstructs a receiver-local FormID. Different local indices can therefore refer to the same plugin record, but filename parity alone does not prove byte parity.

## Safe analysis sequence

1. Copy no licensed plugin into Git. Open the isolated profile in SSEEdit/xEdit with the exact active list.
2. Confirm masters and ESL/ESM/ESP flags; never infer plugin type from extension alone.
3. Locate the record by owning plugin plus local/object identity, then inspect the full override chain and winning override.
4. Distinguish an intended override from a conflict. Record the field path and source plugin without copying proprietary record payloads.
5. If a fix is warranted, create the smallest separate patch plugin. Never modify Bethesda or third-party masters, compact FormIDs casually, or change an ESL flag without proving reference safety.
6. Reload the patch in a fresh xEdit process, compare protected-input hashes, and exercise the user-visible behavior on a disposable save/profile.

## Versioned claims

| Claim | Source | Accessed | Applies to | Confidence | Reproduced |
|---|---|---|---|---|---|
| The pinned Together client separates standard and `0xFE` light-plugin indices and maps them through server mod IDs. | [TiltedEvolution `ModSystem.cpp` at `9d81ef07`](https://github.com/tiltedphoques/TiltedEvolution/blob/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/Code/client/Systems/ModSystem.cpp) | 2026-08-06 | That commit's Skyrim client | High | Yes; source path inspected, runtime multiplayer untested |
| xEdit `4.1.5f` is the pinned parser/definition baseline for this skill. | [Maintainer release](https://github.com/TES5Edit/TES5Edit/releases/tag/xedit-4.1.5f) | 2026-08-06 | SSE mode `4.1.5f` | High | Yes; historical read-only tool run, live patch round trip still blocked |
