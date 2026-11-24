class_name EquipmentComponent
extends RefCounted

const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

var _items: Dictionary = {}


func _init() -> void:
	for slot_id: String in GameDataRegistryType.EQUIPMENT_SLOTS:
		_items[slot_id] = ""


func has_slot(slot_id: String) -> bool:
	return _items.has(slot_id)


func get_item_id(slot_id: String) -> String:
	return str(_items.get(slot_id, ""))


func set_item_id(slot_id: String, item_id: String) -> bool:
	if not _items.has(slot_id):
		return false
	_items[slot_id] = item_id
	return true


func get_equipped_item_ids() -> Dictionary:
	return _items.duplicate(true)


func get_snapshot() -> Dictionary:
	return _items.duplicate(true)
