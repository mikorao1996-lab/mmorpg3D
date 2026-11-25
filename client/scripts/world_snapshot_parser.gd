class_name WorldSnapshotParser
extends RefCounted

## Validates and parses the world snapshot of the server.
##
## The parser never trusts the payload: every entry is checked against the
## game data registries before the client renders it. It returns the parsed
## state together with the reason a snapshot was rejected.

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")


## Parses a world snapshot.
##
## Returns a dictionary with `ok`, `error`, and the parsed `positions`,
## `player_health_states`, `mob_states`, `npc_states`, `drop_states`,
## `inventory_state`, `equipment_state`, and `quest_states`.
static func parse(
	snapshot: Dictionary,
	game_data_registry: Dictionary,
	inventory_slot_count: int,
) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"error": "",
		"positions": {},
		"player_health_states": {},
		"mob_states": {},
		"npc_states": {},
		"drop_states": {},
		"inventory_state": [],
		"equipment_state": {},
		"quest_states": [],
		"gold": 0,
	}

	var gold_result: Dictionary = _parse_gold(snapshot)
	if not bool(gold_result["ok"]):
		return _fail(result, str(gold_result["error"]))
	result["gold"] = gold_result["gold"]

	var equipment_result: Dictionary = _parse_equipment(snapshot, game_data_registry)
	if not bool(equipment_result["ok"]):
		return _fail(result, str(equipment_result["error"]))
	result["equipment_state"] = equipment_result["equipment_state"]

	var player_result: Dictionary = _parse_players(snapshot, game_data_registry)
	if not bool(player_result["ok"]):
		return _fail(result, str(player_result["error"]))
	result["positions"] = player_result["positions"]
	result["player_health_states"] = player_result["player_health_states"]

	var mob_result: Dictionary = _parse_mobs(snapshot, game_data_registry)
	if not bool(mob_result["ok"]):
		return _fail(result, str(mob_result["error"]))
	result["mob_states"] = mob_result["mob_states"]

	var drop_result: Dictionary = _parse_drops(snapshot, game_data_registry)
	if not bool(drop_result["ok"]):
		return _fail(result, str(drop_result["error"]))
	result["drop_states"] = drop_result["drop_states"]

	var npc_result: Dictionary = _parse_npcs(snapshot, game_data_registry)
	if not bool(npc_result["ok"]):
		return _fail(result, str(npc_result["error"]))
	result["npc_states"] = npc_result["npc_states"]

	var quest_result: Dictionary = _parse_quests(snapshot, game_data_registry)
	if not bool(quest_result["ok"]):
		return _fail(result, str(quest_result["error"]))
	result["quest_states"] = quest_result["quest_states"]

	var inventory_result: Dictionary = _parse_inventory(
		snapshot,
		game_data_registry,
		inventory_slot_count,
	)
	if not bool(inventory_result["ok"]):
		return _fail(result, str(inventory_result["error"]))
	result["inventory_state"] = inventory_result["inventory_state"]

	result["ok"] = true
	return result


## Parses the gold balance of the observing player.
static func _parse_gold(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "gold": 0}
	var gold_value: Variant = snapshot.get("gold", null)
	if gold_value is not int or int(gold_value) < 0:
		result["error"] = "malformed gold balance in world snapshot"
		return result
	result["gold"] = int(gold_value)
	result["ok"] = true
	return result


static func _parse_equipment(
	snapshot: Dictionary,
	game_data_registry: Dictionary,
) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "equipment_state": {}}
	var equipment_entries: Variant = snapshot.get("equipment", null)
	if (
		not equipment_entries is Dictionary
		or equipment_entries.size() != GameDataRegistryType.EQUIPMENT_SLOTS.size()
	):
		result["error"] = "malformed equipment in world snapshot"
		return result
	var equipment_state: Dictionary = {}
	for slot_id: String in GameDataRegistryType.EQUIPMENT_SLOTS:
		var item_id: Variant = equipment_entries.get(slot_id, null)
		if item_id is not String:
			result["error"] = "malformed equipment slot"
			return result
		if not item_id.is_empty():
			var item_definition: Dictionary = game_data_registry["items"].get(item_id, {})
			if (
				item_definition.is_empty()
				or str(item_definition.get("equipment_slot", "")) != slot_id
			):
				result["error"] = "invalid equipped item %s" % item_id
				return result
		equipment_state[slot_id] = item_id
	result["equipment_state"] = equipment_state
	result["ok"] = true
	return result


