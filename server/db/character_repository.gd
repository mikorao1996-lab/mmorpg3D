extends RefCounted

## Repository of the persisted characters.
##
## The repository owns the SQL and the shape of the stored data; it never
## decides what a character is allowed to do. The gameplay rules live in
## `server/systems/character_session_service.gd`.
##
## The inventory, the equipment, and the quests are stored as JSONB documents:
## they are lists of small records that always travel together with the
## character, so a single row keeps the whole state of a character atomic.

const INSERT_SQL: String = (
	"INSERT INTO characters ("
	+ "character_id, character_name, character_token_hash, class_id, level, "
	+ "experience, gold, zone_id, position_x, position_y, position_z, "
	+ "health, resource, inventory, equipment, quests"
	+ ") VALUES ("
	+ "$1::uuid, $2::text, $3::text, $4::text, $5::smallint, $6::bigint, "
	+ "$7::integer, $8::text, $9::double precision, $10::double precision, "
	+ "$11::double precision, $12::double precision, $13::double precision, "
	+ "$14::jsonb, $15::jsonb, $16::jsonb"
	+ ")"
)

const SAVE_SQL: String = (
	INSERT_SQL
	+ " ON CONFLICT (character_id) DO UPDATE SET "
	+ "character_name = EXCLUDED.character_name, "
	+ "character_token_hash = EXCLUDED.character_token_hash, "
	+ "class_id = EXCLUDED.class_id, "
	+ "level = EXCLUDED.level, "
	+ "experience = EXCLUDED.experience, "
	+ "gold = EXCLUDED.gold, "
	+ "zone_id = EXCLUDED.zone_id, "
	+ "position_x = EXCLUDED.position_x, "
	+ "position_y = EXCLUDED.position_y, "
	+ "position_z = EXCLUDED.position_z, "
	+ "health = EXCLUDED.health, "
	+ "resource = EXCLUDED.resource, "
	+ "inventory = EXCLUDED.inventory, "
	+ "equipment = EXCLUDED.equipment, "
	+ "quests = EXCLUDED.quests, "
	+ "updated_at = CURRENT_TIMESTAMP"
)

const LOAD_SQL: String = (
	"SELECT character_id::text AS character_id, character_name, "
	+ "character_token_hash, class_id, level::text AS level, "
	+ "experience::text AS experience, gold::text AS gold, zone_id, "
	+ "position_x::text AS position_x, position_y::text AS position_y, "
	+ "position_z::text AS position_z, health::text AS health, "
	+ "resource::text AS resource, inventory::text AS inventory, "
	+ "equipment::text AS equipment, quests::text AS quests "
	+ "FROM characters WHERE character_id = $1::uuid"
)

const CHARACTER_FIELDS: Array[String] = [
	"character_id",
	"character_name",
	"character_token_hash",
	"class_id",
	"level",
	"experience",
	"gold",
	"zone_id",
	"position",
	"health",
	"resource",
	"inventory",
	"equipment",
	"quests",
]

const ROW_FIELDS: Array[String] = [
	"character_id",
	"character_name",
	"character_token_hash",
	"class_id",
	"level",
	"experience",
	"gold",
	"zone_id",
	"position_x",
	"position_y",
	"position_z",
	"health",
	"resource",
	"inventory",
	"equipment",
	"quests",
]

const UUID_REGEX: String = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

static var _uuid_regex: RegEx = null

var _connection: RefCounted


## Reports whether the value is the identifier of a character.
static func is_valid_character_id(value: String) -> bool:
	if _uuid_regex == null:
		_uuid_regex = RegEx.new()
		_uuid_regex.compile(UUID_REGEX)
	return _uuid_regex.search(value) != null


func _init(connection: RefCounted) -> void:
	_connection = connection


