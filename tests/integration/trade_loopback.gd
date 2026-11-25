extends Node

## End-to-end check for the vendor, the currency, and the trade loop.
##
## The test starts the real server listener and world in-process, loads the
## production client scene, and walks through the full trade cycle: talk to the
## vendor, buy an item with the gold of the player, equip it, and see the
## bonus. Every step goes through the network, the server stays authoritative,
## and the client only renders what it receives. The test also forges a trade
## request that the server has to refuse.

var listener: RefCounted
var server_world: RefCounted
var client_scene: Node = null
var dialog_panel: PanelContainer = null
var inventory_panel: PanelContainer = null
var status_label: Label = null
var authenticated_peer_id: int = 0
var elapsed_seconds: float = 0.0
var talk_sent: bool = false
var purchase_sent: bool = false
var item_bought: bool = false
var equip_sent: bool = false
var item_equipped: bool = false
var forgery_sent: bool = false
var forgery_done: bool = false
var _next_request_allowed_at: float = 0.0

const TEST_PORT: int = 7793
const VENDOR_NPC_ID: String = "vendor_grom"
const TRADED_ITEM_ID: String = "starter_sword"
const TRADED_ITEM_PRICE: int = 10
const STARTING_GOLD: int = 100


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
	game_data_registry["npcs"][VENDOR_NPC_ID]["spawn_position"] = [0.0, 0.0, 2.0]

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
	listener.npc_interact_requested.connect(_on_npc_interact_requested)
	listener.trade_requested.connect(_on_trade_requested)

	client_scene = load("res://client/scenes/main.tscn").instantiate()
	OS.set_environment("MMORPG3D_SERVER_PORT", str(TEST_PORT))
	add_child(client_scene)
	dialog_panel = client_scene.get_node("QuestCanvas/NpcDialogPanel")
	inventory_panel = client_scene.get_node("InventoryCanvas/InventoryPanel")
	status_label = client_scene.get_node("StatusCanvas/StatusPanel/StatusLabel")


func _process(delta: float) -> void:
	elapsed_seconds += delta
	listener.poll()
	if server_world.advance(delta):
		listener.broadcast_world_snapshots(server_world.create_snapshots())

	if authenticated_peer_id == 0:
		_finish_if_timeout()
		return

	if not talk_sent:
		if elapsed_seconds >= _next_request_allowed_at:
			_next_request_allowed_at = elapsed_seconds + 0.2
			client_scene.call("_request_nearest_npc")
		talk_sent = _dialog_has_buy_rows()
		_finish_if_timeout()
		return

	if not purchase_sent:
		if elapsed_seconds >= _next_request_allowed_at:
			_next_request_allowed_at = elapsed_seconds + 0.2
			purchase_sent = _try_buy_item()
		_finish_if_timeout()
		return

	if not item_bought:
		item_bought = _client_inventory_has(TRADED_ITEM_ID)
		_finish_if_timeout()
		return

	if not equip_sent:
		if elapsed_seconds >= _next_request_allowed_at:
			_next_request_allowed_at = elapsed_seconds + 0.2
			equip_sent = _try_equip_item()
		_finish_if_timeout()
		return

	if not item_equipped:
		item_equipped = _client_equipment_has(TRADED_ITEM_ID)
		if item_equipped and not _client_reports_bonus():
			push_error("The client does not show the bonus of the bought item")
			get_tree().quit(1)
			return
		_finish_if_timeout()
		return

	if not forgery_sent:
		if elapsed_seconds >= _next_request_allowed_at:
			_next_request_allowed_at = elapsed_seconds + 0.2
			_send_forged_request()
			forgery_sent = true
		_finish_if_timeout()
		return

	if not forgery_done:
		forgery_done = _forgery_was_rejected()
		_finish_if_timeout()
		return

	print("TRADE_LOOPBACK_OK")
	get_tree().quit(0)


## Checks whether the dialogue panel shows the assortment of the vendor.
func _dialog_has_buy_rows() -> bool:
	var buy_rows: VBoxContainer = dialog_panel.get_node("DialogRoot/BuyRows")
	return buy_rows.get_child_count() > 0


