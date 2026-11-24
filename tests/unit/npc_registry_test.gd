extends RefCounted

## Checks the NPC registry and the quest content of the vertical slice.

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

const EXPECTED_QUEST_COUNT: int = 5
const EXPECTED_NPC_COUNT: int = 2


func run() -> bool:
	var registries: Dictionary = GameDataRegistryType.load_all()
	if registries.is_empty():
		return false
	if not registries.has("npcs"):
		push_error("Game data registry does not provide NPC definitions")
		return false
	var npcs: Dictionary = registries["npcs"]
	var quests: Dictionary = registries["quests"]
	if npcs.size() != EXPECTED_NPC_COUNT:
		push_error("Expected %d NPCs, found %d" % [EXPECTED_NPC_COUNT, npcs.size()])
		return false
	if quests.size() != EXPECTED_QUEST_COUNT:
		push_error("Expected %d quests, found %d" % [EXPECTED_QUEST_COUNT, quests.size()])
		return false

	var objective_types: Dictionary = {}
	for quest: Dictionary in quests.values():
		var objective_type: String = quest["objective_type"]
		objective_types[objective_type] = true
	for expected_type: String in ["kill", "collect", "talk"]:
		if not objective_types.has(expected_type):
			push_error("Quest catalog has no %s objective" % expected_type)
			return false

	for npc: Dictionary in npcs.values():
		if (npc["quest_ids"] as Array).is_empty():
			push_error("NPC %s does not offer any quest" % npc["id"])
			return false
		for quest_id: String in npc["quest_ids"]:
			if not quests.has(quest_id):
				push_error("NPC %s references unknown quest %s" % [npc["id"], quest_id])
				return false

	var invalid_position: Dictionary = npcs["quest_giver_mira"].duplicate(true)
	invalid_position["spawn_position"] = [0.0, 1.0]
	if GameDataRegistryType.validate_entry("npcs", invalid_position).is_empty():
		push_error("Game data registry accepted an NPC with a malformed spawn position")
		return false
	var invalid_range: Dictionary = npcs["quest_giver_mira"].duplicate(true)
	invalid_range["interaction_range"] = 0.0
	if GameDataRegistryType.validate_entry("npcs", invalid_range).is_empty():
		push_error("Game data registry accepted an NPC without an interaction range")
		return false
	var invalid_dialogue: Dictionary = npcs["quest_giver_mira"].duplicate(true)
	invalid_dialogue["dialogue_key"] = ""
	if GameDataRegistryType.validate_entry("npcs", invalid_dialogue).is_empty():
		push_error("Game data registry accepted an NPC without a dialogue key")
		return false
	return true
