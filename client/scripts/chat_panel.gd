extends PanelContainer

## Chat and party panel.
##
## The panel renders the messages the server sent, keeps the chat history, and
## sends requests. The server decides whether a message is accepted and who
## receives it, so the panel only renders what it received.

signal chat_message_requested(channel: String, text: String)
signal party_invite_requested(target_peer_id: int)
signal party_invite_responded(accepted: bool)
signal party_leave_requested()

const CHANNEL_SAY: String = "say"
const CHANNEL_PARTY: String = "party"
const FILTER_ALL: String = "all"
const FILTER_SYSTEM: String = "system"
const BACKGROUND_ALPHA_IDLE: float = 0.62
const BACKGROUND_ALPHA_ACTIVE: float = 0.92

const COLOR_SAY: String = "#d7e3f4"
const COLOR_PARTY: String = "#8fd6a0"
const COLOR_SYSTEM: String = "#9aa4b2"

var _history_size: int = 30
var _active_channel: String = CHANNEL_SAY
var _messages: Array[Dictionary] = []
var _party_state: Dictionary = {}
var _local_peer_id: int = 0
var _zone_players: Array[int] = []
var _pending_invite: Dictionary = {}

var _history_label: RichTextLabel = null
var _channel_label: Label = null
var _say_button: Button = null
var _party_button: Button = null
var _all_button: Button = null
var _system_button: Button = null
var _input: LineEdit = null
var _send_button: Button = null
var _party_label: Label = null
var _party_rows: VBoxContainer = null
var _invite_row: HBoxContainer = null
var _history_filter: String = FILTER_ALL


func _ready() -> void:
	_ensure_layout()


## Provides the chat limits of the simulation config.
func setup(config: Dictionary) -> void:
	_history_size = int(config.get("chat_history_size", 30))
	_ensure_layout()


## Sets the player the panel belongs to.
func set_local_peer(peer_id: int) -> void:
	_local_peer_id = peer_id


## Sets the peers of the players in the zone of the player.
func set_zone_players(peer_ids: Array) -> void:
	_zone_players.clear()
	for peer_id: Variant in peer_ids:
		_zone_players.append(int(peer_id))
	_render_party()


## Adds a message of the server to the history.
func add_message(message: Dictionary) -> void:
	_messages.append(message)
	while _messages.size() > _history_size:
		_messages.pop_front()
	_render_history()


## Updates the party state of the player.
func set_party_state(party_id: int, leader_peer_id: int, members: Array) -> void:
	_party_state = {
		"party_id": party_id,
		"leader_peer_id": leader_peer_id,
		"members": members.duplicate(),
	}
	_render_party()


## Clears the party state of the player.
func clear_party_state() -> void:
	_party_state = {}
	_render_party()


## Shows the invitation of another player.
func show_invitation(inviter_peer_id: int, inviter_name: String) -> void:
	_pending_invite = {
		"inviter_peer_id": inviter_peer_id,
		"inviter_name": inviter_name,
	}
	_render_party()


## Returns the channel the input line sends to.
func get_active_channel() -> String:
	return _active_channel


