class_name WorldLiveness
extends RefCounted

## Builds the living layer of the world: the grass and the lake.
##
## The grass is one MultiMesh, so thousands of tufts cost one draw call, and a
## shader bends their tips in the wind. The lake is a flat surface at the
## water level, and the depth of the ground under every vertex of it is baked
## into the vertex color, so the shader can colour the water from the shallow
## blue to the deep one and draw the foam along the shore.
##
## Both need the height of the terrain, so the builder of the landscape is
## passed to every call and asked for the height of every point.

const FoliageShaderType: Shader = preload("res://client/shaders/foliage_wind.gdshader")
const WaterShaderType: Shader = preload("res://client/shaders/stylized_water.gdshader")

const FOLIAGE_SEED: int = 42019
const FOLIAGE_CLEAR_RADIUS: float = 4.0
const GRASS_CLUMP_WIDTH: float = 0.1
const GRASS_CLUMP_HEIGHT: float = 0.46
const FOLIAGE_RADIUS: float = 58.0
const LAKE_MAX_DEPTH: float = 6.0
const LAKE_SUBDIVISIONS: int = 64


## Builds the layer of grass of the map.
##
## The tufts stand on the ground of the terrain, they keep away from the plaza
## of the hub, and they do not grow in the lake.
func build_foliage_layer(
	builder: RefCounted,
	parent: Node3D,
	count: int = 0,
) -> MultiMeshInstance3D:
	var instance_count: int = count if count > 0 else builder.get_foliage_count()
	var placements: Array[Dictionary] = compute_foliage_placements(builder, instance_count)
	var multi_mesh: MultiMesh = MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = true
	multi_mesh.mesh = _create_grass_clump_mesh()
	multi_mesh.instance_count = placements.size()

	for index: int in range(placements.size()):
		multi_mesh.set_instance_transform(index, placements[index]["transform"])
		multi_mesh.set_instance_color(index, placements[index]["color"])

	multi_mesh.visible_instance_count = placements.size()
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = "FoliageMultiMesh"
	instance.multimesh = multi_mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## Places the tufts of grass.
##
## The placement is calculated on the CPU, so it can be checked without a
## renderer, and it is the same in every session.
func compute_foliage_placements(builder: RefCounted, count: int) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = FOLIAGE_SEED
	var water_level: float = builder.get_water_level()
	var hub_radius: float = builder.get_hub_radius()
	var attempts: int = 0
	while placements.size() < count and attempts < count * 4:
		attempts += 1
		# The grass grows around the hub, where the player walks, and not over
		# the whole map, so every tuft is worth its place.
		var angle: float = random.randf_range(0.0, TAU)
		var distance: float = sqrt(random.randf()) * FOLIAGE_RADIUS
		var x: float = cos(angle) * distance
		var z: float = sin(angle) * distance
		if Vector2(x, z).length() < hub_radius + FOLIAGE_CLEAR_RADIUS:
			continue
		var height: float = builder.get_height(x, z)
		if height < water_level:
			continue
		var transform: Transform3D = Transform3D.IDENTITY
		transform = transform.rotated(Vector3.UP, random.randf_range(0.0, TAU))
		var scale_xz: float = random.randf_range(0.75, 1.35)
		var scale_y: float = random.randf_range(0.65, 1.45)
		transform = transform.scaled(Vector3(scale_xz, scale_y, scale_xz))
		transform.origin = Vector3(x, height, z)
		var tint: float = random.randf_range(0.85, 1.15)
		var biome: Color = builder.get_terrain_color(height)
		var biome_tint: Color = Color(1.0, 1.0, 1.0).lerp(biome * 2.4, 0.65)
		placements.append({
			"transform": transform,
			"color": biome_tint * tint,
			"position": transform.origin,
		})
	return placements


## Returns the positions of the tufts of grass.
func get_foliage_positions(builder: RefCounted) -> Array:
	var positions: Array = []
	for placement: Dictionary in compute_foliage_placements(
		builder,
		builder.get_foliage_count(),
	):
		positions.append(placement["position"])
	return positions