## Inserts a new character and fails when the character already exists.
func create_character(character: Dictionary) -> Dictionary:
	var validation_error: String = _validate_character(character)
	if not validation_error.is_empty():
		return _failure(validation_error)
	return _write_character(INSERT_SQL, character)


## Inserts or updates a character, so the same call can create and update.
func save_character(character: Dictionary) -> Dictionary:
	var validation_error: String = _validate_character(character)
	if not validation_error.is_empty():
		return _failure(validation_error)
	return _write_character(SAVE_SQL, character)


## Reads a character by its identifier.
##
## The result carries `found`, so the caller can tell an unknown character from
## a failed query.
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
			character["character_token_hash"],
			character["class_id"],
			character["level"],
			character["experience"],
			character["gold"],
			character["zone_id"],
			position.x,
			position.y,
			position.z,
			float(character["health"]),
			float(character["resource"]),
			JSON.stringify(character["inventory"]),
			JSON.stringify(character["equipment"]),
			JSON.stringify(character["quests"]),
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
	var gold_text: String = str(row["gold"])
	if (
		not level_text.is_valid_int()
		or not experience_text.is_valid_int()
		or not gold_text.is_valid_int()
	):
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

	var inventory_result: Dictionary = _decode_json_field(row["inventory"], TYPE_ARRAY)
	if not _is_ok(inventory_result):
		return _failure("PostgreSQL returned invalid character inventory: %s" % str(inventory_result["error"]))
	var equipment_result: Dictionary = _decode_json_field(row["equipment"], TYPE_DICTIONARY)
	if not _is_ok(equipment_result):
		return _failure("PostgreSQL returned invalid character equipment: %s" % str(equipment_result["error"]))
	var quests_result: Dictionary = _decode_json_field(row["quests"], TYPE_DICTIONARY)
	if not _is_ok(quests_result):
		return _failure("PostgreSQL returned invalid character quests: %s" % str(quests_result["error"]))

	var character: Dictionary = {
		"character_id": str(row["character_id"]),
		"character_name": str(row["character_name"]),
		"character_token_hash": str(row["character_token_hash"]),
		"class_id": str(row["class_id"]),
		"level": int(level_text),
		"experience": int(experience_text),
		"gold": int(gold_text),
		"zone_id": str(row["zone_id"]),
		"position": Vector3(
			float(str(row["position_x"])),
			float(str(row["position_y"])),
			float(str(row["position_z"])),
		),
		"health": float(str(row["health"])),
		"resource": float(str(row["resource"])),
		"inventory": inventory_result["value"],
		"equipment": equipment_result["value"],
		"quests": quests_result["value"],
	}
	return {"ok": true, "character": character}


## Decodes a JSONB column, which the driver returns as text.
func _decode_json_field(value: Variant, expected_type: int) -> Dictionary:
	if typeof(value) == expected_type:
		return {"ok": true, "value": value}
	var text_value: String = str(value)
	if text_value.strip_edges().is_empty():
		return _failure("the column is empty.")
	var parsed: Variant = JSON.parse_string(text_value)
	if typeof(parsed) != expected_type:
		return _failure("the column does not hold the expected JSON type.")
	return {"ok": true, "value": parsed}


