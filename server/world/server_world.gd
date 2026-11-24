class_name ServerWorld
extends RefCounted

const ServerZoneType: GDScript = preload("res://server/world/server_zone.gd")

var _zones: Dictionary = {}
var _peer_zones: Dictionary = {}
var _game_data_registry: Dictionary = {}
var _ability_ready_at_ms: Dictionary = {}
var _default_zone_id: String


func _init(config: Dictionary, game_data_registry: Dictionary) -> void:
	_game_data_registry = game_data_registry
	var zone_ids: Array = config["zone_ids"]
	_default_zone_id = zone_ids[0]
	for zone_id: String in zone_ids:
		_zones[zone_id] = ServerZoneType.new(zone_id, config, game_data_registry)


func add_player(peer_id: int) -> void:
	if _peer_zones.has(peer_id):
		return
	var default_zone: RefCounted = _zones[_default_zone_id]
	default_zone.add_player(peer_id)
	_peer_zones[peer_id] = _default_zone_id


func remove_player(peer_id: int) -> void:
	if not _peer_zones.has(peer_id):
		return
	var zone_id: String = _peer_zones[peer_id]
	var zone: RefCounted = _zones[zone_id]
	zone.remove_player(peer_id)
	_peer_zones.erase(peer_id)
	_ability_ready_at_ms.erase(peer_id)


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
		var mob_definition: Dictionary = _game_data_registry["mobs"][target_mob_id]
		var experience_result: Dictionary = zone.award_experience(
			peer_id,
			int(mob_definition["experience_reward"]),
		)
		if not bool(experience_result.get("ok", false)):
			push_error(
				"Could not award experience to peer %d: %s"
				% [peer_id, str(experience_result.get("error", "Unknown error."))],
			)
		var loot_result: Dictionary = zone.spawn_loot_for_mob(target_mob_id)
		if not bool(loot_result.get("ok", false)):
			push_error(
				"Could not spawn loot for mob %s: %s"
				% [target_mob_id, str(loot_result.get("error", "Unknown error."))],
			)
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
