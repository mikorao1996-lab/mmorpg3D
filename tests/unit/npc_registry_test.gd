extends RefCounted

## Checks the NPC registry and the quest content of the vertical slice.

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

const EXPECTED_QUEST_COUNT: int = 5
const EXPECTED_NPC_COUNT: int = 3
const EXPECTED_VENDOR_COUNT: int = 1


func run() -> bool:
	var registries: Dictionary = GameDataRegistryType.load_all()
	if registries.is_empty():
		return false
	if not registries.has("npcs"):
		push_error("Game data registry does not provide NPC definitions")
		return false
	if not registries.has("vendors"):
		push_error("Game data registry does not provide vendor definitions")
		return false
	var npcs: Dictionary = registries["npcs"]
	var quests: Dictionary = registries["quests"]
	var vendors: Dictionary = registries["vendors"]
	if npcs.size() != EXPECTED_NPC_COUNT:
		push_error("Expected %d NPCs, found %d" % [EXPECTED_NPC_COUNT, npcs.size()])
		return false
	if quests.size() != EXPECTED_QUEST_COUNT:
		push_error("Expected %d quests, found %d" % [EXPECTED_QUEST_COUNT, quests.size()])
		return false
	if vendors.size() != EXPECTED_VENDOR_COUNT:
		push_error(
			"Expected %d vendors, found %d" % [EXPECTED_VENDOR_COUNT, vendors.size()]
		)
		return false

	var objective_types: Dictionary = {}
	for quest: Dictionary in quests.values():
		var objective_type: String = quest["objective_type"]
		objective_types[objective_type] = true
	for expected_type: String in ["kill", "collect", "talk"]:
		if not objective_types.has(expected_type):
			push_error("Quest catalog has no %s objective" % expected_type)
			return false

	var vendor_npc_ids: Dictionary = {}
	for vendor: Dictionary in vendors.values():
		var vendor_npc_id: String = vendor["npc_id"]
		if not npcs.has(vendor_npc_id):
			push_error("Vendor %s references unknown NPC %s" % [vendor["id"], vendor_npc_id])
			return false
		if vendor_npc_ids.has(vendor_npc_id):
			push_error("NPC %s is served by more than one vendor" % vendor_npc_id)
			return false
		vendor_npc_ids[vendor_npc_id] = true
		if (vendor["items"] as Array).is_empty():
			push_error("Vendor %s has an empty assortment" % vendor["id"])
			return false
		for vendor_item: Dictionary in vendor["items"]:
			if not registries["items"].has(vendor_item["item_id"]):
				push_error(
					"Vendor %s references unknown item %s"
					% [vendor["id"], vendor_item["item_id"]]
				)
				return false
			if int(vendor_item["buy_price"]) <= 0:
				push_error("Vendor %s sells %s without a price" % [
					vendor["id"],
					vendor_item["item_id"],
				])
				return false
			if int(vendor_item["sell_price"]) < 0:
				push_error("Vendor %s buys %s for a negative price" % [
					vendor["id"],
					vendor_item["item_id"],
				])
				return false

	for npc: Dictionary in npcs.values():
		if (npc["quest_ids"] as Array).is_empty() and not vendor_npc_ids.has(npc["id"]):
			push_error("NPC %s neither offers a quest nor trades" % npc["id"])
			return false
		for quest_id: String in npc["quest_ids"]:
			if not quests.has(quest_id):
				push_error("NPC %s references unknown quest %s" % [npc["id"], quest_id])
				return false

	var invalid_vendor: Dictionary = vendors["vendor_grom"].duplicate(true)
	invalid_vendor["npc_id"] = ""
	if GameDataRegistryType.validate_entry("vendors", invalid_vendor).is_empty():
		push_error("Game data registry accepted a vendor without an NPC")
		return false
	var invalid_price: Dictionary = vendors["vendor_grom"].duplicate(true)
	invalid_price["items"] = [{"item_id": "starter_sword", "buy_price": -1, "sell_price": 1}]
	if GameDataRegistryType.validate_entry("vendors", invalid_price).is_empty():
		push_error("Game data registry accepted a vendor with a negative price")
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
