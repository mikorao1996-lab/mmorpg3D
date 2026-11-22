class_name ServerListener
extends RefCounted

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")
const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")

var peer: ENetMultiplayerPeer
var sessions: Dictionary = {}
var started: bool = false


func start(port: int = ProtocolConstantsType.SERVER_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, 50, 2, 0, 0)
	if error != OK:
		push_error("Failed to start ENet server: %s" % error)
		return false
	started = true
	print("[INFO] ENet server listening on port %d" % port)
	return true


func poll() -> void:
	if not started:
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var peer_id: int = peer.get_packet_peer()
		var channel: int = peer.get_packet_channel()
		var packet: PackedByteArray = peer.get_packet()
		handle_packet(peer_id, channel, packet)

	var now_ms: int = Time.get_ticks_msec()
	var timed_out_peers: Array[int] = []
	for peer_id: int in sessions:
		var session: RefCounted = sessions[peer_id]
		if session.is_handshake_timed_out(now_ms):
			timed_out_peers.append(peer_id)
	for peer_id: int in timed_out_peers:
		var timeout_session: RefCounted = sessions[peer_id]
		timeout_session.peer.peer_disconnect_now(0)
		sessions.erase(peer_id)
		push_warning("Handshake timeout for peer %d" % peer_id)


func handle_packet(peer_id: int, channel: int, packet: PackedByteArray) -> void:
	if not sessions.has(peer_id):
		var packet_peer: ENetPacketPeer = peer.get_peer(peer_id)
		if packet_peer == null:
			return
		sessions[peer_id] = load("res://server/net/server_session.gd").new(packet_peer)

	var session: RefCounted = sessions[peer_id]
	if channel != ProtocolConstantsType.EVENT_CHANNEL:
		push_warning("Rejected packet on invalid channel from peer %d" % peer_id)
		return
	if not session.accept_packet(Time.get_ticks_msec()):
		push_warning("Rate limit exceeded for peer %d" % peer_id)
		return

	var envelope: Dictionary = PacketCodecType.decode(packet)
	if envelope.is_empty():
		return

	var opcode: int = envelope["opcode"]
	var payload: Dictionary = envelope["payload"]
	if opcode == ProtocolConstantsType.OPCODE_HELLO:
		handle_hello(session, payload)
	elif opcode == ProtocolConstantsType.OPCODE_KEEPALIVE:
		if session.authenticated:
			session.send(ProtocolConstantsType.OPCODE_KEEPALIVE_ACK)
		else:
			push_warning("Keepalive before authentication from peer %d" % peer_id)
	else:
		push_warning("Unknown opcode %d from peer %d" % [opcode, peer_id])


func handle_hello(session: RefCounted, payload: Dictionary) -> void:
	var client_version: Variant = payload.get("protocol", -1)
	if client_version is not int or client_version != ProtocolConstantsType.PROTOCOL_VERSION:
		session.send(ProtocolConstantsType.OPCODE_HELLO_REJECTED, {"reason": "protocol_mismatch"})
		push_warning("Rejected protocol mismatch")
		return

	session.authenticated = true
	session.send(ProtocolConstantsType.OPCODE_HELLO_ACCEPTED, {
		"protocol": ProtocolConstantsType.PROTOCOL_VERSION,
	})
