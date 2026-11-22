extends RefCounted

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")


func run() -> bool:
	var registries: Dictionary = GameDataRegistryType.load_all()
	if registries.is_empty():
		return false
	for registry_name: String in ["items", "abilities", "mobs", "quests"]:
		if not registries.has(registry_name) or registries[registry_name].is_empty():
			push_error("Missing or empty game data registry: %s" % registry_name)
			return false

	var slime: Dictionary = registries["mobs"].get("training_slime", {})
	if not registries["items"].has("minor_potion") \
			or not slime.get("loot_item_ids", []).has("minor_potion"):
		push_error("Game data registry failed to resolve the mob loot reference")
		return false

	var quest: Dictionary = registries["quests"].get("slime_problem", {})
	if not registries["mobs"].has(quest.get("objective_target", "")):
		push_error("Game data registry failed to resolve the quest objective reference")
		return false

	var invalid_item: Dictionary = registries["items"]["starter_sword"].duplicate(true)
	invalid_item["item_type"] = "artifact"
	if GameDataRegistryType.validate_entry("items", invalid_item).is_empty():
		push_error("Game data registry accepted an unsupported item type")
		return false
	invalid_item["item_type"] = "weapon"
	invalid_item["stack_limit"] = 1.5
	if GameDataRegistryType.validate_entry("items", invalid_item).is_empty():
		push_error("Game data registry accepted a fractional integer field")
		return false

	var invalid_references: Dictionary = registries.duplicate(true)
	invalid_references["quests"]["slime_problem"]["objective_target"] = "missing_mob"
	if GameDataRegistryType.validate_references(invalid_references).is_empty():
		push_error("Game data registry accepted an unknown quest target")
		return false
	return true
