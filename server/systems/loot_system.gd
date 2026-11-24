class_name LootSystem
extends RefCounted

## Server-authoritative ground loot.
##
## A defeated mob drops the items configured in its mob definition. Drops stay
## in the zone until a player picks them up, and a pickup is only granted when
## the player is close enough and the inventory can hold the item.

var _drops: Dictionary = {}
var _next_drop_id: int = 1


## Creates the configured drops for a defeated mob.
##
## `mob_state` and `mob_definition` are the zone-owned dictionaries; the loot
## flag is written back into `mob_state` so a defeat cannot drop twice.
func spawn_for_mob(mob_state: Dictionary, mob_definition: Dictionary) -> Dictionary:
	if float(mob_state["health"]) > 0.0:
		return {"ok": false, "error": "Loot can only be spawned for a defeated mob."}
	if bool(mob_state["loot_spawned"]):
		return {"ok": false, "error": "Loot has already spawned for this defeat."}

	var drop_ids: Array[int] = []
	for item_id: String in mob_definition["loot_item_ids"]:
		var drop_id: int = _next_drop_id
		_next_drop_id += 1
		_drops[drop_id] = {
			"item_id": item_id,
			"position": mob_state["position"],
		}
		drop_ids.append(drop_id)
	mob_state["loot_spawned"] = true
	return {"ok": true, "drop_ids": drop_ids}


## Attempts to pick a drop up for a player.
##
## Returns `accepted`, `reason`, and `item_id`. A rejected pickup always leaves
## the drop in the world.
func pickup(
	player_state: Dictionary,
	drop_id: int,
	pickup_range: float,
	item_definitions: Dictionary,
) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"item_id": "",
	}
	if not _drops.has(drop_id):
		result["reason"] = "drop_not_found"
		return result

	var drop: Dictionary = _drops[drop_id]
	var player_position: Vector3 = player_state["position"]
	var drop_position: Vector3 = drop["position"]
	if (
		player_position.distance_squared_to(drop_position)
		> pickup_range * pickup_range
	):
		result["reason"] = "out_of_range"
		result["item_id"] = drop["item_id"]
		return result

	var item_id: String = drop["item_id"]
	if not item_definitions.has(item_id):
		push_error("Loot drop references unknown item %s" % item_id)
		result["reason"] = "unknown_item"
		return result

	var inventory: InventoryComponent = player_state["inventory"]
	var inventory_result: Dictionary = inventory.add_item(
		item_id,
		item_definitions[item_id],
	)
	if not bool(inventory_result.get("ok", false)):
		result["reason"] = str(inventory_result.get("reason", "inventory_error"))
		result["item_id"] = item_id
		return result

	_drops.erase(drop_id)
	result["accepted"] = true
	result["item_id"] = item_id
	return result


## Returns the live drop table. The dictionary is shared with the owning zone,
## so mutations stay visible to the snapshot builder.
func get_drops() -> Dictionary:
	return _drops
