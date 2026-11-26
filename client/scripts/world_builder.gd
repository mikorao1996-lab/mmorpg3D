class_name WorldBuilder
extends RefCounted

## Builds the landscape and the props of the zone.
##
## The terrain is a heightmap mesh generated from a fixed seed, so every client
## shows the same ground. The area around the hub stays flat so that the
## spawn point, the NPCs, and the first mobs stand on level ground, and the
## ground rises towards the edges of the map.
##
## The trees and the rocks are pure decoration: they are placed from a fixed
## seed, they avoid the hub and the positions of the NPCs and the mobs, and
## they are never part of the server state.
##
## The living layer of the world — the grass and the lake — lives in
## `WorldLiveness`, so this file stays about the landscape itself.

const TerrainShaderType: Shader = preload("res://client/shaders/terrain_pbr.gdshader")

const DEFAULT_TERRAIN_RESOLUTION: int = 72
const PROP_CLEAR_RADIUS: float = 11.0
const PROP_CLEARANCE: float = 3.0
const FOLIAGE_DEFAULT_COUNT: int = 24000
const LAKE_CENTER: Vector3 = Vector3(-14.0, 0.0, 27.0)
const LAKE_SIZE: float = 42.0
const LAKE_LEVEL_MARGIN: float = 0.15

const COLOR_GRASS: Color = Color(0.17, 0.33, 0.15)
const COLOR_GRASS_DARK: Color = Color(0.13, 0.25, 0.13)
const COLOR_ROCK: Color = Color(0.36, 0.34, 0.31)
const COLOR_SAND: Color = Color(0.38, 0.33, 0.22)
const COLOR_TRUNK: Color = Color(0.28, 0.19, 0.12)
const COLOR_LEAVES: Color = Color(0.12, 0.29, 0.12)
const COLOR_LEAVES_LIGHT: Color = Color(0.18, 0.39, 0.16)

var _noise: FastNoiseLite = FastNoiseLite.new()
var _extent: float = 42.0
var _resolution: int = DEFAULT_TERRAIN_RESOLUTION
var _height_scale: float = 4.5
var _hub_radius: float = 10.0
var _prop_radius: float = 46.0
var _prop_seed: int = 4711
var _prop_positions: Array[Vector3] = []
var _tree_count: int = 190
var _rock_count: int = 45
var _foliage_count: int = FOLIAGE_DEFAULT_COUNT


func _init(config: Dictionary = {}) -> void:
	_extent = float(config.get("terrain_extent", 42.0))
	_resolution = int(config.get("terrain_resolution", DEFAULT_TERRAIN_RESOLUTION))
	_height_scale = float(config.get("terrain_height", 4.5))
	_hub_radius = float(config.get("terrain_hub_radius", 10.0))
	_prop_seed = int(config.get("prop_seed", 4711))
	_prop_radius = float(config.get("prop_radius", 46.0))
	_tree_count = int(config.get("tree_count", 190))
	_rock_count = int(config.get("rock_count", 45))
	_foliage_count = int(config.get("foliage_count", FOLIAGE_DEFAULT_COUNT))
	_noise.seed = int(config.get("terrain_seed", 20261125))
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.028
	_noise.fractal_octaves = 3


## Returns the height of the terrain at the given position.
##
## The hub is flat, and the hills grow with the distance from the hub.
func get_height(x: float, z: float) -> float:
	var distance_from_hub: float = sqrt(x * x + z * z)
	var hill_factor: float = clampf(
		(distance_from_hub - _hub_radius) / 14.0,
		0.0,
		1.0,
	)
	var noise_value: float = _noise.get_noise_2d(x, z)
	return noise_value * _height_scale * hill_factor


## Builds the terrain mesh of the map.
func build_terrain() -> MeshInstance3D:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step: float = (_extent * 2.0) / float(_resolution)
	for z_index: int in range(_resolution):
		for x_index: int in range(_resolution):
			var x0: float = -_extent + float(x_index) * step
			var z0: float = -_extent + float(z_index) * step
			var x1: float = x0 + step
			var z1: float = z0 + step
			_append_terrain_quad(surface, x0, z0, x1, z1)
	surface.generate_normals()

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TerrainShaderType
	surface.set_material(material)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Terrain"
	mesh_instance.mesh = surface.commit()
	return mesh_instance


