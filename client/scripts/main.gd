extends Node3D

const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const MovementSimulationType: GDScript = preload("res://shared/sim/movement_simulation.gd")
const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")
const PlayerBodyAdapterType: GDScript = preload("res://client/scripts/player_body_adapter.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const WorldSnapshotParserType: GDScript = preload("res://client/scripts/world_snapshot_parser.gd")
const WorldBuilderType: GDScript = preload("res://client/scripts/world_builder.gd")

@onready var status_label: Label = $StatusCanvas/StatusPanel/StatusLabel
@onready var hint_label: Label = $StatusCanvas/HintLabel
@onready var hint_panels_label: Label = $StatusCanvas/HintPanelsLabel
@onready var camera: Camera3D = $Camera3D
@onready var inventory_panel: PanelContainer = $InventoryCanvas/InventoryPanel
@onready var npc_dialog_panel: PanelContainer = $QuestCanvas/NpcDialogPanel
@onready var quest_tracker_panel: PanelContainer = $QuestCanvas/QuestTrackerPanel
@onready var chat_panel: PanelContainer = $ChatCanvas/ChatPanel

var _simulation_config: Dictionary = {}
var _game_data_registry: Dictionary = {}
var _server_address: String = ProtocolConstantsType.DEFAULT_SERVER_ADDRESS
var _server_port: int = ProtocolConstantsType.SERVER_PORT
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
var _mob_types_by_instance: Dictionary = {}
var _drop_states: Dictionary = {}
var _drop_views: Dictionary = {}
var _npc_states: Dictionary = {}
var _npc_views: Dictionary = {}
var _quest_states: Array = []
var _inventory_state: Array[Dictionary] = []
var _equipment_state: Dictionary = {}
var _gold: int = 0
var _world_builder: RefCounted = null
var _inventory_key_down: bool = false
var _chat_key_down: bool = false
var _slash_key_down: bool = false
var _heavy_strike_key_down: bool = false
var _guard_break_key_down: bool = false
var _whirlwind_key_down: bool = false
var _second_wind_key_down: bool = false
var _loot_key_down: bool = false
var _interact_key_down: bool = false
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
	_server_address = _resolve_server_address()
	_server_port = _resolve_server_port()
	_mob_types_by_instance = GameDataRegistryType.build_mob_instance_types(
		_game_data_registry["mobs"]
	)
	_build_landscape()

	hint_label.text = tr("controls_hint")
	hint_panels_label.text = tr("controls_hint_panels")
	status_label.text = tr("connection_connecting") % [
		_server_address,
		_server_port,
	]
	inventory_panel.setup(_game_data_registry["items"])
	inventory_panel.equip_requested.connect(_on_equip_requested)
	inventory_panel.unequip_requested.connect(_on_unequip_requested)
	inventory_panel.use_item_requested.connect(_on_use_item_requested)
	npc_dialog_panel.setup(_game_data_registry["items"], _game_data_registry["mobs"])
	npc_dialog_panel.accept_quest_requested.connect(_on_accept_quest_requested)
	npc_dialog_panel.turn_in_quest_requested.connect(_on_turn_in_quest_requested)
	npc_dialog_panel.trade_requested.connect(_on_trade_requested)
	quest_tracker_panel.setup(_game_data_registry["items"], _game_data_registry["mobs"])
	chat_panel.setup(_simulation_config)
	chat_panel.chat_message_requested.connect(_on_chat_message_requested)
	chat_panel.party_invite_requested.connect(_on_party_invite_requested)
	chat_panel.party_invite_responded.connect(_on_party_invite_responded)
	chat_panel.party_leave_requested.connect(_on_party_leave_requested)
	_client_net = ClientNet.new()
	add_child(_client_net)
	_client_net.hello_accepted.connect(_on_hello_accepted)
	_client_net.hello_rejected.connect(_on_hello_rejected)
	_client_net.disconnected.connect(_on_disconnected)
	_client_net.world_snapshot.connect(_on_world_snapshot)
	_client_net.ability_cast_completed.connect(_on_ability_cast_completed)
	_client_net.loot_pickup_completed.connect(_on_loot_pickup_completed)
	_client_net.equipment_action_completed.connect(_on_equipment_action_completed)
	_client_net.item_use_completed.connect(_on_item_use_completed)
	_client_net.npc_interaction_completed.connect(_on_npc_interaction_completed)
	_client_net.trade_completed.connect(_on_trade_completed)
	_client_net.chat_message_received.connect(_on_chat_message_received)
	_client_net.party_result_received.connect(_on_party_result_received)

	var error: Error = _client_net.connect_to_server(_server_address, _server_port)
	if error != OK:
		status_label.text = tr("connection_failed")
		push_error("Could not start ENet client: %s" % error)


## Builds the landscape of the zone.
##
## The terrain and the props are generated from a fixed seed, so every client
## shows the same map. The flat ground of the scene is replaced by the
## generated terrain.
func _build_landscape() -> void:
	var ground: Node3D = get_node_or_null("Ground")
	if ground != null:
		ground.queue_free()
	_world_builder = WorldBuilderType.new(_simulation_config)
	add_child(_world_builder.build_terrain())
	add_child(_world_builder.build_props(_collect_occupied_positions()))


## Collects the positions of the NPCs and the mobs, so that no prop is placed
## on top of them.
func _collect_occupied_positions() -> Array:
	var occupied: Array = []
	for npc_definition: Dictionary in _game_data_registry["npcs"].values():
		var spawn_position: Array = npc_definition["spawn_position"]
		occupied.append(Vector3(
			float(spawn_position[0]),
			0.0,
			float(spawn_position[2]),
		))
	for instance: Dictionary in GameDataRegistryType.build_mob_instances(
		_game_data_registry["mobs"]
	):
		var position: Vector3 = instance["position"]
		occupied.append(Vector3(position.x, 0.0, position.z))
	return occupied


## Returns the definition of a mob.
##
## A mob type can have several instances in the zone, so the definition is
## looked up by the type of the instance.
func _mob_definition(mob_id: String) -> Dictionary:
	var mob_type: String = str(_mob_types_by_instance.get(mob_id, mob_id))
	return _game_data_registry["mobs"].get(mob_type, {})


## Returns the height of the terrain at the given position.
func _ground_height(x: float, z: float) -> float:
	if _world_builder == null:
		return 0.0
	return _world_builder.get_height(x, z)


## Returns the given position raised onto the terrain.
func _terrain_position(position: Vector3) -> Vector3:
	return Vector3(position.x, _ground_height(position.x, position.z), position.z)


## Resolves the server address from the simulation config, with an environment
## override so a client can join a server on another machine.
func _resolve_server_address() -> String:
	var configured_address: String = str(
		_simulation_config.get(
			"server_address",
			ProtocolConstantsType.DEFAULT_SERVER_ADDRESS,
		)
	)
	var environment_address: String = OS.get_environment("MMORPG3D_SERVER_ADDRESS")
	if not environment_address.strip_edges().is_empty():
		return environment_address.strip_edges()
	return configured_address


## Resolves the server port from the simulation config, with an environment
## override for non-default deployments.
func _resolve_server_port() -> int:
	var configured_port: int = int(
		_simulation_config.get("server_port", ProtocolConstantsType.SERVER_PORT)
	)
	var environment_port: String = OS.get_environment("MMORPG3D_SERVER_PORT")
	if environment_port.strip_edges().is_valid_int():
		var parsed_port: int = environment_port.strip_edges().to_int()
		if parsed_port > 0 and parsed_port <= 65535:
			return parsed_port
	return configured_port


func _physics_process(delta: float) -> void:
	if _client_net == null or not _client_net.is_connected or _local_player_id == 0:
		return

	var local_health_state: Dictionary = _player_health_states.get(_local_player_id, {})
	var player_is_defeated: bool = (
		not local_health_state.is_empty() and float(local_health_state["health"]) <= 0.0
	)
	var input_direction: Vector2 = Vector2.ZERO
	var chat_input_focused: bool = chat_panel.is_input_focused()
	if not player_is_defeated and not chat_input_focused:
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
		local_view.move_to_simulated_position(_terrain_position(_predicted_position), delta)
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
	var interact_key_pressed: bool = Input.is_key_pressed(KEY_V)
	if not player_is_defeated and interact_key_pressed and not _interact_key_down:
		_request_nearest_npc()
	_interact_key_down = interact_key_pressed
	var inventory_key_pressed: bool = Input.is_key_pressed(KEY_I)
	if inventory_key_pressed and not _inventory_key_down:
		_toggle_inventory_panel()
	_inventory_key_down = inventory_key_pressed
	var chat_key_pressed: bool = Input.is_key_pressed(KEY_C)
	if chat_key_pressed and not _chat_key_down:
		_toggle_chat_panel()
	_chat_key_down = chat_key_pressed


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
	chat_panel.set_local_peer(player_id)
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
	var mob_definition: Dictionary = _mob_definition(mob_id)
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


func _on_equipment_action_completed(
	operation: String,
	accepted: bool,
	reason: String,
	item_id: String,
	slot_id: String,
) -> void:
	if accepted:
		var item_definition: Dictionary = _game_data_registry["items"].get(item_id, {})
		if item_definition.is_empty():
			push_error("Equipment result referenced unknown item %s" % item_id)
			return
		status_label.text = tr("equipment_action_success") % [
			tr(item_definition["name_key"]),
			tr("equipment_slot_" + slot_id),
		]
	else:
		status_label.text = tr("equipment_action_failed") % tr("equipment_reason_" + reason)
	_combat_message_time_remaining = 2.0


func _on_world_snapshot(snapshot: Dictionary) -> void:
	var parsed: Dictionary = WorldSnapshotParserType.parse(
		snapshot,
		_game_data_registry,
		int(_simulation_config["inventory_slot_count"]),
	)
	if not bool(parsed["ok"]):
		push_warning("Rejected world snapshot: %s" % str(parsed["error"]))
		return
	var positions: Dictionary = parsed["positions"]
	var player_health_states: Dictionary = parsed["player_health_states"]
	var new_mob_states: Dictionary = parsed["mob_states"]
	var new_drop_states: Dictionary = parsed["drop_states"]
	var new_npc_states: Dictionary = parsed["npc_states"]
	var new_quest_states: Array = parsed["quest_states"]
	var inventory_state: Array = parsed["inventory_state"]
	var equipment_state: Dictionary = parsed["equipment_state"]
	for player_id: int in positions:
		_ensure_player_view(player_id)
		if player_id == _local_player_id and not _has_authoritative_position:
			_predicted_position = positions[player_id]
			var local_player_view: PlayerBodyAdapter = _player_views[player_id]
			local_player_view.set_simulated_position(_terrain_position(positions[player_id]))
			_has_authoritative_position = true
	for mob_id: String in new_mob_states:
		_ensure_mob_view(mob_id)

	var snapshot_record: Dictionary = {
		"received_at_ms": Time.get_ticks_msec(),
		"positions": positions,
	}
	_player_health_states = player_health_states
	_mob_states = new_mob_states
	_drop_states = new_drop_states
	_npc_states = new_npc_states
	_quest_states = new_quest_states
	_inventory_state = inventory_state
	_equipment_state = equipment_state
	_gold = int(parsed["gold"])
	var zone_player_ids: Array[int] = []
	for player_id: int in positions:
		zone_player_ids.append(player_id)
	chat_panel.set_zone_players(zone_player_ids)
	var existing_npc_ids: Array = _npc_views.keys()
	for npc_id: String in existing_npc_ids:
		if not _npc_states.has(npc_id):
			var npc_view: Node3D = _npc_views[npc_id]
			npc_view.queue_free()
			_npc_views.erase(npc_id)
		else:
			var npc_view: Node3D = _npc_views[npc_id]
			npc_view.position = _terrain_position(_npc_states[npc_id]["position"])
	for npc_id: String in _npc_states:
		_ensure_npc_view(npc_id)
		var npc_view: Node3D = _npc_views[npc_id]
		npc_view.position = _terrain_position(_npc_states[npc_id]["position"])
	var existing_mob_ids: Array = _mob_views.keys()
	for mob_id: String in existing_mob_ids:
		if not _mob_states.has(mob_id):
			var mob_view: Node3D = _mob_views[mob_id]
			mob_view.queue_free()
			_mob_views.erase(mob_id)
		else:
			var mob_view: Node3D = _mob_views[mob_id]
			mob_view.position = _terrain_position(_mob_states[mob_id]["position"])
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
			_terrain_position(_drop_states[drop_id]["position"])
			+ Vector3(0.0, float(_simulation_config["loot_visual_radius"]), 0.0)
		)
	_update_combat_status()
	_update_inventory_panel()
	_update_quest_tracker()
	_update_nameplates()
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
			player_view.set_simulated_position(_terrain_position(_predicted_position))
			continue
		var older_position: Vector3 = older_positions.get(player_id, newer_position)
		player_view.position = _terrain_position(older_position.lerp(newer_position, interpolation_alpha))


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
	player_view.build_nameplate(capsule.height + 0.45)
	add_child(player_view)
	_player_views[player_id] = player_view
	var color: Color = Color(0.25, 0.7, 0.95)
	if player_id == _local_player_id:
		color = Color(0.95, 0.72, 0.25)
	_set_player_color(player_id, color)


