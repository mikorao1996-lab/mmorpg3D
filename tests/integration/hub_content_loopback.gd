extends Node

## End-to-end check for the content of the hub.
##
## The test starts the real server listener and world in-process and connects
## two real clients over the loopback. The positions of the NPCs and of the
## mobs are taken from the registry as they are: the first client walks to the
## quest giver, takes a quest, kills a slime, picks up its loot, and buys a
## potion from the vendor. The second client joins the zone, and the two of
## them form a party.

const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

const TEST_PORT: int = 7796
const MIRA_NPC_ID: String = "quest_giver_mira"
const VENDOR_NPC_ID: String = "vendor_grom"
const TALK_QUEST_ID: String = "training_grounds"
const SLIME_TYPE_ID: String = "training_slime"
const POTION_ITEM_ID: String = "minor_potion"
const CHAT_TEXT: String = "the hub is alive"
const ARRIVAL_DISTANCE: float = 1.5
const MOVE_INTERVAL_SECONDS: float = 0.1
const TIMEOUT_SECONDS: float = 90.0

var listener: RefCounted
var server_world: RefCounted
var client_a: ClientNet
var client_b: ClientNet
var elapsed_seconds: float = 0.0
var step: int = 0
var _next_request_allowed_at: float = 0.0
var _state_a: Dictionary = {}
var _state_b: Dictionary = {}
var _talk_result: Dictionary = {}
var _turn_in_result: Dictionary = {}
var _gold_before_quest: int = 0
var _accepted_casts: int = 0
var _loot_result: Dictionary = {}
var _trade_result: Dictionary = {}
var _gold_before_buy: int = 0
var _chat_seen: bool = false
var _party_members_a: int = 0
var _party_members_b: int = 0


func _ready() -> void:
	var simulation_config: Dictionary = SimulationConfigType.load_config()
	var game_data_registry: Dictionary = GameDataRegistryType.load_all()
	if simulation_config.is_empty() or game_data_registry.is_empty():
		_finish_with_error("The registries of the hub are empty")
		return

	listener = load("res://server/net/server_listener.gd").new()
	if not listener.start(TEST_PORT):
		_finish_with_error("The hub listener did not start")
		return
	server_world = load("res://server/world/server_world.gd").new(
		simulation_config,
		game_data_registry,
	)
	listener.player_authenticated.connect(server_world.add_player)
	listener.player_disconnected.connect(server_world.remove_player)
	listener.movement_intent.connect(_on_movement_intent)
	listener.ability_cast_requested.connect(_on_ability_cast_requested)
	listener.loot_pickup_requested.connect(_on_loot_pickup_requested)
	listener.equip_item_requested.connect(_on_equip_item_requested)
	listener.npc_interact_requested.connect(_on_npc_interact_requested)
	listener.trade_requested.connect(_on_trade_requested)
	listener.chat_requested.connect(_on_chat_requested)
	listener.party_requested.connect(_on_party_requested)

	client_a = ClientNet.new()
	add_child(client_a)
	client_a.hello_accepted.connect(_on_hello_accepted_a)
	client_a.world_snapshot.connect(_on_snapshot_a)
	client_a.npc_interaction_completed.connect(_on_npc_interaction_completed)
	client_a.ability_cast_completed.connect(_on_ability_cast_completed)
	client_a.loot_pickup_completed.connect(_on_loot_pickup_completed)
	client_a.trade_completed.connect(_on_trade_completed)
	client_a.chat_message_received.connect(_on_chat_message_received)
	client_a.party_result_received.connect(_on_party_result_a)
	var error_a: Error = client_a.connect_to_server("127.0.0.1", TEST_PORT)
	if error_a != OK:
		_finish_with_error("The first client did not connect")
		return

	client_b = ClientNet.new()
	add_child(client_b)
	client_b.hello_accepted.connect(_on_hello_accepted_b)
	client_b.world_snapshot.connect(_on_snapshot_b)
	client_b.chat_message_received.connect(_on_chat_message_received)
	client_b.party_result_received.connect(_on_party_result_b)
	var error_b: Error = client_b.connect_to_server("127.0.0.1", TEST_PORT)
	if error_b != OK:
		_finish_with_error("The second client did not connect")
		return


