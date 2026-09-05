extends RefCounted
## Local control boundary. Protocol clients never receive the live Stores.

const Session = preload("res://scripts/sim/core/sim_session.gd")
const LiveView = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const OutpostView = preload("res://scripts/rebuild/v5_seventh_outpost_view_model.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")
const NETWORK := "res://data/sim/fixtures/generated_settlement_network_fixture.json"
const SAVE_ROOT := "user://agent_play/"
const CACHE_LIMIT := 32
const FIELDS := {
	"start": ["mode", "scenario", "seed"],
	"observe": [], "act": ["choice_id", "confirm"],
	"advance": ["hours"], "inspect": ["kind", "offset", "limit"],
	"save": ["slot", "overwrite"], "load": ["slot"],
}
const READ_ONLY := ["observe", "inspect"]

var revision: int = 0
var session_id: String = Crypto.new().generate_random_bytes(16).hex_encode()
var mode: String = ""
var scenario: String = ""
var surface: String = ""
var model: Variant = null
var _view: Dictionary = {}
var _choices: Dictionary = {}
var _receipts: Dictionary = {}


func handle(request: Variant) -> Dictionary:
	if not request is Dictionary:
		return _error("request_not_object")
	var command: String = str(request.get("command", ""))
	if not _integer(request.get("protocol"), 1, 1):
		return _error("unsupported_protocol")
	if not FIELDS.has(command):
		return _error("unknown_command")
	for key: Variant in request:
		if key not in ["protocol", "command", "request_id", "session_id", "expected_revision"] and key not in FIELDS[command]:
			return _error("unknown_field:%s" % str(key))
	var request_id: Variant = request.get("request_id", "")
	if not request_id is String or request_id.length() < 1 or request_id.length() > 96:
		return _error("invalid_request_id")
	var fingerprint := JSON.stringify(request, "", true, true)
	if command not in READ_ONLY and _receipts.has(request_id):
		var cached: Dictionary = _receipts[request_id]
		if cached.fingerprint != fingerprint:
			return _error("request_id_reused")
		var replay: Dictionary = cached.response.duplicate(true)
		replay["replayed"] = true
		return replay
	if command not in READ_ONLY:
		if request.get("session_id", "") != session_id:
			return _error("wrong_session")
		if not _integer(request.get("expected_revision"), revision, revision):
			return _error("stale_revision")
	var result: Dictionary
	if command == "start":
		result = _start(request)
	elif model == null:
		result = _error("not_started")
	else:
		match command:
			"observe": result = _response()
			"inspect": result = _inspect(request)
			"act": result = _act(request)
			"advance": result = _advance(request)
			"save": result = _save(request)
			"load": result = _load(request)
	result["request_id"] = request_id
	if command not in READ_ONLY:
		_receipts[request_id] = {"fingerprint": fingerprint, "response": result.duplicate(true)}
		if _receipts.size() > CACHE_LIMIT:
			_receipts.erase(_receipts.keys()[0])
	return result


func hello() -> Dictionary:
	return {"protocol": 1, "session_id": session_id, "revision": revision,
		"modes": ["world", "play"], "scenarios": ["generated_network", "lake_town", "first_winter"]}


func _start(request: Dictionary) -> Dictionary:
	var next_mode: Variant = request.get("mode", "world")
	var next_scenario: Variant = request.get("scenario", "generated_network")
	var seed: Variant = request.get("seed", 81001)
	if next_mode not in ["world", "play"] or next_scenario not in ["generated_network", "lake_town", "first_winter"]:
		return _error("invalid_start_profile")
	if next_mode == "world" and next_scenario != "generated_network":
		return _error("world_mode_requires_generated_network")
	if not _integer(seed, 1, 2147483647):
		return _error("invalid_seed")
	var next_model: Variant
	var result: Dictionary
	var options := {"challenge_seed_override": int(seed)}
	if next_scenario == "first_winter":
		next_model = OutpostView.new()
		result = next_model.start({}, "first_winter", options)
	else:
		var next_session := Session.new()
		result = next_session.start_from_fixture_path(
			NETWORK if next_scenario == "generated_network" else LiveView.FIXTURE_PATH,
			LiveView.RULE_PATHS, options)
		next_model = LiveView.new(next_session)
	if not result.get("success", false):
		return _error("start_failed:%s" % str(result.get("error", "unknown")))
	model = next_model
	mode = next_mode
	scenario = next_scenario
	surface = "outpost" if scenario == "first_winter" else "location"
	return _settled(result, "session_start")


