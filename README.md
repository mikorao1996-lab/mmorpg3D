# mmorpg3D

Godot 4 MMORPG vertical-slice project.

## Requirements

- Godot 4.7 or newer
- Windows for the editor/client
- Linux/Docker for the server target

## Client

```powershell
godot --path D:\Dev\mmorpg3D --editor
```

The main client scene is `client/scenes/main.tscn`.

## Headless server

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

Both clients connect to `127.0.0.1:7788`. Use **WASD** to move; each client
shows both players, predicts its own movement, and interpolates server snapshots.
The server filters snapshots by the configured `interest_radius` (10 world units
by default) and always includes the observing player. Close the server with
`Ctrl+C` when finished. Client player bodies use `CharacterBody3D` as a platform
adapter: the shared movement simulation still determines target positions, while
remote players are interpolated from snapshots. Player collision layers are
disabled until collision rules are authoritative on the server.

Each zone contains the configured training slime. Use **SPACE** to attack the
nearest living mob with `starter_slash`; the server enforces target, range,
damage, and the 1.2-second cooldown. Mob health is shown in the status panel,
and a defeated mob respawns after its configured 8 seconds.

The simulation config defines in-memory zones `starter` and `dungeon`; clients
start in the first configured zone. `ClientNet.request_zone_transfer(zone_id)`
is available for server-validated transfers, but there is not yet a portal or
zone-selection UI.

The server loads the versioned item, ability, mob, and quest JSON registries
before listening. Their initial schema and cross-reference rules are described
in [docs/data_registries.md](./docs/data_registries.md).

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
rejection.