func _process(delta: float) -> void:
	elapsed_seconds += delta
	listener.poll()
	if server_world.advance(delta):
		listener.broadcast_world_snapshots(server_world.create_snapshots())

	match step:
		0:
			if _state_a.has("peer_id") and _state_b.has("peer_id"):
				_gold_before_quest = _gold_of(_state_a)
				step = 1
		1:
			# The first client walks to the quest giver and talks to her.
			if _walk_to(_state_a, _npc_position(MIRA_NPC_ID)):
				if elapsed_seconds >= _next_request_allowed_at:
					_next_request_allowed_at = elapsed_seconds + 0.3
					client_a.request_npc_interact(MIRA_NPC_ID, "talk")
				if not _talk_result.is_empty():
					step = 2
		2:
			# The quest giver offers a quest, and the client takes it.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.3
				client_a.request_npc_interact(MIRA_NPC_ID, "accept", TALK_QUEST_ID)
			if _quest_is_active(_state_a, TALK_QUEST_ID):
				step = 3
		3:
			# The quest of the talk is completed by another talk to the giver.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.3
				client_a.request_npc_interact(MIRA_NPC_ID, "talk")
			if _quest_is_completed(_state_a, TALK_QUEST_ID):
				step = 4
		4:
			# The finished quest is handed in for its reward.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.3
				client_a.request_npc_interact(MIRA_NPC_ID, "turn_in", TALK_QUEST_ID)
			if not _turn_in_result.is_empty():
				if not bool(_turn_in_result.get("accepted", false)):
					_finish_with_error(
						"The server refused the hand-in: %s"
						% str(_turn_in_result.get("reason", "")),
					)
					return
				if _gold_of(_state_a) <= _gold_before_quest:
					_finish_with_error("The hand-in did not award the gold")
					return
				step = 5
		5:
			# The client walks to a slime of the hub and defeats it.
			var slime_id: String = _find_live_mob(_state_a, SLIME_TYPE_ID)
			if slime_id.is_empty():
				_finish_with_error("The hub holds no live slime")
				return
			if _walk_to_mob(_state_a, slime_id, 2.0):
				if elapsed_seconds >= _next_request_allowed_at:
					_next_request_allowed_at = elapsed_seconds + 0.3
					client_a.request_ability_cast("starter_slash", slime_id)
				if _accepted_casts >= 4:
					step = 6
		6:
			# The loot of the slime lies on the ground and is picked up.
			var drop_id: int = _find_nearest_drop(_state_a)
			if drop_id == 0:
				if elapsed_seconds > TIMEOUT_SECONDS:
					_finish_with_error("The loot of the slime did not appear")
					return
				return
			var drop_position: Vector3 = _drop_position(_state_a, drop_id)
			if _walk_to(_state_a, drop_position):
				if elapsed_seconds >= _next_request_allowed_at:
					_next_request_allowed_at = elapsed_seconds + 0.3
					client_a.request_loot_pickup(drop_id)
				if not _loot_result.is_empty():
					if not bool(_loot_result.get("accepted", false)):
						_finish_with_error(
							"The server refused the pickup: %s"
							% str(_loot_result.get("reason", "")),
						)
						return
					step = 7
		7:
			# The client walks to the vendor and buys a potion.
			if _walk_to(_state_a, _npc_position(VENDOR_NPC_ID)):
				if elapsed_seconds >= _next_request_allowed_at:
					_next_request_allowed_at = elapsed_seconds + 0.3
					_gold_before_buy = _gold_of(_state_a)
					client_a.request_trade(VENDOR_NPC_ID, "buy", POTION_ITEM_ID, 1)
				if not _trade_result.is_empty():
					if not bool(_trade_result.get("accepted", false)):
						_finish_with_error(
							"The server refused the purchase: %s"
							% str(_trade_result.get("reason", "")),
						)
						return
					step = 8
		8:
			# The next snapshot carries the gold of the purchase.
			if _gold_of(_state_a) < _gold_before_buy:
				step = 9
		9:
			# The second client writes a message into the zone chat.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.3
				client_b.request_chat("say", CHAT_TEXT)
			if _chat_seen:
				step = 10
		10:
			# The first client invites the second one into a party.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.3
				client_a.request_party_action("invite", int(_state_b["peer_id"]))
			if _party_members_b > 0:
				step = 11
		11:
			# The second client accepts the invitation.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.3
				client_b.request_party_action("accept")
			if _party_members_a >= 2 and _party_members_b >= 2:
				print("HUB_CONTENT_LOOPBACK_OK")
				get_tree().quit(0)
				return
		_:
			pass

	if elapsed_seconds > TIMEOUT_SECONDS:
		_finish_with_error(
			"The hub scenario did not finish (step %d)" % step,
		)


## Walks the player towards a position and reports whether it arrived.
func _walk_to(state: Dictionary, target: Vector3) -> bool:
	if state.is_empty() or not state.has("position"):
		return false
	var offset: Vector3 = target - (state["position"] as Vector3)
	offset.y = 0.0
	if offset.length() <= ARRIVAL_DISTANCE:
		_send_movement(state, Vector2.ZERO)
		return true
	var direction: Vector3 = offset.normalized()
	_send_movement(state, Vector2(direction.x, direction.z))
	return false


