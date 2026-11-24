class_name GameDataRegistry
extends RefCounted

const REGISTRY_PATHS: Dictionary = {
	"items": "res://resources/data/items.json",
	"abilities": "res://resources/data/abilities.json",
	"mobs": "res://resources/data/mobs.json",
	"progression": "res://resources/data/progression.json",
	"quests": "res://resources/data/quests.json",
}
const ITEM_TYPES: PackedStringArray = ["weapon", "armor", "consumable", "quest"]
const EQUIPMENT_SLOTS: PackedStringArray = [
	"weapon",
	"head",
	"chest",
	"hands",
	"legs",
	"feet",
]
const ARMOR_SLOTS: PackedStringArray = ["head", "chest", "hands", "legs", "feet"]
const TARGET_TYPES: PackedStringArray = ["self", "ally", "enemy"]
const ABILITY_EFFECT_TYPES: PackedStringArray = ["damage", "heal", "buff"]
const QUEST_OBJECTIVE_TYPES: PackedStringArray = ["kill", "collect", "talk"]
const ITEM_STAT_KEYS: PackedStringArray = ["attack", "defense", "health", "resource"]
const SCHEMA_VERSION: int = 1
const MAX_CHARACTER_LEVEL: int = 10


static func load_all() -> Dictionary:
	var registries: Dictionary = {}
	for registry_name: String in REGISTRY_PATHS:
		var entries: Dictionary = _load_registry(
			registry_name,
			REGISTRY_PATHS[registry_name],
		)
		if entries.is_empty():
			return {}
		registries[registry_name] = entries

	var reference_error: String = validate_references(registries)
	if not reference_error.is_empty():
		push_error(reference_error)
		return {}
	return registries