static func _parse_players(
	snapshot: Dictionary,
	game_data_registry: Dictionary,
) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"error": "",
		"positions": {},
		"player_health_states": {},
	}
	var player_entries: Variant = snapshot.get("players", null)
	if not player_entries is Array:
		result["error"] = "world snapshot without player list"
		return result
	var positions: Dictionary = {}
	var player_health_states: Dictionary = {}
	var maximum_level: int = game_data_registry["progression"].size()
	for entry: Variant in player_entries:
		if not entry is Array or entry.size() != 10:
			result["error"] = "malformed player entry in world snapshot"
			return result
		var player_id: Variant = entry[0]
		var position: Variant = entry[1]
		var health: Variant = entry[2]
		var max_health: Variant = entry[3]
		var level: Variant = entry[4]
		var experience: Variant = entry[5]
		var resource: Variant = entry[6]
		var max_resource: Variant = entry[7]
		var attack_multiplier: Variant = entry[8]
		var defense: Variant = entry[9]
		if (
			player_id is not int
			or position is not Vector3
			or not _is_finite_number(health)
			or not _is_finite_number(max_health)
			or level is not int
			or experience is not int
			or experience < 0
			or not _is_finite_number(resource)
			or not _is_finite_number(max_resource)
			or not _is_finite_number(attack_multiplier)
			or not _is_finite_number(defense)
			or float(max_health) <= 0.0
			or level < 1
			or level > maximum_level
			or float(max_resource) <= 0.0
			or float(attack_multiplier) <= 0.0
			or float(defense) < 0.0
			or float(health) < 0.0
			or float(health) > float(max_health)
			or float(resource) < 0.0
			or float(resource) > float(max_resource)
		):
			result["error"] = "malformed player state in world snapshot"
			return result
		positions[player_id] = position
		player_health_states[player_id] = {
			"health": float(health),
			"max_health": float(max_health),
			"level": level,
			"experience": int(experience),
			"resource": float(resource),
			"max_resource": float(max_resource),
			"attack_multiplier": float(attack_multiplier),
			"defense": float(defense),
		}
	result["positions"] = positions
	result["player_health_states"] = player_health_states
	result["ok"] = true
	return result


static func _parse_mobs(
	snapshot: Dictionary,
	game_data_registry: Dictionary,
) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "mob_states": {}}
	var mob_entries: Variant = snapshot.get("mobs", null)
	if not mob_entries is Array:
		result["error"] = "world snapshot without mob list"
		return result
	var mob_states: Dictionary = {}
	for entry: Variant in mob_entries:
		if not entry is Array or entry.size() != 4:
			result["error"] = "malformed mob entry in world snapshot"
			return result
		var mob_id: Variant = entry[0]
		var position: Variant = entry[1]
		var health: Variant = entry[2]
		var max_health: Variant = entry[3]
		if (
			mob_id is not String
			or position is not Vector3
			or not _is_finite_number(health)
			or not _is_finite_number(max_health)
			or float(max_health) <= 0.0
			or float(health) < 0.0
			or float(health) > float(max_health)
		):
			result["error"] = "malformed mob state in world snapshot"
			return result
		if not GameDataRegistryType.build_mob_instance_types(
			game_data_registry["mobs"]
		).has(mob_id):
			result["error"] = "snapshot for unknown mob %s" % mob_id
			return result
		mob_states[mob_id] = {
			"position": position,
			"health": float(health),
			"max_health": float(max_health),
		}
	result["mob_states"] = mob_states
	result["ok"] = true
	return result


