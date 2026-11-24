class_name ZoneSnapshotBuilder
extends RefCounted

## Builds the world snapshot of a zone for one observer.
##
## The builder only formats the zone state; it never changes it. The zone
## passes its own state, so the snapshot format stays in one place while the
## zone keeps the ownership of the simulation.

const QuestSystemType: GDScript = preload("res://server/systems/quest_system.gd")


## Builds the snapshot for the observer.
##
## `zone_data` carries the shared zone state: `players`, `mobs`,
## `mob_definitions`, `npcs`, `drops`, `interest_radius`, `quest_definitions`,
## and `zone_id`.
static func build(
	observer_id: int,
	observer_state: Dictionary,
	zone_data: Dictionary,
) -> Dictionary:
	var players: Dictionary = zone_data["players"]
	var mobs: Dictionary = zone_data["mobs"]
	var mob_definitions: Dictionary = zone_data["mob_definitions"]
	var npcs: Dictionary = zone_data["npcs"]
	var drops: Dictionary = zone_data["drops"]
	var interest_radius: float = float(zone_data["interest_radius"])
	var interest_radius_squared: float = interest_radius * interest_radius
	var observer_position: Vector3 = observer_state["position"]

	var player_ids: Array = players.keys()
	player_ids.sort()
	var player_states: Array = []
	for peer_id: int in player_ids:
		var player_state: Dictionary = players[peer_id]
		var player_position: Vector3 = player_state["position"]
		if (
			peer_id == observer_id
			or observer_position.distance_squared_to(player_position)
			<= interest_radius_squared
		):
			player_states.append([
				peer_id,
				player_position,
				player_state["health"],
				player_state["max_health"],
				player_state["level"],
				player_state["experience"],
				player_state["resource"],
				player_state["max_resource"],
				player_state["attack_multiplier"],
				player_state["defense"],
			])

	var mob_ids: Array = mobs.keys()
	mob_ids.sort()
	var mob_states: Array = []
	for mob_id: String in mob_ids:
		var mob_state: Dictionary = mobs[mob_id]
		var mob_definition: Dictionary = mob_definitions[mob_id]
		mob_states.append([
			mob_id,
			mob_state["position"],
			mob_state["health"],
			float(mob_definition["health"]),
		])

	var npc_ids: Array = npcs.keys()
	npc_ids.sort()
	var npc_states: Array = []
	for npc_id: String in npc_ids:
		npc_states.append([
			npc_id,
			npcs[npc_id]["position"],
		])

	var drop_ids: Array = drops.keys()
	drop_ids.sort()
	var drop_states: Array = []
	for drop_id: int in drop_ids:
		var drop: Dictionary = drops[drop_id]
		if (
			observer_position.distance_squared_to(drop["position"])
			> interest_radius_squared
		):
			continue
		drop_states.append([
			drop_id,
			drop["item_id"],
			drop["position"],
		])

	var inventory: RefCounted = observer_state["inventory"]
	var equipment: RefCounted = observer_state["equipment"]
	return {
		"zone_id": str(zone_data["zone_id"]),
		"server_time_ms": Time.get_ticks_msec(),
		"players": player_states,
		"mobs": mob_states,
		"npcs": npc_states,
		"drops": drop_states,
		"inventory": inventory.call("get_snapshot"),
		"equipment": equipment.call("get_snapshot"),
		"quests": QuestSystemType.build_snapshot(
			observer_state,
			zone_data["quest_definitions"],
		),
	}
