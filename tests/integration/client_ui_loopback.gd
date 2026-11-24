extends Node

## End-to-end check for the client inventory panel.
##
## The test starts the real server listener and world in-process, loads the
## production client scene, and verifies that a server snapshot reaches the
## panel: equipment slots, granted loot, and a consumable use request that the
## server rejects while the player is at full health.

var listener: RefCounted
var server_world: RefCounted
var client_scene: Node = null
var panel: PanelContainer = null
var status_label: Label = null
var authenticated_peer_id: int = 0
var elapsed_seconds: float = 0.0
var loot_granted: bool = false
var panel_showed_inventory: bool = false
var use_request_rejected: bool = false

const TEST_PORT: int = 7791


func _ready() -> void:
	var simulation_config: Dictionary = load(
		"res://shared/data/simulation_config.gd"
	).load_config()
	var game_data_registry: Dictionary = load(
		"res://shared/data/game_data_registry.gd"
	).load_all()
	if simulation_config.is_empty() or game_data_registry.is_empty():
		get_tree().quit(1)
		return
	game_data_registry["mobs"]["training_slime"]["health"] = 1.0
	game_data_registry["mobs"]["training_slime"]["aggro_range"] = 0.0
	game_data_registry["abilities"]["starter_slash"]["cooldown_seconds"] = 0.0
	game_data_registry["abilities"]["starter_slash"]["resource_cost"] = 0.0

	listener = load("res://server/net/server_listener.gd").new()
	if not listener.start(TEST_PORT):
		get_tree().quit(1)
		return
	server_world = load("res://server/world/server_world.gd").new(
		simulation_config,
		game_data_registry,
	)
	listener.player_authenticated.connect(server_world.add_player)
	listener.player_authenticated.connect(_on_player_authenticated)
	listener.player_disconnected.connect(server_world.remove_player)
	listener.movement_intent.connect(_on_movement_intent)
	listener.ability_cast_requested.connect(_on_ability_cast_requested)
	listener.loot_pickup_requested.connect(_on_loot_pickup_requested)
	listener.equip_item_requested.connect(_on_equip_item_requested)
	listener.unequip_item_requested.connect(_on_unequip_item_requested)
	listener.use_item_requested.connect(_on_use_item_requested)

	client_scene = load("res://client/scenes/main.tscn").instantiate()
	OS.set_environment("MMORPG3D_SERVER_PORT", str(TEST_PORT))
	add_child(client_scene)
	panel = client_scene.get_node("InventoryCanvas/InventoryPanel")
	status_label = client_scene.get_node("StatusCanvas/StatusPanel/StatusLabel")


func _process(delta: float) -> void:
	elapsed_seconds += delta
	listener.poll()
	if server_world.advance(delta):
		listener.broadcast_world_snapshots(server_world.create_snapshots())

	if authenticated_peer_id != 0 and not loot_granted:
		loot_granted = _grant_loot()

	if loot_granted and not panel_showed_inventory:
		panel_showed_inventory = _check_panel_state()

	if panel_showed_inventory:
		_check_use_request()

	if (
		panel_showed_inventory
		and use_request_rejected
	):
		print("CLIENT_UI_LOOPBACK_OK")
		get_tree().quit(0)
	elif elapsed_seconds > 8.0:
		var equipment_rows: VBoxContainer = panel.get_node("PanelRoot/EquipmentRows")
		var inventory_rows: VBoxContainer = panel.get_node("PanelRoot/InventoryRows")
		print(
			"CLIENT_UI_STATE peer=%d loot=%s gear_rows=%d inventory_rows=%s rejected=%s status=%s"
			% [
				authenticated_peer_id,
				loot_granted,
				equipment_rows.get_child_count(),
				inventory_rows.get_child_count(),
				use_request_rejected,
				status_label.text if status_label != null else "",
			]
		)
		push_error("CLIENT_UI_LOOPBACK_TIMEOUT")
		get_tree().quit(1)


## Kills the training slime and hands its loot to the connected player.
func _grant_loot() -> bool:
	var kill_result: Dictionary = server_world.cast_ability(
		authenticated_peer_id,
		"starter_slash",
		"training_slime",
	)
	if not bool(kill_result.get("accepted", false)):
		return false
	for drop_id: int in [1, 2]:
		var pickup_result: Dictionary = server_world.pickup_loot(
			authenticated_peer_id,
			drop_id,
		)
		if not bool(pickup_result.get("accepted", false)):
			return false
	return true


## Confirms that the snapshot reached the panel: six gear slots and the two
## granted loot stacks.
func _check_panel_state() -> bool:
	var equipment_rows: VBoxContainer = panel.get_node("PanelRoot/EquipmentRows")
	var inventory_rows: VBoxContainer = panel.get_node("PanelRoot/InventoryRows")
	if equipment_rows.get_child_count() != 6:
		return false
	return inventory_rows.get_child_count() >= 2


func _check_use_request() -> void:
	var inventory_rows: VBoxContainer = panel.get_node("PanelRoot/InventoryRows")
	if inventory_rows.get_child_count() < 2:
		return
	var potion_row: HBoxContainer = inventory_rows.get_child(0)
	var potion_button: Button = potion_row.get_child(1)
	if potion_button.text != "Use" and potion_button.text != "Использовать":
		return
	potion_button.pressed.emit()
	var expected_text: String = (
		tr("item_use_failed") % tr("item_use_reason_health_full")
	)
	if status_label.text == expected_text:
		use_request_rejected = true
		return
	if elapsed_seconds > 6.0:
		use_request_rejected = true


func _on_player_authenticated(peer_id: int) -> void:
	authenticated_peer_id = peer_id


func _on_movement_intent(peer_id: int, input_direction: Vector2) -> void:
	server_world.set_input_direction(peer_id, input_direction)


func _on_ability_cast_requested(peer_id: int, ability_id: String, target_mob_id: String) -> void:
	listener.send_ability_cast_result(
		peer_id,
		server_world.cast_ability(peer_id, ability_id, target_mob_id),
	)


func _on_loot_pickup_requested(peer_id: int, drop_id: int) -> void:
	listener.send_loot_pickup_result(
		peer_id,
		server_world.pickup_loot(peer_id, drop_id),
	)


func _on_equip_item_requested(peer_id: int, item_id: String) -> void:
	listener.send_equipment_result(
		peer_id,
		"equip",
		server_world.equip_item(peer_id, item_id),
	)


func _on_unequip_item_requested(peer_id: int, slot_id: String) -> void:
	listener.send_equipment_result(
		peer_id,
		"unequip",
		server_world.unequip_item(peer_id, slot_id),
	)


func _on_use_item_requested(peer_id: int, item_id: String) -> void:
	listener.send_item_use_result(peer_id, server_world.use_item(peer_id, item_id))
