extends "res://tests/sim/situation_continuity_test.gd"

const JourneySetup = preload("res://scripts/sim/generation/journey_content_setup.gd")
const LocalServices = preload("res://scripts/sim/player/local_services.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")


func _run() -> void:
	var agent := NewAgent.new()
	var started: Dictionary = agent.handle({"protocol": 1, "command": "start", "request_id": "phase2.start",
		"session_id": agent.session_id, "expected_revision": 0, "mode": "play", "scenario": "echo_realm",
		"seed": 81001, "economy_variant": "world_situation_v2"})
	_check(started.ok, "phase2 source world starts")
	if not started.ok:
		_finish()
		return
	var base: Dictionary = agent.model.session.fixture_source_data.duplicate(true)
	var host: Dictionary = base.entities.filter(func(e: Dictionary) -> bool:
		return e.has("guesthouse_rules") and e.states.get("settlement_id") == "generated_settlement.echo_landing")[0]
	for amount: int in [14, 9, 4]:
		_budget_case(base, host, amount)
	_budget_alternative(base, host)
	_time_case(base, host)
	_safety_consumer_case(base, host)
	_stale_lead_case(base, host)
	_wait_market_case(base, host)
	_absent_host_case(base, host)
	_finish()


func _fixture(base: Dictionary, host: Dictionary, cash: int, hour: int) -> Dictionary:
	var fixture := base.duplicate(true)
	var site := str(host.guesthouse_rules.location_id)
	fixture.location_id = site
	fixture.player.location_id = site
	fixture.world_time = {"day": 1, "hour": hour}
	_entity(fixture, str(host.id)).states.merge({"location_id": site, "daily_route_id": "", "visible": true,
		"daily_activity": "home", "hunger": "none", "fatigue": 0}, true)
	_entity(fixture, WHO).states.merge({"location_id": site, "daily_route_id": "", "visible": true,
		"daily_activity": "working", "hunger": "none", "fatigue": 0, "health": 100}, true)
	fixture.known_facts.append({"fact_id": "test_injection.phase2", "fact_type": "test_injection",
		"summary": "测试注入：控制同场、时刻、卖家库存和初始铜币；只验证真实行动消费者。"})
	for item: Dictionary in fixture.initial_items:
		if item.item_instance_id == "item_instance.journey.traveler.coins":
			fixture.economic_generation_result.initial_currency_total += cash - int(item.quantity)
			item.quantity = cash
	fixture.initial_items.append({"item_instance_id": "test.phase2.mantle", "item_def_id": "item.light_reed_mantle",
		"quantity": 1, "holder": {"kind": "entity", "id": host.id}})
	fixture.initial_items.append({"item_instance_id": "test.phase2.roots", "item_def_id": "item.root_vegetable_portion",
		"quantity": 6, "holder": {"kind": "entity", "id": host.id}})
	fixture.journey_generated.signature = JourneySetup._signature(fixture)
	return fixture