## Walks the player towards a mob and reports whether it came into reach.
func _walk_to_mob(state: Dictionary, mob_id: String, distance: float) -> bool:
	var mob_position: Vector3 = _mob_position(state, mob_id)
	if mob_position == Vector3.INF:
		return false
	var offset: Vector3 = mob_position - (state["position"] as Vector3)
	offset.y = 0.0
	if offset.length() <= distance:
		_send_movement(state, Vector2.ZERO)
		return true
	var direction: Vector3 = offset.normalized()
	_send_movement(state, Vector2(direction.x, direction.z))
	return false


## Sends a movement intent, but not more often than the real client does.
func _send_movement(state: Dictionary, input_direction: Vector2) -> void:
	if elapsed_seconds < float(state.get("last_move_at", 0.0)) + MOVE_INTERVAL_SECONDS:
		return
	state["last_move_at"] = elapsed_seconds
	(state["client"] as ClientNet).send_movement_intent(input_direction)


## Returns the position of an NPC of the hub.
func _npc_position(npc_id: String) -> Vector3:
	var snapshot: Dictionary = _state_a.get("snapshot", {})
	for npc_entry: Array in snapshot.get("npcs", []):
		if str(npc_entry[0]) == npc_id:
			return npc_entry[1]
	return Vector3.INF


## Returns the position of a mob of the snapshot.
func _mob_position(state: Dictionary, mob_id: String) -> Vector3:
	var snapshot: Dictionary = state.get("snapshot", {})
	for mob_entry: Array in snapshot.get("mobs", []):
		if str(mob_entry[0]) == mob_id:
			return mob_entry[1]
	return Vector3.INF


## Returns the identifier of a living mob of a type.
func _find_live_mob(state: Dictionary, type_id: String) -> String:
	var snapshot: Dictionary = state.get("snapshot", {})
	for mob_entry: Array in snapshot.get("mobs", []):
		if str(mob_entry[0]).begins_with(type_id) and float(mob_entry[2]) > 0.0:
			return str(mob_entry[0])
	return ""


## Returns the identifier of the drop that lies closest to the player.
func _find_nearest_drop(state: Dictionary) -> int:
	var snapshot: Dictionary = state.get("snapshot", {})
	var player_position: Vector3 = state.get("position", Vector3.ZERO)
	var nearest_drop_id: int = 0
	var nearest_distance: float = INF
	for drop_entry: Array in snapshot.get("drops", []):
		var distance: float = player_position.distance_to(drop_entry[2])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_drop_id = int(drop_entry[0])
	return nearest_drop_id


## Returns the position of a drop of the snapshot.
func _drop_position(state: Dictionary, drop_id: int) -> Vector3:
	var snapshot: Dictionary = state.get("snapshot", {})
	for drop_entry: Array in snapshot.get("drops", []):
		if int(drop_entry[0]) == drop_id:
			return drop_entry[2]
	return Vector3.INF


## Returns the gold of the player of a client.
func _gold_of(state: Dictionary) -> int:
	var snapshot: Dictionary = state.get("snapshot", {})
	return int(snapshot.get("gold", 0))


## Reports whether a quest of the player is active.
func _quest_is_active(state: Dictionary, quest_id: String) -> bool:
	var snapshot: Dictionary = state.get("snapshot", {})
	for quest_entry: Array in snapshot.get("quests", []):
		if str(quest_entry[0]) == quest_id:
			return str(quest_entry[1]) != "turned_in"
	return false


## Reports whether a quest of the player reached its objective.
func _quest_is_completed(state: Dictionary, quest_id: String) -> bool:
	var snapshot: Dictionary = state.get("snapshot", {})
	for quest_entry: Array in snapshot.get("quests", []):
		if str(quest_entry[0]) == quest_id:
			return str(quest_entry[1]) == "completed"
	return false


func _on_hello_accepted_a(_protocol: int, player_id: int) -> void:
	_state_a["peer_id"] = player_id
	_state_a["client"] = client_a


func _on_hello_accepted_b(_protocol: int, player_id: int) -> void:
	_state_b["peer_id"] = player_id
	_state_b["client"] = client_b


func _on_snapshot_a(snapshot: Dictionary) -> void:
	_state_a["snapshot"] = snapshot
	_state_a["position"] = _own_position(snapshot, int(_state_a.get("peer_id", 0)))


func _on_snapshot_b(snapshot: Dictionary) -> void:
	_state_b["snapshot"] = snapshot
	_state_b["position"] = _own_position(snapshot, int(_state_b.get("peer_id", 0)))


## Returns the position of the player inside of a snapshot.
func _own_position(snapshot: Dictionary, peer_id: int) -> Vector3:
	for player_entry: Array in snapshot.get("players", []):
		if int(player_entry[0]) == peer_id:
			return player_entry[1]
	return Vector3.ZERO


