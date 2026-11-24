extends Node

const PROJECT_LOGGER: GDScript = preload("res://shared/logging/project_logger.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const DatabaseBootstrapType: GDScript = preload("res://server/db/database_bootstrap.gd")

var server_listener: RefCounted
var server_world: RefCounted
var database_connection: RefCounted
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

	var database_result: Dictionary = DatabaseBootstrapType.new().connect_and_migrate()
	if not bool(database_result.get("ok", false)):
		PROJECT_LOGGER.log_error(
			"Server database initialization failed: %s"
			% str(database_result.get("error", "Unknown database error.")),
		)
		get_tree().quit(2)
		return
	database_connection = database_result["connection"]
	PROJECT_LOGGER.log_info("PostgreSQL connection and migrations are ready")

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
	server_listener.loot_pickup_requested.connect(_on_loot_pickup_requested)
	server_listener.equip_item_requested.connect(_on_equip_item_requested)
	server_listener.unequip_item_requested.connect(_on_unequip_item_requested)
	server_listener.use_item_requested.connect(_on_use_item_requested)
	server_listener.npc_interact_requested.connect(_on_npc_interact_requested)
	if not server_listener.start():
		get_tree().quit(2)


func _exit_tree() -> void:
	if database_connection != null:
		database_connection.call("close_connection")
		database_connection = null


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


func _on_loot_pickup_requested(peer_id: int, drop_id: int) -> void:
	var result: Dictionary = server_world.pickup_loot(peer_id, drop_id)
	server_listener.send_loot_pickup_result(peer_id, result)


func _on_equip_item_requested(peer_id: int, item_id: String) -> void:
	var result: Dictionary = server_world.equip_item(peer_id, item_id)
	server_listener.send_equipment_result(peer_id, "equip", result)


func _on_unequip_item_requested(peer_id: int, slot_id: String) -> void:
	var result: Dictionary = server_world.unequip_item(peer_id, slot_id)
	server_listener.send_equipment_result(peer_id, "unequip", result)


func _on_use_item_requested(peer_id: int, item_id: String) -> void:
	var result: Dictionary = server_world.use_item(peer_id, item_id)
	server_listener.send_item_use_result(peer_id, result)


func _on_npc_interact_requested(
	peer_id: int,
	npc_id: String,
	action: String,
	quest_id: String,
) -> void:
	var result: Dictionary = server_world.interact_npc(peer_id, npc_id, action, quest_id)
	server_listener.send_npc_interact_result(peer_id, result)