func _session() -> Variant:
	return model.controller.session if surface == "outpost" else model.session


func _refresh() -> void:
	_choices.clear()
	if mode == "world":
		_view = {"visibility": "omniscient_debug", "actor_policy": "passive_fixture_actor",
			"time": _session().get_time_summary(), "counts": _session().get_store_summary(),
			"network": _session().get_settlement_network_summary()}
		return
	var projected: Dictionary = model.build_view_data()
	_view = {"visibility": "player_surface"}
	# Never expose raw transaction history or save payloads through player observation.
	for key: String in ["location", "playtest", "player", "time", "region_status", "visible_people",
		"visible_observations", "decision", "agency", "risk", "knowledge", "investigation",
		"chronicle", "feedback", "title", "subtitle", "phase_id", "day", "duration_days",
		"complete", "objective", "ritual", "status", "market", "people", "incident", "completion"]:
		if projected.has(key):
			_view[key] = projected[key].duplicate(true) if projected[key] is Array or projected[key] is Dictionary else projected[key]
	_view["time"] = _session().get_time_summary()
	for key: String in ["visible_people", "visible_observations"]:
		if _view.has(key):
			_view[key].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return str(a.get("id", "")) < str(b.get("id", "")))
	if surface == "location":
		_location_choices(projected)
	else:
		_outpost_choices(projected)


func _offer(kind: String, id: String, row: Dictionary, enabled: bool = true) -> void:
	if id == "":
		return
	var choice := row.duplicate(true)
	choice.merge({"choice_id": kind + "/" + id, "kind": kind, "id": id, "enabled": enabled}, true)
	_choices[choice.choice_id] = choice


func _location_choices(view: Dictionary) -> void:
	var combat := false
	for row: Dictionary in view.get("actions", []):
		var kind := str(row.get("event_type", "player_action"))
		combat = combat or kind == "combat_encounter"
		_offer(kind, str(row.get("action_id", "")), row, bool(row.get("can_execute", true)))
	for row: Dictionary in view.get("travel_options", []):
		_offer("travel", str(row.get("route_id", "")), row, bool(row.get("can_travel", false)))
	if not combat:
		_offer("wait", "one_hour", {"label": "等待一小时", "cost": "1 小时", "hint": "世界继续结算，不能保证局势改善。"})
	if bool(view.get("playtest", {}).get("completed", false)):
		_offer("phase", "first_winter", {"label": "进入第七哨站", "requires_confirmation": true,
			"warning": "旧生涯切片会载入新场景并只携带部分状态，尚非连续世界。"})


func _outpost_choices(view: Dictionary) -> void:
	for row: Dictionary in view.get("market", {}).get("offers", []):
		_offer("market", str(row.get("item_instance_id", "")), row, bool(row.get("can_purchase", false)))
	var incident: Dictionary = view.get("incident", {})
	if incident.get("active", false):
		for row: Dictionary in incident.get("responses", []):
			_offer("incident", str(row.get("response_id", "")), row, bool(row.get("can_execute", true)))
		return
	if not view.get("complete", false):
		for row: Dictionary in view.get("actions", []):
			_offer("duty", str(row.get("duty_id", "")), row, bool(row.get("can_execute", true)))
		return
	if view.get("can_advance_phase", false):
		var next_phase: String = {"first_winter": "first_quarter", "first_quarter": "first_year_close",
			"first_year_close": "second_year_reception"}.get(view.phase_id, "")
		_offer("phase", next_phase, {"label": "进入 " + next_phase, "requires_confirmation": true,
			"warning": "旧生涯切片会载入新场景并只携带部分状态，尚非连续世界。"})
		return
	var completion: Dictionary = view.get("completion", {})
	if view.phase_id == "first_winter":
		for row: Dictionary in completion.get("growth_candidates", []):
			if row.get("confirmed", false):
				return
		for row: Dictionary in completion.get("growth_candidates", []):
			var choice := row.duplicate(true)
			choice["requires_confirmation"] = true
			_offer("growth", str(row.get("candidate_id", "")), choice)
	elif view.phase_id == "first_year_close":
		var milestone: Dictionary = completion.get("milestone", {})
		if not milestone.get("resolved", false) and not milestone.get("outcomes", []).is_empty():
			_offer("milestone", "resolve", milestone)