func _ensure_mob_view(mob_id: String) -> void:
	if _mob_views.has(mob_id):
		return
	var mob_definition: Dictionary = _mob_definition(mob_id)
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


func _ensure_npc_view(npc_id: String) -> void:
	if _npc_views.has(npc_id):
		return
	var npc_view: Node3D = Node3D.new()
	npc_view.name = "Npc_%s" % npc_id
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = float(_simulation_config["player_visual_radius"])
	capsule.height = float(_simulation_config["player_visual_height"])
	mesh_instance.mesh = capsule
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.72, 0.3)
	mesh_instance.material_override = material
	mesh_instance.position.y = capsule.height / 2.0
	npc_view.add_child(mesh_instance)
	add_child(npc_view)
	_npc_views[npc_id] = npc_view


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


## Updates the nameplates above the players.
##
## The plate of a player shows the level, the health, and the resource that the
## server reported for it.
func _update_nameplates() -> void:
	for player_id: Variant in _player_health_states:
		var player_view: PlayerBodyAdapter = _player_views.get(player_id)
		if player_view == null:
			continue
		var state: Dictionary = _player_health_states[player_id]
		player_view.update_nameplate(
			int(state.get("level", 1)),
			float(state.get("health", 0.0)),
			float(state.get("max_health", 1.0)),
			float(state.get("resource", 0.0)),
			float(state.get("max_resource", 1.0)),
		)


