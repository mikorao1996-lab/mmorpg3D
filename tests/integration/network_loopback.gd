extends Node

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")
const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")

var listener: RefCounted
var server_world: RefCounted
var valid_client: ClientNet
var second_valid_client: ClientNet
var mismatch_client: ENetMultiplayerPeer
var elapsed_seconds: float = 0.0
var mismatch_sent: bool = false
var movement_sent: bool = false
var valid_accepted: bool = false
var second_valid_accepted: bool = false
var mismatch_rejected: bool = false
var saw_two_players: bool = false
var local_position_seen: bool = false
var local_player_moved: bool = false
var valid_player_id: int = 0
var initial_local_position: Vector3 = Vector3.ZERO
var _simulation_config: Dictionary = {}


func _ready() -> void:
	_simulation_config = SimulationConfigType.load_config()
	if _simulation_config.is_empty():
		get_tree().quit(1)
		return

	listener = load("res://server/net/server_listener.gd").new()
	if not listener.start(7790):
		get_tree().quit(1)
		return
	server_world = load("res://server/world/server_world.gd").new(_simulation_config)
	listener.player_authenticated.connect(server_world.add_player)
	listener.player_disconnected.connect(server_world.remove_player)
	listener.movement_intent.connect(_on_movement_intent)

	valid_client = ClientNet.new()
	add_child(valid_client)
	valid_client.hello_accepted.connect(_on_valid_hello_accepted)
	valid_client.world_snapshot.connect(_on_valid_world_snapshot)
	var valid_error: Error = valid_client.connect_to_server("127.0.0.1", 7790)
	if valid_error != OK:
		push_error("Failed to connect primary integration client: %s" % valid_error)
		get_tree().quit(1)
		return

	second_valid_client = ClientNet.new()
	add_child(second_valid_client)
	second_valid_client.hello_accepted.connect(_on_second_hello_accepted)
	second_valid_client.world_snapshot.connect(_on_second_world_snapshot)
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
		listener.broadcast_world_snapshot(server_world.create_snapshot())

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

	poll_mismatch_client()
	if (
		valid_accepted
		and second_valid_accepted
		and mismatch_rejected
		and saw_two_players
		and local_player_moved
	):
		print("WORLD_LOOPBACK_OK")
		get_tree().quit(0)
	elif elapsed_seconds > 5.0:
		print("WORLD_TEST_STATE accepted=%s second_accepted=%s rejected=%s two_players=%s moved=%s movement_sent=%s player_id=%d" % [
			valid_accepted,
			second_valid_accepted,
			mismatch_rejected,
			saw_two_players,
			local_player_moved,
			movement_sent,
			valid_player_id,
		])
		push_error("WORLD_LOOPBACK_TIMEOUT")
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


func _on_second_hello_accepted(protocol: int, _player_id: int) -> void:
	second_valid_accepted = protocol == ProtocolConstantsType.PROTOCOL_VERSION


func _on_valid_world_snapshot(snapshot: Dictionary) -> void:
	_process_world_snapshot(snapshot, true)


func _on_second_world_snapshot(snapshot: Dictionary) -> void:
	_process_world_snapshot(snapshot, false)


func _process_world_snapshot(snapshot: Dictionary, track_local_player: bool) -> void:
	var player_states: Variant = snapshot.get("players", null)
	if not player_states is Array:
		return
	saw_two_players = saw_two_players or player_states.size() >= 2
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
