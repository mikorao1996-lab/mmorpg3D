extends SceneTree

const ProtocolTest: GDScript = preload("res://tests/unit/protocol_constants_test.gd")
const CodecTest: GDScript = preload("res://tests/unit/packet_codec_test.gd")
const MovementTest: GDScript = preload("res://tests/unit/movement_simulation_test.gd")
const ServerWorldTest: GDScript = preload("res://tests/unit/server_world_test.gd")


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
	print("UNIT_TESTS_OK")
	quit(0)
