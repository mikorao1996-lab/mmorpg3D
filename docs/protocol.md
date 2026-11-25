# Protocol

## Bootstrap protocol constants

- Protocol version: `8`
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
- `17`: `USE_ITEM`
- `18`: `ITEM_USE_RESULT`
- `19`: `NPC_INTERACT`
- `20`: `NPC_INTERACT_RESULT`
- `21`: `TRADE_REQUEST`
- `22`: `TRADE_RESULT`

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
radius. Every item in a mob's `loot_item_ids` is a guaranteed drop; every item
in its `loot_chances` list only drops when the server rolls at or below its
configured `chance`, so a rare item is a rare drop. A chance of `1.0` always
drops and a chance of `0.0` never drops. Drops remain in the zone until picked
up.
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

`USE_ITEM` requests contain an `item_id`. Only authenticated peers can request
item use. The server resolves the item in the item registry, requires it to be
a `consumable`, and requires the player to own a unit of it. The effect comes
from the item definition: `stats.health` heals the player and `stats.resource`
restores the player resource, capped by the current maximum values. The item is
consumed only when the effect applies, so a potion is never wasted while the
player is at full health. `ITEM_USE_RESULT` reliably contains `accepted`,
`reason`, `item_id`, `health`, `max_health`, `resource`, and `max_resource`.
Rejection reasons are `invalid_player`, `player_dead`, `unknown_item`,
`not_consumable`, `item_not_in_inventory`, `no_effect`, `no_effect_needed`,
`health_full`, `resource_full`, and `inventory_error`.

The client resolves the server address and port from `resources/data/simulation.json`.
`MMORPG3D_SERVER_ADDRESS` and `MMORPG3D_SERVER_PORT` override those values so a
client can join a server on another machine without a rebuild.

`NPC_INTERACT` requests contain `npc_id`, `action` and an optional `quest_id`.
Supported actions are `talk`, `accept` and `turn_in`. Only authenticated peers
can interact, and the server checks the NPC, the interaction distance from the
NPC definition, the level requirement, the quest state, and the free inventory
space before anything changes. `NPC_INTERACT_RESULT` reliably contains
`accepted`, `reason`, `action`, `npc_id`, `npc_name_key`, `dialogue_key`, the
`quests` list of the NPC, `quest_id`, `reward_experience`, `reward_gold`,
`reward_item_ids`, and `vendor_items`. Every quest entry of the list contains
`quest_id`, `name_key`, `status`, `progress`, `objective_count`, `objective_type`,
`objective_target`, `min_level`, `reward_experience`, `reward_gold`, and
`reward_item_ids`. The status is `available`, `active`, `completed`, or
`turned_in`. Rejection reasons are `invalid_player`, `invalid_action`,
`unknown_npc`, `out_of_range`, `unknown_quest`, `not_offered`,
`level_requirement`, `already_active`, `already_turned_in`, `not_active`,
`not_complete`, `inventory_full`, and `inventory_error`.

The world snapshot of protocol version 8 additionally contains the `npcs` list
with `[npc_id, position]` entries and the `quests` list of the observing
player with `[quest_id, status, progress, objective_count, name_key,
objective_type, objective_target]` entries. Quest progress is server
authoritative: mob defeats, item pickups, and NPC conversations are counted on
the server, and a quest can be handed in only once.

## Currency and trading

Gold is the currency of the vertical slice. The balance is server-authoritative:
it starts at `starting_gold` from `resources/data/simulation.json`, is earned
from quest hand-ins (`reward_gold`) and from mob defeats (`gold_reward`), and is
spent at a vendor. The world snapshot carries the gold of the observing player
in the top-level `gold` field, so the client only renders a value it received.

`TRADE_REQUEST` requests contain `npc_id`, `action`, `item_id`, and `quantity`.
Supported actions are `buy` and `sell`. Only authenticated peers can trade. The
request never carries a price: the server reads the price from the vendor
registry, so a client cannot change what an item costs. The server also checks
that the NPC is a vendor, that the item is in the assortment of that vendor,
that the quantity is between `1` and `20`, that the level requirement of the
item is met for a purchase, that the balance covers the total price, and that
the inventory has room for the delivered items. Every check runs before the
balance or the inventory is touched, so a rejected trade leaves both of them
exactly as they were. `TRADE_RESULT` reliably contains `accepted`, `reason`,
`action`, `npc_id`, `item_id`, `quantity`, `price`, and the resulting `gold`.
Rejection reasons are `invalid_player`, `invalid_action`, `not_a_vendor`,
`invalid_quantity`, `item_not_traded`, `unknown_item`, `item_not_for_sale`,
`item_not_accepted`, `level_requirement`, `insufficient_gold`,
`inventory_full`, and `item_not_in_inventory`.

The `vendor_items` list of an `NPC_INTERACT_RESULT` carries the assortment of a
vendor as `item_id`, `buy_price`, and `sell_price` entries, and is empty for an
NPC that is not a vendor. The client renders those prices, but every trade is
priced by the server again.
