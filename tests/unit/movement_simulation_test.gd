extends RefCounted

const MovementSimulationType: GDScript = preload("res://shared/sim/movement_simulation.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	if config.is_empty():
		return false

	var simulation_step: float = float(config["simulation_step_seconds"])
	var movement_speed: float = float(config["movement_speed"])
	var max_input: float = float(config["max_input_magnitude"])
	var world_extent: float = float(config["world_half_extent"])
	var moved_position: Vector3 = MovementSimulationType.advance(
		Vector3.ZERO,
		Vector2.RIGHT,
		simulation_step,
		movement_speed,
		max_input,
		world_extent,
	)
	if not is_equal_approx(moved_position.x, movement_speed * simulation_step):
		push_error("Movement simulation returned an incorrect displacement")
		return false

	var clamped_position: Vector3 = MovementSimulationType.advance(
		Vector3(world_extent, 0.0, 0.0),
		Vector2.RIGHT,
		simulation_step,
		movement_speed,
		max_input,
		world_extent,
	)
	if not is_equal_approx(clamped_position.x, world_extent):
		push_error("Movement simulation exceeded configured world bounds")
		return false
	return true
