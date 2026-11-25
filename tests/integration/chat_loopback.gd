extends Node

## End-to-end check for the chat and the party.
##
## The test starts the real server listener and world in-process, loads two
## production client scenes, and walks through the whole social loop: a zone
## message reaches the other player, an invitation creates a party, a party
## message reaches the members, and a party message does not reach a player
## that left the party.

var listener: RefCounted
var server_world: RefCounted
var client_a: Node = null
var client_b: Node = null
var panel_a: PanelContainer = null
var panel_b: PanelContainer = null
var elapsed_seconds: float = 0.0
var step: int = 0
var _next_request_allowed_at: float = 0.0
var _isolation_wait_started_at: float = 0.0
var _isolation_message_sent: bool = false

const TEST_PORT: int = 7794
const ZONE_MESSAGE: String = "hello zone"
const PARTY_MESSAGE: String = "hello party"
const ISOLATED_MESSAGE: String = "hello party again"


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

	listener = load("res://server/net/server_listener.gd").new()
	if not listener.start(TEST_PORT):
		get_tree().quit(1)
		return
	server_world = load("res://server/world/server_world.gd").new(
		simulation_config,
		game_data_registry,
	)
	listener.player_authenticated.connect(server_world.add_player)
	listener.player_named.connect(server_world.set_player_name)
	listener.player_disconnected.connect(server_world.remove_player)
	listener.chat_requested.connect(_on_chat_requested)
	listener.party_requested.connect(_on_party_requested)

	OS.set_environment("MMORPG3D_SERVER_PORT", str(TEST_PORT))
	client_a = load("res://client/scenes/main.tscn").instantiate()
	add_child(client_a)
	client_b = load("res://client/scenes/main.tscn").instantiate()
	add_child(client_b)
	panel_a = client_a.get_node("ChatCanvas/ChatPanel")
	panel_b = client_b.get_node("ChatCanvas/ChatPanel")


func _process(delta: float) -> void:
	elapsed_seconds += delta
	listener.poll()
	if server_world.advance(delta):
		listener.broadcast_world_snapshots(server_world.create_snapshots())

	match step:
		0:
			if _both_authenticated():
				step = 1
		1:
			# The first client writes a message into the chat and sends it.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.2
				_send_message(panel_a, "say", ZONE_MESSAGE)
			if panel_b.has_message_with_text(ZONE_MESSAGE):
				step = 2
		2:
			# The first client invites the second one into a party.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.2
				if not _press_invite_button(panel_a):
					_finish_with_error("The party section does not offer an invitation")
					return
			if panel_b.has_pending_invitation():
				step = 3
		3:
			# The second client accepts the invitation.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.2
				if not _press_accept_button(panel_b):
					_finish_with_error("The second client does not show the invitation")
					return
			if (
				panel_a.get_party_member_count() == 2
				and panel_b.get_party_member_count() == 2
			):
				step = 4
		4:
			# The first client writes a party message.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.2
				_press_channel_button(panel_a, "PartyButton")
				_send_message(panel_a, "party", PARTY_MESSAGE)
			if panel_b.has_message_with_text(PARTY_MESSAGE):
				step = 5
		5:
			# The second client leaves the party.
			if elapsed_seconds >= _next_request_allowed_at:
				_next_request_allowed_at = elapsed_seconds + 0.2
				if not _press_leave_button(panel_b):
					_finish_with_error("The party section does not offer the departure")
					return
			if not panel_b.is_in_party():
				step = 6
		6:
			# The first client writes another party message; the second client
			# is not a member anymore and must not receive it.
			if not _isolation_message_sent:
				if elapsed_seconds >= _next_request_allowed_at:
					_next_request_allowed_at = elapsed_seconds + 0.2
					_send_message(panel_a, "party", ISOLATED_MESSAGE)
					_isolation_message_sent = true
					_isolation_wait_started_at = elapsed_seconds
			elif elapsed_seconds - _isolation_wait_started_at > 1.0:
				if panel_b.has_message_with_text(ISOLATED_MESSAGE):
					_finish_with_error("A party message reached a player outside the party")
					return
				if not panel_a.has_message_with_text(ISOLATED_MESSAGE):
					_finish_with_error("The party message did not reach the party members")
					return
				step = 7
		7:
			print("CHAT_LOOPBACK_OK")
			get_tree().quit(0)
			return

	if elapsed_seconds > 25.0:
		_finish_with_error("CHAT_LOOPBACK_TIMEOUT")


