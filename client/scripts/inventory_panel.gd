extends PanelContainer

## Inventory and equipment panel.
##
## The panel renders the server-authoritative snapshot: equipped gear, carried
## items, their level requirements, and their stat bonuses. Every action is a
## request to the server; the panel never changes the local state on its own.

signal equip_requested(item_id: String)
signal unequip_requested(slot_id: String)
signal use_item_requested(item_id: String)

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const STAT_KEYS: PackedStringArray = ["attack", "defense", "health", "resource"]

## The colors of the items follow the level that is needed to use them, so the
## rarity of an item is readable without opening it.
const RARITY_COLOR_COMMON: Color = Color(0.74, 0.74, 0.74)
const RARITY_COLOR_FINE: Color = Color(0.45, 0.82, 0.45)
const RARITY_COLOR_RARE: Color = Color(0.42, 0.62, 0.95)
const RARITY_COLOR_EPIC: Color = Color(0.74, 0.46, 0.95)

var _item_definitions: Dictionary = {}
var _equipment_rows: VBoxContainer = null
var _inventory_rows: VBoxContainer = null
var _header_label: Label = null
var _bonuses_label: Label = null
var _render_signature: String = ""


func _ready() -> void:
	_ensure_layout()


## Provides the item registry used to render names, requirements, and bonuses.
func setup(item_definitions: Dictionary) -> void:
	_item_definitions = item_definitions
	_ensure_layout()
	_render_signature = ""


## Rebuilds the panel when the server state changed.
func update_view(
	inventory: Array,
	equipment: Dictionary,
	level: int,
) -> void:
	_ensure_layout()
	var signature: String = "%d|%s|%s" % [level, str(inventory), str(equipment)]
	if signature == _render_signature:
		return
	_render_signature = signature
	_header_label.text = tr("inventory_panel_title") % level
	_render_equipment(equipment, level)
	_render_inventory(inventory, level)
	_render_bonuses(equipment)


## Builds the widget tree on demand so the panel also works when it is used
## outside the scene tree, for example in headless tests.
func _ensure_layout() -> void:
	if _equipment_rows != null:
		return
	_build_layout()


func _build_layout() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "PanelRoot"
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_header_label = Label.new()
	_header_label.name = "HeaderLabel"
	_header_label.text = tr("inventory_panel_title") % 1
	_header_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	_header_label.add_theme_font_size_override("font_size", 17)
	root.add_child(_header_label)

	var gear_title: Label = Label.new()
	gear_title.name = "GearTitle"
	gear_title.text = tr("inventory_gear_title")
	gear_title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	root.add_child(gear_title)

	_equipment_rows = VBoxContainer.new()
	_equipment_rows.name = "EquipmentRows"
	_equipment_rows.add_theme_constant_override("separation", 2)
	root.add_child(_equipment_rows)

	var inventory_title: Label = Label.new()
	inventory_title.name = "InventoryTitle"
	inventory_title.text = tr("inventory_items_title")
	inventory_title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	root.add_child(inventory_title)

	_inventory_rows = VBoxContainer.new()
	_inventory_rows.name = "InventoryRows"
	_inventory_rows.add_theme_constant_override("separation", 2)
	root.add_child(_inventory_rows)

	_bonuses_label = Label.new()
	_bonuses_label.name = "BonusesLabel"
	_bonuses_label.text = tr("inventory_bonuses_empty")
	root.add_child(_bonuses_label)


## Returns the color of an item by the level that is needed to use it.
func _rarity_color(level_requirement: int) -> Color:
	if level_requirement >= 6:
		return RARITY_COLOR_EPIC
	if level_requirement >= 4:
		return RARITY_COLOR_RARE
	if level_requirement >= 2:
		return RARITY_COLOR_FINE
	return RARITY_COLOR_COMMON


## Builds the style of an item, so the rarity is visible in the list.
func _build_rarity_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.border_width_left = 3
	style.border_color = color
	style.content_margin_left = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


func _render_equipment(equipment: Dictionary, level: int) -> void:
	_clear_rows(_equipment_rows)
	for slot_id: String in GameDataRegistryType.EQUIPMENT_SLOTS:
		var item_id: String = str(equipment.get(slot_id, ""))
		var row: HBoxContainer = HBoxContainer.new()
		var slot_label: Label = Label.new()
		slot_label.name = "SlotLabel"
		slot_label.text = tr("equipment_slot_" + slot_id)
		slot_label.custom_minimum_size = Vector2(90.0, 0.0)
		row.add_child(slot_label)

		var item_button: Button = Button.new()
		item_button.name = "ItemButton"
		item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if item_id.is_empty():
			item_button.text = tr("inventory_slot_empty")
			item_button.disabled = true
		else:
			var item_definition: Dictionary = _item_definitions.get(item_id, {})
			item_button.text = tr(item_definition.get("name_key", item_id))
			item_button.tooltip_text = _build_item_tooltip(item_id, level)
			item_button.add_theme_color_override(
				"font_color",
				_rarity_color(int(item_definition.get("level_requirement", 1))),
			)
			item_button.pressed.connect(_on_unequip_pressed.bind(slot_id))
		row.add_child(item_button)
		_equipment_rows.add_child(row)


