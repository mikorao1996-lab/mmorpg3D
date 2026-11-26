class_name ServerWorld
extends RefCounted

const ServerZoneType: GDScript = preload("res://server/world/server_zone.gd")
const ChatSystemType: GDScript = preload("res://server/systems/chat_system.gd")
const PartySystemType: GDScript = preload("res://server/systems/party_system.gd")

var _zones: Dictionary = {}
var _peer_zones: Dictionary = {}
var _game_data_registry: Dictionary = {}
var _ability_ready_at_ms: Dictionary = {}
var _default_zone_id: String
var _chat_system: ChatSystem
var _party_system: PartySystem
var _player_names: Dictionary = {}


func _init(config: Dictionary, game_data_registry: Dictionary) -> void:
	_game_data_registry = game_data_registry
	var zone_ids: Array = config["zone_ids"]
	_default_zone_id = zone_ids[0]
	for zone_id: String in zone_ids:
		_zones[zone_id] = ServerZoneType.new(zone_id, config, game_data_registry)
	_chat_system = ChatSystemType.new(config)
	_party_system = PartySystemType.new(config)


## Stores the display name of a player.
##
## The name comes from the handshake and is only used for the chat; the game
## itself never depends on it.
func set_player_name(peer_id: int, player_name: String) -> void:
	if player_name.strip_edges().is_empty():
		return
	_player_names[peer_id] = player_name


## Returns the display name of a player.
func get_player_name(peer_id: int) -> String:
	if _player_names.has(peer_id):
		return str(_player_names[peer_id])
	return "Player %d" % peer_id


## Sends a chat message.
##
## The server decides who receives the message: a zone message reaches every
## player of the zone, and a party message reaches only the members of the
## party of the sender.
func chat(peer_id: int, channel: String, text: String) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"message": {},
		"recipients": [],
	}
	if not _peer_zones.has(peer_id):
		result["reason"] = "invalid_player"
		return result
	if (
		channel != ChatSystemType.CHANNEL_SAY
		and channel != ChatSystemType.CHANNEL_PARTY
	):
		result["reason"] = "invalid_channel"
		return result
	var rate_result: Dictionary = _chat_system.check_rate(peer_id, Time.get_ticks_msec())
	if not bool(rate_result["ok"]):
		result["reason"] = str(rate_result["reason"])
		return result
	var validation: Dictionary = _chat_system.validate_message(text)
	if not bool(validation["ok"]):
		result["reason"] = str(validation["reason"])
		return result

	var recipients: Array[int] = []
	if channel == ChatSystemType.CHANNEL_PARTY:
		var party: Dictionary = _party_system.get_party_of(peer_id)
		if party.is_empty():
			result["reason"] = "not_in_party"
			return result
		for member_id: Variant in (party["members"] as Dictionary):
			recipients.append(int(member_id))
	else:
		var zone: RefCounted = _zones[_peer_zones[peer_id]]
		recipients = zone.get_player_ids()

	var message: Dictionary = _chat_system.build_message(
		channel,
		peer_id,
		get_player_name(peer_id),
		str(validation["text"]),
	)
	_chat_system.remember(message)
	result["accepted"] = true
	result["message"] = message
	result["recipients"] = recipients
	return result


## Builds a system message for a player and the recipients of its zone.
func build_system_message(system_key: String, peer_id: int) -> Dictionary:
	var recipients: Array[int] = []
	if _peer_zones.has(peer_id):
		var zone: RefCounted = _zones[_peer_zones[peer_id]]
		recipients = zone.get_player_ids()
	return {
		"message": _chat_system.build_message(
			ChatSystemType.CHANNEL_SYSTEM,
			peer_id,
			get_player_name(peer_id),
			"",
			system_key,
		),
		"recipients": recipients,
	}


## Returns the peers of the members of a party.
func _collect_party_members(party: Dictionary) -> Array[int]:
	var members: Array[int] = []
	if party.is_empty():
		return members
	for member_id: Variant in (party["members"] as Dictionary):
		members.append(int(member_id))
	return members


