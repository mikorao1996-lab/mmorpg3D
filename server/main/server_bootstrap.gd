extends SceneTree

const PROJECT_LOGGER: GDScript = preload("res://shared/logging/project_logger.gd")
var server_listener: RefCounted


func _initialize() -> void:
	var display_server_name: String = DisplayServer.get_name().to_lower()
	if display_server_name != "headless":
		push_error("Server bootstrap must be launched with --headless")
		quit(2)
		return

	PROJECT_LOGGER.log_info("Server bootstrap initialized")
	server_listener = load("res://server/net/server_listener.gd").new()
	if not server_listener.start():
		quit(2)


func _process(delta: float) -> bool:
	if server_listener != null:
		server_listener.poll()
	return false