func _act(request: Dictionary) -> Dictionary:
	if mode != "play":
		return _error("actor_actions_disabled_in_world_mode")
	var choice_id: Variant = request.get("choice_id", "")
	if not choice_id is String or not _choices.has(choice_id):
		return _error("choice_not_offered")
	var choice: Dictionary = _choices[choice_id]
	if not choice.enabled:
		return _error("choice_blocked")
	if request.has("confirm") and not request.confirm is bool:
		return _error("invalid_confirmation")
	if choice.get("requires_confirmation", false) and request.get("confirm", false) != true:
		return _error("confirmation_required")
	var result: Dictionary
	match choice.kind:
		"player_action": result = model.perform_action(choice.id)
		"travel": result = model.perform_travel(choice.id)
		"challenge": result = model.perform_challenge(choice.id)
		"combat_encounter": result = model.perform_combat_encounter(choice.id)
		"return_echo": result = model.perform_return_echo(choice.id)
		"investigation": result = model.perform_investigation(choice.id)
		"ferry_wait": result = model.wait_until_north_quay_ferry()
		"wait": result = model.advance_time(1)
		"duty": result = model.perform_duty(choice.id)
		"incident": result = model.resolve_life_incident(choice.id)
		"market": result = model.purchase_market_offer(choice.id, int(choice.unit_price), 1)
		"growth": result = model.confirm_growth_candidate(choice.id)
		"milestone": result = model.resolve_milestone()
		"phase": result = _enter_phase(choice.id)
		_: return _error("unsupported_choice_kind")
	# A formal operation can commit before its time step fails. Never auto-retry it.
	return _settled(result, "agent_action", choice_id)


func _enter_phase(id: String) -> Dictionary:
	if id == "first_winter":
		var transition: Dictionary = model.build_life_stage_transition()
		if transition.is_empty():
			return {"success": false, "error": "transition_not_ready"}
		var next_model := OutpostView.new()
		var result: Dictionary = next_model.start(transition)
		if result.get("success", false):
			model = next_model
			surface = "outpost"
		return result
	match id:
		"first_quarter": return model.enter_first_quarter()
		"first_year_close": return model.enter_first_year_close()
		"second_year_reception": return model.enter_second_year_reception()
	return {"success": false, "error": "unknown_phase"}


func _advance(request: Dictionary) -> Dictionary:
	if mode != "world":
		return _error("use_offered_actions_in_play_mode")
	if not _integer(request.get("hours"), 1, 24):
		return _error("hours_must_be_integer_1_to_24")
	var result: Dictionary = _session().advance_time(int(request.hours), "agent_world_advance", {
		"scope_type": "global", "scope_id": "", "source": "agent_world_observer"})
	return _settled(result, "world_advance")


func _inspect(request: Dictionary) -> Dictionary:
	if mode != "world":
		return _error("omniscient_inspection_disabled_in_play_mode")
	var offset: Variant = request.get("offset", 0)
	var limit: Variant = request.get("limit", 20)
	if not _integer(offset, 0, 10000000) or not _integer(limit, 1, 100):
		return _error("invalid_page")
	var rows: Array
	var stores: Dictionary = _session().stores
	match request.get("kind", "facts"):
		"facts": rows = stores.fact_store.snapshot_facts()
		"entities": rows = stores.entity_store.list_entities().values()
		"resources": rows = stores.resource_stock_store.list_stocks()
		"items": rows = stores.item_store.list_items()
		"obligations": rows = stores.obligation_store.list_obligations()
		"exchanges": rows = stores.exchange_store.list_exchanges()
		_: return _error("unknown_inspection_kind")
	var result := hello()
	result.merge({"ok": true, "visibility": "omniscient_debug", "offset": int(offset), "total": rows.size(),
		"rows": rows.slice(int(offset), mini(int(offset) + int(limit), rows.size())).duplicate(true)}, true)
	return result


func _slot_path(request: Dictionary) -> String:
	var slot: Variant = request.get("slot", "")
	if not slot is String or slot.length() < 1 or slot.length() > 48:
		return ""
	for character: String in slot:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return ""
	return SAVE_ROOT + mode + "/" + scenario + "/" + slot + ".json"


