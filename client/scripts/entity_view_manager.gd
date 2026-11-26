class_name EntityViewManager
extends RefCounted

## The bodies of the entities in the world.
##
## The manager owns the views of the players, the mobs, the NPCs, and the drops,
## the nameplates above the players, the ring that marks the current target,
## and the flash that shows that an entity was hit. The client scene keeps the
## dictionaries of the views, so the rest of the client can reach them without
## knowing where the views are built.

const PlayerBodyAdapterType: GDScript = preload("res://client/scripts/player_body_adapter.gd")
const EntityVisualEffectsType: GDScript = preload("res://client/scripts/entity_visual_effects.gd")

var player_views: Dictionary = {}
var mob_views: Dictionary = {}
var npc_views: Dictionary = {}
var drop_views: Dictionary = {}
var mob_types_by_instance: Dictionary = {}

var _root: Node3D = null
var _config: Dictionary = {}
var _registry: Dictionary = {}
var _target_ring: MeshInstance3D = null
var _target_view: Node3D = null
var _previous_health: Dictionary = {}


## Connects the manager to the scene and to the game data.
func setup(root: Node3D, config: Dictionary, registry: Dictionary) -> void:
	_root = root
	_config = config
	_registry = registry
	if _root == null:
		return
	_target_ring = EntityVisualEffectsType.create_target_ring(1.0, Color(1.0, 1.0, 1.0))
	_root.add_child(_target_ring)


## Returns the definition of a mob.
##
## A mob type can have several instances in the zone, so the definition is
## looked up by the type of the instance.
func mob_definition(mob_id: String) -> Dictionary:
	var mob_type: String = str(mob_types_by_instance.get(mob_id, mob_id))
	return _registry.get("mobs", {}).get(mob_type, {})


## Builds the view of a player.
func ensure_player_view(peer_id: int) -> void:
	if player_views.has(peer_id) or _root == null:
		return
	var player_view: PlayerBodyAdapter = PlayerBodyAdapterType.new()
	player_view.name = "Player_%d" % peer_id
	player_view.collision_layer = 0
	player_view.collision_mask = 0
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = float(_config["player_visual_radius"])
	capsule.height = float(_config["player_visual_height"])
	mesh_instance.mesh = capsule
	mesh_instance.material_override = StandardMaterial3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.position.y = capsule.height / 2.0
	player_view.add_child(mesh_instance)
	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
	capsule_shape.radius = float(_config["player_visual_radius"])
	capsule_shape.height = float(_config["player_visual_height"])
	collision_shape.shape = capsule_shape
	collision_shape.position.y = capsule_shape.height / 2.0
	player_view.add_child(collision_shape)
	player_view.build_nameplate(capsule.height + 0.45)
	_root.add_child(player_view)
	player_views[peer_id] = player_view
	set_player_color(peer_id, Color(0.25, 0.7, 0.95))


## Builds the view of a mob.
func ensure_mob_view(mob_id: String) -> void:
	if mob_views.has(mob_id) or _root == null:
		return
	var mob_definition: Dictionary = mob_definition(mob_id)
	var mob_view: Node3D = Node3D.new()
	mob_view.name = "Mob_%s" % mob_id
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = float(mob_definition.get("visual_radius", 0.5))
	capsule.height = float(mob_definition.get("visual_height", 1.0))
	mesh_instance.mesh = capsule
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = (
		Color(0.78, 0.24, 0.2)
		if bool(mob_definition.get("is_boss", false))
		else Color(0.35, 0.78, 0.38)
	)
	mesh_instance.material_override = material
	mesh_instance.position.y = capsule.height / 2.0
	mob_view.add_child(mesh_instance)
	_root.add_child(mob_view)
	mob_views[mob_id] = mob_view


## Builds the view of an NPC.
func ensure_npc_view(npc_id: String) -> void:
	if npc_views.has(npc_id) or _root == null:
		return
	var npc_view: Node3D = Node3D.new()
	npc_view.name = "Npc_%s" % npc_id
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = float(_config["player_visual_radius"])
	capsule.height = float(_config["player_visual_height"])
	mesh_instance.mesh = capsule
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.72, 0.3)
	mesh_instance.material_override = material
	mesh_instance.position.y = capsule.height / 2.0
	npc_view.add_child(mesh_instance)
	_root.add_child(npc_view)
	npc_views[npc_id] = npc_view


## Builds the view of a drop.
func ensure_loot_view(drop_id: int) -> void:
	if drop_views.has(drop_id) or _root == null:
		return
	var loot_view: MeshInstance3D = MeshInstance3D.new()
	loot_view.name = "Loot_%d" % drop_id
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = float(_config["loot_visual_radius"])
	sphere.height = sphere.radius * 2.0
	loot_view.mesh = sphere
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.78, 0.2)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.78, 0.2)
	material.emission_energy_multiplier = 0.6
	loot_view.material_override = material
	_root.add_child(loot_view)
	drop_views[drop_id] = loot_view


