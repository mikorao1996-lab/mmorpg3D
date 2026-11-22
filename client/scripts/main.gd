extends Node3D

const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const MovementSimulationType: GDScript = preload("res://shared/sim/movement_simulation.gd")
const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")

@onready var status_label: Label = $StatusCanvas/StatusPanel/StatusLabel
@onready var hint_label: Label = $StatusCanvas/HintLabel
@onready var camera: Camera3D = $Camera3D

var _simulation_config: Dictionary = {}
var _client_net: ClientNet
var _local_player_id: int = 0
var _predicted_position: Vector3 = Vector3.ZERO
var _has_authoritative_position: bool = false
var _input_send_accumulator: float = 0.0
var _snapshot_buffer: Array[Dictionary] = []
var _player_views: Dictionary = {}


func _ready() -> void:
	_simulation_config = SimulationConfigType.load_config()
	if _simulation_config.is_empty():
		status_label.text = tr("simulation_config_error")
		return

	hint_label.text = tr("controls_hint")
	status_label.text = tr("connection_connecting")
	_client_net = ClientNet.new()
	add_child(_client_net)
	_client_net.hello_accepted.connect(_on_hello_accepted)
	_client_net.hello_rejected.connect(_on_hello_rejected)
	_client_net.disconnected.connect(_on_disconnected)
	_client_net.world_snapshot.connect(_on_world_snapshot)

	var error: Error = _client_net.connect_to_server("127.0.0.1")
	if error != OK:
		status_label.text = tr("connection_failed")
		push_error("Could not start ENet client: %s" % error)


func _physics_process(delta: float) -> void:
	if _client_net == null or not _client_net.is_connected or _local_player_id == 0:
		return

	var input_direction: Vector2 = Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)),
	)
	var max_input_magnitude: float = float(_simulation_config["max_input_magnitude"])
	if input_direction.length() > max_input_magnitude:
		input_direction = input_direction.normalized() * max_input_magnitude

	_predicted_position = MovementSimulationType.advance(
		_predicted_position,
		input_direction,
		delta,
		float(_simulation_config["movement_speed"]),
		max_input_magnitude,
		float(_simulation_config["world_half_extent"]),
	)
	var local_view: Node3D = _player_views.get(_local_player_id)
	if local_view != null:
		local_view.position = _predicted_position

	_input_send_accumulator += delta
	if _input_send_accumulator >= float(_simulation_config["input_send_interval_seconds"]):
		_input_send_accumulator = 0.0
		var send_error: Error = _client_net.send_movement_intent(input_direction)
		if send_error != OK:
			push_warning("Could not send movement intent: %s" % send_error)


func _process(_delta: float) -> void:
	_render_snapshot_buffer()
	var local_view: Node3D = _player_views.get(_local_player_id)
	if local_view != null:
		camera.global_position = local_view.global_position + Vector3(
			0.0,
			float(_simulation_config["camera_height"]),
			float(_simulation_config["camera_distance"]),
		)
		camera.look_at(
			local_view.global_position
			+ Vector3(0.0, float(_simulation_config["camera_look_height"]), 0.0),
			Vector3.UP,
		)


func _on_hello_accepted(protocol: int, player_id: int) -> void:
	if protocol != ProtocolConstantsType.PROTOCOL_VERSION:
		_on_hello_rejected("protocol_mismatch")
		return
	_local_player_id = player_id
	_ensure_player_view(player_id)
	_set_player_color(player_id, Color(0.95, 0.72, 0.25))
	status_label.text = tr("connection_connected") % player_id


func _on_hello_rejected(reason: String) -> void:
	status_label.text = tr("connection_rejected") % reason


func _on_disconnected() -> void:
	status_label.text = tr("connection_disconnected")


