# Protocol

## Bootstrap protocol constants

- Protocol version: `1`
- Snapshot channel: `0`, unreliable.
- Event channel: `1`, reliable.
- Maximum packet size: `4096` bytes.
- Default server port: `7788`.

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

Channel `0` is for unreliable snapshots. Channel `1` is reliable events.
