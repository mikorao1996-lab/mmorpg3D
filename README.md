# mmorpg3D

Godot 4 MMORPG vertical-slice project.

## Requirements

- Godot 4.7 or newer
- Windows for the editor/client
- Linux for the server target; Docker is optional

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

Both clients connect to `127.0.0.1:7788`. Use **WASD** to move; each client
shows both players, predicts its own movement, and interpolates server snapshots.
The server filters snapshots by the configured `interest_radius` (10 world units
by default) and always includes the observing player. Close the server with
`Ctrl+C` when finished. Client player bodies use `CharacterBody3D` as a platform
adapter: the shared movement simulation still determines target positions, while
remote players are interpolated from snapshots. Player collision layers are
disabled until collision rules are authoritative on the server.

Each zone contains the configured training slime. **SPACE** uses `starter_slash`
and **E** uses `heavy_strike` on the nearest living mob. **Q** uses
`guard_break`, **R** uses `whirlwind`, and **T** uses `second_wind`. The server
enforces target, range, damage/heal, resource cost, and separate cooldowns. Mob health is
shown in the status panel, and a defeated mob respawns after its configured
8 seconds. The slime pursues nearby players and attacks according to its mob
data; players have 100 health and respawn at their zone spawn after 3 seconds
if defeated. After a zone transfer, the entry position becomes that zone's
respawn point.

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
rejection, plus independent execution of the heavy strike while slash is on
cooldown.

## PostgreSQL driver spike

The native extension in `native/postgres` is a synchronous `libpq` adapter.
The server initializes the database and applies migrations before opening its
listener. The character repository is not yet wired to live sessions because
stable character identity and selection are not implemented.

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

To check that the extension loads and reports an unavailable database without
starting PostgreSQL:

```powershell
$env:PATH = "D:\Dev\mmorpg3D\native\postgres\bin\windows;$env:PATH"
& 'D:\Dev\Godot_v4.7.2-stable_win64.exe' --headless --path . --script tests/integration/postgres_driver_load_test.gd
```
