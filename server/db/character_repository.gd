extends RefCounted

const INSERT_SQL: String = (
	"INSERT INTO characters ("
	+ "character_id, character_name, class_id, level, experience, zone_id, "
	+ "position_x, position_y, position_z, health, resource"
	+ ") VALUES ("
	+ "$1::uuid, $2::text, $3::text, $4::smallint, $5::bigint, $6::text, "
	+ "$7::double precision, $8::double precision, $9::double precision, "
	+ "$10::double precision, $11::double precision"
	+ ")"
)

const SAVE_SQL: String = (
	INSERT_SQL
	+ " ON CONFLICT (character_id) DO UPDATE SET "
	+ "character_name = EXCLUDED.character_name, "
	+ "class_id = EXCLUDED.class_id, "
	+ "level = EXCLUDED.level, "
	+ "experience = EXCLUDED.experience, "
	+ "zone_id = EXCLUDED.zone_id, "
	+ "position_x = EXCLUDED.position_x, "
	+ "position_y = EXCLUDED.position_y, "
	+ "position_z = EXCLUDED.position_z, "
	+ "health = EXCLUDED.health, "
	+ "resource = EXCLUDED.resource, "
	+ "updated_at = CURRENT_TIMESTAMP"
)

const LOAD_SQL: String = (
	"SELECT character_id::text AS character_id, character_name, class_id, "
	+ "level::text AS level, experience::text AS experience, zone_id, "
	+ "position_x::text AS position_x, position_y::text AS position_y, "
	+ "position_z::text AS position_z, health::text AS health, "
	+ "resource::text AS resource "
	+ "FROM characters WHERE character_id = $1::uuid"
)

const CHARACTER_FIELDS: Array[String] = [
	"character_id",
	"character_name",
	"class_id",
	"level",
	"experience",
	"zone_id",
	"position",
	"health",
	"resource",
]

const ROW_FIELDS: Array[String] = [
	"character_id",
	"character_name",
	"class_id",
	"level",
	"experience",
	"zone_id",
	"position_x",
	"position_y",
	"position_z",
	"health",
	"resource",
]

var _connection: RefCounted


func _init(connection: RefCounted) -> void:
	_connection = connection


func create_character(character: Dictionary) -> Dictionary:
	var validation_error: String = _validate_character(character)
	if not validation_error.is_empty():
		return _failure(validation_error)
	return _write_character(INSERT_SQL, character)


func save_character(character: Dictionary) -> Dictionary:
	var validation_error: String = _validate_character(character)
	if not validation_error.is_empty():
		return _failure(validation_error)
	return _write_character(SAVE_SQL, character)


func load_character(character_id: String) -> Dictionary:
	if character_id.strip_edges().is_empty():
		return _failure("Character ID must not be empty.")

	var query_result: Dictionary = _execute(LOAD_SQL, [character_id])
	if not _is_ok(query_result):
		return query_result
	if typeof(query_result.get("rows")) != TYPE_ARRAY:
		return _failure("PostgreSQL returned a malformed character query result.")

	var rows: Array = query_result["rows"]
	if rows.is_empty():
		return {"ok": true, "found": false}
	if rows.size() != 1 or typeof(rows[0]) != TYPE_DICTIONARY:
		return _failure("PostgreSQL returned an invalid character row count or shape.")

	var decode_result: Dictionary = _decode_character(rows[0])
	if not _is_ok(decode_result):
		return decode_result
	return {
		"ok": true,
		"found": true,
		"character": decode_result["character"],
	}


func _write_character(query: String, character: Dictionary) -> Dictionary:
	var position: Vector3 = character["position"]
	var query_result: Dictionary = _execute(
		query,
		[
			character["character_id"],
			character["character_name"],
			character["class_id"],
			character["level"],
			character["experience"],
			character["zone_id"],
			position.x,
			position.y,
			position.z,
			float(character["health"]),
			float(character["resource"]),
		],
	)
	if not _is_ok(query_result):
		return query_result
	if int(query_result.get("affected_rows", 0)) != 1:
		return _failure("PostgreSQL did not confirm the character write.")
	return query_result


func _decode_character(row: Dictionary) -> Dictionary:
	for field: String in ROW_FIELDS:
		if not row.has(field):
			return _failure("PostgreSQL character row is missing field %s." % field)

	var level_text: String = str(row["level"])
	var experience_text: String = str(row["experience"])
	if not level_text.is_valid_int() or not experience_text.is_valid_int():
		return _failure("PostgreSQL returned invalid character progression values.")

	var number_fields: Array[String] = [
		"position_x",
		"position_y",
		"position_z",
		"health",
		"resource",
	]
	for field: String in number_fields:
		if not row.has(field) or not str(row[field]).is_valid_float():
			return _failure("PostgreSQL returned invalid character field %s." % field)

	var character: Dictionary = {
		"character_id": str(row["character_id"]),
		"character_name": str(row["character_name"]),
		"class_id": str(row["class_id"]),
		"level": int(level_text),
		"experience": int(experience_text),
		"zone_id": str(row["zone_id"]),
		"position": Vector3(
			float(str(row["position_x"])),
			float(str(row["position_y"])),
			float(str(row["position_z"])),
		),
		"health": float(str(row["health"])),
		"resource": float(str(row["resource"])),
	}
	return {"ok": true, "character": character}


func _validate_character(character: Dictionary) -> String:
	for field: String in CHARACTER_FIELDS:
		if not character.has(field):
			return "Character is missing field %s." % field

	for field: String in ["character_id", "character_name", "class_id", "zone_id"]:
		if typeof(character[field]) != TYPE_STRING or str(character[field]).strip_edges().is_empty():
			return "Character field %s must be a non-empty string." % field
	if str(character["character_name"]).length() > 32:
		return "Character name must not exceed 32 characters."
	if str(character["class_id"]).length() > 64 or str(character["zone_id"]).length() > 64:
		return "Character class and zone IDs must not exceed 64 characters."
	if typeof(character["level"]) != TYPE_INT or int(character["level"]) < 1 or int(character["level"]) > 10:
		return "Character level must be an integer between 1 and 10."
	if typeof(character["experience"]) != TYPE_INT or int(character["experience"]) < 0:
		return "Character experience must be a non-negative integer."
	if typeof(character["position"]) != TYPE_VECTOR3:
		return "Character position must be a Vector3."
	var position: Vector3 = character["position"]
	if not is_finite(position.x) or not is_finite(position.y) or not is_finite(position.z):
		return "Character position must contain only finite coordinates."
	for field: String in ["health", "resource"]:
		if not _is_finite_number(character[field]) or float(character[field]) < 0.0:
			return "Character %s must be a finite non-negative number." % field
	return ""


func _execute(query: String, parameters: Array = []) -> Dictionary:
	var result: Variant = _connection.call("execute_query", query, parameters)
	if typeof(result) != TYPE_DICTIONARY:
		return _failure("PostgreSQL driver returned a malformed query result.")
	return result


func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	return is_finite(float(value))


func _is_ok(result: Dictionary) -> bool:
	return bool(result.get("ok", false))


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