func _save(request: Dictionary) -> Dictionary:
	var path := _slot_path(request)
	if path == "":
		return _error("invalid_slot")
	if not request.get("overwrite", false) is bool:
		return _error("invalid_overwrite")
	if FileAccess.file_exists(path) and not request.get("overwrite", false):
		return _error("slot_exists")
	var envelope: Dictionary = model.controller.build_save_envelope() if surface == "outpost" else _session().build_save_envelope()
	var runtime := {"mode": mode, "scenario": scenario, "surface": surface,
		"latest_result": model.latest_result, "latest_event_type": model.latest_event_type}
	if surface == "location":
		runtime["action_history"] = model.action_history
		runtime["last_player_impact"] = model.last_player_impact
	envelope["agent_control"] = runtime.duplicate(true)
	var service := Saves.new()
	envelope = service.finalize_envelope(envelope)
	var temporary := path + "." + session_id + ".tmp"
	var result := service.save_to_path(temporary, envelope)
	if not result.get("ok", false):
		return _error("save_failed:%s" % str(result.get("error", "unknown")))
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _error("save_replace_failed:%d" % rename_error)
	return _settled({"success": true}, "save")


func _load(request: Dictionary) -> Dictionary:
	var path := _slot_path(request)
	if path == "":
		return _error("invalid_slot")
	var loaded := Saves.new().load_from_path(path)
	if not loaded.get("ok", false):
		return _error("load_failed:%s" % str(loaded.get("error", "unknown")))
	var envelope: Dictionary = loaded.envelope
	var runtime: Variant = envelope.get("agent_control", {})
	if not runtime is Dictionary or runtime.get("mode") != mode or runtime.get("scenario") != scenario:
		return _error("save_profile_mismatch")
	var next_surface: Variant = runtime.get("surface", "")
	if next_surface not in ["outpost", "location"] or (mode == "world" and next_surface != "location"):
		return _error("save_surface_invalid")
	if not runtime.get("latest_result", {}) is Dictionary or not runtime.get("latest_event_type", "") is String:
		return _error("save_surface_runtime_invalid")
	if next_surface == "location":
		if not runtime.get("action_history", []) is Array or not runtime.get("last_player_impact", {}) is Dictionary:
			return _error("save_surface_runtime_invalid")
		for row: Variant in runtime.get("action_history", []):
			if not row is Dictionary:
				return _error("save_surface_runtime_invalid")
	var next_model: Variant
	var result: Dictionary
	if next_surface == "outpost":
		next_model = OutpostView.new()
		result = next_model.load_from_path(path)
	else:
		var next_session := Session.new()
		result = next_session.load_from_save_envelope(envelope)
		next_model = LiveView.new(next_session)
	if not result.get("success", false):
		return _error("load_failed:%s" % str(result.get("error", "unknown")))
	next_model.latest_result = runtime.get("latest_result", {}).duplicate(true)
	next_model.latest_event_type = runtime.get("latest_event_type", "")
	if next_surface == "location":
		next_model.action_history.assign(runtime.get("action_history", []))
		next_model.last_player_impact = runtime.get("last_player_impact", {}).duplicate(true)
	model = next_model
	surface = next_surface
	return _settled({"success": true}, "load")


func _settled(result: Dictionary, cause: String, choice_id: String = "") -> Dictionary:
	revision += 1
	_refresh()
	var response := _response()
	response["ok"] = bool(result.get("success", result.get("ok", false)))
	response["receipt"] = {"cause": cause, "choice_id": choice_id, "world_time": _session().get_time_summary(),
		"control_source": "code_agent", "success": response.ok,
		"error": result.get("error", result.get("error_reason", "")),
		"partial_commit_possible": not response.ok, "automatic_retry_safe": false}
	return response


func _response() -> Dictionary:
	var result := hello()
	var choices: Array = _choices.values().duplicate(true)
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.choice_id) < str(b.choice_id))
	result.merge({"ok": true, "mode": mode, "scenario": scenario, "surface": surface,
		"observation": _view.duplicate(true), "choices": choices}, true)
	return result


func _error(reason: String) -> Dictionary:
	var result := hello()
	result.merge({"ok": false, "error": reason, "rejected_before_execution": true}, true)
	return result


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum
