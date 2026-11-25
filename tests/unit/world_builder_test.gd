extends RefCounted

## Checks the generated landscape.
##
## The terrain has to keep the hub flat, it has to rise outside of it, and the
## props have to be placed deterministically and never on the hub or on the
## positions of the NPCs and the mobs.

const WorldBuilderType: GDScript = preload("res://client/scripts/world_builder.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")

const PROP_CLEAR_RADIUS: float = 11.0
const PROP_CLEARANCE: float = 3.0


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	var registries: Dictionary = GameDataRegistryType.load_all()
	if config.is_empty() or registries.is_empty():
		return false

	var builder: RefCounted = WorldBuilderType.new(config)
	var hub_radius: float = float(config["terrain_hub_radius"])
	var terrain_height: float = float(config["terrain_height"])

	if not is_equal_approx(builder.get_height(0.0, 0.0), 0.0):
		push_error("The terrain is not flat in the middle of the hub")
		return false
	if not is_equal_approx(builder.get_height(hub_radius * 0.5, hub_radius * 0.5), 0.0):
		push_error("The terrain is not flat around the spawn point")
		return false

	var highest_point: float = 0.0
	var lowest_point: float = 0.0
	for sample_x: int in range(-12, 13):
		for sample_z: int in range(-12, 13):
			var height: float = builder.get_height(
				float(sample_x) * 4.0,
				float(sample_z) * 4.0,
			)
			highest_point = maxf(highest_point, height)
			lowest_point = minf(lowest_point, height)
	if is_equal_approx(highest_point, lowest_point):
		push_error("The terrain has no relief outside of the hub")
		return false
	if absf(highest_point) > terrain_height or absf(lowest_point) > terrain_height:
		push_error("The terrain exceeds the configured height")
		return false

	var terrain: MeshInstance3D = builder.build_terrain()
	if terrain.mesh == null:
		push_error("The world builder did not build a terrain mesh")
		return false
	if terrain.mesh.get_surface_count() != 1:
		push_error("The terrain mesh does not have a single surface")
		return false
	var expected_vertices: int = int(config["terrain_resolution"]) * int(config["terrain_resolution"]) * 6
	if terrain.mesh.surface_get_array_len(0) != expected_vertices:
		push_error("The terrain mesh does not match the configured resolution")
		return false

	var occupied: Array = []
	for npc_definition: Dictionary in registries["npcs"].values():
		var npc_position: Array = npc_definition["spawn_position"]
		occupied.append(Vector3(float(npc_position[0]), 0.0, float(npc_position[2])))
	for mob_definition: Dictionary in registries["mobs"].values():
		var mob_position: Array = mob_definition["spawn_position"]
		occupied.append(Vector3(float(mob_position[0]), 0.0, float(mob_position[2])))

	var props: MeshInstance3D = builder.build_props(occupied)
	if props.mesh == null:
		push_error("The world builder did not build a props mesh")
		return false
	var prop_positions: Array = builder.get_prop_positions()
	var requested_props: int = int(config["tree_count"]) + int(config["rock_count"])
	if prop_positions.size() < requested_props * 9 / 10:
		push_error("The world builder placed too few props")
		return false
	for position: Vector3 in prop_positions:
		if Vector2(position.x, position.z).length() < PROP_CLEAR_RADIUS:
			push_error("A prop was placed inside of the hub")
			return false
		for occupied_position: Vector3 in occupied:
			if Vector2(position.x, position.z).distance_to(
				Vector2(occupied_position.x, occupied_position.z)
			) < PROP_CLEARANCE:
				push_error("A prop was placed on an NPC or a mob")
				return false

	var second_builder: RefCounted = WorldBuilderType.new(config)
	var second_props: MeshInstance3D = second_builder.build_props(occupied)
	if second_props.mesh.get_surface_count() != props.mesh.get_surface_count():
		push_error("The prop placement is not reproducible")
		return false
	if second_props.mesh.surface_get_array_len(0) != props.mesh.surface_get_array_len(0):
		push_error("The prop placement is not reproducible")
		return false
	if (
		second_builder.get_prop_positions()[0]
		!= builder.get_prop_positions()[0]
	):
		push_error("The prop placement is not reproducible")
		return false

	# The generated nodes own rendering resources, so they are released before
	# the test ends.
	terrain.free()
	props.free()
	second_props.free()
	return true
