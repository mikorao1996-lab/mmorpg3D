extends RefCounted

## Unit checks of the character session service.
##
## The service owns the identity of a character: it issues a character and a
## secret, it only opens a character for the client that owns the secret, and
## it stores the progress of a session.

const CharacterSessionServiceType: GDScript = preload("res://server/systems/character_session_service.gd")
const InMemoryRepositoryType: GDScript = preload("res://tests/support/in_memory_character_repository.gd")


func run() -> bool:
	var repository: RefCounted = InMemoryRepositoryType.new()
	var service: RefCounted = CharacterSessionServiceType.new(
		repository,
		"starter",
		"warrior",
		Vector3.ZERO,
		100,
	)

	var created: Dictionary = service.call("authenticate", "", "", "Hero")
	if not _check(bool(created.get("ok", false)), "a first handshake must create a character"):
		return false
	var character_id: String = str(created.get("character_id", ""))
	var character_token: String = str(created.get("character_token", ""))
	if character_id.is_empty() or character_token.is_empty():
		push_error("a created character needs an identifier and a secret")
		return false
	if character_token.length() != 64:
		push_error("the secret of a character must be a SHA-256 hex digest")
		return false
	var created_state: Dictionary = created.get("state", {})
	if int(created_state.get("gold", 0)) != 100:
		push_error("a new character starts with the configured gold")
		return false
	if int(created_state.get("level", 0)) != 1:
		push_error("a new character starts at level 1")
		return false

	var stored: Dictionary = repository.characters[character_id]
	if str(stored.get("character_token_hash", "")) == character_token:
		push_error("the secret must not be stored as it is")
		return false
	if str(stored.get("character_token_hash", "")) != CharacterSessionServiceType.hash_token(character_token):
		push_error("the stored digest must match the secret of the client")
		return false

	var foreign: Dictionary = service.call(
		"authenticate",
		character_id,
		"a-secret-of-another-client",
		"",
	)
	if not _check(
			not bool(foreign.get("ok", true)) and str(foreign.get("reason", "")) == "identity_mismatch",
			"a foreign secret must not open a character",
	):
		return false

	var reopened: Dictionary = service.call("authenticate", character_id, character_token, "")
	if not _check(bool(reopened.get("ok", false)), "the owner of a character must open it"):
		return false
	if not str(reopened.get("character_token", "")).is_empty():
		push_error("the server must not send the secret of a known character again")
		return false
	if str(reopened.get("character_name", "")) != "Hero":
		push_error("a known character keeps its stored name")
		return false

	var unknown: Dictionary = service.call(
		"authenticate",
		"11111111-2222-4333-8444-555555555555",
		character_token,
		"",
	)
	if not _check(
			not bool(unknown.get("ok", true)) and str(unknown.get("reason", "")) == "unknown_character",
			"an unknown character must be reported",
	):
		return false

	var invalid: Dictionary = service.call("authenticate", "not-a-uuid", character_token, "")
	if not _check(
			not bool(invalid.get("ok", true)) and str(invalid.get("reason", "")) == "invalid_identity",
			"a malformed identifier must be rejected",
	):
		return false

	var saved: Dictionary = service.call("save_state", character_id, {
		"zone_id": "starter",
		"position": Vector3(1.5, 0.0, -2.5),
		"level": 3,
		"experience": 250,
		"gold": 175,
		"health": 80.0,
		"resource": 40.0,
		"inventory": [{"item_id": "minor_potion", "quantity": 2}],
		"equipment": {"weapon": "iron_sword"},
		"quests": {"slime_problem": {"status": "active", "progress": 2}},
	})
	if not _check(bool(saved.get("ok", false)), "the progress of a session must be stored"):
		return false

	var restored: Dictionary = service.call("authenticate", character_id, character_token, "")
	var restored_state: Dictionary = restored.get("state", {})
	if int(restored_state.get("level", 0)) != 3:
		push_error("the stored level must be restored")
		return false
	if int(restored_state.get("experience", 0)) != 250:
		push_error("the stored experience must be restored")
		return false
	if int(restored_state.get("gold", 0)) != 175:
		push_error("the stored gold must be restored")
		return false
	var restored_inventory: Array = restored_state.get("inventory", [])
	if not _check(restored_inventory.size() == 1, "the stored inventory must be restored"):
		return false
	if str(restored_inventory[0].get("item_id", "")) != "minor_potion":
		push_error("the stored inventory must keep its item")
		return false
	if int(restored_inventory[0].get("quantity", 0)) != 2:
		push_error("the stored inventory must keep its quantity")
		return false
	if str((restored_state.get("equipment", {}) as Dictionary).get("weapon", "")) != "iron_sword":
		push_error("the stored equipment must be restored")
		return false
	var restored_quests: Dictionary = restored_state.get("quests", {})
	if str((restored_quests.get("slime_problem", {}) as Dictionary).get("status", "")) != "active":
		push_error("the stored quests must be restored")
		return false

	var first_claim: Dictionary = service.call("claim_session", character_id, 7)
	if not _check(bool(first_claim.get("ok", false)), "the first session of a character must open"):
		return false
	var second_claim: Dictionary = service.call("claim_session", character_id, 8)
	if not _check(
			not bool(second_claim.get("ok", true)) and str(second_claim.get("reason", "")) == "character_in_use",
			"a character belongs to one session at a time",
	):
		return false
	service.call("release_session", character_id)
	var third_claim: Dictionary = service.call("claim_session", character_id, 8)
	if not _check(bool(third_claim.get("ok", false)), "a released character opens again"):
		return false

	var failed_write: Dictionary = service.call("save_state", "22222222-2222-4333-8444-555555555555", {})
	if not _check(
			not bool(failed_write.get("ok", true)),
			"a character without a session must not be stored",
	):
		return false

	return true


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition
