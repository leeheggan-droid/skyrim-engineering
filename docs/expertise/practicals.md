# Hands-on practical record

Evidence date: 2026-08-06. Status values are `PASS` only for directly executed, reproducible work; `BLOCKED` means required evidence could not be produced. The accepted CK V3 and runtime practicals ran entirely under `C:\tmp`; no pre-existing game file was changed.

## 1. FormID decode and mapping — PASS (synthetic only)

Executed with Windows PowerShell 5.1 using literal, hand-checkable values:

```powershell
$resolved = (0x2A -shl 24) -bor 0x00C123
'0x{0:X8} 0x{1:X2} 0x{2:X6}' -f $resolved,(($resolved -shr 24) -band 0xFF),($resolved -band 0xFFFFFF)
$resolved = 0xFE000000 -bor (0x123 -shl 12) -bor 0xABC
'0x{0:X8} 0x{1:X3} 0x{2:X3}' -f $resolved,(($resolved -shr 12) -band 0xFFF),($resolved -band 0xFFF)
```

Sanitized output:

```text
standard: 0x2A00C123 -> load 0x2A, object 0x00C123 -> 0x2A00C123
light:    0xFE123ABC -> light 0x123, object 0xABC -> 0xFE123ABC
master-relative example: file 0x01000123, master runtime slot 0x05 -> runtime 0x05000123
```

The master-relative example means the source plugin's master-table index `01` identifies a master record with object portion `000123`; when that master occupies runtime load index `05`, the resolved ID is `05000123`. This does not infer the current game's actual load order.

## 2. Read-only xEdit inspection — PASS (bounded sub-practical)

xEdit `4.1.5f` (`xTESEdit64.exe` SHA-256 `659FADDD8DC061A9D2EDDD20DE925821B87E377284CE179F4538FF78BB2420CD`) ran the original [read-only script](../../tests/fixtures/xedit/InspectReadOnly.pas) against an isolated Data directory and two-master custom profile. The retained [fresh replay](../../tests/fixtures/xedit/fresh-replay.json) records every argument and the Windows UI Automation action on the exact module-selection OK control; raw [cache-build](../../tests/fixtures/xedit/first-pass-inspection.txt) and [cached-pass](../../tests/fixtures/xedit/second-pass-inspection.txt) outputs are preserved.

Observed facts: both `Skyrim.esm` and `Update.esm` have `TES4` headers, header flags `10000001`, and header version `1.71`; `Update.esm` names `Skyrim.esm` as a master; `GMST:000D4D01` originates in `Skyrim.esm` and wins from `Update.esm`; and a quest VMAD sample exposes two scripts. Raw `modified-file-count` is `3` during cache construction and `2` on the cached pass. This is xEdit's in-memory `esModified` load-normalization state, not a disk-write count. The authoritative external disk hash delta is zero: `Skyrim.esm` remained `2BBC77FD…6107` and `Update.esm` remained `C1795E0A…ED9`. No save was requested. The maintained script labels future output `in-memory-normalized-file-count`. Missing-master behavior and a real minimal patch save/reopen remain unexecuted, so the xEdit domain stays below threshold at 7/10.

## 3. Original Creation Kit plugin — BLOCKED (historical invalid check only)

The earlier 1,643-byte V3 fixture copied a Bethesda sandbox `PACK`; it is not an original-only or distributable practical. The retained generator now creates a blank original package shell, but that replacement has not completed a CK configuration/save/reopen/xDump round-trip. The earlier check hash remains diagnostic history only and earns no replacement-package credit.

Creation Kit `1.6.1378.1` loaded `SEG_CK_Practical3.esp` as the active file in a disposable root with enabled Object/Cell/Render windows. In the original quest, the practical added stage `10` and attached the already compiler-proven `SEG_ValidEvent` script, then saved. The first save changed the hash to `1FE479CBC41C2D6D15E312AF1656B400FDFBE9FCF7C1DF2FC33618DDA9BDB06F`. On the required full reopen, `xDump64 -check` exposed an empty CK-created player-dialogue branch with a null starting topic. That observed save artifact was removed in the same reopened CK round trip and saved again; the final 1,899-byte plugin SHA-256 is `84B371725A3F7940A39536DBFA91F7F876A04C16129C881217052EBD1CD441B7`.