## Handles a party request.
##
## The supported actions are `invite`, `accept`, and `leave`. The result
## carries the state of the party for the requesting player and the
## notifications that the server has to deliver to the other players.
func party_request(peer_id: int, action: String, target_peer_id: int) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"action": action,
		"party_id": 0,
		"leader_peer_id": 0,
		"members": [],
		"inviter_peer_id": 0,
		"inviter_name": "",
		"notifications": [],
		"chat_messages": [],
	}
	if not _peer_zones.has(peer_id):
		result["reason"] = "invalid_player"
		return result
	if not PartySystemType.ACTIONS.has(action):
		result["reason"] = "invalid_action"
		return result
	match action:
		PartySystemType.ACTION_INVITE:
			return _party_invite(peer_id, target_peer_id, result)
		PartySystemType.ACTION_ACCEPT:
			return _party_accept(peer_id, result)
		PartySystemType.ACTION_LEAVE:
			return _party_leave(peer_id, result)
	return result


## Invites a player into the party of the sender.
func _party_invite(
	peer_id: int,
	target_peer_id: int,
	result: Dictionary,
) -> Dictionary:
	if target_peer_id <= 0 or not _peer_zones.has(target_peer_id):
		result["reason"] = "invalid_target"
		return result
	if _peer_zones[peer_id] != _peer_zones[target_peer_id]:
		result["reason"] = "different_zone"
		return result
	var party: Dictionary = _party_system.get_party_of(peer_id)
	var party_created: bool = false
	if party.is_empty():
		var create_result: Dictionary = _party_system.create_party(
			peer_id,
			get_player_name(peer_id),
			str(_peer_zones[peer_id]),
		)
		if not bool(create_result["ok"]):
			result["reason"] = str(create_result["reason"])
			return result
		party = create_result["party"]
		party_created = true
	var invite_result: Dictionary = _party_system.invite(
		int(party["id"]),
		peer_id,
		get_player_name(peer_id),
		target_peer_id,
	)
	if not bool(invite_result["ok"]):
		result["reason"] = str(invite_result["reason"])
		if party_created:
			# The party was only created for this invite, so an empty party is
			# removed again.
			_party_system.leave(peer_id)
		return result
	result["accepted"] = true
	result["party_id"] = int(party["id"])
	result["leader_peer_id"] = int(party["leader_peer_id"])
	result["members"] = _party_system.build_members(party)
	result["inviter_peer_id"] = peer_id
	result["inviter_name"] = get_player_name(peer_id)
	result["notifications"].append({
		"peer_id": target_peer_id,
		"result": {
			"accepted": true,
			"reason": "",
			"action": PartySystemType.ACTION_INVITE,
			"party_id": int(party["id"]),
			"leader_peer_id": int(party["leader_peer_id"]),
			"members": _party_system.build_members(party),
			"inviter_peer_id": peer_id,
			"inviter_name": get_player_name(peer_id),
		},
	})
	return result


## Accepts the pending party invite of a player.
func _party_accept(peer_id: int, result: Dictionary) -> Dictionary:
	var accept_result: Dictionary = _party_system.accept(
		peer_id,
		get_player_name(peer_id),
	)
	if not bool(accept_result["ok"]):
		result["reason"] = str(accept_result["reason"])
		return result
	var party: Dictionary = accept_result["party"]
	result["accepted"] = true
	result["party_id"] = int(party["id"])
	result["leader_peer_id"] = int(party["leader_peer_id"])
	result["members"] = _party_system.build_members(party)
	result["chat_messages"].append({
		"message": _chat_system.build_message(
			ChatSystemType.CHANNEL_SYSTEM,
			peer_id,
			get_player_name(peer_id),
			"",
			"chat_system_party_joined",
		),
		"recipients": _collect_party_members(party),
	})
	for member_id: Variant in (party["members"] as Dictionary):
		if int(member_id) == peer_id:
			continue
		result["notifications"].append({
			"peer_id": int(member_id),
			"result": {
				"accepted": true,
				"reason": "",
				"action": PartySystemType.ACTION_ACCEPT,
				"party_id": int(party["id"]),
				"leader_peer_id": int(party["leader_peer_id"]),
				"members": _party_system.build_members(party),
				"inviter_peer_id": 0,
				"inviter_name": "",
			},
		})
	return result


