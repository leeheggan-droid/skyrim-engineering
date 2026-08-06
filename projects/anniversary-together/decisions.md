# Anniversary Together compatibility lab

This repository contains repeatable compatibility contracts, not player data.
Actual participant identities stay in a private, untracked local roster. Tracked
artifacts use only `slot-1` through `slot-3` for private setup and `client-a`
through `client-c` for public result records.

The host is the authority for irreversible quest, world, dialogue, and scene
state. Clients exercise bounded combat and loot actions, then record whether
the host commit converges. Each case names its checkpoint, retained sanitized
diagnostic evidence, and cleanup before it is run.

Only clean campaign saves are used locally. Saves, dumps, binaries, licensed
assets, Steam IDs, network addresses, and real names are never committed.
