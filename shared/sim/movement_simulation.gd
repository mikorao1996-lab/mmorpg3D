class_name MovementSimulation
extends RefCounted


static func advance(
	position: Vector3,
	input_direction: Vector2,
	delta: float,
	movement_speed: float,
	max_input_magnitude: float,
	world_half_extent: float,
) -> Vector3:
	if delta <= 0.0 or not is_finite(delta):
		return position

	var input_magnitude: float = input_direction.length()
	if not is_finite(input_magnitude):
		return position
	if input_magnitude > max_input_magnitude:
		input_direction = input_direction / input_magnitude * max_input_magnitude

	var displacement: Vector3 = Vector3(input_direction.x, 0.0, input_direction.y)
	var next_position: Vector3 = position + displacement * movement_speed * delta
	return Vector3(
		clampf(next_position.x, -world_half_extent, world_half_extent),
		0.0,
		clampf(next_position.z, -world_half_extent, world_half_extent),
	)
