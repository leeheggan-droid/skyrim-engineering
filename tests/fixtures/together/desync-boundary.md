# Desync evidence boundary

`Test-DesyncEdge.ps1` exercises a deliberately small source model. It is useful
for checking the expected sequence—authority update, missed delta, divergent
local activation, reconnect, full snapshot—but it is not wired into
TiltedEvolution production code and is not evidence of a reproduced Skyrim
Together desync. The activation route is intentional in the model; therefore no
production-edge rubric credit is claimed.

The strongest non-GUI native integration added in round 3 compiles the pinned
production `RequestInventoryChanges` and `NotifyInventoryChanges` types and
passes each through its actual production factory/serialization path. The patch
and raw result are retained beside this file. It remains in-process.

The minimal runtime protocol still required for production credit is:

1. `PlayerCharacter.cpp:169-171` or `Actor.cpp:1099-1101` creates the real
   `InventoryChangeEvent`, including activation-derived `UpdateClients`.
2. Client `InventoryService.cpp:48-74` maps it to
   `RequestInventoryChanges`; `TransportService` sends the encoded client packet.
3. Server `GameServer.cpp:581` extracts through `ClientMessageFactory` and
   dispatches `PacketEvent<RequestInventoryChanges>`.
4. Server `InventoryService.cpp:28-53` mutates `InventoryComponent`, evaluates
   `UpdateClients`, constructs `NotifyInventoryChanges`, and calls
   `SendToPlayersInRange` excluding the sender.
5. `GameServer.cpp:703+` selects recipients and the server transport writes the
   packet; client `TransportService.cpp:98` extracts via `ServerMessageFactory`.
6. Client `InventoryService.cpp:123+` applies the notification to a remote game
   object. A retained divergent state must be observed before and after this
   boundary under actual isolated processes.

No game/client/server process was launched, so steps 1, 3-6 and a real divergent
state remain unproven and the automatic block remains.