## Builds the layer of grass of the map.
##
## The grass is one MultiMesh, so thousands of tufts cost one draw call. The
## tufts stand on the ground of the terrain, they keep away from the plaza of
## the hub, and they do not grow in the lake.
func build_foliage_layer(parent: Node3D, count: int = 0) -> MultiMeshInstance3D:
	return WorldLiveness.new().build_foliage_layer(self, parent, count)


## Returns the positions of the tufts of grass.
func get_foliage_positions() -> Array:
	return WorldLiveness.new().get_foliage_positions(self)


## Builds the surface of the lake.
##
## The lake is a flat surface at the water level, and the shore of the lake is
## the line where the ground of the terrain rises through it.
func build_water(parent: Node3D) -> MeshInstance3D:
	return WorldLiveness.new().build_water(self, parent)


## Returns the number of the tufts of grass of the map.
func get_foliage_count() -> int:
	return _foliage_count


## Returns the radius of the flat ground of the hub.
func get_hub_radius() -> float:
	return _hub_radius


## Reports whether a position stands inside the map.
func is_inside_map(x: float, z: float) -> bool:
	return absf(x) <= _extent and absf(z) <= _extent


## Returns the color of the ground for a height.
func get_terrain_color(height: float) -> Color:
	return _terrain_color(height)


## Returns the center of the lake.
func get_lake_center() -> Vector3:
	return LAKE_CENTER


## Returns the size of the lake.
func get_lake_size() -> float:
	return LAKE_SIZE


## Returns the level of the water of the lake.
func get_water_level() -> float:
	return get_height(LAKE_CENTER.x, LAKE_CENTER.z) + LAKE_LEVEL_MARGIN


## Builds the trees and the rocks of the map.
##
## The `occupied_positions` are the positions of the NPCs and the mobs; no prop
## is placed on them.
func build_props(occupied_positions: Array = []) -> MeshInstance3D:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = _prop_seed

	for _index: int in range(_tree_count):
		var position: Vector3 = _find_prop_position(random, occupied_positions)
		if position == Vector3.ZERO:
			continue
		var tree_scale: float = random.randf_range(0.85, 1.7)
		_append_tree(surface, position, tree_scale, random)
		_prop_positions.append(position)

	for _index: int in range(_rock_count):
		var position: Vector3 = _find_prop_position(random, occupied_positions)
		if position == Vector3.ZERO:
			continue
		var rock_scale: float = random.randf_range(0.4, 1.1)
		_append_rock(surface, position, rock_scale)
		_prop_positions.append(position)

	surface.generate_normals()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.86
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.set_material(material)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Props"
	mesh_instance.mesh = surface.commit()
	return mesh_instance


## Builds the atmosphere of the zone.
##
## The atmosphere is the sky, the sun, and the post effects: the volumetric fog
## gives the world depth, the glow lights the bright parts of the scene, and
## the ambient occlusion keeps the objects in contact with the ground. It is
## built in code, so the look of the world lives in one place.
func setup_atmosphere(root: Node3D) -> void:
	if root == null:
		return
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = _build_sky()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.012
	environment.volumetric_fog_albedo = Color(0.75, 0.84, 0.92)
	environment.volumetric_fog_emission_energy = 0.2
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.glow_bloom = 0.25
	environment.glow_hdr_threshold = 1.1
	environment.ssao_enabled = true
	environment.ssao_radius = 1.5
	environment.ssao_intensity = 1.8

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	root.add_child(world_environment)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	root.add_child(sun)


## Builds the sky of the zone.
func _build_sky() -> Sky:
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.14, 0.32, 0.58)
	sky_material.sky_horizon_color = Color(0.65, 0.78, 0.88)
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = Color(0.12, 0.14, 0.16)
	sky_material.ground_horizon_color = Color(0.45, 0.52, 0.58)
	sky_material.sun_angle_max = 35.0
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	return sky