func _budget_case(base: Dictionary, host: Dictionary, cash: int) -> void:
	var session: Variant = _prepared(_fixture(base, host, cash, 17))
	if not session.initialized:
		return
	_check(Treasury.new(_snapshot(session)).balance("player") == cash, "controlled %d-coin initial state" % cash)
	_ask(session)
	var worn: Array = _options(session, "give").filter(func(row: Dictionary) -> bool: return row.has("clear_slots"))
	_check(not worn.is_empty(), "%d coins: worn protection can be given" % cash)
	if worn.is_empty():
		return
	var gift: Dictionary = session.PlayerLife.execute(session, worn[0].action_id)
	_check(gift.success and not session.stores.equipment_store.get_loadout("player").slots.values().has(worn[0].item_id),
		"%d coins: real gift removes player's protection" % cash)
	_followup("gift_worn_armor", ["player.body_outer=empty", "owner.cloak=recipient"],
		["unprotected until a replacement is equipped"], [], ["replacement purchase remains possible"], "ownership", 0)
	var buys: Array = _by_id(session, "buy:test.phase2.mantle")
	_check(not buys.is_empty(), "%d coins: replacement is an actual merchant offer" % cash)
	if buys.is_empty():
		return
	if buys[0].can_execute:
		var bought: Dictionary = session.PlayerLife.execute(session, buys[0].action_id)
		_check(bought.success, "%d coins: replacement purchase commits" % cash)
		_check(session.stores.item_store.get_item("test.phase2.mantle").holder.id == "player", "replacement changes real ownership")
		_followup("buy_replacement", ["coins=%d" % Treasury.new(_snapshot(session)).balance("player"), "owner.mantle=player"],
			["cannot pay for both food and bed"] if cash == 9 else [], ["equip replacement"],
			["food purchase", "bed"], "budget", 0)
	else:
		_check(cash < 5, "%d coins: unaffordable replacement is blocked" % cash)
	var roots: Array = _by_id(session, "buy:test.phase2.roots")
	_check(roots.size() == 1 and roots[0].can_execute, "%d coins: finite two-coin food is initially affordable" % cash)
	if roots.is_empty() or not roots[0].can_execute:
		return
	_check(session.PlayerLife.execute(session, roots[0].action_id).success, "%d coins: legal food purchase" % cash)
	var remaining := Treasury.new(_snapshot(session)).balance("player")
	_check(remaining == cash - (5 if cash >= 5 else 0) - 2, "%d coins: spent coins are conserved" % cash)
	var bed: Dictionary = _service(session, "service:bed")
	_check(bed.can_execute == (cash == 14), "%d coins: bed eligibility follows real remaining coins" % cash)
	if cash == 14:
		_check(session.PlayerLife.execute(session, bed.action_id).success, "rich branch buys all three")
		_check(Treasury.new(_snapshot(session)).balance("player") == 4, "rich branch has four coins after three payments")
	else:
		_check(not session.PlayerLife.execute(session, bed.action_id).success, "%d coins: unaffordable bed cannot be forced" % cash)
		_followup("buy_food_after_gift", ["coins=%d" % remaining], ["bed blocked: need 3 coins"],
			[], ["free outdoor rest remains possible"], "budget", 0)
	_check(session.save_to_path("user://tests/situations/phase2_budget_%d.json" % cash).ok,
		"%d-coin branch persists natively" % cash)
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/situations/phase2_budget_%d.json" % cash).success,
		"%d-coin branch restores natively" % cash)


func _budget_alternative(base: Dictionary, host: Dictionary) -> void:
	var session: Variant = _prepared(_fixture(base, host, 9, 17))
	_ask(session)
	var worn: Array = _options(session, "give").filter(func(row: Dictionary) -> bool: return row.has("clear_slots"))
	_check(session.PlayerLife.execute(session, worn[0].action_id).success, "medium branch repeats same sacrifice")
	_check(session.PlayerLife.execute(session, "buy:test.phase2.mantle").success, "medium branch buys replacement")
	_check(session.PlayerLife.execute(session, "service:bed").success, "medium branch can choose bed before food")
	var roots: Array = _by_id(session, "buy:test.phase2.roots")
	_check(roots.is_empty() or not roots[0].can_execute, "bed-first medium branch loses the food purchase instead")
	_check(Treasury.new(_snapshot(session)).balance("player") == 1, "bed-first medium branch keeps one coin")


func _by_id(session: Variant, id: String) -> Array:
	return session.PlayerLife.options(session).filter(func(row: Dictionary) -> bool: return row.action_id == id)


func _service(session: Variant, id: String) -> Dictionary:
	return LocalServices.options(session).filter(func(row: Dictionary) -> bool: return row.action_id == id)[0]


func _followup(id: String, changes: Array, constraints: Array, opportunities: Array, affordances: Array,
		semantic: String, minutes: int) -> void:
	print("choice_followup_problem ", JSON.stringify({"choice_id": id, "state_changes": changes,
		"new_constraints": constraints, "new_opportunities": opportunities,
		"new_affordances": affordances, "time_to_next_meaningful_choice": minutes,
		"followup_semantic_type": semantic, "evidence_scope": "test_injection"}))


func _time_case(base: Dictionary, host: Dictionary) -> void:
	var session: Variant = _session(_fixture(base, host, 14, 23))
	if not session.initialized:
		return
	_check(_service(session, "service:bed").can_execute and _service(session, "service:drink").can_execute,
		"at 23:00 both bed and tavern are initially legal")
	_check(session.PlayerLife.execute(session, "service:bed").success, "late bed commits through legal service")
	_check(not _service(session, "service:drink").can_execute and _service(session, "service:drink").blocked_reason.contains("午夜"),
		"sleeping first crosses real opening-hours threshold and loses tavern access")
	_followup("bed_before_tavern", ["world_time=day2.03", "coins=11"], ["tavern closed until 17:00"],
		[], ["bed remains open", "leave or wait"], "time", 0)
	var alternative: Variant = _session(_fixture(base, host, 14, 23))
	_check(alternative.PlayerLife.execute(alternative, "service:drink").success, "alternative order: drink first")
	_check(Treasury.new(_snapshot(alternative)).balance("player") == 12, "drink first spends two real coins")
	_check(_service(alternative, "service:bed").can_execute, "after drink, bed remains legal after midnight")
	_check(alternative.PlayerLife.execute(alternative, "service:bed").success, "drink-first branch can still sleep")
	_check(Treasury.new(_snapshot(alternative)).balance("player") == 9, "drink-first branch pays both services")


func _safety_consumer_case(base: Dictionary, host: Dictionary) -> void:
	var session: Variant = _prepared(_fixture(base, host, 14, 17))
	_ask(session)
	var threat: Dictionary = _snapshot(session).get_entity("world_threat.field_boar")
	var combat := Danger.Combat.new()
	combat.configure(session.registry)
	var guarded: Dictionary = combat.preview(Danger.new().definition(_snapshot(session), "player", threat,
		session.fixture_source_data.world_danger), _snapshot(session), "guard", "player")
	var worn: Array = _options(session, "give").filter(func(row: Dictionary) -> bool: return row.has("clear_slots"))
	_check(session.PlayerLife.execute(session, worn[0].action_id).success, "safety case gifts actual worn armor")
	var bare: Dictionary = combat.preview(Danger.new().definition(_snapshot(session), "player", threat,
		session.fixture_source_data.world_danger), _snapshot(session), "guard", "player")
	_check(int(guarded.effective_score) == int(bare.effective_score) + 2,
		"same hypothetical encounter loses two guard score after real gift; freezing passive is not claimed")


