extends RefCounted

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")


func run() -> bool:
	if ProtocolConstantsType.PROTOCOL_VERSION != 8:
		push_error("Unexpected protocol version")
		return false
	if (
		ProtocolConstantsType.OPCODE_LOOT_PICKUP
		== ProtocolConstantsType.OPCODE_LOOT_PICKUP_RESULT
	):
		push_error("Loot request and result opcodes must differ")
		return false
	if (
		ProtocolConstantsType.OPCODE_EQUIP_ITEM == ProtocolConstantsType.OPCODE_UNEQUIP_ITEM
		or ProtocolConstantsType.OPCODE_EQUIP_ITEM == ProtocolConstantsType.OPCODE_EQUIPMENT_RESULT
		or ProtocolConstantsType.OPCODE_UNEQUIP_ITEM == ProtocolConstantsType.OPCODE_EQUIPMENT_RESULT
	):
		push_error("Equipment request and result opcodes must differ")
		return false
	if (
		ProtocolConstantsType.OPCODE_USE_ITEM == ProtocolConstantsType.OPCODE_ITEM_USE_RESULT
	):
		push_error("Item use request and result opcodes must differ")
		return false
	if (
		ProtocolConstantsType.OPCODE_NPC_INTERACT
		== ProtocolConstantsType.OPCODE_NPC_INTERACT_RESULT
	):
		push_error("NPC interaction request and result opcodes must differ")
		return false
	if (
		ProtocolConstantsType.OPCODE_TRADE_REQUEST
		== ProtocolConstantsType.OPCODE_TRADE_RESULT
	):
		push_error("Trade request and result opcodes must differ")
		return false
	if (
		ProtocolConstantsType.OPCODE_TRADE_REQUEST
		== ProtocolConstantsType.OPCODE_NPC_INTERACT
		or ProtocolConstantsType.OPCODE_TRADE_RESULT
		== ProtocolConstantsType.OPCODE_NPC_INTERACT_RESULT
	):
		push_error("Trade opcodes must not collide with the NPC opcodes")
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
