class_name ServerZone
extends RefCounted

const MovementSimulationType: GDScript = preload("res://shared/sim/movement_simulation.gd")
const InventoryComponentType: GDScript = preload("res://server/systems/inventory_component.gd")
const EquipmentComponentType: GDScript = preload("res://server/systems/equipment_component.gd")
const EquipmentSystemType: GDScript = preload("res://server/systems/equipment_system.gd")
const LootSystemType: GDScript = preload("res://server/systems/loot_system.gd")
const ConsumableSystemType: GDScript = preload("res://server/systems/consumable_system.gd")

var zone_id: String
var _movement_speed: float
var _player_respawn_seconds: float
var _max_input_magnitude: float
var _world_half_extent: float
var _interest_radius: float
var _spawn_spacing: float
var _simulation_step_seconds: float
var _snapshot_interval_seconds: float
var _inventory_slot_count: int
var _loot_pickup_range: float
var _players: Dictionary = {}
var _simulation_accumulator: float = 0.0
var _snapshot_accumulator: float = 0.0
var _next_spawn_index: int = 0
var _mob_definitions: Dictionary = {}
var _item_definitions: Dictionary = {}
var _progression_definitions: Dictionary = {}
var _mobs: Dictionary = {}
var _loot_system: LootSystem = LootSystemType.new()


func _init(
	configured_zone_id: String,
	config: Dictionary,
	game_data_registry: Dictionary,
) -> void:
	zone_id = configured_zone_id
	_movement_speed = float(config["movement_speed"])
	_player_respawn_seconds = float(config["player_respawn_seconds"])
	_max_input_magnitude = float(config["max_input_magnitude"])
	_world_half_extent = float(config["world_half_extent"])
	_interest_radius = float(config["interest_radius"])
	_spawn_spacing = float(config["spawn_spacing"])
	_simulation_step_seconds = float(config["simulation_step_seconds"])
	_snapshot_interval_seconds = float(config["snapshot_interval_seconds"])
	_inventory_slot_count = int(config["inventory_slot_count"])
	_loot_pickup_range = float(config["loot_pickup_range"])
	_mob_definitions = game_data_registry["mobs"]
	_item_definitions = game_data_registry["items"]
	_progression_definitions = game_data_registry["progression"]
	for mob_id: String in _mob_definitions:
		var definition: Dictionary = _mob_definitions[mob_id]
		var spawn_position: Array = definition["spawn_position"]
		_mobs[mob_id] = {
			"position": Vector3(
				float(spawn_position[0]),
				float(spawn_position[1]),
				float(spawn_position[2]),
			),
			"home_position": Vector3(
				float(spawn_position[0]),
				float(spawn_position[1]),
				float(spawn_position[2]),
			),
			"health": float(definition["health"]),
			"respawn_remaining_seconds": 0.0,
			"attack_remaining_seconds": 0.0,
			"loot_spawned": false,
		}


func add_player(peer_id: int) -> void:
	if _players.has(peer_id):
		return
	var spawn_x: float = float(_next_spawn_index) * _spawn_spacing
	_next_spawn_index += 1
	add_player_at(peer_id, Vector3(spawn_x, 0.0, 0.0))


func add_player_at(peer_id: int, position: Vector3) -> void:
	if _players.has(peer_id):
		return
	_players[peer_id] = _create_player_state(position)


func add_player_with_state(peer_id: int, player_state: Dictionary) -> void:
	if _players.has(peer_id):
		return
	var copied_state: Dictionary = player_state.duplicate(true)
	copied_state["spawn_position"] = copied_state["position"]
	copied_state["input"] = Vector2.ZERO
	_players[peer_id] = copied_state


