# Diagnostics and reproduction

Baseline: 2026-08-06. A log line is evidence of an event, not automatically its cause. Prefer a small reproducible transition over an unsorted archive.

## Triage order

1. Record exact runtime, SKSE/native-plugin versions, active plugin list, Creation state, profile, and the last known-good control.
2. Reproduce once on an isolated profile. For multiplayer, record host/client role and the last synchronized checkpoint without retaining account or network identifiers.
3. Classify the failure boundary: launch/load, native crash, Papyrus compile/runtime, record/load-order, single-client behavior, connection, or synchronized state.
4. Collect the smallest relevant evidence: concise steps, timestamps relative to the run, sanitized log excerpt, module/version list, hashes, and a dump only when authorized and handled privately.
5. State **Observation** separately from **Hypothesis**. Name the next check that could disprove the hypothesis.
6. Reduce by one variable at a time against stock control. Never test by deleting paid content, editing a save, or changing the live installation.

Use [Microsoft's WinDbg documentation](https://learn.microsoft.com/windows-hardware/drivers/debugger/) for dump analysis and the [Crash Logger SSE upstream repository](https://github.com/alandtse/CrashLoggerSSE) for that logger's version/build boundary. Match symbols to the exact module bytes. A top stack frame is a starting point, not attribution.

Papyrus compile failures and VM runtime errors are different surfaces. Preserve compiler command/imports for compile issues; for runtime issues, use a disposable save and the smallest script/event transition. Do not commit `.pex`, saves, raw logs, or dumps.

Sanitization is a risk-reduction pass, not a publication guarantee. The collector
redacts common personal paths, network identities, credentials, identifiers, and
sensitive filenames, but novel formats can survive automated rules. Before
sharing or committing a bundle, manually inspect every output file and the
generated manifest; keep the original evidence private.

Run diagnostics tests with the exact supported runner and propagate failures:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 5.9.0 -Force; `$r = Invoke-Pester tests/Common.Tests.ps1,tests/CollectDiagnostics.Tests.ps1 -Output Detailed -PassThru; if (`$r.FailedCount -gt 0) { exit 1 }"
```

## Minimum public evidence

- relative component/plugin identifiers and exact versions;
- deterministic case ID and sanitized reproduction steps;
- stock versus changed result;
- hashes where identity matters, without source bytes;
- Observation, Hypothesis, confidence, and reproduction status;
- tests run and remaining uncertainty.

## Versioned claims

| Claim | Source | Accessed | Applies to | Confidence | Reproduced |
|---|---|---|---|---|---|
| Crash Logger SSE's current upstream documents an Address Library requirement for its Anniversary Edition build path. | [Crash Logger SSE README](https://github.com/alandtse/CrashLoggerSSE) | 2026-08-06 | Upstream repository state on access date; select a binary supporting runtime `1.6.1170` | Medium | No; binary intake is not authorized by this reference |
| WinDbg supports user-mode dump debugging on current Windows tooling. | [Microsoft debugger documentation](https://learn.microsoft.com/windows-hardware/drivers/debugger/) | 2026-08-06 | Windows 11/current debugger | High | Yes; historical matching-symbol CDB practical, not a claim about a new dump |
