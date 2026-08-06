# Versioned ecosystem baseline

Baseline: 2026-08-06. Scope: Windows 11, Steam Skyrim Special Edition `1.6.1170.0`, the licensed Anniversary Upgrade catalogue, and x64 tools. “AE” is community shorthand for the 1.6 runtime/Anniversary era, not a different plugin format; always record the executable version and store explicitly.

## Resolve the stack before diagnosis

1. Read the executable product and file version; do not infer it from a mod label.
2. Match [SKSE](https://skse.silverlock.org/) to the exact runtime. The maintainer page listed SKSE `2.2.6` for Steam runtime `1.6.1170` on the baseline date.
3. Resolve each native plugin's runtime support and Address Library dependency independently. Address data does not prove ABI or behavioral compatibility.
4. Record the Creation Kit, xEdit/SSEEdit, mod manager, compiler, and Together release or commit. Prefer immutable upstream tags/commits to “latest”.
5. Inventory licensed Creation state separately from the executable. Owning Anniversary does not prove that every file is present, identical, enabled, or compatible.

Canonical acquisition points are [Steam's Skyrim Special Edition page](https://store.steampowered.com/app/489830/), [Steam's Creation Kit page](https://store.steampowered.com/app/1946180/), [SKSE](https://skse.silverlock.org/), and the [xEdit repository and releases](https://github.com/TES5Edit/TES5Edit). Do not use rehosted executables.

## Versioned claims

| Claim | Source | Accessed | Applies to | Confidence | Reproduced |
|---|---|---|---|---|---|
| SKSE `2.2.6` is the maintainer-listed build for Steam Skyrim `1.6.1170`. | [SKSE maintainer distribution](https://skse.silverlock.org/) | 2026-08-06 | Steam runtime `1.6.1170` only | High | No; documentary baseline only |
| Anniversary Edition/Upgrade contains the Special Edition add-ons and the Creation Club set released for the 2021 bundle. | [Bethesda Anniversary page](https://elderscrolls.bethesda.net/en-US/skyrim10) and [official catalogue announcement](https://elderscrolls.bethesda.net/en-AU/news/3mxTW4iQYGrVZrWRqVfomQ/skyrim-anniversary-edition-and-creation-club-content-first-look) | 2026-08-06 | 2021 Anniversary bundle, not later Verified Creations | High | No; verify licensed files locally |

If observed versions differ, stop and route the claim through [research-ledger.md](research-ledger.md); do not silently transpose this baseline.
