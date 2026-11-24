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
	print("UNIT_TESTS_OK")
	quit(0)