func _on_npc_interaction_completed(
	accepted: bool,
	reason: String,
	action: String,
	_npc_id: String,
	_npc_name_key: String,
	_dialogue_key: String,
	_quests: Array,
	_quest_id: String,
	_reward_experience: int,
	_reward_gold: int,
	_reward_item_ids: Array,
	_vendor_items: Array,
) -> void:
	if str(action) == "talk":
		_talk_result = {"accepted": accepted, "reason": reason}
	elif str(action) == "turn_in":
		_turn_in_result = {"accepted": accepted, "reason": reason}


func _on_ability_cast_completed(
	accepted: bool,
	_reason: String,
	_mob_id: String,
	_health: float,
	_max_health: float,
) -> void:
	if accepted:
		_accepted_casts += 1


func _on_loot_pickup_completed(accepted: bool, reason: String, _item_id: String) -> void:
	_loot_result = {"accepted": accepted, "reason": reason}


func _on_trade_completed(
	accepted: bool,
	reason: String,
	_action: String,
	_npc_id: String,
	_item_id: String,
	_quantity: int,
	_price: int,
	_gold: int,
) -> void:
	_trade_result = {"accepted": accepted, "reason": reason}


func _on_chat_message_received(
	_channel: String,
	_sender_id: int,
	_sender_name: String,
	_text: String,
	_system_key: String,
	_reason: String,
) -> void:
	if _text == CHAT_TEXT:
		_chat_seen = true


func _on_party_result_a(
	_accepted: bool,
	_reason: String,
	_action: String,
	_party_id: int,
	_leader_peer_id: int,
	_members: Array,
	_inviter_peer_id: int,
	_inviter_name: String,
) -> void:
	_party_members_a = _members.size()


func _on_party_result_b(
	_accepted: bool,
	_reason: String,
	_action: String,
	_party_id: int,
	_leader_peer_id: int,
	_members: Array,
	_inviter_peer_id: int,
	_inviter_name: String,
) -> void:
	_party_members_b = _members.size()


func _on_movement_intent(peer_id: int, input_direction: Vector2) -> void:
	server_world.set_input_direction(peer_id, input_direction)


func _on_ability_cast_requested(
	peer_id: int,
	ability_id: String,
	target_mob_id: String,
) -> void:
	var result: Dictionary = server_world.cast_ability(peer_id, ability_id, target_mob_id)
	listener.send_ability_cast_result(peer_id, result)


func _on_loot_pickup_requested(peer_id: int, drop_id: int) -> void:
	var result: Dictionary = server_world.pickup_loot(peer_id, drop_id)
	listener.send_loot_pickup_result(peer_id, result)


func _on_equip_item_requested(peer_id: int, item_id: String) -> void:
	var result: Dictionary = server_world.equip_item(peer_id, item_id)
	listener.send_equipment_result(peer_id, "equip", result)


func _on_npc_interact_requested(
	peer_id: int,
	npc_id: String,
	action: String,
	quest_id: String,
) -> void:
	var result: Dictionary = server_world.interact_npc(peer_id, npc_id, action, quest_id)
	listener.send_npc_interact_result(peer_id, result)


func _on_trade_requested(
	peer_id: int,
	npc_id: String,
	action: String,
	item_id: String,
	quantity: int,
) -> void:
	var result: Dictionary = server_world.trade(peer_id, npc_id, action, item_id, quantity)
	listener.send_trade_result(peer_id, result)


func _on_chat_requested(peer_id: int, channel: String, text: String) -> void:
	var result: Dictionary = server_world.chat(peer_id, channel, text)
	if not bool(result["accepted"]):
		listener.send_chat_message(peer_id, {
			"channel": "system",
			"sender_peer_id": 0,
			"sender_name": "",
			"text": "",
			"system_key": "",
			"reason": str(result["reason"]),
		})
		return
	var message: Dictionary = result["message"]
	for recipient_id: int in result["recipients"]:
		listener.send_chat_message(recipient_id, message)


func _on_party_requested(peer_id: int, action: String, target_peer_id: int) -> void:
	var result: Dictionary = server_world.party_request(peer_id, action, target_peer_id)
	listener.send_party_result(peer_id, result)
	for notification: Dictionary in result["notifications"]:
		listener.send_party_result(int(notification["peer_id"]), notification["result"])
	for chat_message: Dictionary in result["chat_messages"]:
		for recipient_id: int in chat_message["recipients"]:
			listener.send_chat_message(recipient_id, chat_message["message"])


func _finish_with_error(message: String) -> void:
	push_error("HUB_CONTENT_LOOPBACK_FAILED: %s" % message)
	get_tree().quit(1)
