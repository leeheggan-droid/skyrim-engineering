# Build, package, and release

Baseline: 2026-08-06. Build only from a named upstream repository/tag/commit in an isolated checkout. A build is evidence about the toolchain, not game or multiplayer compatibility.

## Reproducible sequence

1. Record origin, commit/tag, submodules, license, tool versions, package hashes/signatures, and the exact clean destination. Do not build in the live game tree or a personal-path-bearing release directory.
2. Reconcile maintainer documentation with pinned CI. For Together commit `9d81ef07`, inspect the [build guide](https://wiki.tiltedphoques.com/tilted-online/technical-documentation/build-guide) and [Windows workflow](https://github.com/tiltedphoques/TiltedEvolution/blob/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/.github/workflows/windows.yml); do not silently substitute newer commands.
3. Initialize required submodules, configure the pinned architecture/mode, run focused tests, then build/install to an isolated staging directory.
4. Capture command, exit code, concise compiler/test output, commit, tool versions, and SHA-256 for original distributable artifacts. Exclude proprietary dependencies and absolute paths.
5. Rebuild from a fresh checkout when determinism matters. Explain any non-deterministic bytes rather than normalizing them away.
6. Stage single-client and multi-client verification separately from build success.

## Legal package boundary

- Keep TiltedEvolution derivatives in a separate fork and follow its [GPL-3.0-or-later license](https://github.com/tiltedphoques/TiltedEvolution/blob/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/LICENSE), notices, and corresponding-source obligations.
- xEdit-covered files follow the pinned [MPL-2.0 license](https://github.com/TES5Edit/TES5Edit/blob/xedit-4.1.5f/LICENSE.txt).
- SkyMP is primarily GPLv3/AGPLv3 and uses per-subproject terms; inspect its pinned [TERMS](https://github.com/skyrim-multiplayer/skymp/blob/d85f18d808f877401c4e20484d2c2f6f73cf9caa/TERMS.md) and exact subproject license before reuse.
- SkyrimCoop's pinned [license](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/LICENSE) is GPL-3.0-or-later with an LGPLv2 launcher note; a derivative also needs an inherited-source and notice audit.
- No open-source license grants rights to Bethesda assets, Creation plugins/archives, Nexus packages, SKSE binaries, saves, dumps, or user data. Package links, provenance, hashes, and original code—not third-party payloads.

Release notes must name version/commit, supported runtime/store, tested scope, evidence, known limits, license/notices, install destination, backup/rollback, and a clear distinction between upstream and experimental builds. Never overwrite an existing profile or imply paid-content compatibility that was not tested.

## Versioned claims

| Claim | Source | Accessed | Applies to | Confidence | Reproduced |
|---|---|---|---|---|---|
| TiltedEvolution's pinned Windows CI initializes recursive submodules and pins xmake `3.0.9` for its build. | [Windows workflow at `9d81ef07`](https://github.com/tiltedphoques/TiltedEvolution/blob/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/.github/workflows/windows.yml) | 2026-08-06 | Pinned commit, not future `dev` | High | Yes; historical isolated build succeeded |
| TiltedEvolution derivatives are governed by GPL-3.0-or-later at the pinned commit. | [Pinned license](https://github.com/tiltedphoques/TiltedEvolution/blob/9d81ef07d68e4bb2bd94fca246e798a564b7fb92/LICENSE) | 2026-08-06 | Covered upstream source and derivatives | High | Yes; license inspected; distribution obligations still require release review |
