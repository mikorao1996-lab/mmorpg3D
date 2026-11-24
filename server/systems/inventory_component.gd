class_name InventoryComponent
extends RefCounted

var _slot_capacity: int
var _slots: Array[Dictionary] = []


func _init(slot_capacity: int) -> void:
	_slot_capacity = slot_capacity


func add_item(item_id: String, item_definition: Dictionary) -> Dictionary:
	var stack_limit_value: Variant = item_definition.get("stack_limit", null)
	var stack_limit_number: float = 0.0
	if typeof(stack_limit_value) == TYPE_INT or typeof(stack_limit_value) == TYPE_FLOAT:
		stack_limit_number = float(stack_limit_value)
	if (
		item_id.strip_edges().is_empty()
		or not is_finite(stack_limit_number)
		or stack_limit_number < 1.0
		or stack_limit_number != floor(stack_limit_number)
	):
		return {"ok": false, "reason": "invalid_item"}

	var stack_limit: int = int(stack_limit_number)
	var updated_slots: Array[Dictionary] = []
	for slot: Dictionary in _slots:
		updated_slots.append(slot.duplicate(true))

	for slot_index: int in range(updated_slots.size()):
		var slot: Dictionary = updated_slots[slot_index]
		if slot["item_id"] != item_id or int(slot["quantity"]) >= stack_limit:
			continue
		slot["quantity"] = int(slot["quantity"]) + 1
		updated_slots[slot_index] = slot
		_slots = updated_slots
		return {"ok": true, "reason": ""}

	if updated_slots.size() >= _slot_capacity:
		return {"ok": false, "reason": "inventory_full"}
	updated_slots.append({"item_id": item_id, "quantity": 1})
	_slots = updated_slots
	return {"ok": true, "reason": ""}


func remove_item(item_id: String) -> Dictionary:
	for slot_index: int in range(_slots.size()):
		if _slots[slot_index]["item_id"] != item_id:
			continue
		if int(_slots[slot_index]["quantity"]) == 1:
			_slots.remove_at(slot_index)
		else:
			_slots[slot_index]["quantity"] = int(_slots[slot_index]["quantity"]) - 1
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "item_not_in_inventory"}


## Reports whether at least one unit of the item is held.
func has_item(item_id: String) -> bool:
	for slot: Dictionary in _slots:
		if slot["item_id"] == item_id:
			return true
	return false


func get_snapshot() -> Array:
	var snapshot: Array = []
	for slot: Dictionary in _slots:
		snapshot.append([slot["item_id"], slot["quantity"]])
	return snapshot
