extends SceneTree

const PROJECT_LOGGER: GDScript = preload("res://shared/logging/project_logger.gd")


func _initialize() -> void:
	var display_server_name: String = DisplayServer.get_name().to_lower()
	if display_server_name != "headless":
		push_error("Server bootstrap must be launched with --headless")
		quit(2)
		return

	PROJECT_LOGGER.log_info("Server bootstrap initialized")


func _process(_delta: float) -> bool:
	return false
