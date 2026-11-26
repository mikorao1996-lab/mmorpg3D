# mmorpg3D

Godot 4 MMORPG vertical-slice project.

## Requirements

- Godot 4.7 or newer
- Windows for the editor/client
- Linux for the server target; Docker is optional

## Project documents

- [docs/plan.md](./docs/plan.md) — roadmap, current state, and the handoff for the next session
- [docs/protocol.md](./docs/protocol.md) — network protocol, opcodes, and snapshot format
- [docs/data_registries.md](./docs/data_registries.md) — schemas of the JSON game data registries
- [docs/architecture.md](./docs/architecture.md) — module overview

## Client

```powershell
godot --path D:\Dev\mmorpg3D --editor
```

The main client scene is `client/scenes/main.tscn`.

## Headless server

The server requires `MMORPG3D_DB_HOST`, `MMORPG3D_DB_PORT`,
`MMORPG3D_DB_NAME`, and `MMORPG3D_DB_USER` in its environment; password is
optional for local trust-authenticated test clusters. PostgreSQL connectivity
and migrations are checked before ENet starts. Missing configuration, an
unavailable database, or a migration error exits the server with code `2`.

```powershell
godot --headless --path D:\Dev\mmorpg3D --scene res://server/main/server_main.tscn
```

The server listens on UDP port `7788` and authoritatively simulates player movement.

## Multiplayer sandbox

Start the headless server in one terminal:

```powershell
godot --headless --path D:\Dev\mmorpg3D --scene res://server/main/server_main.tscn
```

Then launch the project twice (for example, in two terminals):

```powershell
godot --path D:\Dev\mmorpg3D
```

Both clients connect to `127.0.0.1:7788`. The address and port come from
`resources/data/simulation.json`; set `MMORPG3D_SERVER_ADDRESS` and
`MMORPG3D_SERVER_PORT` to join a server on another machine without a rebuild.
Use **WASD** to move; each client
shows both players, predicts its own movement, and interpolates server snapshots.
The server filters snapshots by the configured `interest_radius` (16 world units
by default) and always includes the observing player. Close the server with
`Ctrl+C` when finished. Client player bodies use `CharacterBody3D` as a platform
adapter: the shared movement simulation still determines target positions, while
remote players are interpolated from snapshots. Player collision layers are
disabled until collision rules are authoritative on the server.

The world is a generated landscape: a heightmap terrain with rolling hills
around a flat hub, a forest of trees, and rocks. The terrain and the props are
built from a fixed seed, so every client shows the same map, and they are
decoration only — they never touch the server state. The playable area is
`world_half_extent` units around the spawn point, and the server sends the
mobs, the NPCs, and the drops of the `interest_radius` around a player.

The hub itself is laid out by hand in the registries. The quest givers and the
vendor stand next to the spawn point, the training slimes hold the glade to
the west, the wolves patrol the woods to the east, and the mini-boss waits on
its own spot to the north. A mob type owns a list of spawn points, and the
server creates one instance per point, so the hub holds ten mobs of three
types. The instances of a type share its statistics, and a quest counts the
defeats of the type, not of a single instance. The layout is checked
automatically: no two entities of the hub stand too close, everything stays
inside the world and within a walk of the spawn point, and every equipment
slot has an item the player can actually obtain.

Every player carries a nameplate above the head with the level of the
character, a bar for the health, and a bar for the resource. The panels of the
interface can be hidden: **I** toggles the inventory panel, **C** toggles the
chat panel.

Each zone holds the mobs of the registries. **SPACE** uses `starter_slash`and **E** uses `heavy_strike` on the nearest living mob. **Q** uses
`guard_break`, **R** uses `whirlwind`, and **T** uses `second_wind`. The server
enforces target, range, damage/heal, resource cost, and separate cooldowns. Mob health is
shown in the status panel, and a defeated mob respawns after its configured
8 seconds. The slime pursues nearby players and attacks according to its mob
data; players have 100 health and respawn at their zone spawn after 3 seconds
if defeated. After a zone transfer, the entry position becomes that zone's
respawn point.

The inventory panel on the right shows the six equipment slots, the carried
items, their level requirements, and their stat bonuses. **Equip** sends an
`EQUIP_ITEM` request, clicking a filled gear slot sends `UNEQUIP_ITEM`, and
**Use** on a consumable sends `USE_ITEM`. The server decides whether the
request is accepted; the panel only renders the authoritative snapshot, so an
item above the character level stays locked and a potion is never wasted while
health is full.

