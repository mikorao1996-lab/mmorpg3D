extends RefCounted

## Checks the layout of the hub and the integrity of its content.
##
## Every NPC and every mob instance has to stand inside of the world, far
## enough from the others, and close enough to the spawn point to be reached
## on foot. The content has to be complete: every quest has to be offered by
## an NPC, every objective has to be achievable, every equipment slot has to
## be filled by something the player can obtain, and the vendor has to cover
## the items that cannot be looted.

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")

const ENTITY_CLEARANCE: float = 2.5
const SPAWN_CLEARANCE: float = 1.5
const WALK_LIMIT: float = 18.0
const MIN_MOB_COUNT: int = 8
const MAX_MOB_COUNT: int = 12


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	var registries: Dictionary = GameDataRegistryType.load_all()
	if config.is_empty() or registries.is_empty():
		return false

	if not _check_layout(config, registries):
		return false
	if not _check_mob_population(registries):
		return false
	if not _check_quests(registries):
		return false
	if not _check_equipment(registries):
		return false
	if not _check_vendor(registries):
		return false
	return true


## Checks that the entities of the hub are placed on free ground, inside of
## the world, and not too far away from the spawn point.
func _check_layout(config: Dictionary, registries: Dictionary) -> bool:
	var entities: Array = _collect_entities(registries)
	if entities.size() < 4:
		push_error("The hub has too few entities to be a hub")
		return false

	var world_half_extent: float = float(config["world_half_extent"])
	for entity: Dictionary in entities:
		var position: Vector3 = entity["position"]
		if absf(position.x) > world_half_extent - 1.0:
			push_error("Entity %s stands outside of the world" % entity["id"])
			return false
		if absf(position.z) > world_half_extent - 1.0:
			push_error("Entity %s stands outside of the world" % entity["id"])
			return false
		if position.length() > WALK_LIMIT:
			push_error("Entity %s is too far from the spawn point" % entity["id"])
			return false

	for first_index: int in range(entities.size()):
		for second_index: int in range(first_index + 1, entities.size()):
			var first_entity: Dictionary = entities[first_index]
			var second_entity: Dictionary = entities[second_index]
			var distance: float = (first_entity["position"] as Vector3).distance_to(
				second_entity["position"] as Vector3,
			)
			if distance < ENTITY_CLEARANCE:
				push_error(
					"Entities %s and %s stand too close to each other"
					% [first_entity["id"], second_entity["id"]]
				)
				return false

	var spawn_spacing: float = float(config["spawn_spacing"])
	for spawn_index: int in range(5):
		var spawn_point: Vector3 = Vector3(float(spawn_index) * spawn_spacing, 0.0, 0.0)
		for entity: Dictionary in entities:
			if (entity["position"] as Vector3).distance_to(spawn_point) < SPAWN_CLEARANCE:
				push_error(
					"Entity %s stands on the spawn point of a player" % entity["id"]
				)
				return false
	return true


## Checks that the hub holds a population of mobs, with a boss among them.
func _check_mob_population(registries: Dictionary) -> bool:
	var instances: Array = GameDataRegistryType.build_mob_instances(registries["mobs"])
	if instances.size() < MIN_MOB_COUNT or instances.size() > MAX_MOB_COUNT:
		push_error("The hub holds an unexpected number of mobs")
		return false
	if registries["mobs"].size() < 2:
		push_error("The hub holds fewer than two kinds of mobs")
		return false

	var boss_count: int = 0
	for mob_definition: Dictionary in registries["mobs"].values():
		if bool(mob_definition["is_boss"]):
			boss_count += 1
	if boss_count != 1:
		push_error("The hub does not hold exactly one boss")
		return false

	var instance_types: Dictionary = GameDataRegistryType.build_mob_instance_types(
		registries["mobs"],
	)
	for instance: Dictionary in instances:
		var instance_id: String = instance["instance_id"]
		if not instance_types.has(instance_id):
			push_error("The mob instance %s has no type" % instance_id)
			return false
	return true


## Checks that the quests are offered, and that their objectives are
## achievable.
func _check_quests(registries: Dictionary) -> bool:
	var offered_quests: Dictionary = {}
	for npc_definition: Dictionary in registries["npcs"].values():
		for quest_id: String in npc_definition["quest_ids"]:
			offered_quests[quest_id] = true

	var looted_items: Dictionary = _collect_looted_items(registries)
	var vendor_items: Dictionary = _collect_vendor_items(registries)
	var mob_types: Dictionary = _collect_mob_types(registries)

	for quest_definition: Dictionary in registries["quests"].values():
		var quest_id: String = quest_definition["id"]
		if not offered_quests.has(quest_id):
			push_error("Quest %s is not offered by any NPC" % quest_id)
			return false
		for reward_item_id: String in quest_definition["reward_item_ids"]:
			if not registries["items"].has(reward_item_id):
				push_error("Quest %s rewards an unknown item" % quest_id)
				return false

		var objective_type: String = quest_definition["objective_type"]
		var objective_target: String = quest_definition["objective_target"]
		match objective_type:
			"kill":
				if not registries["mobs"].has(objective_target):
					push_error("Quest %s targets an unknown mob" % quest_id)
					return false
				if not mob_types.has(objective_target):
					push_error("Quest %s targets a mob without spawn points" % quest_id)
					return false
			"collect":
				if not registries["items"].has(objective_target):
					push_error("Quest %s targets an unknown item" % quest_id)
					return false
				if (
					not looted_items.has(objective_target)
					and not vendor_items.has(objective_target)
				):
					push_error("Quest %s targets an item nobody provides" % quest_id)
					return false
			"talk":
				if not registries["npcs"].has(objective_target):
					push_error("Quest %s targets an unknown NPC" % quest_id)
					return false
			_:
				push_error("Quest %s has an unknown objective type" % quest_id)
				return false
	return true


