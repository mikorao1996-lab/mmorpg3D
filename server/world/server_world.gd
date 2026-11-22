class_name ServerWorld
extends RefCounted

const MovementSimulationType: GDScript = preload("res://shared/sim/movement_simulation.gd")

var _movement_speed: float
var _max_input_magnitude: float
var _world_half_extent: float
var _spawn_spacing: float
var _simulation_step_seconds: float
var _snapshot_interval_seconds: float
var _positions: Dictionary = {}
var _inputs: Dictionary = {}
var _simulation_accumulator: float = 0.0
var _snapshot_accumulator: float = 0.0
var _next_spawn_index: int = 0


func _init(config: Dictionary) -> void:
	_movement_speed = float(config["movement_speed"])
	_max_input_magnitude = float(config["max_input_magnitude"])
	_world_half_extent = float(config["world_half_extent"])
	_spawn_spacing = float(config["spawn_spacing"])
	_simulation_step_seconds = float(config["simulation_step_seconds"])
	_snapshot_interval_seconds = float(config["snapshot_interval_seconds"])


func add_player(peer_id: int) -> void:
	if _positions.has(peer_id):
		return
	var spawn_x: float = float(_next_spawn_index) * _spawn_spacing
	_next_spawn_index += 1
	_positions[peer_id] = Vector3(spawn_x, 0.0, 0.0)
	_inputs[peer_id] = Vector2.ZERO


func remove_player(peer_id: int) -> void:
	_positions.erase(peer_id)
	_inputs.erase(peer_id)


func set_input_direction(peer_id: int, input_direction: Vector2) -> bool:
	if not _positions.has(peer_id):
		return false
	var input_magnitude: float = input_direction.length()
	if not is_finite(input_magnitude) or input_magnitude > _max_input_magnitude:
		return false
	_inputs[peer_id] = input_direction
	return true


func advance(delta: float) -> bool:
	_simulation_accumulator += delta
	var snapshot_due: bool = false
	while _simulation_accumulator >= _simulation_step_seconds:
		for peer_id: int in _positions:
			_positions[peer_id] = MovementSimulationType.advance(
				_positions[peer_id],
				_inputs[peer_id],
				_simulation_step_seconds,
				_movement_speed,
				_max_input_magnitude,
				_world_half_extent,
			)
		_simulation_accumulator -= _simulation_step_seconds
		_snapshot_accumulator += _simulation_step_seconds
		if _snapshot_accumulator >= _snapshot_interval_seconds:
			_snapshot_accumulator -= _snapshot_interval_seconds
			snapshot_due = true
	return snapshot_due


func create_snapshot() -> Dictionary:
	var player_ids: Array = _positions.keys()
	player_ids.sort()
	var player_states: Array = []
	for peer_id: int in player_ids:
		player_states.append([peer_id, _positions[peer_id]])
	return {
		"server_time_ms": Time.get_ticks_msec(),
		"players": player_states,
	}