Final independent checks passed: `xDump64 -check` exited `0` with zero record-error hits; `xDump64 -dump` showed QUST VMAD `SEG_ValidEvent`, script name `SEG_ValidEvent`, stage index `10`, and no `SEG_ExpertiseQuestNewBranch0`. The save warning was the inherited Bethesda `MaleHead.nif` tint-map warning, distinct from fixture record integrity. Seventy-eight licensed master/plugin copies (112,763,251 bytes) used only in the disposable root were deleted after validation and are recoverable from the installed licensed source. No generated plugin, PEX, or Bethesda content is committed.

## 4. Papyrus compile, logs and safe error — BLOCKED (compiler sub-practical passes)

The Steam CK compiler used the matching extracted `TESV_Papyrus_Flags.flg` and base-source import directory plus the committed fixture directory. The valid [SEG_ValidEvent.psc](../../tests/fixtures/papyrus/SEG_ValidEvent.psc) compiled with `0 error(s), 0 warning(s)`, `Assembly succeeded`, and exit `0`. The deliberate type mismatch in [SEG_InvalidEvent.psc](../../tests/fixtures/papyrus/SEG_InvalidEvent.psc) failed at line 4, column 8 with `type mismatch while assigning to a int`, and exit `-1`. Generated PEX and licensed base sources stayed under `C:\tmp`.

Compilation proves syntax and imports, not runtime correctness. Existing script instances, properties and state may already be serialized in saves; replacing PEX does not reset those instances. Tests therefore use a disposable profile/save, avoid removing persistent properties from an installed save, and treat a migration or clean-save requirement as an explicit compatibility decision.

## 4a. Exact isolated runtime compatibility — PASS

The user-supplied Address Library version `11` archive SHA-256 is `D345CCDAC52C096FE9628A62FF3764BBF23111BA30E3D282CD3B1FB66968863A`. It was extracted only under `C:\tmp`. The exact primary runtime database is `versionlib-1-6-1170-0.bin`, SHA-256 `C4093C569A3C83B26587F4B9EA4C55DE9AE6E73B84A2AF9FB3FBD30E2FE0D452`; the alternate is `versionlib-1-6-1170-0-1.bin`, SHA-256 `AC6D17E8A4BB4DA2539E7A571113BCB28AE5ADF4874CD977332F1A5215F65C07`.

The original [isolated runtime verifier](../../tests/fixtures/runtime/Test-IsolatedRuntimeCompatibility.ps1) reads the installed executable's exact `1.6.1170.0` file version, requires SKSE build `2.2.6`, resolves only the corresponding database filenames, and refuses staging outside `C:\tmp`. A mismatch probe for `1.6.1179.0` was rejected with exit `2`; the exact `1.6.1170.0`/SKSE `2.2.6` case was accepted with exit `0`. The source SKSE DLL SHA-256 was `C9A2C8A80DF6BF2372C5F49468BB2E5AB67786157265B6F29ECE9F4EAC075D54`; only the two Address Library databases were copied. This proves selection/rejection and rollback boundaries, not DLL staging, game launch, or ABI compatibility.

## 5. Together actor/inventory/quest/lite traces — PASS (source trace only)

Executed commands:

```text
git -C C:\tmp\TiltedEvolution-audit rev-parse HEAD
rg -n "FormId|AddLite|RequestInventoryChanges|NotifyInventoryChanges|RequestQuestUpdate|NotifyQuestUpdate|AssignCharacterRequest|CharacterSpawnRequest" Code
```

Commit output was `9d81ef07d68e4bb2bd94fca246e798a564b7fb92`. Exact client capture, `GameId` encoding, server state/ownership, and remote application functions are recorded in [architecture-traces.md](architecture-traces.md). This passes the source-trace practical but does not substitute for build/runtime tests.

## 6. Current TiltedEvolution isolated build — PASS after fixture-target repair

At commit `9d81ef07d68e4bb2bd94fca246e798a564b7fb92`, required submodules were initialized. With xmake `3.0.9` and VS2022 Community `17.14.37`, a fresh `xmake -y` returned `build ok`, and `xmake install -o distrib` returned `install ok`.

The initial reverse test crashed. CDB loaded the matching private PDB and identified a null execute from `Code/tests/src/reverse.cpp:39`: release mode loads `DLL_r.dll`, but the current xmake migration omitted the legacy fixture DLL target and the test dereferenced the resulting null exports. In the isolated GPL checkout, a minimal patch added that shared-library target/dependency and explicit module/export assertions. Fresh installed-suite output was:

