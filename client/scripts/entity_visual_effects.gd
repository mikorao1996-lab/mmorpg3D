class_name EntityVisualEffects
extends RefCounted

## The visual feedback of the entities in the world.
##
## A ring under the selected entity shows what the player is aiming at, and a
## short flash shows that an entity was hit. Both are decoration: the server
## decides what really happened, and the client only shows it.

const TARGET_COLOR_ENEMY: Color = Color(0.95, 0.25, 0.2)
const TARGET_COLOR_ALLY: Color = Color(0.35, 0.9, 0.45)
const TARGET_COLOR_QUEST: Color = Color(0.95, 0.78, 0.3)
const FLASH_COLOR: Color = Color(1.0, 0.42, 0.3)
const FLASH_DURATION_SECONDS: float = 0.12
const RING_HEIGHT: float = 0.06
const TEXT_RISE_SECONDS: float = 0.85
const TEXT_FADE_SECONDS: float = 0.45
const TEXT_RISE_DISTANCE: float = 1.25


## Returns the color of the ring for a kind of target.
##
## The kinds are `enemy`, `ally`, and `quest`.
static func target_color(kind: String) -> Color:
	match kind:
		"ally":
			return TARGET_COLOR_ALLY
		"quest":
			return TARGET_COLOR_QUEST
	return TARGET_COLOR_ENEMY


## Builds the ring that marks the selected entity.
##
## The ring lies flat on the ground under the entity and glows, so it stays
## readable in any light.
static func create_target_ring(radius: float, color: Color) -> MeshInstance3D:
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = maxf(radius * 0.82, 0.05)
	torus.outer_radius = maxf(radius, 0.08)
	torus.rings = 24
	torus.ring_segments = 8

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.85)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.8
	material.no_depth_test = false
	torus.material = material

	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "TargetRing"
	ring.mesh = torus
	ring.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	ring.position.y = RING_HEIGHT
	ring.visible = false
	return ring


## Shows the number of the damage or of the healing over an entity.
##
## The number floats up and fades away. The kind decides the look: `damage`,
## `heal`, `crit`, and `miss` are the kinds of the text.
static func spawn_floating_combat_text(
	parent: Node3D,
	world_position: Vector3,
	amount: int,
	kind: String = "damage",
) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var label: Label3D = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.0065
	label.outline_size = 10
	label.outline_modulate = Color(0.05, 0.05, 0.08, 0.95)
	label.render_priority = 8

	match kind:
		"crit":
			label.text = "%d!" % amount
			label.modulate = Color(1.0, 0.82, 0.22)
			label.scale = Vector3.ONE * 1.35
		"heal":
			label.text = "+%d" % amount
			label.modulate = Color(0.28, 0.95, 0.45)
		"miss":
			label.text = TranslationServer.translate("combat_text_miss")
			label.modulate = Color(0.75, 0.78, 0.82)
		_:
			label.text = "-%d" % amount
			label.modulate = Color(1.0, 0.32, 0.28)

	# The numbers of a series of hits spread out a little.
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.randomize()
	label.position = world_position + Vector3(
		random.randf_range(-0.35, 0.35),
		2.1,
		random.randf_range(-0.35, 0.35),
	)
	parent.add_child(label)

	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		label,
		"position:y",
		label.position.y + TEXT_RISE_DISTANCE,
		TEXT_RISE_SECONDS,
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		label,
		"modulate:a",
		0.0,
		TEXT_FADE_SECONDS,
	).set_delay(TEXT_RISE_SECONDS * 0.45)
	tween.chain().tween_callback(label.queue_free)


## Flashes the material of an entity that was hit.
##
## The flash is short: the color returns to the color of the entity, so the
## next hit starts from the same place.
static func flash_damage(node: Node, material: StandardMaterial3D) -> void:
	if node == null or material == null or not node.is_inside_tree():
		return
	var base_color: Color = material.albedo_color
	material.emission_enabled = true
	material.emission = FLASH_COLOR
	var tween: Tween = node.create_tween()
	tween.tween_property(
		material,
		"albedo_color",
		FLASH_COLOR,
		FLASH_DURATION_SECONDS * 0.35,
	)
	tween.parallel().tween_property(
		material,
		"emission_energy_multiplier",
		2.0,
		FLASH_DURATION_SECONDS * 0.35,
	)
	tween.tween_property(
		material,
		"albedo_color",
		base_color,
		FLASH_DURATION_SECONDS * 0.65,
	)
	tween.parallel().tween_property(
		material,
		"emission_energy_multiplier",
		0.0,
		FLASH_DURATION_SECONDS * 0.65,
	)
