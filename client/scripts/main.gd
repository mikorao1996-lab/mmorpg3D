extends Node3D

const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const MovementSimulationType: GDScript = preload("res://shared/sim/movement_simulation.gd")
const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")
const PlayerBodyAdapterType: GDScript = preload("res://client/scripts/player_body_adapter.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

@onready var status_label: Label = $StatusCanvas/StatusPanel/StatusLabel
@onready var hint_label: Label = $StatusCanvas/HintLabel
@onready var camera: Camera3D = $Camera3D

var _simulation_config: Dictionary = {}
var _game_data_registry: Dictionary = {}
var _client_net: ClientNet
var _local_player_id: int = 0
var _predicted_position: Vector3 = Vector3.ZERO
var _has_authoritative_position: bool = false
var _input_send_accumulator: float = 0.0
var _snapshot_buffer: Array[Dictionary] = []
var _player_views: Dictionary = {}
var _player_health_states: Dictionary = {}
var _mob_states: Dictionary = {}
var _mob_views: Dictionary = {}
var _drop_states: Dictionary = {}
var _drop_views: Dictionary = {}
var _inventory_state: Array[Dictionary] = []
var _slash_key_down: bool = false
var _heavy_strike_key_down: bool = false
var _guard_break_key_down: bool = false
var _whirlwind_key_down: bool = false
var _second_wind_key_down: bool = false
var _loot_key_down: bool = false
var _combat_message_time_remaining: float = 0.0


func _ready() -> void:
	_simulation_config = SimulationConfigType.load_config()
	if _simulation_config.is_empty():
		status_label.text = tr("simulation_config_error")
		return
	_game_data_registry = GameDataRegistryType.load_all()
	if _game_data_registry.is_empty():
		status_label.text = tr("game_data_error")
		return

	hint_label.text = tr("controls_hint")
	status_label.text = tr("connection_connecting")
	_client_net = ClientNet.new()
	add_child(_client_net)
	_client_net.hello_accepted.connect(_on_hello_accepted)
	_client_net.hello_rejected.connect(_on_hello_rejected)
	_client_net.disconnected.connect(_on_disconnected)
	_client_net.world_snapshot.connect(_on_world_snapshot)
	_client_net.ability_cast_completed.connect(_on_ability_cast_completed)
	_client_net.loot_pickup_completed.connect(_on_loot_pickup_completed)

	var error: Error = _client_net.connect_to_server("127.0.0.1")
	if error != OK:
		status_label.text = tr("connection_failed")
		push_error("Could not start ENet client: %s" % error)


func _physics_process(delta: float) -> void:
	if _client_net == null or not _client_net.is_connected or _local_player_id == 0:
		return

	var local_health_state: Dictionary = _player_health_states.get(_local_player_id, {})
	var player_is_defeated: bool = (
		not local_health_state.is_empty() and float(local_health_state["health"]) <= 0.0
	)
	var input_direction: Vector2 = Vector2.ZERO
	if not player_is_defeated:
		input_direction = Vector2(
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
	var local_view: PlayerBodyAdapter = _player_views.get(_local_player_id)
	if local_view != null:
		local_view.move_to_simulated_position(_predicted_position, delta)
		_predicted_position = local_view.global_position

	_input_send_accumulator += delta
	if _input_send_accumulator >= float(_simulation_config["input_send_interval_seconds"]):
		_input_send_accumulator = 0.0
		var send_error: Error = _client_net.send_movement_intent(input_direction)
		if send_error != OK:
			push_warning("Could not send movement intent: %s" % send_error)

	var slash_key_pressed: bool = Input.is_key_pressed(KEY_SPACE)
	if not player_is_defeated and slash_key_pressed and not _slash_key_down:
		_request_attack("starter_slash")
	_slash_key_down = slash_key_pressed
	var heavy_strike_key_pressed: bool = Input.is_key_pressed(KEY_E)
	if not player_is_defeated and heavy_strike_key_pressed and not _heavy_strike_key_down:
		_request_attack("heavy_strike")
	_heavy_strike_key_down = heavy_strike_key_pressed
	var guard_break_key_pressed: bool = Input.is_key_pressed(KEY_Q)
	if not player_is_defeated and guard_break_key_pressed and not _guard_break_key_down:
		_request_attack("guard_break")
	_guard_break_key_down = guard_break_key_pressed
	var whirlwind_key_pressed: bool = Input.is_key_pressed(KEY_R)
	if not player_is_defeated and whirlwind_key_pressed and not _whirlwind_key_down:
		_request_attack("whirlwind")
	_whirlwind_key_down = whirlwind_key_pressed
	var second_wind_key_pressed: bool = Input.is_key_pressed(KEY_T)
	if not player_is_defeated and second_wind_key_pressed and not _second_wind_key_down:
		_request_attack("second_wind")
	_second_wind_key_down = second_wind_key_pressed
	var loot_key_pressed: bool = Input.is_key_pressed(KEY_F)
	if not player_is_defeated and loot_key_pressed and not _loot_key_down:
		_request_nearest_loot()
	_loot_key_down = loot_key_pressed


func _process(_delta: float) -> void:
	_render_snapshot_buffer()
	if _combat_message_time_remaining > 0.0:
		_combat_message_time_remaining = maxf(
			0.0,
			_combat_message_time_remaining - _delta,
		)
		if _combat_message_time_remaining == 0.0:
			_update_combat_status()
	var local_view: PlayerBodyAdapter = _player_views.get(_local_player_id)
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


func _on_ability_cast_completed(
	accepted: bool,
	reason: String,
	mob_id: String,
	health: float,
	max_health: float,
) -> void:
	var mob_definition: Dictionary = _game_data_registry["mobs"].get(mob_id, {})
	var mob_name: String = tr(mob_definition.get("name_key", "combat_unknown_target"))
	if accepted:
		status_label.text = tr("combat_cast_success") % [
			mob_name,
			int(health),
			int(max_health),
		]
	else:
		status_label.text = tr("combat_cast_failed") % tr("combat_reason_" + reason)
	_combat_message_time_remaining = 2.0


func _on_loot_pickup_completed(accepted: bool, reason: String, item_id: String) -> void:
	if accepted:
		var item_definition: Dictionary = _game_data_registry["items"].get(item_id, {})
		if item_definition.is_empty():
			push_error("Loot pickup result referenced unknown item %s" % item_id)
			return
		status_label.text = tr("loot_pickup_success") % tr(item_definition["name_key"])
	else:
		status_label.text = tr("loot_pickup_failed") % tr("loot_reason_" + reason)
	_combat_message_time_remaining = 2.0


func _on_world_snapshot(snapshot: Dictionary) -> void:
	var player_entries: Variant = snapshot.get("players", null)
	if not player_entries is Array:
		push_warning("Rejected world snapshot without player list")
		return
	var mob_entries: Variant = snapshot.get("mobs", null)
	if not mob_entries is Array:
		push_warning("Rejected world snapshot without mob list")
		return
	var drop_entries: Variant = snapshot.get("drops", null)
	if not drop_entries is Array:
		push_warning("Rejected world snapshot without loot drops")
		return
	var inventory_entries: Variant = snapshot.get("inventory", null)
	if (
		not inventory_entries is Array
		or inventory_entries.size() > int(_simulation_config["inventory_slot_count"])
	):
		push_warning("Rejected malformed inventory in world snapshot")
		return

	var positions: Dictionary = {}
	var player_health_states: Dictionary = {}
	for entry: Variant in player_entries:
		if not entry is Array or entry.size() != 10:
			push_warning("Rejected malformed player entry in world snapshot")
			return
		var player_id: Variant = entry[0]
		var position: Variant = entry[1]
		var health: Variant = entry[2]
		var max_health: Variant = entry[3]
		var level: Variant = entry[4]
		var experience: Variant = entry[5]
		var resource: Variant = entry[6]
		var max_resource: Variant = entry[7]
		var attack_multiplier: Variant = entry[8]
		var defense: Variant = entry[9]
		if (
			player_id is not int
			or position is not Vector3
			or not _is_finite_number(health)
			or not _is_finite_number(max_health)
			or level is not int
			or experience is not int
			or experience < 0
			or not _is_finite_number(resource)
			or not _is_finite_number(max_resource)
			or not _is_finite_number(attack_multiplier)
			or not _is_finite_number(defense)
			or float(max_health) <= 0.0
			or level < 1
			or level > _game_data_registry["progression"].size()
			or float(max_resource) <= 0.0
			or float(attack_multiplier) <= 0.0
			or float(defense) < 0.0
			or float(health) < 0.0
			or float(health) > float(max_health)
			or float(resource) < 0.0
			or float(resource) > float(max_resource)
		):
			push_warning("Rejected malformed player state in world snapshot")
			return
		positions[player_id] = position
		player_health_states[player_id] = {
			"health": float(health),
			"max_health": float(max_health),
			"level": level,
			"experience": int(experience),
			"resource": float(resource),
			"max_resource": float(max_resource),
			"attack_multiplier": float(attack_multiplier),
			"defense": float(defense),
		}
		_ensure_player_view(player_id)
		if player_id == _local_player_id and not _has_authoritative_position:
			_predicted_position = position
			var local_player_view: PlayerBodyAdapter = _player_views[player_id]
			local_player_view.set_simulated_position(position)
			_has_authoritative_position = true

	var new_mob_states: Dictionary = {}
	for entry: Variant in mob_entries:
		if not entry is Array or entry.size() != 4:
			push_warning("Rejected malformed mob entry in world snapshot")
			return
		var mob_id: Variant = entry[0]
		var position: Variant = entry[1]
		var health: Variant = entry[2]
		var max_health: Variant = entry[3]
		if (
			mob_id is not String
			or position is not Vector3
			or not _is_finite_number(health)
			or not _is_finite_number(max_health)
			or float(max_health) <= 0.0
			or float(health) < 0.0
			or float(health) > float(max_health)
		):
			push_warning("Rejected malformed mob state in world snapshot")
			return
		if not _game_data_registry["mobs"].has(mob_id):
			push_warning("Rejected snapshot for unknown mob %s" % mob_id)
			return
		new_mob_states[mob_id] = {
			"position": position,
			"health": float(health),
			"max_health": float(max_health),
		}
		_ensure_mob_view(mob_id)

	var new_drop_states: Dictionary = {}
	for entry: Variant in drop_entries:
		if not entry is Array or entry.size() != 3:
			push_warning("Rejected malformed loot drop in world snapshot")
			return
		var drop_id: Variant = entry[0]
		var item_id: Variant = entry[1]
		var drop_position: Variant = entry[2]
		if (
			drop_id is not int
			or drop_id < 1
			or item_id is not String
			or drop_position is not Vector3
			or not _game_data_registry["items"].has(item_id)
			or new_drop_states.has(drop_id)
		):
			push_warning("Rejected malformed loot drop state")
			return
		new_drop_states[drop_id] = {
			"item_id": item_id,
			"position": drop_position,
		}

	var inventory_state: Array[Dictionary] = []
	for entry: Variant in inventory_entries:
		if not entry is Array or entry.size() != 2:
			push_warning("Rejected malformed inventory slot")
			return
		var item_id: Variant = entry[0]
		var quantity: Variant = entry[1]
		if (
			item_id is not String
			or quantity is not int
			or quantity < 1
			or not _game_data_registry["items"].has(item_id)
			or quantity > int(_game_data_registry["items"][item_id]["stack_limit"])
		):
			push_warning("Rejected malformed inventory item")
			return
		inventory_state.append({
			"item_id": item_id,
			"quantity": quantity,
		})

	var snapshot_record: Dictionary = {
		"received_at_ms": Time.get_ticks_msec(),
		"positions": positions,
	}
	_player_health_states = player_health_states
	_mob_states = new_mob_states
	_drop_states = new_drop_states
	_inventory_state = inventory_state
	var existing_mob_ids: Array = _mob_views.keys()
	for mob_id: String in existing_mob_ids:
		if not _mob_states.has(mob_id):
			var mob_view: Node3D = _mob_views[mob_id]
			mob_view.queue_free()
			_mob_views.erase(mob_id)
		else:
			var mob_view: Node3D = _mob_views[mob_id]
			mob_view.position = _mob_states[mob_id]["position"]
			mob_view.visible = float(_mob_states[mob_id]["health"]) > 0.0
	var existing_drop_ids: Array = _drop_views.keys()
	for drop_id: int in existing_drop_ids:
		if not _drop_states.has(drop_id):
			var drop_view: MeshInstance3D = _drop_views[drop_id]
			drop_view.queue_free()
			_drop_views.erase(drop_id)
	for drop_id: int in _drop_states:
		_ensure_loot_view(drop_id)
		var drop_view: MeshInstance3D = _drop_views[drop_id]
		drop_view.position = (
			_drop_states[drop_id]["position"]
			+ Vector3(0.0, float(_simulation_config["loot_visual_radius"]), 0.0)
		)
	_update_combat_status()
	_snapshot_buffer.append(snapshot_record)
	var capacity: int = int(_simulation_config["snapshot_buffer_capacity"])
	while _snapshot_buffer.size() > capacity:
		_snapshot_buffer.pop_front()

	var existing_player_ids: Array = _player_views.keys()
	for player_id: int in existing_player_ids:
		if not positions.has(player_id):
			var player_view: PlayerBodyAdapter = _player_views[player_id]
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
		var player_view: PlayerBodyAdapter = _player_views[player_id]
		if not newer_positions.has(player_id):
			continue
		var newer_position: Vector3 = newer_positions[player_id]
		if player_id == _local_player_id:
			var correction_factor: float = float(_simulation_config["local_reconciliation_factor"])
			_predicted_position = _predicted_position.lerp(latest_positions[player_id], correction_factor)
			player_view.set_simulated_position(_predicted_position)
			continue
		var older_position: Vector3 = older_positions.get(player_id, newer_position)
		player_view.position = older_position.lerp(newer_position, interpolation_alpha)


func _ensure_player_view(player_id: int) -> void:
	if _player_views.has(player_id):
		return

	var player_view: PlayerBodyAdapter = PlayerBodyAdapterType.new()
	player_view.name = "Player_%d" % player_id
	player_view.collision_layer = 0
	player_view.collision_mask = 0
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = float(_simulation_config["player_visual_radius"])
	capsule.height = float(_simulation_config["player_visual_height"])
	mesh_instance.mesh = capsule
	mesh_instance.material_override = StandardMaterial3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.position.y = capsule.height / 2.0
	player_view.add_child(mesh_instance)
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
	capsule_shape.radius = float(_simulation_config["player_visual_radius"])
	capsule_shape.height = float(_simulation_config["player_visual_height"])
	collision_shape.shape = capsule_shape
	collision_shape.position.y = capsule_shape.height / 2.0
	player_view.add_child(collision_shape)
	add_child(player_view)
	_player_views[player_id] = player_view
	var color: Color = Color(0.25, 0.7, 0.95)
	if player_id == _local_player_id:
		color = Color(0.95, 0.72, 0.25)
	_set_player_color(player_id, color)


func _ensure_mob_view(mob_id: String) -> void:
	if _mob_views.has(mob_id):
		return
	var mob_definition: Dictionary = _game_data_registry["mobs"][mob_id]
	var mob_view: Node3D = Node3D.new()
	mob_view.name = "Mob_%s" % mob_id
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = float(mob_definition["visual_radius"])
	capsule.height = float(mob_definition["visual_height"])
	mesh_instance.mesh = capsule
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = (
		Color(0.78, 0.24, 0.2)
		if bool(mob_definition["is_boss"])
		else Color(0.35, 0.78, 0.38)
	)
	mesh_instance.material_override = material
	mesh_instance.position.y = capsule.height / 2.0
	mob_view.add_child(mesh_instance)
	add_child(mob_view)
	_mob_views[mob_id] = mob_view


func _ensure_loot_view(drop_id: int) -> void:
	if _drop_views.has(drop_id):
		return
	var loot_view: MeshInstance3D = MeshInstance3D.new()
	loot_view.name = "Loot_%d" % drop_id
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = float(_simulation_config["loot_visual_radius"])
	sphere.height = sphere.radius * 2.0
	loot_view.mesh = sphere
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.78, 0.2)
	loot_view.material_override = material
	add_child(loot_view)
	_drop_views[drop_id] = loot_view


func _update_combat_status() -> void:
	if (
		_combat_message_time_remaining > 0.0
		or not _player_health_states.has(_local_player_id)
		or _mob_states.is_empty()
	):
		return
	var mob_id: String = _mob_states.keys()[0]
	var mob_definition: Dictionary = _game_data_registry["mobs"][mob_id]
	var player_state: Dictionary = _player_health_states[_local_player_id]
	var inventory_names: PackedStringArray = []
	for slot: Dictionary in _inventory_state:
		var item_definition: Dictionary = _game_data_registry["items"][slot["item_id"]]
		inventory_names.append(
			"%s x%d" % [tr(item_definition["name_key"]), int(slot["quantity"])],
		)
	var inventory_summary: String = tr("inventory_empty")
	if not inventory_names.is_empty():
		inventory_summary = ", ".join(inventory_names)
	var combat_summary: String = tr("combat_status") % [
		int(player_state["level"]),
		int(player_state["experience"]),
		int(player_state["health"]),
		int(player_state["max_health"]),
		int(player_state["resource"]),
		int(player_state["max_resource"]),
		tr(mob_definition["name_key"]),
		int(_mob_states[mob_id]["health"]),
		int(_mob_states[mob_id]["max_health"]),
	]
	var inventory_line: String = tr("inventory_status") % [
		_inventory_state.size(),
		int(_simulation_config["inventory_slot_count"]),
		inventory_summary,
	]
	status_label.text = combat_summary + "\n" + inventory_line


func _request_nearest_loot() -> void:
	var local_view: PlayerBodyAdapter = _player_views.get(_local_player_id)
	if local_view == null:
		return
	var pickup_range_squared: float = (
		float(_simulation_config["loot_pickup_range"])
		* float(_simulation_config["loot_pickup_range"])
	)
	var nearest_drop_id: int = 0
	var nearest_distance_squared: float = pickup_range_squared
	for drop_id: int in _drop_states:
		var drop_position: Vector3 = _drop_states[drop_id]["position"]
		var distance_squared: float = local_view.global_position.distance_squared_to(drop_position)
		if distance_squared <= nearest_distance_squared:
			nearest_drop_id = drop_id
			nearest_distance_squared = distance_squared
	if nearest_drop_id == 0:
		status_label.text = tr("loot_no_nearby")
		_combat_message_time_remaining = 1.0
		return
	var error: Error = _client_net.request_loot_pickup(nearest_drop_id)
	if error != OK:
		push_warning("Could not request loot pickup: %s" % error)


func _request_attack(ability_id: String) -> void:
	var local_view: PlayerBodyAdapter = _player_views.get(_local_player_id)
	if local_view == null or _mob_states.is_empty():
		return
	var target_mob_id: String = ""
	var nearest_distance_squared: float = INF
	for mob_id: String in _mob_states:
		if float(_mob_states[mob_id]["health"]) <= 0.0:
			continue
		var mob_position: Vector3 = _mob_states[mob_id]["position"]
		var distance_squared: float = local_view.global_position.distance_squared_to(mob_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			target_mob_id = mob_id
	if target_mob_id.is_empty():
		return
	var error: Error = _client_net.request_ability_cast(ability_id, target_mob_id)
	if error != OK:
		push_warning("Could not send ability cast: %s" % error)


func _set_player_color(player_id: int, color: Color) -> void:
	var player_view: PlayerBodyAdapter = _player_views.get(player_id)
	if player_view == null:
		return
	var mesh_instance: MeshInstance3D = player_view.get_node("Visual")
	var material: StandardMaterial3D = mesh_instance.material_override
	material.albedo_color = color


func _is_finite_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	return (
		(value_type == TYPE_INT or value_type == TYPE_FLOAT)
		and is_finite(float(value))
	)
