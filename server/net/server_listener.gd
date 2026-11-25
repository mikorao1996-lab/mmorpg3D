class_name ServerListener
extends RefCounted

signal player_authenticated(peer_id: int)
signal player_disconnected(peer_id: int)
signal movement_intent(peer_id: int, input_direction: Vector2)
signal zone_transfer_requested(peer_id: int, zone_id: String)
signal ability_cast_requested(peer_id: int, ability_id: String, target_mob_id: String)
signal loot_pickup_requested(peer_id: int, drop_id: int)
signal equip_item_requested(peer_id: int, item_id: String)
signal unequip_item_requested(peer_id: int, slot_id: String)
signal use_item_requested(peer_id: int, item_id: String)
signal npc_interact_requested(peer_id: int, npc_id: String, action: String, quest_id: String)
signal trade_requested(
	peer_id: int,
	npc_id: String,
	action: String,
	item_id: String,
	quantity: int,
)
signal player_named(peer_id: int, player_name: String)
signal chat_requested(peer_id: int, channel: String, text: String)
signal party_requested(peer_id: int, action: String, target_peer_id: int)

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
	peer.peer_disconnected.connect(_on_peer_disconnected)
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
		handle_hello(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_KEEPALIVE:
		if session.authenticated:
			session.send(ProtocolConstantsType.OPCODE_KEEPALIVE_ACK)
		else:
			push_warning("Keepalive before authentication from peer %d" % peer_id)
	elif opcode == ProtocolConstantsType.OPCODE_MOVE_INPUT:
		handle_movement_intent(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_ZONE_TRANSFER:
		handle_zone_transfer(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_ABILITY_CAST:
		handle_ability_cast(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_LOOT_PICKUP:
		handle_loot_pickup(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_EQUIP_ITEM:
		handle_equip_item(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_UNEQUIP_ITEM:
		handle_unequip_item(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_USE_ITEM:
		handle_use_item(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_NPC_INTERACT:
		handle_npc_interact(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_TRADE_REQUEST:
		handle_trade_request(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_CHAT_SAY_REQUEST:
		handle_chat_request(session, peer_id, payload)
	elif opcode == ProtocolConstantsType.OPCODE_PARTY_REQUEST:
		handle_party_request(session, peer_id, payload)
	else:
		push_warning("Unknown opcode %d from peer %d" % [opcode, peer_id])


func handle_hello(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	var client_version: Variant = payload.get("protocol", -1)
	if client_version is not int or client_version != ProtocolConstantsType.PROTOCOL_VERSION:
		session.send(ProtocolConstantsType.OPCODE_HELLO_REJECTED, {"reason": "protocol_mismatch"})
		push_warning("Rejected protocol mismatch")
		return

	var first_handshake: bool = not session.authenticated
	session.authenticated = true
	if first_handshake:
		player_authenticated.emit(peer_id)
		var name_value: Variant = payload.get("name", "")
		if name_value is String and not name_value.strip_edges().is_empty():
			session.player_name = name_value
			player_named.emit(peer_id, name_value)
	var send_error: Error = session.send(ProtocolConstantsType.OPCODE_HELLO_ACCEPTED, {
		"protocol": ProtocolConstantsType.PROTOCOL_VERSION,
		"player_id": peer_id,
	})
	if send_error != OK:
		push_warning("Failed to send hello response to peer %d: %s" % [peer_id, send_error])


func handle_movement_intent(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Movement intent before authentication from peer %d" % peer_id)
		return
	var input_value: Variant = payload.get("direction")
	if not input_value is Vector2:
		push_warning("Rejected malformed movement intent from peer %d" % peer_id)
		return
	movement_intent.emit(peer_id, input_value)


func handle_zone_transfer(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Zone transfer before authentication from peer %d" % peer_id)
		return
	var zone_id_value: Variant = payload.get("zone_id")
	if zone_id_value is not String or zone_id_value.strip_edges().is_empty():
		push_warning("Rejected malformed zone transfer from peer %d" % peer_id)
		return
	zone_transfer_requested.emit(peer_id, zone_id_value)


func handle_ability_cast(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Ability cast before authentication from peer %d" % peer_id)
		return
	var ability_id_value: Variant = payload.get("ability_id")
	var target_mob_id_value: Variant = payload.get("target_mob_id")
	if (
		ability_id_value is not String
		or ability_id_value.strip_edges().is_empty()
		or target_mob_id_value is not String
		or target_mob_id_value.strip_edges().is_empty()
	):
		push_warning("Rejected malformed ability cast from peer %d" % peer_id)
		return
	ability_cast_requested.emit(peer_id, ability_id_value, target_mob_id_value)


func handle_loot_pickup(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Loot pickup before authentication from peer %d" % peer_id)
		return
	var drop_id_value: Variant = payload.get("drop_id", null)
	if drop_id_value is not int or drop_id_value < 1:
		push_warning("Rejected malformed loot pickup from peer %d" % peer_id)
		return
	loot_pickup_requested.emit(peer_id, drop_id_value)


func handle_equip_item(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Equipment request before authentication from peer %d" % peer_id)
		return
	var item_id_value: Variant = payload.get("item_id")
	if item_id_value is not String or item_id_value.strip_edges().is_empty():
		push_warning("Rejected malformed equip request from peer %d" % peer_id)
		return
	equip_item_requested.emit(peer_id, item_id_value)


func handle_unequip_item(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Equipment request before authentication from peer %d" % peer_id)
		return
	var slot_id_value: Variant = payload.get("slot_id")
	if slot_id_value is not String or slot_id_value.strip_edges().is_empty():
		push_warning("Rejected malformed unequip request from peer %d" % peer_id)
		return
	unequip_item_requested.emit(peer_id, slot_id_value)


func handle_use_item(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Item use before authentication from peer %d" % peer_id)
		return
	var item_id_value: Variant = payload.get("item_id")
	if item_id_value is not String or item_id_value.strip_edges().is_empty():
		push_warning("Rejected malformed item use request from peer %d" % peer_id)
		return
	use_item_requested.emit(peer_id, item_id_value)


func handle_npc_interact(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("NPC interaction before authentication from peer %d" % peer_id)
		return
	var npc_id_value: Variant = payload.get("npc_id")
	var action_value: Variant = payload.get("action")
	var quest_id_value: Variant = payload.get("quest_id", "")
	if npc_id_value is not String or npc_id_value.strip_edges().is_empty():
		push_warning("Rejected malformed NPC interaction from peer %d" % peer_id)
		return
	if action_value is not String or action_value.strip_edges().is_empty():
		push_warning("Rejected malformed NPC interaction action from peer %d" % peer_id)
		return
	if quest_id_value is not String:
		push_warning("Rejected malformed NPC interaction quest id from peer %d" % peer_id)
		return
	npc_interact_requested.emit(
		peer_id,
		npc_id_value,
		action_value,
		quest_id_value,
	)


## Handles a trade request.
##
## The request only names the NPC, the action, the item, and the quantity. The
## price is never part of the request: the server reads it from the vendor
## registry, so a client cannot change what an item costs.
func handle_trade_request(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Trade request before authentication from peer %d" % peer_id)
		return
	var npc_id_value: Variant = payload.get("npc_id")
	var action_value: Variant = payload.get("action")
	var item_id_value: Variant = payload.get("item_id")
	var quantity_value: Variant = payload.get("quantity", 1)
	if npc_id_value is not String or npc_id_value.strip_edges().is_empty():
		push_warning("Rejected malformed trade request from peer %d" % peer_id)
		return
	if action_value is not String or action_value.strip_edges().is_empty():
		push_warning("Rejected malformed trade action from peer %d" % peer_id)
		return
	if item_id_value is not String or item_id_value.strip_edges().is_empty():
		push_warning("Rejected malformed trade item from peer %d" % peer_id)
		return
	if quantity_value is not int or quantity_value < 1:
		push_warning("Rejected malformed trade quantity from peer %d" % peer_id)
		return
	trade_requested.emit(
		peer_id,
		npc_id_value,
		action_value,
		item_id_value,
		quantity_value,
	)


func broadcast_world_snapshots(snapshots_by_peer: Dictionary) -> void:
	for peer_id: int in sessions:
		var session: RefCounted = sessions[peer_id]
		if not session.authenticated:
			continue
		if not snapshots_by_peer.has(peer_id) or not snapshots_by_peer[peer_id] is Dictionary:
			push_warning("No world snapshot generated for authenticated peer %d" % peer_id)
			continue
		var send_error: Error = session.send(
			ProtocolConstantsType.OPCODE_WORLD_SNAPSHOT,
			snapshots_by_peer[peer_id],
			ProtocolConstantsType.SNAPSHOT_CHANNEL,
		)
		if send_error != OK:
			push_warning("Failed to send snapshot to peer %d: %s" % [peer_id, send_error])


## Handles a chat message request.
##
## The request names the channel and the text; the server decides who receives
## the message and whether it is accepted at all.
func handle_chat_request(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Chat request before authentication from peer %d" % peer_id)
		return
	var channel_value: Variant = payload.get("channel")
	var text_value: Variant = payload.get("text")
	if channel_value is not String or channel_value.strip_edges().is_empty():
		push_warning("Rejected malformed chat channel from peer %d" % peer_id)
		return
	if text_value is not String:
		push_warning("Rejected malformed chat text from peer %d" % peer_id)
		return
	chat_requested.emit(peer_id, channel_value, text_value)


## Handles a party request.
##
## The request names the action (`invite`, `accept`, or `leave`) and the peer
## the invitation is meant for.
func handle_party_request(session: RefCounted, peer_id: int, payload: Dictionary) -> void:
	if not session.authenticated:
		push_warning("Party request before authentication from peer %d" % peer_id)
		return
	var action_value: Variant = payload.get("action")
	var target_value: Variant = payload.get("target_peer_id", 0)
	if action_value is not String or action_value.strip_edges().is_empty():
		push_warning("Rejected malformed party action from peer %d" % peer_id)
		return
	if not target_value is int:
		push_warning("Rejected malformed party target from peer %d" % peer_id)
		return
	party_requested.emit(peer_id, action_value, target_value)


## Sends a chat message to a client.
func send_chat_message(peer_id: int, message: Dictionary) -> void:
	if not sessions.has(peer_id):
		return
	var session: RefCounted = sessions[peer_id]
	if not session.authenticated:
		return
	var send_error: Error = session.send(
		ProtocolConstantsType.OPCODE_CHAT_MESSAGE,
		{
			"channel": str(message.get("channel", "system")),
			"sender_peer_id": int(message.get("sender_peer_id", 0)),
			"sender_name": str(message.get("sender_name", "")),
			"text": str(message.get("text", "")),
			"system_key": str(message.get("system_key", "")),
			"reason": str(message.get("reason", "")),
		},
	)
	if send_error != OK:
		push_warning("Failed to send chat message to peer %d: %s" % [peer_id, send_error])


## Sends the result of a party request to a client.
func send_party_result(peer_id: int, result: Dictionary) -> void:
	if not sessions.has(peer_id):
		push_warning("Cannot send party result to missing peer %d" % peer_id)
		return
	var session: RefCounted = sessions[peer_id]
	if not session.authenticated:
		push_warning("Cannot send party result to unauthenticated peer %d" % peer_id)
		return
	var send_error: Error = session.send(
		ProtocolConstantsType.OPCODE_PARTY_RESULT,
		{
			"accepted": bool(result.get("accepted", false)),
			"reason": str(result.get("reason", "party_error")),
			"action": str(result.get("action", "invite")),
			"party_id": int(result.get("party_id", 0)),
			"leader_peer_id": int(result.get("leader_peer_id", 0)),
			"members": result.get("members", []),
			"inviter_peer_id": int(result.get("inviter_peer_id", 0)),
			"inviter_name": str(result.get("inviter_name", "")),
		},
	)
	if send_error != OK:
		push_warning("Failed to send party result to peer %d: %s" % [peer_id, send_error])


func send_zone_transfer_result(
	peer_id: int,
	zone_id: String,
	accepted: bool,
	reason: String = "",
) -> void:
	if not sessions.has(peer_id):
		push_warning("Cannot send zone transfer result to missing peer %d" % peer_id)
		return
	var session: RefCounted = sessions[peer_id]
	if not session.authenticated:
		push_warning("Cannot send zone transfer result to unauthenticated peer %d" % peer_id)
		return
	var send_error: Error = session.send(
		ProtocolConstantsType.OPCODE_ZONE_TRANSFER_RESULT,
		{
			"zone_id": zone_id,
			"accepted": accepted,
			"reason": reason,
		},
	)
	if send_error != OK:
		push_warning("Failed to send zone transfer result to peer %d: %s" % [peer_id, send_error])


func send_ability_cast_result(peer_id: int, result: Dictionary) -> void:
	if not sessions.has(peer_id):
		push_warning("Cannot send ability cast result to missing peer %d" % peer_id)
		return
	var session: RefCounted = sessions[peer_id]
	if not session.authenticated:
		push_warning("Cannot send ability cast result to unauthenticated peer %d" % peer_id)
		return
	var send_error: Error = session.send(
		ProtocolConstantsType.OPCODE_ABILITY_CAST_RESULT,
		result,
	)
	if send_error != OK:
		push_warning("Failed to send ability cast result to peer %d: %s" % [peer_id, send_error])


func send_loot_pickup_result(peer_id: int, result: Dictionary) -> void:
	if not sessions.has(peer_id):
		push_warning("Cannot send loot pickup result to missing peer %d" % peer_id)
		return
	var session: RefCounted = sessions[peer_id]
	if not session.authenticated:
		push_warning("Cannot send loot pickup result to unauthenticated peer %d" % peer_id)
		return
	var send_error: Error = session.send(
		ProtocolConstantsType.OPCODE_LOOT_PICKUP_RESULT,
		result,
	)
	if send_error != OK:
		push_warning("Failed to send loot pickup result to peer %d: %s" % [peer_id, send_error])


func send_equipment_result(peer_id: int, operation: String, result: Dictionary) -> void:
	if not sessions.has(peer_id):
		push_warning("Cannot send equipment result to missing peer %d" % peer_id)
		return
	var session: RefCounted = sessions[peer_id]
	if not session.authenticated:
		push_warning("Cannot send equipment result to unauthenticated peer %d" % peer_id)
		return
	var send_error: Error = session.send(
		ProtocolConstantsType.OPCODE_EQUIPMENT_RESULT,
		{
			"operation": operation,
			"accepted": bool(result.get("accepted", false)),
			"reason": str(result.get("reason", "equipment_error")),
			"item_id": str(result.get("item_id", "")),
			"slot_id": str(result.get("slot_id", "")),
		},
	)
	if send_error != OK:
		push_warning("Failed to send equipment result to peer %d: %s" % [peer_id, send_error])


func send_item_use_result(peer_id: int, result: Dictionary) -> void:
	if not sessions.has(peer_id):
		push_warning("Cannot send item use result to missing peer %d" % peer_id)
		return
	var session: RefCounted = sessions[peer_id]
	if not session.authenticated:
		push_warning("Cannot send item use result to unauthenticated peer %d" % peer_id)
		return
	var send_error: Error = session.send(
		ProtocolConstantsType.OPCODE_ITEM_USE_RESULT,
		{
			"accepted": bool(result.get("accepted", false)),
			"reason": str(result.get("reason", "item_use_error")),
			"item_id": str(result.get("item_id", "")),
			"health": float(result.get("health", 0.0)),
			"max_health": float(result.get("max_health", 0.0)),
			"resource": float(result.get("resource", 0.0)),
			"max_resource": float(result.get("max_resource", 0.0)),
		},
	)
	if send_error != OK:
		push_warning("Failed to send item use result to peer %d: %s" % [peer_id, send_error])


func send_npc_interact_result(peer_id: int, result: Dictionary) -> void:
	if not sessions.has(peer_id):
		push_warning("Cannot send NPC interaction result to missing peer %d" % peer_id)
		return
	var session: RefCounted = sessions[peer_id]
	if not session.authenticated:
		push_warning("Cannot send NPC interaction result to unauthenticated peer %d" % peer_id)
		return
	var send_error: Error = session.send(
		ProtocolConstantsType.OPCODE_NPC_INTERACT_RESULT,
		{
			"accepted": bool(result.get("accepted", false)),
			"reason": str(result.get("reason", "npc_interact_error")),
			"action": str(result.get("action", "talk")),
			"npc_id": str(result.get("npc_id", "")),
			"npc_name_key": str(result.get("npc_name_key", "")),
			"dialogue_key": str(result.get("dialogue_key", "")),
			"quests": result.get("quests", []),
			"quest_id": str(result.get("quest_id", "")),
			"reward_experience": int(result.get("reward_experience", 0)),
			"reward_gold": int(result.get("reward_gold", 0)),
			"reward_item_ids": result.get("reward_item_ids", []),
			"vendor_items": result.get("vendor_items", []),
		},
	)
	if send_error != OK:
		push_warning(
			"Failed to send NPC interaction result to peer %d: %s" % [peer_id, send_error]
		)


## Sends the result of a trade to the client.
func send_trade_result(peer_id: int, result: Dictionary) -> void:
	if not sessions.has(peer_id):
		push_warning("Cannot send trade result to missing peer %d" % peer_id)
		return
	var session: RefCounted = sessions[peer_id]
	if not session.authenticated:
		push_warning("Cannot send trade result to unauthenticated peer %d" % peer_id)
		return
	var send_error: Error = session.send(
		ProtocolConstantsType.OPCODE_TRADE_RESULT,
		{
			"accepted": bool(result.get("accepted", false)),
			"reason": str(result.get("reason", "trade_error")),
			"action": str(result.get("action", "buy")),
			"npc_id": str(result.get("npc_id", "")),
			"item_id": str(result.get("item_id", "")),
			"quantity": int(result.get("quantity", 0)),
			"price": int(result.get("price", 0)),
			"gold": int(result.get("gold", 0)),
		},
	)
	if send_error != OK:
		push_warning("Failed to send trade result to peer %d: %s" % [peer_id, send_error])


func _on_peer_disconnected(peer_id: int) -> void:
	if not sessions.has(peer_id):
		return
	var session: RefCounted = sessions[peer_id]
	if session.authenticated:
		player_disconnected.emit(peer_id)
	sessions.erase(peer_id)
