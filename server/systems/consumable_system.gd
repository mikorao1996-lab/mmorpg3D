class_name ConsumableSystem
extends RefCounted

## Server-authoritative consumable use.
##
## A consumable defines its effect in the item registry: `stats.health` heals
## the player and `stats.resource` restores their resource. The item is only
## consumed when the effect actually applies, so a full-health player cannot
## waste a potion.

const InventoryComponentType: GDScript = preload("res://server/systems/inventory_component.gd")


## Uses one unit of a consumable item from the player's inventory.
##
## Returns `accepted`, `reason`, `item_id`, `health`, `max_health`,
## `resource`, and `max_resource`.
static func use_item(
	player_state: Dictionary,
	item_id: String,
	item_definitions: Dictionary,
) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"item_id": item_id,
		"health": float(player_state["health"]),
		"max_health": float(player_state["max_health"]),
		"resource": float(player_state["resource"]),
		"max_resource": float(player_state["max_resource"]),
	}
	if float(player_state["health"]) <= 0.0:
		result["reason"] = "player_dead"
		return result
	if not item_definitions.has(item_id):
		result["reason"] = "unknown_item"
		return result

	var item_definition: Dictionary = item_definitions[item_id]
	if str(item_definition.get("item_type", "")) != "consumable":
		result["reason"] = "not_consumable"
		return result

	var inventory: InventoryComponent = player_state["inventory"]
	if not inventory.has_item(item_id):
		result["reason"] = "item_not_in_inventory"
		return result

	var item_stats: Dictionary = item_definition.get("stats", {})
	var heal_amount: float = float(item_stats.get("health", 0.0))
	var resource_amount: float = float(item_stats.get("resource", 0.0))
	if heal_amount <= 0.0 and resource_amount <= 0.0:
		result["reason"] = "no_effect"
		return result

	var applies_health: bool = heal_amount > 0.0
	var applies_resource: bool = resource_amount > 0.0
	var health_is_full: bool = (
		float(player_state["health"]) >= float(player_state["max_health"])
	)
	var resource_is_full: bool = (
		float(player_state["resource"]) >= float(player_state["max_resource"])
	)
	if applies_health and applies_resource:
		if health_is_full and resource_is_full:
			result["reason"] = "no_effect_needed"
			return result
	elif applies_health:
		if health_is_full:
			result["reason"] = "health_full"
			return result
	elif applies_resource:
		if resource_is_full:
			result["reason"] = "resource_full"
			return result

	var removal_result: Dictionary = inventory.remove_item(item_id)
	if not bool(removal_result.get("ok", false)):
		result["reason"] = "inventory_error"
		return result

	if heal_amount > 0.0:
		player_state["health"] = minf(
			float(player_state["max_health"]),
			float(player_state["health"]) + heal_amount,
		)
	if resource_amount > 0.0:
		player_state["resource"] = minf(
			float(player_state["max_resource"]),
			float(player_state["resource"]) + resource_amount,
		)

	result["accepted"] = true
	result["health"] = float(player_state["health"])
	result["max_health"] = float(player_state["max_health"])
	result["resource"] = float(player_state["resource"])
	result["max_resource"] = float(player_state["max_resource"])
	return result