**V** talks to the closest NPC in interaction range. The dialogue panel at the
bottom shows the localized dialogue and the quests of that NPC: **Accept**
sends `NPC_INTERACT` with the action `accept`, **Turn in** sends it with
`turn_in`. The quest tracker in the top-left corner lists the accepted quests
with their progress. The server counts kills, item pickups, and conversations,
and hands out the reward of a quest only once. A hand-in is rejected when the
reward does not fit into the inventory, so no experience is lost.

Gold is the currency of the slice. The server pays it for quest hand-ins and
mob defeats, it survives a zone transfer, and the status panel shows the
balance the server reported. Talking to the vendor opens a trade section in
the dialogue panel: **Buy** sends `TRADE_REQUEST` with the action `buy`,
**Sell** sends it with `sell`. A request only names the item and the quantity;
the price always comes from the vendor registry on the server, and the server
checks the vendor, the assortment, the level requirement, the balance, and the
inventory space before anything changes. A rejected trade leaves the balance
and the inventory untouched.

Mob loot is no longer a fixed list. Every item in a mob's `loot_item_ids`
still drops on defeat, while the items in its `loot_chances` list only drop
when the server rolls at or below their chance, so the rare equipment of the
training guardian is a rare drop.

The chat panel on the left holds the chat history, a field to write a message,
and a switch between the **Zone** and the **Party** channel. A zone message
reaches every player of the zone, a party message only the members of the
party. The server checks the length of a message and the number of messages a
player sends per second, and it decides who receives a message. The party
section of the panel lists the members of the party, invites the other players
of the zone, and leaves the party again. A group holds up to
`party_max_size` players, only the leader invites, and the leadership passes
to another member when the leader leaves.

The simulation config defines in-memory zones `starter` and `dungeon`; clients
start in the first configured zone. `ClientNet.request_zone_transfer(zone_id)`
is available for server-validated transfers, but there is not yet a portal or
zone-selection UI.

The character survives a reconnect. On the first connection the server issues
the character an identifier and a secret, and the client keeps both in
`user://character_identity.json`. Every following handshake carries that pair,
so the server restores the level, the experience, the gold, the inventory, the
equipment, the quests, the zone, and the position of the character. The
progress is written back to PostgreSQL when the player leaves and on a regular
interval. The client never sends progress, only the identity, so a modified
client cannot grant itself anything; a client that does not own the secret of a
character is rejected. The secret is a bearer token and the transport is still
plain ENet, so a full login with a protected transport is a separate step.

The server loads the versioned item, ability, mob, quest, NPC, vendor, and
progression JSON registries before listening. Their initial schema and
cross-reference rules are described in
[docs/data_registries.md](./docs/data_registries.md). The item
catalog holds 18 items: three weapons, armor for all six slots, three
consumables, and two quest items. Every equipment slot has at least one item
that can be obtained from mob loot or a quest reward. The quest catalog holds
five quests with kill, collect, and talk objectives, and two quest givers hand
them out. The vendor catalog holds one trader with an explicit assortment and
explicit prices, which is the only place a trade price comes from.

## Unit checks

```powershell
godot --headless --path D:\Dev\mmorpg3D --script tests/unit/run_unit_tests.gd
```

## Network integration check

```powershell
$env:GODOT_BIN = "D:\Dev\Godot_v4.7.2-stable_win64.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File tests/integration/run_integration_tests.ps1
```

The loopback check starts one headless ENet server, two production `ClientNet`
clients, and one incompatible raw client in-process. It checks both successful
handshakes, rejection of the unsupported protocol version, presence of both
players in world snapshots, server-side movement, a successful transfer between
zones with isolated snapshots, and an explicit rejection for an unknown zone.
It also verifies a server-authoritative hit, cooldown enforcement, and range
rejection, plus independent execution of the heavy strike while slash is on
cooldown, an equipment request for an item the player does not own, and two
item-use rejections (a non-consumable and an item that is not carried).

The second integration scene loads the production client scene against an
in-process server and verifies that a snapshot reaches the inventory panel:
six gear slots, the granted loot stacks, and a consumable use request that the
server rejects while the player is at full health.