## Removes a player from the party.
func _party_leave(peer_id: int, result: Dictionary) -> Dictionary:
	var leave_result: Dictionary = _party_system.leave(peer_id)
	if not bool(leave_result["ok"]):
		result["reason"] = str(leave_result["reason"])
		return result
	var party: Dictionary = leave_result["party"]
	result["accepted"] = true
	result["party_id"] = int(party.get("id", 0))
	result["leader_peer_id"] = int(party.get("leader_peer_id", 0))
	result["members"] = _party_system.build_members(party)
	result["chat_messages"].append({
		"message": _chat_system.build_message(
			ChatSystemType.CHANNEL_SYSTEM,
			peer_id,
			get_player_name(peer_id),
			"",
			"chat_system_party_left",
		),
		"recipients": _collect_party_members(party),
	})
	for member_id: Variant in (party["members"] as Dictionary):
		result["notifications"].append({
			"peer_id": int(member_id),
			"result": {
				"accepted": true,
				"reason": "",
				"action": PartySystemType.ACTION_LEAVE,
				"party_id": int(party.get("id", 0)),
				"leader_peer_id": int(party.get("leader_peer_id", 0)),
				"members": _party_system.build_members(party),
				"inviter_peer_id": 0,
				"inviter_name": "",
			},
		})
	return result


func add_player(peer_id: int) -> void:
	if _peer_zones.has(peer_id):
		return
	var default_zone: RefCounted = _zones[_default_zone_id]
	default_zone.add_player(peer_id)
	_peer_zones[peer_id] = _default_zone_id


## Adds a player with the progress of a stored character.
##
## The character returns to the zone it was saved in, and falls back to the
## default zone when that zone is not configured anymore.
func add_player_with_restored_state(peer_id: int, restored_state: Dictionary) -> bool:
	if _peer_zones.has(peer_id):
		return false
	var target_zone_id: String = str(restored_state.get("zone_id", ""))
	if not _zones.has(target_zone_id):
		target_zone_id = _default_zone_id
	var zone: RefCounted = _zones[target_zone_id]
	if not zone.call("add_player_with_restored_state", peer_id, restored_state):
		return false
	_peer_zones[peer_id] = target_zone_id
	return true


## Exports the live player state of a peer for the persistence.
func export_player_state(peer_id: int) -> Dictionary:
	if not _peer_zones.has(peer_id):
		return {}
	var zone: RefCounted = _zones[_peer_zones[peer_id]]
	return zone.export_player_state(peer_id)


func remove_player(peer_id: int) -> void:
	if not _peer_zones.has(peer_id):
		return
	var zone_id: String = _peer_zones[peer_id]
	var zone: RefCounted = _zones[zone_id]
	zone.remove_player(peer_id)
	_peer_zones.erase(peer_id)
	_ability_ready_at_ms.erase(peer_id)
	_chat_system.forget_peer(peer_id)
	_party_system.forget_peer(peer_id)
	_player_names.erase(peer_id)


func set_input_direction(peer_id: int, input_direction: Vector2) -> bool:
	if not _peer_zones.has(peer_id):
		return false
	var zone_id: String = _peer_zones[peer_id]
	var zone: RefCounted = _zones[zone_id]
	return zone.set_input_direction(peer_id, input_direction)


func move_player_to_zone(peer_id: int, target_zone_id: String) -> bool:
	if not _peer_zones.has(peer_id) or not _zones.has(target_zone_id):
		return false
	var current_zone_id: String = _peer_zones[peer_id]
	if current_zone_id == target_zone_id:
		return true

	var current_zone: RefCounted = _zones[current_zone_id]
	var target_zone: RefCounted = _zones[target_zone_id]
	var player_state: Dictionary = current_zone.get_player_state(peer_id)
	current_zone.remove_player(peer_id)
	target_zone.add_player_with_state(peer_id, player_state)
	_peer_zones[peer_id] = target_zone_id
	return true


