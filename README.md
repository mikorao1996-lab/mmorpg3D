# mmorpg3D

Godot 4 MMORPG vertical-slice project.

## Requirements

- Godot 4.3 or newer
- Windows for the editor/client
- Linux/Docker for the server target

## Client

```powershell
godot --path D:\Dev\mmorpg3D --editor
```

The main client scene is `client/scenes/main.tscn`.

## Headless server

```powershell
godot --headless --path D:\Dev\mmorpg3D --script server/main/server_bootstrap.gd
```

The server currently provides the bootstrap and no gameplay yet.

## Unit checks

```powershell
godot --headless --path D:\Dev\mmorpg3D --script tests/unit/run_unit_tests.gd
```