The third integration scene walks the full quest cycle against the production
client scene: talk to the NPC, accept the quest, defeat the target mob, and
hand the quest in. It checks that the dialogue panel lists the NPC quests, that
the quest tracker reports the progress, and that the hand-in grants the reward
exactly once.

The fourth integration scene walks the full trade cycle against the production
client scene: talk to the vendor, buy an item with the gold of the player,
equip it, and see the stat bonus. It then forges a trade request against an
NPC that does not trade and checks that the server rejects it and leaves the
balance untouched.

The fifth integration scene starts two production client scenes against one
in-process server and walks the social loop: a zone message reaches the other
player, an invitation creates a party, a party message reaches the members,
and a party message no longer reaches the player that left the party.

The sixth integration scene checks the landscape and the interface against the
production client scene: the terrain and the props are built, the flat ground
of the scene is replaced, the nameplate of a player shows the level and the
bars, and the inventory and the chat panel can be hidden and shown again.

The seventh integration scene walks the content of the hub with two real
clients against an in-process server. The positions of the NPCs and of the
mobs are taken from the registries as they are: the first client walks to the
quest giver, accepts a quest, completes it, hands it in, defeats a slime of
the glade, picks up its loot, and buys a potion from the vendor, while the
second client writes into the zone chat and joins the party.

The eighth integration scene plays the life of a persisted character: the
client receives its identity, defeats a slime, picks up the loot, and leaves.
The server stores the progress. The client then comes back with the same
identity and finds its level, experience, gold, and inventory where it left
them, while a client with a foreign secret is rejected.

## PostgreSQL driver spike

The native extension in `native/postgres` is a synchronous `libpq` adapter.
The server initializes the database and applies migrations before opening its
listener. The character repository is wired to the live sessions: the level,
the experience, the gold, the inventory, the equipment, the quests, the zone,
and the position of a character are stored in PostgreSQL and restored on the
next connection.

Initialize the `godot-cpp` submodule:

```powershell
git submodule update --init --recursive
```

Windows builds require Visual Studio C++ Build Tools, Python with SCons, and
PostgreSQL development files. From an x64 Native Tools Command Prompt for
Visual Studio:

```cmd
set POSTGRESQL_PATH=C:\Program Files\PostgreSQL\19
python -m SCons -C native/postgres platform=windows target=template_debug arch=x86_64
```

Linux builds require a C++ toolchain, SCons, `pkg-config`, and `libpq-dev`:

```sh
python3 -m SCons -C native/postgres platform=linux target=template_debug arch=x86_64
```

The PostgreSQL spike test uses a local database at `127.0.0.1:55432`; run it
against a temporary local cluster rather than changing the authentication of a
shared PostgreSQL service. The character repository test applies migrations
and writes a fixture, so run both tests only against a disposable test cluster:

```powershell
$env:PATH = "$env:POSTGRESQL_PATH\bin;$env:PATH"
& 'D:\Dev\Godot_v4.7.2-stable_win64.exe' --headless --path . --script tests/integration/postgres_driver_spike.gd
& 'D:\Dev\Godot_v4.7.2-stable_win64.exe' --headless --path . --script tests/integration/postgres_character_repository_test.gd
```

On Linux, with the temporary cluster listening on the same address and port:

```sh
godot --headless --path /path/to/mmorpg3D --script res://tests/integration/postgres_character_repository_test.gd
```

`tests/integration/sql/repository_statements.sql` holds the same statements as
the character repository, so the SQL can be checked against a live PostgreSQL
with `psql -f` even when the GDExtension cannot be loaded:

```sh
psql -h 127.0.0.1 -p 55432 -U postgres -d mmorpg3d \
  -v ON_ERROR_STOP=1 \
  -f server/db/migrations/0001_create_characters.sql \
  -f server/db/migrations/0002_character_progress.sql \
  -f tests/integration/sql/repository_statements.sql
```

To check that the extension loads and reports an unavailable database without
starting PostgreSQL:

```powershell
$env:PATH = "D:\Dev\mmorpg3D\native\postgres\bin\windows;$env:PATH"
& 'D:\Dev\Godot_v4.7.2-stable_win64.exe' --headless --path . --script tests/integration/postgres_driver_load_test.gd
```
