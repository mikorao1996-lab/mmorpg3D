extends RefCounted

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")


func run() -> bool:
	if ProtocolConstantsType.PROTOCOL_VERSION != 1:
		push_error("Unexpected protocol version")
		return false
	if ProtocolConstantsType.MAX_PACKET_SIZE_BYTES <= 0:
		push_error("Packet size limit must be positive")
		return false
	if ProtocolConstantsType.SNAPSHOT_CHANNEL == ProtocolConstantsType.EVENT_CHANNEL:
		push_error("Snapshot and event channels must differ")
		return false
	return true
