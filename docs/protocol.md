# Protocol

## Bootstrap protocol constants

- Protocol version: `1`
- Snapshot channel: `0`, unreliable.
- Event channel: `1`, reliable.
- Maximum packet size: `4096` bytes.
- Default server port: `7788`.
- Maximum requests: `20` per peer in a one-second rate window.
- Unauthenticated handshake timeout: `10` seconds.

The channel IDs above are protocol channel IDs. Godot's `ENetMultiplayerPeer`
reserves two underlying ENet channels, so direct `ENetPacketPeer.send()` calls
map a protocol channel to the transport channel by adding one.

## Packet envelope

Packets are serialized with `var_to_bytes` and decode with `bytes_to_var`.
Envelope fields:

- `protocol`: integer protocol version.
- `opcode`: integer opcode.
- `sequence`: integer sequence number.
- `payload`: dictionary.

Opcodes:

- `1`: `HELLO`
- `2`: `HELLO_ACCEPTED`
- `3`: `HELLO_REJECTED`
- `4`: `KEEPALIVE`
- `5`: `KEEPALIVE_ACK`
- `6`: `MOVE_INPUT`
- `7`: `WORLD_SNAPSHOT`
- `8`: `ZONE_TRANSFER`
- `9`: `ZONE_TRANSFER_RESULT`

Channel `0` is for unreliable snapshots. Channel `1` is reliable events.

`MOVE_INPUT` payloads contain a `direction` Vector2; the server validates its
magnitude and applies it during the fixed simulation step. `WORLD_SNAPSHOT`
payloads contain `zone_id`, `server_time_ms` and a `players` array of
`[peer_id, position]` entries. Each snapshot is filtered to the configured
interest radius around its recipient and always includes that recipient. The
current default radius is `10` world units in `resources/data/simulation.json`.

`ZONE_TRANSFER` requests contain a configured `zone_id`. Only authenticated
peers can request a transfer. The server replies reliably with
`ZONE_TRANSFER_RESULT`, containing the requested `zone_id`, an `accepted` boolean,
and a `reason` string (`unknown_zone` when the zone is not configured). Player
snapshots are routed only within the player's current zone.
