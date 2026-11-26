extends SceneTree

const POSTGRES_EXTENSION = preload("res://native/postgres/postgres.gdextension")
const DatabaseBootstrapType: GDScript = preload("res://server/db/database_bootstrap.gd")
const DatabaseMigrationsType: GDScript = preload("res://server/db/database_migrations.gd")
const CharacterRepositoryType: GDScript = preload("res://server/db/character_repository.gd")

const TEST_PORT: int = 55432
const TEST_CHARACTER_ID: String = "7e3fc52e-15b7-4a56-a819-df5d119b2904"


func _initialize() -> void:
	if POSTGRES_EXTENSION == null:
		push_error("PostgreSQL GDExtension failed to load")
		quit(1)
		return
	call_deferred("_run")


func _run() -> void:
	var connection: RefCounted = ClassDB.instantiate("PostgresConnection") as RefCounted
	if connection == null:
		push_error("PostgresConnection class was not registered")
		quit(1)
		return

	var repository: RefCounted = CharacterRepositoryType.new(connection)
	var disconnected_result: Dictionary = repository.save_character(_test_character())
	if not _check_failure(disconnected_result, "save without database connection"):
		connection.close_connection()
		quit(1)
		return
	var invalid_character: Dictionary = _test_character()
	invalid_character["level"] = 11
	if not _check_failure(
			repository.save_character(invalid_character),
			"reject out-of-range character level"):
		connection.close_connection()
		quit(1)
		return

	for variable_name: String in [
		"MMORPG3D_DB_HOST",
		"MMORPG3D_DB_PORT",
		"MMORPG3D_DB_NAME",
		"MMORPG3D_DB_USER",
	]:
		OS.set_environment(variable_name, "")
	var bootstrap: RefCounted = DatabaseBootstrapType.new()
	if not _check_failure(
			bootstrap.connect_and_migrate(),
			"reject missing database configuration"):
		connection.close_connection()
		quit(1)
		return

	OS.set_environment("MMORPG3D_DB_HOST", "127.0.0.1")
	OS.set_environment("MMORPG3D_DB_PORT", str(TEST_PORT))
	OS.set_environment("MMORPG3D_DB_NAME", "postgres")
	OS.set_environment("MMORPG3D_DB_USER", "postgres")
	OS.set_environment("MMORPG3D_DB_PASSWORD", "")
	var database_result: Dictionary = bootstrap.connect_and_migrate()
	if not _check_result(database_result, "connect and apply migrations"):
		connection.close_connection()
		quit(1)
		return

	var database_connection: RefCounted = database_result["connection"]
	connection.close_connection()
	var migrations: RefCounted = DatabaseMigrationsType.new()
	if not _check_result(migrations.apply_all(database_connection), "apply migrations"):
		database_connection.call("close_connection")
		quit(1)
		return
	if not _check_result(migrations.apply_all(database_connection), "reapply migrations"):
		database_connection.call("close_connection")
		quit(1)
		return

	var repository_with_connection: RefCounted = CharacterRepositoryType.new(database_connection)
	var cleanup_result: Dictionary = database_connection.call(
		"execute_query",
		"DELETE FROM characters WHERE character_id = $1::uuid",
		[TEST_CHARACTER_ID],
	)
	if not _check_result(cleanup_result, "clear prior test character"):
		database_connection.call("close_connection")
		quit(1)
		return

	var original_character: Dictionary = _test_character()
	if not _check_result(
			repository_with_connection.create_character(original_character),
			"create character"):
		database_connection.call("close_connection")
		quit(1)
		return

	var duplicate_result: Dictionary = repository_with_connection.create_character(
		original_character,
	)
	if not _check_failure(duplicate_result, "reject duplicate character"):
		database_connection.call("close_connection")
		quit(1)
		return

	var loaded_result: Dictionary = repository_with_connection.load_character(TEST_CHARACTER_ID)
	if not _check_loaded_character(loaded_result, original_character):
		database_connection.call("close_connection")
		quit(1)
		return

	var updated_character: Dictionary = original_character.duplicate(true)
	updated_character["character_name"] = "Updated O'Reilly"
	updated_character["character_token_hash"] = (
		"fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
	)
	updated_character["experience"] = 1250
	updated_character["gold"] = 275
	updated_character["position"] = Vector3(3.25, 0.0, -8.5)
	updated_character["health"] = 73.5
	updated_character["resource"] = 41.0
	updated_character["inventory"] = [
		{"item_id": "minor_potion", "quantity": 5},
		{"item_id": "slime_gel", "quantity": 1},
	]
	updated_character["equipment"] = {"weapon": "iron_sword", "chest": "leather_vest"}
	updated_character["quests"] = {
		"slime_problem": {"status": "turned_in", "progress": 3},
	}
	if not _check_result(
			repository_with_connection.save_character(updated_character),
			"save character"):
		database_connection.call("close_connection")
		quit(1)
		return

	var updated_result: Dictionary = repository_with_connection.load_character(TEST_CHARACTER_ID)
	if not _check_loaded_character(updated_result, updated_character):
		database_connection.call("close_connection")
		quit(1)
		return

	var missing_result: Dictionary = repository_with_connection.load_character(
		"aa566c4e-e92e-4881-8c34-5ed7d8fbc111",
	)
	if not _check(
			bool(missing_result.get("ok", false))
					and not bool(missing_result.get("found", true)),
			"missing character should be reported as not found"):
		database_connection.call("close_connection")
		quit(1)
		return

	var final_cleanup_result: Dictionary = database_connection.call(
		"execute_query",
		"DELETE FROM characters WHERE character_id = $1::uuid",
		[TEST_CHARACTER_ID],
	)
	if not _check_result(final_cleanup_result, "remove test character"):
		database_connection.call("close_connection")
		quit(1)
		return

	database_connection.call("close_connection")
	print("POSTGRES_CHARACTER_REPOSITORY_OK")
	quit(0)


