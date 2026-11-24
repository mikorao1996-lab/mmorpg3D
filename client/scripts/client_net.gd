class_name ClientNet
extends Node

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")
const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")

signal connected()
signal disconnected()
signal hello_accepted(protocol: int, player_id: int)
signal hello_rejected(reason: String)
signal world_snapshot(snapshot: Dictionary)
signal zone_transfer_completed(zone_id: String, accepted: bool, reason: String)
signal ability_cast_completed(
	accepted: bool,
	reason: String,
	mob_id: String,
	health: float,
	max_health: float,
)
signal loot_pickup_completed(accepted: bool, reason: String, item_id: String)
signal equipment_action_completed(
	operation: String,
	accepted: bool,
	reason: String,
	item_id: String,
	slot_id: String,
)

var peer: ENetMultiplayerPeer
var is_connected: bool = false
var _transport_connected: bool = false
var _hello_sent: bool = false


func connect_to_server(address: String, port: int = ProtocolConstantsType.SERVER_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port, 2)
	if error != OK:
		push_error("Failed to create ENet client")
		return error
	var server_peer: ENetPacketPeer = peer.get_peer(1)
	if server_peer == null:
		push_error("ENet client did not create its server peer")
		peer.close()
		return ERR_UNCONFIGURED
	server_peer.set_timeout(3000, 5000, 10000)
	return OK


