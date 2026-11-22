extends RefCounted

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")


func run() -> bool:
	if ProtocolConstantsType.PROTOCOL_VERSION != 2:
		push_error("Unexpected protocol version")
		return false
	if ProtocolConstantsType.MAX_PACKET_SIZE_BYTES <= 0:
		push_error("Packet size limit must be positive")
		return false
	if ProtocolConstantsType.SNAPSHOT_CHANNEL == ProtocolConstantsType.EVENT_CHANNEL:
		push_error("Snapshot and event channels must differ")
		return false
	if ProtocolConstantsType.to_transport_channel(ProtocolConstantsType.SNAPSHOT_CHANNEL) != 1:
		push_error("Snapshot channel does not map to the expected ENet channel")
		return false
	if ProtocolConstantsType.to_transport_channel(ProtocolConstantsType.EVENT_CHANNEL) != 2:
		push_error("Event channel does not map past ENet's reserved channels")
		return false
	return true