func _ensure_layout() -> void:
	if _history_label != null:
		return
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "ChatRoot"
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_channel_label = Label.new()
	_channel_label.name = "ChannelLabel"
	_channel_label.text = tr("chat_channel_zone")
	root.add_child(_channel_label)

	_history_label = RichTextLabel.new()
	_history_label.name = "HistoryLabel"
	_history_label.bbcode_enabled = true
	_history_label.scroll_following = true
	_history_label.custom_minimum_size = Vector2(440.0, 150.0)
	_history_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_history_label)

	var channel_row: HBoxContainer = HBoxContainer.new()
	channel_row.name = "ChannelRow"
	_say_button = Button.new()
	_say_button.name = "SayButton"
	_say_button.text = tr("chat_channel_zone")
	_say_button.pressed.connect(_on_channel_pressed.bind(CHANNEL_SAY))
	channel_row.add_child(_say_button)
	_party_button = Button.new()
	_party_button.name = "PartyButton"
	_party_button.text = tr("chat_channel_party")
	_party_button.pressed.connect(_on_channel_pressed.bind(CHANNEL_PARTY))
	channel_row.add_child(_party_button)
	root.add_child(channel_row)

	var filter_row: HBoxContainer = HBoxContainer.new()
	filter_row.name = "FilterRow"
	_all_button = Button.new()
	_all_button.name = "AllButton"
	_all_button.text = tr("chat_filter_all")
	_all_button.pressed.connect(_on_filter_pressed.bind(FILTER_ALL))
	filter_row.add_child(_all_button)
	_system_button = Button.new()
	_system_button.name = "SystemButton"
	_system_button.text = tr("chat_filter_system")
	_system_button.pressed.connect(_on_filter_pressed.bind(FILTER_SYSTEM))
	filter_row.add_child(_system_button)
	root.add_child(filter_row)

	var input_row: HBoxContainer = HBoxContainer.new()
	input_row.name = "InputRow"
	_input = LineEdit.new()
	_input.name = "Input"
	_input.placeholder_text = tr("chat_input_placeholder")
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_input_submitted)
	input_row.add_child(_input)
	_send_button = Button.new()
	_send_button.name = "SendButton"
	_send_button.text = tr("chat_action_send")
	_send_button.pressed.connect(_on_send_pressed)
	input_row.add_child(_send_button)
	root.add_child(input_row)

	_party_label = Label.new()
	_party_label.name = "PartyLabel"
	_party_label.text = tr("party_none")
	root.add_child(_party_label)

	_party_rows = VBoxContainer.new()
	_party_rows.name = "PartyRows"
	_party_rows.add_theme_constant_override("separation", 2)
	root.add_child(_party_rows)

	_invite_row = HBoxContainer.new()
	_invite_row.name = "InviteRow"
	root.add_child(_invite_row)

	_render_history()
	_render_party()
	_apply_background(BACKGROUND_ALPHA_IDLE)
	mouse_entered.connect(_on_panel_hover_entered)
	mouse_exited.connect(_on_panel_hover_exited)
	_input.focus_entered.connect(_on_panel_hover_entered)
	_input.focus_exited.connect(_on_panel_hover_exited)


## Darkens the background of the panel.
##
## The panel is almost transparent while the player reads the world, and it
## becomes solid while the pointer or the input line is on it.
func _apply_background(alpha: float) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, alpha)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.45, 0.28, 0.55)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)


func _on_panel_hover_entered() -> void:
	_apply_background(BACKGROUND_ALPHA_ACTIVE)


func _on_panel_hover_exited() -> void:
	_apply_background(BACKGROUND_ALPHA_IDLE)


## Shows only the messages of the chosen filter.
func _on_filter_pressed(filter: String) -> void:
	_history_filter = filter
	_all_button.disabled = filter == FILTER_ALL
	_system_button.disabled = filter == FILTER_SYSTEM
	_render_history()


## Renders the chat history.
func _render_history() -> void:
	if _history_label == null:
		return
	var lines: PackedStringArray = []
	for message: Dictionary in _messages:
		if _history_filter == FILTER_SYSTEM:
			var channel: String = str(message.get("channel", "system"))
			if channel != "system" and str(message.get("reason", "")).is_empty():
				continue
		lines.append(_format_message(message))
	_history_label.text = "\n".join(lines)


## Formats a single message for the history.
func _format_message(message: Dictionary) -> String:
	var channel: String = str(message.get("channel", "system"))
	var system_key: String = str(message.get("system_key", ""))
	var reason: String = str(message.get("reason", ""))
	if not reason.is_empty():
		return "[color=%s]%s[/color]" % [COLOR_SYSTEM, _format_reason(reason)]
	if channel == "system":
		var system_text: String = tr(system_key) % [str(message.get("sender_name", ""))]
		return "[color=%s]%s[/color]" % [COLOR_SYSTEM, system_text]
	var sender_name: String = str(message.get("sender_name", ""))
	var prefix: String = tr("chat_prefix_say")
	var color: String = COLOR_SAY
	if channel == CHANNEL_PARTY:
		prefix = tr("chat_prefix_party")
		color = COLOR_PARTY
	return "[color=%s]%s %s:[/color] %s" % [
		color,
		prefix,
		sender_name,
		str(message.get("text", "")),
	]


## Formats the reason of a rejected request.
##
## The chat and the party use separate key namespaces; a reason without a
## translation falls back to a generic message.
func _format_reason(reason: String) -> String:
	var reason_key: String = "chat_reason_" + reason
	if reason.begins_with("party_"):
		reason_key = "party_reason_" + reason
	var reason_text: String = tr(reason_key)
	if reason_text == reason_key:
		return tr("chat_reason_generic")
	return reason_text


