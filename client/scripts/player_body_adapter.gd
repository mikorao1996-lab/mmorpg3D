class_name PlayerBodyAdapter
extends CharacterBody3D


func move_to_simulated_position(target_position: Vector3, delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		push_error("Player body adapter requires a positive finite physics delta")
		return

	velocity = (target_position - global_position) / delta
	move_and_slide()
	velocity = Vector3.ZERO


func set_simulated_position(target_position: Vector3) -> void:
	global_position = target_position
	velocity = Vector3.ZERO
