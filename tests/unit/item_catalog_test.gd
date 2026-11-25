extends RefCounted

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

const MINIMUM_ITEM_COUNT: int = 15
const MAXIMUM_ITEM_COUNT: int = 20
const EQUIPMENT_SLOTS: PackedStringArray = [
	"weapon",
	"head",
	"chest",
	"hands",
	"legs",
	"feet",
]


func run() -> bool:
	var registries: Dictionary = GameDataRegistryType.load_all()
	if registries.is_empty():
		return false
	var items: Dictionary = registries["items"]
	if items.size() < MINIMUM_ITEM_COUNT or items.size() > MAXIMUM_ITEM_COUNT:
		push_error(
			"Item catalog must contain %d-%d items, found %d"
			% [MINIMUM_ITEM_COUNT, MAXIMUM_ITEM_COUNT, items.size()]
		)
		return false

	var slots_with_items: Dictionary = {}
	for slot_id: String in EQUIPMENT_SLOTS:
		slots_with_items[slot_id] = false
	for item_id: String in items:
		var item_definition: Dictionary = items[item_id]
		var level_requirement: int = int(item_definition["level_requirement"])
		if level_requirement < 1 or level_requirement > 10:
			push_error("Item %s has an out-of-range level requirement" % item_id)
			return false
		var equipment_slot: String = str(item_definition.get("equipment_slot", ""))
		if equipment_slot.is_empty():
			continue
		if not slots_with_items.has(equipment_slot):
			push_error("Item %s uses an unknown equipment slot" % item_id)
			return false
		slots_with_items[equipment_slot] = true
	for slot_id: String in EQUIPMENT_SLOTS:
		if not bool(slots_with_items[slot_id]):
			push_error("No item is registered for the %s equipment slot" % slot_id)
			return false

	var consumable_count: int = 0
	for item_id: String in items:
		var item_definition: Dictionary = items[item_id]
		if str(item_definition.get("item_type", "")) != "consumable":
			continue
		consumable_count += 1
		var item_stats: Dictionary = item_definition.get("stats", {})
		if (
			float(item_stats.get("health", 0.0)) <= 0.0
			and float(item_stats.get("resource", 0.0)) <= 0.0
		):
			push_error("Consumable %s has no usable effect" % item_id)
			return false
	if consumable_count == 0:
		push_error("Item catalog has no consumable items")
		return false

	var obtainable_items: Dictionary = {}
	for mob: Dictionary in registries["mobs"].values():
		for item_id: String in mob["loot_item_ids"]:
			obtainable_items[item_id] = true
		for chance_entry: Dictionary in mob["loot_chances"]:
			obtainable_items[str(chance_entry["item_id"])] = true
	for quest: Dictionary in registries["quests"].values():
		for item_id: String in quest["reward_item_ids"]:
			obtainable_items[item_id] = true
	for slot_id: String in EQUIPMENT_SLOTS:
		var slot_has_source: bool = false
		for item_id: String in items:
			if str(items[item_id].get("equipment_slot", "")) != slot_id:
				continue
			if obtainable_items.has(item_id):
				slot_has_source = true
				break
		if not slot_has_source:
			push_error(
				"No %s item can be obtained from mob loot or quest rewards" % slot_id
			)
			return false

	var invalid_consumable: Dictionary = items["minor_potion"].duplicate(true)
	invalid_consumable["stats"] = {}
	if GameDataRegistryType.validate_entry("items", invalid_consumable).is_empty():
		push_error("Game data registry accepted a consumable without an effect")
		return false
	var invalid_level: Dictionary = items["starter_sword"].duplicate(true)
	invalid_level["level_requirement"] = 11
	if GameDataRegistryType.validate_entry("items", invalid_level).is_empty():
		push_error("Game data registry accepted a level requirement above the cap")
		return false
	return true