## Toggles the inventory panel.
func _toggle_inventory_panel() -> void:
	inventory_panel.visible = not inventory_panel.visible


## Toggles the chat panel.
func _toggle_chat_panel() -> void:
	chat_panel.visible = not chat_panel.visible


func _update_inventory_panel() -> void:
	var local_state: Dictionary = _player_health_states.get(_local_player_id, {})
	var local_level: int = int(local_state.get("level", 1))
	inventory_panel.update_view(_inventory_state, _equipment_state, local_level)


func _update_quest_tracker() -> void:
	quest_tracker_panel.update_view(_quest_states)


func _update_combat_status() -> void:
	if (
		_combat_message_time_remaining > 0.0
		or not _player_health_states.has(_local_player_id)
		or _mob_states.is_empty()
	):
		return
	var mob_id: String = _mob_states.keys()[0]
	var mob_definition: Dictionary = _mob_definition(mob_id)
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
	var equipment_names: PackedStringArray = []
	for slot_id: String in GameDataRegistryType.EQUIPMENT_SLOTS:
		var item_id: String = str(_equipment_state.get(slot_id, ""))
		if item_id.is_empty():
			continue
		var item_definition: Dictionary = _game_data_registry["items"][item_id]
		equipment_names.append(
			"%s: %s" % [
				tr("equipment_slot_" + slot_id),
				tr(item_definition["name_key"]),
			],
		)
	var equipment_summary: String = tr("equipment_empty")
	if not equipment_names.is_empty():
		equipment_summary = ", ".join(equipment_names)
	var equipment_line: String = tr("equipment_status") % equipment_summary
	var gold_line: String = tr("gold_status") % _gold
	status_label.text = (
		combat_summary
		+ "\n"
		+ inventory_line
		+ "\n"
		+ equipment_line
		+ "\n"
		+ gold_line
	)


