extends RefCounted

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")


func run() -> bool:
	if ProtocolConstantsType.PROTOCOL_VERSION != 10:
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
	if (
		ProtocolConstantsType.OPCODE_CHAT_SAY_REQUEST
		== ProtocolConstantsType.OPCODE_CHAT_MESSAGE
	):
		push_error("Chat request and message opcodes must differ")
		return false
	if (
		ProtocolConstantsType.OPCODE_PARTY_REQUEST
		== ProtocolConstantsType.OPCODE_PARTY_RESULT
	):
		push_error("Party request and result opcodes must differ")
		return false
	var new_opcodes: Array[int] = [
		ProtocolConstantsType.OPCODE_CHAT_SAY_REQUEST,
		ProtocolConstantsType.OPCODE_CHAT_MESSAGE,
		ProtocolConstantsType.OPCODE_PARTY_REQUEST,
		ProtocolConstantsType.OPCODE_PARTY_RESULT,
	]
	for opcode: int in new_opcodes:
		for known_opcode: int in [
			ProtocolConstantsType.OPCODE_HELLO,
			ProtocolConstantsType.OPCODE_HELLO_ACCEPTED,
			ProtocolConstantsType.OPCODE_HELLO_REJECTED,
			ProtocolConstantsType.OPCODE_KEEPALIVE,
			ProtocolConstantsType.OPCODE_KEEPALIVE_ACK,
			ProtocolConstantsType.OPCODE_MOVE_INPUT,
			ProtocolConstantsType.OPCODE_WORLD_SNAPSHOT,
			ProtocolConstantsType.OPCODE_ZONE_TRANSFER,
			ProtocolConstantsType.OPCODE_ZONE_TRANSFER_RESULT,
			ProtocolConstantsType.OPCODE_ABILITY_CAST,
			ProtocolConstantsType.OPCODE_ABILITY_CAST_RESULT,
			ProtocolConstantsType.OPCODE_LOOT_PICKUP,
			ProtocolConstantsType.OPCODE_LOOT_PICKUP_RESULT,
			ProtocolConstantsType.OPCODE_EQUIP_ITEM,
			ProtocolConstantsType.OPCODE_UNEQUIP_ITEM,
			ProtocolConstantsType.OPCODE_EQUIPMENT_RESULT,
			ProtocolConstantsType.OPCODE_USE_ITEM,
			ProtocolConstantsType.OPCODE_ITEM_USE_RESULT,
			ProtocolConstantsType.OPCODE_NPC_INTERACT,
			ProtocolConstantsType.OPCODE_NPC_INTERACT_RESULT,
			ProtocolConstantsType.OPCODE_TRADE_REQUEST,
			ProtocolConstantsType.OPCODE_TRADE_RESULT,
		]:
			if opcode == known_opcode:
				push_error("A chat or party opcode collides with an older opcode")
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
