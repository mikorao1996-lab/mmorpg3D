extends PanelContainer

## NPC dialogue panel.
##
## The panel renders the quest list of an NPC exactly as the server reported it
## and only sends accept and turn-in requests. The server decides whether the
## quest can be accepted or handed in.

signal accept_quest_requested(npc_id: String, quest_id: String)
signal turn_in_quest_requested(npc_id: String, quest_id: String)

var _npc_id: String = ""
var _title_label: Label = null
var _dialogue_label: Label = null
var _quest_rows: VBoxContainer = null
var _item_definitions: Dictionary = {}
var _mob_definitions: Dictionary = {}


func _ready() -> void:
	_ensure_layout()
	hide()


## Provides the registries used to render quest objectives and rewards.
func setup(
	item_definitions: Dictionary,
	mob_definitions: Dictionary,
) -> void:
	_item_definitions = item_definitions
	_mob_definitions = mob_definitions


## Shows the dialogue of an NPC with its quest list.
func show_npc(
	npc_id: String,
	name_key: String,
	dialogue_key: String,
	quests: Array,
) -> void:
	_ensure_layout()
	_npc_id = npc_id
	_title_label.text = tr(name_key) if not name_key.is_empty() else tr("dialogue_title")
	_dialogue_label.text = tr(dialogue_key) if not dialogue_key.is_empty() else ""
	_render_quests(quests)
	show()


## Hides the panel and forgets the current NPC.
func hide_panel() -> void:
	_npc_id = ""
	hide()


func _ensure_layout() -> void:
	if _quest_rows != null:
		return
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "DialogRoot"
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = tr("dialogue_title")
	root.add_child(_title_label)

	_dialogue_label = Label.new()
	_dialogue_label.name = "DialogueLabel"
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.custom_minimum_size = Vector2(420.0, 0.0)
	root.add_child(_dialogue_label)

	_quest_rows = VBoxContainer.new()
	_quest_rows.name = "QuestRows"
	_quest_rows.add_theme_constant_override("separation", 4)
	root.add_child(_quest_rows)


func _render_quests(quests: Array) -> void:
	for child: Node in _quest_rows.get_children():
		_quest_rows.remove_child(child)
		child.queue_free()
	for entry: Variant in quests:
		if not entry is Dictionary:
			continue
		var quest_id: String = str(entry.get("quest_id", ""))
		var status: String = str(entry.get("status", "available"))
		var row: HBoxContainer = HBoxContainer.new()
		var description: Label = Label.new()
		description.name = "QuestLabel"
		description.text = _build_quest_text(entry)
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(description)

		var action_button: Button = Button.new()
		action_button.name = "ActionButton"
		match status:
			"available":
				action_button.text = tr("quest_action_accept")
				action_button.pressed.connect(
					_on_accept_pressed.bind(quest_id)
				)
			"completed":
				action_button.text = tr("quest_action_turn_in")
				action_button.pressed.connect(
					_on_turn_in_pressed.bind(quest_id)
				)
			_:
				action_button.text = tr("quest_status_" + status)
				action_button.disabled = true
		row.add_child(action_button)
		_quest_rows.add_child(row)


func _build_quest_text(entry: Dictionary) -> String:
	var quest_name: String = tr(str(entry.get("name_key", "")))
	var objective_type: String = str(entry.get("objective_type", ""))
	var objective_target: String = str(entry.get("objective_target", ""))
	var progress: int = int(entry.get("progress", 0))
	var objective_count: int = int(entry.get("objective_count", 1))
	var objective_text: String = _build_objective_text(objective_type, objective_target)
	var reward_items: Array = entry.get("reward_item_ids", [])
	var reward_names: PackedStringArray = []
	for item_id: String in reward_items:
		var item_definition: Dictionary = _item_definitions.get(item_id, {})
		reward_names.append(tr(str(item_definition.get("name_key", item_id))))
	var reward_text: String = tr("quest_reward_line") % [
		int(entry.get("reward_experience", 0)),
		", ".join(reward_names),
	]
	return "%s — %s (%d/%d)\n%s" % [
		quest_name,
		objective_text,
		progress,
		objective_count,
		reward_text,
	]


func _build_objective_text(objective_type: String, objective_target: String) -> String:
	match objective_type:
		"kill":
			var mob_definition: Dictionary = _mob_definitions.get(objective_target, {})
			return tr("quest_objective_kill") % tr(
				str(mob_definition.get("name_key", objective_target))
			)
		"collect":
			var item_definition: Dictionary = _item_definitions.get(objective_target, {})
			return tr("quest_objective_collect") % tr(
				str(item_definition.get("name_key", objective_target))
			)
		"talk":
			return tr("quest_objective_talk")
	return objective_target


func _on_accept_pressed(quest_id: String) -> void:
	accept_quest_requested.emit(_npc_id, quest_id)


func _on_turn_in_pressed(quest_id: String) -> void:
	turn_in_quest_requested.emit(_npc_id, quest_id)