## Checks that every equipment slot has an item, and that every item can be
## obtained by the player.
func _check_equipment(registries: Dictionary) -> bool:
	var obtainable_items: Dictionary = _collect_looted_items(registries)
	for quest_definition: Dictionary in registries["quests"].values():
		for reward_item_id: String in quest_definition["reward_item_ids"]:
			obtainable_items[reward_item_id] = true
	for vendor_item_id: String in _collect_vendor_items(registries).keys():
		obtainable_items[vendor_item_id] = true

	var slots: Dictionary = {}
	for item_definition: Dictionary in registries["items"].values():
		var slot: String = str(item_definition.get("equipment_slot", ""))
		if slot.is_empty():
			continue
		slots[slot] = true
		var item_id: String = item_definition["id"]
		if not obtainable_items.has(item_id):
			push_error("Item %s cannot be obtained by the player" % item_id)
			return false

	if slots.size() < 4:
		push_error("The catalog covers too few equipment slots")
		return false
	for required_slot: String in ["weapon", "head", "chest", "hands", "legs", "feet"]:
		if not slots.has(required_slot):
			push_error("No item covers the equipment slot %s" % required_slot)
			return false
	return true


## Checks that the vendor sells known items, and that it covers the items the
## player cannot loot.
func _check_vendor(registries: Dictionary) -> bool:
	var vendor_items: Dictionary = _collect_vendor_items(registries)
	if vendor_items.is_empty():
		push_error("The hub has no vendor")
		return false

	for vendor_definition: Dictionary in registries["vendors"].values():
		var npc_id: String = vendor_definition["npc_id"]
		if not registries["npcs"].has(npc_id):
			push_error("The vendor %s has no NPC" % vendor_definition["id"])
			return false
		for vendor_item: Dictionary in vendor_definition["items"]:
			var item_id: String = vendor_item["item_id"]
			if not registries["items"].has(item_id):
				push_error("The vendor sells an unknown item %s" % item_id)
				return false
			var buy_price: int = int(vendor_item["buy_price"])
			var sell_price: int = int(vendor_item["sell_price"])
			if buy_price <= 0 or sell_price < 0 or sell_price >= buy_price:
				push_error("The vendor prices the item %s unreasonably" % item_id)
				return false

	var looted_items: Dictionary = _collect_looted_items(registries)
	var quest_items: Dictionary = {}
	for quest_definition: Dictionary in registries["quests"].values():
		for reward_item_id: String in quest_definition["reward_item_ids"]:
			quest_items[reward_item_id] = true
	for item_id: String in registries["items"].keys():
		if looted_items.has(item_id) or quest_items.has(item_id):
			continue
		if not vendor_items.has(item_id):
			push_error("Item %s is neither looted nor sold by the vendor" % item_id)
			return false
	return true


## Collects the NPCs and the mob instances of the hub.
func _collect_entities(registries: Dictionary) -> Array:
	var entities: Array = []
	for npc_id: String in registries["npcs"].keys():
		var npc_definition: Dictionary = registries["npcs"][npc_id]
		var npc_position: Array = npc_definition["spawn_position"]
		entities.append({
			"id": str(npc_id),
			"position": Vector3(
				float(npc_position[0]),
				float(npc_position[1]),
				float(npc_position[2]),
			),
		})
	for instance: Dictionary in GameDataRegistryType.build_mob_instances(
		registries["mobs"]
	):
		entities.append({
			"id": str(instance["instance_id"]),
			"position": instance["position"],
		})
	return entities


## Collects the mob types of the hub and their number of instances.
func _collect_mob_types(registries: Dictionary) -> Dictionary:
	var mob_types: Dictionary = {}
	for instance: Dictionary in GameDataRegistryType.build_mob_instances(
		registries["mobs"]
	):
		var type_id: String = instance["type_id"]
		mob_types[type_id] = int(mob_types.get(type_id, 0)) + 1
	return mob_types


## Collects the items that the mobs can drop.
func _collect_looted_items(registries: Dictionary) -> Dictionary:
	var looted_items: Dictionary = {}
	for mob_definition: Dictionary in registries["mobs"].values():
		for loot_item_id: String in mob_definition["loot_item_ids"]:
			looted_items[loot_item_id] = true
		for loot_chance: Dictionary in mob_definition["loot_chances"]:
			looted_items[str(loot_chance["item_id"])] = true
	return looted_items


## Collects the items that the vendors sell.
func _collect_vendor_items(registries: Dictionary) -> Dictionary:
	var vendor_items: Dictionary = {}
	for vendor_definition: Dictionary in registries["vendors"].values():
		for vendor_item: Dictionary in vendor_definition["items"]:
			vendor_items[str(vendor_item["item_id"])] = true
	return vendor_items
