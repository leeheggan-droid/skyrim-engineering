# Client A setup checkpoint — 2026-08-07

Status: paused deliberately at the Skyrim main menu. Resume from **Next action**.

## Completed

- Verified Steam Skyrim Special Edition/Anniversary runtime `1.6.1170.0` at
  `C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition`.
- Installed portable Mod Organizer 2 `2.5.2` at
  `C:\Tools\ModOrganizer-2.5.2` and connected it to Nexus Mods.
- Created and selected the MO2 profile `Skyrim Together Reborn` with
  profile-specific saves and INIs.
- Downloaded, installed, and enabled Address Library for SKSE Plugins, version
  11, including the `1.6.1170` address database. SKSE itself was not installed.
- Downloaded, installed, and enabled Skyrim Together Reborn `1.8.0` and enabled
  `SkyrimTogether.esp`.
- Added `Skyrim Together Reborn` as an MO2 executable and successfully used the
  MO2 Run button to launch Skyrim through that entry.
- Accepted Skyrim's first-run Anniversary Edition download. The first transfer
  stalled on `The Cause` at 95%; Skyrim was closed cleanly and relaunched through
  MO2. It then reached the main menu.
- The MO2 overwrite directory contains 38 newly captured Creation Club files,
  totalling 849,895,601 bytes. Keep these files: they are licensed local content
  and have not yet been promoted into a named MO2 mod.

## Current local state

- MO2 profile: `Skyrim Together Reborn`
- Enabled mods: `Address Library for SKSE Plugins`, `Skyrim Together Reborn`
- Enabled Reborn plugin: `SkyrimTogether.esp`
- Skyrim was left running at the main menu when this checkpoint was written.
- Two failed extraction attempts were retained reversibly under
  `C:\Tools\ModOrganizer-2.5.2\downloads\_failed-extractions`; they are outside
  the active mod list and can be removed after the successful installation is
  fully verified.

## Next action

1. In Skyrim, choose **New** or **Continue** and wait until the player character
   can move.
2. Press **F2** in-game. Confirm that the Skyrim Together Reborn connection
   panel appears. F2 doing nothing at the main menu is not a failure.
3. Close Skyrim cleanly after the overlay check.
4. Promote the 38 Creation Club files from MO2 `overwrite` into a named,
   client-local MO2 mod before further tests; do not copy or redistribute them.
5. Run the sanitized client inventory/parity capture, then repeat the standard
   installation on `client-b` before beginning the two-laptop reproduction
   matrix.

## Do not redo

- Do not reinstall MO2, Address Library, or Reborn unless verification finds a
  concrete defect.
- Do not install SKSE merely because Address Library contains an `SKSE` folder;
  Reborn does not require the SKSE launcher.
- Do not patch Reborn before a two-laptop Anniversary defect is reproduced.
