# Game data registries

The server loads all registries through `GameDataRegistry.load_all()` before
opening its ENet listener. Item, ability, mob, quest, NPC, vendor, and progression
files use a versioned root object:

```json
{
  "schema_version": 3,
  "entries": []
}
```

Each registry must contain at least one entry. IDs are non-empty, unique strings.
If a file, entry, enum, numeric value, or cross-registry reference is invalid,
loading fails and the headless server does not start.

## Items

File: `resources/data/items.json`

- `id`, `name_key`: non-empty strings.
- `item_type`: `weapon`, `armor`, `consumable`, or `quest`.
- Weapons require `equipment_slot: "weapon"`; armor requires one of `head`,
  `chest`, `hands`, `legs`, or `feet`. Consumables and quest items do not have
  an equipment slot. Weapons and armor have `stack_limit: 1`.
- `stack_limit`: integer >= 1.
- `level_requirement`: integer between `1` and the character level cap (`10`).
  The server rejects an equip request below that level.
- `sell_price`: integer >= 0.
- `stats`: object with optional `attack`, `defense`, `health`, or `resource`
  numeric values >= 0. For equipment these are passive bonuses; for
  consumables they are the use effect (`health` heals, `resource` restores
  the player resource) and at least one of them must be greater than zero.

## Abilities

File: `resources/data/abilities.json`

- `id`, `name_key`, `class_id`: non-empty strings.
- `target_type`: `self`, `ally`, or `enemy`.
- `effect_type`: `damage`, `heal`, or `buff`.
- `cooldown_seconds`, `resource_cost`, `range`: finite numbers >= 0.
- `magnitude`: finite number > 0.

## Mobs

File: `resources/data/mobs.json`

- `id`, `name_key`: non-empty strings.
- `is_boss`: boolean that marks a mini-boss for client presentation.
- `level`: integer >= 1; `experience_reward` and `gold_reward` are integers >= 0;
  `health` > 0.
- `attack`, `defense`, `move_speed`, `aggro_range`, `attack_range`: finite numbers >= 0.
- `attack_interval_seconds` and `respawn_seconds`: finite numbers > 0.
- `spawn_positions`: a non-empty list of spawn points, each of them three finite
  numeric coordinates. Every point holds one instance of the mob, so a type with
  three points stands in the world three times. The points of a type have to be
  distinct; the instances of different types may stand close to each other, the
  layout check of the hub keeps the distance between them.
  `visual_radius` and `visual_height` are finite numbers > 0.
- `loot_item_ids`: unique item IDs; each must exist in the item registry.
  Every listed item is a guaranteed drop on defeat.
- `loot_chances`: list of `{item_id, chance}` entries; each item must exist and
  each chance is a number between `0` and `1`. The item only drops when the
  server rolls at or below the chance, so `1.0` always drops and `0.0` never
  drops.
- The combat slice uses spawn/visual fields to initialize and render zone-local
  mobs, and the aggro/attack fields to drive server-authoritative mob AI.
  Configured loot items drop on defeat; bosses use the same server-authoritative
  combat and loot rules with their own data-defined stats. The current catalog
  spreads the six equipment slots over the mob loot tables and the quest
  rewards so every slot has an obtainable item.

A mob type is a definition, and every spawn point of it is an instance. The
instances are numbered in the order of their spawn points: the first instance
keeps the identifier of the type (`training_slime`), the next ones get a
numeric suffix (`training_slime_2`). The server spawns the instances and
counts the defeats of a type, and the client resolves the type of an instance
from the same registry, so the wire protocol carries only the identifier of
the instance.

## Progression

File: `resources/data/progression.json`

- Defines exactly ten contiguous levels, `level_1` through `level_10`.
- `experience_required` is the cumulative experience required to reach a level;
  level 1 starts at zero and later thresholds must strictly increase.
- `max_health`, `max_resource`, and `attack_multiplier` are finite numbers > 0;
  `defense` is a finite number >= 0.
- On level-up, maximum stats and combat multipliers change according to the
  table, while current health/resource percentages are preserved. Experience
  and level are currently session-only and are not persisted across disconnects.

## Quests

File: `resources/data/quests.json`

- `id`, `name_key`, `objective_target`: non-empty strings.
- `min_level`, `objective_count`: integers >= 1.
- `objective_type`: `kill`, `collect`, or `talk`.
- `reward_experience`: integer >= 0.
- `reward_gold`: integer >= 0; the gold a handed-in quest pays out.
- `reward_item_ids`: unique item IDs; each must exist.
- `kill` objectives must reference a registered mob; `collect` objectives must
  reference a registered item; `talk` objectives must reference a registered NPC.
- The quest runtime reads this registry: the server tracks the accepted quests
  of every player, counts kills, pickups, and conversations, and grants the
  reward exactly once. The reward items are only granted when the inventory can
  hold all of them; otherwise the hand-in is rejected and no experience is
  awarded.

## NPCs

File: `resources/data/npcs.json`

- `id`, `name_key`, `dialogue_key`: non-empty strings. The dialogue key points
  to a localized line that is shown when the player talks to the NPC.
- `spawn_position`: three finite numbers; the world position of the NPC.
- `interaction_range`: number > 0; the distance in world units in which the
  player may interact with the NPC.
- `quest_ids`: unique quest IDs; each must exist in the quest registry. An NPC
  that is a vendor may have an empty list.

## Simulation config

File: `resources/data/simulation.json`

- `starting_gold`: integer >= 0; the gold balance a player starts with. The
  balance is earned from quests and mob defeats and is spent at a vendor.
- `chat_message_max_length`: integer > 0; the longest message the server
  accepts. A longer message is rejected with `message_too_long`.
- `chat_messages_per_second`: integer > 0; the number of messages a player may
  send within one second. A player above the limit is rejected with
  `rate_limited`.
- `chat_history_size`: integer > 0; the number of messages the client keeps in
  the chat panel.
- `chat_player_name_max_length`: integer > 0; the longest display name the
  server accepts in the handshake.
- `party_max_size`: integer > 0; the number of members a party may have.
- `world_half_extent`: the half size of the playable area; the movement
  simulation clamps the player to it.
- `interest_radius`: the radius around a player in which the server sends the
  mobs, the NPCs, and the drops.
- `terrain_seed` and `prop_seed`: the seeds of the generated landscape; every
  client shows the same terrain and the same props.
- `terrain_extent`: the half size of the generated terrain mesh.
- `terrain_height`: the highest hill of the terrain.
- `terrain_hub_radius`: the radius around the spawn point that stays flat, so
  the player, the NPCs, and the first mobs stand on level ground.
- `terrain_resolution`: the number of quads per side of the terrain mesh.
- `prop_radius`: the radius around the hub in which the trees and the rocks
  are placed.
- `tree_count` and `rock_count`: the number of trees and rocks of the map.
- The remaining keys configure the simulation step, the movement, the snapshot
  rate, and the inventory size.

## Vendors

File: `resources/data/vendors.json`

- `id`: non-empty string.
- `npc_id`: the NPC that serves the vendor; it must exist in the NPC registry
  and only one vendor may serve an NPC.
- `items`: a non-empty list of `{item_id, buy_price, sell_price}` entries. Each
  item must exist in the item registry, and each price is an integer >= 0.
  `buy_price` is what the player pays, `sell_price` is what the vendor pays.
  An item with a `buy_price` of zero is not sold, and an item with a
  `sell_price` of zero is not bought back.

The vendor registry is the only source of prices: a trade request never carries
a price, and the server resolves the price of the traded item from this
registry again for every trade.

`GameDataRegistry.load_all()` returns dictionaries keyed by entry ID under
`items`, `abilities`, `mobs`, `progression`, `quests`, `npcs`, and `vendors`.
These are initial schema contracts; database persistence and the chat system
are separate Phase 5 work.
