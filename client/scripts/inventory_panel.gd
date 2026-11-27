extends PanelContainer

## Inventory and equipment panel.
##
## The panel renders the server-authoritative snapshot: equipped gear, carried
## items, their level requirements, and their stat bonuses. Every action is a
## request to the server; the panel never changes the local state on its own.
##
## The list of the carried items lives in a scroll container, so a full
## inventory is always reachable. The player selects an item with a click, and
## the panel under the list shows what is selected and offers the action for
## it. A double click acts on the item right away.
##
## The rows themselves are built by `InventoryRows`, so this file stays about
## the panel and not about every single cell of it.

signal equip_requested(item_id: String)
signal unequip_requested(slot_id: String)
signal use_item_requested(item_id: String)

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

const SCROLL_MINIMUM_SIZE: Vector2 = Vector2(280.0, 260.0)
const FONT_SIZE_TITLE: int = 15
const FONT_SIZE_SMALL: int = 11

var _item_definitions: Dictionary = {}
var _rows_builder: RefCounted = null
var _equipment_rows: VBoxContainer = null
var _inventory_rows: VBoxContainer = null
var _inventory_scroll: ScrollContainer = null
var _header_label: Label = null
var _bonuses_label: Label = null
var _selection_label: Label = null
var _selection_button: Button = null
var _selected_item_id: String = ""
var _selected_slot_id: String = ""
var _selected_level: int = 1
var _equipment_items: Dictionary = {}
var _render_signature: String = ""


func _ready() -> void:
	_ensure_layout()


## Provides the item registry used to render names, requirements, and bonuses.
func setup(item_definitions: Dictionary) -> void:
	_item_definitions = item_definitions
	_rows_builder = InventoryRows.new(self, _item_definitions)
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
	_selected_level = level
	_header_label.text = tr("inventory_panel_title") % level
	_render_equipment(equipment, level)
	_render_inventory(inventory, level)
	_render_bonuses(equipment)
	_render_selection()


## Selects an item of the inventory.
func select_item(item_id: String) -> void:
	_selected_item_id = item_id
	_selected_slot_id = ""
	_render_selection()


## Selects the item of an equipment slot.
func select_slot(slot_id: String) -> void:
	_selected_slot_id = slot_id
	_selected_item_id = ""
	_render_selection()


## Acts on an item of the inventory right away.
func activate_item(item_id: String) -> void:
	var item_definition: Dictionary = _item_definitions.get(item_id, {})
	if item_definition.is_empty():
		return
	if str(item_definition.get("item_type", "")) == "consumable":
		use_item_requested.emit(item_id)
		return
	equip_requested.emit(item_id)


## Builds the widget tree on demand so the panel also works when it is used
## outside the scene tree, for example in headless tests.
func _ensure_layout() -> void:
	if _equipment_rows != null:
		return
	if _rows_builder == null:
		_rows_builder = InventoryRows.new(self, _item_definitions)
	_build_layout()


func _build_layout() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "PanelRoot"
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_header_label = Label.new()
	_header_label.name = "HeaderLabel"
	_header_label.text = tr("inventory_panel_title") % 1
	_header_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	_header_label.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	root.add_child(_header_label)

	var gear_title: Label = Label.new()
	gear_title.name = "GearTitle"
	gear_title.text = tr("inventory_gear_title")
	gear_title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	gear_title.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	root.add_child(gear_title)

	_equipment_rows = VBoxContainer.new()
	_equipment_rows.name = "EquipmentRows"
	_equipment_rows.add_theme_constant_override("separation", 1)
	root.add_child(_equipment_rows)

	var inventory_title: Label = Label.new()
	inventory_title.name = "InventoryTitle"
	inventory_title.text = tr("inventory_items_title")
	inventory_title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	inventory_title.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	root.add_child(inventory_title)

	# The list of the items scrolls, so a full inventory is always reachable.
	_inventory_scroll = ScrollContainer.new()
	_inventory_scroll.name = "InventoryScroll"
	_inventory_scroll.custom_minimum_size = SCROLL_MINIMUM_SIZE
	_inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inventory_scroll.follow_focus = true
	_inventory_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_inventory_scroll)

	_inventory_rows = VBoxContainer.new()
	_inventory_rows.name = "InventoryRows"
	_inventory_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_rows.add_theme_constant_override("separation", 1)
	_inventory_scroll.add_child(_inventory_rows)

	_bonuses_label = Label.new()
	_bonuses_label.name = "BonusesLabel"
	_bonuses_label.text = tr("inventory_bonuses_empty")
	_bonuses_label.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	root.add_child(_bonuses_label)

	var selection_row: HBoxContainer = HBoxContainer.new()
	selection_row.name = "SelectionRow"
	selection_row.add_theme_constant_override("separation", 4)
	root.add_child(selection_row)

	_selection_label = Label.new()
	_selection_label.name = "SelectedLabel"
	_selection_label.text = tr("inventory_selected_empty")
	_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_label.clip_text = true
	_selection_label.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	selection_row.add_child(_selection_label)

	_selection_button = Button.new()
	_selection_button.name = "SelectedActionButton"
	_selection_button.text = tr("inventory_action_none")
	_selection_button.disabled = true
	_selection_button.add_theme_font_size_override("font_size", FONT_SIZE_SMALL)
	_selection_button.pressed.connect(_on_selection_action_pressed)
	selection_row.add_child(_selection_button)

	# The slots of the equipment are shown right away, so the panel never looks
	# broken before the first snapshot of the server arrives.
	_render_equipment({}, 1)


