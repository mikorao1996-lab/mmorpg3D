class_name CharacterIdentity
extends RefCounted

## The identity of the character of this client.
##
## The server issues the identifier and the secret of a character on the first
## connection, and the client keeps them in the user directory. The client only
## sends the pair back to the server: it never stores or sends the progress of
## a character.
##
## The secret is a bearer token, and the transport is still plain ENet, so the
## token is readable for anyone on the wire. A protected transport belongs to
## the credential login step.

const DEFAULT_PATH: String = "user://character_identity.json"

var character_id: String = ""
var character_token: String = ""
var identity_path: String = DEFAULT_PATH


func _init(path: String = DEFAULT_PATH) -> void:
	identity_path = path
	load_identity()


## Loads the stored identity of the client.
##
## The result is `false` when there is no identity yet, which is the normal
## state of a fresh installation.
func load_identity() -> bool:
	if not FileAccess.file_exists(identity_path):
		return false
	var file: FileAccess = FileAccess.open(identity_path, FileAccess.READ)
	if file == null:
		push_error("Could not read the character identity: %s" % identity_path)
		return false
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("The character identity is not a valid document")
		return false
	var data: Dictionary = parsed
	character_id = str(data.get("character_id", ""))
	character_token = str(data.get("character_token", ""))
	return not character_id.is_empty()


## Stores the identity of the character and keeps it on disk.
##
## An empty secret keeps the stored one, because the server only sends the
## secret when it issues it.
func store(new_character_id: String, new_character_token: String = "") -> bool:
	if new_character_id.strip_edges().is_empty():
		return false
	character_id = new_character_id.strip_edges()
	if not new_character_token.strip_edges().is_empty():
		character_token = new_character_token.strip_edges()
	var file: FileAccess = FileAccess.open(identity_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write the character identity: %s" % identity_path)
		return false
	file.store_string(JSON.stringify({
		"character_id": character_id,
		"character_token": character_token,
	}))
	file.close()
	return true


## Forgets the stored identity.
##
## The next connection then starts a new character.
func clear() -> void:
	character_id = ""
	character_token = ""
	var directory: DirAccess = DirAccess.open("user://")
	if directory != null:
		directory.remove(identity_path.get_file())