static func _parse_drops(
	snapshot: Dictionary,
	game_data_registry: Dictionary,
) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "drop_states": {}}
	var drop_entries: Variant = snapshot.get("drops", null)
	if not drop_entries is Array:
		result["error"] = "world snapshot without loot drops"
		return result
	var drop_states: Dictionary = {}
	for entry: Variant in drop_entries:
		if not entry is Array or entry.size() != 3:
			result["error"] = "malformed loot drop in world snapshot"
			return result
		var drop_id: Variant = entry[0]
		var item_id: Variant = entry[1]
		var drop_position: Variant = entry[2]
		if (
			drop_id is not int
			or drop_id < 1
			or item_id is not String
			or drop_position is not Vector3
			or not game_data_registry["items"].has(item_id)
			or drop_states.has(drop_id)
		):
			result["error"] = "malformed loot drop state"
			return result
		drop_states[drop_id] = {
			"item_id": item_id,
			"position": drop_position,
		}
	result["drop_states"] = drop_states
	result["ok"] = true
	return result


static func _parse_npcs(
	snapshot: Dictionary,
	game_data_registry: Dictionary,
) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "npc_states": {}}
	var npc_entries: Variant = snapshot.get("npcs", null)
	if not npc_entries is Array:
		result["error"] = "world snapshot without npc list"
		return result
	var npc_states: Dictionary = {}
	for entry: Variant in npc_entries:
		if not entry is Array or entry.size() != 2:
			result["error"] = "malformed npc entry in world snapshot"
			return result
		var npc_id: Variant = entry[0]
		var npc_position: Variant = entry[1]
		if (
			npc_id is not String
			or npc_position is not Vector3
			or not game_data_registry["npcs"].has(npc_id)
			or npc_states.has(npc_id)
		):
			result["error"] = "malformed npc state"
			return result
		npc_states[npc_id] = {"position": npc_position}
	result["npc_states"] = npc_states
	result["ok"] = true
	return result


static func _parse_quests(
	snapshot: Dictionary,
	game_data_registry: Dictionary,
) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "quest_states": []}
	var quest_entries: Variant = snapshot.get("quests", null)
	if not quest_entries is Array:
		result["error"] = "world snapshot without quest list"
		return result
	var quest_states: Array = []
	for entry: Variant in quest_entries:
		if not entry is Array or entry.size() != 7:
			result["error"] = "malformed quest entry in world snapshot"
			return result
		var quest_id: Variant = entry[0]
		var quest_status: Variant = entry[1]
		var quest_progress: Variant = entry[2]
		var quest_count: Variant = entry[3]
		var quest_name_key: Variant = entry[4]
		var quest_objective_type: Variant = entry[5]
		var quest_objective_target: Variant = entry[6]
		if (
			quest_id is not String
			or quest_status is not String
			or not quest_progress is int
			or not quest_count is int
			or quest_name_key is not String
			or quest_objective_type is not String
			or quest_objective_target is not String
			or not game_data_registry["quests"].has(quest_id)
		):
			result["error"] = "malformed quest state"
			return result
		quest_states.append(entry)
	result["quest_states"] = quest_states
	result["ok"] = true
	return result


static func _parse_inventory(
	snapshot: Dictionary,
	game_data_registry: Dictionary,
	inventory_slot_count: int,
) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "inventory_state": []}
	var inventory_entries: Variant = snapshot.get("inventory", null)
	if (
		not inventory_entries is Array
		or inventory_entries.size() > inventory_slot_count
	):
		result["error"] = "malformed inventory in world snapshot"
		return result
	var inventory_state: Array[Dictionary] = []
	for entry: Variant in inventory_entries:
		if not entry is Array or entry.size() != 2:
			result["error"] = "malformed inventory slot"
			return result
		var item_id: Variant = entry[0]
		var quantity: Variant = entry[1]
		if (
			item_id is not String
			or quantity is not int
			or quantity < 1
			or not game_data_registry["items"].has(item_id)
			or quantity > int(game_data_registry["items"][item_id]["stack_limit"])
		):
			result["error"] = "malformed inventory item"
			return result
		inventory_state.append({
			"item_id": item_id,
			"quantity": quantity,
		})
	result["inventory_state"] = inventory_state
	result["ok"] = true
	return result


static func _fail(result: Dictionary, error: String) -> Dictionary:
	result["ok"] = false
	result["error"] = error
	return result


static func _is_finite_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	return (
		(value_type == TYPE_INT or value_type == TYPE_FLOAT)
		and is_finite(float(value))
	)