func _on_world_snapshot(snapshot: Dictionary) -> void:
	var player_entries: Variant = snapshot.get("players", null)
	if not player_entries is Array:
		push_warning("Rejected world snapshot without player list")
		return

	var positions: Dictionary = {}
	for entry: Variant in player_entries:
		if not entry is Array or entry.size() != 2:
			push_warning("Rejected malformed player entry in world snapshot")
			return
		var player_id: Variant = entry[0]
		var position: Variant = entry[1]
		if player_id is not int or position is not Vector3:
			push_warning("Rejected malformed player state in world snapshot")
			return
		positions[player_id] = position
		_ensure_player_view(player_id)
		if player_id == _local_player_id and not _has_authoritative_position:
			_predicted_position = position
			_player_views[player_id].position = position
			_has_authoritative_position = true

	var snapshot_record: Dictionary = {
		"received_at_ms": Time.get_ticks_msec(),
		"positions": positions,
	}
	_snapshot_buffer.append(snapshot_record)
	var capacity: int = int(_simulation_config["snapshot_buffer_capacity"])
	while _snapshot_buffer.size() > capacity:
		_snapshot_buffer.pop_front()

	var existing_player_ids: Array = _player_views.keys()
	for player_id: int in existing_player_ids:
		if not positions.has(player_id):
			var player_view: Node3D = _player_views[player_id]
			player_view.queue_free()
			_player_views.erase(player_id)


func _render_snapshot_buffer() -> void:
	if _snapshot_buffer.is_empty():
		return

	var render_time_ms: float = (
		float(Time.get_ticks_msec())
		- float(_simulation_config["interpolation_buffer_seconds"]) * 1000.0
	)
	var older_snapshot: Dictionary = _snapshot_buffer[0]
	var newer_snapshot: Dictionary = _snapshot_buffer[_snapshot_buffer.size() - 1]
	for index: int in range(_snapshot_buffer.size() - 1):
		var candidate_older: Dictionary = _snapshot_buffer[index]
		var candidate_newer: Dictionary = _snapshot_buffer[index + 1]
		if (
			float(candidate_older["received_at_ms"]) <= render_time_ms
			and float(candidate_newer["received_at_ms"]) >= render_time_ms
		):
			older_snapshot = candidate_older
			newer_snapshot = candidate_newer
			break

	var older_time_ms: float = float(older_snapshot["received_at_ms"])
	var newer_time_ms: float = float(newer_snapshot["received_at_ms"])
	var interpolation_alpha: float = 1.0
	if newer_time_ms > older_time_ms:
		interpolation_alpha = clampf(
			(render_time_ms - older_time_ms) / (newer_time_ms - older_time_ms),
			0.0,
			1.0,
		)
	var older_positions: Dictionary = older_snapshot["positions"]
	var newer_positions: Dictionary = newer_snapshot["positions"]
	var latest_positions: Dictionary = _snapshot_buffer[_snapshot_buffer.size() - 1]["positions"]

	for player_id: int in _player_views:
		var player_view: Node3D = _player_views[player_id]
		if not newer_positions.has(player_id):
			continue
		var newer_position: Vector3 = newer_positions[player_id]
		if player_id == _local_player_id:
			var correction_factor: float = float(_simulation_config["local_reconciliation_factor"])
			_predicted_position = _predicted_position.lerp(latest_positions[player_id], correction_factor)
			player_view.position = _predicted_position
			continue
		var older_position: Vector3 = older_positions.get(player_id, newer_position)
		player_view.position = older_position.lerp(newer_position, interpolation_alpha)


func _ensure_player_view(player_id: int) -> void:
	if _player_views.has(player_id):
		return

	var player_view: Node3D = Node3D.new()
	player_view.name = "Player_%d" % player_id
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = float(_simulation_config["player_visual_radius"])
	capsule.height = float(_simulation_config["player_visual_height"])
	mesh_instance.mesh = capsule
	mesh_instance.material_override = StandardMaterial3D.new()
	mesh_instance.position.y = capsule.height / 2.0
	player_view.add_child(mesh_instance)
	add_child(player_view)
	_player_views[player_id] = player_view
	var color: Color = Color(0.25, 0.7, 0.95)
	if player_id == _local_player_id:
		color = Color(0.95, 0.72, 0.25)
	_set_player_color(player_id, color)


func _set_player_color(player_id: int, color: Color) -> void:
	var player_view: Node3D = _player_views.get(player_id)
	if player_view == null:
		return
	var mesh_instance: MeshInstance3D = player_view.get_child(0)
	var material: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
	material.albedo_color = color
