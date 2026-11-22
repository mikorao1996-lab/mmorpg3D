extends Node

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")
const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

var listener: RefCounted
var server_world: RefCounted
var valid_client: ClientNet
var second_valid_client: ClientNet
var mismatch_client: ENetMultiplayerPeer
var elapsed_seconds: float = 0.0
var mismatch_sent: bool = false
var movement_sent: bool = false
var zone_transfer_sent: bool = false
var valid_accepted: bool = false
var second_valid_accepted: bool = false
var mismatch_rejected: bool = false
var saw_two_players: bool = false
var local_position_seen: bool = false
var local_player_moved: bool = false
var zone_transfer_applied: bool = false
var zone_transfer_accepted: bool = false
var invalid_zone_request_sent: bool = false
var invalid_zone_rejected: bool = false
var primary_isolated_in_starter: bool = false
var second_isolated_in_dungeon: bool = false
var primary_cast_sent: bool = false
var primary_cast_accepted: bool = false
var cooldown_cast_sent: bool = false
var cooldown_rejected: bool = false
var heavy_strike_cast_sent: bool = false
var heavy_strike_cast_accepted: bool = false
var out_of_range_cast_sent: bool = false
var out_of_range_rejected: bool = false
var valid_player_id: int = 0
var second_player_id: int = 0
var initial_local_position: Vector3 = Vector3.ZERO
var _simulation_config: Dictionary = {}
var _game_data_registry: Dictionary = {}


func _ready() -> void:
	_simulation_config = SimulationConfigType.load_config()
	if _simulation_config.is_empty():
		get_tree().quit(1)
		return
	_game_data_registry = GameDataRegistryType.load_all()
	if _game_data_registry.is_empty():
		get_tree().quit(1)
		return

	listener = load("res://server/net/server_listener.gd").new()
	if not listener.start(7790):
		get_tree().quit(1)
		return
	server_world = load("res://server/world/server_world.gd").new(
		_simulation_config,
		_game_data_registry,
	)
	listener.player_authenticated.connect(server_world.add_player)
	listener.player_disconnected.connect(server_world.remove_player)
	listener.movement_intent.connect(_on_movement_intent)
	listener.zone_transfer_requested.connect(_on_zone_transfer_requested)
	listener.ability_cast_requested.connect(_on_ability_cast_requested)

	valid_client = ClientNet.new()
	add_child(valid_client)
	valid_client.hello_accepted.connect(_on_valid_hello_accepted)
	valid_client.world_snapshot.connect(_on_valid_world_snapshot)
	valid_client.ability_cast_completed.connect(_on_primary_ability_cast_completed)
	valid_client.ability_cast_completed.connect(_on_cooldown_cast_completed)
	valid_client.ability_cast_completed.connect(_on_heavy_strike_cast_completed)
	var valid_error: Error = valid_client.connect_to_server("127.0.0.1", 7790)
	if valid_error != OK:
		push_error("Failed to connect primary integration client: %s" % valid_error)
		get_tree().quit(1)
		return

	second_valid_client = ClientNet.new()
	add_child(second_valid_client)
	second_valid_client.hello_accepted.connect(_on_second_hello_accepted)
	second_valid_client.world_snapshot.connect(_on_second_world_snapshot)
	second_valid_client.zone_transfer_completed.connect(_on_zone_transfer_completed)
	second_valid_client.ability_cast_completed.connect(_on_out_of_range_cast_completed)
	var second_error: Error = second_valid_client.connect_to_server("127.0.0.1", 7790)
	if second_error != OK:
		push_error("Failed to connect second integration client: %s" % second_error)
		get_tree().quit(1)
		return

	mismatch_client = create_raw_client()
	if mismatch_client == null:
		get_tree().quit(1)