func _test_character() -> Dictionary:
	return {
		"character_id": TEST_CHARACTER_ID,
		"character_name": "O'Reilly",
		"character_token_hash": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		"class_id": "warrior",
		"level": 1,
		"experience": 0,
		"gold": 100,
		"zone_id": "starter",
		"position": Vector3(1.25, 0.0, -4.5),
		"health": 100.0,
		"resource": 100.0,
		"inventory": [{"item_id": "minor_potion", "quantity": 2}],
		"equipment": {"weapon": "iron_sword"},
		"quests": {"slime_problem": {"status": "active", "progress": 1}},
	}


func _check_loaded_character(result: Dictionary, expected: Dictionary) -> bool:
	if not bool(result.get("ok", false)) or not bool(result.get("found", false)):
		return _check(false, "load character failed: %s" % str(result.get("error", "not found")))
	var actual_value: Variant = result.get("character")
	if typeof(actual_value) != TYPE_DICTIONARY:
		return _check(false, "loaded character result is malformed")
	var actual: Dictionary = actual_value
	var expected_position: Vector3 = expected["position"]
	var actual_position: Vector3 = actual["position"]
	return _check(
		actual["character_id"] == expected["character_id"]
				and actual["character_name"] == expected["character_name"]
				and actual["character_token_hash"] == expected["character_token_hash"]
				and actual["class_id"] == expected["class_id"]
				and actual["level"] == expected["level"]
				and actual["experience"] == expected["experience"]
				and actual["gold"] == expected["gold"]
				and actual["zone_id"] == expected["zone_id"]
				and actual_position.is_equal_approx(expected_position)
				and is_equal_approx(float(actual["health"]), float(expected["health"]))
				and is_equal_approx(float(actual["resource"]), float(expected["resource"]))
				and _same_json(actual["inventory"], expected["inventory"])
				and _same_json(actual["equipment"], expected["equipment"])
				and _same_json(actual["quests"], expected["quests"]),
		"loaded character does not match expected state",
	)


## Compares two JSON documents by their content.
##
## PostgreSQL reorders the keys of a JSONB document, so the comparison cannot
## rely on the order of the keys.
func _same_json(actual: Variant, expected: Variant) -> bool:
	var actual_is_number: bool = typeof(actual) == TYPE_INT or typeof(actual) == TYPE_FLOAT
	var expected_is_number: bool = typeof(expected) == TYPE_INT or typeof(expected) == TYPE_FLOAT
	if actual_is_number and expected_is_number:
		return is_equal_approx(float(actual), float(expected))
	if typeof(actual) != typeof(expected):
		return false
	if typeof(actual) == TYPE_DICTIONARY:
		var actual_keys: Array = (actual as Dictionary).keys()
		var expected_keys: Array = (expected as Dictionary).keys()
		actual_keys.sort()
		expected_keys.sort()
		if actual_keys != expected_keys:
			return false
		for key: Variant in actual_keys:
			if not _same_json((actual as Dictionary)[key], (expected as Dictionary)[key]):
				return false
		return true
	if typeof(actual) == TYPE_ARRAY:
		var actual_array: Array = actual
		var expected_array: Array = expected
		if actual_array.size() != expected_array.size():
			return false
		for index: int in range(actual_array.size()):
			if not _same_json(actual_array[index], expected_array[index]):
				return false
		return true
	return actual == expected


func _check_result(result: Dictionary, label: String) -> bool:
	return _check(
		bool(result.get("ok", false)),
		"%s failed: %s" % [label, str(result.get("error", "missing error detail"))],
	)


func _check_failure(result: Dictionary, label: String) -> bool:
	return _check(
		not bool(result.get("ok", true))
				and not str(result.get("error", "")).is_empty(),
		"%s should return an explicit failure" % label,
	)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition
