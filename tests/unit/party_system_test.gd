extends RefCounted

## Checks the server-authoritative party rules.
##
## The tests cover the creation of a party, the invitation, the acceptance, the
## limits of a party, and the change of the leader.

const PartySystemType: GDScript = preload("res://server/systems/party_system.gd")

const CONFIG: Dictionary = {"party_max_size": 3}


func run() -> bool:
	var party_system: RefCounted = PartySystemType.new(CONFIG)

	var create_result: Dictionary = party_system.create_party(1, "Traveler", "starter")
	if not bool(create_result["ok"]):
		push_error("The party system rejected the creation of a party")
		return false
	var party: Dictionary = create_result["party"]
	if not party_system.is_member(1):
		push_error("The leader is not a member of the new party")
		return false
	if int(party["leader_peer_id"]) != 1:
		push_error("The leader of the new party is wrong")
		return false

	var second_party_result: Dictionary = party_system.create_party(1, "Traveler", "starter")
	if bool(second_party_result["ok"]):
		push_error("The party system accepted a second party for a player")
		return false
	if str(second_party_result["reason"]) != "already_in_party":
		push_error("A second party did not report the existing party")
		return false

	var invite_result: Dictionary = party_system.invite(
		int(party["id"]),
		1,
		"Traveler",
		2,
	)
	if not bool(invite_result["ok"]):
		push_error("The party system rejected a valid invitation")
		return false
	if party_system.get_pending_invite(2).is_empty():
		push_error("The party system did not remember the invitation")
		return false

	var not_leader_result: Dictionary = party_system.invite(
		int(party["id"]),
		2,
		"Other",
		3,
	)
	if bool(not_leader_result["ok"]):
		push_error("The party system accepted an invitation from a member")
		return false
	if str(not_leader_result["reason"]) != "not_leader":
		push_error("An invitation from a member did not report the missing leadership")
		return false

	var accept_result: Dictionary = party_system.accept(2, "Other")
	if not bool(accept_result["ok"]):
		push_error("The party system rejected a valid acceptance")
		return false
	if not party_system.is_member(2):
		push_error("The accepted player is not a member of the party")
		return false

	var members: Array = party_system.build_members(accept_result["party"])
	if members.size() != 2:
		push_error("The party does not list every member")
		return false
	var leader_found: bool = false
	for member: Dictionary in members:
		if bool(member["is_leader"]):
			leader_found = true
	if not leader_found:
		push_error("The member list does not mark the leader")
		return false

	var already_member_result: Dictionary = party_system.invite(
		int(party["id"]),
		1,
		"Traveler",
		2,
	)
	if bool(already_member_result["ok"]):
		push_error("The party system accepted an invitation for a party member")
		return false
	if str(already_member_result["reason"]) != "already_in_party":
		push_error("An invitation for a party member did not report the party")
		return false

	var third_invite: Dictionary = party_system.invite(
		int(party["id"]),
		1,
		"Traveler",
		3,
	)
	if not bool(third_invite["ok"]):
		push_error("The party system rejected an invitation into a party with room")
		return false
	party_system.accept(3, "Third")
	var full_invite: Dictionary = party_system.invite(
		int(party["id"]),
		1,
		"Traveler",
		4,
	)
	if bool(full_invite["ok"]):
		push_error("The party system accepted an invitation into a full party")
		return false
	if str(full_invite["reason"]) != "party_full":
		push_error("An invitation into a full party did not report the full party")
		return false

	var no_invite_result: Dictionary = party_system.accept(4, "Fourth")
	if bool(no_invite_result["ok"]):
		push_error("The party system accepted a player without an invitation")
		return false
	if str(no_invite_result["reason"]) != "no_invite":
		push_error("An acceptance without an invitation did not report the missing invite")
		return false

	var leave_result: Dictionary = party_system.leave(2)
	if not bool(leave_result["ok"]):
		push_error("The party system rejected a valid departure")
		return false
	if party_system.is_member(2):
		push_error("The player is still a member after the departure")
		return false

	var leader_leave_result: Dictionary = party_system.leave(1)
	if not bool(leader_leave_result["ok"]):
		push_error("The party system rejected the departure of the leader")
		return false
	var party_after_leave: Dictionary = leader_leave_result["party"]
	if int(party_after_leave["leader_peer_id"]) != 3:
		push_error("The leadership did not pass to the remaining member")
		return false

	var last_leave_result: Dictionary = party_system.leave(3)
	if not bool(last_leave_result["ok"]):
		push_error("The party system rejected the departure of the last member")
		return false
	if not bool(last_leave_result["disbanded"]):
		push_error("The party was not disbanded after the last member left")
		return false
	if not party_system.get_party_of(3).is_empty():
		push_error("The disbanded party is still known to the party system")
		return false
	return true
