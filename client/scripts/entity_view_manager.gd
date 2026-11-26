class_name EntityViewManager
extends RefCounted

## The bodies of the entities in the world.
##
## The manager owns the views of the players, the mobs, the NPCs, and the drops,
## the nameplates above them, the ring that marks the current target, and the
## flash and the floating numbers that show that an entity was hit. The client
## scene keeps the dictionaries of the views, so the rest of the client can
## reach them without knowing where the views are built.

const PlayerBodyAdapterType: GDScript = preload("res://client/scripts/player_body_adapter.gd")
const EntityVisualEffectsType: GDScript = preload("res://client/scripts/entity_visual_effects.gd")

const NAMEPLATE_WIDTH: float = 1.1
const NAMEPLATE_HEIGHT: float = 0.11
const NAMEPLATE_BAR_OFFSET: float = 0.2
const NAMEPLATE_LABEL_OFFSET: float = 0.14

const NAME_COLOR_PLAYER: Color = Color(0.55, 0.85, 1.0)
const NAME_COLOR_PARTY: Color = Color(0.35, 0.95, 0.45)
const NAME_COLOR_NPC: Color = Color(1.0, 0.86, 0.38)
const NAME_COLOR_MOB: Color = Color(1.0, 0.38, 0.34)
const QUEST_MARKER_READY: String = "!"
const QUEST_MARKER_AVAILABLE: String = "?"

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
var _player_names: Dictionary = {}
var _party_members: Dictionary = {}
var _mob_nameplates: Dictionary = {}
var _npc_nameplates: Dictionary = {}


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
	var name_label: Dictionary = _build_nameplate(
		mob_view,
		capsule.height + 0.4,
		NAME_COLOR_MOB,
	)
	name_label["label"].text = tr("nameplate_mob_name") % [
		tr(str(mob_definition.get("name_key", mob_id))),
		int(mob_definition.get("level", 1)),
	]
	_mob_nameplates[mob_id] = name_label


## Builds the view of an NPC.
func ensure_npc_view(npc_id: String) -> void:
	if npc_views.has(npc_id) or _root == null:
		return
	var npc_definition: Dictionary = _registry.get("npcs", {}).get(npc_id, {})
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
	var nameplate: Dictionary = _build_nameplate(
		npc_view,
		capsule.height + 0.4,
		NAME_COLOR_NPC,
	)
	nameplate["label"].text = tr(str(npc_definition.get("name_key", npc_id)))
	_npc_nameplates[npc_id] = nameplate


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
	_player_names.erase(peer_id)
	_previous_health.erase("player_%d" % peer_id)


## Removes the view of a mob.
func remove_mob_view(mob_id: String) -> void:
	if not mob_views.has(mob_id):
		return
	var mob_view: Node3D = mob_views[mob_id]
	mob_view.queue_free()
	mob_views.erase(mob_id)
	_mob_nameplates.erase(mob_id)
	_previous_health.erase("mob_%s" % mob_id)


## Removes the view of an NPC.
func remove_npc_view(npc_id: String) -> void:
	if not npc_views.has(npc_id):
		return
	var npc_view: Node3D = npc_views[npc_id]
	npc_view.queue_free()
	npc_views.erase(npc_id)
	_npc_nameplates.erase(npc_id)


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


## Remembers the name of a player.
func set_player_name(peer_id: int, player_name: String) -> void:
	if player_name.strip_edges().is_empty():
		return
	_player_names[peer_id] = player_name


## Remembers the members of the party of the player.
##
## The names of the members of the party are green, so the player sees who
## belongs to the group. The server sends the members as dictionaries with the
## peer and the name of every member.
func set_party_members(members: Array) -> void:
	_party_members.clear()
	for member: Variant in members:
		var peer_id: int = 0
		if member is Dictionary:
			peer_id = int((member as Dictionary).get("peer_id", 0))
		elif member is int or member is float:
			peer_id = int(member)
		if peer_id == 0:
			continue
		_party_members[peer_id] = true


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
		var name_label: Label3D = player_view.get_node_or_null("Nameplate/LevelLabel")
		if name_label == null:
			continue
		var display_name: String = str(_player_names.get(player_id, ""))
		var color: Color = (
			NAME_COLOR_PARTY
			if _party_members.has(int(player_id))
			else NAME_COLOR_PLAYER
		)
		name_label.modulate = color
		if display_name.is_empty():
			name_label.text = tr("nameplate_level") % int(state.get("level", 1))
		else:
			name_label.text = tr("nameplate_player_name") % [
				display_name,
				int(state.get("level", 1)),
			]


## Updates the nameplates of the mobs and of the NPCs.
##
## The bar of a mob shows only when it lost health or when it is the target,
## so the screen stays clean in a peaceful zone.
func update_entity_nameplates(
	mob_states: Dictionary,
	quest_states: Array,
	target_mob_id: String,
) -> void:
	for mob_id: String in mob_states:
		var nameplate: Dictionary = _mob_nameplates.get(mob_id, {})
		if nameplate.is_empty():
			continue
		var state: Dictionary = mob_states[mob_id]
		var health: float = float(state.get("health", 0.0))
		var max_health: float = float(state.get("max_health", 1.0))
		_update_nameplate_bar(nameplate, health, max_health, mob_id == target_mob_id)
	for npc_id: String in _npc_nameplates:
		var nameplate: Dictionary = _npc_nameplates[npc_id]
		nameplate["marker"].text = _quest_marker(npc_id, quest_states)


