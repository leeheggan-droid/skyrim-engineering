---
name: skyrim-engineering
description: Diagnose and engineer version-specific Skyrim Special Edition, Anniversary Edition, and Skyrim Together issues. Use for mod and plugin compatibility, load-order and FormID analysis, crash diagnostics, SKSE ecosystem work, or safe build and release workflows.
---

# Skyrim Engineering

## Foundation

Treat installed games, mods, saves, dumps, and diagnostic archives as private artifacts. Inspect them in place and keep them out of the repository unless the user explicitly authorizes a reviewed, licensed fixture.

Record the exact game runtime, SKSE, mod, and tool versions before diagnosing a compatibility issue. Prefer reversible, minimally invasive changes and verify each result with the applicable tests or tool output.

## Resources

Use `references/` for versioned ecosystem and workflow evidence, and `scripts/` for deterministic inspection or validation helpers as they are added.
