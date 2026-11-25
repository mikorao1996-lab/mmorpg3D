extends RefCounted

## Checks the currency of the vertical slice.
##
## The gold is earned from quests and from mob defeats, it is part of the
## world snapshot, and it survives a zone transfer.

const ServerZoneType: GDScript = preload("res://server/world/server_zone.gd")
const ServerWorldType: GDScript = preload("res://server/world/server_world.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

const MIRA_POSITION: Vector3 = Vector3(0.0, 0.0, 3.0)


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	var registries: Dictionary = GameDataRegistryType.load_all()
	if config.is_empty() or registries.is_empty():
		return false
	if not config.has("starting_gold"):
		push_error("The simulation config does not define the starting gold")
		return false
	var starting_gold: int = int(config["starting_gold"])

	var zone: RefCounted = ServerZoneType.new("starter", config, registries)
	zone.add_player_at(1, MIRA_POSITION)
	var player_state: Dictionary = zone.get_player_state(1)
	if int(player_state.get("gold", -1)) != starting_gold:
		push_error("The player did not start with the configured gold")
		return false

	var accept_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"accept",
		"slime_problem",
	)
	if not bool(accept_result["accepted"]):
		push_error("Server rejected a valid quest acceptance for the gold check")
		return false
	for _kill_index: int in range(3):
		zone.record_quest_kill(1, "training_slime")
	var turn_in_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"turn_in",
		"slime_problem",
	)
	if not bool(turn_in_result["accepted"]):
		push_error("Server rejected a valid quest hand-in for the gold check")
		return false
	var quest_gold: int = int(registries["quests"]["slime_problem"]["reward_gold"])
	if int(turn_in_result.get("reward_gold", -1)) != quest_gold:
		push_error("The quest hand-in did not report the configured gold reward")
		return false
	player_state = zone.get_player_state(1)
	if int(player_state["gold"]) != starting_gold + quest_gold:
		push_error("The quest hand-in did not award the configured gold")
		return false

	var snapshots: Dictionary = zone.create_snapshots()
	if int(snapshots[1].get("gold", -1)) != starting_gold + quest_gold:
		push_error("The world snapshot does not carry the gold of the player")
		return false

	var world_registries: Dictionary = GameDataRegistryType.load_all()
	world_registries["mobs"]["training_slime"]["aggro_range"] = 0.0
	world_registries["mobs"]["training_slime"]["health"] = 1.0
	world_registries["mobs"]["training_slime"]["loot_chances"] = []
	world_registries["abilities"]["starter_slash"]["cooldown_seconds"] = 0.0
	world_registries["abilities"]["starter_slash"]["resource_cost"] = 0.0
	world_registries["abilities"]["starter_slash"]["magnitude"] = 5.0
	var world: RefCounted = ServerWorldType.new(config, world_registries)
	world.add_player(3)
	var gold_before: int = int(world.create_snapshots()[3]["gold"])
	var kill_result: Dictionary = world.cast_ability(3, "starter_slash", "training_slime")
	if not bool(kill_result.get("accepted", false)):
		push_error("Server rejected a valid lethal ability for the gold check")
		return false
	var mob_gold: int = int(world_registries["mobs"]["training_slime"]["gold_reward"])
	var gold_after: int = int(world.create_snapshots()[3]["gold"])
	if gold_after != gold_before + mob_gold:
		push_error("The mob defeat did not award the configured gold")
		return false

	if not world.move_player_to_zone(3, "dungeon"):
		push_error("Server rejected a zone transfer for the gold check")
		return false
	var transferred_gold: int = int(world.create_snapshots()[3]["gold"])
	if transferred_gold != gold_after:
		push_error("The gold did not survive the zone transfer")
		return false

	var negative_award: Dictionary = zone.award_gold(1, -5)
	if bool(negative_award.get("ok", false)):
		push_error("Server accepted a negative gold award")
		return false
	zone.remove_player(1)
	world.remove_player(3)
	return true
