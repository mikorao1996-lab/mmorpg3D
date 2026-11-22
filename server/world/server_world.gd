class_name ServerWorld
extends RefCounted

const ServerZoneType: GDScript = preload("res://server/world/server_zone.gd")

var _zones: Dictionary = {}
var _peer_zones: Dictionary = {}
var _default_zone_id: String


func _init(config: Dictionary) -> void:
	var zone_ids: Array = config["zone_ids"]
	_default_zone_id = zone_ids[0]
	for zone_id: String in zone_ids:
		_zones[zone_id] = ServerZoneType.new(zone_id, config)


func add_player(peer_id: int) -> void:
	if _peer_zones.has(peer_id):
		return
	var default_zone: RefCounted = _zones[_default_zone_id]
	default_zone.add_player(peer_id)
	_peer_zones[peer_id] = _default_zone_id


func remove_player(peer_id: int) -> void:
	if not _peer_zones.has(peer_id):
		return
	var zone_id: String = _peer_zones[peer_id]
	var zone: RefCounted = _zones[zone_id]
	zone.remove_player(peer_id)
	_peer_zones.erase(peer_id)


func set_input_direction(peer_id: int, input_direction: Vector2) -> bool:
	if not _peer_zones.has(peer_id):
		return false
	var zone_id: String = _peer_zones[peer_id]
	var zone: RefCounted = _zones[zone_id]
	return zone.set_input_direction(peer_id, input_direction)


func move_player_to_zone(peer_id: int, target_zone_id: String) -> bool:
	if not _peer_zones.has(peer_id) or not _zones.has(target_zone_id):
		return false
	var current_zone_id: String = _peer_zones[peer_id]
	if current_zone_id == target_zone_id:
		return true

	var current_zone: RefCounted = _zones[current_zone_id]
	var target_zone: RefCounted = _zones[target_zone_id]
	var player_position: Vector3 = current_zone.get_player_position(peer_id)
	current_zone.remove_player(peer_id)
	target_zone.add_player_at(peer_id, player_position)
	_peer_zones[peer_id] = target_zone_id
	return true


func advance(delta: float) -> bool:
	var snapshot_due: bool = false
	for zone: RefCounted in _zones.values():
		snapshot_due = zone.advance(delta) or snapshot_due
	return snapshot_due


func create_snapshots() -> Dictionary:
	var snapshots: Dictionary = {}
	for zone: RefCounted in _zones.values():
		snapshots.merge(zone.create_snapshots())
	return snapshots
