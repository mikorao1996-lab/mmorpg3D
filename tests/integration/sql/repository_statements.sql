PREPARE ins (uuid, text, text, text, smallint, bigint, integer, text, double precision, double precision, double precision, double precision, double precision, jsonb, jsonb, jsonb) AS
INSERT INTO characters (character_id, character_name, character_token_hash, class_id, level, experience, gold, zone_id, position_x, position_y, position_z, health, resource, inventory, equipment, quests)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
ON CONFLICT (character_id) DO UPDATE SET
character_name = EXCLUDED.character_name,
character_token_hash = EXCLUDED.character_token_hash,
class_id = EXCLUDED.class_id,
level = EXCLUDED.level,
experience = EXCLUDED.experience,
gold = EXCLUDED.gold,
zone_id = EXCLUDED.zone_id,
position_x = EXCLUDED.position_x,
position_y = EXCLUDED.position_y,
position_z = EXCLUDED.position_z,
health = EXCLUDED.health,
resource = EXCLUDED.resource,
inventory = EXCLUDED.inventory,
equipment = EXCLUDED.equipment,
quests = EXCLUDED.quests,
updated_at = CURRENT_TIMESTAMP;

EXECUTE ins('11111111-1111-4111-8111-111111111111', 'Hero', 'hash', 'warrior', 3, 250, 175, 'starter', 1.5, 0.0, -2.5, 80.0, 40.0, '[{"item_id":"minor_potion","quantity":2}]', '{"weapon":"iron_sword"}', '{"slime_problem":{"status":"active","progress":2}}');

SELECT character_id::text AS character_id, character_name, character_token_hash, class_id, level::text AS level, experience::text AS experience, gold::text AS gold, zone_id,
position_x::text AS position_x, position_y::text AS position_y, position_z::text AS position_z, health::text AS health, resource::text AS resource,
inventory::text AS inventory, equipment::text AS equipment, quests::text AS quests
FROM characters WHERE character_id = '11111111-1111-4111-8111-111111111111'::uuid;

EXECUTE ins('11111111-1111-4111-8111-111111111111', 'Hero2', 'hash2', 'warrior', 4, 300, 200, 'dungeon', 0.0, 0.0, 0.0, 100.0, 50.0, '[]', '{}', '{}');

SELECT character_id::text AS character_id, character_name, level::text AS level, gold::text AS gold, zone_id, updated_at > created_at AS touched
FROM characters WHERE character_id = '11111111-1111-4111-8111-111111111111'::uuid;
