extends Node

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")
const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")

var listener: RefCounted
var valid_client: ENetMultiplayerPeer
var mismatch_client: ENetMultiplayerPeer
var elapsed_seconds: float = 0.0
var valid_sent: bool = false
var mismatch_sent: bool = false
var valid_accepted: bool = false
var mismatch_rejected: bool = false


func _ready() -> void:
	listener = load("res://server/net/server_listener.gd").new()
	if not listener.start(7790):
		get_tree().quit(1)
		return

	valid_client = create_client()
	mismatch_client = create_client()
	if valid_client == null or mismatch_client == null:
		get_tree().quit(1)
		return


func _process(delta: float) -> void:
	elapsed_seconds += delta
	listener.poll()
	valid_client.poll()
	mismatch_client.poll()

	if (
		elapsed_seconds >= 0.25
		and not valid_sent
		and valid_client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	):
		send_hello(valid_client, ProtocolConstantsType.PROTOCOL_VERSION)
		valid_sent = true
	if (
		elapsed_seconds >= 0.25
		and not mismatch_sent
		and mismatch_client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	):
		send_hello(mismatch_client, ProtocolConstantsType.PROTOCOL_VERSION + 1)
		mismatch_sent = true

	poll_client(valid_client, false)
	poll_client(mismatch_client, true)
	if valid_accepted and mismatch_rejected:
		print("NETWORK_LOOPBACK_OK")
		get_tree().quit(0)
	elif elapsed_seconds > 5.0:
		push_error("NETWORK_LOOPBACK_TIMEOUT")
		get_tree().quit(1)


func create_client() -> ENetMultiplayerPeer:
	var client_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = client_peer.create_client("127.0.0.1", 7790, 2)
	if error != OK:
		push_error("Failed to create loopback client")
		return null
	return client_peer


func send_hello(client_peer: ENetMultiplayerPeer, protocol: int) -> void:
	var server_peer: ENetPacketPeer = client_peer.get_peer(1)
	if server_peer == null:
		return
	var packet: PackedByteArray = PacketCodecType.encode(
		ProtocolConstantsType.OPCODE_HELLO,
		{"protocol": protocol},
	)
	server_peer.send(
		ProtocolConstantsType.to_transport_channel(ProtocolConstantsType.EVENT_CHANNEL),
		packet,
		ProtocolConstantsType.PACKET_FLAG_RELIABLE,
	)


func poll_client(client_peer: ENetMultiplayerPeer, mismatch: bool) -> void:
	while client_peer.get_available_packet_count() > 0:
		var channel: int = client_peer.get_packet_channel()
		var packet: PackedByteArray = client_peer.get_packet()
		if channel != ProtocolConstantsType.EVENT_CHANNEL:
			continue
		var envelope: Dictionary = PacketCodecType.decode(packet)
		if envelope.is_empty():
			continue
		var opcode: int = envelope["opcode"]
		if not mismatch and opcode == ProtocolConstantsType.OPCODE_HELLO_ACCEPTED:
			valid_accepted = true
		elif mismatch and opcode == ProtocolConstantsType.OPCODE_HELLO_REJECTED:
			mismatch_rejected = true
