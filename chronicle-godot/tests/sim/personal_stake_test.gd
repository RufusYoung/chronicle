extends "res://tests/sim/interest_pursuit_test.gd"


func _run() -> void:
	var game := NewAgent.new()
	var response := _call(game, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v2"})
	_check(response.observation.goal_pressure.personal_stakes.is_empty(), "no invented stakes before player intention")
	var base: Dictionary = game.model.session.fixture_source_data.duplicate(true)
	var host: Dictionary = base.entities.filter(func(e: Dictionary) -> bool: return e.has("guesthouse_rules") and e.states.get("settlement_id") == "generated_settlement.echo_landing")[0]
	for id: String in ["situation:ask:generated_resident.echo_landing.008:", "generated_route.network.echo_shore_road.a_to_b"]:
		response = _act_offered(game, response, id)
	response = _call(game, "set_goal", {"goal_id": "visit:generated_location.echo_terrace.terraces"})
	var intended: Dictionary = response.observation.goal_pressure.selected.duplicate(true)
	_check(intended.intent_basis == "destination" and not intended.title.contains("危险"), "own destination chosen before hearing danger")
	for id: String in ["situation:ask:generated_resident.echo_terrace.006:", "generated_route.echo_terrace.commons_to_terrace_farming",
		"situation:follow:generated_resident.echo_terrace.008:generated_route.echo_terrace.terrace_farming_to_commons",
		"situation:ask:generated_resident.echo_terrace.008:"]:
		response = _act_offered(game, response, id)
	var overlap: Dictionary = response.observation.goal_pressure
	_check(overlap.selected == intended, "world news cannot rewrite the player's original purpose")
	_check(overlap.goal_status == "arrived" and not overlap.interest.promoted, "selfplay regression: completed destination does not turn later rumor into reason to return")
	_check(overlap.candidates.any(func(c: Dictionary) -> bool: return c.id == "visit:generated_home.echo_terrace.01"), "selfplay regression: legal guesthouse is not dropped by an arbitrary six-goal cap")
	response = _call(game, "set_goal", {"goal_id": intended.id})
	intended = response.observation.goal_pressure.selected.duplicate(true)
	overlap = response.observation.goal_pressure
	_check(overlap.goal_status == "active", "only an explicit new selection reopens a completed trip")
	_check(overlap.interest.promoted and overlap.why_it_matters_to_you.contains("已知消息"), "known danger overlaps chosen destination with factual explanation")
	_check(not overlap.intention_before_testimony, "explicit revisit after hearing testimony is not disguised as a preexisting goal")
	_check(overlap.personal_stakes.any(func(s: Dictionary) -> bool: return s.stake_type == "ROUTE_ACCESS"), "route stake grounded in selected place")
	_check(overlap.personal_stakes.any(func(s: Dictionary) -> bool: return s.stake_type == "SELF_SURVIVAL"), "real equipment consumer named without requiring fake gift")
	_check(overlap.personal_stakes.all(func(s: Dictionary) -> bool: return s.stake_type != "RELATIONSHIP"), "meetings and trust do not manufacture relationship stake")
	_check(overlap.alternatives.any(func(a: Dictionary) -> bool: return a.get("role") == "postpone_without_resolving"), "real waiting cost is visible but does not promise a resolution")
	_check(overlap.alternatives.any(func(a: Dictionary) -> bool: return a.get("role") == "leave_original_plan"), "another legal road is a change of plan, not a substitute destination")
	_check(Presentation.build(response).body.contains("已知消息"), "public main scene explains why news matters")
	_check(Presentation.build(response).title == intended.title, "scene preserves destination rather than changing to investigation")
	var signature := _signature(game.model.session)
	_call(game, "observe")
	_check(signature == _signature(game.model.session), "stake projection leaves world, RNG and clock untouched")
	_check(_call(game, "save", {"slot": "personal_stake_contract", "overwrite": true}).ok, "native save stores only existing intention metadata")
	var restored := _call(game, "load", {"slot": "personal_stake_contract"})
	_check(JSON.parse_string(JSON.stringify(restored.observation.goal_pressure)) == JSON.parse_string(JSON.stringify(overlap)), "native restore recomputes identical public stakes")
	game.model.current_goal.erase("intent_basis")
	var legacy: Dictionary = game.model.build_view_data().goal_pressure
	_check(not legacy.interest.promoted and legacy.selected.title == intended.title, "legacy intention is kept but not retrospectively certified as prior destination")
	var confirmed := _call(game, "set_goal", {"goal_id": intended.id})
	_check(confirmed.ok and confirmed.observation.goal_pressure.interest.promoted, "legacy player may explicitly reselect a currently offered destination")
	game.model.current_goal = intended.duplicate(true)
	response = _call(game, "set_goal", {"goal_id": ""})
	_check(response.observation.goal_pressure.personal_stakes.is_empty(), "abandoning destination removes current overlap")
	_check(response.observation.goal_pressure.interests.size() == 1 and not response.observation.goal_pressure.interests[0].promoted, "same world news remains available without false importance")
	_check(not Presentation.build(response).body.contains("你原本要去这里"), "unrelated rumor cannot take over main scene")
	_check(Presentation.build(response).choices.all(func(c: Dictionary) -> bool: return c.get("intent") != "pursue"), "unrelated pursuit cannot reenter primary actions through the focused NPC")
	_check(Presentation.build(response, "map").choices.any(func(c: Dictionary) -> bool: return c.get("intent") == "pursue"), "secondary map retains voluntary pursuit")
	_check(signature == _signature(game.model.session), "clearing intent does not rearrange NPCs or danger")
	for cash: int in [9, 4]:
		_money_and_gift(base, host, cash)
	_planned_before_news()
	_safety_consumer_case(base, host)
	_person_pursuit()
	_finish()


func _planned_before_news() -> void:
	var game := NewAgent.new()
	var response := _call(game, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v2"})
	response = _act_offered(game, response, "generated_route.network.echo_shore_road.a_to_b")
	response = _call(game, "set_goal", {"goal_id": "visit:generated_location.echo_terrace.terraces"})
	var selected: Dictionary = response.observation.goal_pressure.selected.duplicate(true)
	for id: String in ["generated_route.echo_terrace.commons_to_reed_craft", "generated_route.echo_terrace.reed_craft_to_commons",
		"situation:ask:generated_resident.echo_terrace.008:"]:
		response = _act_offered(game, response, id)
	var pairing: Dictionary = response.observation.goal_pressure
	_check(pairing.selected == selected and pairing.intention_before_testimony, "legal replay: intention genuinely precedes hearing the autonomous NPC's experience")
	_check(pairing.interest.promoted and pairing.why_it_matters_to_you.contains("你原本要去这里"), "legal replay: unvisited intended destination overlaps newly heard risk")
	_check(pairing.motivation_validation == "requires_play_evidence", "legal replay does not certify human motivation")
	_check(_call(game, "save", {"slot": "personal_stake_route_pending", "overwrite": true}).ok, "pending original route has isolated native save")
	var restored := _call(game, "load", {"slot": "personal_stake_route_pending"})
	_check(restored.observation.goal_pressure == pairing, "source-first route restores without retroactive intention")
	response = _act_offered(game, restored, "generated_route.echo_terrace.commons_to_terrace_farming")
	_check(response.observation.goal_pressure.goal_status == "arrived", "arrival is derived from existing own observation facts")
	_check(response.observation.goal_pressure.interest.question_status == "resolved", "route question still receives actual local answer")
	response = _act_offered(game, response, "generated_route.echo_terrace.terrace_farming_to_commons")
	_check(response.observation.goal_pressure.goal_status == "arrived" and response.observation.goal_pressure.urgency == "none", "leaving a completed trip cannot create a new return obligation")


func _money_and_gift(base: Dictionary, host: Dictionary, cash: int) -> void:
	var model := View.new()
	model.session = _prepared(_fixture(base, host, cash, 17))
	_ask(model.session)
	var worn: Array = _options(model.session, "give").filter(func(row: Dictionary) -> bool: return row.has("clear_slots"))
	_check(model.session.PlayerLife.execute(model.session, worn[0].action_id).success, "test fixture: actual gift transaction")
	_check(model.set_current_goal("replace_outerwear").success, "own missing protection is selected, not imposed")
	var data := model.build_view_data()
	var stakes: Array = data.goal_pressure.personal_stakes
	_check(stakes.any(func(s: Dictionary) -> bool: return s.stake_type == "OWNERSHIP" and s.possible_loss.contains("交出")), "formal gift causes own loss without claiming gifted item still belongs to player")
	var money: Array = stakes.filter(func(s: Dictionary) -> bool: return s.stake_type == "MONEY" and s.linked_fact == "buy:test.phase2.mantle")
	_check(money.size() == 1 and money[0].possible_loss.contains("现有%d铜币" % cash), "money stake uses actual own treasury and related price")
	_check(money[0].possible_loss.contains("付不起") == (cash < 5), "budget disclosure agrees with formal purchase availability")
	_check(stakes.all(func(s: Dictionary) -> bool: return s.stake_type != "RELATIONSHIP"), "single gift never certifies affection")
	_check(data.goal_pressure.interests.all(func(i: Dictionary) -> bool: return not i.promoted), "repairing own protection does not promote unrelated investigation or recipient storyline")
	var signature := _signature(model.session)
	model.set_current_goal("")
	_check(model.build_view_data().goal_pressure.personal_stakes.is_empty(), "prices alone are not reasons to care without a relevant goal")
	_check(signature == _signature(model.session), "stake calculations do not spend cash or change holder")
