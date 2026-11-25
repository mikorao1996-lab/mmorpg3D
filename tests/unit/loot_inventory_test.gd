extends RefCounted

const InventoryComponentType: GDScript = preload("res://server/systems/inventory_component.gd")
const ServerZoneType: GDScript = preload("res://server/world/server_zone.gd")
const ServerWorldType: GDScript = preload("res://server/world/server_world.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	if config.is_empty():
		return false
	var registries: Dictionary = GameDataRegistryType.load_all()
	if registries.is_empty():
		return false

	var inventory: RefCounted = InventoryComponentType.new(2)
	var potion_definition: Dictionary = registries["items"]["minor_potion"]
	var sword_definition: Dictionary = registries["items"]["starter_sword"]
	for _index: int in range(3):
		var add_potion_result: Variant = inventory.call(
			"add_item",
			"minor_potion",
			potion_definition,
		)
		if typeof(add_potion_result) != TYPE_DICTIONARY or not add_potion_result["ok"]:
			push_error("Inventory rejected an item that fit an existing stack")
			return false
	var add_sword_result: Variant = inventory.call(
		"add_item",
		"starter_sword",
		sword_definition,
	)
	if typeof(add_sword_result) != TYPE_DICTIONARY or not add_sword_result["ok"]:
		push_error("Inventory rejected an item that fit a new slot")
		return false
	var full_result: Dictionary = inventory.call(
		"add_item",
		"starter_sword",
		sword_definition,
	)
	if full_result.get("reason") != "inventory_full":
		push_error("Inventory did not reject an item when all slots were occupied")
		return false
	var inventory_snapshot: Array = inventory.get_snapshot()
	if (
		inventory_snapshot.size() != 2
		or inventory_snapshot[0] != ["minor_potion", 3]
		or inventory_snapshot[1] != ["starter_sword", 1]
	):
		push_error("Inventory snapshot did not preserve item stacks")
		return false

	config["inventory_slot_count"] = 1
	registries["mobs"]["training_slime"]["aggro_range"] = 0.0
	registries["mobs"]["training_slime"]["loot_item_ids"] = ["starter_sword"]
	registries["mobs"]["training_slime"]["loot_chances"] = []
	var zone: RefCounted = ServerZoneType.new("starter", config, registries)
	zone.add_player_at(1, Vector3.ZERO)
	zone.add_player_at(2, Vector3(8.0, 0.0, 8.0))

	if zone.damage_mob("training_slime", 100.0):
		var first_spawn: Dictionary = zone.spawn_loot_for_mob("training_slime")
		if not bool(first_spawn.get("ok", false)):
			push_error("Zone did not spawn loot for a defeated mob")
			return false
		var duplicate_spawn: Dictionary = zone.spawn_loot_for_mob("training_slime")
		if bool(duplicate_spawn.get("ok", true)):
			push_error("Zone spawned duplicate drops for the same defeat")
			return false
		var first_drop_id: int = first_spawn["drop_ids"][0]
		var out_of_range: Dictionary = zone.pickup_loot(2, first_drop_id)
		if out_of_range.get("reason") != "out_of_range":
			push_error("Zone accepted loot pickup from outside the configured range")
			return false
		if zone.create_snapshots()[1]["drops"].size() != 1:
			push_error("Out-of-range pickup removed the ground drop")
			return false
		var first_pickup: Dictionary = zone.pickup_loot(1, first_drop_id)
		if not bool(first_pickup.get("accepted", false)):
			push_error("Zone rejected an in-range loot pickup")
			return false
	else:
		push_error("Zone could not defeat a mob for the loot test")
		return false

	zone.advance(float(registries["mobs"]["training_slime"]["respawn_seconds"]) + 0.1)
	if not zone.damage_mob("training_slime", 100.0):
		push_error("Defeated mob did not respawn for the inventory-capacity test")
		return false
	var second_spawn: Dictionary = zone.spawn_loot_for_mob("training_slime")
	if not bool(second_spawn.get("ok", false)):
		push_error("Zone did not spawn loot after mob respawn")
		return false
	var full_inventory_pickup: Dictionary = zone.pickup_loot(1, second_spawn["drop_ids"][0])
	if full_inventory_pickup.get("reason") != "inventory_full":
		push_error("Zone did not enforce inventory capacity")
		return false
	if zone.create_snapshots()[1]["drops"].size() != 1:
		push_error("Full-inventory pickup removed the ground drop")
		return false

	zone.remove_player(1)
	zone.remove_player(2)

	var transfer_registry: Dictionary = GameDataRegistryType.load_all()
	transfer_registry["mobs"]["training_slime"]["aggro_range"] = 0.0
	transfer_registry["mobs"]["training_slime"]["health"] = 1.0
	transfer_registry["mobs"]["training_slime"]["loot_item_ids"] = ["starter_sword"]
	transfer_registry["mobs"]["training_slime"]["loot_chances"] = []
	transfer_registry["abilities"]["starter_slash"]["cooldown_seconds"] = 0.0
	transfer_registry["abilities"]["starter_slash"]["resource_cost"] = 0.0
	transfer_registry["abilities"]["starter_slash"]["magnitude"] = 5.0
	var world: RefCounted = ServerWorldType.new(config, transfer_registry)
	world.add_player(3)
	var kill_result: Dictionary = world.cast_ability(3, "starter_slash", "training_slime")
	if not bool(kill_result.get("accepted", false)):
		push_error("Server world rejected a valid lethal ability for the loot test")
		return false
	var world_pickup: Dictionary = world.pickup_loot(3, 1)
	if not bool(world_pickup.get("accepted", false)):
		push_error("Server world did not route a valid loot pickup")
		return false
	if not world.move_player_to_zone(3, "dungeon"):
		push_error("Server world rejected zone transfer with an inventory")
		return false
	var transferred_snapshot: Dictionary = world.create_snapshots()[3]
	if transferred_snapshot.get("inventory", []) != [["starter_sword", 1]]:
		push_error("Player inventory did not survive zone transfer")
		return false
	world.remove_player(3)
	return true
