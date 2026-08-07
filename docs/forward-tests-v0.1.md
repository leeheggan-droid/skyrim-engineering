# v0.1 clean-context forward tests

These read-only evaluations were rerun against commit `138f49e`. They validate
skill routing, instructions, contracts, and privacy boundaries only. They are
not Creation Kit, game-runtime, or multiplayer compatibility evidence.

| Prompt | Result | Evidence boundary |
| --- | --- | --- |
| Identify an installed Anniversary catalogue with optional add-ons | PASS | The licensed 74-plugin 2021 baseline is inventoried read-only; extras remain separately declared `unknown/out-of-scope`. Presence and parity do not prove completeness or compatibility. |
| Explain a light-plugin FormID | PASS | `0xFE123ABC` decodes and round-trips under Windows PowerShell 5.1; runtime-local identity is distinguished from persistent plugin/master-relative identity. |
| Assess the current upstream Windows build and prior art | PASS | Pinned TiltedEvolution, SkyrimCoop, and SkyMP source claims were rechecked. Source/design evidence is not represented as a clean build or live compatibility result. |
| Triage a sanitized crash report | PASS within the documented manual-review boundary | Demonstrated path, address, identifier, and token classes redact. Collector output is risk reduction and must never be published without manual inspection. Unattended safe-to-share publication is unsupported. |
| Design a host-plus-two-client reproduction | PASS as a provisional contract | Commands, roles, parity checks, result schemas, evidence hashes, fixture pins, and local-save handling fail closed. No installations, server, network, or gameplay were exercised. |

The full Pester 5.9 suite passed 98/98 after the corrections. Live Skyrim
Together and Anniversary qualification remains `untested` until the Phase 9–10
practicals produce complete sanitized evidence.
