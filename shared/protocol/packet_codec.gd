class_name PacketCodec
extends RefCounted

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")


static func encode(opcode: int, payload: Dictionary = {}, sequence: int = 0) -> PackedByteArray:
	var envelope: Dictionary = {
		"protocol": ProtocolConstantsType.PROTOCOL_VERSION,
		"opcode": opcode,
		"sequence": sequence,
		"payload": payload,
	}
	var packet: PackedByteArray = var_to_bytes(envelope)
	if packet.size() > ProtocolConstantsType.MAX_PACKET_SIZE_BYTES:
		push_error("Packet exceeds maximum size")
		return PackedByteArray()
	return packet


static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.is_empty():
		push_error("Rejected empty packet")
		return {}
	if packet.size() > ProtocolConstantsType.MAX_PACKET_SIZE_BYTES:
		push_error("Rejected oversized packet")
		return {}

	var envelope: Variant = bytes_to_var(packet)
	if not envelope is Dictionary:
		push_error("Rejected packet with invalid envelope")
		return {}

	var dictionary: Dictionary = envelope
	if not dictionary.has("protocol") or not dictionary.has("opcode"):
		push_error("Rejected packet missing required fields")
		return {}
	if dictionary["protocol"] is not int:
		push_error("Rejected packet with invalid protocol type")
		return {}
	if dictionary["protocol"] != ProtocolConstantsType.PROTOCOL_VERSION:
		push_error("Rejected packet with unsupported protocol")
		return {}
	if dictionary["opcode"] is not int:
		push_error("Rejected packet with invalid opcode type")
		return {}
	if not dictionary.has("payload") or not dictionary["payload"] is Dictionary:
		push_error("Rejected packet with invalid payload")
		return {}

	dictionary["packet_size"] = packet.size()
	return dictionary
