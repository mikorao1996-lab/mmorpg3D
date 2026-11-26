class_name CharacterStateSystem
extends RefCounted

## Converts between the stored character and the live player state.
##
## The stored character is a plain record: numbers, a position, and the lists of
## the inventory, the equipment, and the quests. The live player state is the
## dictionary the zone owns, with the inventory and the equipment as
## components. The conversion lives here so the zone keeps the ownership of the
## simulation and the persistence keeps its own rules.

const InventoryComponentType: GDScript = preload("res://server/systems/inventory_component.gd")
const EquipmentComponentType: GDScript = preload("res://server/systems/equipment_component.gd")
const QuestSystemType: GDScript = preload("res://server/systems/quest_system.gd")

const MAX_STACK_QUANTITY: int = 999


## Builds the player state of a stored character.
##
## `context` carries the registries the state depends on: `progression`,
## `items`, `quests`, and `inventory_slot_count`. The result is empty when the
## stored character cannot be restored, so the caller can fall back to a new
## character instead of starting a broken session.
static func build_restored_state(restored: Dictionary, context: Dictionary) -> Dictionary:
	var progression: Dictionary = context.get("progression", {})
	var item_definitions: Dictionary = context.get("items", {})
	var quest_definitions: Dictionary = context.get("quests", {})
	var inventory_slot_count: int = int(context.get("inventory_slot_count", 20))
	if progression.is_empty():
		return {}

	var level: int = clampi(int(restored.get("level", 1)), 1, progression.size())
	var level_key: String = "level_%d" % level
	if not progression.has(level_key):
		return {}
	var level_definition: Dictionary = progression[level_key]

	var position: Vector3 = restored.get("position", Vector3.ZERO)
	if typeof(position) != TYPE_VECTOR3:
		position = Vector3.ZERO

	var state: Dictionary = {
		"position": position,
		"spawn_position": position,
		"input": Vector2.ZERO,
		"level": level,
		"experience": maxi(int(restored.get("experience", 0)), 0),
		"gold": maxi(int(restored.get("gold", 0)), 0),
		"base_max_health": float(level_definition["max_health"]),
		"base_max_resource": float(level_definition["max_resource"]),
		"base_defense": float(level_definition["defense"]),
		"attack_multiplier": float(level_definition["attack_multiplier"]),
		"respawn_remaining_seconds": 0.0,
		"inventory": _build_inventory(
			restored.get("inventory", []),
			item_definitions,
			inventory_slot_count,
		),
		"equipment": _build_equipment(
			restored.get("equipment", {}),
			item_definitions,
		),
		"quests": _build_quest_states(
			restored.get("quests", {}),
			quest_definitions,
		),
	}

	# The gear decides the maximum values, so the limits are known only after
	# the equipment is in place.
	state["equipment_attack"] = 0.0
	state["max_health"] = float(state["base_max_health"])
	state["max_resource"] = float(state["base_max_resource"])
	state["defense"] = float(state["base_defense"])
	_equipment_bonuses(state, item_definitions)

	var saved_health: float = float(restored.get("health", 0.0))
	var saved_resource: float = float(restored.get("resource", 0.0))
	if saved_health <= 0.0:
		# A character that died in the last session starts over at its entry
		# point, exactly like a respawn in the zone.
		state["health"] = float(state["max_health"])
		state["resource"] = float(state["max_resource"])
	else:
		state["health"] = minf(saved_health, float(state["max_health"]))
		state["resource"] = minf(saved_resource, float(state["max_resource"]))
	return state


## Exports the live player state into the stored shape.
static func export_state(player_state: Dictionary, zone_id: String) -> Dictionary:
	var inventory: Array = []
	var inventory_component: RefCounted = player_state.get("inventory")
	if inventory_component != null:
		for slot: Variant in inventory_component.call("get_snapshot"):
			if typeof(slot) != TYPE_ARRAY or slot.size() < 2:
				continue
			inventory.append({
				"item_id": str(slot[0]),
				"quantity": int(slot[1]),
			})
	var equipment: Dictionary = {}
	var equipment_component: RefCounted = player_state.get("equipment")
	if equipment_component != null:
		var equipment_snapshot: Variant = equipment_component.call("get_snapshot")
		if typeof(equipment_snapshot) == TYPE_DICTIONARY:
			for slot_id: Variant in equipment_snapshot:
				equipment[str(slot_id)] = str(equipment_snapshot[slot_id])
	return {
		"zone_id": zone_id,
		"position": player_state.get("position", Vector3.ZERO),
		"level": int(player_state.get("level", 1)),
		"experience": int(player_state.get("experience", 0)),
		"gold": int(player_state.get("gold", 0)),
		"health": float(player_state.get("health", 0.0)),
		"resource": float(player_state.get("resource", 0.0)),
		"inventory": inventory,
		"equipment": equipment,
		"quests": _export_quest_states(player_state.get("quests", {})),
	}


