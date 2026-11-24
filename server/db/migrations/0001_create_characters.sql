CREATE TABLE characters (
	character_id UUID PRIMARY KEY,
	character_name TEXT NOT NULL
		CHECK (char_length(btrim(character_name)) BETWEEN 1 AND 32),
	class_id TEXT NOT NULL
		CHECK (btrim(class_id) <> ''),
	level SMALLINT NOT NULL DEFAULT 1
		CHECK (level BETWEEN 1 AND 10),
	experience BIGINT NOT NULL DEFAULT 0
		CHECK (experience >= 0),
	zone_id TEXT NOT NULL
		CHECK (btrim(zone_id) <> ''),
	position_x DOUBLE PRECISION NOT NULL
		CHECK (
			position_x > '-Infinity'::DOUBLE PRECISION
			AND position_x < 'Infinity'::DOUBLE PRECISION
		),
	position_y DOUBLE PRECISION NOT NULL
		CHECK (
			position_y > '-Infinity'::DOUBLE PRECISION
			AND position_y < 'Infinity'::DOUBLE PRECISION
		),
	position_z DOUBLE PRECISION NOT NULL
		CHECK (
			position_z > '-Infinity'::DOUBLE PRECISION
			AND position_z < 'Infinity'::DOUBLE PRECISION
		),
	health DOUBLE PRECISION NOT NULL
		CHECK (health >= 0 AND health < 'Infinity'::DOUBLE PRECISION),
	resource DOUBLE PRECISION NOT NULL
		CHECK (resource >= 0 AND resource < 'Infinity'::DOUBLE PRECISION),
	created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