func _process(delta: float) -> void:
	elapsed_seconds += delta
	listener.poll()
	mismatch_client.poll()
	if server_world.advance(delta):
		listener.broadcast_world_snapshots(server_world.create_snapshots())

	if (
		not mismatch_sent
		and mismatch_client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	):
		send_mismatched_hello(mismatch_client)
		mismatch_sent = true

	if valid_accepted and not movement_sent:
		var movement_error: Error = valid_client.send_movement_intent(Vector2.RIGHT)
		if movement_error != OK:
			push_error("Failed to send loopback movement intent: %s" % movement_error)
			get_tree().quit(1)
			return
		movement_sent = true

	if valid_accepted and not primary_cast_sent:
		var cast_error: Error = valid_client.request_ability_cast(
			"starter_slash",
			"training_slime",
		)
		if cast_error != OK:
			push_error("Failed to send loopback ability cast: %s" % cast_error)
			get_tree().quit(1)
			return
		primary_cast_sent = true

	if primary_cast_accepted and not cooldown_cast_sent:
		var cooldown_error: Error = valid_client.request_ability_cast(
			"starter_slash",
			"training_slime",
		)
		if cooldown_error != OK:
			push_error("Failed to send loopback cooldown cast: %s" % cooldown_error)
			get_tree().quit(1)
			return
		cooldown_cast_sent = true

	if primary_cast_accepted and not heavy_strike_cast_sent:
		var heavy_strike_error: Error = valid_client.request_ability_cast(
			"heavy_strike",
			"training_slime",
		)
		if heavy_strike_error != OK:
			push_error("Failed to send loopback heavy strike: %s" % heavy_strike_error)
			get_tree().quit(1)
			return
		heavy_strike_cast_sent = true

	if second_valid_accepted and not out_of_range_cast_sent:
		var range_error: Error = second_valid_client.request_ability_cast(
			"starter_slash",
			"training_slime",
		)
		if range_error != OK:
			push_error("Failed to send loopback out-of-range cast: %s" % range_error)
			get_tree().quit(1)
			return
		out_of_range_cast_sent = true

	if (
		valid_accepted
		and second_valid_accepted
		and saw_two_players
		and local_player_moved
		and not zone_transfer_sent
	):
		var transfer_error: Error = second_valid_client.request_zone_transfer("dungeon")
		if transfer_error != OK:
			push_error("Failed to request loopback zone transfer: %s" % transfer_error)
			get_tree().quit(1)
			return
		zone_transfer_sent = true

	if (
		zone_transfer_accepted
		and second_isolated_in_dungeon
		and not invalid_zone_request_sent
	):
		var invalid_transfer_error: Error = second_valid_client.request_zone_transfer("missing")
		if invalid_transfer_error != OK:
			push_error("Failed to request invalid loopback zone transfer")
			get_tree().quit(1)
			return
		invalid_zone_request_sent = true

	poll_mismatch_client()
	if (
		valid_accepted
		and second_valid_accepted
		and mismatch_rejected
		and saw_two_players
		and local_player_moved
		and zone_transfer_applied
		and zone_transfer_accepted
		and invalid_zone_rejected
		and primary_cast_accepted
		and cooldown_rejected
		and heavy_strike_cast_accepted
		and out_of_range_rejected
		and primary_isolated_in_starter
		and second_isolated_in_dungeon
	):
		print("COMBAT_LOOPBACK_OK")
		get_tree().quit(0)
	elif elapsed_seconds > 5.0:
		print("ZONE_TEST_STATE accepted=%s second_accepted=%s rejected=%s two_players=%s moved=%s movement_sent=%s zone_sent=%s zone_applied=%s zone_accepted=%s invalid_zone=%s combat=%s cooldown=%s heavy=%s out_of_range=%s isolated=%s/%s player_id=%d second_player_id=%d" % [
			valid_accepted,
			second_valid_accepted,
			mismatch_rejected,
			saw_two_players,
			local_player_moved,
			movement_sent,
			zone_transfer_sent,
			zone_transfer_applied,
			zone_transfer_accepted,
			invalid_zone_rejected,
			primary_cast_accepted,
			cooldown_rejected,
			heavy_strike_cast_accepted,
			out_of_range_rejected,
			primary_isolated_in_starter,
			second_isolated_in_dungeon,
			valid_player_id,
			second_player_id,
		])
		push_error("ZONE_LOOPBACK_TIMEOUT")
		get_tree().quit(1)


func create_raw_client() -> ENetMultiplayerPeer:
	var client_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = client_peer.create_client("127.0.0.1", 7790, 2)
	if error != OK:
		push_error("Failed to create mismatch integration client")
		return null
	return client_peer


func send_mismatched_hello(client_peer: ENetMultiplayerPeer) -> void:
	var server_peer: ENetPacketPeer = client_peer.get_peer(1)
	if server_peer == null:
		return
	var packet: PackedByteArray = PacketCodecType.encode(
		ProtocolConstantsType.OPCODE_HELLO,
		{"protocol": ProtocolConstantsType.PROTOCOL_VERSION + 1},
	)
	server_peer.send(
		ProtocolConstantsType.to_transport_channel(ProtocolConstantsType.EVENT_CHANNEL),
		packet,
		ProtocolConstantsType.PACKET_FLAG_RELIABLE,
	)


func poll_mismatch_client() -> void:
	while mismatch_client.get_available_packet_count() > 0:
		var channel: int = mismatch_client.get_packet_channel()
		var packet: PackedByteArray = mismatch_client.get_packet()
		if channel != ProtocolConstantsType.EVENT_CHANNEL:
			continue
		var envelope: Dictionary = PacketCodecType.decode(packet)
		if not envelope.is_empty() \
				and envelope["opcode"] == ProtocolConstantsType.OPCODE_HELLO_REJECTED:
			mismatch_rejected = true


