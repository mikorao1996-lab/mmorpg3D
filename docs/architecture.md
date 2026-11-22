# Initial architecture

The server is authoritative. Clients send intent and receive snapshots/events.
Movement simulation is shared by client and server and must not depend on UI or rendering.

## Network channels

- Channel 0: unreliable snapshots.
- Channel 1: reliable events.

These channels and the protocol version are defined in `shared/protocol/protocol_constants.gd`.
