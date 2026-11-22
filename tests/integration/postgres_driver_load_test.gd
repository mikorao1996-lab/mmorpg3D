extends SceneTree

const POSTGRES_EXTENSION = preload("res://native/postgres/postgres.gdextension")


func _initialize() -> void:
	if POSTGRES_EXTENSION == null or not ClassDB.class_exists("PostgresConnection"):
		push_error("PostgreSQL GDExtension failed to register PostgresConnection")
		quit(1)
		return

	var connection: RefCounted = ClassDB.instantiate("PostgresConnection") as RefCounted
	if connection == null:
		push_error("PostgresConnection could not be instantiated")
		quit(1)
		return

	var result: Dictionary = connection.connect_to_db(
		"127.0.0.1",
		65535,
		"postgres",
		"postgres",
		"",
	)
	if bool(result.get("ok", false)):
		connection.close_connection()
		push_error("Unexpected PostgreSQL service on reserved port 65535")
		quit(1)
		return
	if str(result.get("error", "")).is_empty():
		push_error("Connection failures must include an error message")
		quit(1)
		return
	if connection.is_db_connected():
		connection.close_connection()
		push_error("Failed connection must not be reported as connected")
		quit(1)
		return

	connection.close_connection()
	print("POSTGRES_DRIVER_LOAD_OK")
	quit(0)
