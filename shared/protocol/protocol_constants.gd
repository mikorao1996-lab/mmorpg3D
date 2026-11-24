class_name ProtocolConstants
extends RefCounted

const PROTOCOL_VERSION: int = 3
const SNAPSHOT_CHANNEL: int = 0
const EVENT_CHANNEL: int = 1
const ENET_USER_CHANNEL_OFFSET: int = 1
const MAX_PACKET_SIZE_BYTES: int = 4096
const PACKET_FLAG_RELIABLE: int = 1
const PACKET_FLAG_UNRELIABLE: int = 0
const HANDSHAKE_TIMEOUT_SECONDS: float = 10.0
const MAX_REQUESTS_PER_SECOND: int = 20
const SERVER_PORT: int = 7788
const OPCODE_HELLO: int = 1
const OPCODE_HELLO_ACCEPTED: int = 2
const OPCODE_HELLO_REJECTED: int = 3
const OPCODE_KEEPALIVE: int = 4
const OPCODE_KEEPALIVE_ACK: int = 5
const OPCODE_MOVE_INPUT: int = 6
const OPCODE_WORLD_SNAPSHOT: int = 7
const OPCODE_ZONE_TRANSFER: int = 8
const OPCODE_ZONE_TRANSFER_RESULT: int = 9
const OPCODE_ABILITY_CAST: int = 10
const OPCODE_ABILITY_CAST_RESULT: int = 11


static func to_transport_channel(protocol_channel: int) -> int:
	return protocol_channel + ENET_USER_CHANNEL_OFFSET
