extends SceneTree

const POSTGRES_EXTENSION = preload("res://native/postgres/postgres.gdextension")

const TEST_PORT: int = 55432


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
	var connect_result: Dictionary = connection.connect_to_db(
		"127.0.0.1",
		TEST_PORT,
		"postgres",
		"postgres",
		"",
	)
	if not _check_result(connect_result, "connect"):
		connection.close_connection()
		quit(1)
		return
	if not _check(connection.is_connected(), "connection should be open"):
		connection.close_connection()
		quit(1)
		return

	var create_result: Dictionary = connection.execute_query(
		"CREATE TEMP TABLE driver_spike_records (value TEXT NOT NULL)"
	)
	if not _check_result(create_result, "create temporary table"):
		connection.close_connection()
		quit(1)
		return

	var payload := "O'Reilly'; DROP TABLE driver_spike_records; --"
	var parameter_result: Dictionary = connection.execute_query(
		"SELECT $1::text AS payload, $2::integer AS number, "
		+ "CASE WHEN $3::boolean THEN 'yes' ELSE 'no' END AS flag, "
		+ "($4::text IS NULL)::text AS is_null",
		[payload, 42, true, null],
	)
	if not _check_result(parameter_result, "parameterized query"):
		connection.close_connection()
		quit(1)
		return

	var parameter_rows: Array = parameter_result["rows"]
	if not _check(parameter_rows.size() == 1, "parameterized query should return one row"):
		connection.close_connection()
		quit(1)
		return
	var parameter_row: Dictionary = parameter_rows[0]
	if not _check(parameter_row["payload"] == payload, "text parameter should round-trip"):
		connection.close_connection()
		quit(1)
		return
	if not _check(parameter_row["number"] == "42", "integer parameter should round-trip"):
		connection.close_connection()
		quit(1)
		return
	if not _check(parameter_row["flag"] == "yes", "boolean parameter should round-trip"):
		connection.close_connection()
		quit(1)
		return
	if not _check(parameter_row["is_null"] == "true", "NIL should become SQL NULL"):
		connection.close_connection()
		quit(1)
		return

	if not _check_result(connection.begin_transaction(), "begin rollback transaction"):
		connection.close_connection()
		quit(1)
		return
	var rollback_insert: Dictionary = connection.execute_query(
		"INSERT INTO driver_spike_records (value) VALUES ($1)",
		["rolled back"],
	)
	if not _check_result(rollback_insert, "insert before rollback"):
		connection.close_connection()
		quit(1)
		return
	if not _check_result(connection.rollback_transaction(), "rollback transaction"):
		connection.close_connection()
		quit(1)
		return

	var rollback_count: Dictionary = connection.execute_query(
		"SELECT COUNT(*)::text AS count FROM driver_spike_records"
	)
	if not _check_result(rollback_count, "verify rollback"):
		connection.close_connection()
		quit(1)
		return
	if not _check(
			rollback_count["rows"][0]["count"] == "0",
			"rolled-back row should not be visible"):
		connection.close_connection()
		quit(1)
		return

	if not _check_result(connection.begin_transaction(), "begin commit transaction"):
		connection.close_connection()
		quit(1)
		return
	var commit_insert: Dictionary = connection.execute_query(
		"INSERT INTO driver_spike_records (value) VALUES ($1)",
		["committed"],
	)
	if not _check_result(commit_insert, "insert before commit"):
		connection.close_connection()
		quit(1)
		return
	if not _check_result(connection.commit_transaction(), "commit transaction"):
		connection.close_connection()
		quit(1)
		return

	var committed_count: Dictionary = connection.execute_query(
		"SELECT COUNT(*)::text AS count FROM driver_spike_records"
	)
	if not _check_result(committed_count, "verify commit"):
		connection.close_connection()
		quit(1)
		return
	if not _check(
			committed_count["rows"][0]["count"] == "1",
			"committed row should be visible"):
		connection.close_connection()
		quit(1)
		return

	var invalid_query: Dictionary = connection.execute_query("SELEC broken")
	if not _check(
			not bool(invalid_query.get("ok", true))
					and not str(invalid_query.get("error", "")).is_empty(),
			"invalid SQL should return an explicit error"):
		connection.close_connection()
		quit(1)
		return

	var recovery_query: Dictionary = connection.execute_query("SELECT 1::integer AS alive")
	if not _check_result(recovery_query, "query after SQL error"):
		connection.close_connection()
		quit(1)
		return
	if not _check(
			recovery_query["rows"][0]["alive"] == "1",
			"connection should remain usable after a SQL error"):
		connection.close_connection()
		quit(1)
		return

	connection.close_connection()
	if not _check(not connection.is_connected(), "connection should be closed"):
		quit(1)
		return
	var closed_query: Dictionary = connection.execute_query("SELECT 1")
	if not _check(
			not bool(closed_query.get("ok", true)),
			"queries after close should fail explicitly"):
		quit(1)
		return

	print("POSTGRES_DRIVER_SPIKE_OK")
	quit(0)


func _check_result(result: Dictionary, label: String) -> bool:
	return _check(
		bool(result.get("ok", false)),
		"%s failed: %s" % [label, str(result.get("error", "missing error detail"))],
	)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition
