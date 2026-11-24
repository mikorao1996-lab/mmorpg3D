# Game data registries

The server loads all registries through `GameDataRegistry.load_all()` before
opening its ENet listener. Item, ability, mob, quest, and progression files use
a versioned root object:

```json
{
  "schema_version": 1,
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
- `stack_limit`, `level_requirement`: integers >= 1.
- `sell_price`: integer >= 0.
- `stats`: object with optional `attack`, `defense`, `health`, or `resource`
  numeric values >= 0.

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
- `level`: integer >= 1; `experience_reward` is an integer >= 0; `health` > 0.
- `attack`, `defense`, `move_speed`, `aggro_range`, `attack_range`: finite numbers >= 0.
- `attack_interval_seconds` and `respawn_seconds`: finite numbers > 0.
- `spawn_position`: three finite numeric coordinates; `visual_radius` and
  `visual_height` are finite numbers > 0.
- `loot_item_ids`: unique item IDs; each must exist in the item registry.
  The combat slice uses spawn/visual fields to initialize and render zone-local
  mobs, and the aggro/attack fields to drive server-authoritative mob AI.
  Configured loot items drop on defeat; bosses use the same server-authoritative
  combat and loot rules with their own data-defined stats.

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
- `reward_item_ids`: unique item IDs; each must exist.
- `kill` objectives must reference a registered mob; `collect` objectives must
  reference a registered item. `talk` targets are non-empty NPC IDs; an NPC
  registry is not defined yet.

`GameDataRegistry.load_all()` returns dictionaries keyed by entry ID under
`items`, `abilities`, `mobs`, `progression`, and `quests`. These are initial
schema contracts; database persistence and runtime gameplay systems are
separate Phase 4/5 work.