func _on_valid_hello_accepted(protocol: int, player_id: int) -> void:
	valid_accepted = protocol == ProtocolConstantsType.PROTOCOL_VERSION
	valid_player_id = player_id


func _on_second_hello_accepted(protocol: int, player_id: int) -> void:
	second_valid_accepted = protocol == ProtocolConstantsType.PROTOCOL_VERSION
	second_player_id = player_id


func _on_valid_world_snapshot(snapshot: Dictionary) -> void:
	_process_world_snapshot(snapshot, true)


func _on_second_world_snapshot(snapshot: Dictionary) -> void:
	_process_world_snapshot(snapshot, false)


func _process_world_snapshot(snapshot: Dictionary, track_local_player: bool) -> void:
	var player_states: Variant = snapshot.get("players", null)
	if not player_states is Array:
		return
	saw_two_players = saw_two_players or player_states.size() >= 2
	if zone_transfer_applied and track_local_player:
		primary_isolated_in_starter = (
			snapshot.get("zone_id") == "starter"
			and player_states.size() == 1
			and _snapshot_has_player(player_states, valid_player_id)
		)
	elif zone_transfer_applied:
		second_isolated_in_dungeon = (
			snapshot.get("zone_id") == "dungeon"
			and player_states.size() == 1
			and _snapshot_has_player(player_states, second_player_id)
		)
	if not track_local_player:
		return

	for state: Variant in player_states:
		if not state is Array or state.size() != 2:
			continue
		if state[0] != valid_player_id or not state[1] is Vector3:
			continue
		var current_position: Vector3 = state[1]
		if not local_position_seen:
			initial_local_position = current_position
			local_position_seen = true
			continue
		var movement_threshold: float = (
			float(_simulation_config["movement_speed"])
			* float(_simulation_config["simulation_step_seconds"])
		)
		local_player_moved = (
			current_position.distance_to(initial_local_position) > movement_threshold
		)


func _on_movement_intent(peer_id: int, input_direction: Vector2) -> void:
	if not server_world.set_input_direction(peer_id, input_direction):
		push_error("Loopback world rejected valid movement intent")


func _on_zone_transfer_requested(peer_id: int, zone_id: String) -> void:
	var accepted: bool = server_world.move_player_to_zone(peer_id, zone_id)
	var reason: String = "" if accepted else "unknown_zone"
	listener.send_zone_transfer_result(peer_id, zone_id, accepted, reason)
	if zone_id == "dungeon":
		if not accepted:
			push_error("Loopback world rejected transfer to configured zone")
			get_tree().quit(1)
			return
		zone_transfer_applied = true
	elif zone_id == "missing" and accepted:
		push_error("Loopback world accepted transfer to an unconfigured zone")
		get_tree().quit(1)


func _on_ability_cast_requested(peer_id: int, ability_id: String, target_mob_id: String) -> void:
	var result: Dictionary = server_world.cast_ability(peer_id, ability_id, target_mob_id)
	listener.send_ability_cast_result(peer_id, result)


func _on_primary_ability_cast_completed(
	accepted: bool,
	reason: String,
	mob_id: String,
	health: float,
	max_health: float,
) -> void:
	if accepted:
		if (
			mob_id == "training_slime"
			and is_equal_approx(health, 22.0)
			and is_equal_approx(max_health, 30.0)
		):
			primary_cast_accepted = true
	elif reason != "cooldown":
		push_error("Primary loopback ability cast was rejected: %s" % reason)


func _on_out_of_range_cast_completed(
	accepted: bool,
	reason: String,
	_mob_id: String,
	_health: float,
	_max_health: float,
) -> void:
	out_of_range_rejected = not accepted and reason == "out_of_range"


func _on_cooldown_cast_completed(
	accepted: bool,
	reason: String,
	_mob_id: String,
	_health: float,
	_max_health: float,
) -> void:
	if not accepted and reason == "cooldown":
		cooldown_rejected = true


func _on_heavy_strike_cast_completed(
	accepted: bool,
	reason: String,
	mob_id: String,
	health: float,
	max_health: float,
) -> void:
	if accepted:
		heavy_strike_cast_accepted = (
			mob_id == "training_slime"
			and is_equal_approx(health, 7.0)
			and is_equal_approx(max_health, 30.0)
		)
	elif reason != "cooldown":
		push_error("Loopback heavy strike was rejected: %s" % reason)


func _on_zone_transfer_completed(zone_id: String, accepted: bool, reason: String) -> void:
	if zone_id == "dungeon":
		zone_transfer_accepted = accepted
	elif zone_id == "missing":
		invalid_zone_rejected = not accepted and reason == "unknown_zone"


func _snapshot_has_player(player_states: Array, player_id: int) -> bool:
	for player_state: Variant in player_states:
		if player_state is Array and player_state.size() == 2 and player_state[0] == player_id:
			return true
	return false
