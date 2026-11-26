extends RefCounted

## Unit checks of the conversion between a stored character and a live player.
##
## The conversion decides what a client may bring back into a session, so it
## has to drop everything that the registries do not know.

const CharacterStateSystemType: GDScript = preload("res://server/systems/character_state_system.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")


func run() -> bool:
	var game_data_registry: Dictionary = GameDataRegistryType.load_all()
	if game_data_registry.is_empty():
		return false
	var context: Dictionary = {
		"progression": game_data_registry["progression"],
		"items": game_data_registry["items"],
		"quests": game_data_registry["quests"],
		"inventory_slot_count": 20,
	}

	var stored: Dictionary = {
		"zone_id": "starter",
		"position": Vector3(2.0, 0.0, -3.0),
		"level": 2,
		"experience": 120,
		"gold": 175,
		"health": 90.0,
		"resource": 40.0,
		"inventory": [{"item_id": "minor_potion", "quantity": 2}],
		"equipment": {"weapon": "iron_sword"},
		"quests": {"slime_problem": {"status": "active", "progress": 2}},
	}
	var state: Dictionary = CharacterStateSystemType.build_restored_state(stored, context)
	if not _check(not state.is_empty(), "a stored character must be restored"):
		return false
	if int(state.get("level", 0)) != 2:
		push_error("the stored level must be restored")
		return false
	if int(state.get("experience", 0)) != 120:
		push_error("the stored experience must be restored")
		return false
	if int(state.get("gold", 0)) != 175:
		push_error("the stored gold must be restored")
		return false
	if float(state.get("health", 0.0)) != 90.0:
		push_error("the stored health must be restored")
		return false
	if (state.get("position", Vector3.ZERO) as Vector3) != Vector3(2.0, 0.0, -3.0):
		push_error("the stored position must be restored")
		return false

	var inventory: RefCounted = state.get("inventory")
	var slots: Array = inventory.call("get_snapshot")
	if not _check(slots.size() == 1, "the stored inventory must be restored"):
		return false
	if str(slots[0][0]) != "minor_potion" or int(slots[0][1]) != 2:
		push_error("the restored inventory must keep its item and quantity")
		return false

	var equipment: RefCounted = state.get("equipment")
	if str(equipment.call("get_item_id", "weapon")) != "iron_sword":
		push_error("the stored equipment must be restored")
		return false

	var quests: Dictionary = state.get("quests", {})
	if str((quests.get("slime_problem", {}) as Dictionary).get("status", "")) != "active":
		push_error("the stored quests must be restored")
		return false

	# A stored character cannot bring items or quests the registries do not
	# know, and it cannot put a weapon into another slot.
	var tampered: Dictionary = stored.duplicate(true)
	tampered["inventory"] = [
		{"item_id": "minor_potion", "quantity": 1},
		{"item_id": "not_an_item", "quantity": 1},
	]
	tampered["equipment"] = {"chest": "iron_sword"}
	tampered["quests"] = {
		"slime_problem": {"status": "active", "progress": 2},
		"not_a_quest": {"status": "active", "progress": 1},
	}
	var guarded: Dictionary = CharacterStateSystemType.build_restored_state(tampered, context)
	var guarded_inventory: RefCounted = guarded.get("inventory")
	if not _check(
			(guarded_inventory.call("get_snapshot") as Array).size() == 1,
			"an unknown item must not enter the inventory",
	):
		return false
	var guarded_equipment: RefCounted = guarded.get("equipment")
	if not _check(
			str(guarded_equipment.call("get_item_id", "chest")).is_empty(),
			"an item must not enter a slot it does not belong to",
	):
		return false
	if not _check(
			(guarded.get("quests", {}) as Dictionary).size() == 1,
			"an unknown quest must not enter the tracker",
	):
		return false

	# A character that died in the last session starts over at full health.
	var dead: Dictionary = stored.duplicate(true)
	dead["health"] = 0.0
	var restored_dead: Dictionary = CharacterStateSystemType.build_restored_state(dead, context)
	if not _check(
			float(restored_dead.get("health", 0.0)) > 0.0,
			"a character that died must come back alive",
	):
		return false

	var exported: Dictionary = CharacterStateSystemType.export_state(state, "starter")
	if int(exported.get("level", 0)) != 2:
		push_error("the exported level must match the live state")
		return false
	if int(exported.get("gold", 0)) != 175:
		push_error("the exported gold must match the live state")
		return false
	if not _check(
			(exported.get("inventory", []) as Array).size() == 1,
			"the exported inventory must match the live state",
	):
		return false
	if str((exported.get("equipment", {}) as Dictionary).get("weapon", "")) != "iron_sword":
		push_error("the exported equipment must match the live state")
		return false

	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition
