extends RefCounted

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const ServerWorldType: GDScript = preload("res://server/world/server_world.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	var game_data: Dictionary = GameDataRegistryType.load_all()
	if config.is_empty() or game_data.is_empty():
		return false
	var chase_world: RefCounted = ServerWorldType.new(config, game_data)
	chase_world.add_player(1)
	chase_world.advance(0.1)
	var chase_snapshot: Dictionary = chase_world.create_snapshots()[1]
	var slime_moved: bool = false
	for mob_entry: Variant in chase_snapshot["mobs"]:
		if mob_entry is Array and mob_entry[0] == "training_slime":
			if mob_entry[1] is Vector3:
				var mob_position: Vector3 = mob_entry[1]
				slime_moved = mob_position.z > -2.0
	if not slime_moved:
		push_error("Mob did not pursue a player inside its configured aggro range")
		return false

	config["player_respawn_seconds"] = 0.1
	game_data["progression"]["level_1"]["max_health"] = 40.0
	var slime: Dictionary = game_data["mobs"]["training_slime"]
	slime["attack"] = 25.0
	slime["attack_range"] = 6.0
	slime["attack_interval_seconds"] = 0.1
	slime["move_speed"] = 0.0

	var server_world: RefCounted = ServerWorldType.new(config, game_data)
	server_world.add_player(1)
	server_world.advance(0.05)
	var player_state: Array = _get_player_entry(server_world)
	if player_state.is_empty() or not is_equal_approx(float(player_state[2]), 15.0):
		push_error("Aggressive mob did not apply configured damage to the player")
		return false

	if not server_world.move_player_to_zone(1, "dungeon"):
		push_error("World rejected player transfer during combat")
		return false
	player_state = _get_player_entry(server_world)
	if player_state.is_empty() or not is_equal_approx(float(player_state[2]), 15.0):
		push_error("Zone transfer did not preserve player health")
		return false
	if not server_world.move_player_to_zone(1, "starter"):
		push_error("World rejected return transfer after combat")
		return false

	server_world.advance(0.1)
	player_state = _get_player_entry(server_world)
	if player_state.is_empty() or not is_equal_approx(float(player_state[2]), 0.0):
		push_error("Player did not reach zero health after configured mob attacks")
		return false
	var dead_cast: Dictionary = server_world.cast_ability(
		1,
		"starter_slash",
		"training_slime",
	)
	if dead_cast["accepted"] or dead_cast["reason"] != "player_dead":
		push_error("Server world accepted an ability cast while the player was defeated")
		return false

	if not server_world.set_input_direction(1, Vector2.RIGHT):
		push_error("World rejected input from a defeated player")
		return false
	server_world.advance(0.1)
	player_state = _get_player_entry(server_world)
	if (
		player_state.is_empty()
		or not is_equal_approx(float(player_state[2]), 40.0)
		or player_state[1] != Vector3.ZERO
	):
		push_error("Defeated player did not respawn at full health and the spawn point")
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
