extends RefCounted

## Headless coverage for the client inventory panel.
##
## The panel renders the server snapshot, so the test checks that the rows are
## built, that the level requirement gates the equip action, and that the
## buttons request the server action instead of changing local state.

const InventoryPanelType: GDScript = preload("res://client/scripts/inventory_panel.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

var _tree_root: Node = null
var _equip_requests: Array[String] = []
var _unequip_requests: Array[String] = []
var _use_requests: Array[String] = []


func _init(tree_root: Node = null) -> void:
	_tree_root = tree_root


func run() -> bool:
	if _tree_root == null:
		push_error("Inventory panel test requires a scene tree root")
		return false
	var registries: Dictionary = GameDataRegistryType.load_all()
	if registries.is_empty():
		return false

	var panel: PanelContainer = InventoryPanelType.new()
	_tree_root.add_child(panel)
	panel.equip_requested.connect(func(item_id: String) -> void: _equip_requests.append(item_id))
	panel.unequip_requested.connect(
		func(slot_id: String) -> void: _unequip_requests.append(slot_id)
	)
	panel.use_item_requested.connect(func(item_id: String) -> void: _use_requests.append(item_id))
	panel.setup(registries["items"])

	var equipment: Dictionary = {
		"weapon": "starter_sword",
		"head": "",
		"chest": "",
		"hands": "",
		"legs": "",
		"feet": "",
	}
	var inventory: Array = [
		{"item_id": "minor_potion", "quantity": 2},
		{"item_id": "iron_sword", "quantity": 1},
	]
	panel.update_view(inventory, equipment, 1)

	var equipment_rows: VBoxContainer = panel.get_node("PanelRoot/EquipmentRows")
	var scroll: ScrollContainer = panel.get_node("PanelRoot/InventoryScroll")
	var inventory_rows: VBoxContainer = panel.get_node("PanelRoot/InventoryScroll/InventoryRows")
	if scroll.custom_minimum_size.y <= 0.0:
		push_error("The inventory list has no height to scroll in")
		return false
	if scroll.mouse_filter != Control.MOUSE_FILTER_STOP:
		push_error("The inventory list must take the wheel of the mouse")
		return false
	if not scroll.follow_focus:
		push_error("The inventory list must follow the focused item")
		return false
	if equipment_rows.get_child_count() != 6:
		push_error("Inventory panel did not render all six equipment slots")
		return false
	if inventory_rows.get_child_count() != 2:
		push_error("Inventory panel did not render every inventory stack")
		return false

	var potion_row: HBoxContainer = inventory_rows.get_child(0)
	var sword_row: HBoxContainer = inventory_rows.get_child(1)
	var potion_button: Button = potion_row.get_child(1)
	var sword_button: Button = sword_row.get_child(1)
	if potion_button.disabled:
		push_error("Inventory panel disabled a consumable that is always usable")
		return false
	if not sword_button.disabled:
		push_error("Inventory panel allowed equipping an item above the character level")
		return false

	panel.update_view(inventory, equipment, 4)
	sword_button = (inventory_rows.get_child(1) as HBoxContainer).get_child(1)
	if sword_button.disabled:
		push_error("Inventory panel kept an item locked after the level requirement was met")
		return false

	potion_button.pressed.emit()
	sword_button.pressed.emit()
	if _use_requests != ["minor_potion"]:
		push_error("Inventory panel did not request the consumable use")
		return false
	if _equip_requests != ["iron_sword"]:
		push_error("Inventory panel did not request the equip action")
		return false

	var equipped_button: Button = (
		equipment_rows.get_child(0) as HBoxContainer
	).get_child(1)
	equipped_button.pressed.emit()
	if _unequip_requests != ["weapon"]:
		push_error("Inventory panel did not request the unequip action")
		return false

	# Selecting an item shows it in the status line and opens its action.
	var item_button: Button = potion_row.get_node("ItemButton")
	item_button.pressed.emit()
	var selection_label: Label = panel.get_node("PanelRoot/SelectionRow/SelectedLabel")
	var selection_button: Button = panel.get_node(
		"PanelRoot/SelectionRow/SelectedActionButton"
	)
	if selection_label.text == tr("inventory_selected_empty"):
		push_error("The inventory panel did not show the selected item")
		return false
	if selection_button.disabled:
		push_error("The inventory panel did not offer the action of the selected item")
		return false
	selection_button.pressed.emit()
	if _use_requests != ["minor_potion", "minor_potion"]:
		push_error("The inventory panel did not use the selected item")
		return false

	# A full inventory has to be reachable with the wheel of the mouse.
	var full_inventory: Array = []
	for index: int in range(30):
		full_inventory.append({"item_id": "minor_potion", "quantity": index + 1})
	panel.update_view(full_inventory, equipment, 4)
	var full_rows: VBoxContainer = panel.get_node(
		"PanelRoot/InventoryScroll/InventoryRows"
	)
	if full_rows.get_child_count() != 30:
		push_error("The inventory panel did not render a full inventory")
		return false
	if full_rows.get_combined_minimum_size().y <= scroll.custom_minimum_size.y:
		push_error("A full inventory has to be taller than the visible list")
		return false
	if scroll.get_v_scroll_bar() == null:
		push_error("The inventory list has no scroll bar")
		return false
	return true