func cast_ability(peer_id: int, ability_id: String, target_mob_id: String) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"mob_id": target_mob_id,
		"health": 0.0,
		"max_health": 0.0,
	}
	if not _peer_zones.has(peer_id):
		result["reason"] = "invalid_player"
		return result
	var abilities: Dictionary = _game_data_registry["abilities"]
	if not abilities.has(ability_id):
		result["reason"] = "unknown_ability"
		return result
	var ability: Dictionary = abilities[ability_id]
	if (
		ability["target_type"] == "enemy"
		and ability["effect_type"] == "damage"
	):
		pass
	elif (
		ability["target_type"] == "self"
		and ability["effect_type"] == "heal"
	):
		pass
	else:
		result["reason"] = "unsupported_ability"
		return result

	var zone_id: String = _peer_zones[peer_id]
	var zone: RefCounted = _zones[zone_id]
	var player_state: Dictionary = zone.get_player_state(peer_id)
	if float(player_state["health"]) <= 0.0:
		result["reason"] = "player_dead"
		return result

	var ability_resource_cost: float = float(ability["resource_cost"])
	if float(player_state["resource"]) < ability_resource_cost:
		result["reason"] = "resource"
		return result

	var now_ms: int = Time.get_ticks_msec()
	var player_cooldowns: Dictionary = _ability_ready_at_ms.get(peer_id, {})
	if now_ms < int(player_cooldowns.get(ability_id, 0)):
		result["reason"] = "cooldown"
		return result

	if ability["target_type"] == "self":
		if not zone.spend_player_resource(peer_id, ability_resource_cost):
			result["reason"] = "resource"
			return result
		if not zone.heal_player(peer_id, float(ability["magnitude"])):
			result["reason"] = "invalid_heal_target"
			return result
		player_cooldowns[ability_id] = now_ms + ceili(float(ability["cooldown_seconds"]) * 1000.0)
		_ability_ready_at_ms[peer_id] = player_cooldowns
		result["accepted"] = true
		return result

	var target_state: Dictionary = zone.get_mob_state(target_mob_id)
	if target_state.is_empty():
		result["reason"] = "target_not_found"
		return result
	result["health"] = target_state["health"]
	result["max_health"] = target_state["max_health"]
	if float(target_state["health"]) <= 0.0:
		result["reason"] = "target_dead"
		return result

	var player_position: Vector3 = zone.get_player_position(peer_id)
	var ability_range: float = float(ability["range"])
	if (
		player_position.distance_squared_to(target_state["position"])
		> ability_range * ability_range
	):
		result["reason"] = "out_of_range"
		return result
	var damage: float = (
		float(ability["magnitude"]) * float(player_state["attack_multiplier"])
		+ float(player_state["equipment_attack"])
	)
	if not zone.damage_mob(target_mob_id, damage):
		result["reason"] = "target_dead"
		return result
	if not zone.spend_player_resource(peer_id, ability_resource_cost):
		result["reason"] = "resource"
		return result

	player_cooldowns[ability_id] = now_ms + ceili(float(ability["cooldown_seconds"]) * 1000.0)
	_ability_ready_at_ms[peer_id] = player_cooldowns
	var updated_target_state: Dictionary = zone.get_mob_state(target_mob_id)
	if float(updated_target_state["health"]) == 0.0:
		var mob_type: String = zone.get_mob_type(target_mob_id)
		var mob_definition: Dictionary = _game_data_registry["mobs"].get(mob_type, {})
		var experience_result: Dictionary = zone.award_experience(
			peer_id,
			int(mob_definition["experience_reward"]),
		)
		if not bool(experience_result.get("ok", false)):
			push_error(
				"Could not award experience to peer %d: %s"
				% [peer_id, str(experience_result.get("error", "Unknown error."))],
			)
		var gold_result: Dictionary = zone.award_gold(
			peer_id,
			int(mob_definition["gold_reward"]),
		)
		if not bool(gold_result.get("ok", false)):
			push_error(
				"Could not award gold to peer %d: %s"
				% [peer_id, str(gold_result.get("error", "Unknown error."))],
			)
		var loot_result: Dictionary = zone.spawn_loot_for_mob(target_mob_id)
		if not bool(loot_result.get("ok", false)):
			push_error(
				"Could not spawn loot for mob %s: %s"
				% [target_mob_id, str(loot_result.get("error", "Unknown error."))],
			)
		zone.record_quest_kill(peer_id, target_mob_id)
	result["accepted"] = true
	result["health"] = updated_target_state["health"]
	result["max_health"] = updated_target_state["max_health"]
	return result