func _on_equip_requested(item_id: String) -> void:
	var error: Error = _client_net.request_equip_item(item_id)
	if error != OK:
		push_warning("Could not request item equip: %s" % error)


func _on_unequip_requested(slot_id: String) -> void:
	var error: Error = _client_net.request_unequip_item(slot_id)
	if error != OK:
		push_warning("Could not request item unequip: %s" % error)


func _on_use_item_requested(item_id: String) -> void:
	var error: Error = _client_net.request_use_item(item_id)
	if error != OK:
		push_warning("Could not request item use: %s" % error)


func _on_item_use_completed(
	accepted: bool,
	reason: String,
	item_id: String,
	health: float,
	max_health: float,
	resource: float,
	max_resource: float,
) -> void:
	if accepted:
		var item_definition: Dictionary = _game_data_registry["items"].get(item_id, {})
		status_label.text = tr("item_use_success") % [
			tr(item_definition.get("name_key", item_id)),
			int(health),
			int(max_health),
			int(resource),
			int(max_resource),
		]
	else:
		status_label.text = tr("item_use_failed") % tr("item_use_reason_" + reason)
	_combat_message_time_remaining = 2.0


## Finds the closest NPC the player can reach and starts a conversation.
func _request_nearest_npc() -> void:
	var local_view: PlayerBodyAdapter = _player_views.get(_local_player_id)
	if local_view == null or _npc_states.is_empty():
		return
	var nearest_npc_id: String = ""
	var nearest_distance_squared: float = INF
	for npc_id: String in _npc_states:
		var npc_definition: Dictionary = _game_data_registry["npcs"].get(npc_id, {})
		var interaction_range: float = float(npc_definition.get("interaction_range", 0.0))
		var npc_position: Vector3 = _npc_states[npc_id]["position"]
		var distance_squared: float = local_view.global_position.distance_squared_to(
			npc_position
		)
		if distance_squared > interaction_range * interaction_range:
			continue
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_npc_id = npc_id
	if nearest_npc_id.is_empty():
		status_label.text = tr("interact_no_npc")
		_combat_message_time_remaining = 1.0
		return
	var error: Error = _client_net.request_npc_interact(nearest_npc_id, "talk")
	if error != OK:
		push_warning("Could not request NPC interaction: %s" % error)


