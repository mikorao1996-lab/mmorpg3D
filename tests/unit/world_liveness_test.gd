extends RefCounted

## Checks the living layer of the world: the grass and the lake.
##
## The grass has to stand on the ground, to keep away from the plaza of the
## hub and from the lake, and to be placed the same way in every session. The
## lake has to be baked with the depth of the ground under every vertex, so
## the shader can colour the water and draw the foam along the shore.

const WorldBuilderType: GDScript = preload("res://client/scripts/world_builder.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")

const SAMPLE_FOLIAGE_COUNT: int = 512


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	if config.is_empty():
		return false

	var builder: RefCounted = WorldBuilderType.new(config)
	var hub_radius: float = float(config["terrain_hub_radius"])
	var water_level: float = builder.get_water_level()

	var parent: Node3D = Node3D.new()
	var foliage: MultiMeshInstance3D = builder.build_foliage_layer(parent, SAMPLE_FOLIAGE_COUNT)
	if foliage == null or foliage.multimesh == null:
		push_error("The world builder did not build a layer of grass")
		return false
	var multi_mesh: MultiMesh = foliage.multimesh
	if multi_mesh.mesh == null:
		push_error("The layer of grass has no tuft mesh")
		return false
	if multi_mesh.visible_instance_count != SAMPLE_FOLIAGE_COUNT:
		push_error("The layer of grass has the wrong number of tufts")
		return false
	if multi_mesh.mesh.surface_get_array_len(0) <= 0:
		push_error("The tuft of grass is an empty mesh")
		return false

	var positions: Array = builder.get_foliage_positions()
	if positions.size() != int(config["foliage_count"]):
		push_error("The layer of grass has the wrong number of tufts")
		return false
	for position: Vector3 in positions:
		if position.y < water_level - 0.01:
			push_error("A tuft of grass grows in the lake")
			return false
		if Vector2(position.x, position.z).length() < hub_radius + 3.9:
			push_error("A tuft of grass grows on the plaza of the hub")
			return false

	var second_builder: RefCounted = WorldBuilderType.new(config)
	var second_parent: Node3D = Node3D.new()
	var second_foliage: MultiMeshInstance3D = second_builder.build_foliage_layer(
		second_parent,
		SAMPLE_FOLIAGE_COUNT,
	)
	var second_positions: Array = second_builder.get_foliage_positions()
	if second_positions.size() != positions.size():
		push_error("The placement of the grass is not reproducible")
		return false
	if second_positions[0] != positions[0]:
		push_error("The placement of the grass is not reproducible")
		return false

	var water: MeshInstance3D = builder.build_water(parent)
	if water.mesh == null:
		push_error("The world builder did not build the surface of the lake")
		return false
	if not is_equal_approx(water.position.y, water_level):
		push_error("The surface of the lake is not at the level of the water")
		return false
	var arrays: Array = water.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if vertices.is_empty():
		push_error("The surface of the lake is empty")
		return false
	if vertices.size() != colors.size():
		push_error("The depth of the lake is not baked into the vertices")
		return false

	var deepest: float = 0.0
	var shallowest: float = 1.0
	for index: int in range(vertices.size()):
		var vertex: Vector3 = vertices[index]
		var color: Color = colors[index]
		if Vector2(vertex.x, vertex.z).length() < hub_radius:
			push_error("The lake covers the plaza of the hub")
			return false
		if color.r <= 0.0:
			continue
		deepest = maxf(deepest, color.r)
		shallowest = minf(shallowest, color.r)
	if deepest <= 0.05:
		push_error("The lake has no deep water")
		return false
	if shallowest >= 0.05:
		push_error("The lake has no shore to draw the foam on")
		return false

	foliage.free()
	water.free()
	parent.free()
	second_foliage.free()
	second_parent.free()
	return true
