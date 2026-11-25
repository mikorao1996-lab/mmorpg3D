extends RefCounted

## Checks the server-authoritative trading rules.
##
## The tests cover a successful buy and sell, the rejections of a trade that
## the server has to refuse, and the guarantee that a rejected trade leaves the
## balance and the inventory untouched.

const TradeSystemType: GDScript = preload("res://server/systems/trade_system.gd")
const InventoryComponentType: GDScript = preload("res://server/systems/inventory_component.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")


func run() -> bool:
	var registries: Dictionary = GameDataRegistryType.load_all()
	if registries.is_empty():
		return false
	var vendors: Dictionary = registries["vendors"]
	if not vendors.has("vendor_grom"):
		push_error("The vendor registry does not define the training vendor")
		return false
	var vendor: Dictionary = vendors["vendor_grom"]
	var item_definitions: Dictionary = registries["items"]

	var player_state: Dictionary = {
		"gold": 100,
		"level": 1,
		"inventory": InventoryComponentType.new(20),
	}
	var inventory: InventoryComponent = player_state["inventory"]

	var buy_result: Dictionary = TradeSystemType.trade(
		player_state,
		vendor,
		"buy",
		"starter_sword",
		1,
		item_definitions,
	)
	if not bool(buy_result.get("accepted", false)):
		push_error("The server rejected a valid purchase")
		return false
	if int(buy_result.get("price", 0)) != 10:
		push_error("The purchase did not use the price of the vendor registry")
		return false
	if int(player_state["gold"]) != 90:
		push_error("The purchase did not debit the price from the balance")
		return false
	if inventory.get_item_count("starter_sword") != 1:
		push_error("The purchase did not deliver the item")
		return false

	var stack_result: Dictionary = TradeSystemType.trade(
		player_state,
		vendor,
		"buy",
		"minor_potion",
		10,
		item_definitions,
	)
	if not bool(stack_result.get("accepted", false)):
		push_error("The server rejected a valid stack purchase")
		return false
	if int(player_state["gold"]) != 40:
		push_error("The stack purchase did not debit the total price")
		return false
	if inventory.get_item_count("minor_potion") != 10:
		push_error("The stack purchase did not deliver every potion")
		return false

	player_state["gold"] = 40
	var too_expensive: Dictionary = TradeSystemType.trade(
		player_state,
		vendor,
		"buy",
		"minor_potion",
		10,
		item_definitions,
	)
	if bool(too_expensive.get("accepted", false)):
		push_error("The server accepted a purchase the player cannot afford")
		return false
	if str(too_expensive.get("reason", "")) != "insufficient_gold":
		push_error("An unaffordable purchase did not report insufficient gold")
		return false
	if int(player_state["gold"]) != 40:
		push_error("A rejected purchase changed the balance")
		return false

	player_state["gold"] = 500
	var too_high_level: Dictionary = TradeSystemType.trade(
		player_state,
		vendor,
		"buy",
		"iron_helm",
		1,
		item_definitions,
	)
	if bool(too_high_level.get("accepted", false)):
		push_error("The server accepted an item above the character level")
		return false
	if str(too_high_level.get("reason", "")) != "level_requirement":
		push_error("A locked purchase did not report the level requirement")
		return false
	if int(player_state["gold"]) != 500:
		push_error("A rejected purchase changed the balance")
		return false
	player_state["gold"] = 40

	var sell_result: Dictionary = TradeSystemType.trade(
		player_state,
		vendor,
		"sell",
		"starter_sword",
		1,
		item_definitions,
	)
	if not bool(sell_result.get("accepted", false)):
		push_error("The server rejected a valid sale")
		return false
	if int(sell_result.get("price", 0)) != 2:
		push_error("The sale did not use the price of the vendor registry")
		return false
	if int(player_state["gold"]) != 42:
		push_error("The sale did not credit the balance")
		return false
	if inventory.get_item_count("starter_sword") != 0:
		push_error("The sale did not remove the item")
		return false

	var sell_missing: Dictionary = TradeSystemType.trade(
		player_state,
		vendor,
		"sell",
		"battle_axe",
		1,
		item_definitions,
	)
	if bool(sell_missing.get("accepted", false)):
		push_error("The server accepted a sale of an item the player does not own")
		return false
	if str(sell_missing.get("reason", "")) != "item_not_in_inventory":
		push_error("A sale of a missing item did not report the missing item")
		return false

	var sell_quest_item: Dictionary = TradeSystemType.trade(
		player_state,
		vendor,
		"sell",
		"slime_gel",
		1,
		item_definitions,
	)
	if bool(sell_quest_item.get("accepted", false)):
		push_error("The server accepted a sale of an item that is not traded")
		return false
	if str(sell_quest_item.get("reason", "")) != "item_not_traded":
		push_error("A sale of an untraded item did not report the wrong assortment")
		return false

	var not_a_vendor: Dictionary = TradeSystemType.trade(
		player_state,
		{},
		"buy",
		"starter_sword",
		1,
		item_definitions,
	)
	if bool(not_a_vendor.get("accepted", false)):
		push_error("The server accepted a trade with an NPC that does not trade")
		return false
	if str(not_a_vendor.get("reason", "")) != "not_a_vendor":
		push_error("A trade with a non-vendor NPC did not report the missing vendor")
		return false

	var invalid_action: Dictionary = TradeSystemType.trade(
		player_state,
		vendor,
		"rob",
		"starter_sword",
		1,
		item_definitions,
	)
	if bool(invalid_action.get("accepted", false)):
		push_error("The server accepted an unknown trade action")
		return false
	if str(invalid_action.get("reason", "")) != "invalid_action":
		push_error("An unknown trade action did not report the invalid action")
		return false

	for invalid_quantity: int in [0, -1, TradeSystemType.MAX_QUANTITY + 1]:
		var invalid_quantity_result: Dictionary = TradeSystemType.trade(
			player_state,
			vendor,
			"buy",
			"starter_sword",
			invalid_quantity,
			item_definitions,
		)
		if bool(invalid_quantity_result.get("accepted", false)):
			push_error("The server accepted an invalid trade quantity")
			return false
		if str(invalid_quantity_result.get("reason", "")) != "invalid_quantity":
			push_error("An invalid trade quantity did not report the invalid quantity")
			return false

	var full_inventory_state: Dictionary = {
		"gold": 100,
		"level": 1,
		"inventory": InventoryComponentType.new(1),
	}
	var full_result: Dictionary = TradeSystemType.trade(
		full_inventory_state,
		vendor,
		"buy",
		"starter_sword",
		2,
		item_definitions,
	)
	if bool(full_result.get("accepted", false)):
		push_error("The server accepted a purchase that does not fit into the inventory")
		return false
	if str(full_result.get("reason", "")) != "inventory_full":
		push_error("A purchase without inventory space did not report the full inventory")
		return false
	if int(full_inventory_state["gold"]) != 100:
		push_error("A rejected purchase debited the balance")
		return false

	var assortment: Array = TradeSystemType.build_assortment(vendor)
	if assortment.size() != (vendor["items"] as Array).size():
		push_error("The vendor assortment does not match the registry")
		return false
	for entry: Dictionary in assortment:
		if not entry.has("item_id") or not entry.has("buy_price"):
			push_error("The vendor assortment is missing the price information")
			return false
	return true