func _on_accept_quest_requested(npc_id: String, quest_id: String) -> void:
	var error: Error = _client_net.request_npc_interact(npc_id, "accept", quest_id)
	if error != OK:
		push_warning("Could not request quest acceptance: %s" % error)


func _on_turn_in_quest_requested(npc_id: String, quest_id: String) -> void:
	var error: Error = _client_net.request_npc_interact(npc_id, "turn_in", quest_id)
	if error != OK:
		push_warning("Could not request quest turn-in: %s" % error)


func _on_npc_interaction_completed(
	accepted: bool,
	reason: String,
	action: String,
	npc_id: String,
	npc_name_key: String,
	dialogue_key: String,
	quests: Array,
	quest_id: String,
	reward_experience: int,
	reward_gold: int,
	reward_item_ids: Array,
	vendor_items: Array,
) -> void:
	if not accepted:
		status_label.text = tr("interact_failed") % tr("interact_reason_" + reason)
		_combat_message_time_remaining = 2.0
		return
	if action == "turn_in":
		var reward_names: PackedStringArray = []
		for item_id: String in reward_item_ids:
			var item_definition: Dictionary = _game_data_registry["items"].get(item_id, {})
			reward_names.append(tr(str(item_definition.get("name_key", item_id))))
		status_label.text = tr("quest_turn_in_success") % [
			reward_experience,
			reward_gold,
			", ".join(reward_names),
		]
		_combat_message_time_remaining = 2.0
	var local_state: Dictionary = _player_health_states.get(_local_player_id, {})
	npc_dialog_panel.show_npc(
		npc_id,
		npc_name_key,
		dialogue_key,
		quests,
		vendor_items,
		_inventory_state,
		_gold,
		int(local_state.get("level", 1)),
	)


