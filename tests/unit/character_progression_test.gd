extends RefCounted

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const ServerWorldType: GDScript = preload("res://server/world/server_world.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	var game_data: Dictionary = GameDataRegistryType.load_all()
	if config.is_empty() or game_data.is_empty():
		return false

	game_data["abilities"]["heavy_strike"]["cooldown_seconds"] = 0.0
	var level_two_experience: int = int(
		game_data["progression"]["level_2"]["experience_required"],
	)
	game_data["mobs"]["training_slime"]["experience_reward"] = level_two_experience
	# Both mobs are placed next to the spawn point, so the hits are in range.
	game_data["mobs"]["training_slime"]["spawn_positions"] = [[0.0, 0.0, -2.0]]
	game_data["mobs"]["training_wolf"]["spawn_positions"] = [[0.0, 0.0, -2.0]]
	game_data["mobs"]["training_wolf"]["attack_range"] = 2.5

	var server_world: RefCounted = ServerWorldType.new(config, game_data)
	server_world.add_player(1)
	var initial_player: Array = _get_player_entry(server_world)
	if (
		initial_player.size() != 10
		or initial_player[4] != 1
		or initial_player[5] != 0
		or not is_equal_approx(float(initial_player[2]), 100.0)
		or not is_equal_approx(float(initial_player[6]), 100.0)
	):
		push_error("New player did not start with configured level-one stats")
		return false

	var first_hit: Dictionary = server_world.cast_ability(
		1,
		"heavy_strike",
		"training_slime",
	)
	var player_after_first_hit: Array = _get_player_entry(server_world)
	if (
		not bool(first_hit.get("accepted", false))
		or player_after_first_hit.size() != 10
		or player_after_first_hit[5] != 0
	):
		push_error("A non-lethal hit awarded mob experience")
		return false
	var finishing_hit: Dictionary = server_world.cast_ability(
		1,
		"heavy_strike",
		"training_slime",
	)
	if not bool(finishing_hit.get("accepted", false)):
		push_error("Level progression test could not finish the slime")
		return false
	var leveled_player: Array = _get_player_entry(server_world)
	if (
		leveled_player.size() != 10
		or leveled_player[4] != 2
		or leveled_player[5] != level_two_experience
		or not is_equal_approx(float(leveled_player[2]), 110.0)
		or not is_equal_approx(float(leveled_player[3]), 110.0)
		or not is_equal_approx(float(leveled_player[6]), 105.0)
		or not is_equal_approx(float(leveled_player[7]), 105.0)
	):
		push_error("Killing a mob did not award XP and apply level-two stats")
		return false

	var wolf_hit: Dictionary = server_world.cast_ability(
		1,
		"heavy_strike",
		"training_wolf",
	)
	if (
		not bool(wolf_hit.get("accepted", false))
		or not is_equal_approx(float(wolf_hit["health"]), 27.25)
	):
		push_error("Level attack multiplier or mob defense was not applied")
		return false

	server_world.advance(float(config["simulation_step_seconds"]))
	var defended_player: Array = _get_player_entry(server_world)
	if (
		defended_player.is_empty()
		or not is_equal_approx(float(defended_player[2]), 105.5)
	):
		push_error("Player defense was not applied to mob damage")
		return false

	var cap_game_data: Dictionary = GameDataRegistryType.load_all()
	cap_game_data["abilities"]["heavy_strike"]["cooldown_seconds"] = 0.0
	var cap_experience: int = (
		int(cap_game_data["progression"]["level_10"]["experience_required"]) + 50
	)
	cap_game_data["mobs"]["training_slime"]["experience_reward"] = cap_experience
	cap_game_data["mobs"]["training_slime"]["spawn_positions"] = [[0.0, 0.0, -2.0]]
	var cap_world: RefCounted = ServerWorldType.new(config, cap_game_data)
	cap_world.add_player(1)
	for hit_index: int in range(2):
		var cap_hit: Dictionary = cap_world.cast_ability(
			1,
			"heavy_strike",
			"training_slime",
		)
		if not bool(cap_hit.get("accepted", false)):
			push_error("Level-cap test could not defeat the slime")
			return false
	var capped_player: Array = _get_player_entry(cap_world)
	if (
		capped_player.size() != 10
		or capped_player[4] != 10
		or capped_player[5] != cap_experience
		or not is_equal_approx(float(capped_player[2]), 190.0)
		or not is_equal_approx(float(capped_player[3]), 190.0)
		or not is_equal_approx(float(capped_player[6]), 145.0)
		or not is_equal_approx(float(capped_player[7]), 145.0)
	):
		push_error("Progression did not apply level-ten stats or enforce the cap")
		return false
	return true


func _get_player_entry(server_world: RefCounted) -> Array:
	var snapshots: Dictionary = server_world.create_snapshots()
	if not snapshots.has(1):
		return []
	var player_entries: Array = snapshots[1]["players"]
	for entry: Variant in player_entries:
		if entry is Array and entry.size() == 10 and entry[0] == 1:
			return entry
	return []
