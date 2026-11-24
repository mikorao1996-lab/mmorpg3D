class_name QuestSystem
extends RefCounted

## Server-authoritative quest state.
##
## Quest progress lives in the player state dictionary, so it follows the player
## between zones and is reset together with the session. Every progress event
## is validated against the accepted quest definition on the server; the client
## only reports what happened.

const STATUS_ACTIVE: String = "active"
const STATUS_COMPLETED: String = "completed"
const STATUS_TURNED_IN: String = "turned_in"


## Returns the quest state dictionary of the player, creating it on demand.
static func get_quest_states(player_state: Dictionary) -> Dictionary:
	if not player_state.has("quests") or not player_state["quests"] is Dictionary:
		player_state["quests"] = {}
	return player_state["quests"]


## Returns the stored state of a single quest, or an empty dictionary.
static func get_quest_state(player_state: Dictionary, quest_id: String) -> Dictionary:
	var quest_states: Dictionary = get_quest_states(player_state)
	if not quest_states.has(quest_id):
		return {}
	return quest_states[quest_id]


## Checks whether a quest can be accepted right now.
##
## Returns `ok` and `reason`. Reasons: `unknown_quest`, `not_offered`,
## `level_requirement`, `already_active`, `already_turned_in`.
static func can_accept(
	player_state: Dictionary,
	quest_id: String,
	quest_definition: Dictionary,
	offered_quest_ids: Array,
) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": ""}
	if quest_definition.is_empty():
		result["reason"] = "unknown_quest"
		return result
	if not offered_quest_ids.has(quest_id):
		result["reason"] = "not_offered"
		return result
	var quest_state: Dictionary = get_quest_state(player_state, quest_id)
	if str(quest_state.get("status", "")) == STATUS_TURNED_IN:
		result["reason"] = "already_turned_in"
		return result
	if not quest_state.is_empty() and str(quest_state.get("status", "")) != STATUS_TURNED_IN:
		result["reason"] = "already_active"
		return result
	if int(player_state["level"]) < int(quest_definition["min_level"]):
		result["reason"] = "level_requirement"
		return result
	result["ok"] = true
	return result


## Accepts a quest and starts tracking its progress.
static func accept_quest(
	player_state: Dictionary,
	quest_id: String,
	quest_definition: Dictionary,
) -> void:
	var quest_states: Dictionary = get_quest_states(player_state)
	quest_states[quest_id] = {
		"status": STATUS_ACTIVE,
		"progress": 0,
	}


## Reports whether the quest reached its objective count.
static func is_complete(
	player_state: Dictionary,
	quest_id: String,
	quest_definition: Dictionary,
) -> bool:
	var quest_state: Dictionary = get_quest_state(player_state, quest_id)
	if quest_state.is_empty():
		return false
	return int(quest_state.get("progress", 0)) >= int(
		quest_definition.get("objective_count", 1)
	)


## Marks an accepted quest as completed and ready to be handed in.
static func mark_turned_in(player_state: Dictionary, quest_id: String) -> void:
	var quest_states: Dictionary = get_quest_states(player_state)
	if not quest_states.has(quest_id):
		return
	quest_states[quest_id]["status"] = STATUS_TURNED_IN


## Records progress for quests with a matching kill objective.
static func record_kill(
	player_state: Dictionary,
	mob_id: String,
	quest_definitions: Dictionary,
) -> void:
	_record_progress(player_state, "kill", mob_id, quest_definitions)


## Records progress for quests with a matching collect objective.
static func record_collect(
	player_state: Dictionary,
	item_id: String,
	quest_definitions: Dictionary,
) -> void:
	_record_progress(player_state, "collect", item_id, quest_definitions)


## Records progress for quests with a matching talk objective.
static func record_talk(
	player_state: Dictionary,
	npc_id: String,
	quest_definitions: Dictionary,
) -> void:
	_record_progress(player_state, "talk", npc_id, quest_definitions)


## Builds the quest part of the world snapshot for one player.
##
## Each entry is `[quest_id, status, progress, objective_count, name_key,
## objective_type, objective_target]`.
static func build_snapshot(
	player_state: Dictionary,
	quest_definitions: Dictionary,
) -> Array:
	var snapshot: Array = []
	var quest_states: Dictionary = get_quest_states(player_state)
	for quest_id: String in quest_states:
		var quest_state: Dictionary = quest_states[quest_id]
		var quest_definition: Dictionary = quest_definitions.get(quest_id, {})
		snapshot.append([
			quest_id,
			str(quest_state.get("status", STATUS_ACTIVE)),
			int(quest_state.get("progress", 0)),
			int(quest_definition.get("objective_count", 1)),
			str(quest_definition.get("name_key", quest_id)),
			str(quest_definition.get("objective_type", "")),
			str(quest_definition.get("objective_target", "")),
		])
	return snapshot


static func _record_progress(
	player_state: Dictionary,
	objective_type: String,
	target_id: String,
	quest_definitions: Dictionary,
) -> void:
	var quest_states: Dictionary = get_quest_states(player_state)
	for quest_id: String in quest_states.keys():
		var quest_state: Dictionary = quest_states[quest_id]
		if str(quest_state.get("status", "")) != STATUS_ACTIVE:
			continue
		var quest_definition: Dictionary = quest_definitions.get(quest_id, {})
		if quest_definition.is_empty():
			continue
		if str(quest_definition.get("objective_type", "")) != objective_type:
			continue
		if str(quest_definition.get("objective_target", "")) != target_id:
			continue
		var objective_count: int = int(quest_definition.get("objective_count", 1))
		var progress: int = int(quest_state.get("progress", 0))
		if progress >= objective_count:
			continue
		progress += 1
		quest_state["progress"] = progress
		if progress >= objective_count:
			quest_state["status"] = STATUS_COMPLETED
