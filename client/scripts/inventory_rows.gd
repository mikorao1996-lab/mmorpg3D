class_name InventoryRows
extends RefCounted

## Builds the rows of the inventory panel.
##
## A row of the equipment holds the name of the slot and the item in it. A row
## of the inventory holds the item and the action for it. Both are compact:
## the rarity of the item is a colored border on the left, the name of the
## item is the text of the button, and the action is the button on the right.

const STAT_KEYS: PackedStringArray = ["attack", "defense", "health", "resource"]

## The colors of the items follow the level that is needed to use them, so the
## rarity of an item is readable without opening it.
const RARITY_COLOR_COMMON: Color = Color(0.74, 0.74, 0.74)
const RARITY_COLOR_FINE: Color = Color(0.45, 0.82, 0.45)
const RARITY_COLOR_RARE: Color = Color(0.42, 0.62, 0.95)
const RARITY_COLOR_EPIC: Color = Color(0.74, 0.46, 0.95)

const COLOR_SELECTED_FRAME: Color = Color(0.95, 0.8, 0.45, 0.95)
const COLOR_SELECTED_FILL: Color = Color(0.16, 0.15, 0.12, 0.95)

const ACTION_MINIMUM_SIZE: Vector2 = Vector2(66.0, 0.0)
const FONT_SIZE_BODY: int = 13
const FONT_SIZE_SMALL: int = 11

var _panel: PanelContainer = null
var _item_definitions: Dictionary = {}


func _init(panel: PanelContainer, item_definitions: Dictionary) -> void:
	_panel = panel
	_item_definitions = item_definitions


