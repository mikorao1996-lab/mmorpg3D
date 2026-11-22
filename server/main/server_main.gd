extends Node

const PROJECT_LOGGER: GDScript = preload("res://shared/logging/project_logger.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")

var server_listener: RefCounted
var server_world: RefCounted


func _ready() -> void:
	var display_server_name: String = DisplayServer.get_name().to_lower()
	if display_server_name != "headless":
		push_error("Server must be launched with --headless")
		get_tree().quit(2)
		return

	var simulation_config: Dictionary = SimulationConfigType.load_config()
	if simulation_config.is_empty():
		get_tree().quit(2)
		return

	PROJECT_LOGGER.log_info("Server bootstrap initialized")
	server_listener = load("res://server/net/server_listener.gd").new()
	server_world = load("res://server/world/server_world.gd").new(simulation_config)
	server_listener.player_authenticated.connect(server_world.add_player)
	server_listener.player_disconnected.connect(server_world.remove_player)
	server_listener.movement_intent.connect(_on_movement_intent)
	if not server_listener.start():
		get_tree().quit(2)


func _process(delta: float) -> void:
	if server_listener != null:
		server_listener.poll()
	if server_world != null and server_world.advance(delta):
		server_listener.broadcast_world_snapshot(server_world.create_snapshot())


func _on_movement_intent(peer_id: int, input_direction: Vector2) -> void:
	if not server_world.set_input_direction(peer_id, input_direction):
		push_warning("Rejected movement intent outside configured limits from peer %d" % peer_id)