## Finds a free position for a prop.
##
## The position is rejected when it is too close to the hub, too close to
## another prop, or too close to an occupied position.
func _find_prop_position(
	random: RandomNumberGenerator,
	occupied_positions: Array,
) -> Vector3:
	for _attempt: int in range(24):
		var x: float = random.randf_range(-_prop_radius, _prop_radius)
		var z: float = random.randf_range(-_prop_radius, _prop_radius)
		if sqrt(x * x + z * z) < PROP_CLEAR_RADIUS:
			continue
		var height: float = get_height(x, z)
		if height < get_water_level():
			# Nothing grows in the lake.
			continue
		var position: Vector3 = Vector3(x, height, z)
		if _is_too_close(position, occupied_positions):
			continue
		return position
	return Vector3.ZERO


## Returns the positions of the placed props.
func get_prop_positions() -> Array:
	return _prop_positions.duplicate()


## Reports whether a position is too close to an occupied position.
func _is_too_close(position: Vector3, occupied_positions: Array) -> bool:
	for occupied: Variant in occupied_positions:
		if not occupied is Vector3:
			continue
		var occupied_position: Vector3 = occupied
		if Vector2(position.x, position.z).distance_to(
			Vector2(occupied_position.x, occupied_position.z)
		) < PROP_CLEARANCE:
			return true
	return false


## Appends a quad of the terrain with the color and the normal of its height.
func _append_terrain_quad(
	surface: SurfaceTool,
	x0: float,
	z0: float,
	x1: float,
	z1: float,
) -> void:
	var corners: Array[Vector2] = [
		Vector2(x0, z0),
		Vector2(x0, z1),
		Vector2(x1, z1),
		Vector2(x1, z0),
	]
	# The corners wind clockwise from above, so the normals of the triangles
	# point up and the ground is lit from the sky.
	_append_terrain_triangle(surface, corners[0], corners[2], corners[1])
	_append_terrain_triangle(surface, corners[0], corners[3], corners[2])


## Appends a triangle of the terrain.
##
## The normal of every vertex is taken from the height field, so the ground is
## always lit from above.
func _append_terrain_triangle(
	surface: SurfaceTool,
	first: Vector2,
	second: Vector2,
	third: Vector2,
) -> void:
	for corner: Vector2 in [first, second, third]:
		var height: float = get_height(corner.x, corner.y)
		surface.set_color(_terrain_color(height))
		surface.set_normal(_terrain_normal(corner.x, corner.y))
		surface.add_vertex(Vector3(corner.x, height, corner.y))


## Returns the normal of the terrain at the given position.
func _terrain_normal(x: float, z: float) -> Vector3:
	var sample: float = 0.75
	var slope_x: float = get_height(x + sample, z) - get_height(x - sample, z)
	var slope_z: float = get_height(x, z + sample) - get_height(x, z - sample)
	return Vector3(-slope_x, 2.0 * sample, -slope_z).normalized()


## Returns the ground color for a height.
func _terrain_color(height: float) -> Color:
	var height_factor: float = clampf(
		(height + _height_scale) / maxf(_height_scale * 2.0, 0.001),
		0.0,
		1.0,
	)
	if height_factor > 0.72:
		return COLOR_ROCK.lerp(COLOR_GRASS_DARK, (1.0 - height_factor) / 0.28)
	if height_factor > 0.55:
		return COLOR_SAND.lerp(COLOR_ROCK, (height_factor - 0.55) / 0.17)
	return COLOR_GRASS.lerp(COLOR_GRASS_DARK, height_factor / 0.55)