static func _load_registry(registry_name: String, path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open %s registry: %s" % [registry_name, path])
		return {}

	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		push_error(
			"Invalid %s registry at line %d: %s"
			% [registry_name, parser.get_error_line(), parser.get_error_message()]
		)
		return {}
	if not parser.data is Dictionary:
		push_error("%s registry root must be a JSON object" % registry_name)
		return {}

	var registry_data: Dictionary = parser.data
	var schema_version_value: Variant = registry_data.get("schema_version", null)
	if typeof(schema_version_value) != TYPE_INT and typeof(schema_version_value) != TYPE_FLOAT:
		push_error("%s registry has an unsupported schema version" % registry_name)
		return {}
	var schema_version_number: float = float(schema_version_value)
	if not is_finite(schema_version_number) or schema_version_number != float(SCHEMA_VERSION):
		push_error("%s registry has an unsupported schema version" % registry_name)
		return {}
	var entries: Variant = registry_data.get("entries", null)
	if not entries is Array or entries.is_empty():
		push_error("%s registry must contain a non-empty entries array" % registry_name)
		return {}

	var records: Dictionary = {}
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			push_error("%s registry entries must be JSON objects" % registry_name)
			return {}
		var entry: Dictionary = entry_value
		var id_value: Variant = entry.get("id", null)
		if not _is_non_empty_string(id_value):
			push_error("%s registry entry is missing a non-empty id" % registry_name)
			return {}
		var id: String = id_value
		if records.has(id):
			push_error("Duplicate %s registry ID: %s" % [registry_name, id])
			return {}
		var validation_error: String = validate_entry(registry_name, entry)
		if not validation_error.is_empty():
			push_error(
				"Invalid %s entry %s: %s" % [registry_name, id, validation_error]
			)
			return {}
		records[id] = entry
	return records


static func validate_entry(registry_name: String, entry: Dictionary) -> String:
	if not _is_non_empty_string(entry.get("id")):
		return "missing non-empty id"
	match registry_name:
		"items":
			var item_type: Variant = entry.get("item_type")
			var equipment_slot: Variant = entry.get("equipment_slot", "")
			var equipment_slot_valid: bool = (
				(item_type == "weapon" and equipment_slot == "weapon")
				or (
					item_type == "armor"
					and equipment_slot is String
					and ARMOR_SLOTS.has(equipment_slot)
				)
				or (
					(item_type == "consumable" or item_type == "quest")
					and equipment_slot == ""
				)
			)
			var is_equipment_item: bool = item_type == "weapon" or item_type == "armor"
			var stack_limit_value: Variant = entry.get("stack_limit")
			var equipment_stack_limit_valid: bool = (
				not is_equipment_item
				or (
					_is_integer_at_least(stack_limit_value, 1)
					and float(stack_limit_value) == 1.0
				)
			)
			var level_requirement_value: Variant = entry.get("level_requirement")
			var level_requirement_valid: bool = (
				_is_integer_at_least(level_requirement_value, 1)
				and int(level_requirement_value) <= MAX_CHARACTER_LEVEL
			)
			if (
				not _is_non_empty_string(entry.get("name_key"))
				or not _is_enum_value(entry.get("item_type"), ITEM_TYPES)
				or not equipment_slot_valid
				or not equipment_stack_limit_valid
				or not _is_integer_at_least(entry.get("stack_limit"), 1)
				or not level_requirement_valid
				or not _is_integer_at_least(entry.get("sell_price"), 0)
				or not _validate_item_stats(entry.get("stats"))
				or not _is_valid_consumable_effect(item_type, entry.get("stats"))
			):
				return "invalid item fields"
		"abilities":
			if (
				not _is_non_empty_string(entry.get("name_key"))
				or not _is_non_empty_string(entry.get("class_id"))
				or not _is_enum_value(entry.get("target_type"), TARGET_TYPES)
				or not _is_number_at_least(entry.get("cooldown_seconds"), 0.0)
				or not _is_number_at_least(entry.get("resource_cost"), 0.0)
				or not _is_number_at_least(entry.get("range"), 0.0)
				or not _is_enum_value(entry.get("effect_type"), ABILITY_EFFECT_TYPES)
				or not _is_number_greater_than(entry.get("magnitude"), 0.0)
			):
				return "invalid ability fields"
		"mobs":
			if (
				not _is_non_empty_string(entry.get("name_key"))
				or typeof(entry.get("is_boss")) != TYPE_BOOL
				or not _is_integer_at_least(entry.get("level"), 1)
				or not _is_integer_at_least(entry.get("experience_reward"), 0)
				or not _is_number_greater_than(entry.get("health"), 0.0)
				or not _is_number_at_least(entry.get("attack"), 0.0)
				or not _is_number_at_least(entry.get("defense"), 0.0)
				or not _is_number_at_least(entry.get("move_speed"), 0.0)
				or not _is_number_at_least(entry.get("aggro_range"), 0.0)
				or not _is_number_at_least(entry.get("attack_range"), 0.0)
				or not _is_number_greater_than(entry.get("attack_interval_seconds"), 0.0)
				or not _is_number_greater_than(entry.get("respawn_seconds"), 0.0)
				or not _is_vector3_array(entry.get("spawn_position"))
				or not _is_number_greater_than(entry.get("visual_radius"), 0.0)
				or not _is_number_greater_than(entry.get("visual_height"), 0.0)
				or not _is_string_array(entry.get("loot_item_ids"))
			):
				return "invalid mob fields"
		"progression":
			if (
				not _is_integer_at_least(entry.get("level"), 1)
				or int(entry["level"]) > MAX_CHARACTER_LEVEL
				or not _is_integer_at_least(entry.get("experience_required"), 0)
				or not _is_number_greater_than(entry.get("max_health"), 0.0)
				or not _is_number_greater_than(entry.get("max_resource"), 0.0)
				or not _is_number_greater_than(entry.get("attack_multiplier"), 0.0)
				or not _is_number_at_least(entry.get("defense"), 0.0)
			):
				return "invalid progression fields"
		"quests":
			if (
				not _is_non_empty_string(entry.get("name_key"))
				or not _is_integer_at_least(entry.get("min_level"), 1)
				or not _is_enum_value(entry.get("objective_type"), QUEST_OBJECTIVE_TYPES)
				or not _is_non_empty_string(entry.get("objective_target"))
				or not _is_integer_at_least(entry.get("objective_count"), 1)
				or not _is_integer_at_least(entry.get("reward_experience"), 0)
				or not _is_string_array(entry.get("reward_item_ids"))
			):
				return "invalid quest fields"
		_:
			return "unknown game data registry: %s" % registry_name
	return ""


static func _validate_item_stats(stats_value: Variant) -> bool:
	if not stats_value is Dictionary:
		return false
	for stat_name: Variant in stats_value:
		if stat_name is not String or not ITEM_STAT_KEYS.has(stat_name):
			return false
		if not _is_number_at_least(stats_value[stat_name], 0.0):
			return false
	return true


## Consumables must define a usable effect: healing or resource restoration.
## Equipment and quest items intentionally have no consumable effect.
static func _is_valid_consumable_effect(item_type: Variant, stats_value: Variant) -> bool:
	if item_type != "consumable":
		return true
	if not stats_value is Dictionary:
		return false
	var stats: Dictionary = stats_value
	return (
		_is_number_greater_than(stats.get("health", 0.0), 0.0)
		or _is_number_greater_than(stats.get("resource", 0.0), 0.0)
	)


static func validate_references(registries: Dictionary) -> String:
	if (
		not registries.has("items")
		or not registries.has("mobs")
		or not registries.has("progression")
		or not registries.has("quests")
	):
		return "Game data registries are missing required collections"
	var items: Dictionary = registries["items"]
	var mobs: Dictionary = registries["mobs"]
	var progression: Dictionary = registries["progression"]
	if progression.size() != MAX_CHARACTER_LEVEL:
		return "Progression registry must define levels 1 through %d" % MAX_CHARACTER_LEVEL
	var previous_experience_required: int = -1
	var previous_level_definition: Dictionary = {}
	for level: int in range(1, MAX_CHARACTER_LEVEL + 1):
		var level_id: String = "level_%d" % level
		if not progression.has(level_id):
			return "Progression registry is missing %s" % level_id
		var level_definition: Dictionary = progression[level_id]
		if int(level_definition["level"]) != level:
			return "Progression entry %s has a mismatched level" % level_id
		var experience_required: int = int(level_definition["experience_required"])
		if (
			(level == 1 and experience_required != 0)
			or (level > 1 and experience_required <= previous_experience_required)
		):
			return "Progression experience thresholds must increase from level 1"
		if level > 1 and (
			float(level_definition["max_health"])
					<= float(previous_level_definition["max_health"])
			or float(level_definition["max_resource"])
					< float(previous_level_definition["max_resource"])
			or float(level_definition["attack_multiplier"])
					< float(previous_level_definition["attack_multiplier"])
			or float(level_definition["defense"])
					< float(previous_level_definition["defense"])
		):
			return "Progression stats must not decrease between levels"
		previous_experience_required = experience_required
		previous_level_definition = level_definition

	for mob: Dictionary in mobs.values():
		for item_id: String in mob["loot_item_ids"]:
			if not items.has(item_id):
				return "Mob %s references unknown loot item %s" % [mob["id"], item_id]

	for quest: Dictionary in registries["quests"].values():
		var objective_type: String = quest["objective_type"]
		var target_id: String = quest["objective_target"]
		if objective_type == "kill" and not mobs.has(target_id):
			return "Quest %s references unknown mob %s" % [quest["id"], target_id]
		if objective_type == "collect" and not items.has(target_id):
			return "Quest %s references unknown item %s" % [quest["id"], target_id]
		for item_id: String in quest["reward_item_ids"]:
			if not items.has(item_id):
				return "Quest %s references unknown reward item %s" % [quest["id"], item_id]
	return ""


static func _is_non_empty_string(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func _is_enum_value(value: Variant, allowed_values: PackedStringArray) -> bool:
	return value is String and allowed_values.has(value)


static func _is_integer_at_least(value: Variant, minimum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number == floor(number)


static func _is_number_at_least(value: Variant, minimum: float) -> bool:
	return _is_finite_number(value) and float(value) >= minimum


static func _is_number_greater_than(value: Variant, minimum: float) -> bool:
	return _is_finite_number(value) and float(value) > minimum


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func _is_string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not _is_non_empty_string(item) or seen.has(item):
			return false
		seen[item] = true
	return true


static func _is_vector3_array(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not _is_finite_number(component):
			return false
	return true
