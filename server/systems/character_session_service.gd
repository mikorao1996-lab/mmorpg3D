class_name CharacterSessionService
extends RefCounted

## Server-authoritative character sessions.
##
## The service owns the identity of a character: it resolves the handshake of
## a client into a stored character, hands the stored progress to the world,
## and writes the progress back when the session ends.
##
## The client never sends progress. It only sends the identifier of its
## character and the secret that belongs to it, and the server decides whether
## that pair may open the character. The secret is stored as a SHA-256 digest,
## so the database never holds the value the client knows.
##
## The transport is still plain ENet, so the secret travels in clear text. A
## full credential login with a protected transport stays a separate step; this
## service only guarantees that a client cannot take over a character it does
## not own.

const CharacterRepositoryType: GDScript = preload("res://server/db/character_repository.gd")

const TOKEN_BYTE_COUNT: int = 32
const CHARACTER_NAME_MAX_LENGTH: int = 32
const DEFAULT_CLASS_ID: String = "warrior"
const DEFAULT_ZONE_ID: String = "starter"

var _repository: RefCounted
var _default_class_id: String
var _default_zone_id: String
var _default_position: Vector3
var _default_gold: int
var _metadata: Dictionary = {}
var _active_sessions: Dictionary = {}


func _init(
	repository: RefCounted,
	default_zone_id: String = DEFAULT_ZONE_ID,
	default_class_id: String = DEFAULT_CLASS_ID,
	default_position: Vector3 = Vector3.ZERO,
	default_gold: int = 0,
) -> void:
	_repository = repository
	_default_zone_id = default_zone_id
	_default_class_id = default_class_id
	_default_position = default_position
	_default_gold = default_gold


## Builds a service on top of a PostgreSQL connection.
static func from_connection(
	connection: RefCounted,
	default_zone_id: String = DEFAULT_ZONE_ID,
	default_class_id: String = DEFAULT_CLASS_ID,
	default_position: Vector3 = Vector3.ZERO,
	default_gold: int = 0,
) -> CharacterSessionService:
	return CharacterSessionService.new(
		CharacterRepositoryType.new(connection),
		default_zone_id,
		default_class_id,
		default_position,
		default_gold,
	)


## Resolves the identity of a handshake.
##
## `character_id` is empty for a first connection: the service then creates a
## character and issues a secret for it. A known identifier is only accepted
## together with the secret that belongs to it.
##
## The result carries `ok`, `reason`, `character_id`, `character_name`,
## `state`, and `character_token`. The token is only present when the service
## issued it, so it is never sent back to a client that already owns it.
func authenticate(
	character_id: String,
	character_token: String,
	character_name: String,
) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"reason": "",
		"character_id": "",
		"character_name": "",
		"character_token": "",
		"state": {},
	}
	var trimmed_id: String = character_id.strip_edges()
	var trimmed_token: String = character_token.strip_edges()
	if trimmed_id.is_empty():
		return _create_character(character_name, result)
	if not CharacterRepositoryType.is_valid_character_id(trimmed_id):
		result["reason"] = "invalid_identity"
		return result

	var load_result: Dictionary = _repository.call("load_character", trimmed_id)
	if not bool(load_result.get("ok", false)):
		result["reason"] = "database_error"
		return result
	if not bool(load_result.get("found", false)):
		result["reason"] = "unknown_character"
		return result

	var character: Dictionary = load_result["character"]
	var stored_hash: String = str(character.get("character_token_hash", ""))
	if stored_hash.is_empty():
		# A character that predates the identity column has no owner yet, so the
		# first client that presents it claims it.
		var claim_result: Dictionary = _claim_character(character, trimmed_token)
		if not bool(claim_result.get("ok", false)):
			result["reason"] = str(claim_result.get("reason", "identity_mismatch"))
			return result
	elif not _token_matches(trimmed_token, stored_hash):
		result["reason"] = "identity_mismatch"
		return result

	result["ok"] = true
	result["character_id"] = trimmed_id
	result["character_name"] = str(character["character_name"])
	result["state"] = _build_restored_state(character)
	_remember_metadata(character)
	return result


## Stores the progress of a character.
##
## The state is the exported player state of the world; the service adds the
## metadata it remembered during the handshake.
func save_state(character_id: String, state: Dictionary) -> Dictionary:
	var metadata: Dictionary = _metadata.get(character_id, {})
	if metadata.is_empty():
		return {"ok": false, "error": "The character is not an open session."}
	var character: Dictionary = metadata.duplicate(true)
	character["level"] = int(state.get("level", 1))
	character["experience"] = int(state.get("experience", 0))
	character["gold"] = int(state.get("gold", 0))
	character["zone_id"] = str(state.get("zone_id", _default_zone_id))
	character["position"] = state.get("position", _default_position)
	character["health"] = float(state.get("health", 0.0))
	character["resource"] = float(state.get("resource", 0.0))
	character["inventory"] = _normalize_inventory(state.get("inventory", []))
	character["equipment"] = _normalize_equipment(state.get("equipment", {}))
	character["quests"] = _normalize_quests(state.get("quests", {}))
	var save_result: Dictionary = _repository.call("save_character", character)
	if not bool(save_result.get("ok", false)):
		return {
			"ok": false,
			"error": str(save_result.get("error", "Unknown database error.")),
		}
	return {"ok": true, "error": ""}


## Marks a character as taken by a session.
##
## A character belongs to one session at a time, so a second client with the
## same identity is rejected instead of overwriting the progress of the first.
func claim_session(character_id: String, peer_id: int) -> Dictionary:
	if _active_sessions.has(character_id):
		return {"ok": false, "reason": "character_in_use"}
	_active_sessions[character_id] = peer_id
	return {"ok": true, "reason": ""}


