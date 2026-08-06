# Skyrim Engineering Skill Design

Date: 2026-08-06
Status: Approved for implementation planning

## Purpose

Create a public, versioned Codex skill that provides durable Skyrim Special
Edition and Anniversary Edition engineering capability. The skill must support
repeat work on Skyrim mod diagnostics, plugin analysis, Skyrim Together Reborn
development, Anniversary Creation compatibility, reproducible family setups,
and upstream-quality fixes.

The first applied project is a three-player Skyrim Together Reborn compatibility
programme using the complete licensed Anniversary Creation Club library on
matching Windows laptops.

## Outcomes

The completed capability will:

- give future Codex sessions a concise, source-aware Skyrim engineering workflow;
- preserve detailed knowledge in selectively loaded references rather than a
  monolithic prompt;
- provide deterministic, read-only inspection and diagnostic scripts;
- distinguish verified facts, community reports, hypotheses, and test results;
- make research and engineering work repeatable across Lee, Erinn, and Flynn's
  matching laptops;
- support safe forks and upstream contributions to Skyrim Together Reborn; and
- prevent copyrighted game or mod files, personal data, and secrets from entering
  the public repository.

## Repository and Installation Model

The canonical public repository will be:

`https://github.com/leeheggan-droid/skyrim-engineering`

The canonical local checkout will be:

`C:\Users\jacks\github\skyrim-engineering`

The discoverable skill path will be:

`C:\Users\jacks\.codex\skills\skyrim-engineering`

The discoverable path will be a Windows directory junction to
`C:\Users\jacks\github\skyrim-engineering\skill\skyrim-engineering`. This keeps
Git as the only source of truth and avoids copy drift. Installation tooling must
verify both resolved paths before creating or replacing any junction. It must
not overwrite a real directory or an unrelated link.

The repository will be public. It will use an open-source licence suitable for
the original scripts and documentation. Any fork or derivative of Skyrim
Together Reborn will remain in a separate GPLv3-compliant repository or fork;
the engineering skill will not copy upstream source into its own history.

## Skill Trigger and Scope

The skill name will be `skyrim-engineering`.

Its metadata will trigger for Skyrim Special Edition or Anniversary Edition
engineering tasks including:

- game, Creation, mod, save, load-order, or crash diagnosis;
- ESP, ESM, ESL, light-plugin, FormID, Papyrus, SKSE, Address Library, xEdit,
  Creation Kit, or runtime-version work;
- Skyrim Together Reborn client, server, source, build, synchronization, test,
  fork, patch, release, or upstream-contribution work;
- Anniversary Creation compatibility research or testing; and
- construction or validation of a reproducible Skyrim installation.

The skill is an engineering capability, not a general lore guide, gameplay
walkthrough, cheat guide, or repository for game assets.

## Architecture

```text
skyrim-engineering/
|-- skill/
|   `-- skyrim-engineering/
|       |-- SKILL.md
|       |-- agents/
|       |   `-- openai.yaml
|       |-- references/
|       |   |-- ecosystem.md
|       |   |-- plugins-and-formids.md
|       |   |-- diagnostics.md
|       |   |-- together-reborn.md
|       |   |-- anniversary-creations.md
|       |   |-- build-and-release.md
|       |   `-- research-ledger.md
|       `-- scripts/
|           |-- inspect-skyrim.ps1
|           |-- inventory-creations.ps1
|           |-- compare-installations.ps1
|           `-- collect-diagnostics.ps1
|-- projects/
|   `-- anniversary-together/
|-- tests/
|-- docs/
`-- LICENSE
```

### Core Skill

`SKILL.md` will remain concise and procedural. It will define source hierarchy,
task routing, safety boundaries, diagnostic order, research-quality rules, and
which reference to load for each class of work. It will not duplicate detailed
reference content.

### References

References will use progressive disclosure:

- `ecosystem.md`: precise SE/AE terminology, runtimes, tools, file locations,
  and version relationships;
- `plugins-and-formids.md`: ESP/ESM/ESL structures, light-plugin address space,
  load order, records, overrides, and safe analysis practices;
- `diagnostics.md`: logs, dumps, saves, Papyrus evidence, reproducibility, and
  triage sequencing;
- `together-reborn.md`: upstream repositories, architecture, client/server data
  flow, mod mapping, build system, test surfaces, and contribution workflow;
- `anniversary-creations.md`: licensed catalogue identifiers, plugin mapping,
  known interaction surfaces, and compatibility status;
- `build-and-release.md`: reproducible Windows builds, artefact provenance,
  versioning, packaging, and rollback; and
- `research-ledger.md`: dated claims with source type, affected versions,
  confidence, verification state, and supersession links.

Long references will have a table of contents. Information will live in exactly
one canonical location.

### Scripts

All initial scripts will be PowerShell because the target family machines run
Windows 11. Scripts will default to read-only operation, support explicit paths,
return non-zero exit codes for actionable failures, and offer structured JSON
output as well as concise human output.

- `inspect-skyrim.ps1` detects Steam and Skyrim paths, runtime and file versions,
  DLC state, relevant tools, free space, and diagnostic locations.
- `inventory-creations.ps1` inventories plugins and archives, identifies plugin
  type, records sizes and hashes, and emits a stable manifest without copying
  content.
- `compare-installations.ps1` compares sanitized manifests from multiple
  machines and reports missing, extra, version-different, hash-different, and
  order-different entries.
- `collect-diagnostics.ps1` collects only approved logs and configuration into a
  sanitized bundle. It redacts Windows usernames, home paths, Steam account IDs,
  server passwords, tokens, and network addresses by default.

No script will download paid content, bypass licences, alter Bethesda plugins,
edit saves, modify firewall rules, publish data, or install software without an
explicit task and a separate confirmation when risk or user experience warrants
it.

### Applied Projects

`projects/anniversary-together/` will hold original manifests, test definitions,
result schemas, sanitized observations, and project decisions for the first
compatibility programme. It will not contain Bethesda assets, Nexus packages,
Skyrim Together binaries, personal saves, raw crash dumps containing personal
data, or credentials.

Reusable knowledge discovered by a project will move into the appropriate skill
reference only after review. Project-specific state will remain in the project.

## Knowledge and Research Workflow

Use this evidence order unless the task justifies otherwise:

1. Direct observation and reproducible artefacts from the affected version.
2. Upstream source, official documentation, release notes, and maintainers.
3. Primary tool or platform documentation.
4. Well-supported community reports with versions, logs, and reproduction steps.
5. Unsourced guides, videos, and anecdotes only as leads.

Every unstable technical claim must record the source URL or repository
reference, access date, applicable game/tool version, confidence, and whether it
was independently reproduced. Conflicting sources remain visible until evidence
resolves them. A newer source does not automatically supersede an older one
unless the affected version or code changed.

Research packages supplied later will pass an intake check covering provenance,
licence, malware risk where applicable, currency, duplication, and practical
value. Accepted material will be summarized into original references or stored
only where its licence permits. Untrusted binaries will not be run merely to
inspect them.

## Engineering Workflow

For a Skyrim engineering task:

1. Identify exact game runtime, store, DLC/Creation state, mod manager, plugin
   order, Skyrim Together version, and affected save type.
2. Preserve the original installation and reproduce on an isolated profile or
   fixture.
3. Establish a stock control before changing source or content.
4. Collect the smallest useful logs, dumps, manifests, and reproduction steps.
5. Classify observations separately from hypotheses.
6. Inspect upstream source and history before designing a patch.
7. Add or update a focused automated test when the codebase permits it.
8. Validate single-client behaviour, then server connection, then multi-client
   synchronization, reconnect, and save continuity.
9. Package only original or legally redistributable changes with provenance and
   rollback instructions.
10. Promote reusable, reviewed findings into the skill knowledge base.

For Skyrim Together work, do not assume that Anniversary executable support is
the same as support for the full Creation library. Current source already
contains light-plugin/FormID handling; compatibility claims must be tested at the
Creation behaviour and synchronization level.

## Anniversary Together First Project

The first project will use three identical Gigabyte Gaming A16 Windows laptops,
Steam Skyrim Special Edition runtime `1.6.1170.0`, the licensed complete
Anniversary Creation Club library, and Lee, Erinn, and Flynn as testers.

It will:

- capture a canonical, sanitized Creation manifest from each laptop;
- establish unmodified-current-release control sessions;
- use fresh co-op-only characters that complete Helgen before connecting;
- define short tests for connection, inventory, combat, quests, horses, pets,
  homes, containers, Survival Mode, death, reconnect, and save continuity;
- classify each scenario as pass, partial, host-only, desync, crash, blocked, or
  untested;
- correlate failures with logs and precise Creation/plugin identifiers;
- patch Skyrim Together only when evidence identifies an upstream-code defect;
  and
- keep unsupported experimental releases visibly distinct from upstream builds.

The project will not convert or redistribute Bethesda ESL files. The historical
ESL-to-ESP workaround will be recorded as dated community prior art, not adopted
as the implementation strategy.

## Error Handling and Privacy

Inspection scripts must fail safely when paths, permissions, tools, or expected
files are missing. They must report the failed check, discovered paths, and the
next safe action without silently changing the machine.

Generated public artefacts must exclude:

- credentials, tokens, server passwords, and private keys;
- Steam IDs and account ownership identifiers;
- Windows usernames and personal absolute paths;
- public or private IP addresses unless explicitly approved for a private test;
- copyrighted game, Creation, mod, or tool binaries; and
- saves or dumps not explicitly sanitized and approved.

Fixtures will be synthetic or irreversibly sanitized. CI will scan for common
secret formats, prohibited binary extensions, and accidental local paths.

## Validation

### Skill Validation

- Run the Codex skill validator with no errors.
- Confirm `agents/openai.yaml` matches the skill metadata and default prompt.
- Check that representative Skyrim engineering prompts trigger the skill and
  unrelated gaming prompts do not.

### Script Validation

- Parse every PowerShell file without executing mutations.
- Use Pester tests and sanitized fixtures for detection, manifest, comparison,
  redaction, missing-path, and malformed-input cases.
- Run read-only inspection against Lee's reference laptop and compare results to
  directly observed game files.
- Verify deterministic JSON output for unchanged fixtures.

### Forward Tests

Use clean agent contexts to test at least these tasks:

- identify the installed Anniversary catalogue from a sanitized fixture;
- explain and inspect a light-plugin FormID;
- plan a current Skyrim Together Windows build from upstream instructions;
- triage a sanitized crash/log bundle; and
- design a three-client synchronization reproduction without leaking expected
  conclusions.

Forward tests must receive the skill and raw task artefacts, not this design's
intended answers.

### Continuous Integration

CI will validate Markdown links where network access permits, skill structure,
PowerShell syntax and tests, deterministic fixtures, secret scanning, local-path
leakage, and prohibited file types. It will not require Skyrim, paid Creations,
Nexus authentication, or proprietary binaries.

## Completion Criteria

Version 1 is complete when:

- the public repository exists with the agreed structure and licence;
- the local auto-discovered skill resolves to the canonical checkout;
- the skill passes structural validation;
- all four initial scripts pass automated tests and a read-only reference-laptop
  check;
- the seven initial references contain sourced, versioned baseline knowledge;
- CI passes on the public repository;
- forward tests demonstrate useful behaviour on the five representative tasks;
  and
- the Anniversary Together project can begin with a reproducible control test
  and three-machine parity workflow.

## Explicit Non-Goals for Version 1

- A complete Skyrim lore or gameplay knowledge base.
- Redistribution or automated acquisition of paid/proprietary content.
- An automatic mod installer or unattended machine-changing bootstrapper.
- A claim that every Anniversary Creation is compatible before testing.
- A pre-emptive Skyrim Together code change without a reproduced defect.
- Support for console, VR, Game Pass, Epic, GOG, or non-Windows clients.
- Inclusion of post-Anniversary paid Verified Creations.
