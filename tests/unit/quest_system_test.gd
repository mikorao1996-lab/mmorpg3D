extends RefCounted

const ServerZoneType: GDScript = preload("res://server/world/server_zone.gd")
const ServerWorldType: GDScript = preload("res://server/world/server_world.gd")
const SimulationConfigType: GDScript = preload("res://shared/data/simulation_config.gd")
const GameDataRegistryType: GDScript = preload("res://shared/data/game_data_registry.gd")
const QuestSystemType: GDScript = preload("res://server/systems/quest_system.gd")

const MIRA_POSITION: Vector3 = Vector3(-2.0, 0.0, 2.5)


func run() -> bool:
	var config: Dictionary = SimulationConfigType.load_config()
	var registries: Dictionary = GameDataRegistryType.load_all()
	if config.is_empty() or registries.is_empty():
		return false

	var zone: RefCounted = ServerZoneType.new("starter", config, registries)
	zone.add_player_at(1, MIRA_POSITION)

	var unknown_npc_result: Dictionary = zone.interact_npc(1, "missing_npc", "talk", "")
	if bool(unknown_npc_result["accepted"]) or unknown_npc_result["reason"] != "unknown_npc":
		push_error("Server accepted an interaction with an unknown NPC")
		return false
	var invalid_action_result: Dictionary = zone.interact_npc(1, "quest_giver_mira", "hug", "")
	if (
		bool(invalid_action_result["accepted"])
		or invalid_action_result["reason"] != "invalid_action"
	):
		push_error("Server accepted an unknown NPC interaction action")
		return false
	var out_of_range_result: Dictionary = zone.interact_npc(1, "quest_giver_bron", "talk", "")
	if (
		bool(out_of_range_result["accepted"])
		or out_of_range_result["reason"] != "out_of_range"
	):
		push_error("Server allowed an interaction from outside the interaction range")
		return false

	var talk_result: Dictionary = zone.interact_npc(1, "quest_giver_mira", "talk", "")
	if not bool(talk_result["accepted"]):
		push_error("Server rejected a valid NPC conversation")
		return false
	if str(talk_result["npc_name_key"]) != "npc_quest_giver_mira":
		push_error("NPC conversation did not report the NPC name key")
		return false
	var offered_quests: Array = talk_result["quests"]
	if offered_quests.size() != 4:
		push_error("NPC conversation did not report the offered quests")
		return false
	for entry: Variant in offered_quests:
		if not entry is Dictionary:
			push_error("NPC conversation reported a malformed quest entry")
			return false
		if str(entry["status"]) != "available":
			push_error("NPC conversation reported a wrong initial quest status")
			return false

	var accept_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"accept",
		"slime_problem",
	)
	if not bool(accept_result["accepted"]):
		push_error("Server rejected a valid quest acceptance")
		return false
	var duplicate_accept_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"accept",
		"slime_problem",
	)
	if (
		bool(duplicate_accept_result["accepted"])
		or duplicate_accept_result["reason"] != "already_active"
	):
		push_error("Server accepted the same quest twice")
		return false
	var not_offered_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"accept",
		"pelt_hunt",
	)
	if (
		bool(not_offered_result["accepted"])
		or not_offered_result["reason"] != "not_offered"
	):
		push_error("Server accepted a quest that the NPC does not offer")
		return false
	var level_requirement_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"accept",
		"wolf_problem",
	)
	if (
		bool(level_requirement_result["accepted"])
		or level_requirement_result["reason"] != "level_requirement"
	):
		push_error("Server accepted a quest below the level requirement")
		return false

	var early_turn_in_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"turn_in",
		"slime_problem",
	)
	if (
		bool(early_turn_in_result["accepted"])
		or early_turn_in_result["reason"] != "not_complete"
	):
		push_error("Server accepted a quest that was not finished yet")
		return false

	for kill_index: int in range(3):
		zone.record_quest_kill(1, "training_slime")
	var player_state: Dictionary = zone.get_player_state(1)
	var quest_state: Dictionary = QuestSystemType.get_quest_state(player_state, "slime_problem")
	if int(quest_state.get("progress", 0)) != 3:
		push_error("Quest kill progress was not recorded")
		return false
	if str(quest_state.get("status", "")) != QuestSystemType.STATUS_COMPLETED:
		push_error("Quest did not reach the completed status")
		return false

	var experience_before: int = int(player_state["experience"])
	var inventory_before: int = (player_state["inventory"] as InventoryComponent).get_snapshot().size()
	var turn_in_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"turn_in",
		"slime_problem",
	)
	if not bool(turn_in_result["accepted"]):
		push_error("Server rejected a valid quest hand-in")
		return false
	player_state = zone.get_player_state(1)
	if int(player_state["experience"]) != experience_before + 25:
		push_error("Quest hand-in did not award the configured experience")
		return false
	var inventory_after: int = (player_state["inventory"] as InventoryComponent).get_snapshot().size()
	if inventory_after != inventory_before + 3:
		push_error("Quest hand-in did not award the configured items")
		return false
	var turned_in_state: Dictionary = QuestSystemType.get_quest_state(
		player_state,
		"slime_problem",
	)
	if str(turned_in_state.get("status", "")) != QuestSystemType.STATUS_TURNED_IN:
		push_error("Quest hand-in did not mark the quest as turned in")
		return false
	var repeat_turn_in_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"turn_in",
		"slime_problem",
	)
	if (
		bool(repeat_turn_in_result["accepted"])
		or repeat_turn_in_result["reason"] != "already_turned_in"
	):
		push_error("Server allowed the same quest to be handed in twice")
		return false

	var talk_quest_accept: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"accept",
		"training_grounds",
	)
	if not bool(talk_quest_accept["accepted"]):
		push_error("Server rejected the talk quest acceptance")
		return false
	zone.interact_npc(1, "quest_giver_mira", "talk", "")
	player_state = zone.get_player_state(1)
	var talk_state: Dictionary = QuestSystemType.get_quest_state(
		player_state,
		"training_grounds",
	)
	if int(talk_state.get("progress", 0)) != 1:
		push_error("Quest talk progress was not recorded")
		return false

	return _check_inventory_full_reward(config, registries)


## A quest hand-in must not be accepted when the reward does not fit.
func _check_inventory_full_reward(
	config: Dictionary,
	registries: Dictionary,
) -> bool:
	var small_inventory_config: Dictionary = config.duplicate(true)
	small_inventory_config["inventory_slot_count"] = 1
	var zone: RefCounted = ServerZoneType.new("starter", small_inventory_config, registries)
	zone.add_player_at(1, MIRA_POSITION)
	zone.interact_npc(1, "quest_giver_mira", "accept", "slime_problem")
	for kill_index: int in range(3):
		zone.record_quest_kill(1, "training_slime")
	var experience_before: int = int(zone.get_player_state(1)["experience"])
	var turn_in_result: Dictionary = zone.interact_npc(
		1,
		"quest_giver_mira",
		"turn_in",
		"slime_problem",
	)
	if (
		bool(turn_in_result["accepted"])
		or turn_in_result["reason"] != "inventory_full"
	):
		push_error("Server handed in a quest although the reward did not fit")
		return false
	var player_state: Dictionary = zone.get_player_state(1)
	if int(player_state["experience"]) != experience_before:
		push_error("A rejected quest hand-in still awarded experience")
		return false
	var quest_state: Dictionary = QuestSystemType.get_quest_state(player_state, "slime_problem")
	if str(quest_state.get("status", "")) != QuestSystemType.STATUS_COMPLETED:
		push_error("A rejected quest hand-in consumed the quest")
		return false
	return true
