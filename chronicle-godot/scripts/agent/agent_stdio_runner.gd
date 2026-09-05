extends SceneTree

const Game = preload("res://scripts/agent/agent_game_session.gd")
const PREFIX := "CHRONICLE_AGENT_JSON\t"
const MAX_REQUEST_BYTES := 65536


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Agent runner requires --headless.")
		quit(2)
		return
	var game := Game.new()
	_emit({"event": "hello", "ok": true, "session": game.hello()})
	while true:
		var header := _read_exact(8)
		if header.is_empty():
			quit(0)
			return
		var valid := header.size() == 8
		for byte: int in header:
			valid = valid and byte >= 48 and byte <= 57
		var count := header.get_string_from_ascii().to_int() if valid else 0
		if count < 1 or count > MAX_REQUEST_BYTES:
			_emit({"ok": false, "error": "invalid_frame_length"})
			quit(2)
			return
		var payload := _read_exact(count)
		if payload.size() != count:
			_emit({"ok": false, "error": "incomplete_frame"})
			quit(2)
			return
		var parser := JSON.new()
		var decoded := payload.get_string_from_utf8()
		if payload.has(0) or decoded.to_utf8_buffer() != payload or parser.parse(decoded) != OK:
			_emit({"ok": false, "error": "invalid_json"})
			continue
		_emit(game.handle(parser.data))


func _read_exact(count: int) -> PackedByteArray:
	var result := PackedByteArray()
	while result.size() < count:
		# Godot 4.6.3 Windows returns a requested-size buffer even on a short ReadFile.
		# Reading one byte avoids padded partial frames and preserves UTF-8 boundaries.
		var remaining := 1 if OS.get_name() == "Windows" else count - result.size()
		var chunk := OS.read_buffer_from_stdin(remaining)
		if chunk.is_empty():
			break
		result.append_array(chunk)
	return result


func _emit(response: Dictionary) -> void:
	print(PREFIX + JSON.stringify(response, "", true, true))
