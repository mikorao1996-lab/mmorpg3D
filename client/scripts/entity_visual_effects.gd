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