## Builds a row of the equipment.
##
## The name of the slot lets the pointer through, so the wheel of the mouse
## still reaches the list under it, and a click on it selects the item.
func build_equipment_row(slot_id: String, item_id: String, level: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var slot_label: Label = Label.new()
	slot_label.name = "SlotLabel"
	slot_label.text = tr("equipment_slot_" + slot_id)
	slot_label.custom_minimum_size = Vector2(86.0, 0.0)
	slot_label.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	slot_label.mouse_filter = Control.MOUSE_FILTER_PASS
	slot_label.gui_input.connect(_on_slot_label_input.bind(slot_id))
	row.add_child(slot_label)

	var item_button: Button = Button.new()
	item_button.name = "ItemButton"
	item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_button.clip_text = true
	item_button.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	if item_id.is_empty():
		item_button.text = tr("inventory_slot_empty")
		item_button.disabled = true
	else:
		var item_definition: Dictionary = _item_definitions.get(item_id, {})
		item_button.text = tr(item_definition.get("name_key", item_id))
		item_button.tooltip_text = item_tooltip(item_id, level)
		item_button.add_theme_color_override(
			"font_color",
			rarity_color(int(item_definition.get("level_requirement", 1))),
		)
		item_button.pressed.connect(_on_unequip_pressed.bind(slot_id))
	row.add_child(item_button)
	return row


## Builds a row of the inventory.
##
## The button of the item is the selection: a click selects it, a double click
## acts on it right away.
func build_item_row(
	item_id: String,
	quantity: int,
	level: int,
	selected: bool,
) -> HBoxContainer:
	var item_definition: Dictionary = _item_definitions.get(item_id, {})
	var is_consumable: bool = str(item_definition.get("item_type", "")) == "consumable"
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var rarity: Color = rarity_color(int(item_definition.get("level_requirement", 1)))
	var item_button: Button = Button.new()
	item_button.name = "ItemButton"
	item_button.text = item_label(item_id, quantity, level)
	item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_button.clip_text = true
	item_button.tooltip_text = item_tooltip(item_id, level)
	item_button.add_theme_color_override("font_color", rarity)
	item_button.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	item_button.add_theme_stylebox_override("normal", rarity_style(rarity, selected))
	item_button.add_theme_stylebox_override("hover", rarity_style(rarity, selected))
	item_button.add_theme_stylebox_override("pressed", rarity_style(rarity, selected))
	# The selection is shown with a frame, so the focus needs no outline of
	# its own.
	item_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	item_button.pressed.connect(_on_item_pressed.bind(item_id))
	item_button.gui_input.connect(_on_item_gui_input.bind(item_id))
	row.add_child(item_button)

	var action_button: Button = Button.new()
	action_button.name = "ActionButton"
	action_button.text = (
		tr("inventory_action_use") if is_consumable else tr("inventory_action_equip")
	)
	action_button.custom_minimum_size = ACTION_MINIMUM_SIZE
	action_button.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	action_button.disabled = (
		not is_consumable
		and int(item_definition.get("level_requirement", 1)) > level
	)
	if is_consumable:
		action_button.pressed.connect(_on_use_pressed.bind(item_id))
	else:
		action_button.pressed.connect(_on_equip_pressed.bind(item_id))
	row.add_child(action_button)
	return row


## Returns the color of an item by the level that is needed to use it.
func rarity_color(level_requirement: int) -> Color:
	if level_requirement >= 6:
		return RARITY_COLOR_EPIC
	if level_requirement >= 4:
		return RARITY_COLOR_RARE
	if level_requirement >= 2:
		return RARITY_COLOR_FINE
	return RARITY_COLOR_COMMON


## Builds the style of an item, so the rarity is visible in the list.
func rarity_style(color: Color, selected: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	# The background of a flat style box is opaque by default, and it would
	# cover the whole row of the list.
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_width_left = 3
	style.border_color = color
	style.content_margin_left = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	if not selected:
		return style
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = COLOR_SELECTED_FRAME
	style.bg_color = COLOR_SELECTED_FILL
	return style


## Builds the text of a row of the inventory.
func item_label(item_id: String, quantity: int, level: int) -> String:
	var item_definition: Dictionary = _item_definitions.get(item_id, {})
	var item_name: String = tr(item_definition.get("name_key", item_id))
	var text: String = "%s x%d" % [item_name, quantity]
	var requirement: int = int(item_definition.get("level_requirement", 1))
	if requirement > level:
		text += tr("inventory_level_required") % requirement
	return text


## Builds the tooltip of an item.
func item_tooltip(item_id: String, level: int) -> String:
	var item_definition: Dictionary = _item_definitions.get(item_id, {})
	var item_name: String = tr(item_definition.get("name_key", item_id))
	var requirement: int = int(item_definition.get("level_requirement", 1))
	var lines: PackedStringArray = [item_name]
	lines.append(tr("inventory_tooltip_level") % requirement)
	var slot_id: String = str(item_definition.get("equipment_slot", ""))
	if not slot_id.is_empty():
		lines.append(tr("equipment_slot_" + slot_id))
	var stats: String = stats_text(item_definition)
	if not stats.is_empty():
		lines.append(stats)
	if requirement > level:
		lines.append(tr("inventory_tooltip_locked") % requirement)
	return "\n".join(lines)


## Builds the text of the bonuses of an item.
func stats_text(item_definition: Dictionary) -> String:
	var item_stats: Dictionary = item_definition.get("stats", {})
	var parts: PackedStringArray = []
	for stat_name: String in STAT_KEYS:
		var value: float = float(item_stats.get(stat_name, 0.0))
		if value <= 0.0:
			continue
		parts.append("%s %s" % [tr("stat_" + stat_name), format_stat_value(value)])
	return ", ".join(parts)


## Builds the text of the bonuses of the whole equipment.
func bonuses_text(equipment: Dictionary) -> String:
	var totals: Dictionary = {
		"attack": 0.0,
		"defense": 0.0,
		"health": 0.0,
		"resource": 0.0,
	}
	for item_id: Variant in equipment.values():
		if str(item_id).is_empty():
			continue
		var item_definition: Dictionary = _item_definitions.get(item_id, {})
		var item_stats: Dictionary = item_definition.get("stats", {})
		for stat_name: String in STAT_KEYS:
			totals[stat_name] += float(item_stats.get(stat_name, 0.0))
	var parts: PackedStringArray = []
	for stat_name: String in STAT_KEYS:
		var value: float = float(totals[stat_name])
		if value <= 0.0:
			continue
		parts.append("%s %s" % [tr("stat_" + stat_name), format_stat_value(value)])
	return ", ".join(parts)


## Formats the value of a bonus.
func format_stat_value(value: float) -> String:
	if value == floor(value):
		return str(int(value))
	return "%.1f" % value


func _on_equip_pressed(item_id: String) -> void:
	_panel.equip_requested.emit(item_id)


func _on_unequip_pressed(slot_id: String) -> void:
	_panel.unequip_requested.emit(slot_id)


func _on_use_pressed(item_id: String) -> void:
	_panel.use_item_requested.emit(item_id)


func _on_item_pressed(item_id: String) -> void:
	_panel.call("select_item", item_id)


func _on_item_gui_input(event: InputEvent, item_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event
	if not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not mouse_event.double_click:
		return
	_panel.call("activate_item", item_id)


## Selects the item of an equipment slot.
func _on_slot_label_input(event: InputEvent, slot_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event
	if not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	_panel.call("select_slot", slot_id)
