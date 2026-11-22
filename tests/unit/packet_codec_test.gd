extends RefCounted

const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")
const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")


func run() -> bool:
	var packet: PackedByteArray = PacketCodecType.encode(
		ProtocolConstantsType.OPCODE_HELLO,
		{"protocol": ProtocolConstantsType.PROTOCOL_VERSION},
	)
	if packet.is_empty():
		push_error("Packet encoding returned empty data")
		return false

	var envelope: Dictionary = PacketCodecType.decode(packet)
	if envelope.is_empty():
		push_error("Packet decoding failed")
		return false
	if envelope["opcode"] != ProtocolConstantsType.OPCODE_HELLO:
		push_error("Packet opcode changed during codec round trip")
		return false
	if envelope["payload"].get("protocol", -1) != ProtocolConstantsType.PROTOCOL_VERSION:
		push_error("Packet payload changed during codec round trip")
		return false

	return true
