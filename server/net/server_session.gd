class_name ServerSession
extends RefCounted

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")

var peer: ENetPacketPeer
var authenticated: bool = false
var connected_at_ms: int = Time.get_ticks_msec()
var last_packet_ms: int = connected_at_ms
var sequence_by_peer: int = 0


func _init(packet_peer: ENetPacketPeer) -> void:
	peer = packet_peer


func is_handshake_timed_out(now_ms: int) -> bool:
	if authenticated:
		return false
	return float(now_ms - connected_at_ms) / 1000.0 > ProtocolConstantsType.HANDSHAKE_TIMEOUT_SECONDS


func accept_packet(now_ms: int) -> bool:
	if now_ms - last_packet_ms > 1000:
		sequence_by_peer = 0
	last_packet_ms = now_ms
	sequence_by_peer += 1
	return sequence_by_peer <= ProtocolConstantsType.MAX_REQUESTS_PER_SECOND


func send(opcode: int, payload: Dictionary = {}) -> Error:
	const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")
	var channel: int = ProtocolConstantsType.EVENT_CHANNEL
	var packet: PackedByteArray = PacketCodecType.encode(opcode, payload)
	if packet.is_empty():
		return ERR_INVALID_DATA
	if channel == ProtocolConstantsType.SNAPSHOT_CHANNEL:
		return peer.send(channel, packet, 0)
	return peer.send(channel, packet, 2)
