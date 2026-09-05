extends RefCounted
## A live-location save preserves the session, not a life-stage transition subset.

const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")


func save_model(model: Variant, path: String, overwrite: bool = false) -> Dictionary:
	if not model.is_ready():
		return _failure("session_not_initialized")
	if FileAccess.file_exists(path) and not overwrite:
		return _failure("save_exists")
	var envelope: Dictionary = model.session.build_save_envelope()
	envelope["live_surface_runtime"] = {
		"version": 1, "latest_result": model.latest_result,
		"latest_event_type": model.latest_event_type,
		"action_history": model.action_history, "last_player_impact": model.last_player_impact,
	}
	var service := Saves.new()
	envelope = service.finalize_envelope(envelope)
	var temporary := path + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var written := service.save_to_path(temporary, envelope)
	if not written.get("ok", false):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _failure(str(written.get("error", "save_failed")))
	# Read-back validation catches incomplete writes before touching the previous save.
	var checked := service.load_from_path(temporary)
	if not checked.get("ok", false):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _failure(str(checked.get("error", "save_readback_failed")))
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _failure("save_replace_failed:%d" % error)
	return {"success": true, "path": path, "byte_count": written.byte_count}


func load_model(model: Variant, path: String) -> Dictionary:
	var loaded := Saves.new().load_from_path(path)
	if not loaded.get("ok", false):
		return _failure(str(loaded.get("error", "load_failed")))
	var envelope: Dictionary = loaded.envelope
	if envelope.get("source_kind", "") != "player_save":
		return _failure("not_a_player_save")
	var runtime: Variant = envelope.get("live_surface_runtime", {})
	if not runtime is Dictionary or runtime.get("version", 0) != 1:
		return _failure("live_surface_runtime_missing")
	if not runtime.get("latest_result") is Dictionary or not runtime.get("last_player_impact") is Dictionary or not runtime.get("latest_event_type") is String or not runtime.get("action_history") is Array:
		return _failure("live_surface_runtime_invalid")
	for row: Variant in runtime.action_history:
		if not row is Dictionary:
			return _failure("live_surface_history_invalid")
	var candidate := Session.new()
	var restored := candidate.load_from_save_envelope(envelope)
	if not restored.get("success", false):
		return _failure(str(restored.get("error", "session_load_failed")))
	model.session = candidate
	model.start_result = restored.duplicate(true)
	model.latest_result = runtime.latest_result.duplicate(true)
	model.latest_event_type = runtime.latest_event_type
	model.last_player_impact = runtime.last_player_impact.duplicate(true)
	model.action_history.assign(runtime.action_history)
	return {"success": true, "path": path}


func _failure(reason: String) -> Dictionary:
	return {"success": false, "error": reason}