## Renders the party section.
func _render_party() -> void:
	if _party_label == null:
		return
	for child: Node in _party_rows.get_children():
		_party_rows.remove_child(child)
		child.queue_free()
	for child: Node in _invite_row.get_children():
		_invite_row.remove_child(child)
		child.queue_free()

	if not _pending_invite.is_empty():
		_invite_row.add_child(_build_label(
			tr("party_invitation") % str(_pending_invite.get("inviter_name", ""))
		))
		var accept_button: Button = Button.new()
		accept_button.name = "AcceptInviteButton"
		accept_button.text = tr("party_action_accept")
		accept_button.pressed.connect(_on_invite_responded.bind(true))
		_invite_row.add_child(accept_button)
		var decline_button: Button = Button.new()
		decline_button.name = "DeclineInviteButton"
		decline_button.text = tr("party_action_decline")
		decline_button.pressed.connect(_on_invite_responded.bind(false))
		_invite_row.add_child(decline_button)

	if _party_state.is_empty():
		_party_label.text = tr("party_none")
	else:
		var member_names: PackedStringArray = []
		for member: Variant in _party_state["members"]:
			if not member is Dictionary:
				continue
			var member_entry: Dictionary = member
			var name: String = str(member_entry.get("name", ""))
			if bool(member_entry.get("is_leader", false)):
				name += tr("party_leader_suffix")
			member_names.append(name)
		_party_label.text = tr("party_members") % ", ".join(member_names)

	if not _party_state.is_empty():
		var leave_button: Button = Button.new()
		leave_button.name = "LeavePartyButton"
		leave_button.text = tr("party_action_leave")
		leave_button.pressed.connect(_on_leave_party_pressed)
		_party_rows.add_child(leave_button)

	if _local_peer_id == 0:
		return
	var can_invite: bool = (
		_party_state.is_empty()
		or int(_party_state["leader_peer_id"]) == _local_peer_id
	)
	if not can_invite:
		return
	for peer_id: int in _zone_players:
		if peer_id == _local_peer_id:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		row.add_child(_build_label(tr("party_invite_target") % peer_id))
		var invite_button: Button = Button.new()
		invite_button.name = "InviteButton"
		invite_button.text = tr("party_action_invite")
		invite_button.pressed.connect(_on_invite_pressed.bind(peer_id))
		row.add_child(invite_button)
		_party_rows.add_child(row)


## Builds a label with the given text.
func _build_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label


## Switches the channel the input line sends to.
func _on_channel_pressed(channel: String) -> void:
	_active_channel = channel
	_channel_label.text = tr("chat_channel_zone") if channel == CHANNEL_SAY else tr(
		"chat_channel_party"
	)


## Sends the text of the input line.
func _on_send_pressed() -> void:
	_send_input_text()


## Sends the text of the input line after the enter key.
func _on_input_submitted(_text: String) -> void:
	_send_input_text()


## Emits the request for the text of the input line.
func _send_input_text() -> void:
	var text: String = _input.text.strip_edges()
	if text.is_empty():
		return
	_input.text = ""
	chat_message_requested.emit(_active_channel, text)


## Emits the request to invite another player.
func _on_invite_pressed(target_peer_id: int) -> void:
	party_invite_requested.emit(target_peer_id)


## Emits the answer of the player on an invitation.
func _on_invite_responded(accepted: bool) -> void:
	_pending_invite = {}
	_render_party()
	party_invite_responded.emit(accepted)


## Emits the request to leave the party.
func _on_leave_party_pressed() -> void:
	party_leave_requested.emit()


## Returns the messages of the chat history.
func get_messages() -> Array:
	return _messages.duplicate()


## Reports whether an invitation is waiting for an answer.
func has_pending_invitation() -> bool:
	return not _pending_invite.is_empty()


## Reports whether the player belongs to a party.
func is_in_party() -> bool:
	return not _party_state.is_empty()


## Returns the number of members of the party of the player.
func get_party_member_count() -> int:
	if _party_state.is_empty():
		return 0
	return (_party_state["members"] as Array).size()


## Reports whether the chat input has the focus.
##
## The client uses it to stop the movement keys while a message is written.
func is_input_focused() -> bool:
	return _input != null and _input.has_focus()


## Reports whether the history contains a message with the given text.
func has_message_with_text(text: String) -> bool:
	for message: Dictionary in _messages:
		if str(message.get("text", "")) == text:
			return true
	return false