## Releases the session of a character.
func release_session(character_id: String) -> void:
	_active_sessions.erase(character_id)


## Reports whether a peer holds the session of a character.
func is_session_owner(character_id: String, peer_id: int) -> bool:
	return int(_active_sessions.get(character_id, 0)) == peer_id


## Generates a random identifier for a new character.
func generate_character_id() -> String:
	return _generate_uuid()


## Hashes a secret the way the repository stores it.
static func hash_token(token: String) -> String:
	var hashing_context: HashingContext = HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA256)
	hashing_context.update(token.to_utf8_buffer())
	return hashing_context.finish().hex_encode()


## Generates a secret for a new character.
static func generate_token() -> String:
	return Crypto.new().generate_random_bytes(TOKEN_BYTE_COUNT).hex_encode()


func _create_character(character_name: String, result: Dictionary) -> Dictionary:
	var new_character_id: String = _generate_uuid()
	var new_token: String = generate_token()
	var character: Dictionary = {
		"character_id": new_character_id,
		"character_name": _normalize_character_name(character_name),
		"character_token_hash": hash_token(new_token),
		"class_id": _default_class_id,
		"level": 1,
		"experience": 0,
		"gold": _default_gold,
		"zone_id": _default_zone_id,
		"position": _default_position,
		"health": 0.0,
		"resource": 0.0,
		"inventory": [],
		"equipment": {},
		"quests": {},
	}
	var create_result: Dictionary = _repository.call("create_character", character)
	if not bool(create_result.get("ok", false)):
		result["reason"] = "database_error"
		return result
	result["ok"] = true
	result["character_id"] = new_character_id
	result["character_name"] = str(character["character_name"])
	result["character_token"] = new_token
	result["state"] = _build_restored_state(character)
	_remember_metadata(character)
	return result


## Claims a character that has no owner yet and stores the digest of the secret.
func _claim_character(character: Dictionary, token: String) -> Dictionary:
	if token.strip_edges().is_empty():
		return {"ok": false, "reason": "identity_mismatch"}
	var claimed: Dictionary = character.duplicate(true)
	claimed["character_token_hash"] = hash_token(token)
	var save_result: Dictionary = _repository.call("save_character", claimed)
	if not bool(save_result.get("ok", false)):
		return {"ok": false, "reason": "database_error"}
	character["character_token_hash"] = claimed["character_token_hash"]
	return {"ok": true, "reason": ""}


func _token_matches(token: String, stored_hash: String) -> bool:
	if token.strip_edges().is_empty():
		return false
	return hash_token(token) == stored_hash


func _remember_metadata(character: Dictionary) -> void:
	var character_id: String = str(character["character_id"])
	_metadata[character_id] = {
		"character_id": character_id,
		"character_name": str(character["character_name"]),
		"character_token_hash": str(character["character_token_hash"]),
		"class_id": str(character["class_id"]),
	}


## Builds the player state the world restores for a character.
func _build_restored_state(character: Dictionary) -> Dictionary:
	return {
		"zone_id": str(character["zone_id"]),
		"position": character["position"],
		"level": int(character["level"]),
		"experience": int(character["experience"]),
		"gold": int(character["gold"]),
		"health": float(character["health"]),
		"resource": float(character["resource"]),
		"inventory": _normalize_inventory(character.get("inventory", [])),
		"equipment": _normalize_equipment(character.get("equipment", {})),
		"quests": _normalize_quests(character.get("quests", {})),
	}


func _normalize_character_name(character_name: String) -> String:
	var trimmed: String = character_name.strip_edges()
	if trimmed.is_empty():
		return "Traveler"
	return trimmed.substr(0, CHARACTER_NAME_MAX_LENGTH)


## Keeps only the inventory records that the repository accepts.
func _normalize_inventory(inventory: Variant) -> Array:
	var normalized: Array = []
	if typeof(inventory) != TYPE_ARRAY:
		return normalized
	for entry: Variant in inventory:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = entry
		var item_id: String = str(slot.get("item_id", ""))
		var quantity: int = int(slot.get("quantity", 0))
		if item_id.strip_edges().is_empty() or quantity < 1:
			continue
		normalized.append({"item_id": item_id, "quantity": quantity})
	return normalized


## Keeps only the equipment records that the repository accepts.
func _normalize_equipment(equipment: Variant) -> Dictionary:
	var normalized: Dictionary = {}
	if typeof(equipment) != TYPE_DICTIONARY:
		return normalized
	for slot_id: Variant in equipment:
		var item_id: String = str(equipment[slot_id])
		if str(slot_id).strip_edges().is_empty() or item_id.strip_edges().is_empty():
			continue
		normalized[str(slot_id)] = item_id
	return normalized


## Keeps only the quest records that the repository accepts.
func _normalize_quests(quests: Variant) -> Dictionary:
	var normalized: Dictionary = {}
	if typeof(quests) != TYPE_DICTIONARY:
		return normalized
	for quest_id: Variant in quests:
		if typeof(quests[quest_id]) != TYPE_DICTIONARY:
			continue
		var quest_state: Dictionary = quests[quest_id]
		var status: String = str(quest_state.get("status", ""))
		var progress: int = int(quest_state.get("progress", 0))
		if str(quest_id).strip_edges().is_empty() or status.is_empty() or progress < 0:
			continue
		normalized[str(quest_id)] = {"status": status, "progress": progress}
	return normalized


func _generate_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]