func _validate_character(character: Dictionary) -> String:
	for field: String in CHARACTER_FIELDS:
		if not character.has(field):
			return "Character is missing field %s." % field

	for field: String in ["character_id", "character_name", "class_id", "zone_id"]:
		if typeof(character[field]) != TYPE_STRING or str(character[field]).strip_edges().is_empty():
			return "Character field %s must be a non-empty string." % field
	if not is_valid_character_id(str(character["character_id"])):
		return "Character ID must be a UUID."
	if str(character["character_name"]).length() > 32:
		return "Character name must not exceed 32 characters."
	if str(character["class_id"]).length() > 64 or str(character["zone_id"]).length() > 64:
		return "Character class and zone IDs must not exceed 64 characters."
	if typeof(character["character_token_hash"]) != TYPE_STRING:
		return "Character token hash must be a string."
	if str(character["character_token_hash"]).length() != 64:
		return "Character token hash must be a SHA-256 hex digest."
	if typeof(character["level"]) != TYPE_INT or int(character["level"]) < 1 or int(character["level"]) > 10:
		return "Character level must be an integer between 1 and 10."
	if typeof(character["experience"]) != TYPE_INT or int(character["experience"]) < 0:
		return "Character experience must be a non-negative integer."
	if typeof(character["gold"]) != TYPE_INT or int(character["gold"]) < 0:
		return "Character gold must be a non-negative integer."
	if typeof(character["position"]) != TYPE_VECTOR3:
		return "Character position must be a Vector3."
	var position: Vector3 = character["position"]
	if not is_finite(position.x) or not is_finite(position.y) or not is_finite(position.z):
		return "Character position must contain only finite coordinates."
	for field: String in ["health", "resource"]:
		if not _is_finite_number(character[field]) or float(character[field]) < 0.0:
			return "Character %s must be a finite non-negative number." % field

	var inventory_error: String = _validate_inventory(character["inventory"])
	if not inventory_error.is_empty():
		return inventory_error
	var equipment_error: String = _validate_equipment(character["equipment"])
	if not equipment_error.is_empty():
		return equipment_error
	var quests_error: String = _validate_quests(character["quests"])
	if not quests_error.is_empty():
		return quests_error
	return ""


func _validate_inventory(inventory: Variant) -> String:
	if typeof(inventory) != TYPE_ARRAY:
		return "Character inventory must be an array."
	for entry: Variant in inventory:
		if typeof(entry) != TYPE_DICTIONARY:
			return "Character inventory entries must be objects."
		var slot: Dictionary = entry
		if not slot.has("item_id") or typeof(slot["item_id"]) != TYPE_STRING:
			return "Character inventory entries need an item ID."
		if str(slot["item_id"]).strip_edges().is_empty():
			return "Character inventory entries need a non-empty item ID."
		if not slot.has("quantity"):
			return "Character inventory entries need an integer quantity."
		var quantity_value: Variant = slot["quantity"]
		if typeof(quantity_value) == TYPE_FLOAT:
			# A JSONB number comes back as a float, so a whole number is fine.
			if not is_equal_approx(quantity_value, round(quantity_value)):
				return "Character inventory quantities must be whole numbers."
			quantity_value = int(quantity_value)
		if typeof(quantity_value) != TYPE_INT or int(quantity_value) < 1:
			return "Character inventory quantities must be positive."
	return ""


func _validate_equipment(equipment: Variant) -> String:
	if typeof(equipment) != TYPE_DICTIONARY:
		return "Character equipment must be an object."
	for slot_id: Variant in equipment:
		if typeof(slot_id) != TYPE_STRING or str(slot_id).strip_edges().is_empty():
			return "Character equipment slots need a non-empty slot ID."
		if typeof(equipment[slot_id]) != TYPE_STRING:
			return "Character equipment slots need an item ID."
	return ""


func _validate_quests(quests: Variant) -> String:
	if typeof(quests) != TYPE_DICTIONARY:
		return "Character quests must be an object."
	for quest_id: Variant in quests:
		if typeof(quest_id) != TYPE_STRING or str(quest_id).strip_edges().is_empty():
			return "Character quests need a non-empty quest ID."
		if typeof(quests[quest_id]) != TYPE_DICTIONARY:
			return "Character quest states must be objects."
		var quest_state: Dictionary = quests[quest_id]
		if not quest_state.has("status") or typeof(quest_state["status"]) != TYPE_STRING:
			return "Character quest states need a status."
		if not quest_state.has("progress") or typeof(quest_state["progress"]) != TYPE_INT:
			return "Character quest states need an integer progress."
		if int(quest_state["progress"]) < 0:
			return "Character quest progress must not be negative."
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