func remove_player(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	_players.erase(peer_id)


func get_player_position(peer_id: int) -> Vector3:
	if not _players.has(peer_id):
		push_error("Cannot retrieve position for missing player %d in zone %s" % [peer_id, zone_id])
		return Vector3.ZERO
	var player_state: Dictionary = _players[peer_id]
	return player_state["position"]


func get_player_state(peer_id: int) -> Dictionary:
	if not _players.has(peer_id):
		return {}
	return _players[peer_id].duplicate(true)


func award_experience(peer_id: int, amount: int) -> Dictionary:
	if not _players.has(peer_id):
		return {"ok": false, "error": "Player is not in this zone."}
	if amount < 0:
		return {"ok": false, "error": "Experience award must not be negative."}

	var player_state: Dictionary = _players[peer_id]
	player_state["experience"] = int(player_state["experience"]) + amount
	var old_level: int = int(player_state["level"])
	var max_level: int = _progression_definitions.size()
	while int(player_state["level"]) < max_level:
		var next_level: int = int(player_state["level"]) + 1
		var next_definition: Dictionary = _progression_definitions["level_%d" % next_level]
		if int(player_state["experience"]) < int(next_definition["experience_required"]):
			break
		_apply_level_definition(player_state, next_definition)

	return {
		"ok": true,
		"leveled_up": int(player_state["level"]) > old_level,
		"level": int(player_state["level"]),
		"experience": int(player_state["experience"]),
	}


func spend_player_resource(peer_id: int, cost: float) -> bool:
	if not _players.has(peer_id) or not is_finite(cost) or cost < 0.0:
		return false
	var player_state: Dictionary = _players[peer_id]
	if float(player_state["health"]) <= 0.0:
		return false
	if float(player_state["resource"]) < cost:
		return false
	player_state["resource"] = float(player_state["resource"]) - cost
	return true


func heal_player(peer_id: int, amount: float) -> bool:
	if not _players.has(peer_id) or not is_finite(amount) or amount <= 0.0:
		return false
	var player_state: Dictionary = _players[peer_id]
	if float(player_state["health"]) <= 0.0:
		return false
	player_state["health"] = minf(
		float(player_state["max_health"]),
		float(player_state["health"]) + amount,
	)
	return true


func damage_player(peer_id: int, damage: float) -> bool:
	if not _players.has(peer_id) or not is_finite(damage) or damage <= 0.0:
		return false
	var player_state: Dictionary = _players[peer_id]
	if float(player_state["health"]) <= 0.0:
		return false
	var effective_damage: float = maxf(
		0.0,
		damage - float(player_state["defense"]),
	)
	player_state["health"] = maxf(0.0, float(player_state["health"]) - effective_damage)
	if float(player_state["health"]) == 0.0:
		player_state["input"] = Vector2.ZERO
		player_state["respawn_remaining_seconds"] = _player_respawn_seconds
	return true


func get_mob_state(mob_id: String) -> Dictionary:
	if not _mobs.has(mob_id):
		return {}
	var mob_state: Dictionary = _mobs[mob_id]
	var mob_definition: Dictionary = _mob_definitions[mob_id]
	return {
		"position": mob_state["position"],
		"health": mob_state["health"],
		"max_health": float(mob_definition["health"]),
	}


func damage_mob(mob_id: String, damage: float) -> bool:
	if not _mobs.has(mob_id) or not is_finite(damage) or damage <= 0.0:
		return false
	var mob_state: Dictionary = _mobs[mob_id]
	if float(mob_state["health"]) <= 0.0:
		return false
	var definition: Dictionary = _mob_definitions[mob_id]
	var effective_damage: float = maxf(
		0.0,
		damage - float(definition["defense"]),
	)
	mob_state["health"] = maxf(0.0, float(mob_state["health"]) - effective_damage)
	if float(mob_state["health"]) == 0.0:
		mob_state["respawn_remaining_seconds"] = float(definition["respawn_seconds"])
		mob_state["loot_spawned"] = false
	return true


func spawn_loot_for_mob(mob_id: String) -> Dictionary:
	if not _mobs.has(mob_id):
		return {"ok": false, "error": "Mob is not present in this zone."}
	return _loot_system.spawn_for_mob(_mobs[mob_id], _mob_definitions[mob_id])


func pickup_loot(peer_id: int, drop_id: int) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"item_id": "",
	}
	if not _players.has(peer_id):
		result["reason"] = "invalid_player"
		return result
	return _loot_system.pickup(
		_players[peer_id],
		drop_id,
		_loot_pickup_range,
		_item_definitions,
	)


func equip_item(peer_id: int, item_id: String) -> Dictionary:
	if not _players.has(peer_id):
		return {
			"accepted": false,
			"reason": "invalid_player",
			"item_id": item_id,
			"slot_id": "",
		}
	return EquipmentSystemType.equip_item(_players[peer_id], item_id, _item_definitions)


func unequip_item(peer_id: int, slot_id: String) -> Dictionary:
	if not _players.has(peer_id):
		return {
			"accepted": false,
			"reason": "invalid_player",
			"item_id": "",
			"slot_id": slot_id,
		}
	return EquipmentSystemType.unequip_item(
		_players[peer_id],
		slot_id,
		_item_definitions,
	)


