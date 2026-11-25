class_name ChatSystem
extends RefCounted

## Server-authoritative chat rules.
##
## The system validates every message before it is accepted: a message has to
## fit into the configured length limit, it must not be empty, and a player may
## only send a limited number of messages per second. The system never sends
## anything itself; it only builds the message and remembers it, so the caller
## decides who receives it.

const CHANNEL_SAY: String = "say"
const CHANNEL_PARTY: String = "party"
const CHANNEL_SYSTEM: String = "system"
const CHANNELS: PackedStringArray = [CHANNEL_SAY, CHANNEL_PARTY, CHANNEL_SYSTEM]

const RATE_WINDOW_MILLISECONDS: int = 1000

var _max_message_length: int = 120
var _messages_per_second: int = 5
var _history_size: int = 30
var _send_windows: Dictionary = {}
var _history: Array[Dictionary] = []


func _init(config: Dictionary = {}) -> void:
	_max_message_length = int(config.get("chat_message_max_length", 120))
	_messages_per_second = int(config.get("chat_messages_per_second", 5))
	_history_size = int(config.get("chat_history_size", 30))


## Validates the text of a message.
##
## The text is trimmed and the inner whitespace is collapsed, so a message
## cannot smuggle line breaks into the chat history.
func validate_message(text: String) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": "", "text": ""}
	var normalized: String = _normalize_text(text)
	if normalized.is_empty():
		result["reason"] = "empty_message"
		return result
	if normalized.length() > _max_message_length:
		result["reason"] = "message_too_long"
		return result
	result["ok"] = true
	result["text"] = normalized
	return result


## Checks whether a player may send a message right now.
func check_rate(peer_id: int, now_ms: int) -> Dictionary:
	var window: Dictionary = _send_windows.get(peer_id, {})
	var window_start: int = int(window.get("start_ms", now_ms))
	var sent_count: int = int(window.get("count", 0))
	if now_ms - window_start >= RATE_WINDOW_MILLISECONDS:
		window_start = now_ms
		sent_count = 0
	if sent_count >= _messages_per_second:
		return {"ok": false, "reason": "rate_limited"}
	_send_windows[peer_id] = {"start_ms": window_start, "count": sent_count + 1}
	return {"ok": true}


## Builds a chat message.
##
## A player message carries the text; a system message carries a translation
## key and the name of the subject the message is about.
func build_message(
	channel: String,
	sender_peer_id: int,
	sender_name: String,
	text: String,
	system_key: String = "",
) -> Dictionary:
	return {
		"channel": channel,
		"sender_peer_id": sender_peer_id,
		"sender_name": sender_name,
		"text": text,
		"system_key": system_key,
		"timestamp_ms": Time.get_ticks_msec(),
	}


## Remembers a message in the history.
##
## The history keeps the most recent messages of the zone; it is capped by the
## configured history size.
func remember(message: Dictionary) -> void:
	_history.append(message)
	while _history.size() > _history_size:
		_history.pop_front()


## Returns the remembered messages.
func get_history() -> Array:
	return _history.duplicate()


## Forgets the rate limit state of a player.
func forget_peer(peer_id: int) -> void:
	_send_windows.erase(peer_id)


## Trims the text and collapses the inner whitespace.
func _normalize_text(text: String) -> String:
	var normalized: String = " ".join(text.strip_edges().split("\n"))
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return normalized.strip_edges()
