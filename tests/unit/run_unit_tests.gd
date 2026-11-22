extends SceneTree

const ProtocolTest: GDScript = preload("res://tests/unit/protocol_constants_test.gd")
const CodecTest: GDScript = preload("res://tests/unit/packet_codec_test.gd")


func _initialize() -> void:
	if not ProtocolTest.new().run():
		quit(1)
		return
	if not CodecTest.new().run():
		quit(1)
		return
	print("UNIT_TESTS_OK")
	quit(0)