func _render_inventory(inventory: Array, level: int) -> void:
	_clear_rows(_inventory_rows)
	if inventory.is_empty():
		var empty_label: Label = Label.new()
		empty_label.name = "EmptyLabel"
		empty_label.text = tr("inventory_empty")
		_inventory_rows.add_child(empty_label)
		return
	for entry: Variant in inventory:
		if not entry is Dictionary:
			continue
		var item_id: String = str(entry.get("item_id", ""))
		var quantity: int = int(entry.get("quantity", 0))
		var item_definition: Dictionary = _item_definitions.get(item_id, {})
		if item_definition.is_empty():
			continue
		var is_consumable: bool = (
			str(item_definition.get("item_type", "")) == "consumable"
		)
		var row: HBoxContainer = HBoxContainer.new()
		var item_label: Label = Label.new()
		item_label.name = "ItemLabel"
		item_label.text = _build_item_label(item_id, quantity, level)
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_label.tooltip_text = _build_item_tooltip(item_id, level)
		var rarity_color: Color = _rarity_color(
			int(item_definition.get("level_requirement", 1))
		)
		item_label.add_theme_stylebox_override("normal", _build_rarity_style(rarity_color))
		item_label.add_theme_color_override("font_color", rarity_color)
		row.add_child(item_label)

		var action_button: Button = Button.new()
		action_button.name = "ActionButton"
		action_button.text = (
			tr("inventory_action_use") if is_consumable else tr("inventory_action_equip")
		)
		action_button.disabled = (
			not is_consumable
			and int(item_definition.get("level_requirement", 1)) > level
		)
		if is_consumable:
			action_button.pressed.connect(_on_use_pressed.bind(item_id))
		else:
			action_button.pressed.connect(_on_equip_pressed.bind(item_id))
		row.add_child(action_button)
		_inventory_rows.add_child(row)


func _render_bonuses(equipment: Dictionary) -> void:
	var totals: Dictionary = {
		"attack": 0.0,
		"defense": 0.0,
		"health": 0.0,
		"resource": 0.0,
	}
	for item_id: String in equipment.values():
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
		parts.append("%s %s" % [tr("stat_" + stat_name), _format_stat_value(value)])
	if parts.is_empty():
		_bonuses_label.text = tr("inventory_bonuses_empty")
		return
	_bonuses_label.text = tr("inventory_bonuses") % ", ".join(parts)


func _build_item_label(item_id: String, quantity: int, level: int) -> String:
	var item_definition: Dictionary = _item_definitions.get(item_id, {})
	var item_name: String = tr(item_definition.get("name_key", item_id))
	var text: String = "%s x%d" % [item_name, quantity]
	var requirement: int = int(item_definition.get("level_requirement", 1))
	if requirement > level:
		text += tr("inventory_level_required") % requirement
	return text


func _build_item_tooltip(item_id: String, level: int) -> String:
	var item_definition: Dictionary = _item_definitions.get(item_id, {})
	var item_name: String = tr(item_definition.get("name_key", item_id))
	var requirement: int = int(item_definition.get("level_requirement", 1))
	var lines: PackedStringArray = [item_name]
	lines.append(tr("inventory_tooltip_level") % requirement)
	var slot_id: String = str(item_definition.get("equipment_slot", ""))
	if not slot_id.is_empty():
		lines.append(tr("equipment_slot_" + slot_id))
	var stats_text: String = _build_stats_text(item_definition)
	if not stats_text.is_empty():
		lines.append(stats_text)
	if requirement > level:
		lines.append(tr("inventory_tooltip_locked") % requirement)
	return "\n".join(lines)


func _build_stats_text(item_definition: Dictionary) -> String:
	var item_stats: Dictionary = item_definition.get("stats", {})
	var parts: PackedStringArray = []
	for stat_name: String in STAT_KEYS:
		var value: float = float(item_stats.get(stat_name, 0.0))
		if value <= 0.0:
			continue
		parts.append("%s %s" % [tr("stat_" + stat_name), _format_stat_value(value)])
	return ", ".join(parts)


func _format_stat_value(value: float) -> String:
	if value == floor(value):
		return str(int(value))
	return "%.1f" % value


func _clear_rows(container: VBoxContainer) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_equip_pressed(item_id: String) -> void:
	equip_requested.emit(item_id)


func _on_unequip_pressed(slot_id: String) -> void:
	unequip_requested.emit(slot_id)


func _on_use_pressed(item_id: String) -> void:
	use_item_requested.emit(item_id)
