extends RefCounted

const ServerZoneType: GDScript = preload("res://server/world/server_zone.gd")
const ServerWorldType: GDScript = preload("res://server/world/server_world.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	var registries: Dictionary = GameDataRegistryType.load_all()
	if config.is_empty() or registries.is_empty():
		return false
	config["inventory_slot_count"] = 1
	registries["items"]["training_axe"] = {
		"id": "training_axe",
		"name_key": "item_training_axe",
		"item_type": "weapon",
		"equipment_slot": "weapon",
		"stack_limit": 1,
		"level_requirement": 1,
		"sell_price": 0,
		"stats": {"attack": 5},
	}
	registries["items"]["training_helm"] = {
		"id": "training_helm",
		"name_key": "item_training_helm",
		"item_type": "armor",
		"equipment_slot": "head",
		"stack_limit": 1,
		"level_requirement": 2,
		"sell_price": 0,
		"stats": {"defense": 2},
	}
	if (
		not GameDataRegistryType.validate_entry("items", registries["items"]["training_axe"]).is_empty()
		or not GameDataRegistryType.validate_entry("items", registries["items"]["training_helm"]).is_empty()
	):
		push_error("Game data registry rejected valid equipment definitions")
		return false
	var invalid_armor: Dictionary = registries["items"]["training_helm"].duplicate(true)
	invalid_armor["equipment_slot"] = "weapon"
	if GameDataRegistryType.validate_entry("items", invalid_armor).is_empty():
		push_error("Game data registry accepted armor in the weapon slot")
		return false

	var zone: RefCounted = ServerZoneType.new("starter", config, registries)
	zone.add_player_at(1, Vector3.ZERO)
	var player_state: Dictionary = zone.get_player_state(1)
	var inventory: RefCounted = player_state["inventory"]
	if not bool(inventory.call(
		"add_item",
		"starter_sword",
		registries["items"]["starter_sword"],
	)["ok"]):
		push_error("Could not add test sword to inventory")
		return false
	var equip_result: Dictionary = zone.equip_item(1, "starter_sword")
	if not bool(equip_result["accepted"]):
		push_error("Server rejected valid weapon equip")
		return false
	var snapshot: Dictionary = zone.create_snapshots()[1]
	player_state = zone.get_player_state(1)
	if (
		snapshot["equipment"].get("weapon", "") != "starter_sword"
		or snapshot["inventory"].size() != 0
		or not is_equal_approx(float(player_state["equipment_attack"]), 2.0)
	):
		push_error("Equipped item was not reflected in inventory, snapshot, and stats")
		return false

	if not bool(inventory.call(
		"add_item",
		"training_axe",
		registries["items"]["training_axe"],
	)["ok"]):
		push_error("Could not add replacement weapon to inventory")
		return false
	var replacement_result: Dictionary = zone.equip_item(1, "training_axe")
	snapshot = zone.create_snapshots()[1]
	player_state = zone.get_player_state(1)
	if (
		not bool(replacement_result["accepted"])
		or snapshot["equipment"].get("weapon", "") != "training_axe"
		or snapshot["inventory"] != [["starter_sword", 1]]
		or not is_equal_approx(float(player_state["equipment_attack"]), 5.0)
	):
		push_error("Weapon replacement did not atomically swap inventory and equipment")
		return false

	var full_inventory_unequip: Dictionary = zone.unequip_item(1, "weapon")
	if (
		bool(full_inventory_unequip["accepted"])
		or full_inventory_unequip["reason"] != "inventory_full"
		or zone.create_snapshots()[1]["equipment"].get("weapon", "") != "training_axe"
	):
		push_error("Unequip changed gear despite a full inventory")
		return false
	inventory.call("remove_item", "starter_sword")
	if not bool(zone.unequip_item(1, "weapon")["accepted"]):
		push_error("Server rejected unequip when inventory had room")
		return false
	inventory.call("remove_item", "training_axe")

	if not bool(inventory.call(
		"add_item",
		"training_helm",
		registries["items"]["training_helm"],
	)["ok"]):
		push_error("Could not add test armor to inventory")
		return false
	var level_rejection: Dictionary = zone.equip_item(1, "training_helm")
	if bool(level_rejection["accepted"]) or level_rejection["reason"] != "level_requirement":
		push_error("Server did not enforce equipment level requirement")
		return false
	var level_up_result: Dictionary = zone.award_experience(
		1,
		int(registries["progression"]["level_2"]["experience_required"]),
	)
	if not bool(level_up_result["ok"]) or int(level_up_result["level"]) != 2:
		push_error("Could not level up for the armor requirement test")
		return false
	var armor_result: Dictionary = zone.equip_item(1, "training_helm")
	snapshot = zone.create_snapshots()[1]
	player_state = zone.get_player_state(1)
	if (
		not bool(armor_result["accepted"])
		or snapshot["equipment"].get("head", "") != "training_helm"
		or not is_equal_approx(
			float(player_state["defense"]),
			float(registries["progression"]["level_2"]["defense"]) + 2.0,
		)
	):
		push_error("Armor equip did not apply its server-side defense bonus")
		return false

	var combat_registry: Dictionary = registries.duplicate(true)
	combat_registry["mobs"]["training_slime"]["spawn_position"] = [0.0, 0.0, 0.0]
	combat_registry["mobs"]["training_slime"]["health"] = 5.0
	combat_registry["mobs"]["training_slime"]["aggro_range"] = 0.0
	combat_registry["mobs"]["training_slime"]["loot_item_ids"] = ["starter_sword"]
	combat_registry["mobs"]["training_wolf"]["spawn_position"] = [0.0, 0.0, 0.0]
	combat_registry["mobs"]["training_wolf"]["health"] = 100.0
	combat_registry["mobs"]["training_wolf"]["aggro_range"] = 0.0
	combat_registry["abilities"]["starter_slash"]["cooldown_seconds"] = 0.0
	combat_registry["abilities"]["starter_slash"]["resource_cost"] = 0.0
	combat_registry["abilities"]["starter_slash"]["magnitude"] = 5.0
	var world: RefCounted = ServerWorldType.new(config, combat_registry)
	world.add_player(3)
	var kill_result: Dictionary = world.cast_ability(3, "starter_slash", "training_slime")
	if not bool(kill_result["accepted"]) or float(kill_result["health"]) != 0.0:
		push_error("Could not defeat test mob to obtain the sword")
		return false
	var pickup_result: Dictionary = world.pickup_loot(3, 1)
	if not bool(pickup_result["accepted"]):
		push_error("Could not obtain test sword from ground loot")
		return false
	if not bool(world.equip_item(3, "starter_sword")["accepted"]):
		push_error("Could not equip loot through server world")
		return false
	var equipped_attack: Dictionary = world.cast_ability(
		3,
		"starter_slash",
		"training_wolf",
	)
	if (
		not bool(equipped_attack["accepted"])
		or not is_equal_approx(float(equipped_attack["health"]), 94.0)
	):
		push_error(
			"Equipped weapon did not increase server-authoritative combat damage: %s"
			% str(equipped_attack),
		)
		return false
	return true