## Shows the marker of the quests above an NPC.
##
## The marker is `!` when a quest is ready to be handed in, and `?` when a
## quest is available or in progress.
func _quest_marker(npc_id: String, quest_states: Array) -> String:
	var npc_definition: Dictionary = _registry.get("npcs", {}).get(npc_id, {})
	var quest_ids: Array = npc_definition.get("quest_ids", [])
	if quest_ids.is_empty():
		return ""
	var status_by_quest: Dictionary = {}
	for entry: Variant in quest_states:
		if entry is Array and (entry as Array).size() > 1:
			status_by_quest[str((entry as Array)[0])] = str((entry as Array)[1])
	for quest_id: Variant in quest_ids:
		if str(status_by_quest.get(str(quest_id), "")) == "completed":
			return QUEST_MARKER_READY
	for quest_id: Variant in quest_ids:
		var status: String = str(status_by_quest.get(str(quest_id), ""))
		if status == "active" or status.is_empty():
			return QUEST_MARKER_AVAILABLE
	return ""


## Builds the nameplate of a mob or of an NPC.
##
## The plate carries the name, the marker of the quests, and a bar of the
## health that stays hidden while the entity is untouched.
func _build_nameplate(view: Node3D, plate_height: float, color: Color) -> Dictionary:
	var plate: Node3D = Node3D.new()
	plate.name = "Nameplate"
	plate.position.y = plate_height
	view.add_child(plate)

	var label: Label3D = Label3D.new()
	label.name = "NameLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.007
	label.position.y = NAMEPLATE_BAR_OFFSET + NAMEPLATE_LABEL_OFFSET
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.05, 0.08, 0.9)
	label.no_depth_test = true
	label.render_priority = 6
	label.modulate = color
	plate.add_child(label)

	var marker: Label3D = Label3D.new()
	marker.name = "QuestMarker"
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.font_size = 64
	marker.pixel_size = 0.006
	marker.position.y = NAMEPLATE_BAR_OFFSET + NAMEPLATE_LABEL_OFFSET * 2.2
	marker.outline_size = 14
	marker.outline_modulate = Color(0.05, 0.05, 0.08, 0.9)
	marker.no_depth_test = true
	marker.render_priority = 6
	marker.modulate = NAME_COLOR_NPC
	plate.add_child(marker)

	var background: MeshInstance3D = _build_bar_quad(
		"HealthBarBackground",
		Color(0.08, 0.08, 0.1, 0.75),
	)
	background.position.y = NAMEPLATE_BAR_OFFSET
	plate.add_child(background)

	var fill: MeshInstance3D = _build_bar_quad("HealthBar", Color(0.83, 0.24, 0.2))
	fill.position.y = NAMEPLATE_BAR_OFFSET
	plate.add_child(fill)

	return {
		"label": label,
		"marker": marker,
		"background": background,
		"fill": fill,
	}


## Builds the quad of a bar of a nameplate.
func _build_bar_quad(bar_name: String, color: Color) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(NAMEPLATE_WIDTH, NAMEPLATE_HEIGHT)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.render_priority = 5
	quad.material = material
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = bar_name
	mesh_instance.mesh = quad
	return mesh_instance


## Updates the bar of a nameplate.
##
## The bar shows only when the entity lost health or when it is the target.
func _update_nameplate_bar(
	nameplate: Dictionary,
	health: float,
	max_health: float,
	is_target: bool,
) -> void:
	var fill: MeshInstance3D = nameplate.get("fill")
	var background: MeshInstance3D = nameplate.get("background")
	if fill == null or background == null:
		return
	var ratio: float = 0.0
	if max_health > 0.0:
		ratio = clampf(health / max_health, 0.0, 1.0)
	var width: float = NAMEPLATE_WIDTH * ratio
	var quad: QuadMesh = fill.mesh as QuadMesh
	if quad != null:
		quad.size = Vector2(maxf(width, 0.001), NAMEPLATE_HEIGHT)
		quad.center_offset = Vector3(-(NAMEPLATE_WIDTH - width) * 0.5, 0.0, 0.0)
	var visible_bar: bool = is_target or ratio < 1.0
	fill.visible = visible_bar
	background.visible = visible_bar


## Flashes the entities that lost health in the last snapshot.
##
## The server reports the health of the mobs and of the players, so a drop of
## the value means that the entity was hit. The number of the damage floats up
## over the entity.
func flash_damaged_entities(
	mob_states: Dictionary,
	player_health_states: Dictionary,
) -> void:
	for mob_id: String in mob_states:
		_show_change(
			"mob_%s" % mob_id,
			float(mob_states[mob_id].get("health", 0.0)),
			mob_views.get(mob_id),
		)
	for player_id: Variant in player_health_states:
		_show_change(
			"player_%d" % int(player_id),
			float(player_health_states[player_id].get("health", 0.0)),
			player_views.get(player_id),
		)


## Shows the change of the health of an entity.
##
## A drop of the health is damage, a rise is healing.
func _show_change(key: String, health: float, view: Node3D) -> void:
	var previous: float = float(_previous_health.get(key, health))
	_previous_health[key] = health
	if previous <= 0.0 or view == null:
		return
	var difference: int = int(round(abs(health - previous)))
	if difference <= 0:
		return
	var kind: String = "damage" if health < previous else "heal"
	EntityVisualEffectsType.spawn_floating_combat_text(
		_root,
		view.global_position,
		difference,
		kind,
	)
	if kind != "damage":
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
