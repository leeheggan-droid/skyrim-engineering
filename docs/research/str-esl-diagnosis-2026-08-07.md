# DRAFT — Why Anniversary/CC content breaks in Skyrim Together Reborn (source diagnosis)

Status: DRAFT, not yet promoted to the research ledger. Claims below follow the
ledger's Observation/Hypothesis split. Source: direct inspection of
`tiltedphoques/TiltedEvolution` (clone of master, 2026-08-07) plus upstream
issues/PRs. No runtime reproduction yet — that is what the two-laptop session
verifies.

## The historical defect (OBSERVED in source, FIXED upstream)

- ESL (light) plugins compose formIDs as `0xFE | liteId<<12 | recordId&0xFFF`
  (`Code/client/Games/ModManager.cpp`).
- From STR v1.0.0 (2022-07) until PR #615 (merged 2023-08-02, shipped v1.6.1,
  2023-12-09), `ModSystem::GetServerModId()` in
  `Code/client/Systems/ModSystem.cpp` assigned `aBaseId = liteId` for ESL
  forms — every record in a light plugin collapsed to a single, load-order-
  dependent ID. Receivers rebuilt a formID pointing at the wrong or no record;
  lookup failure returns 0 = "no form", so CC content **silently failed to
  sync** rather than crashing.
- The fix was one line: `aBaseId = aGameId & 0xFFF`. The wire protocol never
  needed changing (16-bit mod ids + explicit `IsLite` flag + 32-bit GameId
  already sufficient).
- Corroboration that ESLs are now expected to resolve: master special-cases
  CC's `ccbgssse038-bowofshadows.esl` by name
  (`Code/client/Games/Skyrim/Forms/MagicItem.cpp:40`, PR #800).

## Implications

1. **Community doctrine is largely stale.** "Delete the 4 CC packs", "CC makes
   STR unstable", and the Fahdon ESL→ESM conversion recipe all date from the
   bugged era (2022–2023). The wiki removal guides predate the fix.
2. **ESL→ESM conversion is probably unnecessary on STR ≥ v1.6.1.** It was a
   valid workaround because converted plugins take the standard (correct)
   mapping path. Hypothesis to verify, not fact.
3. **Current builds do not block CC content.** `DiscoveryService::OnEvent`
   (master) compares the load order to the 7 vanilla plugins and, on mismatch,
   only raises `non_default_install` — a UI warning popup
   (`skyrim_ui .. NON_DEFAULT_INSTALL` string, "We do NOT recommend playing
   with mods"). No disconnect is triggered. Server-side `ModPolicy`
   (`bEnableModCheck`, default **false**) is the only hard kick, and it matches
   by filename — so all machines must keep identical (un)converted filenames.
4. **Survival Mode is broken by design, not by the ESL bug**: STR removes
   wait/sleep and server-controls time, so exhaustion is unrecoverable and
   non-host hunger sticks (upstream #621, #290, #526). Community fix mod:
   "You Need to Rest" (Nexus 182400). Recommend: disable Survival for co-op.
5. **Residual landmine if server record-parsing returns**: the server's
   es_loader has record loading disabled since 2022 (`BuildRecordCollection`
   early-returns empty; commit 0d942fc5) and classifies plugins by filename
   extension, so an ESL-flagged `.esp` would classify differently client vs
   server if `LoadFiles()` is ever re-enabled.

## What the two-laptop session should verify first (supersedes stock-only plan)

1. Current STR (≥1.6.1, ideally latest) + full Anniversary content **enabled,
   unconverted**, identical load order both machines, private server,
   ModPolicy check off (default). Expect the `non_default_install` popup;
   dismiss and proceed.
2. Run the 13 cases against CC surfaces: S&S/The Cause quests (leader-hosted),
   fishing minigame, CC homes/pets/horses, Rare Curios items.
3. Only if instability reproduces: retry with ESL→ESM-converted set to isolate
   whether any residual ESL-path defect remains post-#615.
4. Survival Mode: excluded (known-broken); optional later test with the
   "You Need to Rest" addon.

Nobody in the community has published per-Creation behavior results
(host-only vs desync vs works) — that record is this project's genuine
contribution.
