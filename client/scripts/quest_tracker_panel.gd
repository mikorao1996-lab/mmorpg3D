extends PanelContainer

## Quest tracker.
##
## Shows the quests of the local player from the world snapshot: the objective,
## the progress, and the status. The tracker never changes the quest state; it
## only renders what the server reported.

var _title_label: Label = null
var _quest_rows: VBoxContainer = null
var _item_definitions: Dictionary = {}
var _mob_definitions: Dictionary = {}
var _render_signature: String = ""


func _ready() -> void:
	_ensure_layout()


## Provides the registries used to render quest objectives.
func setup(
	item_definitions: Dictionary,
	mob_definitions: Dictionary,
) -> void:
	_item_definitions = item_definitions
	_mob_definitions = mob_definitions
	_render_signature = ""


## Rebuilds the tracker when the quest state changed.
func update_view(quests: Array) -> void:
	_ensure_layout()
	var signature: String = str(quests)
	if signature == _render_signature:
		return
	_render_signature = signature
	_render_quests(quests)


func _ensure_layout() -> void:
	if _quest_rows != null:
		return
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "TrackerRoot"
	root.add_theme_constant_override("separation", 2)
	add_child(root)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = tr("quest_tracker_title")
	root.add_child(_title_label)

	_quest_rows = VBoxContainer.new()
	_quest_rows.name = "QuestRows"
	_quest_rows.add_theme_constant_override("separation", 2)
	root.add_child(_quest_rows)


func _render_quests(quests: Array) -> void:
	for child: Node in _quest_rows.get_children():
		_quest_rows.remove_child(child)
		child.queue_free()
	if quests.is_empty():
		var empty_label: Label = Label.new()
		empty_label.name = "EmptyLabel"
		empty_label.text = tr("quest_tracker_empty")
		_quest_rows.add_child(empty_label)
		return
	for entry: Variant in quests:
		if not entry is Array or entry.size() < 7:
			continue
		var quest_name: String = tr(str(entry[4]))
		var objective_text: String = _build_objective_text(str(entry[5]), str(entry[6]))
		var status: String = str(entry[1])
		var row: Label = Label.new()
		row.name = "QuestLabel"
		row.text = "%s — %s (%d/%d) %s" % [
			quest_name,
			objective_text,
			int(entry[2]),
			int(entry[3]),
			tr("quest_status_" + status),
		]
		_quest_rows.add_child(row)


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
