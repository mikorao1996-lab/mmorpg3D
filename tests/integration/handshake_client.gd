extends Node

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")
const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")

var peer: ENetMultiplayerPeer
var elapsed_seconds: float = 0.0
var hello_sent: bool = false
var mismatched_sent: bool = false
var accepted_received: bool = false
var rejected_received: bool = false
var mismatched_mode: bool = false


func _ready() -> void:
	mismatched_mode = "--mismatched" in OS.get_cmdline_args()
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client("127.0.0.1", ProtocolConstantsType.SERVER_PORT, 2)
	if error != OK:
		push_error("Failed to create handshake client")
		get_tree().quit(2)
		return

	for attempt: int in 500:
		peer.poll()
		if attempt == 50:
			if mismatched_mode:
				send_hello(ProtocolConstantsType.PROTOCOL_VERSION + 1)
			else:
				send_hello(ProtocolConstantsType.PROTOCOL_VERSION)
			hello_sent = true

		while peer.get_available_packet_count() > 0:
			var channel: int = peer.get_packet_channel()
			var packet: PackedByteArray = peer.get_packet()
			if channel != ProtocolConstantsType.EVENT_CHANNEL:
				continue
			var envelope: Dictionary = PacketCodecType.decode(packet)
			if envelope.is_empty():
				continue
			var opcode: int = envelope["opcode"]
			if opcode == ProtocolConstantsType.OPCODE_HELLO_ACCEPTED:
				accepted_received = true
				print("HANDSHAKE_ACCEPTED")
				if not mismatched_mode:
					get_tree().quit(0)
					return
			elif opcode == ProtocolConstantsType.OPCODE_HELLO_REJECTED:
				rejected_received = true
				print("HANDSHAKE_REJECTED")
				if mismatched_mode:
					get_tree().quit(0)
					return
		OS.delay_msec(10)

	push_error("Handshake integration timeout")
	get_tree().quit(1)


func send_hello(protocol: int) -> void:
	var server_peer: ENetPacketPeer = peer.get_peer(1)
	if server_peer == null:
		return
	var packet: PackedByteArray = PacketCodecType.encode(
		ProtocolConstantsType.OPCODE_HELLO,
		{"protocol": protocol},
	)
	server_peer.send(ProtocolConstantsType.EVENT_CHANNEL, packet, 2)
