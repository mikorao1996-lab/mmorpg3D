extends RefCounted

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const ServerWorldType: GDScript = preload("res://server/world/server_world.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	var game_data: Dictionary = GameDataRegistryType.load_all()
	if config.is_empty() or game_data.is_empty():
		return false
	game_data["abilities"]["starter_slash"]["cooldown_seconds"] = 0.0
	game_data["mobs"]["training_slime"]["respawn_seconds"] = 0.1

	var server_world: RefCounted = ServerWorldType.new(config, game_data)
	server_world.add_player(1)
	for expected_health: float in [22.0, 14.0, 6.0, 0.0]:
		var cast_result: Dictionary = server_world.cast_ability(
			1,
			"starter_slash",
			"training_slime",
		)
		if not cast_result["accepted"] \
				or not is_equal_approx(float(cast_result["health"]), expected_health):
			push_error("Configured ability damage did not produce the expected mob health")
			return false

	var dead_target_result: Dictionary = server_world.cast_ability(
		1,
		"starter_slash",
		"training_slime",
	)
	if dead_target_result["accepted"] or dead_target_result["reason"] != "target_dead":
		push_error("Server world accepted an ability targeting a dead mob")
		return false

	server_world.advance(0.1)
	var mob_entries: Array = server_world.create_snapshots()[1]["mobs"]
	for mob_entry: Variant in mob_entries:
		if mob_entry is Array and mob_entry[0] == "training_slime":
			if is_equal_approx(float(mob_entry[2]), 30.0):
				return true
			push_error("Dead mob did not respawn at configured health")
			return false
	push_error("Respawned mob was missing from the world snapshot")
	return false