## Sends a trade request to the server.
##
## The request only names the action, the item, and the quantity; the price is
## decided by the server.
func _on_trade_requested(
	npc_id: String,
	action: String,
	item_id: String,
	quantity: int,
) -> void:
	var error: Error = _client_net.request_trade(npc_id, action, item_id, quantity)
	if error != OK:
		push_warning("Could not request trade: %s" % error)


func _on_trade_completed(
	accepted: bool,
	reason: String,
	action: String,
	npc_id: String,
	item_id: String,
	quantity: int,
	price: int,
	gold: int,
) -> void:
	if not accepted:
		status_label.text = tr("trade_failed") % tr("trade_reason_" + reason)
		_combat_message_time_remaining = 2.0
		return
	var item_definition: Dictionary = _game_data_registry["items"].get(item_id, {})
	var item_name: String = tr(str(item_definition.get("name_key", item_id)))
	if action == "buy":
		status_label.text = tr("trade_buy_success") % [item_name, quantity, price * quantity]
	else:
		status_label.text = tr("trade_sell_success") % [item_name, quantity, price * quantity]
	_combat_message_time_remaining = 2.0


## Sends a chat message to the server.
##
## The request names the channel and the text; the server decides who receives
## the message.
func _on_chat_message_requested(channel: String, text: String) -> void:
	var error: Error = _client_net.request_chat(channel, text)
	if error != OK:
		push_warning("Could not request chat message: %s" % error)


## Renders a chat message of the server.
func _on_chat_message_received(
	channel: String,
	sender_peer_id: int,
	sender_name: String,
	text: String,
	system_key: String,
	reason: String,
) -> void:
	chat_panel.add_message({
		"channel": channel,
		"sender_peer_id": sender_peer_id,
		"sender_name": sender_name,
		"text": text,
		"system_key": system_key,
		"reason": reason,
	})


## Requests an invitation into a party.
func _on_party_invite_requested(target_peer_id: int) -> void:
	var error: Error = _client_net.request_party_action("invite", target_peer_id)
	if error != OK:
		push_warning("Could not request party invitation: %s" % error)


## Answers an invitation into a party.
##
## A declined invitation leaves the party, because the player was not a member
## of it yet.
func _on_party_invite_responded(accepted: bool) -> void:
	var action: String = "accept" if accepted else "leave"
	var error: Error = _client_net.request_party_action(action)
	if error != OK:
		push_warning("Could not answer party invitation: %s" % error)


## Requests to leave the party of the player.
func _on_party_leave_requested() -> void:
	var error: Error = _client_net.request_party_action("leave")
	if error != OK:
		push_warning("Could not request party departure: %s" % error)


## Renders the result of a party request.
func _on_party_result_received(
	accepted: bool,
	reason: String,
	action: String,
	party_id: int,
	leader_peer_id: int,
	members: Array,
	inviter_peer_id: int,
	inviter_name: String,
) -> void:
	if action == "invite" and accepted and inviter_peer_id != 0:
		chat_panel.show_invitation(inviter_peer_id, inviter_name)
		return
	if accepted:
		chat_panel.set_party_state(party_id, leader_peer_id, members)
		return
	if reason == "not_in_party":
		chat_panel.clear_party_state()
		return
	chat_panel.add_message({
		"channel": "system",
		"sender_peer_id": 0,
		"sender_name": "",
		"text": "",
		"system_key": "",
		"reason": "party_" + reason,
	})


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
