class_name ServerZone
extends RefCounted

const MovementSimulationType: GDScript = preload("res://shared/sim/movement_simulation.gd")

var zone_id: String
var _movement_speed: float
var _max_input_magnitude: float
var _world_half_extent: float
var _interest_radius: float
var _spawn_spacing: float
var _simulation_step_seconds: float
var _snapshot_interval_seconds: float
var _players: Dictionary = {}
var _simulation_accumulator: float = 0.0
var _snapshot_accumulator: float = 0.0
var _next_spawn_index: int = 0
var _mob_definitions: Dictionary = {}
var _mobs: Dictionary = {}


func _init(
	configured_zone_id: String,
	config: Dictionary,
	game_data_registry: Dictionary,
) -> void:
	zone_id = configured_zone_id
	_movement_speed = float(config["movement_speed"])
	_max_input_magnitude = float(config["max_input_magnitude"])
	_world_half_extent = float(config["world_half_extent"])
	_interest_radius = float(config["interest_radius"])
	_spawn_spacing = float(config["spawn_spacing"])
	_simulation_step_seconds = float(config["simulation_step_seconds"])
	_snapshot_interval_seconds = float(config["snapshot_interval_seconds"])
	_mob_definitions = game_data_registry["mobs"]
	for mob_id: String in _mob_definitions:
		var definition: Dictionary = _mob_definitions[mob_id]
		var spawn_position: Array = definition["spawn_position"]
		_mobs[mob_id] = {
			"position": Vector3(
				float(spawn_position[0]),
				float(spawn_position[1]),
				float(spawn_position[2]),
			),
			"health": float(definition["health"]),
			"respawn_remaining_seconds": 0.0,
		}


func add_player(peer_id: int) -> void:
	if _players.has(peer_id):
		return
	var spawn_x: float = float(_next_spawn_index) * _spawn_spacing
	_next_spawn_index += 1
	add_player_at(peer_id, Vector3(spawn_x, 0.0, 0.0))


func add_player_at(peer_id: int, position: Vector3) -> void:
	if _players.has(peer_id):
		return
	_players[peer_id] = {
		"position": position,
		"input": Vector2.ZERO,
	}


func remove_player(peer_id: int) -> void:
	_players.erase(peer_id)


func get_player_position(peer_id: int) -> Vector3:
	if not _players.has(peer_id):
		push_error("Cannot retrieve position for missing player %d in zone %s" % [peer_id, zone_id])
		return Vector3.ZERO
	var player_state: Dictionary = _players[peer_id]
	return player_state["position"]


func get_mob_state(mob_id: String) -> Dictionary:
	if not _mobs.has(mob_id):
		return {}
	var mob_state: Dictionary = _mobs[mob_id]
	var mob_definition: Dictionary = _mob_definitions[mob_id]
	return {
		"position": mob_state["position"],
		"health": mob_state["health"],
		"max_health": float(mob_definition["health"]),
	}


func damage_mob(mob_id: String, damage: float) -> bool:
	if not _mobs.has(mob_id) or not is_finite(damage) or damage <= 0.0:
		return false
	var mob_state: Dictionary = _mobs[mob_id]
	if float(mob_state["health"]) <= 0.0:
		return false
	mob_state["health"] = maxf(0.0, float(mob_state["health"]) - damage)
	if float(mob_state["health"]) == 0.0:
		var definition: Dictionary = _mob_definitions[mob_id]
		mob_state["respawn_remaining_seconds"] = float(definition["respawn_seconds"])
	return true


func set_input_direction(peer_id: int, input_direction: Vector2) -> bool:
	if not _players.has(peer_id):
		return false
	var input_magnitude: float = input_direction.length()
	if not is_finite(input_magnitude) or input_magnitude > _max_input_magnitude:
		return false
	var player_state: Dictionary = _players[peer_id]
	player_state["input"] = input_direction
	return true


func advance(delta: float) -> bool:
	_simulation_accumulator += delta
	var snapshot_due: bool = false
	while _simulation_accumulator >= _simulation_step_seconds:
		for peer_id: int in _players:
			var player_state: Dictionary = _players[peer_id]
			player_state["position"] = MovementSimulationType.advance(
				player_state["position"],
				player_state["input"],
				_simulation_step_seconds,
				_movement_speed,
				_max_input_magnitude,
				_world_half_extent,
			)
		_advance_mob_respawns()
		_simulation_accumulator -= _simulation_step_seconds
		_snapshot_accumulator += _simulation_step_seconds
		if _snapshot_accumulator >= _snapshot_interval_seconds:
			_snapshot_accumulator -= _snapshot_interval_seconds
			snapshot_due = true
	return snapshot_due


func _advance_mob_respawns() -> void:
	for mob_id: String in _mobs:
		var mob_state: Dictionary = _mobs[mob_id]
		if float(mob_state["health"]) > 0.0:
			continue
		mob_state["respawn_remaining_seconds"] = maxf(
			0.0,
			float(mob_state["respawn_remaining_seconds"]) - _simulation_step_seconds,
		)
		if float(mob_state["respawn_remaining_seconds"]) == 0.0:
			var definition: Dictionary = _mob_definitions[mob_id]
			mob_state["health"] = float(definition["health"])


func create_snapshots() -> Dictionary:
	var snapshots: Dictionary = {}
	for observer_id: int in _players:
		snapshots[observer_id] = _create_snapshot_for(observer_id)
	return snapshots


func _create_snapshot_for(observer_id: int) -> Dictionary:
	var observer_state: Dictionary = _players[observer_id]
	var observer_position: Vector3 = observer_state["position"]
	var interest_radius_squared: float = _interest_radius * _interest_radius
	var player_ids: Array = _players.keys()
	player_ids.sort()
	var player_states: Array = []
	for peer_id: int in player_ids:
		var player_state: Dictionary = _players[peer_id]
		var player_position: Vector3 = player_state["position"]
		if (
			peer_id == observer_id
			or observer_position.distance_squared_to(player_position) <= interest_radius_squared
		):
			player_states.append([peer_id, player_position])
	var mob_ids: Array = _mobs.keys()
	mob_ids.sort()
	var mob_states: Array = []
	for mob_id: String in mob_ids:
		var mob_state: Dictionary = _mobs[mob_id]
		var mob_definition: Dictionary = _mob_definitions[mob_id]
		mob_states.append([
			mob_id,
			mob_state["position"],
			mob_state["health"],
			float(mob_definition["health"]),
		])
	return {
		"zone_id": zone_id,
		"server_time_ms": Time.get_ticks_msec(),
		"players": player_states,
		"mobs": mob_states,
	}
