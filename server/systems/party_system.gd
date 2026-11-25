class_name PartySystem
extends RefCounted

## Server-authoritative party rules.
##
## A party belongs to the zone it was created in. Only the leader invites, a
## party never grows beyond the configured size, and a player belongs to at
## most one party. The system owns the membership; the caller resolves the
## zone of the players and delivers the results.

const ACTION_INVITE: String = "invite"
const ACTION_ACCEPT: String = "accept"
const ACTION_LEAVE: String = "leave"
const ACTIONS: PackedStringArray = [ACTION_INVITE, ACTION_ACCEPT, ACTION_LEAVE]

var _max_size: int = 5
var _parties: Dictionary = {}
var _peer_parties: Dictionary = {}
var _pending_invites: Dictionary = {}
var _next_party_id: int = 1


func _init(config: Dictionary = {}) -> void:
	_max_size = int(config.get("party_max_size", 5))


## Creates a party with the given leader.
##
## The party starts with the leader as its only member.
func create_party(leader_peer_id: int, leader_name: String, zone_id: String) -> Dictionary:
	if _peer_parties.has(leader_peer_id):
		return {"ok": false, "reason": "already_in_party", "party": {}}
	var party_id: int = _next_party_id
	_next_party_id += 1
	var party: Dictionary = {
		"id": party_id,
		"leader_peer_id": leader_peer_id,
		"zone_id": zone_id,
		"members": {leader_peer_id: leader_name},
	}
	_parties[party_id] = party
	_peer_parties[leader_peer_id] = party_id
	return {"ok": true, "reason": "", "party": party}


## Invites a player into a party.
##
## The inviter has to be the leader of the party and the party has to have room
## for one more member. The invite is remembered until the target accepts it.
func invite(
	party_id: int,
	from_peer_id: int,
	from_name: String,
	target_peer_id: int,
) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": "", "party": {}}
	if not _parties.has(party_id):
		result["reason"] = "unknown_party"
		return result
	var party: Dictionary = _parties[party_id]
	if int(party["leader_peer_id"]) != from_peer_id:
		result["reason"] = "not_leader"
		return result
	if from_peer_id == target_peer_id:
		result["reason"] = "invalid_target"
		return result
	if _peer_parties.has(target_peer_id):
		result["reason"] = "already_in_party"
		return result
	if (party["members"] as Dictionary).size() >= _max_size:
		result["reason"] = "party_full"
		return result
	_pending_invites[target_peer_id] = {
		"party_id": party_id,
		"from_peer_id": from_peer_id,
		"from_name": from_name,
	}
	result["ok"] = true
	result["party"] = party
	return result


## Accepts the pending invite of a player.
func accept(target_peer_id: int, target_name: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": "", "party": {}}
	if not _pending_invites.has(target_peer_id):
		result["reason"] = "no_invite"
		return result
	var invite: Dictionary = _pending_invites[target_peer_id]
	_pending_invites.erase(target_peer_id)
	var party_id: int = int(invite["party_id"])
	if not _parties.has(party_id):
		result["reason"] = "unknown_party"
		return result
	var party: Dictionary = _parties[party_id]
	if _peer_parties.has(target_peer_id):
		result["reason"] = "already_in_party"
		return result
	if (party["members"] as Dictionary).size() >= _max_size:
		result["reason"] = "party_full"
		return result
	(party["members"] as Dictionary)[target_peer_id] = target_name
	_peer_parties[target_peer_id] = party_id
	result["ok"] = true
	result["party"] = party
	return result


## Removes a player from the party.
##
## When the leader leaves, the longest standing member becomes the new leader.
## A party without members is disbanded.
func leave(peer_id: int) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"reason": "",
		"party": {},
		"disbanded": false,
	}
	if not _peer_parties.has(peer_id):
		result["reason"] = "not_in_party"
		return result
	var party_id: int = int(_peer_parties[peer_id])
	_peer_parties.erase(peer_id)
	_pending_invites.erase(peer_id)
	if not _parties.has(party_id):
		result["reason"] = "unknown_party"
		return result
	var party: Dictionary = _parties[party_id]
	(party["members"] as Dictionary).erase(peer_id)
	var members: Dictionary = party["members"]
	if members.is_empty():
		_parties.erase(party_id)
		result["ok"] = true
		result["disbanded"] = true
		result["party"] = party
		return result
	if int(party["leader_peer_id"]) == peer_id:
		var next_leader: int = members.keys()[0]
		party["leader_peer_id"] = next_leader
	result["ok"] = true
	result["party"] = party
	return result


## Removes a player that disconnected.
func forget_peer(peer_id: int) -> Dictionary:
	return leave(peer_id)


## Returns the party of a player, or an empty dictionary.
func get_party_of(peer_id: int) -> Dictionary:
	if not _peer_parties.has(peer_id):
		return {}
	var party_id: int = int(_peer_parties[peer_id])
	if not _parties.has(party_id):
		return {}
	return _parties[party_id]


## Reports whether a player belongs to a party.
func is_member(peer_id: int) -> bool:
	return _peer_parties.has(peer_id)


## Returns the pending invite of a player, or an empty dictionary.
func get_pending_invite(peer_id: int) -> Dictionary:
	return _pending_invites.get(peer_id, {})


## Builds the member list of a party for the protocol.
func build_members(party: Dictionary) -> Array:
	var members: Array = []
	if party.is_empty():
		return members
	var party_members: Dictionary = party["members"]
	for peer_id: Variant in party_members:
		members.append({
			"peer_id": int(peer_id),
			"name": str(party_members[peer_id]),
			"is_leader": int(peer_id) == int(party["leader_peer_id"]),
		})
	return members


## Returns the maximum number of members of a party.
func get_max_size() -> int:
	return _max_size