## Uses a consumable item owned by the player.
func use_item(peer_id: int, item_id: String) -> Dictionary:
	if not _players.has(peer_id):
		return {
			"accepted": false,
			"reason": "invalid_player",
			"item_id": item_id,
			"health": 0.0,
			"max_health": 0.0,
			"resource": 0.0,
			"max_resource": 0.0,
		}
	return ConsumableSystemType.use_item(
		_players[peer_id],
		item_id,
		_item_definitions,
	)


func set_input_direction(peer_id: int, input_direction: Vector2) -> bool:
	if not _players.has(peer_id):
		return false
	var input_magnitude: float = input_direction.length()
	if not is_finite(input_magnitude) or input_magnitude > _max_input_magnitude:
		return false
	var player_state: Dictionary = _players[peer_id]
	player_state["input"] = (
		Vector2.ZERO if float(player_state["health"]) <= 0.0 else input_direction
	)
	return true


func advance(delta: float) -> bool:
	_simulation_accumulator += delta
	var snapshot_due: bool = false
	while _simulation_accumulator >= _simulation_step_seconds:
		for peer_id: int in _players:
			var player_state: Dictionary = _players[peer_id]
			if float(player_state["health"]) <= 0.0:
				player_state["input"] = Vector2.ZERO
				continue
			player_state["position"] = MovementSimulationType.advance(
				player_state["position"],
				player_state["input"],
				_simulation_step_seconds,
				_movement_speed,
				_max_input_magnitude,
				_world_half_extent,
			)
		_advance_mob_respawns()
		_advance_player_respawns()
		_advance_mob_ai()
		_simulation_accumulator -= _simulation_step_seconds
		_snapshot_accumulator += _simulation_step_seconds
		if _snapshot_accumulator >= _snapshot_interval_seconds:
			_snapshot_accumulator -= _snapshot_interval_seconds
			snapshot_due = true
	return snapshot_due


func _advance_mob_respawns() -> void:
	for mob_id: String in _mobs:
		var mob_state: Dictionary = _mobs[mob_id]
		if float(mob_state["health"]) > 0.0:
			continue
		mob_state["respawn_remaining_seconds"] = maxf(
			0.0,
			float(mob_state["respawn_remaining_seconds"]) - _simulation_step_seconds,
		)
		if float(mob_state["respawn_remaining_seconds"]) == 0.0:
			var definition: Dictionary = _mob_definitions[mob_id]
			mob_state["health"] = float(definition["health"])
			mob_state["position"] = mob_state["home_position"]
			mob_state["attack_remaining_seconds"] = 0.0


func _advance_mob_ai() -> void:
	for mob_id: String in _mobs:
		var mob_state: Dictionary = _mobs[mob_id]
		if float(mob_state["health"]) <= 0.0:
			continue
		var definition: Dictionary = _mob_definitions[mob_id]
		var mob_position: Vector3 = mob_state["position"]
		var nearest_peer_id: int = 0
		var nearest_distance_squared: float = INF
		var aggro_range: float = float(definition["aggro_range"])
		for peer_id: int in _players:
			var player_state: Dictionary = _players[peer_id]
			if float(player_state["health"]) <= 0.0:
				continue
			var offset: Vector3 = player_state["position"] - mob_position
			offset.y = 0.0
			var distance_squared: float = offset.length_squared()
			if (
				distance_squared <= aggro_range * aggro_range
				and distance_squared < nearest_distance_squared
			):
				nearest_peer_id = peer_id
				nearest_distance_squared = distance_squared
		if nearest_peer_id == 0:
			continue

		var target_state: Dictionary = _players[nearest_peer_id]
		var target_offset: Vector3 = target_state["position"] - mob_position
		target_offset.y = 0.0
		var distance_to_target: float = target_offset.length()
		var attack_range: float = float(definition["attack_range"])
		var attack_remaining: float = maxf(
			0.0,
			float(mob_state["attack_remaining_seconds"]) - _simulation_step_seconds,
		)
		if distance_to_target > attack_range:
			var move_distance: float = minf(
				distance_to_target - attack_range,
				float(definition["move_speed"]) * _simulation_step_seconds,
			)
			if move_distance > 0.0 and distance_to_target > 0.0:
				mob_position += target_offset / distance_to_target * move_distance
				mob_state["position"] = mob_position
			mob_state["attack_remaining_seconds"] = attack_remaining
			continue
		if attack_remaining <= 0.0:
			damage_player(nearest_peer_id, float(definition["attack"]))
			attack_remaining = float(definition["attack_interval_seconds"])
		mob_state["attack_remaining_seconds"] = attack_remaining


