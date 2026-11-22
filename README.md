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

The server currently provides the network bootstrap on port `7788` and no gameplay yet.

## Unit checks

```powershell
godot --headless --path D:\Dev\mmorpg3D --script tests/unit/run_unit_tests.gd
```

## Network integration check

```powershell
$env:GODOT_BIN = "D:\Dev\Godot_v4.7.2-stable_win64.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File tests/integration/run_integration_tests.ps1
```

The loopback check starts one headless ENet server and two clients in-process.
It checks successful protocol negotiation and rejection of an unsupported version.