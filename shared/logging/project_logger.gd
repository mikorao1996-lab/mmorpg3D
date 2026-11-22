extends RefCounted

const _LEVEL_INFO: String = "INFO"
const _LEVEL_WARNING: String = "WARNING"
const _LEVEL_ERROR: String = "ERROR"


static func log_info(message: String) -> void:
	print_rich("[color=green][%s][/color] %s" % [_LEVEL_INFO, message])


static func log_warning(message: String) -> void:
	push_warning("[%s] %s" % [_LEVEL_WARNING, message])


static func log_error(message: String) -> void:
	push_error("[%s] %s" % [_LEVEL_ERROR, message])
