class_name SimulationConfig
extends RefCounted

const CONFIG_PATH: String = "res://resources/data/simulation.json"
const REQUIRED_NUMBER_KEYS: PackedStringArray = [
	"simulation_step_seconds",
	"movement_speed",
	"player_respawn_seconds",
	"max_input_magnitude",
	"world_half_extent",
	"interest_radius",
	"spawn_spacing",
	"snapshot_interval_seconds",
	"input_send_interval_seconds",
	"interpolation_buffer_seconds",
	"snapshot_buffer_capacity",
	"local_reconciliation_factor",
	"player_visual_radius",
	"player_visual_height",
	"camera_height",
	"camera_distance",
	"camera_look_height",
]


static func load_config() -> Dictionary:
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot open simulation config: %s" % CONFIG_PATH)
		return {}

	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		push_error(
			"Invalid simulation config at line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
		return {}
	if not parser.data is Dictionary:
		push_error("Simulation config root must be a JSON object")
		return {}

	var config: Dictionary = parser.data
	var zone_ids_value: Variant = config.get("zone_ids", null)
	if not zone_ids_value is Array or zone_ids_value.is_empty():
		push_error("Simulation config must define at least one zone ID")
		return {}
	var seen_zone_ids: Dictionary = {}
	for zone_id: Variant in zone_ids_value:
		if zone_id is not String or zone_id.strip_edges().is_empty():
			push_error("Simulation config zone IDs must be non-empty strings")
			return {}
		if seen_zone_ids.has(zone_id):
			push_error("Simulation config contains a duplicate zone ID: %s" % zone_id)
			return {}
		seen_zone_ids[zone_id] = true

	for key: String in REQUIRED_NUMBER_KEYS:
		if not config.has(key):
			push_error("Simulation config is missing required key: %s" % key)
			return {}
		var value: Variant = config[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			push_error("Simulation config value must be numeric: %s" % key)
			return {}
		var number: float = float(value)
		if not is_finite(number) or number <= 0.0:
			push_error("Simulation config value must be finite and positive: %s" % key)
			return {}

	if float(config["local_reconciliation_factor"]) > 1.0:
		push_error("local_reconciliation_factor cannot exceed 1")
		return {}
	if int(config["snapshot_buffer_capacity"]) < 2:
		push_error("snapshot_buffer_capacity must be at least 2")
		return {}
	return config
