extends RefCounted

## Checks the probabilistic loot of a defeated mob.
##
## The guaranteed items always drop, an item with a chance of `1.0` always
## drops, and an item with a chance of `0.0` never drops. The statistical
## check uses a fixed seed, so the result is reproducible.

const LootSystemType: GDScript = preload("res://server/systems/loot_system.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

const ROLL_COUNT: int = 200


func run() -> bool:
	var registries: Dictionary = GameDataRegistryType.load_all()
	if registries.is_empty():
		return false
	var mobs: Dictionary = registries["mobs"]
	if not mobs.has("training_slime"):
		push_error("The mob registry does not define the training slime")
		return false

	var guaranteed_item_id: String = str(mobs["training_slime"]["loot_item_ids"][0])
	var loot_system: RefCounted = LootSystemType.new(2024)
	for _index: int in range(ROLL_COUNT):
		var mob_state: Dictionary = {
			"health": 0.0,
			"position": Vector3.ZERO,
			"loot_spawned": false,
		}
		var definition: Dictionary = {
			"loot_item_ids": [guaranteed_item_id],
			"loot_chances": [
				{"item_id": "always_drops", "chance": 1.0},
				{"item_id": "never_drops", "chance": 0.0},
			],
		}
		var spawn_result: Dictionary = loot_system.spawn_for_mob(mob_state, definition)
		if not bool(spawn_result.get("ok", false)):
			push_error("The loot system did not spawn the drops of a defeated mob")
			return false
		var drops: Dictionary = loot_system.get_drops()
		var dropped_items: Array = []
		for drop_id: Variant in drops:
			dropped_items.append(str(drops[drop_id]["item_id"]))
		if not dropped_items.has(guaranteed_item_id):
			push_error("A guaranteed loot item did not drop")
			return false
		if not dropped_items.has("always_drops"):
			push_error("A loot item with a chance of 1.0 did not drop")
			return false
		if dropped_items.has("never_drops"):
			push_error("A loot item with a chance of 0.0 dropped")
			return false

	var statistical_system: RefCounted = LootSystemType.new(2024)
	var success_count: int = 0
	for _index: int in range(ROLL_COUNT):
		if statistical_system.roll_chance(0.5):
			success_count += 1
	if success_count < ROLL_COUNT / 4 or success_count > (ROLL_COUNT * 3) / 4:
		push_error(
			"The chance roll is not distributed evenly: %d of %d rolls succeeded"
			% [success_count, ROLL_COUNT]
		)
		return false
	if statistical_system.roll_chance(0.0):
		push_error("A chance of 0.0 must never succeed")
		return false
	if not statistical_system.roll_chance(1.0):
		push_error("A chance of 1.0 must always succeed")
		return false

	var second_defeat: Dictionary = {
		"health": 0.0,
		"position": Vector3.ZERO,
		"loot_spawned": false,
	}
	var single_system: RefCounted = LootSystemType.new(7)
	var first_spawn: Dictionary = single_system.spawn_for_mob(second_defeat, {
		"loot_item_ids": ["minor_potion"],
		"loot_chances": [],
	})
	var second_spawn: Dictionary = single_system.spawn_for_mob(second_defeat, {
		"loot_item_ids": ["minor_potion"],
		"loot_chances": [],
	})
	if not bool(first_spawn.get("ok", false)):
		push_error("The loot system did not spawn the drops of a defeated mob")
		return false
	if bool(second_spawn.get("ok", true)):
		push_error("The loot system spawned the drops of the same defeat twice")
		return false
	return true
