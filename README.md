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