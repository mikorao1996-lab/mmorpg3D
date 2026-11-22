class_name ServerSession
extends RefCounted

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")

var peer: ENetPacketPeer
var authenticated: bool = false
var connected_at_ms: int = Time.get_ticks_msec()
var rate_window_started_ms: int = connected_at_ms
var requests_in_window: int = 0


func _init(packet_peer: ENetPacketPeer) -> void:
	peer = packet_peer


func is_handshake_timed_out(now_ms: int) -> bool:
	if authenticated:
		return false
	return float(now_ms - connected_at_ms) / 1000.0 > ProtocolConstantsType.HANDSHAKE_TIMEOUT_SECONDS


func accept_packet(now_ms: int) -> bool:
	if now_ms - rate_window_started_ms >= 1000:
		rate_window_started_ms = now_ms
		requests_in_window = 0
	requests_in_window += 1
	return requests_in_window <= ProtocolConstantsType.MAX_REQUESTS_PER_SECOND


func send(
	opcode: int,
	payload: Dictionary = {},
	protocol_channel: int = ProtocolConstantsType.EVENT_CHANNEL,
) -> Error:
	const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")
	if protocol_channel != ProtocolConstantsType.SNAPSHOT_CHANNEL \
			and protocol_channel != ProtocolConstantsType.EVENT_CHANNEL:
		push_error("Cannot send on unsupported protocol channel")
		return ERR_INVALID_PARAMETER

	var flags: int = ProtocolConstantsType.PACKET_FLAG_UNRELIABLE
	if protocol_channel == ProtocolConstantsType.EVENT_CHANNEL:
		flags = ProtocolConstantsType.PACKET_FLAG_RELIABLE
	var packet: PackedByteArray = PacketCodecType.encode(opcode, payload)
	if packet.is_empty():
		return ERR_INVALID_DATA
	return peer.send(
		ProtocolConstantsType.to_transport_channel(protocol_channel),
		packet,
		flags,
	)
