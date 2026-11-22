extends Node

const PROJECT_LOGGER: GDScript = preload("res://shared/logging/project_logger.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

var server_listener: RefCounted
var server_world: RefCounted
var game_data_registry: Dictionary = {}


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

	game_data_registry = GameDataRegistryType.load_all()
	if game_data_registry.is_empty():
		get_tree().quit(2)
		return

	PROJECT_LOGGER.log_info("Server bootstrap initialized")
	server_listener = load("res://server/net/server_listener.gd").new()
	server_world = load("res://server/world/server_world.gd").new(
		simulation_config,
		game_data_registry,
	)
	server_listener.player_authenticated.connect(server_world.add_player)
	server_listener.player_disconnected.connect(server_world.remove_player)
	server_listener.movement_intent.connect(_on_movement_intent)
	server_listener.zone_transfer_requested.connect(_on_zone_transfer_requested)
	server_listener.ability_cast_requested.connect(_on_ability_cast_requested)
	if not server_listener.start():
		get_tree().quit(2)


func _process(delta: float) -> void:
	if server_listener != null:
		server_listener.poll()
	if server_world != null and server_world.advance(delta):
		server_listener.broadcast_world_snapshots(server_world.create_snapshots())


func _on_movement_intent(peer_id: int, input_direction: Vector2) -> void:
	if not server_world.set_input_direction(peer_id, input_direction):
		push_warning("Rejected movement intent outside configured limits from peer %d" % peer_id)


func _on_zone_transfer_requested(peer_id: int, zone_id: String) -> void:
	var accepted: bool = server_world.move_player_to_zone(peer_id, zone_id)
	var reason: String = "" if accepted else "unknown_zone"
	server_listener.send_zone_transfer_result(peer_id, zone_id, accepted, reason)
	if not accepted:
		push_warning("Rejected transfer for peer %d to unknown zone %s" % [peer_id, zone_id])


func _on_ability_cast_requested(peer_id: int, ability_id: String, target_mob_id: String) -> void:
	var result: Dictionary = server_world.cast_ability(peer_id, ability_id, target_mob_id)
	server_listener.send_ability_cast_result(peer_id, result)
