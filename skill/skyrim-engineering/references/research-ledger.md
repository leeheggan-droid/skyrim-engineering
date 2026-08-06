# Research ledger protocol

Baseline: 2026-08-06. Use this reference for new, unstable, disputed, version-sensitive, or superseded claims. Stable procedures belong in their owning reference; project observations remain with the project until reviewed.

## Evidence order

1. Direct observation and reproducible artifacts from the affected version.
2. Owning upstream source, official documentation, releases, maintainers, and tests.
3. Primary tool/platform documentation.
4. Versioned community reports with logs and reproduction steps.
5. Unsourced guides, videos, and anecdotes as leads only.

Inspect prior art before inventing a mechanism. Preserve disagreements until a reproduction distinguishes version, configuration, or behavior. A newer page does not supersede a pinned older claim unless the applicable code/version changed.

## Required claim record

| Claim | Source | Accessed | Applies to | Confidence | Reproduced |
|---|---|---|---|---|---|
| One atomic, falsifiable statement; separate Observation from Hypothesis. | Direct URL, immutable repository path, or sanitized evidence ID; name source type and license/access limits. | `YYYY-MM-DD` | Exact game/store/tool/release/commit/configuration boundary. | High, Medium, or Low with reason. | Yes/No/Partial plus method; source inspection is not runtime reproduction. |

Also record an owner, supersedes/superseded-by link when relevant, conflicting evidence, the next falsifying check, review state, and where the canonical resolved knowledge will live. Never put private evidence or licensed bytes in the ledger.

## Promotion gate

Promote a claim only when its source is retrievable, version boundary explicit, evidence sanitized, conflicts retained or resolved, reproduction honestly scoped, and an independent reviewer accepts the wording. Mark a missing live practical `blocked` or `untested`. Never turn a successful parser fixture, build, source trace, or synthetic synchronization model into a live compatibility PASS.

## Current architectural prior-art record

SkyMP commit `d85f18d808f877401c4e20484d2c2f6f73cf9caa` is recorded as architectural prior art for plugin parsing (`libespm`), persistent server world state, a custom Papyrus VM, TypeScript/C++ boundaries, synchronization tests, and Skyrim Platform. It is not selected as a replacement because its persistent-server/MMO orientation differs materially from the target Skyrim Together family co-op model. See [together-reborn.md](together-reborn.md) for pinned source links and license/terms.

SkyrimCoop commit `6a0c293a97892f83be0672c1ac4a9e0487a19503` is higher-priority experimental prior art for host-owned NPC/world/quest synchronization and an embedded server. It remains a work in progress with no proven release or Anniversary validation; adoption is gated on a clean build/tests and code-delta audit. See [together-reborn.md](together-reborn.md) for pinned source and license links.

## Versioned claims

| Claim | Source | Accessed | Applies to | Confidence | Reproduced |
|---|---|---|---|---|---|
| The six-field record above is the minimum metadata for unstable claims in this skill. | [Approved skill design](../../../docs/superpowers/specs/2026-08-06-skyrim-engineering-skill-design.md) | 2026-08-06 | This repository's V1 knowledge workflow | High | Yes; enforced by focused Pester reference tests |
| SkyMP is relevant architectural prior art but not a drop-in replacement for the selected Together co-op architecture. | [SkyMP pinned tree](https://github.com/skyrim-multiplayer/skymp/tree/d85f18d808f877401c4e20484d2c2f6f73cf9caa), [README](https://github.com/skyrim-multiplayer/skymp/blob/d85f18d808f877401c4e20484d2c2f6f73cf9caa/README.md), and [terms](https://github.com/skyrim-multiplayer/skymp/blob/d85f18d808f877401c4e20484d2c2f6f73cf9caa/TERMS.md) | 2026-08-06 | Architectural comparison at pinned commit | High | Partial; source-tree inspection only, no runtime comparison |
| SkyrimCoop is relevant host-authority/embedded-server prior art but not ready for adoption. | [Pinned tree](https://github.com/blockheads/SkyrimCoop/tree/6a0c293a97892f83be0672c1ac4a9e0487a19503), [README](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/README.md), and [`HostService.h`](https://github.com/blockheads/SkyrimCoop/blob/6a0c293a97892f83be0672c1ac4a9e0487a19503/Code/client/Services/HostService.h) | 2026-08-06 | Commit `6a0c293a`; experimental design/code only | Medium | Partial; no clean build, tests, release, or Anniversary run retained |
