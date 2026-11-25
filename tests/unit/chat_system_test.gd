extends RefCounted

## Checks the server-authoritative chat rules.
##
## The tests cover the validation of a message, the rate limit of a player, and
## the capped chat history.

const ChatSystemType: GDScript = preload("res://server/systems/chat_system.gd")

const CONFIG: Dictionary = {
	"chat_message_max_length": 20,
	"chat_messages_per_second": 3,
	"chat_history_size": 4,
}


func run() -> bool:
	var chat_system: RefCounted = ChatSystemType.new(CONFIG)

	var empty_result: Dictionary = chat_system.validate_message("")
	if bool(empty_result["ok"]):
		push_error("The chat system accepted an empty message")
		return false
	if str(empty_result["reason"]) != "empty_message":
		push_error("An empty message did not report the empty message")
		return false

	var whitespace_result: Dictionary = chat_system.validate_message("   \n  ")
	if bool(whitespace_result["ok"]):
		push_error("The chat system accepted a message with only whitespace")
		return false

	var valid_result: Dictionary = chat_system.validate_message("  hello world  ")
	if not bool(valid_result["ok"]):
		push_error("The chat system rejected a valid message")
		return false
	if str(valid_result["text"]) != "hello world":
		push_error("The chat system did not normalize the message text")
		return false

	var multiline_result: Dictionary = chat_system.validate_message("first\nsecond")
	if str(multiline_result["text"]) != "first second":
		push_error("The chat system did not collapse a line break")
		return false

	var too_long_result: Dictionary = chat_system.validate_message(
		"0123456789012345678901234567890"
	)
	if bool(too_long_result["ok"]):
		push_error("The chat system accepted a message that is too long")
		return false
	if str(too_long_result["reason"]) != "message_too_long":
		push_error("A long message did not report the length limit")
		return false

	for _index: int in range(3):
		var rate_result: Dictionary = chat_system.check_rate(1, 1000)
		if not bool(rate_result["ok"]):
			push_error("The chat system rejected a message inside the rate limit")
			return false
	var limited_result: Dictionary = chat_system.check_rate(1, 1000)
	if bool(limited_result["ok"]):
		push_error("The chat system accepted a message above the rate limit")
		return false
	if str(limited_result["reason"]) != "rate_limited":
		push_error("A message above the rate limit did not report the rate limit")
		return false
	var next_window_result: Dictionary = chat_system.check_rate(1, 2000)
	if not bool(next_window_result["ok"]):
		push_error("The chat system did not reset the rate limit in the next window")
		return false
	var other_player_result: Dictionary = chat_system.check_rate(2, 2000)
	if not bool(other_player_result["ok"]):
		push_error("The rate limit of one player blocked another player")
		return false

	for _index: int in range(6):
		chat_system.remember(chat_system.build_message("say", 1, "Traveler", "hello"))
	var history: Array = chat_system.get_history()
	if history.size() != 4:
		push_error("The chat history does not respect the configured size")
		return false

	chat_system.forget_peer(1)
	var after_forget: Dictionary = chat_system.check_rate(1, 2000)
	if not bool(after_forget["ok"]):
		push_error("The chat system did not forget the rate limit of a peer")
		return false
	return true