func _render_equipment(equipment: Dictionary, level: int) -> void:
	_clear_rows(_equipment_rows)
	_equipment_items.clear()
	for slot_id: String in GameDataRegistryType.EQUIPMENT_SLOTS:
		var item_id: String = str(equipment.get(slot_id, ""))
		_equipment_items[slot_id] = item_id
		_equipment_rows.add_child(
			_rows_builder.build_equipment_row(slot_id, item_id, level)
		)


func _render_inventory(inventory: Array, level: int) -> void:
	_clear_rows(_inventory_rows)
	if inventory.is_empty():
		var empty_label: Label = Label.new()
		empty_label.name = "EmptyLabel"
		empty_label.text = tr("inventory_empty")
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inventory_rows.add_child(empty_label)
		return
	for entry: Variant in inventory:
		if not entry is Dictionary:
			continue
		var item_id: String = str(entry.get("item_id", ""))
		var quantity: int = int(entry.get("quantity", 0))
		if _item_definitions.get(item_id, {}).is_empty():
			continue
		_inventory_rows.add_child(
			_rows_builder.build_item_row(
				item_id,
				quantity,
				level,
				item_id == _selected_item_id,
			)
		)


func _render_bonuses(equipment: Dictionary) -> void:
	var bonuses: String = _rows_builder.bonuses_text(equipment)
	if bonuses.is_empty():
		_bonuses_label.text = tr("inventory_bonuses_empty")
		return
	_bonuses_label.text = tr("inventory_bonuses") % bonuses


## Shows what the player selected and what can be done with it.
func _render_selection() -> void:
	if _selection_label == null:
		return
	if not _selected_slot_id.is_empty():
		var slot_item_id: String = str(_equipment_items.get(_selected_slot_id, ""))
		var equipped_item: Dictionary = _item_definitions.get(slot_item_id, {})
		_selection_label.text = tr("inventory_selected") % _selection_text(equipped_item)
		_selection_button.text = tr("inventory_action_unequip")
		_selection_button.disabled = slot_item_id.is_empty()
		return
	if not _selected_item_id.is_empty():
		var item_definition: Dictionary = _item_definitions.get(_selected_item_id, {})
		_selection_label.text = tr("inventory_selected") % _selection_text(item_definition)
		var is_consumable: bool = (
			str(item_definition.get("item_type", "")) == "consumable"
		)
		_selection_button.text = (
			tr("inventory_action_use") if is_consumable else tr("inventory_action_equip")
		)
		_selection_button.disabled = (
			not is_consumable
			and int(item_definition.get("level_requirement", 1)) > _selected_level
		)
		return
	_selection_label.text = tr("inventory_selected_empty")
	_selection_button.text = tr("inventory_action_none")
	_selection_button.disabled = true


## Builds the text of the selected item with its bonuses.
func _selection_text(item_definition: Dictionary) -> String:
	if item_definition.is_empty():
		return "?"
	var item_name: String = tr(item_definition.get("name_key", ""))
	var stats: String = _rows_builder.stats_text(item_definition)
	if stats.is_empty():
		return item_name
	return "%s (%s)" % [item_name, stats]


## Sends the request of the action of the selected item.
func _on_selection_action_pressed() -> void:
	if not _selected_slot_id.is_empty():
		unequip_requested.emit(_selected_slot_id)
		return
	if _selected_item_id.is_empty():
		return
	activate_item(_selected_item_id)


func _clear_rows(container: VBoxContainer) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
