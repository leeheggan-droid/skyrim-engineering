# Local toolchain audit

Audit date: 2026-08-06
Method: command discovery, registry and Steam manifest/file metadata inspection, package hashes, Defender state, and isolated build/tool execution. A resumed audit installed only official or maintainer packages. The final V3 Creation Kit round trip and runtime compatibility proof ran entirely under `C:\tmp`; no Bethesda or user-authored live-game file was edited.

Readiness values are `ready`, `missing-free`, `missing-user-supplied`, `not-required-v1`, and `blocked`.

| Tool / content | Observed version | Sanitized discovery path | Licence | Canonical source | Purpose | Readiness | Evidence / boundary |
|---|---|---|---|---|---|---|---|
| Steam Skyrim SE/AE | `SkyrimSE.exe 1.6.1170.0`; Steam build `13189953` | `%PROGRAMFILES(X86)%\Steam\steamapps\common\Skyrim Special Edition` | Proprietary Bethesda/Steam terms | [Steam app 489830](https://store.steampowered.com/app/489830/) | Reference runtime and licensed data | ready | Steam manifest state `4`; executable company Bethesda Softworks. Creation ownership/catalogue was not copied or committed. |
| Creation Kit SE | `1.6.1378.1`; Steam build `16333628` | `%PROGRAMFILES(X86)%\Steam\steamapps\common\Skyrim Special Edition\CreationKit.exe` | Proprietary; free tool with third-party EULA | [Steam app 1946180](https://store.steampowered.com/app/1946180/) | Original plugin, dialogue, quest, actor, package, cell/navmesh and Papyrus practicals | blocked | SHA-256 `3E8F7215303A82D8991F87FBC42EB84EF2672D5D8AB038212447FAECFDF37B23`; manifest state `4`. The checked V3 contains a Bethesda-derived PACK and lacks alias, objective, condition, navmesh and a replacement CK round-trip; it is diagnostic history, not a completed original practical. |
| xEdit / SSEEdit | `4.1.5f` | `C:\Tools\xEdit-4.1.5f` | MPL-2.0 | [TES5Edit repository/releases](https://github.com/TES5Edit/TES5Edit/releases) | Read-only plugin/conflict inspection and fixture generation | ready | `xTESEdit64.exe` SHA-256 `659FADDD8DC061A9D2EDDD20DE925821B87E377284CE179F4538FF78BB2420CD`; archive SHA-256 `54C014DA621F83F06A64FD92DDB8E32ED3082D1C65F543DC1C4E432130DCED08`; Authenticode unsigned, consistent with the maintainer archive. |
| Mod Organizer 2 | `2.5.2` | `C:\Tools\ModOrganizer-2.5.2` | GPL-3.0 | [MO2 releases](https://github.com/ModOrganizer2/modorganizer/releases) | Isolated virtualized deployment/profile | ready | Intake archive SHA-256 `E6376EFD87FD5DDD95AEE959405E8F067AFA526EA6C2C0C5AA03C5108BF4A815`. |
| Vortex | `2.4.2` | `%PROGRAMFILES%\Vortex\Vortex.exe` | GPL-3.0 for open-source majority; packaged components need intake review | [Vortex repository](https://github.com/Nexus-Mods/Vortex) | Alternative deployment manager and user-authenticated Nexus acquisition | not-required-v1 | Installed publisher is Black Tree Gaming Ltd.; SHA-256 `1DCE2957D8FF6CDEF3D70D8BC3F1CA7478FFD50AF24EDE2D9BD59C1109814C57`. It was not launched and was not mixed with the selected MO2 isolated profile. |
| SKSE | `2.2.6` package | `C:\Tools\skse64_2_02_06` | SKSE custom licence | [SKSE official site](https://skse.silverlock.org/) | Runtime extension and Papyrus/native interface practical | ready | Archive SHA-256 `D7297F1A1D613E5265E1AF4DBBFE8BD37A32719C1CCEF363FC6187FA6EBA0848`; package matches Steam runtime `1.6.1170`; not deployed to the live game. |
| Address Library | version `11`, AE all-in-one | `C:\tmp\SEG-address-library-v11`; isolated staged profile only | Maintainer/Nexus distribution terms | [Address Library, Nexus mod 32444](https://www.nexusmods.com/skyrimspecialedition/mods/32444) | Relocation database and Together launch prerequisite | ready | User-supplied archive SHA-256 `D345CCDAC52C096FE9628A62FF3764BBF23111BA30E3D282CD3B1FB66968863A`. Exact runtime files are `versionlib-1-6-1170-0.bin` (`C4093C569A3C83B26587F4B9EA4C55DE9AE6E73B84A2AF9FB3FBD30E2FE0D452`) and alternate `versionlib-1-6-1170-0-1.bin` (`AC6D17E8A4BB4DA2539E7A571113BCB28AE5ADF4874CD977332F1A5215F65C07`). Nothing was deployed to the live game or committed. |
| Visual Studio 2022 C++ tools | Community `17.14.37`, complete and launchable | `%PROGRAMFILES%\Microsoft Visual Studio\2022\Community` | Microsoft Visual Studio licence; Community eligibility applies | [VS Community 2022](https://visualstudio.microsoft.com/vs/community/) | Current TiltedEvolution native Windows build | ready | Native xmake build completed at the pinned commit, proving the selected compiler and SDK path usable. |
| CMake | command/registry not found | expected on `PATH` | BSD-3-Clause | [CMake download](https://cmake.org/download/) | Crash Logger source build and general C++ diagnostics | not-required-v1 | Not required by current TiltedEvolution xmake build, but required only if Crash Logger itself is rebuilt. A prebuilt maintainer Crash Logger is the V1 route. |
| xmake | `3.0.9+20260519` | `%PROGRAMFILES%\xmake\xmake.exe` | Apache-2.0 | [xmake downloads](https://xmake.io/#/getting_started) | TiltedEvolution configure, dependency resolution, build and install | ready | SHA-256 `39AB331724AB6F3792793855B5DADF598652C7875BB59A0965EAB0F1AE79B75A`; matches the upstream CI major/minor pin. |
| Git | `2.54.0.windows.1` | `%PROGRAMFILES%\Git\cmd\git.exe` | GPL-2.0 | [Git for Windows](https://gitforwindows.org/) | Source control and recursive clone | ready | Command completed successfully. |
| Git LFS | `3.7.1` | `%PROGRAMFILES%\Git\cmd\git-lfs.exe` | MIT | [git-lfs releases](https://github.com/git-lfs/git-lfs/releases) | LFS-backed dependency/content retrieval when required | ready | `git lfs version` completed successfully. |
| GitHub CLI | `2.95.0` | `%PROGRAMFILES%\GitHub CLI\gh.exe` | MIT | [GitHub CLI](https://cli.github.com/) | Fork/PR/release metadata | ready | Authentication state was not exposed in evidence. |
| PowerShell 7 | `7.6.4` | resolved `pwsh` installation | MIT | [Microsoft install guidance](https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-windows) | Mandated Pester 5 gate and V1 scripts | ready | The exact gate executes under `pwsh`. |
| Pester | `5.9.0` | PowerShell module path, username removed | Apache-2.0 | [Pester releases](https://github.com/pester/Pester/releases) | Expertise and later script tests | ready | Fix-round-4 gate: 8 discovered, 7 passed, 1 failed, 0 skipped. The sole failure is fail-closed: 0 of 2 required independent approvals. |
| Python | `3.13.14` | `%LOCALAPPDATA%\Programs\Python\Python313\python.exe` | PSF licence | [python.org](https://www.python.org/downloads/windows/) | Fixture utilities and analysis | ready | `python --version` completed successfully. |
| Node.js | `24.18.0`; npm `11.16.0` | `%PROGRAMFILES%\nodejs\node.exe` | MIT | [Node.js](https://nodejs.org/en/download) | Together UI build | ready | `node --version` and `npm --version` completed. |
| pnpm | `11.15.0` | `%APPDATA%\npm\pnpm.ps1` | MIT | [pnpm installation](https://pnpm.io/installation) | Together UI dependencies/deploy | ready | Present despite not being in the initial inventory. |
| 7-Zip | command/registry not found | expected `%PROGRAMFILES%\7-Zip\7z.exe` | LGPL with unRAR restriction | [7-Zip download](https://www.7-zip.org/download.html) | Controlled archive inspection/extraction | missing-free | Acquire only from 7-zip.org; verify signature/hash and never execute archive payloads during intake. |
| WinDbg / CDB | debugger `10.0.29617.1000` | Microsoft Store package under `%PROGRAMFILES%\WindowsApps` | Microsoft product terms | [Microsoft WinDbg install](https://learn.microsoft.com/windows-hardware/drivers/debugger/) | Minidump/call-stack practical | ready | `cdb.exe` produced matching-private-PDB output for `TiltedReverse_Tests.exe`, identifying an execute access violation at null from `reverse.cpp:39`. |
| Crash Logger SSE AE VR | not found | expected isolated profile `Data\SKSE\Plugins` | GPL-3.0-or-later with project exceptions; prebuilt download terms also apply | [CrashLoggerSSE source](https://github.com/alandtse/CrashLoggerSSE) / maintainer-linked Nexus AE binary | Sanitized game crash-log practical | missing-user-supplied | User must acquire the AE binary supporting `1.6.1170` through its maintainer distribution; requires Address Library. Do not generate a deliberate live-game crash. |
| TiltedEvolution source | `dev` at `9d81ef07d68e4bb2bd94fca246e798a564b7fb92`; required submodules initialized | `C:\tmp\TiltedEvolution-expertise` | GPL-3.0-or-later | [pinned TiltedEvolution](https://github.com/tiltedphoques/TiltedEvolution/tree/9d81ef07d68e4bb2bd94fca246e798a564b7fb92) | Architecture trace and build practical | ready | Configure/build/install succeed. The crash was traced to an omitted xmake fixture-DLL target in TiltedReverse `55ee3f29…`; an isolated GPL-compatible patch builds `DLL_r.dll`. Fresh results: `TPTests` 28/28 and `TiltedReverse_Tests` 9/9, both exit `0`. The upstream checkout patch is not a repository release artefact. |

## TiltedEvolution dependency findings

The build checkout has the required submodules initialized, including `TiltedConnect` at `293fab99…`, `TiltedHooks` at `d7c175b8…`, `TiltedReverse` at `55ee3f29…`, and `TiltedUI` at `a2b9a671…`. CI pins xmake `3.0.9`, configures x64, runs `xmake -y`, and installs outputs. The guide additionally requires VS2022 C++ workloads, Node.js, pnpm and Address Library for launch.

Fresh resumed build result:

```text
PS C:\tmp\TiltedEvolution-expertise> & 'C:\Program Files\xmake\xmake.exe' -y
[100%]: build ok, spent 1.188s
PS> & 'C:\Program Files\xmake\xmake.exe' install -o distrib
install ok!
PS> .\distrib\bin\TPTests.exe
All tests passed (28 assertions in 5 test cases)
PS> .\distrib\bin\TiltedReverse_Tests.exe
All tests passed (9 assertions in 2 test cases)
EXIT=0
```

Before the fix, CDB loaded the matching private PDB and stopped on `0xc0000005` at null from `reverse.cpp:39`. `reverse.cpp` loads `DLL_r.dll` in release builds and called the resolved function without checking either the module or function pointer. The current xmake file did not build the legacy DLL fixture at all. The isolated fix adds the missing shared-library target/dependency and explicit null assertions; the fresh build, install and two installed test suites pass.

## Isolated runtime compatibility proof

The original [runtime verifier](../../tests/fixtures/runtime/Test-IsolatedRuntimeCompatibility.ps1) reads the exact `SkyrimSE.exe` file version, requires SKSE build `2.2.6`, resolves only the matching Address Library primary/alternate filenames, and refuses any destination outside `C:\tmp`. It stages files but never launches the game or an SKSE plugin. A fresh paired run produced:

```text
REJECT probe=1.6.1179.0 installed=1.6.1170.0 reason=runtime-mismatch
ACCEPT runtime=1.6.1170.0 skse=2.2.6 database=versionlib-1-6-1170-0.bin
REJECT_EXIT=2 ACCEPT_EXIT=0
```

The inspected source SKSE runtime DLL SHA-256 is `C9A2C8A80DF6BF2372C5F49468BB2E5AB67786157265B6F29ECE9F4EAC075D54`; the verifier copied only the two Address Library databases. The isolated profile is disposable and rollback is deletion of that profile; live Skyrim and Vortex were not used.

## Exact acquisition / authorization list

Remaining optional package gaps are:

1. Official 7-Zip x64 if future intake needs a standalone archiver rather than a package-specific extractor.
2. Crash Logger SSE AE binary supporting `1.6.1170`, supplied through the maintainer's authorized distribution.

CMake is deferred unless source-building Crash Logger becomes necessary. Vortex is installed but remains outside the selected MO2 isolation route.