## Rebuilds the inventory component from the stored slots.
##
## Only registered items are restored, and a stack that does not fit is
## dropped instead of overwriting the capacity of the inventory.
static func _build_inventory(
	inventory: Variant,
	item_definitions: Dictionary,
	inventory_slot_count: int,
) -> InventoryComponent:
	var component: InventoryComponent = InventoryComponentType.new(inventory_slot_count)
	if typeof(inventory) != TYPE_ARRAY:
		return component
	for entry: Variant in inventory:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = entry
		var item_id: String = str(slot.get("item_id", ""))
		if item_id.strip_edges().is_empty() or not item_definitions.has(item_id):
			continue
		var quantity: int = clampi(int(slot.get("quantity", 0)), 0, MAX_STACK_QUANTITY)
		var definition: Dictionary = item_definitions[item_id]
		for _index: int in range(quantity):
			component.add_item(item_id, definition)
	return component


## Rebuilds the equipment component from the stored slots.
##
## An item is only restored into the slot its definition asks for, so a
## corrupted row cannot put a sword into the chest slot.
static func _build_equipment(
	equipment: Variant,
	item_definitions: Dictionary,
) -> EquipmentComponent:
	var component: EquipmentComponent = EquipmentComponentType.new()
	if typeof(equipment) != TYPE_DICTIONARY:
		return component
	for slot_id: Variant in equipment:
		var item_id: String = str(equipment[slot_id])
		if item_id.strip_edges().is_empty() or not item_definitions.has(item_id):
			continue
		var definition: Dictionary = item_definitions[item_id]
		if str(definition.get("equipment_slot", "")) != str(slot_id):
			continue
		component.set_item_id(str(slot_id), item_id)
	return component


## Rebuilds the quest states from the stored record.
##
## A quest that is not in the registry is dropped, and only the known statuses
## survive, so a stored character never breaks the quest tracker.
static func _build_quest_states(
	quests: Variant,
	quest_definitions: Dictionary,
) -> Dictionary:
	var states: Dictionary = {}
	if typeof(quests) != TYPE_DICTIONARY:
		return states
	var known_statuses: Array[String] = [
		QuestSystemType.STATUS_ACTIVE,
		QuestSystemType.STATUS_COMPLETED,
		QuestSystemType.STATUS_TURNED_IN,
	]
	for quest_id: Variant in quests:
		var quest_key: String = str(quest_id)
		if not quest_definitions.has(quest_key):
			continue
		if typeof(quests[quest_id]) != TYPE_DICTIONARY:
			continue
		var quest_state: Dictionary = quests[quest_id]
		var status: String = str(quest_state.get("status", ""))
		if not known_statuses.has(status):
			continue
		states[quest_key] = {
			"status": status,
			"progress": maxi(int(quest_state.get("progress", 0)), 0),
		}
	return states


## Exports the quest states in the stored shape.
static func _export_quest_states(quests: Variant) -> Dictionary:
	var exported: Dictionary = {}
	if typeof(quests) != TYPE_DICTIONARY:
		return exported
	for quest_id: Variant in quests:
		if typeof(quests[quest_id]) != TYPE_DICTIONARY:
			continue
		var quest_state: Dictionary = quests[quest_id]
		exported[str(quest_id)] = {
			"status": str(quest_state.get("status", "")),
			"progress": maxi(int(quest_state.get("progress", 0)), 0),
		}
	return exported


## Adds the bonuses of the equipped gear to the maximum values.
static func _equipment_bonuses(state: Dictionary, item_definitions: Dictionary) -> void:
	var equipment: EquipmentComponent = state["equipment"]
	var bonuses: Dictionary = {
		"attack": 0.0,
		"defense": 0.0,
		"health": 0.0,
		"resource": 0.0,
	}
	for item_id: String in equipment.get_equipped_item_ids().values():
		if item_id.is_empty() or not item_definitions.has(item_id):
			continue
		var item_stats: Dictionary = item_definitions[item_id].get("stats", {})
		for stat_name: String in bonuses:
			bonuses[stat_name] += float(item_stats.get(stat_name, 0.0))
	state["equipment_attack"] = bonuses["attack"]
	state["max_health"] = float(state["base_max_health"]) + bonuses["health"]
	state["max_resource"] = float(state["base_max_resource"]) + bonuses["resource"]
	state["defense"] = float(state["base_defense"]) + bonuses["defense"]