func pickup_loot(peer_id: int, drop_id: int) -> Dictionary:
	if not _peer_zones.has(peer_id):
		return {
			"accepted": false,
			"reason": "invalid_player",
			"item_id": "",
		}
	var zone: RefCounted = _zones[_peer_zones[peer_id]]
	return zone.pickup_loot(peer_id, drop_id)


func equip_item(peer_id: int, item_id: String) -> Dictionary:
	if not _peer_zones.has(peer_id):
		return {
			"accepted": false,
			"reason": "invalid_player",
			"item_id": item_id,
			"slot_id": "",
		}
	var zone: RefCounted = _zones[_peer_zones[peer_id]]
	return zone.equip_item(peer_id, item_id)


func unequip_item(peer_id: int, slot_id: String) -> Dictionary:
	if not _peer_zones.has(peer_id):
		return {
			"accepted": false,
			"reason": "invalid_player",
			"item_id": "",
			"slot_id": slot_id,
		}
	var zone: RefCounted = _zones[_peer_zones[peer_id]]
	return zone.unequip_item(peer_id, slot_id)


func use_item(peer_id: int, item_id: String) -> Dictionary:
	if not _peer_zones.has(peer_id):
		return {
			"accepted": false,
			"reason": "invalid_player",
			"item_id": item_id,
			"health": 0.0,
			"max_health": 0.0,
			"resource": 0.0,
			"max_resource": 0.0,
		}
	var zone: RefCounted = _zones[_peer_zones[peer_id]]
	return zone.use_item(peer_id, item_id)


## Routes an NPC interaction to the zone of the player.
func interact_npc(
	peer_id: int,
	npc_id: String,
	action: String,
	quest_id: String,
) -> Dictionary:
	if not _peer_zones.has(peer_id):
		return {
			"accepted": false,
			"reason": "invalid_player",
			"action": action,
			"npc_id": npc_id,
			"npc_name_key": "",
			"dialogue_key": "",
			"quests": [],
			"quest_id": quest_id,
			"reward_experience": 0,
			"reward_gold": 0,
			"reward_item_ids": [],
			"vendor_items": [],
		}
	var zone: RefCounted = _zones[_peer_zones[peer_id]]
	return zone.interact_npc(peer_id, npc_id, action, quest_id)


## Routes a trade request to the zone of the player.
func trade(
	peer_id: int,
	npc_id: String,
	action: String,
	item_id: String,
	quantity: int,
) -> Dictionary:
	if not _peer_zones.has(peer_id):
		return {
			"accepted": false,
			"reason": "invalid_player",
			"action": action,
			"npc_id": npc_id,
			"item_id": item_id,
			"quantity": quantity,
			"price": 0,
			"gold": 0,
		}
	var zone: RefCounted = _zones[_peer_zones[peer_id]]
	return zone.trade(peer_id, npc_id, action, item_id, quantity)


func advance(delta: float) -> bool:
	var snapshot_due: bool = false
	for zone: RefCounted in _zones.values():
		snapshot_due = zone.advance(delta) or snapshot_due
	return snapshot_due


func create_snapshots() -> Dictionary:
	var snapshots: Dictionary = {}
	for zone: RefCounted in _zones.values():
		snapshots.merge(zone.create_snapshots())
	return snapshots
