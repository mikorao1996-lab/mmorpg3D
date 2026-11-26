class_name InMemoryCharacterRepository
extends RefCounted

## A character repository that keeps the characters in memory.
##
## The repository follows the contract of `server/db/character_repository.gd`,
## so the character service and the server can be tested without a database.
## The PostgreSQL specific behaviour lives in the integration test of the
## repository itself.

var characters: Dictionary = {}
var write_failures: int = 0


## Stores a character and fails when it already exists.
func create_character(character: Dictionary) -> Dictionary:
	if write_failures > 0:
		write_failures -= 1
		return {"ok": false, "error": "Injected write failure."}
	var character_id: String = str(character["character_id"])
	if characters.has(character_id):
		return {"ok": false, "error": "The character already exists."}
	characters[character_id] = character.duplicate(true)
	return {"ok": true, "error": ""}


## Stores a character and replaces an existing one.
func save_character(character: Dictionary) -> Dictionary:
	if write_failures > 0:
		write_failures -= 1
		return {"ok": false, "error": "Injected write failure."}
	characters[str(character["character_id"])] = character.duplicate(true)
	return {"ok": true, "error": ""}


## Reads a character by its identifier.
func load_character(character_id: String) -> Dictionary:
	if not characters.has(character_id):
		return {"ok": true, "found": false}
	return {
		"ok": true,
		"found": true,
		"character": characters[character_id].duplicate(true),
	}