## Reports whether both clients are connected.
func _both_authenticated() -> bool:
	var peer_a: int = int(client_a.get("_local_player_id"))
	var peer_b: int = int(client_b.get("_local_player_id"))
	return peer_a != 0 and peer_b != 0


## Writes a message into the chat input and sends it.
func _send_message(panel: PanelContainer, channel: String, text: String) -> void:
	var input: LineEdit = panel.get_node("ChatRoot/InputRow/Input")
	input.text = text
	var send_button: Button = panel.get_node("ChatRoot/InputRow/SendButton")
	send_button.pressed.emit()


## Presses a channel button of the chat panel.
func _press_channel_button(panel: PanelContainer, button_name: String) -> void:
	var channel_row: HBoxContainer = panel.get_node("ChatRoot/ChannelRow")
	var button: Button = _find_button(channel_row, button_name)
	if button == null:
		_finish_with_error("The chat panel does not offer the %s channel" % button_name)
		return
	button.pressed.emit()


## Presses the invitation button of the first other player.
func _press_invite_button(panel: PanelContainer) -> bool:
	var party_rows: VBoxContainer = panel.get_node("ChatRoot/PartyRows")
	var button: Button = _find_button(party_rows, "InviteButton")
	if button == null:
		return false
	button.pressed.emit()
	return true


## Presses the accept button of a pending invitation.
func _press_accept_button(panel: PanelContainer) -> bool:
	var invite_row: HBoxContainer = panel.get_node("ChatRoot/InviteRow")
	var button: Button = _find_button(invite_row, "AcceptInviteButton")
	if button == null:
		return false
	button.pressed.emit()
	return true


## Presses the leave button of the party section.
func _press_leave_button(panel: PanelContainer) -> bool:
	var party_rows: VBoxContainer = panel.get_node("ChatRoot/PartyRows")
	var button: Button = _find_button(party_rows, "LeavePartyButton")
	if button == null:
		return false
	button.pressed.emit()
	return true


## Finds a button with the given name in a container.
func _find_button(container: Node, button_name: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and (child as Button).name == button_name:
			return child
		if child is Container:
			var found: Button = _find_button(child, button_name)
			if found != null:
				return found
	return null


## Ends the test with an error.
func _finish_with_error(message: String) -> void:
	push_error(message)
	get_tree().quit(1)


func _on_chat_requested(peer_id: int, channel: String, text: String) -> void:
	var result: Dictionary = server_world.chat(peer_id, channel, text)
	if not bool(result["accepted"]):
		listener.send_chat_message(peer_id, {
			"channel": "system",
			"sender_peer_id": 0,
			"sender_name": "",
			"text": "",
			"system_key": "",
			"reason": str(result["reason"]),
		})
		return
	var message: Dictionary = result["message"]
	for recipient_id: int in result["recipients"]:
		listener.send_chat_message(recipient_id, message)


func _on_party_requested(
	peer_id: int,
	action: String,
	target_peer_id: int,
) -> void:
	var result: Dictionary = server_world.party_request(
		peer_id,
		action,
		target_peer_id,
	)
	listener.send_party_result(peer_id, result)
	for notification: Dictionary in result["notifications"]:
		listener.send_party_result(int(notification["peer_id"]), notification["result"])
	for chat_message: Dictionary in result["chat_messages"]:
		for recipient_id: int in chat_message["recipients"]:
			listener.send_chat_message(recipient_id, chat_message["message"])