func _process(_delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_transport_connected = true
		if not _hello_sent:
			var send_error: Error = send_hello()
			if send_error != OK:
				push_error("Failed to send hello packet: %s" % send_error)
			else:
				_hello_sent = true
	elif _transport_connected and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_transport_connected = false
		is_connected = false
		disconnected.emit()

	while peer.get_available_packet_count() > 0:
		var channel: int = peer.get_packet_channel()
		var packet: PackedByteArray = peer.get_packet()
		handle_packet(channel, packet)


func handle_packet(channel: int, packet: PackedByteArray) -> void:
	if channel != ProtocolConstantsType.EVENT_CHANNEL \
			and channel != ProtocolConstantsType.SNAPSHOT_CHANNEL:
		push_warning("Rejected packet on unsupported channel")
		return
	var envelope: Dictionary = PacketCodecType.decode(packet)
	if envelope.is_empty():
		return

	var opcode: int = envelope["opcode"]
	var payload: Dictionary = envelope["payload"]
	if channel == ProtocolConstantsType.SNAPSHOT_CHANNEL:
		if not is_connected or opcode != ProtocolConstantsType.OPCODE_WORLD_SNAPSHOT:
			push_warning("Rejected unexpected snapshot packet")
			return
		world_snapshot.emit(payload)
		return

	match opcode:
		ProtocolConstantsType.OPCODE_HELLO_ACCEPTED:
			var protocol_value: Variant = payload.get("protocol", -1)
			var player_id_value: Variant = payload.get("player_id", -1)
			if protocol_value is not int or player_id_value is not int:
				push_warning("Rejected malformed hello response")
				return
			if protocol_value != ProtocolConstantsType.PROTOCOL_VERSION:
				hello_rejected.emit("protocol_mismatch")
				return
			is_connected = true
			connected.emit()
			hello_accepted.emit(protocol_value, player_id_value)
		ProtocolConstantsType.OPCODE_HELLO_REJECTED:
			hello_rejected.emit(str(payload.get("reason", "unknown")))
		ProtocolConstantsType.OPCODE_ZONE_TRANSFER_RESULT:
			var zone_id_value: Variant = payload.get("zone_id", null)
			var accepted_value: Variant = payload.get("accepted", null)
			var reason_value: Variant = payload.get("reason", "")
			if (
				zone_id_value is not String
				or accepted_value is not bool
				or reason_value is not String
			):
				push_warning("Rejected malformed zone transfer result")
				return
			zone_transfer_completed.emit(zone_id_value, accepted_value, reason_value)
		ProtocolConstantsType.OPCODE_ABILITY_CAST_RESULT:
			var accepted_value: Variant = payload.get("accepted", null)
			var reason_value: Variant = payload.get("reason", null)
			var mob_id_value: Variant = payload.get("mob_id", null)
			var health_value: Variant = payload.get("health", null)
			var max_health_value: Variant = payload.get("max_health", null)
			if (
				accepted_value is not bool
				or reason_value is not String
				or mob_id_value is not String
				or not _is_number(health_value)
				or not _is_number(max_health_value)
			):
				push_warning("Rejected malformed ability cast result")
				return
			ability_cast_completed.emit(
				accepted_value,
				reason_value,
				mob_id_value,
				float(health_value),
				float(max_health_value),
			)
		ProtocolConstantsType.OPCODE_LOOT_PICKUP_RESULT:
			var accepted_value: Variant = payload.get("accepted", null)
			var reason_value: Variant = payload.get("reason", null)
			var item_id_value: Variant = payload.get("item_id", null)
			if (
				accepted_value is not bool
				or reason_value is not String
				or item_id_value is not String
			):
				push_warning("Rejected malformed loot pickup result")
				return
			loot_pickup_completed.emit(accepted_value, reason_value, item_id_value)
		ProtocolConstantsType.OPCODE_EQUIPMENT_RESULT:
			var operation_value: Variant = payload.get("operation", null)
			var accepted_value: Variant = payload.get("accepted", null)
			var reason_value: Variant = payload.get("reason", null)
			var item_id_value: Variant = payload.get("item_id", null)
			var slot_id_value: Variant = payload.get("slot_id", null)
			if (
				operation_value is not String
				or not ["equip", "unequip"].has(operation_value)
				or accepted_value is not bool
				or reason_value is not String
				or item_id_value is not String
				or slot_id_value is not String
			):
				push_warning("Rejected malformed equipment result")
				return
			equipment_action_completed.emit(
				operation_value,
				accepted_value,
				reason_value,
				item_id_value,
				slot_id_value,
			)
		ProtocolConstantsType.OPCODE_KEEPALIVE_ACK:
			pass


func send_hello() -> Error:
	return send_packet(ProtocolConstantsType.OPCODE_HELLO, {
		"protocol": ProtocolConstantsType.PROTOCOL_VERSION,
	})


func send_keepalive() -> Error:
	return send_packet(ProtocolConstantsType.OPCODE_KEEPALIVE)


func send_movement_intent(input_direction: Vector2) -> Error:
	if not is_connected:
		return ERR_UNCONFIGURED
	return send_packet(ProtocolConstantsType.OPCODE_MOVE_INPUT, {
		"direction": input_direction,
	})


func request_zone_transfer(zone_id: String) -> Error:
	if not is_connected:
		return ERR_UNCONFIGURED
	if zone_id.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	return send_packet(ProtocolConstantsType.OPCODE_ZONE_TRANSFER, {
		"zone_id": zone_id,
	})


func request_ability_cast(ability_id: String, target_mob_id: String) -> Error:
	if not is_connected:
		return ERR_UNCONFIGURED
	if ability_id.strip_edges().is_empty() or target_mob_id.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	return send_packet(ProtocolConstantsType.OPCODE_ABILITY_CAST, {
		"ability_id": ability_id,
		"target_mob_id": target_mob_id,
	})


func request_loot_pickup(drop_id: int) -> Error:
	if not is_connected:
		return ERR_UNCONFIGURED
	if drop_id < 1:
		return ERR_INVALID_PARAMETER
	return send_packet(ProtocolConstantsType.OPCODE_LOOT_PICKUP, {
		"drop_id": drop_id,
	})


func request_equip_item(item_id: String) -> Error:
	if not is_connected:
		return ERR_UNCONFIGURED
	if item_id.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	return send_packet(ProtocolConstantsType.OPCODE_EQUIP_ITEM, {
		"item_id": item_id,
	})


func request_unequip_item(slot_id: String) -> Error:
	if not is_connected:
		return ERR_UNCONFIGURED
	if slot_id.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	return send_packet(ProtocolConstantsType.OPCODE_UNEQUIP_ITEM, {
		"slot_id": slot_id,
	})


func send_packet(opcode: int, payload: Dictionary = {}) -> Error:
	if peer == null:
		return ERR_UNCONFIGURED
	var packet: PackedByteArray = PacketCodecType.encode(opcode, payload)
	if packet.is_empty():
		return ERR_INVALID_DATA
	var server_peer: ENetPacketPeer = peer.get_peer(1)
	if server_peer == null:
		return ERR_UNAVAILABLE
	return server_peer.send(
		ProtocolConstantsType.to_transport_channel(ProtocolConstantsType.EVENT_CHANNEL),
		packet,
		ProtocolConstantsType.PACKET_FLAG_RELIABLE,
	)


func _is_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	return (
		(value_type == TYPE_INT or value_type == TYPE_FLOAT)
		and is_finite(float(value))
	)
