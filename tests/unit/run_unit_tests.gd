extends SceneTree

const ProtocolTest: GDScript = preload("res://tests/unit/protocol_constants_test.gd")
const CodecTest: GDScript = preload("res://tests/unit/packet_codec_test.gd")
const MovementTest: GDScript = preload("res://tests/unit/movement_simulation_test.gd")
const ServerWorldTest: GDScript = preload("res://tests/unit/server_world_test.gd")
const GameDataRegistryTest: GDScript = preload("res://tests/unit/game_data_registry_test.gd")
const CombatSystemTest: GDScript = preload("res://tests/unit/combat_system_test.gd")
const PlayerCombatTest: GDScript = preload("res://tests/unit/player_combat_test.gd")
const CharacterProgressionTest: GDScript = preload("res://tests/unit/character_progression_test.gd")
const LootInventoryTest: GDScript = preload("res://tests/unit/loot_inventory_test.gd")
const EquipmentTest: GDScript = preload("res://tests/unit/equipment_test.gd")
const ItemCatalogTest: GDScript = preload("res://tests/unit/item_catalog_test.gd")
const ConsumableTest: GDScript = preload("res://tests/unit/consumable_test.gd")
const InventoryPanelTest: GDScript = preload("res://tests/unit/inventory_panel_test.gd")
const QuestSystemTest: GDScript = preload("res://tests/unit/quest_system_test.gd")
const NpcRegistryTest: GDScript = preload("res://tests/unit/npc_registry_test.gd")
const TradeSystemTest: GDScript = preload("res://tests/unit/trade_system_test.gd")
const LootChanceTest: GDScript = preload("res://tests/unit/loot_chance_test.gd")
const CurrencyTest: GDScript = preload("res://tests/unit/currency_test.gd")
const ChatSystemTest: GDScript = preload("res://tests/unit/chat_system_test.gd")
const PartySystemTest: GDScript = preload("res://tests/unit/party_system_test.gd")
const WorldBuilderTest: GDScript = preload("res://tests/unit/world_builder_test.gd")
const HubLayoutTest: GDScript = preload("res://tests/unit/hub_layout_test.gd")


func _initialize() -> void:
	if not ProtocolTest.new().run():
		quit(1)
		return
	if not CodecTest.new().run():
		quit(1)
		return
	if not MovementTest.new().run():
		quit(1)
		return
	if not ServerWorldTest.new().run():
		quit(1)
		return
	if not GameDataRegistryTest.new().run():
		quit(1)
		return
	if not CombatSystemTest.new().run():
		quit(1)
		return
	if not PlayerCombatTest.new().run():
		quit(1)
		return
	if not CharacterProgressionTest.new().run():
		quit(1)
		return
	if not LootInventoryTest.new().run():
		quit(1)
		return
	if not EquipmentTest.new().run():
		quit(1)
		return
	if not ItemCatalogTest.new().run():
		quit(1)
		return
	if not ConsumableTest.new().run():
		quit(1)
		return
	if not InventoryPanelTest.new(root).run():
		quit(1)
		return
	if not QuestSystemTest.new().run():
		quit(1)
		return
	if not NpcRegistryTest.new().run():
		quit(1)
		return
	if not TradeSystemTest.new().run():
		quit(1)
		return
	if not LootChanceTest.new().run():
		quit(1)
		return
	if not CurrencyTest.new().run():
		quit(1)
		return
	if not ChatSystemTest.new().run():
		quit(1)
		return
	if not PartySystemTest.new().run():
		quit(1)
		return
	if not WorldBuilderTest.new().run():
		quit(1)
		return
	if not HubLayoutTest.new().run():
		quit(1)
		return
	print("UNIT_TESTS_OK")
	quit(0)
