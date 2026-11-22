class_name ProtocolConstants
extends RefCounted

const PROTOCOL_VERSION: int = 1
const SNAPSHOT_CHANNEL: int = 0
const EVENT_CHANNEL: int = 1
const MAX_PACKET_SIZE_BYTES: int = 4096
const HANDSHAKE_TIMEOUT_SECONDS: float = 10.0
const MAX_REQUESTS_PER_SECOND: int = 20
const SERVER_PORT: int = 7788
const OPCODE_HELLO: int = 1
const OPCODE_HELLO_ACCEPTED: int = 2
const OPCODE_HELLO_REJECTED: int = 3
const OPCODE_KEEPALIVE: int = 4
const OPCODE_KEEPALIVE_ACK: int = 5