```text
distrib\bin\TPTests.exe
All tests passed (28 assertions in 5 test cases)
EXIT=0

distrib\bin\TiltedReverse_Tests.exe
All tests passed (9 assertions in 2 test cases)
EXIT=0
```

Build, install and both relevant installed suites are proven. The isolated upstream patch is not committed or packaged here; binaries and third-party source remain outside this repository.

## 7. Diagnostic triage — PASS

Four synthetic, non-personal snippets were reviewed. Matching-symbol CDB output for the real reverse-test access violation separates the observed null execute from the missing-DLL root cause. The [executable desync fixture](../../tests/fixtures/together/Test-DesyncEdge.ps1) is an independently authored model of selected source semantics. It does not exercise production messages, transport, activation routes, clients, or server and receives zero production-edge credit.

| Fixture | Observation | Hypothesis | Reproduction needed | Fix decision |
|---|---|---|---|---|
| Crash | CDB reports `0xc0000005`, execute address zero, matching private PDB, and `TiltedReverse_Tests!C_A_T_C_H_T_E_S_T_0+0x141` at `reverse.cpp:39` | The missing release fixture DLL makes the unchecked export pointer null | Rebuild once with the DLL target absent and once present, retaining hashes/symbol match | Add the omitted xmake target/dependency and fail explicitly on missing module/export; fresh 9/9 assertions pass |
| Plugin parity | Client A manifest has `LiteQuest.esl` SHA-256 `A…`; client B lacks the entry | Connection or FormID mapping can diverge due to missing content | Rebuild sanitized manifests from all clients and compare filename, light flag, hash and order | Restore the authorized identical package/profile, then retest; do not copy paid content through Git |
| Missing master | Loader fixture states `Patch.esp` requires absent `RequiredMaster.esm` | Load cannot be valid; downstream records may be unresolved | Confirm TES4 MAST list in read-only xEdit and mod-manager deployment | Install the entitled exact master or disable the dependent patch; never remove MAST blindly |
| Desynchronization | Executable fixture shows owner request and server `InventoryComponent` mutation while `UpdateClients=false` emits zero notifications and leaves the remote count unchanged | The first reproduced missing edge is server-to-remote `NotifyInventoryChanges`, caused by the explicit early return rather than item-record corruption | The paired `UpdateClients=true` case sends exactly once to the in-range remote, excludes the sender and reaches remote `AddOrRemoveItem`; both cases assert exact sequence and counts | Inspect why the capture site set the flag false and change only that proven call path if remote visibility is required; retain the server gate, then retest out-of-range, sender exclusion, reconnect/full snapshot and save continuity |

Fresh executable output ended `RESULT=PASS cases=2 first-missing-edge=server-to-remote` and exit `0`. The fixture hash `A…` is deliberately synthetic notation inside a diagnostic example, not a release checksum.

## 8. Legally safe release manifest — PASS

The ordered, exact current-byte file set is in [release-manifest.json](../../tests/fixtures/package/release-manifest.json). It selects GPL-3.0-or-later, records every file's byte length and SHA-256, and excludes only its two self-referential control manifests. [Test-EvidenceManifest.ps1](../../tests/fixtures/package/Test-EvidenceManifest.ps1) proves source hashes, exact-set equality, isolated staging, staged hashes, mismatch quarantine, and scoped rollback. No game, mod, save, dump, executable, plugin, archive, PEX, or third-party source is in the set.

## Practical summary

| Practical | Status |
|---|---|
| FormID round trip | PASS |
| xEdit inspection | PASS — bounded read-only replay; domain still lacks patch/reopen |
| Creation Kit fixture | BLOCKED — original GUI practical absent |
| Papyrus compile/error/log | BLOCKED — compiler passes; runtime/save-load absent |
| Together source trace | PASS |
| Together build | PASS |
| Tool-backed diagnostic triage | BLOCKED — production runtime edge remains unobserved |
| Original release manifest | PASS |

Portable and compiler sub-practicals have direct evidence. The xEdit replay,
original CK work, Papyrus save/load runtime, production desync edge, and
independent approvals remain automatic blockers for Task 10 and `v1.0
qualified`. They do not block Tasks 1-8 or the safe `v0.1 provisional`
capability; their live status is recorded in
[`qualification/state.json`](../../qualification/state.json).
