class_name TradeSystem
extends RefCounted

## Server-authoritative trading rules.
##
## A client request only names the NPC, the action, the item, and the quantity.
## The price always comes from the vendor registry, so a client cannot change
## what an item costs. Every check runs before the balance or the inventory is
## touched: a rejected trade leaves both of them exactly as they were.

const ACTION_BUY: String = "buy"
const ACTION_SELL: String = "sell"
const ACTIONS: PackedStringArray = [ACTION_BUY, ACTION_SELL]
const MAX_QUANTITY: int = 20


## Finds the vendor that belongs to an NPC, or an empty dictionary.
static func find_vendor(vendor_definitions: Dictionary, npc_id: String) -> Dictionary:
	for vendor: Dictionary in vendor_definitions.values():
		if str(vendor["npc_id"]) == npc_id:
			return vendor
	return {}


## Builds the assortment of a vendor for the talk response.
##
## The client renders these entries, but the prices are only ever used for
## display; the trade itself always reads the price from the registry again.
static func build_assortment(vendor: Dictionary) -> Array:
	var assortment: Array = []
	for entry: Dictionary in vendor.get("items", []):
		assortment.append({
			"item_id": str(entry["item_id"]),
			"buy_price": int(entry["buy_price"]),
			"sell_price": int(entry["sell_price"]),
		})
	return assortment


## Finds the traded item inside the assortment of a vendor.
static func find_assortment_entry(vendor: Dictionary, item_id: String) -> Dictionary:
	for entry: Dictionary in vendor.get("items", []):
		if str(entry["item_id"]) == item_id:
			return entry
	return {}


## Executes a buy or a sell request.
##
## The result reports `accepted`, `reason`, the traded `item_id`, the
## `quantity`, the unit `price`, and the resulting `gold` balance.
static func trade(
	player_state: Dictionary,
	vendor: Dictionary,
	action: String,
	item_id: String,
	quantity: int,
	item_definitions: Dictionary,
) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"action": action,
		"item_id": item_id,
		"quantity": quantity,
		"price": 0,
		"gold": int(player_state.get("gold", 0)),
	}
	if not ACTIONS.has(action):
		result["reason"] = "invalid_action"
		return result
	if vendor.is_empty():
		result["reason"] = "not_a_vendor"
		return result
	if quantity < 1 or quantity > MAX_QUANTITY:
		result["reason"] = "invalid_quantity"
		return result
	var assortment_entry: Dictionary = find_assortment_entry(vendor, item_id)
	if assortment_entry.is_empty():
		result["reason"] = "item_not_traded"
		return result
	if not item_definitions.has(item_id):
		result["reason"] = "unknown_item"
		return result
	var inventory: InventoryComponent = player_state["inventory"]
	if action == ACTION_BUY:
		return _buy(
			player_state,
			inventory,
			assortment_entry,
			item_id,
			quantity,
			item_definitions,
			result,
		)
	return _sell(player_state, inventory, assortment_entry, item_id, quantity, result)


## Buys an item from the vendor.
static func _buy(
	player_state: Dictionary,
	inventory: InventoryComponent,
	assortment_entry: Dictionary,
	item_id: String,
	quantity: int,
	item_definitions: Dictionary,
	result: Dictionary,
) -> Dictionary:
	var price: int = int(assortment_entry["buy_price"])
	result["price"] = price
	if price <= 0:
		result["reason"] = "item_not_for_sale"
		return result
	var item_definition: Dictionary = item_definitions[item_id]
	# A level-locked item is not purchasable at all, so the level requirement is
	# checked before the balance.
	if int(item_definition.get("level_requirement", 1)) > int(player_state["level"]):
		result["reason"] = "level_requirement"
		return result
	var total_price: int = price * quantity
	var gold: int = int(player_state.get("gold", 0))
	if gold < total_price:
		result["reason"] = "insufficient_gold"
		return result
	if not inventory.can_accept_items(_build_item_list(item_id, quantity), item_definitions):
		result["reason"] = "inventory_full"
		return result

	var added_count: int = 0
	for _index: int in range(quantity):
		var add_result: Dictionary = inventory.add_item(item_id, item_definition)
		if not bool(add_result.get("ok", false)):
			# The capacity check passed, so this only happens on a broken
			# inventory. The partial delivery is rolled back before the trade
			# is rejected.
			for _rollback_index: int in range(added_count):
				inventory.remove_item(item_id)
			result["reason"] = str(add_result.get("reason", "inventory_error"))
			return result
		added_count += 1
	player_state["gold"] = gold - total_price
	result["accepted"] = true
	result["gold"] = int(player_state["gold"])
	return result


## Sells an item to the vendor.
static func _sell(
	player_state: Dictionary,
	inventory: InventoryComponent,
	assortment_entry: Dictionary,
	item_id: String,
	quantity: int,
	result: Dictionary,
) -> Dictionary:
	var price: int = int(assortment_entry["sell_price"])
	result["price"] = price
	if price <= 0:
		result["reason"] = "item_not_accepted"
		return result
	if inventory.get_item_count(item_id) < quantity:
		result["reason"] = "item_not_in_inventory"
		return result
	for _index: int in range(quantity):
		inventory.remove_item(item_id)
	var gold: int = int(player_state.get("gold", 0))
	player_state["gold"] = gold + price * quantity
	result["accepted"] = true
	result["gold"] = int(player_state["gold"])
	return result


## Builds the item list used to simulate the inventory space a trade needs.
static func _build_item_list(item_id: String, quantity: int) -> Array:
	var item_ids: Array = []
	for _index: int in range(quantity):
		item_ids.append(item_id)
	return item_ids
