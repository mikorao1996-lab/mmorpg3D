# Protocol

## Bootstrap protocol constants

- Protocol version: `5`
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
- `10`: `ABILITY_CAST`
- `11`: `ABILITY_CAST_RESULT`
- `12`: `LOOT_PICKUP`
- `13`: `LOOT_PICKUP_RESULT`
- `14`: `EQUIP_ITEM`
- `15`: `UNEQUIP_ITEM`
- `16`: `EQUIPMENT_RESULT`

Channel `0` is for unreliable snapshots. Channel `1` is reliable events.

`MOVE_INPUT` payloads contain a `direction` Vector2; the server validates its
magnitude and applies it during the fixed simulation step. `WORLD_SNAPSHOT`
payloads contain `zone_id`, `server_time_ms` and a `players` array of
`[peer_id, position, health, max_health, level, experience, resource,
max_resource, attack_multiplier, defense]` entries. Each snapshot is filtered
to the configured interest radius around its recipient and always includes
that recipient. The current default radius is `10` world units in
`resources/data/simulation.json`.

Progression is server-authoritative. Killing a mob awards its configured
`experience_reward`; level thresholds and derived stats are loaded from
`resources/data/progression.json`. Stats update on the next snapshot. At the
level cap, further experience does not raise the level. Level and experience
are session-only until a secure account/character identity is implemented.

`ZONE_TRANSFER` requests contain a configured `zone_id`. Only authenticated
peers can request a transfer. The server replies reliably with
`ZONE_TRANSFER_RESULT`, containing the requested `zone_id`, an `accepted` boolean,
and a `reason` string (`unknown_zone` when the zone is not configured). Player
snapshots are routed only within the player's current zone.

`WORLD_SNAPSHOT` also contains a `mobs` array of
`[mob_id, position, health, max_health]` entries for the current zone.
Snapshots also contain `drops` entries in the form
`[drop_id, item_id, position]` and the observing player's `inventory` as
`[item_id, quantity]` slots. Drops are filtered to the observer's interest
radius. Each configured mob loot item is a guaranteed drop for this vertical
slice. Drops remain in the zone until picked up.
`LOOT_PICKUP` is a reliable request containing `drop_id`; only authenticated
peers can request pickup. The server verifies that the drop exists in the
player's current zone, is within `loot_pickup_range`, and fits in the
session-only inventory before removing it. `LOOT_PICKUP_RESULT` reliably
contains `accepted`, `reason`, and `item_id`. A full inventory or failed
range check leaves the drop in the world.
Snapshots contain an `equipment` dictionary with all six slots (`weapon`,
`head`, `chest`, `hands`, `legs`, `feet`) mapped to an item ID or an empty
string. `EQUIP_ITEM` contains an `item_id`; `UNEQUIP_ITEM` contains a `slot_id`.
The server checks inventory ownership, item slot, level requirement, and
capacity before changing gear. `EQUIPMENT_RESULT` reliably reports the
operation, acceptance, reason, item ID, and slot ID. Equipped item stats are
applied server-side to attack, defense, maximum health, and maximum resource.
Mobs pursue the nearest living player inside their configured aggro range and
attack at their data-defined range and interval. Player health, defeat, and
respawn are server-authoritative; defeated players respawn at the current
zone's entry point after the configured delay.
`ABILITY_CAST` requests contain `ability_id` and `target_mob_id`. Only
authenticated peers can request a cast; the server checks the registered
ability, target, range, cooldown, and living target state before applying
configured damage. `ABILITY_CAST_RESULT` reliably contains `accepted`, `reason`,
`mob_id`, `health`, and `max_health`. Mob health and respawns are authoritative
and replicated through subsequent snapshots.
