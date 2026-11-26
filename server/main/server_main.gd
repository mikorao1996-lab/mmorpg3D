extends Node

const PROJECT_LOGGER: GDScript = preload("res://shared/logging/project_logger.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const DatabaseBootstrapType: GDScript = preload("res://server/db/database_bootstrap.gd")
const CharacterSessionServiceType: GDScript = preload("res://server/systems/character_session_service.gd")

var server_listener: RefCounted
var server_world: RefCounted
var database_connection: RefCounted
var character_service: RefCounted
var game_data_registry: Dictionary = {}
var _character_ids: Dictionary = {}
var _autosave_accumulator: float = 0.0
var _autosave_interval_seconds: float = 30.0


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
	character_service = CharacterSessionServiceType.from_connection(
		database_connection,
		str((simulation_config["zone_ids"] as Array)[0]),
		str(simulation_config.get("player_class_id", "warrior")),
		Vector3.ZERO,
		int(simulation_config.get("starting_gold", 0)),
	)
	_autosave_interval_seconds = float(
		simulation_config.get("character_autosave_interval_seconds", 30.0)
	)
	server_listener.set_character_service(character_service)
	server_listener.player_authorized.connect(_on_player_authorized)
	server_listener.player_named.connect(_on_player_named)
	server_listener.player_disconnected.connect(_on_player_disconnected)
	server_listener.movement_intent.connect(_on_movement_intent)
	server_listener.zone_transfer_requested.connect(_on_zone_transfer_requested)
	server_listener.ability_cast_requested.connect(_on_ability_cast_requested)
	server_listener.loot_pickup_requested.connect(_on_loot_pickup_requested)
	server_listener.equip_item_requested.connect(_on_equip_item_requested)
	server_listener.unequip_item_requested.connect(_on_unequip_item_requested)
	server_listener.use_item_requested.connect(_on_use_item_requested)
	server_listener.npc_interact_requested.connect(_on_npc_interact_requested)
	server_listener.trade_requested.connect(_on_trade_requested)
	server_listener.chat_requested.connect(_on_chat_requested)
	server_listener.party_requested.connect(_on_party_requested)
	if not server_listener.start():
		get_tree().quit(2)


func _exit_tree() -> void:
	_save_all_characters()
	if database_connection != null:
		database_connection.call("close_connection")
		database_connection = null


func _process(delta: float) -> void:
	if server_listener != null:
		server_listener.poll()
	if server_world != null and server_world.advance(delta):
		server_listener.broadcast_world_snapshots(server_world.create_snapshots())
	_autosave_accumulator += delta
	if _autosave_accumulator >= _autosave_interval_seconds:
		_autosave_accumulator = 0.0
		_save_all_characters()


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


func _on_trade_requested(
	peer_id: int,
	npc_id: String,
	action: String,
	item_id: String,
	quantity: int,
) -> void:
	var result: Dictionary = server_world.trade(
		peer_id,
		npc_id,
		action,
		item_id,
		quantity,
	)
	server_listener.send_trade_result(peer_id, result)


func _on_player_named(peer_id: int, player_name: String) -> void:
	server_world.set_player_name(peer_id, player_name)


## Adds a player whose identity the server has resolved.
##
## The stored progress of the character is restored, so the player continues
## where the last session ended.
func _on_player_authorized(
	peer_id: int,
	character_id: String,
	restored_state: Dictionary,
) -> void:
	if not server_world.add_player_with_restored_state(peer_id, restored_state):
		push_error(
			"Could not restore the character %s for peer %d" % [character_id, peer_id]
		)
		server_world.add_player(peer_id)
	_character_ids[peer_id] = character_id
	_send_system_message("chat_system_player_joined", peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	# The peer that left the zone is no longer a valid recipient.
	_save_character(peer_id)
	_character_ids.erase(peer_id)
	_send_system_message("chat_system_player_left", peer_id, peer_id)
	server_world.remove_player(peer_id)


## Saves the progress of every character of an open session.
func _save_all_characters() -> void:
	for peer_id: Variant in _character_ids:
		_save_character(int(peer_id))


## Saves the progress of a single character.
func _save_character(peer_id: int) -> void:
	if not _character_ids.has(peer_id) or character_service == null:
		return
	var character_id: String = str(_character_ids[peer_id])
	var state: Dictionary = server_world.export_player_state(peer_id)
	if state.is_empty():
		return
	var save_result: Dictionary = character_service.call(
		"save_state",
		character_id,
		state,
	)
	if not bool(save_result.get("ok", false)):
		push_error(
			"Could not save the character %s: %s"
			% [character_id, str(save_result.get("error", "Unknown database error."))]
		)


## Sends a system message to every player of the zone of the peer.
func _send_system_message(
	system_key: String,
	peer_id: int,
	exclude_peer_id: int = -1,
) -> void:
	var system_message: Dictionary = server_world.build_system_message(system_key, peer_id)
	for recipient_id: int in system_message["recipients"]:
		if recipient_id == exclude_peer_id:
			continue
		server_listener.send_chat_message(recipient_id, system_message["message"])


func _on_chat_requested(peer_id: int, channel: String, text: String) -> void:
	var result: Dictionary = server_world.chat(peer_id, channel, text)
	if not bool(result["accepted"]):
		server_listener.send_chat_message(peer_id, {
			"channel": "system",
			"sender_peer_id": 0,
			"sender_name": "",
			"text": "",
			"system_key": "",
			"reason": str(result["reason"]),
		})
		return
	var message: Dictionary = result["message"]
	for recipient_id: int in result["recipients"]:
		server_listener.send_chat_message(recipient_id, message)


func _on_party_requested(
	peer_id: int,
	action: String,
	target_peer_id: int,
) -> void:
	var result: Dictionary = server_world.party_request(
		peer_id,
		action,
		target_peer_id,
	)
	server_listener.send_party_result(peer_id, result)
	for notification: Dictionary in result["notifications"]:
		server_listener.send_party_result(int(notification["peer_id"]), notification["result"])
	for chat_message: Dictionary in result["chat_messages"]:
		for recipient_id: int in chat_message["recipients"]:
			server_listener.send_chat_message(recipient_id, chat_message["message"])