func _stale_lead_case(base: Dictionary, host: Dictionary) -> void:
	var session: Variant = _prepared(_fixture(base, host, 14, 10))
	_ask(session)
	var leads_before: Array = Continuity.leads(session, _snapshot(session))
	_check(not leads_before.is_empty(), "first-hand testimony creates a route to check")
	if leads_before.is_empty():
		return
	var lead: Dictionary = leads_before[0]
	var target := str(lead.location_id)
	var arrival := Result.new()
	arrival.add_fact({"fact_id": "test.phase2.checked_destination", "fact_type": "actor_arrived", "actor_id": "player",
		"location_id": target, "route_id": "test_injection.route", "day": 1, "hour": 11,
		"summary": "测试注入：早先亲自到过线索地点。"})
	arrival.mark_resolved("test_injection")
	_check(session.writer.apply_result(arrival, session.stores), "test injection: recorded first-hand visit")
	_check(not Continuity.leads(session, _snapshot(session)).any(func(row: Dictionary) -> bool:
		return row.get("location_id") == target and row.get("source_fact_id") == lead.source_fact_id),
		"checked and unchanged lead does not return as main pursuit")
	_check(session.save_to_path("user://tests/situations/phase2_checked_lead.json").ok, "checked lead persists")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/situations/phase2_checked_lead.json").success, "checked lead reloads")
	_check(not Continuity.leads(restored, _snapshot(restored)).any(func(row: Dictionary) -> bool:
		return row.get("location_id") == target and row.get("source_fact_id") == lead.source_fact_id),
		"old lead stays suppressed after native reload")
	# A newer first-hand conversation about the same place must reopen it.
	restored.current_hour = 12
	var newer := Result.new()
	newer.add_fact({"fact_id": "test.phase2.new_tip", "fact_type": "situation_inquiry", "actor_id": "player",
		"subject_id": lead.subject_id, "location_id": str(host.guesthouse_rules.location_id),
		"day": 1, "hour": 12, "stated_destination_id": target if lead.kind != "danger" else "",
		"danger_location_id": target if lead.kind == "danger" else "",
		"summary": "测试注入：亲自复核之后收到更新的当面消息。"})
	newer.mark_resolved("test_injection")
	_check(restored.writer.apply_result(newer, restored.stores), "test injection: new first-hand tip after visit")
	_check(Continuity.leads(restored, _snapshot(restored)).any(func(row: Dictionary) -> bool:
		return row.get("location_id") == target and row.get("source_fact_id") == "test.phase2.new_tip"),
		"newer testified lead reopens the route without remote omniscience")


func _wait_market_case(base: Dictionary, host: Dictionary) -> void:
	var session: Variant = _session(_fixture(base, host, 14, 10))
	var before := Actions.visible_signature(session)
	var addition := Result.new()
	addition.add_fact({"fact_id": "test.phase2.new_stock_fact", "fact_type": "test_injection",
		"summary": "测试注入：卖家获得新的有限现货。"})
	addition.add_item_change({"operation": "create", "item": {"item_instance_id": "test.phase2.new_stock",
		"item_def_id": "item.light_reed_mantle", "quantity": 1,
		"holder": {"kind": "entity", "id": host.id}}, "source_fact_ids": ["test.phase2.new_stock_fact"]})
	addition.mark_resolved("test_injection")
	_check(session.writer.apply_result(addition, session.stores), "test injection: merchant acquires finite new stock")
	_check(Actions.visible_signature(session) != before, "wait signature notices new legal stock without a new person")


func _absent_host_case(base: Dictionary, host: Dictionary) -> void:
	var session: Variant = _session(_fixture(base, host, 14, 18))
	var moved := Result.new()
	moved.add_state_change({"entity_id": host.id, "key": "location_id", "to": "generated_location.echo_landing.commons"})
	moved.mark_resolved("test_injection")
	_check(session.writer.apply_result(moved, session.stores), "test injection: innkeeper is absent but a witness remains")
	var questions: Array = session.PlayerLife.options(session).filter(func(row: Dictionary) -> bool:
		return row.get("intent") == "whereabouts" and row.get("wanted_id") == host.id and row.get("subject_id") == WHO)
	_check(questions.size() == 1, "absent innkeeper can be asked about without prior acquaintance")
	if questions.is_empty():
		return
	var answer: Dictionary = session.PlayerLife.execute(session, questions[0].action_id)
	_check(answer.success and (str(answer.player_life_feedback.body).contains("没有见到")
		or str(answer.player_life_feedback.body).contains("小时前")), "witness either dates a sighting or says they do not know")
	_check(session.PlayerLife.options(session).filter(func(row: Dictionary) -> bool:
		return row.get("intent") == "whereabouts" and row.get("wanted_id") == host.id and row.get("subject_id") == WHO).is_empty(),
		"same empty host inquiry is not immediately repeated")
	session.current_day = 2
	session.current_hour = 1
	_check(session.PlayerLife.options(session).filter(func(row: Dictionary) -> bool:
		return row.get("intent") == "whereabouts" and row.get("wanted_id") == host.id and row.get("subject_id") == WHO).is_empty(),
		"unchanged witness does not reopen the same host question after six hours")
