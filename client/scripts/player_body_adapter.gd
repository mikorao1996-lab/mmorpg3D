class_name PlayerBodyAdapter
extends CharacterBody3D

## The body of a player in the world.
##
## The adapter follows the server simulation and carries the nameplate that
## shows the level, the health, and the resource of the character.

const BAR_WIDTH: float = 1.2
const BAR_HEIGHT: float = 0.14
const BAR_SPACING: float = 0.22

var _nameplate: Node3D = null
var _level_label: Label3D = null
var _health_fill: MeshInstance3D = null
var _resource_fill: MeshInstance3D = null


func move_to_simulated_position(target_position: Vector3, delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		push_error("Player body adapter requires a positive finite physics delta")
		return

	velocity = (target_position - global_position) / delta
	move_and_slide()
	velocity = Vector3.ZERO


func set_simulated_position(target_position: Vector3) -> void:
	global_position = target_position
	velocity = Vector3.ZERO


## Builds the nameplate above the character.
##
## The plate shows the level of the character, a bar for the health, and a bar
## for the resource. Both bars are billboards, so they always face the camera.
func build_nameplate(plate_height: float) -> void:
	if _nameplate != null:
		return
	_nameplate = Node3D.new()
	_nameplate.name = "Nameplate"
	_nameplate.position.y = plate_height
	add_child(_nameplate)

	_level_label = Label3D.new()
	_level_label.name = "LevelLabel"
	_level_label.text = tr("nameplate_level") % 1
	_level_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_level_label.font_size = 64
	_level_label.pixel_size = 0.007
	_level_label.position.y = BAR_HEIGHT + 0.26
	_level_label.outline_size = 14
	_level_label.outline_modulate = Color(0.05, 0.05, 0.08, 0.9)
	_level_label.no_depth_test = true
	_level_label.render_priority = 6
	_nameplate.add_child(_level_label)

	_health_fill = _build_bar("HealthFill", Color(0.83, 0.24, 0.2))
	_health_fill.position.y = 0.16
	_nameplate.add_child(_health_fill)

	_resource_fill = _build_bar("ResourceFill", Color(0.29, 0.58, 0.95))
	_resource_fill.position.y = 0.16 - BAR_SPACING
	_nameplate.add_child(_resource_fill)


## Updates the nameplate with the state of the character.
func update_nameplate(
	level: int,
	health: float,
	max_health: float,
	resource: float,
	max_resource: float,
) -> void:
	if _level_label == null:
		return
	_level_label.text = tr("nameplate_level") % level
	_update_bar(_health_fill, health, max_health)
	_update_bar(_resource_fill, resource, max_resource)


## Builds a bar of the nameplate.
func _build_bar(bar_name: String, color: Color) -> MeshInstance3D:
	var background_quad: QuadMesh = QuadMesh.new()
	background_quad.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	var background_material: StandardMaterial3D = StandardMaterial3D.new()
	background_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	background_material.albedo_color = Color(0.08, 0.08, 0.1, 0.75)
	background_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	background_material.no_depth_test = true
	background_material.render_priority = 4
	background_quad.material = background_material
	var background: MeshInstance3D = MeshInstance3D.new()
	background.name = "%sBackground" % bar_name
	background.mesh = background_quad
	_nameplate.add_child(background)

	var fill_quad: QuadMesh = QuadMesh.new()
	fill_quad.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	var fill_material: StandardMaterial3D = StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.albedo_color = color
	fill_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_material.no_depth_test = true
	fill_material.render_priority = 5
	fill_quad.material = fill_material
	var fill: MeshInstance3D = MeshInstance3D.new()
	fill.name = bar_name
	fill.mesh = fill_quad
	return fill


## Sets the length of a bar.
##
## The bar grows from its left edge, so the filled part stays aligned with the
## left side of the background.
func _update_bar(bar: MeshInstance3D, value: float, maximum: float) -> void:
	if bar == null:
		return
	var quad: QuadMesh = bar.mesh as QuadMesh
	if quad == null:
		return
	var ratio: float = 0.0
	if maximum > 0.0:
		ratio = clampf(value / maximum, 0.0, 1.0)
	var width: float = BAR_WIDTH * ratio
	quad.size = Vector2(maxf(width, 0.001), BAR_HEIGHT)
	quad.center_offset = Vector3(-(BAR_WIDTH - width) * 0.5, 0.0, 0.0)
