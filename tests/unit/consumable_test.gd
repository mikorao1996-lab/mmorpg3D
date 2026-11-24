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

	var zone: RefCounted = ServerZoneType.new("starter", config, registries)
	zone.add_player_at(1, Vector3.ZERO)
	var player_state: Dictionary = zone.get_player_state(1)
	var inventory: RefCounted = player_state["inventory"]
	if not bool(inventory.call(
		"add_item",
		"minor_potion",
		registries["items"]["minor_potion"],
	)["ok"]):
		push_error("Could not add a potion to the test inventory")
		return false

	var unknown_item_result: Dictionary = zone.use_item(1, "missing_item")
	if bool(unknown_item_result["accepted"]) or unknown_item_result["reason"] != "unknown_item":
		push_error("Server accepted a request for an unknown item")
		return false
	var not_owned_result: Dictionary = zone.use_item(1, "greater_potion")
	if (
		bool(not_owned_result["accepted"])
		or not_owned_result["reason"] != "item_not_in_inventory"
	):
		push_error("Server allowed using an item the player does not own")
		return false
	var not_consumable_result: Dictionary = zone.use_item(1, "starter_sword")
	if (
		bool(not_consumable_result["accepted"])
		or not_consumable_result["reason"] != "not_consumable"
	):
		push_error("Server allowed using a non-consumable item")
		return false

	var full_health_result: Dictionary = zone.use_item(1, "minor_potion")
	if (
		bool(full_health_result["accepted"])
		or full_health_result["reason"] != "health_full"
	):
		push_error("Server consumed a potion while the player was at full health")
		return false
	if int(inventory.call("get_snapshot")[0][1]) != 1:
		push_error("A rejected potion use consumed the potion")
		return false

	if not zone.damage_player(1, 40.0):
		push_error("Could not damage the test player")
		return false
	var heal_result: Dictionary = zone.use_item(1, "minor_potion")
	if not bool(heal_result["accepted"]):
		push_error("Server rejected a valid potion use")
		return false
	player_state = zone.get_player_state(1)
	if (
		not is_equal_approx(float(player_state["health"]), 85.0)
		or inventory.call("get_snapshot").size() != 0
	):
		push_error("Potion use did not heal the player and consume the item")
		return false

	if not bool(inventory.call(
		"add_item",
		"stamina_tonic",
		registries["items"]["stamina_tonic"],
	)["ok"]):
		push_error("Could not add a tonic to the test inventory")
		return false
	if not zone.spend_player_resource(1, 60.0):
		push_error("Could not spend player resource for the tonic test")
		return false
	var tonic_result: Dictionary = zone.use_item(1, "stamina_tonic")
	player_state = zone.get_player_state(1)
	if (
		not bool(tonic_result["accepted"])
		or not is_equal_approx(float(player_state["resource"]), 80.0)
	):
		push_error("Tonic use did not restore the player resource")
		return false
	if not bool(inventory.call(
		"add_item",
		"stamina_tonic",
		registries["items"]["stamina_tonic"],
	)["ok"]):
		push_error("Could not add a second tonic to the test inventory")
		return false
	var capped_result: Dictionary = zone.use_item(1, "stamina_tonic")
	player_state = zone.get_player_state(1)
	if (
		not bool(capped_result["accepted"])
		or not is_equal_approx(float(player_state["resource"]), 100.0)
	):
		push_error("Tonic use did not cap the restored resource at the maximum")
		return false
	if not bool(inventory.call(
		"add_item",
		"stamina_tonic",
		registries["items"]["stamina_tonic"],
	)["ok"]):
		push_error("Could not add a third tonic to the test inventory")
		return false
	var full_resource_result: Dictionary = zone.use_item(1, "stamina_tonic")
	if (
		bool(full_resource_result["accepted"])
		or full_resource_result["reason"] != "resource_full"
	):
		push_error("Server consumed a tonic while the resource was already full")
		return false
	if int(inventory.call("get_snapshot")[0][1]) != 1:
		push_error("A rejected tonic use consumed the tonic")
		return false

	var world: RefCounted = ServerWorldType.new(config, registries)
	world.add_player(2)
	var routed_result: Dictionary = world.use_item(2, "minor_potion")
	if bool(routed_result["accepted"]) or routed_result["reason"] != "item_not_in_inventory":
		push_error("Server world did not route the item use request")
		return false
	return true