func _advance_player_respawns() -> void:
	for peer_id: int in _players:
		var player_state: Dictionary = _players[peer_id]
		if float(player_state["health"]) > 0.0:
			continue
		player_state["respawn_remaining_seconds"] = maxf(
			0.0,
			float(player_state["respawn_remaining_seconds"]) - _simulation_step_seconds,
		)
		if float(player_state["respawn_remaining_seconds"]) == 0.0:
			player_state["health"] = player_state["max_health"]
			player_state["resource"] = player_state["max_resource"]
			player_state["position"] = player_state["spawn_position"]
			player_state["input"] = Vector2.ZERO


func create_snapshots() -> Dictionary:
	var snapshots: Dictionary = {}
	for observer_id: int in _players:
		snapshots[observer_id] = _create_snapshot_for(observer_id)
	return snapshots


func _create_snapshot_for(observer_id: int) -> Dictionary:
	var observer_state: Dictionary = _players[observer_id]
	var observer_position: Vector3 = observer_state["position"]
	var interest_radius_squared: float = _interest_radius * _interest_radius
	var player_ids: Array = _players.keys()
	player_ids.sort()
	var player_states: Array = []
	for peer_id: int in player_ids:
		var player_state: Dictionary = _players[peer_id]
		var player_position: Vector3 = player_state["position"]
		if (
			peer_id == observer_id
			or observer_position.distance_squared_to(player_position) <= interest_radius_squared
		):
			player_states.append([
				peer_id,
				player_position,
				player_state["health"],
				player_state["max_health"],
				player_state["level"],
				player_state["experience"],
				player_state["resource"],
				player_state["max_resource"],
				player_state["attack_multiplier"],
				player_state["defense"],
			])
	var mob_ids: Array = _mobs.keys()
	mob_ids.sort()
	var mob_states: Array = []
	for mob_id: String in mob_ids:
		var mob_state: Dictionary = _mobs[mob_id]
		var mob_definition: Dictionary = _mob_definitions[mob_id]
		mob_states.append([
			mob_id,
			mob_state["position"],
			mob_state["health"],
			float(mob_definition["health"]),
		])
	var drops: Dictionary = _loot_system.get_drops()
	var drop_ids: Array = drops.keys()
	drop_ids.sort()
	var drop_states: Array = []
	for drop_id: int in drop_ids:
		var drop: Dictionary = drops[drop_id]
		if (
			observer_position.distance_squared_to(drop["position"])
			> interest_radius_squared
		):
			continue
		drop_states.append([
			drop_id,
			drop["item_id"],
			drop["position"],
		])
	var inventory: RefCounted = observer_state["inventory"]
	var equipment: RefCounted = observer_state["equipment"]
	return {
		"zone_id": zone_id,
		"server_time_ms": Time.get_ticks_msec(),
		"players": player_states,
		"mobs": mob_states,
		"drops": drop_states,
		"inventory": inventory.call("get_snapshot"),
		"equipment": equipment.call("get_snapshot"),
	}


func _create_player_state(position: Vector3) -> Dictionary:
	var initial_definition: Dictionary = _progression_definitions["level_1"]
	return {
		"position": position,
		"spawn_position": position,
		"input": Vector2.ZERO,
		"health": float(initial_definition["max_health"]),
		"max_health": float(initial_definition["max_health"]),
		"resource": float(initial_definition["max_resource"]),
		"max_resource": float(initial_definition["max_resource"]),
		"level": 1,
		"experience": 0,
		"attack_multiplier": float(initial_definition["attack_multiplier"]),
		"defense": float(initial_definition["defense"]),
		"base_max_health": float(initial_definition["max_health"]),
		"base_max_resource": float(initial_definition["max_resource"]),
		"base_defense": float(initial_definition["defense"]),
		"equipment_attack": 0.0,
		"respawn_remaining_seconds": 0.0,
		"inventory": InventoryComponentType.new(_inventory_slot_count),
		"equipment": EquipmentComponentType.new(),
	}


func _apply_level_definition(
	player_state: Dictionary,
	level_definition: Dictionary,
) -> void:
	var health_ratio: float = float(player_state["health"]) / float(player_state["max_health"])
	var resource_ratio: float = float(player_state["resource"]) / float(player_state["max_resource"])
	player_state["level"] = int(level_definition["level"])
	player_state["base_max_health"] = float(level_definition["max_health"])
	player_state["base_max_resource"] = float(level_definition["max_resource"])
	player_state["base_defense"] = float(level_definition["defense"])
	player_state["attack_multiplier"] = float(level_definition["attack_multiplier"])
	EquipmentSystemType.refresh_stats(
		player_state,
		_item_definitions,
		health_ratio,
		resource_ratio,
	)
