extends RefCounted

const MIGRATIONS: Array[Dictionary] = [
	{
		"version": 1,
		"file": "res://server/db/migrations/0001_create_characters.sql",
	},
	{
		"version": 2,
		"file": "res://server/db/migrations/0002_character_progress.sql",
	},
]


func apply_all(connection: RefCounted) -> Dictionary:
	var create_history_result: Dictionary = _execute(
		connection,
		"CREATE TABLE IF NOT EXISTS schema_migrations ("
		+ "version INTEGER PRIMARY KEY, "
		+ "applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP"
		+ ")",
	)
	if not _is_ok(create_history_result):
		return _contextual_error("Create migration history", create_history_result)

	var history_result: Dictionary = _execute(
		connection,
		"SELECT version::text AS version FROM schema_migrations",
	)
	if not _is_ok(history_result):
		return _contextual_error("Read migration history", history_result)
	if typeof(history_result.get("rows")) != TYPE_ARRAY:
		return _failure("PostgreSQL returned an invalid migration history result.")

	var applied_versions: Dictionary = {}
	var history_rows: Array = history_result["rows"]
	for row_value: Variant in history_rows:
		if typeof(row_value) != TYPE_DICTIONARY:
			return _failure("PostgreSQL returned an invalid migration history row.")
		var row: Dictionary = row_value
		var version_text: String = str(row.get("version", ""))
		if not version_text.is_valid_int():
			return _failure("Migration history contains an invalid version.")
		applied_versions[int(version_text)] = true

	for migration: Dictionary in MIGRATIONS:
		var version: int = int(migration["version"])
		if applied_versions.has(version):
			continue

		var migration_file_path: String = str(migration["file"])
		var migration_file: FileAccess = FileAccess.open(
			migration_file_path,
			FileAccess.READ,
		)
		if migration_file == null:
			return _failure(
				"Could not open migration %s (error %d)."
				% [migration_file_path, FileAccess.get_open_error()],
			)
		var migration_sql: String = migration_file.get_as_text()
		migration_file.close()
		if migration_sql.strip_edges().is_empty():
			return _failure("Migration %s is empty." % migration_file_path)

		var begin_result: Dictionary = _call(connection, "begin_transaction")
		if not _is_ok(begin_result):
			return _contextual_error("Begin migration transaction", begin_result)

		var migration_result: Dictionary = _execute(connection, migration_sql)
		if not _is_ok(migration_result):
			return _rollback_failure(
				connection,
				"Apply migration %d: %s"
				% [version, str(migration_result.get("error", "Unknown database error."))],
			)

		var record_result: Dictionary = _execute(
			connection,
			"INSERT INTO schema_migrations (version) VALUES ($1)",
			[version],
		)
		if not _is_ok(record_result):
			return _rollback_failure(
				connection,
				"Record migration %d: %s"
				% [version, str(record_result.get("error", "Unknown database error."))],
			)

		var commit_result: Dictionary = _call(connection, "commit_transaction")
		if not _is_ok(commit_result):
			return _rollback_failure(
				connection,
				"Commit migration %d: %s"
				% [version, str(commit_result.get("error", "Unknown database error."))],
			)

	return {"ok": true, "error": ""}


func _execute(
	connection: RefCounted,
	query: String,
	parameters: Array = [],
) -> Dictionary:
	var result: Variant = connection.call("execute_query", query, parameters)
	if typeof(result) != TYPE_DICTIONARY:
		return _failure("PostgreSQL driver returned a malformed query result.")
	return result


func _call(connection: RefCounted, method_name: String) -> Dictionary:
	var result: Variant = connection.call(method_name)
	if typeof(result) != TYPE_DICTIONARY:
		return _failure("PostgreSQL driver returned a malformed transaction result.")
	return result


func _rollback_failure(connection: RefCounted, message: String) -> Dictionary:
	var rollback_result: Dictionary = _call(connection, "rollback_transaction")
	if not _is_ok(rollback_result):
		return _failure(
			"%s Rollback failed: %s"
			% [message, str(rollback_result.get("error", "Unknown database error."))],
		)
	return _failure(message)


func _contextual_error(context: String, result: Dictionary) -> Dictionary:
	return _failure(
		"%s: %s"
		% [context, str(result.get("error", "Unknown database error."))],
	)


func _is_ok(result: Dictionary) -> bool:
	return bool(result.get("ok", false))


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
