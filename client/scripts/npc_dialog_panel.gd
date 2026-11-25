extends PanelContainer

## NPC dialogue and trade panel.
##
## The panel renders the quest list and the assortment of a vendor exactly as
## the server reported them and only sends requests. The server decides whether
## a quest can be accepted or handed in and what a trade costs, so the prices
## shown here are display values only.

signal accept_quest_requested(npc_id: String, quest_id: String)
signal turn_in_quest_requested(npc_id: String, quest_id: String)
signal trade_requested(npc_id: String, action: String, item_id: String, quantity: int)

const STACK_PURCHASE_QUANTITY: int = 10

var _npc_id: String = ""
var _title_label: Label = null
var _dialogue_label: Label = null
var _quest_rows: VBoxContainer = null
var _trade_title_label: Label = null
var _gold_label: Label = null
var _buy_rows: VBoxContainer = null
var _sell_rows: VBoxContainer = null
var _item_definitions: Dictionary = {}
var _mob_definitions: Dictionary = {}
var _vendor_items: Array = []
var _inventory: Array = []
var _gold: int = 0
var _level: int = 1


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


## Shows the dialogue of an NPC with its quest list and its trade section.
##
## The vendor items are empty for an NPC that is not a vendor, so the trade
## section is hidden in that case.
func show_npc(
	npc_id: String,
	name_key: String,
	dialogue_key: String,
	quests: Array,
	vendor_items: Array = [],
	inventory: Array = [],
	gold: int = 0,
	level: int = 1,
) -> void:
	_ensure_layout()
	_npc_id = npc_id
	_vendor_items = vendor_items.duplicate()
	_inventory = inventory.duplicate()
	_gold = gold
	_level = level
	_title_label.text = tr(name_key) if not name_key.is_empty() else tr("dialogue_title")
	_dialogue_label.text = tr(dialogue_key) if not dialogue_key.is_empty() else ""
	_render_quests(quests)
	_render_trade()
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

	_trade_title_label = Label.new()
	_trade_title_label.name = "TradeTitle"
	_trade_title_label.text = tr("trade_title")
	root.add_child(_trade_title_label)

	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.text = tr("trade_gold_line") % 0
	root.add_child(_gold_label)

	_buy_rows = VBoxContainer.new()
	_buy_rows.name = "BuyRows"
	_buy_rows.add_theme_constant_override("separation", 2)
	root.add_child(_buy_rows)

	_sell_rows = VBoxContainer.new()
	_sell_rows.name = "SellRows"
	_sell_rows.add_theme_constant_override("separation", 2)
	root.add_child(_sell_rows)


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


## Renders the trade section of a vendor.
func _render_trade() -> void:
	_clear_rows(_buy_rows)
	_clear_rows(_sell_rows)
	if _vendor_items.is_empty():
		_trade_title_label.visible = false
		_gold_label.visible = false
		return
	_trade_title_label.visible = true
	_gold_label.visible = true
	_gold_label.text = tr("trade_gold_line") % _gold

	for entry: Variant in _vendor_items:
		if not entry is Dictionary:
			continue
		var item_id: String = str(entry.get("item_id", ""))
		var buy_price: int = int(entry.get("buy_price", 0))
		var item_definition: Dictionary = _item_definitions.get(item_id, {})
		if item_definition.is_empty():
			continue
		var level_requirement: int = int(item_definition.get("level_requirement", 1))
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.name = "ItemLabel"
		label.text = _build_trade_item_text(item_id, buy_price, level_requirement)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var buy_button: Button = Button.new()
		buy_button.name = "BuyButton"
		buy_button.text = tr("trade_action_buy")
		buy_button.disabled = (
			buy_price <= 0
			or _gold < buy_price
			or level_requirement > _level
		)
		buy_button.pressed.connect(_on_trade_pressed.bind("buy", item_id, 1))
		row.add_child(buy_button)

		var stack_limit: int = int(item_definition.get("stack_limit", 1))
		if stack_limit > 1:
			var stack_button: Button = Button.new()
			stack_button.name = "BuyStackButton"
			stack_button.text = tr("trade_action_buy_stack") % STACK_PURCHASE_QUANTITY
			stack_button.disabled = (
				buy_price <= 0
				or _gold < buy_price * STACK_PURCHASE_QUANTITY
				or level_requirement > _level
			)
			stack_button.pressed.connect(
				_on_trade_pressed.bind("buy", item_id, STACK_PURCHASE_QUANTITY)
			)
			row.add_child(stack_button)
		_buy_rows.add_child(row)

	_render_sell_rows()


## Renders the items the player can sell to the vendor.
func _render_sell_rows() -> void:
	var sellable_count: int = 0
	for entry: Variant in _inventory:
		if not entry is Dictionary:
			continue
		var item_id: String = str(entry.get("item_id", ""))
		var quantity: int = int(entry.get("quantity", 0))
		var sell_price: int = _find_sell_price(item_id)
		if sell_price <= 0 or quantity <= 0:
			continue
		sellable_count += 1
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.name = "SellItemLabel"
		label.text = tr("trade_sell_item_line") % [
			_build_item_name(item_id),
			quantity,
			sell_price,
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var sell_button: Button = Button.new()
		sell_button.name = "SellButton"
		sell_button.text = tr("trade_action_sell")
		sell_button.pressed.connect(_on_trade_pressed.bind("sell", item_id, 1))
		row.add_child(sell_button)
		_sell_rows.add_child(row)
	if sellable_count == 0:
		var empty_label: Label = Label.new()
		empty_label.name = "SellEmptyLabel"
		empty_label.text = tr("trade_sell_empty")
		_sell_rows.add_child(empty_label)


## Looks up the price the vendor pays for an item.
func _find_sell_price(item_id: String) -> int:
	for entry: Variant in _vendor_items:
		if not entry is Dictionary:
			continue
		if str(entry.get("item_id", "")) != item_id:
			continue
		return int(entry.get("sell_price", 0))
	return 0


func _build_trade_item_text(
	item_id: String,
	buy_price: int,
	level_requirement: int,
) -> String:
	var text: String = tr("trade_buy_item_line") % [
		_build_item_name(item_id),
		buy_price,
	]
	if level_requirement > _level:
		text += tr("trade_level_required") % level_requirement
	return text


func _build_item_name(item_id: String) -> String:
	var item_definition: Dictionary = _item_definitions.get(item_id, {})
	return tr(str(item_definition.get("name_key", item_id)))


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
		int(entry.get("reward_gold", 0)),
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


func _clear_rows(container: VBoxContainer) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_accept_pressed(quest_id: String) -> void:
	accept_quest_requested.emit(_npc_id, quest_id)


func _on_turn_in_pressed(quest_id: String) -> void:
	turn_in_quest_requested.emit(_npc_id, quest_id)


func _on_trade_pressed(action: String, item_id: String, quantity: int) -> void:
	trade_requested.emit(_npc_id, action, item_id, quantity)
