# Task 4 report: Creation inventory and cross-machine comparison

Status: complete.

## Delivered

- `inventory-creations.ps1` emits deterministic `skyrim-engineering.creations/v1` manifests for the approved Creation filename set. Entries retain only name, relative path, size, lowercase SHA-256, extension-derived kind/plugin type, and `internalFlag: notInspected` for plugins.
- `compare-installations.ps1` validates one or more manifests and emits `skyrim-engineering.comparison/v1`. The first manifest is the baseline; missing, extra, hash, size, and load-order differences are categorized deterministically. Exit codes are 0 (parity), 2 (differences), and 1 (malformed input).
- Synthetic text-only creation and manifest fixtures cover stable ordering, privacy-safe relative paths, lowercase hashes, extension classification, uninspected internal flags, parity, categorized changes, and malformed input.
- The licensed local inventory found all 74 referenced plugin identifiers with no corrections required. This reproduces the filename set, not the display-name-to-filename mapping, which remains medium-confidence source-backed data. No assets or installation paths were copied or retained.

## Evidence

- RED: the new Pester suite failed 5/5 before either entrypoint existed.
- GREEN: `InventoryCreations.Tests.ps1` and `CompareInstallations.Tests.ps1` passed 5/5 after implementation.
- Final focused run: inventory, comparison, and reference suites passed 9/9.
- PowerShell 5.1 and PowerShell 7 parser checks passed for both scripts.
- Read-only licensed inventory: 148 approved files (74 plugins and 74 archives); all 74 reference identifiers present, no extras or omissions, all SHA-256 strings lowercase, and no absolute installation path in emitted JSON.
- Privacy scan found no user paths, Steam IDs, token prefixes, or live game paths in Task 4 artifacts. `git diff --check` passed.

## Concern

The inventory intentionally classifies plugin type from the filename extension only. It does not inspect binary plugin headers, so plugin entries explicitly report `internalFlag: notInspected`.