## Presses the buy button of the traded item.
func _try_buy_item() -> bool:
	var buy_rows: VBoxContainer = dialog_panel.get_node("DialogRoot/BuyRows")
	for row: Node in buy_rows.get_children():
		if not row is HBoxContainer:
			continue
		var row_children: Array = (row as HBoxContainer).get_children()
		if row_children.size() < 2:
			continue
		var label: Label = row_children[0]
		var buy_button: Button = row_children[1]
		if not label.text.contains(str(TRADED_ITEM_PRICE)):
			continue
		if buy_button.disabled:
			push_error("The buy button of the traded item is disabled")
			get_tree().quit(1)
			return true
		buy_button.pressed.emit()
		return true
	push_error("The dialogue panel does not offer the traded item")
	get_tree().quit(1)
	return true


## Presses the equip button of the bought item.
func _try_equip_item() -> bool:
	var inventory_rows: VBoxContainer = inventory_panel.get_node("PanelRoot/InventoryRows")
	for row: Node in inventory_rows.get_children():
		if not row is HBoxContainer:
			continue
		var row_children: Array = (row as HBoxContainer).get_children()
		if row_children.size() < 2:
			continue
		var action_button: Button = row_children[1]
		if action_button.disabled:
			continue
		action_button.pressed.emit()
		return true
	return false


## Sends a forged trade request that the server has to refuse.
##
## The request asks a quest giver for a weapon. The quest giver is not a
## vendor, so the server must reject it and leave the balance untouched.
func _send_forged_request() -> void:
	var packet: PackedByteArray = load("res://shared/protocol/packet_codec.gd").encode(
		load("res://shared/protocol/protocol_constants.gd").OPCODE_TRADE_REQUEST,
		{
			"npc_id": "quest_giver_mira",
			"action": "buy",
			"item_id": "battle_axe",
			"quantity": 1,
		},
	)
	listener.handle_packet(
		authenticated_peer_id,
		load("res://shared/protocol/protocol_constants.gd").EVENT_CHANNEL,
		packet,
	)


## Checks that the forged request did not change the balance.
func _forgery_was_rejected() -> bool:
	var snapshots: Dictionary = server_world.create_snapshots()
	if not snapshots.has(authenticated_peer_id):
		return false
	return int(snapshots[authenticated_peer_id]["gold"]) == STARTING_GOLD - TRADED_ITEM_PRICE


func _client_gold() -> int:
	return int(client_scene.get("_gold"))


func _client_inventory_has(item_id: String) -> bool:
	var inventory_state: Array = client_scene.get("_inventory_state")
	for entry: Variant in inventory_state:
		if entry is Dictionary and str(entry.get("item_id", "")) == item_id:
			return true
	return false


func _client_equipment_has(item_id: String) -> bool:
	var equipment_state: Dictionary = client_scene.get("_equipment_state")
	return str(equipment_state.get("weapon", "")) == item_id


## Checks that the inventory panel reports the bonus of the equipped item.
func _client_reports_bonus() -> bool:
	var bonuses_label: Label = inventory_panel.get_node("PanelRoot/BonusesLabel")
	return bonuses_label.text.contains("2")


func _finish_if_timeout() -> void:
	if elapsed_seconds > 20.0:
		print(
			"TRADE_STATE peer=%d talk=%s purchase=%s bought=%s equip=%s equipped=%s gold=%d status=%s"
			% [
				authenticated_peer_id,
				talk_sent,
				purchase_sent,
				item_bought,
				equip_sent,
				item_equipped,
				_client_gold(),
				status_label.text if status_label != null else "",
			]
		)
		push_error("TRADE_LOOPBACK_TIMEOUT")
		get_tree().quit(1)


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


func _on_npc_interact_requested(
	peer_id: int,
	npc_id: String,
	action: String,
	quest_id: String,
) -> void:
	listener.send_npc_interact_result(
		peer_id,
		server_world.interact_npc(peer_id, npc_id, action, quest_id),
	)


func _on_trade_requested(
	peer_id: int,
	npc_id: String,
	action: String,
	item_id: String,
	quantity: int,
) -> void:
	var result: Dictionary = server_world.trade(peer_id, npc_id, action, item_id, quantity)
	listener.send_trade_result(peer_id, result)
