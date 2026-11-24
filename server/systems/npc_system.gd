class_name NpcSystem
extends RefCounted

## Server-authoritative NPC interaction rules.
##
## The system validates who may be talked to, which quests an NPC offers, and
## whether a quest can be accepted or handed in. Rewards are applied by the
## owning zone, so this module only decides and reports.

const ACTION_TALK: String = "talk"
const ACTION_ACCEPT: String = "accept"
const ACTION_TURN_IN: String = "turn_in"
const ACTIONS: PackedStringArray = [ACTION_TALK, ACTION_ACCEPT, ACTION_TURN_IN]


## Builds the zone-local NPC states from the registry definitions.
static func build_states(npc_definitions: Dictionary) -> Dictionary:
	var states: Dictionary = {}
	for npc_id: String in npc_definitions:
		var definition: Dictionary = npc_definitions[npc_id]
		var spawn_position: Array = definition["spawn_position"]
		states[npc_id] = {
			"position": Vector3(
				float(spawn_position[0]),
				float(spawn_position[1]),
				float(spawn_position[2]),
			),
			"dialogue_key": str(definition["dialogue_key"]),
			"quest_ids": (definition["quest_ids"] as Array).duplicate(),
			"interaction_range": float(definition["interaction_range"]),
		}
	return states


## Returns the state of a single NPC, or an empty dictionary.
static func get_npc_state(npc_states: Dictionary, npc_id: String) -> Dictionary:
	if not npc_states.has(npc_id):
		return {}
	return npc_states[npc_id]


## Checks whether the player is close enough to interact with the NPC.
static func is_in_range(player_position: Vector3, npc_state: Dictionary) -> bool:
	var interaction_range: float = float(npc_state["interaction_range"])
	return (
		player_position.distance_squared_to(npc_state["position"])
		<= interaction_range * interaction_range
	)


## Builds the quest list of an NPC for the talk response.
##
## Each entry contains the quest id, name key, status, progress, objective
## count, minimum level, and reward information. The status is `available` for
## quests the player can still accept, `active` for running quests, `completed`
## for quests that are ready to be handed in, and `turned_in` for finished ones.
static func build_quest_list(
	player_state: Dictionary,
	npc_state: Dictionary,
	quest_definitions: Dictionary,
) -> Array:
	var quest_list: Array = []
	for quest_id: String in npc_state["quest_ids"]:
		var quest_definition: Dictionary = quest_definitions.get(quest_id, {})
		if quest_definition.is_empty():
			continue
		var quest_state: Dictionary = QuestSystem.get_quest_state(player_state, quest_id)
		var status: String = str(quest_state.get("status", ""))
		if status.is_empty():
			status = "available"
		quest_list.append({
			"quest_id": quest_id,
			"name_key": str(quest_definition["name_key"]),
			"status": status,
			"progress": int(quest_state.get("progress", 0)),
			"objective_count": int(quest_definition["objective_count"]),
			"objective_type": str(quest_definition["objective_type"]),
			"objective_target": str(quest_definition["objective_target"]),
			"min_level": int(quest_definition["min_level"]),
			"reward_experience": int(quest_definition["reward_experience"]),
			"reward_item_ids": (quest_definition["reward_item_ids"] as Array).duplicate(),
		})
	return quest_list


## Handles an NPC interaction request.
##
## The function validates the action, the NPC, and the interaction distance,
## and it applies the quest state changes. The reward of a handed-in quest is
## not granted here: the result contains `grant_rewards`, and the owning zone
## applies the reward so the experience and the inventory stay consistent.
static func interact(
	player_state: Dictionary,
	npc_state: Dictionary,
	npc_definition: Dictionary,
	npc_id: String,
	action: String,
	quest_id: String,
	quest_definitions: Dictionary,
	item_definitions: Dictionary,
) -> Dictionary:
	var result: Dictionary = {
		"accepted": false,
		"reason": "",
		"action": action,
		"npc_id": npc_id,
		"npc_name_key": "",
		"dialogue_key": "",
		"quests": [],
		"quest_id": quest_id,
		"reward_experience": 0,
		"reward_item_ids": [],
		"grant_rewards": false,
	}
	if not ACTIONS.has(action):
		result["reason"] = "invalid_action"
		return result
	if npc_state.is_empty():
		result["reason"] = "unknown_npc"
		return result
	if not is_in_range(player_state["position"], npc_state):
		result["reason"] = "out_of_range"
		return result

	result["npc_name_key"] = str(npc_definition.get("name_key", ""))
	result["dialogue_key"] = str(npc_state["dialogue_key"])

	if action == ACTION_TALK:
		QuestSystem.record_talk(player_state, npc_id, quest_definitions)
		result["accepted"] = true
		result["quests"] = build_quest_list(player_state, npc_state, quest_definitions)
		return result

	if action == ACTION_ACCEPT:
		var accept_result: Dictionary = check_accept(
			player_state,
			npc_state,
			quest_id,
			quest_definitions,
		)
		if not bool(accept_result["ok"]):
			result["reason"] = str(accept_result["reason"])
			return result
		QuestSystem.accept_quest(
			player_state,
			quest_id,
			quest_definitions[quest_id],
		)
		result["accepted"] = true
		result["quests"] = build_quest_list(player_state, npc_state, quest_definitions)
		return result

	var turn_in_result: Dictionary = check_turn_in(
		player_state,
		npc_state,
		quest_id,
		quest_definitions,
		item_definitions,
	)
	if not bool(turn_in_result["ok"]):
		result["reason"] = str(turn_in_result["reason"])
		return result
	var quest_definition: Dictionary = quest_definitions[quest_id]
	result["accepted"] = true
	result["reward_experience"] = int(quest_definition["reward_experience"])
	result["reward_item_ids"] = (quest_definition["reward_item_ids"] as Array).duplicate()
	result["grant_rewards"] = true
	return result


## Validates a quest acceptance request.
static func check_accept(
	player_state: Dictionary,
	npc_state: Dictionary,
	quest_id: String,
	quest_definitions: Dictionary,
) -> Dictionary:
	return QuestSystem.can_accept(
		player_state,
		quest_id,
		quest_definitions.get(quest_id, {}),
		npc_state["quest_ids"],
	)


## Validates a quest hand-in request.
##
## The quest must be accepted, complete, and the reward items must fit into
## the inventory. Rewards are only granted when this check passes.
static func check_turn_in(
	player_state: Dictionary,
	npc_state: Dictionary,
	quest_id: String,
	quest_definitions: Dictionary,
	item_definitions: Dictionary,
) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": ""}
	var quest_definition: Dictionary = quest_definitions.get(quest_id, {})
	if quest_definition.is_empty():
		result["reason"] = "unknown_quest"
		return result
	if not npc_state["quest_ids"].has(quest_id):
		result["reason"] = "not_offered"
		return result
	var quest_state: Dictionary = QuestSystem.get_quest_state(player_state, quest_id)
	var status: String = str(quest_state.get("status", ""))
	if status == QuestSystem.STATUS_TURNED_IN:
		result["reason"] = "already_turned_in"
		return result
	if status == QuestSystem.STATUS_ACTIVE:
		result["reason"] = "not_complete"
		return result
	if status != QuestSystem.STATUS_COMPLETED:
		result["reason"] = "not_active"
		return result
	var inventory: InventoryComponent = player_state["inventory"]
	if not inventory.can_accept_items(quest_definition["reward_item_ids"], item_definitions):
		result["reason"] = "inventory_full"
		return result
	result["ok"] = true
	return result
