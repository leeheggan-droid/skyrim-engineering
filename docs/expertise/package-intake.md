# Package intake policy

Version: 1.0
Applies to every executable, archive, source bundle, game/mod package, fixture, symbol file and user-supplied licensed item before it enters an isolated Skyrim engineering workspace.

## Intake record

Create one record per package with:

- package title, exact version, filename and size;
- canonical origin URL and named publisher/maintainer;
- acquisition timestamp and acquiring identity category without personal contact details;
- cryptographic SHA-256 hash recorded before extraction;
- Authenticode/GPG/release-signature status and signer/fingerprint where the publisher provides one;
- licence/EULA, access terms, ownership requirement and redistribution rights;
- malware scan provider, signature/database date, result, and whether any archive member was separately scanned;
- supported Skyrim runtime, SKSE version, tool version, operating system and architecture;
- secrets/privacy scan result for tokens, passwords, account IDs, home paths, network addresses, saves and dumps;
- binary execution risk: scripts, DLL loading, installers, drivers, hooks, network access, update behavior and privilege request;
- approved destination, isolation boundary, expected files and rollback/removal procedure;
- decision: accepted, quarantined, rejected, or user-authorisation-required, with reviewer and rationale.

## Required checks

1. **Origin:** follow only the canonical vendor/maintainer URL in [source-register.md](source-register.md). Redirects must terminate on that publisher's controlled distribution. Do not accept rehosted binaries merely because names match.
2. **Integrity/signature:** compute SHA-256 before unpacking. Verify publisher signature or signed Git tag/release when available. If no publisher hash/signature exists, record that limitation and require a clean malware scan plus source/release correlation.
3. **Licence/access:** read the actual licence/EULA. Confirm the acquiring user is entitled to access it. A free download does not imply redistribution permission.
4. **Malware:** scan the unopened package and extracted tree with current local protection. Multi-engine upload is allowed only when licence and confidentiality permit; never upload paid/proprietary game or mod packages to public scanners without permission.
5. **Version:** match exact game runtime `1.6.1170.0`, Steam store, architecture, SKSE and Address Library where applicable. Reject ambiguous `latest` labels until resolved to a concrete version/hash.
6. **Redistribution:** mark each file as original, licence-compatible, metadata-only, or non-redistributable. Proprietary Bethesda/Creation/Nexus binaries remain outside Git.
7. **Secrets/privacy:** inspect text/config/manifests before commit. Redact usernames, Steam identifiers, credentials, server passwords, IP addresses and personal absolute paths.
8. **Execution risk:** inspect archive listings and scripts before running. Do not execute from Downloads or the live game tree. Installers, DLLs and hooks require explicit authorization and an isolated destination.
9. **Destination:** resolve and display the exact absolute destination before any write. The approved V1 targets are an isolated mod-manager profile, a disposable build checkout without spaces, or a quarantine directory; never silently use the live Steam installation.
10. **Rollback:** record files/directories created, profile changes and how to remove them. Preserve the stock control manifest and do not alter paid plugins.

## Licensed-package handling

- Steam validates Skyrim and the Creation Kit entitlement; only metadata and original fixtures may enter the public repository.
- Nexus-authenticated Address Library and Crash Logger packages are user-supplied inputs unless Lee explicitly authorizes acquisition. Their binaries are not committed.
- A TiltedEvolution derivative remains in a separate GPLv3-compliant fork with corresponding source and notices; this skill repository stores only original evidence and links.
- xEdit, MO2, xmake, PowerShell/Pester, 7-Zip, WinDbg and Visual Studio are obtained from their official sources, then their distinct licences are recorded rather than flattened into the repository licence.

## Current intake queue

| Package | Need | Required selection | Intake decision before acquisition |
|---|---|---|---|
| PowerShell / Pester | Test gate | PowerShell `7.6.4`, Pester `5.9.0` | accepted; exact gate executed |
| Creation Kit | CK/Papyrus practical | Steam app `1946180`, CK `1.6.1378.1` | accepted; executable hashed and isolated V3 round trip completed |
| xEdit | Plugin/conflict practical | Maintainer `4.1.5f` | accepted; archive/executable hashed and read-only practical executed |
| MO2 | Isolation | Maintainer `2.5.2` | accepted; archive hashed; no live deployment |
| SKSE | Runtime practical | `2.2.6` for Steam `1.6.1170` | accepted and hashed; not deployed |
| Address Library | Relocation/Together launch | Version `11` AE/all-in-one containing `1.6.1170` data | accepted from user-supplied archive; archive SHA-256 `D345CCDAC52C096FE9628A62FF3764BBF23111BA30E3D282CD3B1FB66968863A`; temp-only extraction/staging |
| VS2022 C++ workloads | Together build | Community `17.14.37` with native workloads | accepted; build proved usable |
| xmake | Together build | `3.0.9` | accepted, hashed and executed |
| 7-Zip | Archive intake | Official x64 current release | user-authorisation-required |
| WinDbg | Dump practical | Microsoft debugger `10.0.29617.1000` | accepted; matching-symbol CDB practical executed |
| Crash Logger SSE AE | Crash practical | Maintainer AE build supporting `1.6.1170` | user-authorisation-required and authenticated-user-supplied |

Remaining unaccepted optional items are standalone 7-Zip and the Crash Logger binary. Neither is required by the completed V1 gate. Accepted third-party binaries remain outside the repository.
