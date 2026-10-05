extends "res://tests/sim/situation_choice_chain_phase2_test.gd"

const View = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Presentation = preload("res://scripts/rebuild/roaming_presentation.gd")
var request_serial := 0


func _call(game: Variant, command: String, args: Dictionary = {}) -> Dictionary:
	request_serial += 1
	var request := {"protocol": 1, "request_id": "goal.%d" % request_serial, "command": command,
		"session_id": game.session_id, "expected_revision": game.revision}
	request.merge(args)
	return game.handle(request)


func _run() -> void:
	var game := NewAgent.new()
	var response := _call(game, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v2"})
	_check(response.ok, "natural goal world starts")
	if not response.ok:
		_finish()
		return
	_check(response.observation.goal_pressure.selected.is_empty(), "no automatically imposed goal")
	_check(response.observation.goal_pressure.candidates.all(func(c: Dictionary) -> bool: return c.id != "replace_outerwear"), "worn winter cloak is not falsely missing")
	var before := _signature(game.model.session)
	var candidates: Array = response.observation.goal_pressure.candidates
	var chosen: Dictionary = candidates[0]
	response = _call(game, "set_goal", {"goal_id": chosen.id})
	_check(response.ok and response.observation.goal_pressure.selected.id == chosen.id, "public selection succeeds")
	_check(before == _signature(game.model.session), "selecting goal does not mutate any world truth, time or RNG")
	_check(not _call(game, "set_goal", {"goal_id": "visit:hidden_fake_place"}).ok, "cannot select hidden invented location")
	_check(not _call(game, "set_goal", {"goal_id": 7}).ok, "goal type validated")
	_check(_call(game, "save", {"slot": "goal_contract", "overwrite": true}).ok, "goal saves through native agent envelope")
	_check(_call(game, "set_goal", {"goal_id": ""}).ok, "abandon intention without world consequence")
	response = _call(game, "load", {"slot": "goal_contract"})
	_check(response.ok and response.observation.goal_pressure.selected.id == chosen.id, "native agent load retains intention")
	_check(Presentation.build(response, "all").choices.size() == response.choices.size(), "more actions preserves every legal candidate")
	var base: Dictionary = game.model.session.fixture_source_data.duplicate(true)
	var host: Dictionary = base.entities.filter(func(e: Dictionary) -> bool: return e.has("guesthouse_rules") and e.states.get("settlement_id") == "generated_settlement.echo_landing")[0]
	for cash: int in [9, 4]:
		_coupling(base, host, cash)
	_finish()


func _coupling(base: Dictionary, host: Dictionary, cash: int) -> void:
	var model := View.new()
	model.session = _prepared(_fixture(base, host, cash, 17))
	_ask(model.session)
	var data := model.build_view_data()
	var goals: Array = data.goal_pressure.candidates.filter(func(g: Dictionary) -> bool: return g.id.begins_with("visit:") and g.source.begins_with("fact."))
	_check(not goals.is_empty(), "test testimony offers grounded danger destination")
	if goals.is_empty():
		return
	_check(model.set_current_goal(goals[0].id).success, "select testimony-derived destination")
	var selected := model.current_goal.duplicate(true)
	var worn: Array = _options(model.session, "give").filter(func(r: Dictionary) -> bool: return r.has("clear_slots"))
	_check(not worn.is_empty(), "test-injected meeting offers real own armor gift")
	if worn.is_empty():
		return
	_check(model.session.PlayerLife.execute(model.session, worn[0].action_id).success, "actual gift transaction")
	data = model.build_view_data()
	_check(data.goal_pressure.pressure.contains("赠出"), "current goal shows causal loss from actual gift")
	_check(data.goal_pressure.urgency == "current", "missing armor is current pressure for the known destination")
	_check(data.goal_pressure.selected.id == selected.id, "gift does not switch player's goal")
	var buys: Array = data.actions.filter(func(r: Dictionary) -> bool: return r.action_id == "buy:test.phase2.mantle")
	_check(buys.size() == 1 and buys[0].goal_priority > 0 and buys[0].price == 5, "actual replacement and price promoted")
	_check(buys[0].can_execute == (cash >= 5), "goal never overrides money restriction")
	_check(data.goal_pressure.alternatives.any(func(r: Dictionary) -> bool: return r.enabled and "safety" in r.cost_categories), "going without armor remains a legal alternative")
	_check(data.goal_pressure.candidates.any(func(g: Dictionary) -> bool: return g.id == "followup:" + WHO), "actual gift recipient can be followed up")
	var signature := _signature(model.session)
	model.build_view_data()
	model.set_current_goal("")
	_check(signature == _signature(model.session), "projection and abandonment preserve world including absent people")
	model.current_goal = selected
	_check(model.save_to_path("user://tests/situations/goal_view_%d.json" % cash, true).success, "view native save")
	var restored := View.new()
	_check(restored.load_from_path("user://tests/situations/goal_view_%d.json" % cash).success, "view native restore")
	_check(restored.current_goal == selected, "view save retains intention without quest state")
	if cash >= 5:
		_check(model.session.PlayerLife.execute(model.session, "buy:test.phase2.mantle").success, "replacement actually purchased")
		data = model.build_view_data()
		var equips: Array = data.actions.filter(func(r: Dictionary) -> bool: return r.action_id.begins_with("equip:test.phase2.mantle"))
		_check(not equips.is_empty() and equips[0].goal_priority > 0, "buying does not falsely restore worn protection")
		if not equips.is_empty():
			_check(model.session.PlayerLife.execute(model.session, equips[0].action_id).success, "replacement equipped through real action")
			data = model.build_view_data()
			_check(data.goal_pressure.urgency == "none", "actual re-equipping clears pressure")
			_check(model.session.PlayerLife.execute(model.session, "unequip:body_outer").success, "can later remove replacement")
			data = model.build_view_data()
			_check(not data.goal_pressure.pressure.contains("赠出"), "later voluntary removal is not falsely blamed on historical gift")