## Appends a tree with a trunk and two crowns.
func _append_tree(
	surface: SurfaceTool,
	position: Vector3,
	tree_scale: float,
	random: RandomNumberGenerator,
) -> void:
	var trunk_height: float = 1.5 * tree_scale
	var trunk_radius: float = 0.16 * tree_scale
	_append_cylinder(surface, position, trunk_radius, trunk_height, COLOR_TRUNK)
	var crown_center: Vector3 = position + Vector3(0.0, trunk_height, 0.0)
	var crown_radius: float = 0.95 * tree_scale
	var crown_height: float = crown_radius * 1.15
	var lower_color: Color = COLOR_LEAVES.lerp(
		COLOR_LEAVES_LIGHT,
		random.randf(),
	)
	_append_cone(
		surface,
		crown_center,
		crown_radius,
		crown_height,
		lower_color,
	)
	_append_sphere(
		surface,
		crown_center + Vector3(0.0, crown_height * 0.55, 0.0),
		crown_radius * 0.62,
		COLOR_LEAVES_LIGHT.lerp(lower_color, random.randf() * 0.5),
	)


## Appends a rock.
func _append_rock(
	surface: SurfaceTool,
	position: Vector3,
	rock_scale: float,
) -> void:
	_append_sphere(
		surface,
		position + Vector3(0.0, rock_scale * 0.35, 0.0),
		rock_scale * 0.6,
		COLOR_ROCK.lerp(COLOR_SAND, 0.25),
	)


## Appends a cylinder that stands on the given position.
func _append_cylinder(
	surface: SurfaceTool,
	base: Vector3,
	radius: float,
	height: float,
	color: Color,
) -> void:
	var segments: int = 8
	for index: int in range(segments):
		var angle_a: float = TAU * float(index) / float(segments)
		var angle_b: float = TAU * float(index + 1) / float(segments)
		var bottom_a: Vector3 = base + Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
		var bottom_b: Vector3 = base + Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)
		var top_a: Vector3 = bottom_a + Vector3(0.0, height, 0.0)
		var top_b: Vector3 = bottom_b + Vector3(0.0, height, 0.0)
		_append_colored_triangle(surface, bottom_a, bottom_b, top_b, color)
		_append_colored_triangle(surface, bottom_a, top_b, top_a, color)


## Appends a cone that stands on the given position.
func _append_cone(
	surface: SurfaceTool,
	base: Vector3,
	radius: float,
	height: float,
	color: Color,
) -> void:
	var segments: int = 8
	var apex: Vector3 = base + Vector3(0.0, height, 0.0)
	for index: int in range(segments):
		var angle_a: float = TAU * float(index) / float(segments)
		var angle_b: float = TAU * float(index + 1) / float(segments)
		var edge_a: Vector3 = base + Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
		var edge_b: Vector3 = base + Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)
		_append_colored_triangle(surface, edge_a, edge_b, apex, color)


## Appends a sphere.
func _append_sphere(
	surface: SurfaceTool,
	center: Vector3,
	radius: float,
	color: Color,
) -> void:
	var rings: int = 5
	var segments: int = 8
	for ring: int in range(rings):
		var phi_a: float = PI * float(ring) / float(rings)
		var phi_b: float = PI * float(ring + 1) / float(rings)
		for segment: int in range(segments):
			var theta_a: float = TAU * float(segment) / float(segments)
			var theta_b: float = TAU * float(segment + 1) / float(segments)
			var first: Vector3 = center + _sphere_offset(radius, phi_a, theta_a)
			var second: Vector3 = center + _sphere_offset(radius, phi_b, theta_a)
			var third: Vector3 = center + _sphere_offset(radius, phi_b, theta_b)
			var fourth: Vector3 = center + _sphere_offset(radius, phi_a, theta_b)
			_append_colored_triangle(surface, first, second, third, color)
			_append_colored_triangle(surface, first, third, fourth, color)


## Returns the offset of a point of a sphere.
func _sphere_offset(radius: float, phi: float, theta: float) -> Vector3:
	return Vector3(
		radius * sin(phi) * cos(theta),
		radius * cos(phi),
		radius * sin(phi) * sin(theta),
	)


## Appends a triangle with a single color.
func _append_colored_triangle(
	surface: SurfaceTool,
	first: Vector3,
	second: Vector3,
	third: Vector3,
	color: Color,
) -> void:
	surface.set_color(color)
	surface.add_vertex(first)
	surface.set_color(color)
	surface.add_vertex(second)
	surface.set_color(color)
	surface.add_vertex(third)
