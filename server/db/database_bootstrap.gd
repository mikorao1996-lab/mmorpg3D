extends RefCounted

const POSTGRES_EXTENSION = preload("res://native/postgres/postgres.gdextension")
const DatabaseMigrationsType: GDScript = preload("res://server/db/database_migrations.gd")

const REQUIRED_ENVIRONMENT: Array[String] = [
	"MMORPG3D_DB_HOST",
	"MMORPG3D_DB_PORT",
	"MMORPG3D_DB_NAME",
	"MMORPG3D_DB_USER",
]


func connect_and_migrate() -> Dictionary:
	if POSTGRES_EXTENSION == null or not ClassDB.class_exists("PostgresConnection"):
		return _failure("PostgreSQL GDExtension is not loaded.")

	var configuration: Dictionary = _read_configuration()
	if not bool(configuration.get("ok", false)):
		return configuration

	var connection: RefCounted = ClassDB.instantiate("PostgresConnection") as RefCounted
	if connection == null:
		return _failure("Could not instantiate PostgresConnection.")

	var connection_result: Variant = connection.call(
		"connect_to_db",
		configuration["host"],
		configuration["port"],
		configuration["database"],
		configuration["user"],
		configuration["password"],
	)
	if typeof(connection_result) != TYPE_DICTIONARY:
		connection.call("close_connection")
		return _failure("PostgreSQL driver returned a malformed connection result.")
	if not bool(connection_result.get("ok", false)):
		connection.call("close_connection")
		return _failure(
			"PostgreSQL connection failed: %s"
			% str(connection_result.get("error", "Unknown database error.")),
		)

	var migrations: RefCounted = DatabaseMigrationsType.new()
	var migration_result: Variant = migrations.call("apply_all", connection)
	if typeof(migration_result) != TYPE_DICTIONARY:
		connection.call("close_connection")
		return _failure("Migration runner returned a malformed result.")
	if not bool(migration_result.get("ok", false)):
		connection.call("close_connection")
		return _failure(
			"PostgreSQL migration failed: %s"
			% str(migration_result.get("error", "Unknown migration error.")),
		)

	return {
		"ok": true,
		"error": "",
		"connection": connection,
	}


func _read_configuration() -> Dictionary:
	var configuration: Dictionary = {}
	for variable_name: String in REQUIRED_ENVIRONMENT:
		var value: String = OS.get_environment(variable_name).strip_edges()
		if value.is_empty():
			return _failure("Required environment variable %s is not set." % variable_name)
		configuration[variable_name] = value

	var port_text: String = configuration["MMORPG3D_DB_PORT"]
	if not port_text.is_valid_int():
		return _failure("MMORPG3D_DB_PORT must be an integer between 1 and 65535.")
	var port: int = int(port_text)
	if port < 1 or port > 65535:
		return _failure("MMORPG3D_DB_PORT must be an integer between 1 and 65535.")

	return {
		"ok": true,
		"host": configuration["MMORPG3D_DB_HOST"],
		"port": port,
		"database": configuration["MMORPG3D_DB_NAME"],
		"user": configuration["MMORPG3D_DB_USER"],
		"password": OS.get_environment("MMORPG3D_DB_PASSWORD"),
	}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
