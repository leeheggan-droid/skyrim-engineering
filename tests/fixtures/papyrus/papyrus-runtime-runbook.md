# Papyrus runtime migration — isolated human runbook

This procedure prepares an unverified submission. It never grants live
qualification; named human review remains required.

## Preconditions

- Use Steam Skyrim `1.6.1170.0` and a fresh anonymous run ID.
- Create a new isolated mod-manager profile with profile-specific INI files and
  profile-local saves. Set `bEnableLogging=1` and `bEnableTrace=1` only there.
- Do not write to the live game `Data` tree. Never use or overwrite a personal
  save.
- Build an original ESP containing one Start Game Enabled Quest with
  `SEG_RuntimeMigration` attached. Record its Quest FormID, plugin hash, CK/build
  provenance, and original-only review in the plugin evidence JSON.
- Pin `Skyrim.esm` and that ESP in the complete load order. Stage mutually
  exclusive V1 and V2 mods from the prepared manifest.

## V1 phase

1. Record the UTC phase time and hashes of the runtime, plugin, PEX, load order,
   INI evidence, and empty disposable save directory.
2. Enable only V1, launch the isolated profile, start a new disposable game,
   and wait at least ten seconds.
3. Confirm exact V1 markers, create a new local `.ess` save, then exit fully.
4. Preserve the V1 log without editing it. Never copy this save to another
   profile or machine.

## V2 phase

1. Record a later UTC phase time. Disable V1, enable only V2, and keep the same
   original ESP and isolated profile.
2. Load the local V1 disposable save, wait at least ten seconds for the
   persisted update, and confirm the exact V2 markers.
3. Create a separate local post-migration `.ess` save, exit fully, and preserve
   the V2 log without editing it.

Run `Test-RuntimeCapture.ps1` with both logs, both saves, the stage manifest,
runtime/profile evidence JSON, run ID, and UTC phase times. Manually inspect all
inputs and the output for private data. The output remains
`UNVERIFIED_SUBMISSION` until a named reviewer confirms the run, attachment,
activation, provenance, and observed migration.
