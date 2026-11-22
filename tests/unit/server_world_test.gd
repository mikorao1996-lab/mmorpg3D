extends RefCounted

const ServerWorldType: GDScript = preload("res://server/world/server_world.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	if config.is_empty():
		return false
	config["world_half_extent"] = 14.0

	var server_world: RefCounted = ServerWorldType.new(config)
	for peer_id: int in range(1, 6):
		server_world.add_player(peer_id)

	var snapshots: Dictionary = server_world.create_snapshots()
	var first_snapshot: Dictionary = snapshots[1]
	var first_players: Variant = first_snapshot.get("players", null)
	if not first_players is Array:
		push_error("Server world snapshot is missing its player list")
		return false
	if first_players.size() != 4:
		push_error("Interest snapshot did not include exactly the nearby players")
		return false
	if not _snapshot_has_player(first_players, 1):
		push_error("Interest snapshot omitted the observing player")
		return false
	if _snapshot_has_player(first_players, 5):
		push_error("Interest snapshot included a player outside the configured radius")
		return false

	if not server_world.move_player_to_zone(2, "dungeon"):
		push_error("Server world rejected a transfer to a configured zone")
		return false
	var routed_snapshots: Dictionary = server_world.create_snapshots()
	if _snapshot_has_player(routed_snapshots[1]["players"], 2):
		push_error("Player remained visible in the previous zone after transfer")
		return false
	if (
		routed_snapshots[2]["zone_id"] != "dungeon"
		or routed_snapshots[2]["players"].size() != 1
		or not _snapshot_has_player(routed_snapshots[2]["players"], 2)
	):
		push_error("Transferred player did not receive an isolated zone snapshot")
		return false
	if server_world.move_player_to_zone(2, "unknown"):
		push_error("Server world accepted transfer to an unconfigured zone")
		return false
	if server_world.move_player_to_zone(999, "dungeon"):
		push_error("Server world accepted transfer for an unknown player")
		return false
	if not server_world.move_player_to_zone(2, "starter"):
		push_error("Server world rejected a transfer back to the starter zone")
		return false
	var restored_snapshots: Dictionary = server_world.create_snapshots()
	if not _snapshot_has_player(restored_snapshots[1]["players"], 2):
		push_error("Transferred player did not reappear in the destination zone")
		return false

	server_world.remove_player(2)
	var updated_snapshots: Dictionary = server_world.create_snapshots()
	if updated_snapshots.has(2):
		push_error("Disconnected player still has a world snapshot")
		return false
	if _snapshot_has_player(updated_snapshots[1]["players"], 2):
		push_error("Disconnected player remained in another player's snapshot")
		return false
	return true


func _snapshot_has_player(player_states: Array, peer_id: int) -> bool:
	for player_state: Variant in player_states:
		if player_state is Array and player_state.size() == 2 and player_state[0] == peer_id:
			return true
	return false
