extends Node

## End-to-end check for the NPC and quest loop.
##
## The test starts the real server listener and world in-process, loads the
## production client scene, and walks through the full quest cycle: talk to the
## NPC, accept the quest, kill the target mob, and hand the quest in. Every
## step goes through the network, the server stays authoritative, and the
## client only renders what it receives.

var listener: RefCounted
var server_world: RefCounted
var client_scene: Node = null
var dialog_panel: PanelContainer = null
var tracker_panel: PanelContainer = null
var status_label: Label = null
var authenticated_peer_id: int = 0
var elapsed_seconds: float = 0.0
var talk_sent: bool = false
var quest_accepted: bool = false
var kills_done: int = 0
var quest_completed: bool = false
var turn_in_sent: bool = false
var turn_in_finished: bool = false
var _next_request_allowed_at: float = 0.0

const TEST_PORT: int = 7792
const MIRA_ID: String = "quest_giver_mira"
const QUEST_ID: String = "slime_problem"
const TARGET_MOB_ID: String = "training_slime"


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
	game_data_registry["mobs"]["training_slime"]["respawn_seconds"] = 0.3
	game_data_registry["mobs"]["training_slime"]["aggro_range"] = 0.0
	# The slime is placed next to the spawn point, so the cast is in range.
	game_data_registry["mobs"]["training_slime"]["spawn_positions"] = [[0.0, 0.0, -2.0]]
	game_data_registry["abilities"]["starter_slash"]["cooldown_seconds"] = 0.0
	game_data_registry["abilities"]["starter_slash"]["resource_cost"] = 0.0
	game_data_registry["npcs"][MIRA_ID]["spawn_position"] = [0.0, 0.0, 2.0]

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

	client_scene = load("res://client/scenes/main.tscn").instantiate()
	OS.set_environment("MMORPG3D_SERVER_PORT", str(TEST_PORT))
	add_child(client_scene)
	dialog_panel = client_scene.get_node("QuestCanvas/NpcDialogPanel")
	tracker_panel = client_scene.get_node("QuestCanvas/QuestTrackerPanel")
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
		talk_sent = _dialog_has_quest_rows()
		_finish_if_timeout()
		return

	if not quest_accepted:
		if elapsed_seconds >= _next_request_allowed_at:
			_next_request_allowed_at = elapsed_seconds + 0.2
			_try_accept_quest()
		quest_accepted = _tracker_has_active_quest()
		_finish_if_timeout()
		return

	if kills_done < 3:
		_try_kill_target()
		_finish_if_timeout()
		return

	if not quest_completed:
		quest_completed = _tracker_reports_completion()
		_finish_if_timeout()
		return

	if not turn_in_finished:
		if elapsed_seconds >= _next_request_allowed_at:
			_next_request_allowed_at = elapsed_seconds + 0.2
			_try_turn_in_quest()
		turn_in_finished = _check_turn_in_result()
		_finish_if_timeout()
		return

	print("QUEST_LOOPBACK_OK")
	get_tree().quit(0)


func _dialog_has_quest_rows() -> bool:
	var quest_rows: VBoxContainer = dialog_panel.get_node("DialogRoot/QuestRows")
	return quest_rows.get_child_count() > 0


func _tracker_has_active_quest() -> bool:
	var quest_rows: VBoxContainer = dialog_panel.get_node("DialogRoot/QuestRows")
	if quest_rows.get_child_count() == 0:
		return false
	var row: HBoxContainer = quest_rows.get_child(0)
	var action_button: Button = row.get_child(1)
	return action_button.disabled


func _finish_if_timeout() -> void:
	if elapsed_seconds > 20.0:
		print(
			"QUEST_STATE peer=%d talk=%s accepted=%s kills=%d completed=%s turned_in=%s status=%s"
			% [
				authenticated_peer_id,
				talk_sent,
				quest_accepted,
				kills_done,
				quest_completed,
				turn_in_finished,
				status_label.text if status_label != null else "",
			]
		)
		push_error("QUEST_LOOPBACK_TIMEOUT")
		get_tree().quit(1)


## Presses the accept button of the quest row in the dialogue panel.
func _try_accept_quest() -> void:
	var quest_rows: VBoxContainer = dialog_panel.get_node("DialogRoot/QuestRows")
	if quest_rows.get_child_count() == 0:
		return
	var row: HBoxContainer = quest_rows.get_child(0)
	var action_button: Button = row.get_child(1)
	if action_button.disabled:
		return
	action_button.pressed.emit()
	quest_accepted = true


## Kills the target mob and waits for it to respawn before the next kill.
func _try_kill_target() -> void:
	var kill_result: Dictionary = server_world.cast_ability(
		authenticated_peer_id,
		"starter_slash",
		TARGET_MOB_ID,
	)
	if not bool(kill_result.get("accepted", false)):
		return
	kills_done += 1


## Checks whether the quest tracker reports the finished quest.
func _tracker_reports_completion() -> bool:
	var quest_rows: VBoxContainer = tracker_panel.get_node("TrackerRoot/QuestRows")
	for row: Node in quest_rows.get_children():
		if row is Label and (row as Label).text.contains("(3/3)"):
			return true
	return false


## Talks to the NPC again and hands the finished quest in.
func _try_turn_in_quest() -> void:
	client_scene.call("_request_nearest_npc")
	var quest_rows: VBoxContainer = dialog_panel.get_node("DialogRoot/QuestRows")
	if quest_rows.get_child_count() == 0:
		return
	for row: Node in quest_rows.get_children():
		if not row is HBoxContainer:
			continue
		var action_button: Button = (row as HBoxContainer).get_child(1)
		if action_button.disabled:
			continue
		action_button.pressed.emit()
		turn_in_sent = true
		return


## Checks the status message that the client received for the hand-in.
func _check_turn_in_result() -> bool:
	return status_label.text.contains("25")


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