## Removes the view of a player.
func remove_player_view(peer_id: int) -> void:
	if not player_views.has(peer_id):
		return
	var player_view: Node3D = player_views[peer_id]
	player_view.queue_free()
	player_views.erase(peer_id)
	_previous_health.erase("player_%d" % peer_id)


## Removes the view of a mob.
func remove_mob_view(mob_id: String) -> void:
	if not mob_views.has(mob_id):
		return
	var mob_view: Node3D = mob_views[mob_id]
	mob_view.queue_free()
	mob_views.erase(mob_id)
	_previous_health.erase("mob_%s" % mob_id)


## Removes the view of an NPC.
func remove_npc_view(npc_id: String) -> void:
	if not npc_views.has(npc_id):
		return
	var npc_view: Node3D = npc_views[npc_id]
	npc_view.queue_free()
	npc_views.erase(npc_id)


## Removes the view of a drop.
func remove_drop_view(drop_id: int) -> void:
	if not drop_views.has(drop_id):
		return
	var drop_view: Node3D = drop_views[drop_id]
	drop_view.queue_free()
	drop_views.erase(drop_id)


## Sets the color of the body of a player.
func set_player_color(peer_id: int, color: Color) -> void:
	var player_view: PlayerBodyAdapter = player_views.get(peer_id)
	if player_view == null:
		return
	var mesh_instance: MeshInstance3D = player_view.get_node("Visual")
	var material: StandardMaterial3D = mesh_instance.material_override
	material.albedo_color = color


## Updates the nameplates above the players.
##
## The plate of a player shows the level, the health, and the resource that the
## server reported for it.
func update_nameplates(player_health_states: Dictionary) -> void:
	for player_id: Variant in player_health_states:
		var player_view: PlayerBodyAdapter = player_views.get(player_id)
		if player_view == null:
			continue
		var state: Dictionary = player_health_states[player_id]
		player_view.update_nameplate(
			int(state.get("level", 1)),
			float(state.get("health", 0.0)),
			float(state.get("max_health", 1.0)),
			float(state.get("resource", 0.0)),
			float(state.get("max_resource", 1.0)),
		)


## Flashes the entities that lost health in the last snapshot.
##
## The server reports the health of the mobs and of the players, so a drop of
## the value means that the entity was hit.
func flash_damaged_entities(
	mob_states: Dictionary,
	player_health_states: Dictionary,
) -> void:
	for mob_id: String in mob_states:
		_flash_if_hurt("mob_%s" % mob_id, float(mob_states[mob_id].get("health", 0.0)), mob_id)
	for player_id: Variant in player_health_states:
		_flash_if_hurt(
			"player_%d" % int(player_id),
			float(player_health_states[player_id].get("health", 0.0)),
			"",
			int(player_id),
		)


## Flashes an entity when its health dropped since the last snapshot.
func _flash_if_hurt(key: String, health: float, mob_id: String, player_id: int = 0) -> void:
	var previous: float = float(_previous_health.get(key, health))
	_previous_health[key] = health
	if previous <= 0.0 or health >= previous:
		return
	var view: Node3D = null
	if not mob_id.is_empty():
		view = mob_views.get(mob_id)
	else:
		view = player_views.get(player_id)
	if view == null:
		return
	var mesh_instance: Node3D = view.get_node_or_null("Visual")
	if mesh_instance == null:
		return
	var material: StandardMaterial3D = mesh_instance.material_override
	if not material is StandardMaterial3D:
		return
	EntityVisualEffectsType.flash_damage(view, material)


## Marks the entity the player aims at.
##
## The ring follows the view of the target and changes its color with the kind
## of the target.
func set_target(kind: String, view: Node3D, radius: float, ground_height: float) -> void:
	if _target_ring == null:
		return
	if view == null:
		_target_view = null
		_target_ring.visible = false
		return
	_target_view = view
	_target_ring.visible = true
	var color: Color = EntityVisualEffectsType.target_color(kind)
	var material: StandardMaterial3D = _target_ring.mesh.surface_get_material(0)
	material.albedo_color = Color(color.r, color.g, color.b, 0.85)
	material.emission = color
	var torus: TorusMesh = _target_ring.mesh as TorusMesh
	if torus != null:
		torus.inner_radius = maxf(radius * 0.82, 0.05)
		torus.outer_radius = maxf(radius, 0.08)


## Moves the ring of the target onto the entity.
func update_target_position() -> void:
	if _target_ring == null or _target_view == null:
		return
	_target_ring.global_position = Vector3(
		_target_view.global_position.x,
		_target_view.global_position.y + EntityVisualEffectsType.RING_HEIGHT,
		_target_view.global_position.z,
	)
