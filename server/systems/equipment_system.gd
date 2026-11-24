class_name EquipmentSystem
extends RefCounted

## Server-authoritative equipment rules.
##
## The functions operate on a player state dictionary owned by a zone. They never
## trust client data: item ownership, slot compatibility, and level requirements
## are resolved from the server-side item registry before gear changes.

const EquipmentComponentType: GDScript = preload("res://server/systems/equipment_component.gd")
const InventoryComponentType: GDScript = preload("res://server/systems/inventory_component.gd")


## Equips an owned item into its configured slot and replaces whatever the slot
## held. Returns a result dictionary with `accepted`, `reason`, `item_id`, and
## `slot_id`.
static func equip_item(
	player_state: Dictionary,
	item_id: String,
	item_definitions: Dictionary,
) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"item_id": item_id,
		"slot_id": "",
	}
	if float(player_state["health"]) <= 0.0:
		result["reason"] = "player_dead"
		return result
	if not item_definitions.has(item_id):
		result["reason"] = "unknown_item"
		return result

	var item_definition: Dictionary = item_definitions[item_id]
	var slot_id: String = str(item_definition.get("equipment_slot", ""))
	var equipment: EquipmentComponent = player_state["equipment"]
	if slot_id.is_empty() or not equipment.has_slot(slot_id):
		result["reason"] = "not_equippable"
		return result
	if int(player_state["level"]) < int(item_definition["level_requirement"]):
		result["reason"] = "level_requirement"
		result["slot_id"] = slot_id
		return result

	var inventory: InventoryComponent = player_state["inventory"]
	var removal_result: Dictionary = inventory.remove_item(item_id)
	if not bool(removal_result.get("ok", false)):
		result["reason"] = str(removal_result.get("reason", "inventory_error"))
		result["slot_id"] = slot_id
		return result

	var previous_item_id: String = equipment.get_item_id(slot_id)
	if not previous_item_id.is_empty():
		var previous_definition: Dictionary = item_definitions.get(previous_item_id, {})
		var restore_result: Dictionary = inventory.add_item(
			previous_item_id,
			previous_definition,
		)
		if not bool(restore_result.get("ok", false)):
			_rollback_inventory_add(inventory, item_id, item_definition)
			result["reason"] = "inventory_full"
			result["slot_id"] = slot_id
			return result

	if not equipment.set_item_id(slot_id, item_id):
		if not previous_item_id.is_empty():
			var previous_rollback_result: Dictionary = inventory.remove_item(
				previous_item_id,
			)
			if not bool(previous_rollback_result.get("ok", false)):
				push_error(
					"Could not restore replaced equipment for item %s" % item_id
				)
		_rollback_inventory_add(inventory, item_id, item_definition)
		result["reason"] = "equipment_error"
		result["slot_id"] = slot_id
		return result

	refresh_stats(player_state, item_definitions)
	result["accepted"] = true
	result["slot_id"] = slot_id
	return result


## Moves the item in a slot back into the inventory. Fails when the inventory
## cannot hold the returned item.
static func unequip_item(
	player_state: Dictionary,
	slot_id: String,
	item_definitions: Dictionary,
) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"item_id": "",
		"slot_id": slot_id,
	}
	if float(player_state["health"]) <= 0.0:
		result["reason"] = "player_dead"
		return result
	var equipment: EquipmentComponent = player_state["equipment"]
	if not equipment.has_slot(slot_id):
		result["reason"] = "invalid_slot"
		return result
	var item_id: String = equipment.get_item_id(slot_id)
	if item_id.is_empty():
		result["reason"] = "slot_empty"
		return result

	var inventory: InventoryComponent = player_state["inventory"]
	var add_result: Dictionary = inventory.add_item(
		item_id,
		item_definitions.get(item_id, {}),
	)
	if not bool(add_result.get("ok", false)):
		result["reason"] = str(add_result.get("reason", "inventory_error"))
		result["item_id"] = item_id
		return result

	if not equipment.set_item_id(slot_id, ""):
		var rollback_result: Dictionary = inventory.remove_item(item_id)
		if not bool(rollback_result.get("ok", false)):
			push_error("Could not roll back failed unequip for item %s" % item_id)
		result["reason"] = "equipment_error"
		result["item_id"] = item_id
		return result

	refresh_stats(player_state, item_definitions)
	result["accepted"] = true
	result["item_id"] = item_id
	return result


## Recomputes the player stats from the level definition and the equipped gear.
## Health and resource keep their current ratio unless the caller passes one.
static func refresh_stats(
	player_state: Dictionary,
	item_definitions: Dictionary,
	health_ratio: float = -1.0,
	resource_ratio: float = -1.0,
) -> void:
	if health_ratio < 0.0:
		health_ratio = float(player_state["health"]) / float(player_state["max_health"])
	if resource_ratio < 0.0:
		resource_ratio = (
			float(player_state["resource"]) / float(player_state["max_resource"])
		)
	var bonuses: Dictionary = {
		"attack": 0.0,
		"defense": 0.0,
		"health": 0.0,
		"resource": 0.0,
	}
	var equipment: EquipmentComponent = player_state["equipment"]
	var equipped_items: Dictionary = equipment.get_equipped_item_ids()
	for item_id: String in equipped_items.values():
		if item_id.is_empty():
			continue
		var item_definition: Dictionary = item_definitions.get(item_id, {})
		var item_stats: Dictionary = item_definition.get("stats", {})
		for stat_name: String in bonuses:
			bonuses[stat_name] += float(item_stats.get(stat_name, 0.0))
	player_state["equipment_attack"] = bonuses["attack"]
	player_state["max_health"] = float(player_state["base_max_health"]) + bonuses["health"]
	player_state["max_resource"] = (
		float(player_state["base_max_resource"]) + bonuses["resource"]
	)
	player_state["defense"] = float(player_state["base_defense"]) + bonuses["defense"]
	player_state["health"] = float(player_state["max_health"]) * health_ratio
	player_state["resource"] = float(player_state["max_resource"]) * resource_ratio


static func _rollback_inventory_add(
	inventory: InventoryComponent,
	item_id: String,
	item_definition: Dictionary,
) -> void:
	var rollback_result: Dictionary = inventory.add_item(item_id, item_definition)
	if not bool(rollback_result.get("ok", false)):
		push_error("Could not roll back failed equipment change for item %s" % item_id)
