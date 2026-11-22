# Game data registries

The server loads all registries through `GameDataRegistry.load_all()` before
opening its ENet listener. Files use a versioned root object:

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
- `level`: integer >= 1; `health` and `respawn_seconds` are > 0.
- `attack`, `defense`, `move_speed`, `aggro_range`: finite numbers >= 0.
- `spawn_position`: three finite numeric coordinates; `visual_radius` and
  `visual_height` are finite numbers > 0.
- `loot_item_ids`: unique item IDs; each must exist in the item registry.
  The current combat slice uses these spawn and visual fields to initialize
  zone-local mob state and render the placeholder client model.

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
`items`, `abilities`, `mobs`, and `quests`. These are initial schema contracts;
database persistence and runtime gameplay systems are separate Phase 4/5 work.
