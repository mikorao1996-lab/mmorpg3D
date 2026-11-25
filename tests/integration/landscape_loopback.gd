extends Node

## End-to-end check for the landscape and the interface.
##
## The test loads the production client scene against an in-process server and
## checks that the terrain and the props are built, that the nameplates of the
## players show the level and the bars, and that the panels can be hidden.

var listener: RefCounted
var server_world: RefCounted
var client_scene: Node = null
var elapsed_seconds: float = 0.0
var checked_landscape: bool = false
var checked_nameplate: bool = false
var checked_panels: bool = false

const TEST_PORT: int = 7795


func _ready() -> void:
	var simulation_config: Dictionary = load(
		"res://shared/data/simulation_config.gd"
	).load_config()
	var game_data_registry: Dictionary = load(
		"res://shared/data/game_data_registry.gd"
	).load_all()
	if simulation_config.is_empty() or game_data_registry.is_empty():
		get_tree().quit(1)
		return

	listener = load("res://server/net/server_listener.gd").new()
	if not listener.start(TEST_PORT):
		get_tree().quit(1)
		return
	server_world = load("res://server/world/server_world.gd").new(
		simulation_config,
		game_data_registry,
	)
	listener.player_authenticated.connect(server_world.add_player)
	listener.player_disconnected.connect(server_world.remove_player)

	OS.set_environment("MMORPG3D_SERVER_PORT", str(TEST_PORT))
	client_scene = load("res://client/scenes/main.tscn").instantiate()
	add_child(client_scene)


func _process(delta: float) -> void:
	elapsed_seconds += delta
	listener.poll()
	if server_world.advance(delta):
		listener.broadcast_world_snapshots(server_world.create_snapshots())

	if not checked_landscape:
		checked_landscape = _check_landscape()
		if not checked_landscape:
			return
	if not checked_nameplate:
		checked_nameplate = _check_nameplate()
		if not checked_nameplate:
			return
	if not checked_panels:
		checked_panels = _check_panels()
		if not checked_panels:
			return
	print("LANDSCAPE_LOOPBACK_OK")
	get_tree().quit(0)


## Checks the generated terrain and the generated props.
func _check_landscape() -> bool:
	var terrain: MeshInstance3D = client_scene.get_node_or_null("Terrain")
	if terrain == null or terrain.mesh == null:
		print("LANDSCAPE_STATE: waiting for the terrain")
		return false
	if terrain.mesh.get_surface_count() != 1:
		_fail("The terrain mesh does not have a single surface")
		return false
	if terrain.mesh.surface_get_array_len(0) <= 0:
		_fail("The terrain mesh is empty")
		return false
	var props: MeshInstance3D = client_scene.get_node_or_null("Props")
	if props == null or props.mesh == null:
		_fail("The client did not build the props")
		return false
	if props.mesh.surface_get_array_len(0) <= 0:
		_fail("The props mesh is empty")
		return false
	if client_scene.get_node_or_null("Ground") != null:
		_fail("The flat ground of the scene was not replaced by the terrain")
		return false
	return true


## Checks the nameplate of the local player.
func _check_nameplate() -> bool:
	var player_views: Dictionary = client_scene.get("_player_views")
	if player_views.is_empty():
		print("LANDSCAPE_STATE: waiting for the players")
		return false
	for player_id: Variant in player_views:
		var view: Node = player_views[player_id]
		var plate: Node = view.get_node_or_null("Nameplate")
		if plate == null:
			_fail("A player has no nameplate")
			return false
		if plate.get_node_or_null("LevelLabel") == null:
			_fail("The nameplate has no level label")
			return false
		if plate.get_node_or_null("HealthFill") == null:
			_fail("The nameplate has no health bar")
			return false
		if plate.get_node_or_null("ResourceFill") == null:
			_fail("The nameplate has no resource bar")
			return false
		var level_label: Label3D = plate.get_node("LevelLabel")
		if level_label.text.is_empty():
			_fail("The level label of the nameplate is empty")
			return false
	return true


## Checks that the inventory and the chat panel can be hidden.
func _check_panels() -> bool:
	var inventory_panel: PanelContainer = client_scene.get_node("InventoryCanvas/InventoryPanel")
	var chat_panel: PanelContainer = client_scene.get_node("ChatCanvas/ChatPanel")
	if not inventory_panel.visible:
		_fail("The inventory panel is hidden before the toggle")
		return false
	client_scene.call("_toggle_inventory_panel")
	if inventory_panel.visible:
		_fail("The inventory panel did not hide")
		return false
	client_scene.call("_toggle_inventory_panel")
	if not inventory_panel.visible:
		_fail("The inventory panel did not show again")
		return false
	client_scene.call("_toggle_chat_panel")
	if chat_panel.visible:
		_fail("The chat panel did not hide")
		return false
	client_scene.call("_toggle_chat_panel")
	if not chat_panel.visible:
		_fail("The chat panel did not show again")
		return false
	return true


## Ends the test with an error.
func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