## Builds the mesh of a tuft of grass.
##
## The tuft is three crossed blades, so it has a shape from every side.
func _create_grass_clump_mesh() -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle_degrees: float in [0.0, 60.0, 120.0]:
		var rotation: Basis = Basis(Vector3.UP, deg_to_rad(angle_degrees))
		var width: float = GRASS_CLUMP_WIDTH
		var height: float = GRASS_CLUMP_HEIGHT
		var bottom_left: Vector3 = rotation * Vector3(-width, 0.0, 0.0)
		var bottom_right: Vector3 = rotation * Vector3(width, 0.0, 0.0)
		var tip_right: Vector3 = rotation * Vector3(width * 0.7, height, 0.0)
		var tip_left: Vector3 = rotation * Vector3(-width * 0.7, height, 0.0)

		surface.set_uv(Vector2(0.0, 1.0))
		surface.add_vertex(bottom_left)
		surface.set_uv(Vector2(1.0, 1.0))
		surface.add_vertex(bottom_right)
		surface.set_uv(Vector2(1.0, 0.0))
		surface.add_vertex(tip_right)

		surface.set_uv(Vector2(0.0, 1.0))
		surface.add_vertex(bottom_left)
		surface.set_uv(Vector2(1.0, 0.0))
		surface.add_vertex(tip_right)
		surface.set_uv(Vector2(0.0, 0.0))
		surface.add_vertex(tip_left)
	surface.generate_normals()

	var mesh: ArrayMesh = surface.commit()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = FoliageShaderType
	mesh.surface_set_material(0, material)
	return mesh


## Builds the surface of the lake.
##
## The lake is a flat surface at the water level, and the shore of the lake is
## the line where the ground of the terrain rises through it. The depth of the
## ground under every vertex is baked into the vertex color, so the shader can
## colour the water and draw the foam along the shore. The quads that stand on
## dry ground are not built, so the water never floats over the land.
func build_water(builder: RefCounted, parent: Node3D) -> MeshInstance3D:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water_level: float = builder.get_water_level()
	var lake_size: float = builder.get_lake_size()
	var step: float = lake_size / float(LAKE_SUBDIVISIONS)
	var origin_x: float = builder.get_lake_center().x - lake_size * 0.5
	var origin_z: float = builder.get_lake_center().z - lake_size * 0.5
	for z_index: int in range(LAKE_SUBDIVISIONS):
		for x_index: int in range(LAKE_SUBDIVISIONS):
			var x0: float = origin_x + float(x_index) * step
			var z0: float = origin_z + float(z_index) * step
			_append_water_quad(builder, surface, x0, z0, x0 + step, z0 + step, water_level)
	surface.generate_normals()

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = WaterShaderType
	material.set_shader_parameter("max_depth", LAKE_MAX_DEPTH)
	surface.set_material(material)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Water"
	mesh_instance.mesh = surface.commit()
	mesh_instance.position = Vector3(0.0, water_level, 0.0)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_instance)
	return mesh_instance


## Appends a quad of the water surface.
##
## The quad is skipped when every corner stands on dry ground.
func _append_water_quad(
	builder: RefCounted,
	surface: SurfaceTool,
	x0: float,
	z0: float,
	x1: float,
	z1: float,
	water_level: float,
) -> void:
	var corners: Array[Vector2] = [
		Vector2(x0, z0),
		Vector2(x0, z1),
		Vector2(x1, z1),
		Vector2(x1, z0),
	]
	var depths: Array[float] = []
	var submerged: bool = false
	for corner: Vector2 in corners:
		if not builder.is_inside_map(corner.x, corner.y):
			return
		var depth: float = maxf(water_level - builder.get_height(corner.x, corner.y), 0.0)
		depths.append(depth)
		if depth > 0.0:
			submerged = true
	if not submerged:
		return
	# The corners wind clockwise from above, so the normals of the triangles
	# point up and the surface of the lake is lit from the sky.
	_append_water_triangle(surface, corners[0], depths[0], corners[2], depths[2], corners[1], depths[1])
	_append_water_triangle(surface, corners[0], depths[0], corners[3], depths[3], corners[2], depths[2])


## Appends a triangle of the water surface.
##
## The red channel of the vertex color holds the depth of the ground, scaled by
## `LAKE_MAX_DEPTH`.
func _append_water_triangle(
	surface: SurfaceTool,
	first: Vector2,
	first_depth: float,
	second: Vector2,
	second_depth: float,
	third: Vector2,
	third_depth: float,
) -> void:
	var corners: Array[Vector2] = [first, second, third]
	var depths: Array[float] = [first_depth, second_depth, third_depth]
	for index: int in range(3):
		var corner: Vector2 = corners[index]
		var depth: float = depths[index]
		surface.set_color(Color(clampf(depth / LAKE_MAX_DEPTH, 0.0, 1.0), 0.0, 0.0, 1.0))
		surface.add_vertex(Vector3(corner.x, 0.0, corner.y))
