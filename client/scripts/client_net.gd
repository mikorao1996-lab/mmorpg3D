class_name ClientNet
extends Node

const ProtocolConstantsType: GDScript = preload("res://shared/protocol/protocol_constants.gd")
const PacketCodecType: GDScript = preload("res://shared/protocol/packet_codec.gd")

signal connected()
signal disconnected()
signal hello_accepted(protocol: int)
signal hello_rejected(reason: String)

var peer: ENetMultiplayerPeer
var is_connected: bool = false


func connect_to_server(address: String, port: int = ProtocolConstantsType.SERVER_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port, 2)
	if error != OK:
		push_error("Failed to create ENet client")
		return error
	peer.get_peer(1).set_timeout(3000, 5000, 10000)
	return OK


func _process(_delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var channel: int = peer.get_packet_channel()
		var packet: PackedByteArray = peer.get_packet()
		handle_packet(channel, packet)


func handle_packet(channel: int, packet: PackedByteArray) -> void:
	if channel != ProtocolConstantsType.EVENT_CHANNEL:
		push_warning("Rejected snapshot packet before snapshot support")
		return
	var envelope: Dictionary = PacketCodecType.decode(packet)
	if envelope.is_empty():
		return

	match envelope["opcode"] as int:
		ProtocolConstantsType.OPCODE_HELLO_ACCEPTED:
			var protocol: int = envelope["payload"].get("protocol", 0)
			is_connected = true
			connected.emit()
			hello_accepted.emit(protocol)
		ProtocolConstantsType.OPCODE_HELLO_REJECTED:
			hello_rejected.emit(str(envelope["payload"].get("reason", "unknown")))
			disconnected.emit()
		ProtocolConstantsType.OPCODE_KEEPALIVE_ACK:
			pass


func send_hello() -> Error:
	return send_packet(ProtocolConstantsType.OPCODE_HELLO, {
		"protocol": ProtocolConstantsType.PROTOCOL_VERSION,
	})


func send_keepalive() -> Error:
	return send_packet(ProtocolConstantsType.OPCODE_KEEPALIVE)


func send_packet(opcode: int, payload: Dictionary = {}) -> Error:
	if peer == null:
		return ERR_UNCONFIGURED
	var packet: PackedByteArray = PacketCodecType.encode(opcode, payload)
	if packet.is_empty():
		return ERR_INVALID_DATA
	var server_peer: ENetPacketPeer = peer.get_peer(1)
	if server_peer == null:
		return ERR_UNAVAILABLE
	return server_peer.send(ProtocolConstantsType.EVENT_CHANNEL, packet, 2)
