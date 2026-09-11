extends SceneTree

const Session = preload("res://scripts/sim/core/sim_session.gd")
const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] == args[1]:
		push_error("Expected distinct agent checkpoint and test UI output paths")
		quit(1)
		return
	var source := Saves.new().load_from_path(args[0])
	if not source.ok or source.envelope.get("agent_control", {}).get("surface") != "location":
		push_error("Expected a valid location agent checkpoint")
		quit(1)
		return
	var session := Session.new()
	var loaded := session.load_from_save_envelope(source.envelope)
	if not loaded.success:
		push_error(str(loaded))
		quit(1)
		return
	var runtime: Dictionary = source.envelope.agent_control
	var model := Live.new(session)
	model.latest_result = runtime.latest_result.duplicate(true)
	model.latest_event_type = runtime.latest_event_type
	model.action_history.assign(runtime.action_history)
	model.last_player_impact = runtime.last_player_impact.duplicate(true)
	var saved := model.save_to_path(args[1], false)
	if not saved.success:
		push_error(str(saved))
		quit(1)
		return
	var ui := Saves.new().load_from_path(args[1])
	for key: String in ["stores", "session", "world_time", "rng_states", "world_log"]:
		if ui.envelope[key] != source.envelope[key]:
			push_error("UI probe changed native truth: " + key)
			quit(1)
			return
	print("AGENT_UI_PROBE_PREPARED native truth unchanged; only the formal UI presentation wrapper differs")
	quit(0)
