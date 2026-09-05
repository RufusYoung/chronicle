extends SceneTree

const Game = preload("res://scripts/agent/agent_game_session.gd")
const LiveView = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const OutpostView = preload("res://scripts/rebuild/v5_seventh_outpost_view_model.gd")

var failures: Array[String] = []
var checks: int = 0
var serial: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := Game.new()
	_check(not game.handle([]).ok, "non-object requests rejected")
	_check(_call(game, "observe").error == "not_started", "explicit start required")
	_check(_call(game, "start", {"mode": "world", "scenario": "lake_town"}).error == "world_mode_requires_generated_network", "observer cannot run a scripted actor profile")
	var opened := _call(game, "start", {"mode": "play", "scenario": "lake_town", "seed": 81001})
	_check(opened.ok and not opened.choices.is_empty(), "lake town exposes formal choices")
	var initial := _signature(game.model.session)
	for index: int in range(3):
		_call(game, "observe")
	_check(initial == _signature(game.model.session), "observation preserves Stores, cursors and RNG")
	_check(_call(game, "inspect").error == "omniscient_inspection_disabled_in_play_mode", "player cannot inspect hidden facts")
	_check(not opened.observation.has("history") and not opened.has("stores"), "raw histories and Stores omitted")
	var untouched := game.revision
	_check(_call(game, "advance", {"hours": 24}).error == "use_offered_actions_in_play_mode", "player cannot bypass time or encounter rules")
	_check(_call(game, "act", {"choice_id": "travel/old_chen_shop_to_abandoned_granary"}).error == "choice_not_offered", "UI route gate enforced")
	_check(_call(game, "act", {"choice_id": "wait/one_hour", "force_roll": 1}).error == "unknown_field:force_roll", "roll injection rejected")
	_check(_call(game, "save", {"slot": "../../outside"}).error == "invalid_slot", "save paths confined")
	_check(_call(game, "start", {"seed": 1.5}).error == "invalid_seed", "fractional seed rejected")
	_check(game.revision == untouched and initial == _signature(game.model.session), "rejected commands have no gameplay effect")

	var action := "player_action/read_visible_readable_object:old_chen_shop_price_notice"
	var request := _request(game, "act", {"choice_id": action})
	var result := game.handle(request)
	_check(result.ok and result.receipt.cause == "agent_action", "code control receipt explicitly labelled")
	_check(not _has_choice(result, action), "completed observation disappears")
	_check("北路车未到" in JSON.stringify(result.observation.feedback), "actual discovery returned in feedback")
	var committed := _signature(game.model.session)
	var foreign := _request(game, "act", {"choice_id": "wait/one_hour"})
	foreign.session_id = "another-process"
	_check(game.handle(foreign).error == "wrong_session", "foreign session cannot mutate")
	var replay := game.handle(request)
	_check(replay.replayed and replay.revision == result.revision and committed == _signature(game.model.session), "same request returns receipt without a second action")
	var collision := request.duplicate(true)
	collision.choice_id = "wait/one_hour"
	_check(game.handle(collision).error == "request_id_reused", "changed payload cannot reuse request identity")
	var stale := request.duplicate(true)
	stale.request_id = "new-stale"
	_check(game.handle(stale).error == "stale_revision", "stale control revision rejected")
	_check(_call(game, "act", {"choice_id": action}).error == "choice_not_offered", "completed choice cannot be replayed under fresh identity")
	var direct := LiveView.new()
	direct.start({"challenge_seed_override": 81001})
	direct.build_view_data()
	direct.perform_action("read_visible_readable_object:old_chen_shop_price_notice")
	direct.build_view_data()
	_check(committed == _signature(direct.session), "agent action matches formal ViewModel including RNG and cursors")
	var slot := "contract_" + game.session_id
	var before_save := _call(game, "observe")
	_check(_call(game, "save", {"slot": slot}).ok, "native save envelope written")
	_check(_call(game, "save", {"slot": slot}).error == "slot_exists", "overwrite requires explicit flag")
	_check(_call(game, "save", {"slot": slot, "overwrite": true}).ok, "explicit atomic slot replacement works")
	_call(game, "act", {"choice_id": "wait/one_hour"})
	var after_wait := _signature(game.model.session)
	_check(_call(game, "load", {"slot": slot}).ok, "native save restored")
	var restored := _call(game, "observe")
	_check(_canonical(restored.observation) == _canonical(before_save.observation), "save restores feedback and player projection")
	_check(_signature(game.model.session) == committed, "save restores complete simulation state")
	_call(game, "act", {"choice_id": "wait/one_hour"})
	_check(_signature(game.model.session) == after_wait, "save continuation deterministic")
	var before_missing := _signature(game.model.session)
	_check(not _call(game, "load", {"slot": "missing_" + game.session_id}).ok and _signature(game.model.session) == before_missing, "failed load preserves current session")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_ROOT + "play/lake_town/" + slot + ".json"))

	var world := Game.new()
	var started := _call(world, "start", {"mode": "world", "scenario": "generated_network", "seed": 81001})
	_check(started.ok and started.choices.is_empty(), "generated world has no actor commands")
	var world_initial := _signature(world.model.session)
	for kind: String in ["facts", "entities", "resources", "items", "obligations", "exchanges"]:
		var page := _call(world, "inspect", {"kind": kind, "limit": 2})
		_check(page.ok and page.rows.size() <= 2, "bounded inspection: " + kind)
	_check(world_initial == _signature(world.model.session), "omniscient inspection is read-only")
	_check(_call(world, "act", {"choice_id": "wait/one_hour"}).error == "actor_actions_disabled_in_world_mode", "observer has no actor authority")
	_check(not _call(world, "advance", {"hours": true}).ok and not _call(world, "advance", {"hours": 25}).ok, "time bounds and types enforced")
	var advanced := _call(world, "advance", {"hours": 24})
	_check(advanced.ok and advanced.receipt.cause == "world_advance", "autonomous daily cycle exposed")
	_check(_signature(world.model.session) != world_initial and world.model.session.action_count == 0, "world changes with no actor actions")
	var world_slot := "contract_" + world.session_id
	var original_world: Variant = world.model.session
	var world_saved := _signature(original_world, true)
	_check(_call(world, "save", {"slot": world_slot}).ok and _call(world, "load", {"slot": world_slot}).ok, "world observer save round trip")
	_check(world_saved == _signature(world.model.session, true) and _call(world, "observe").choices.is_empty(), "world save preserves native JSON precision and no-actor boundary")
	original_world.advance_time(1, "agent_world_advance", {
		"scope_type": "global", "scope_id": "", "source": "agent_world_observer"})
	_check(_call(world, "advance", {"hours": 1}).ok and _signature(original_world, true) == _signature(world.model.session, true), "world continuation matches at native save precision")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_ROOT + "world/generated_network/" + world_slot + ".json"))
	var fact_page := _call(world, "inspect", {"kind": "facts", "offset": 10000000})
	_check(fact_page.ok and fact_page.rows.is_empty(), "out-of-range inspection is an empty page")

	var winter := Game.new()
	var winter_start := _call(winter, "start", {"mode": "play", "scenario": "first_winter", "seed": 82002})
	_check(winter_start.ok and _has_kind(winter_start, "duty"), "first winter is code playable")
	var reference := OutpostView.new()
	reference.start({}, "first_winter", {"challenge_seed_override": 82002})
	reference.build_view_data()
	for choice: Dictionary in winter_start.choices:
		if choice.kind == "market" and choice.enabled:
			var purchase := _call(winter, "act", {"choice_id": choice.choice_id})
			reference.purchase_market_offer(choice.id, int(choice.unit_price), 1)
			reference.build_view_data()
			_check(purchase.ok and _signature(winter.model.controller.session) == _signature(reference.controller.session), "market action uses the actual quote, inventory and payment")
			break
	winter_start = _call(winter, "observe")
	var selected: Dictionary = {}
	for choice: Dictionary in winter_start.choices:
		if choice.kind == "duty" and choice.enabled:
			selected = choice
			break
	if not selected.is_empty():
		var acted := _call(winter, "act", {"choice_id": selected.choice_id})
		reference.perform_duty(selected.id)
		reference.build_view_data()
		_check(acted.ok and _signature(winter.model.controller.session) == _signature(reference.controller.session), "first winter duty matches formal controller")
		var winter_slot := "contract_" + winter.session_id
		var saved_view := _call(winter, "observe")
		_check(_call(winter, "save", {"slot": winter_slot}).ok and _call(winter, "load", {"slot": winter_slot}).ok, "life-project save keeps controller runtime")
		_check(_canonical(_call(winter, "observe").observation) == _canonical(saved_view.observation), "outpost feedback and incident state survive save")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_ROOT + "play/first_winter/" + winter_slot + ".json"))
	else:
		_check(false, "first winter has an enabled duty")
	print("AGENT_CONTRACT: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _request(game: Variant, command: String, arguments: Dictionary = {}) -> Dictionary:
	serial += 1
	var request := {"protocol": 1, "request_id": "test_%d" % serial, "command": command,
		"session_id": game.session_id, "expected_revision": game.revision}
	request.merge(arguments, true)
	return request


func _call(game: Variant, command: String, arguments: Dictionary = {}) -> Dictionary:
	return game.handle(_request(game, command, arguments))


func _signature(session: Variant, native_save_precision: bool = false) -> String:
	var envelope: Dictionary = session.build_save_envelope()
	var state := {"stores": envelope.stores, "rng": envelope.rng_states,
		"session": envelope.session, "time": envelope.world_time, "log": envelope.world_log}
	if native_save_precision:
		# The existing SaveEnvelope deliberately uses shortest JSON decimal precision.
		var encoded := JSON.stringify(state, "", true, false)
		return JSON.stringify(JSON.parse_string(encoded), "", true, false).sha256_text()
	return _canonical(state).sha256_text()


func _canonical(value: Variant) -> String:
	# JSON numbers load as floats. Compare exact wire values, not int/float spelling.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _has_choice(result: Dictionary, id: String) -> bool:
	for choice: Dictionary in result.get("choices", []):
		if choice.choice_id == id:
			return true
	return false


func _has_kind(result: Dictionary, kind: String) -> bool:
	for choice: Dictionary in result.get("choices", []):
		if choice.kind == kind:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures.append(label)
		push_error("FAIL: " + label)
