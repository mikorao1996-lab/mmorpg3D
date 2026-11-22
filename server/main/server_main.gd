extends Node

const PROJECT_LOGGER: GDScript = preload("res://shared/logging/project_logger.gd")

var server_listener: RefCounted


func _ready() -> void:
	var display_server_name: String = DisplayServer.get_name().to_lower()
	if display_server_name != "headless":
		push_error("Server must be launched with --headless")
		get_tree().quit(2)
		return

	PROJECT_LOGGER.log_info("Server bootstrap initialized")
	server_listener = load("res://server/net/server_listener.gd").new()
	if not server_listener.start():
		get_tree().quit(2)


func _process(_delta: float) -> void:
	if server_listener != null:
		server_listener.poll()
