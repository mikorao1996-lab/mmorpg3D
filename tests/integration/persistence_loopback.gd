extends Node

## Loopback check of the persistence of a character.
##
## The scenario plays the whole life of a character: the client connects and
## receives an identity, it makes progress, it leaves, and it comes back with
## the same identity. The progress has to survive the round trip, and a client
## with a foreign secret has to stay outside.

const ServerListenerType: GDScript = preload("res://server/net/server_listener.gd")
const ServerWorldType: GDScript = preload("res://server/world/server_world.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const CharacterSessionServiceType: GDScript = preload("res://server/systems/character_session_service.gd")
const InMemoryRepositoryType: GDScript = preload("res://tests/support/in_memory_character_repository.gd")
const ClientNetType: GDScript = preload("res://client/scripts/client_net.gd")
const CharacterIdentityType: GDScript = preload("res://client/scripts/character_identity.gd")

const PORT: int = 7797
const IDENTITY_PATH: String = "user://persistence_loopback_identity.json"
const FOREIGN_IDENTITY_PATH: String = "user://persistence_loopback_foreign_identity.json"
const TIMEOUT_SECONDS: float = 12.0
const TARGET_MOB_ID: String = "training_slime"
const STARTING_GOLD: int = 100
const SLIME_GOLD: int = 4
const SLIME_EXPERIENCE: int = 25

var _listener: RefCounted
var _world: RefCounted
var _repository: RefCounted
var _service: RefCounted
var _client: Node
var _character_ids: Dictionary = {}
var _snapshots: Array = []
var _peer_id: int = 0
var _hello_accepted: bool = false
var _foreign_rejection_reason: String = ""
var _loot_result_text: String = "no result"


func _ready() -> void:
	_run()


## Drives the server while the scenario waits for the network.
func _process(delta: float) -> void:
	if _listener != null:
		_listener.poll()
	if _world != null and _world.advance(delta):
		_listener.broadcast_world_snapshots(_world.create_snapshots())


func _run() -> void:
	_cleanup_identity_files()
	var config: Dictionary = SimulationConfigType.load_config()
	if config.is_empty():
		_fail("The simulation configuration is missing")
		return
	var game_data_registry: Dictionary = GameDataRegistryType.load_all()
	if game_data_registry.is_empty():
		_fail("The game data registries are missing")
		return
	# The slime stands next to the spawn point with a single hit of health, so
	# the first player reaches it with a slash.
	game_data_registry["mobs"][TARGET_MOB_ID]["health"] = 1.0
	game_data_registry["mobs"][TARGET_MOB_ID]["respawn_seconds"] = 0.3
	game_data_registry["mobs"][TARGET_MOB_ID]["aggro_range"] = 0.0
	game_data_registry["mobs"][TARGET_MOB_ID]["spawn_positions"] = [[0.0, 0.0, -2.0]]
	game_data_registry["abilities"]["starter_slash"]["cooldown_seconds"] = 0.0
	game_data_registry["abilities"]["starter_slash"]["resource_cost"] = 0.0

	_world = ServerWorldType.new(config, game_data_registry)
	_repository = InMemoryRepositoryType.new()
	_service = CharacterSessionServiceType.new(
		_repository,
		str((config["zone_ids"] as Array)[0]),
		str(config.get("player_class_id", "warrior")),
		Vector3.ZERO,
		int(config.get("starting_gold", STARTING_GOLD)),
	)

	_listener = ServerListenerType.new()
	_listener.set_character_service(_service)
	_listener.player_authorized.connect(_on_player_authorized)
	_listener.player_disconnected.connect(_on_player_disconnected)
	_listener.movement_intent.connect(_on_movement_intent)
	_listener.ability_cast_requested.connect(_on_ability_cast_requested)
	_listener.loot_pickup_requested.connect(_on_loot_pickup_requested)
	if not _listener.start(PORT):
		_fail("The server did not start")
		return

	_client = ClientNetType.new()
	add_child(_client)
	_client.identity_path = IDENTITY_PATH
	_client.world_snapshot.connect(_on_world_snapshot)
	_client.hello_accepted.connect(_on_hello_accepted)
	_client.hello_rejected.connect(_on_hello_rejected)
	_client.loot_pickup_completed.connect(_on_loot_pickup_completed)
	var connect_error: Error = _client.connect_to_server("127.0.0.1", PORT)
	if connect_error != OK:
		_fail("The client did not connect: %s" % connect_error)
		return

	if not await _wait_for(func() -> bool: return _hello_accepted):
		_fail("The client did not receive the accepted handshake")
		return
	await _wait_seconds(0.3)
	var identity: RefCounted = _client.character_identity
	var character_id: String = str(identity.call("get", "character_id"))
	var character_token: String = str(identity.call("get", "character_token"))
	if character_id.is_empty() or character_token.is_empty():
		_fail("The issued identity of the character is incomplete")
		return

	# The character makes progress: the slime dies next to the spawn point.
	var cast_result: Dictionary = _world.cast_ability(_peer_id, "starter_slash", TARGET_MOB_ID)
	if not bool(cast_result.get("accepted", false)):
		_fail("The slash of the character failed: %s" % str(cast_result.get("reason", "")))
		return
	await _wait_seconds(0.5)
	var progress_gold: int = _latest_gold()
	if progress_gold != STARTING_GOLD + SLIME_GOLD:
		_fail("The character did not receive the gold of the kill: %d" % progress_gold)
		return
	var drop_id: int = _latest_drop_id()
	if drop_id < 0:
		_fail("The kill did not leave a drop")
		return
	_client.request_loot_pickup(drop_id)
	await _wait_seconds(0.5)
	if (_latest_inventory() as Array).is_empty():
		_fail("The character did not pick up the loot: %s" % _loot_result_text)
		return

	# The client leaves, and the server stores the progress.
	_client.disconnect_from_server()
	if not await _wait_for(func() -> bool: return _character_ids.is_empty()):
		_fail("The server did not store the character of the client")
		return
	var stored: Dictionary = _repository.characters.get(character_id, {})
	if int(stored.get("gold", 0)) != STARTING_GOLD + SLIME_GOLD:
		_fail("The stored character does not hold the progress: %s" % str(stored.get("gold", 0)))
		return
	if int(stored.get("experience", 0)) != SLIME_EXPERIENCE:
		_fail("The stored character does not hold the experience")
		return
	if (stored.get("inventory", []) as Array).is_empty():
		_fail("The stored character does not hold the loot")
		return

	# The client comes back with the same identity.
	var returning_client: Node = ClientNetType.new()
	add_child(returning_client)
	returning_client.identity_path = IDENTITY_PATH
	var returning_state: Dictionary = {"hello": false, "snapshots": []}
	returning_client.hello_accepted.connect(
		func(_protocol: int, _player_id: int) -> void: returning_state["hello"] = true
	)
	returning_client.world_snapshot.connect(
		func(snapshot: Dictionary) -> void: (returning_state["snapshots"] as Array).append(snapshot)
	)
	var returning_error: Error = returning_client.connect_to_server("127.0.0.1", PORT)
	if returning_error != OK:
		_fail("The returning client did not connect: %s" % returning_error)
		return
	if not await _wait_for(func() -> bool: return bool(returning_state["hello"])):
		_fail("The returning client did not receive the accepted handshake")
		return
	await _wait_seconds(0.5)
	var returning_snapshots: Array = returning_state["snapshots"]
	if returning_snapshots.is_empty():
		_fail("The returning client did not receive a snapshot")
		return
	var returning_snapshot: Dictionary = returning_snapshots[0]
	if int(returning_snapshot.get("gold", 0)) != STARTING_GOLD + SLIME_GOLD:
		_fail("The restored character did not keep the gold: %s" % str(returning_snapshot.get("gold", 0)))
		return
	var returning_players: Array = returning_snapshot.get("players", [])
	if returning_players.is_empty():
		_fail("The restored snapshot has no player")
		return
	# A player entry is
	# [peer_id, position, health, max_health, level, experience, ...].
	var returning_player: Array = returning_players[0]
	if int(returning_player[5]) != SLIME_EXPERIENCE:
		_fail("The restored character did not keep the experience")
		return
	if (returning_snapshot.get("inventory", []) as Array).is_empty():
		_fail("The restored character did not keep the loot")
		return
	returning_client.disconnect_from_server()

	# A client with the identifier of the character but a foreign secret stays
	# outside.
	var foreign_client: Node = ClientNetType.new()
	add_child(foreign_client)
	foreign_client.identity_path = FOREIGN_IDENTITY_PATH
	foreign_client.hello_rejected.connect(
		func(reason: String) -> void: _foreign_rejection_reason = reason
	)
	var foreign_identity: RefCounted = CharacterIdentityType.new(FOREIGN_IDENTITY_PATH)
	foreign_identity.call("store", character_id, "a-secret-of-another-client")
	foreign_client.character_identity = foreign_identity
	var foreign_error: Error = foreign_client.connect_to_server("127.0.0.1", PORT)
	if foreign_error != OK:
		_fail("The foreign client did not connect: %s" % foreign_error)
		return
	if not await _wait_for(func() -> bool: return not _foreign_rejection_reason.is_empty()):
		_fail("The foreign client was not rejected")
		return
	if _foreign_rejection_reason != "identity_mismatch":
		_fail("The foreign client was rejected for the wrong reason: %s" % _foreign_rejection_reason)
		return
	foreign_client.disconnect_from_server()

	_cleanup_identity_files()
	print("PERSISTENCE_LOOPBACK_OK")
	get_tree().quit(0)


## Restores a character into the world and remembers which peer owns it.
func _on_player_authorized(
	peer_id: int,
	character_id: String,
	restored_state: Dictionary,
) -> void:
	if not _world.add_player_with_restored_state(peer_id, restored_state):
		_fail("The world did not restore the character")
		return
	_character_ids[peer_id] = character_id


## Stores the progress of a character that leaves the session.
func _on_player_disconnected(peer_id: int) -> void:
	if not _character_ids.has(peer_id):
		return
	var state: Dictionary = _world.export_player_state(peer_id)
	if not state.is_empty():
		_service.call("save_state", str(_character_ids[peer_id]), state)
	_character_ids.erase(peer_id)
	_world.remove_player(peer_id)


func _on_world_snapshot(snapshot: Dictionary) -> void:
	_snapshots.append(snapshot)


func _on_hello_accepted(_protocol: int, player_id: int) -> void:
	_hello_accepted = true
	_peer_id = player_id


func _on_loot_pickup_completed(accepted: bool, reason: String, item_id: String) -> void:
	_loot_result_text = "accepted=%s reason=%s item=%s" % [str(accepted), reason, item_id]


func _on_movement_intent(peer_id: int, input_direction: Vector2) -> void:
	_world.set_input_direction(peer_id, input_direction)


func _on_ability_cast_requested(
	peer_id: int,
	ability_id: String,
	target_mob_id: String,
) -> void:
	_listener.send_ability_cast_result(
		peer_id,
		_world.cast_ability(peer_id, ability_id, target_mob_id),
	)


func _on_loot_pickup_requested(peer_id: int, drop_id: int) -> void:
	_listener.send_loot_pickup_result(peer_id, _world.pickup_loot(peer_id, drop_id))


func _on_hello_rejected(_reason: String) -> void:
	_fail("The server rejected the handshake of the client")


## Waits until the condition holds or the timeout passes.
func _wait_for(condition: Callable) -> bool:
	var deadline_ms: int = Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


## Waits for the given time.
func _wait_seconds(seconds: float) -> void:
	var deadline_ms: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame


func _latest_snapshot() -> Dictionary:
	if _snapshots.is_empty():
		return {}
	return _snapshots[_snapshots.size() - 1]


func _latest_gold() -> int:
	return int(_latest_snapshot().get("gold", -1))


func _latest_inventory() -> Array:
	return _latest_snapshot().get("inventory", [])


## Returns the identifier of the drop of the last snapshot.
func _latest_drop_id() -> int:
	var drops: Array = _latest_snapshot().get("drops", [])
	if drops.is_empty():
		return -1
	return int((drops[0] as Array)[0])


func _cleanup_identity_files() -> void:
	for path: String in [IDENTITY_PATH, FOREIGN_IDENTITY_PATH]:
		var directory: DirAccess = DirAccess.open("user://")
		if directory != null:
			directory.remove(path.get_file())


func _fail(message: String) -> void:
	push_error(message)
	_cleanup_identity_files()
	get_tree().quit(1)
