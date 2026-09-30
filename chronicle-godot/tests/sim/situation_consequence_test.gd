extends "res://tests/sim/situation_interaction_test.gd"

const Opportunities = preload("res://scripts/sim/economy/resident_work_opportunities.gd")
const Daily = preload("res://scripts/sim/npc/resident_daily_life_system.gd")


func _run() -> void:
	var agent := NewAgent.new()
	var start: Dictionary = agent.handle({"protocol": 1, "command": "start", "request_id": "start", "session_id": agent.session_id,
		"expected_revision": 0, "mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v1"})
	_check(start.ok, "consequence prototype starts")
	var base: Dictionary = agent.model.session.fixture_source_data.duplicate(true)
	base.location_id = SITE
	base.player.location_id = SITE
	base.world_time = {"day": 1, "hour": 10}
	_entity(base, WHO).states.merge({"location_id": SITE, "daily_route_id": "", "visible": true,
		"daily_activity": "home", "fatigue": 0, "hunger": "none", "health": 100}, true)
	base.known_facts.append({"fact_id": "test_injection.situation", "fact_type": "test_injection",
		"summary": "测试注入：配对初态、位置和骰点；合法行动与共同结算的反例，不是自然游玩。"})
	base.initial_items.append({"item_instance_id": "test.spare", "item_def_id": "item.woven_reed_vest", "quantity": 1,
		"holder": {"kind": "entity", "id": "player"}})
	_gift_consequence(base)
	_funding_purchase(base)
	_waiting_case(base)
	_finish()


func _gift_consequence(base: Dictionary) -> void:
	var bare: Variant = _prepared(base)
	var helped: Variant = _prepared(base)
	_ask(bare)
	_ask(helped)
	_check(helped.PlayerLife.execute(helped, _options(helped, "give")[0].action_id).success, "legal gift in one branch")
	_check(Actions.wait_here(bare, 10).success, "no-help branch spends the same ten minutes")
	for session: Variant in [bare, helped]:
		var snap: Variant = _snapshot(session)
		_check(session.writer.apply_result(Intent.Gear.equip(snap, snap.get_entity(WHO), session.get_time_summary()), session.stores), "same autonomous equipment consumer")
	_check(bare.get_time_summary() == helped.get_time_summary(), "paired clocks aligned")
	var before := _danger_choice(bare)
	var after := _danger_choice(helped)
	_check(after.score > before.score, "gift is read by later risk evaluation, not only remembered")
	_check(after.source_fact_ids.any(func(id: String) -> bool:
		return helped.stores.fact_store.get_fact(id).get("source_fact_ids", []).any(func(source: String) -> bool: return source.begins_with("fact.situation."))), "later decision traces equip then actual gift source")
	for session: Variant in [bare, helped]:
		var needs := Result.new()
		for key: String in ["temperament", "hunger", "fatigue"]:
			needs.add_state_change({"entity_id": WHO, "key": key, "to": {"temperament": "steady", "hunger": "extreme", "fatigue": 0}[key]})
		needs.mark_resolved("test_injection")
		_check(session.writer.apply_result(needs, session.stores), "test injection: same competing hunger and safety needs")
	var unprotected_choice := _danger_choice(bare, true)
	var protected_choice := _danger_choice(helped, true)
	_check(unprotected_choice.kind == "home" and protected_choice.kind == "work", "same competing intentions: actual equipment changes chosen action")
	var trust := Result.new()
	trust.add_relationship_change({"source_id": WHO, "target_id": "player", "axis": "trust", "delta": 40})
	trust.mark_resolved("test_injection")
	_check(helped.writer.apply_result(trust, helped.stores), "test injection: trusted advice")
	_check(helped.PlayerLife.execute(helped, _options(helped, "caution")[0].action_id).success, "legal warning, no forced obedience")
	_check(_danger_choice(helped).score < protected_choice.score and _danger_choice(helped, true).kind == "home", "trusted advice changes the competing chosen action without forced obedience")
	# Match bodies, position and roll to isolate the actual gifted armor in the shared danger resolver.
	var previews: Array = []
	for session: Variant in [bare, helped]:
		var move := Result.new()
		var enemy: Dictionary = _snapshot(session).get_entity("world_threat.field_boar")
		for key: String in ["location_id", "daily_route_id", "health", "dexterity", "constitution", "perception"]:
			move.add_state_change({"entity_id": WHO, "key": key, "to": {"location_id": enemy.territory_id, "daily_route_id": "", "health": 100,
				"dexterity": 6, "constitution": 6, "perception": 6}[key]})
		move.mark_resolved("test_injection")
		_check(session.writer.apply_result(move, session.stores), "test injection: matched encounter bodies")
		var snap: Variant = _snapshot(session)
		var resolver := Danger.Combat.new()
		resolver.configure(session.registry)
		previews.append(resolver.preview(Danger.new().definition(snap, WHO, snap.get_entity(enemy.id), base.world_danger), snap, "guard", WHO))
	_check(previews[1].effective_score - previews[0].effective_score == 2, "gifted armor changes shared defense score by its real modifier")
	var roll := clampi(int(previews[0].difficulty) - int(previews[0].effective_score) - 1, 1, 6)
	var outcomes: Array = []
	for session: Variant in [bare, helped]:
		var snap: Variant = _snapshot(session)
		var resolved: Variant = Danger.new().resolve_round(snap, WHO, snap.get_entity("world_threat.field_boar"), "guard", roll, session.get_time_summary(), base.world_danger, session.registry)
		_check(session.writer.apply_result(resolved, session.stores), "same-roll shared combat transaction")
		outcomes.append(resolved.narrative_result.outcome)
	_check(outcomes[0] != outcomes[1], "same-roll danger outcome differs because of legal gift")
	_check(helped.save_to_path("user://tests/situations/consequence.json").ok, "post-consequence native save")
	var loaded := Session.new()
	_check(loaded.load_from_path("user://tests/situations/consequence.json").get("success", false), "post-consequence save restores")
	print("SITUATION_PAIRED ", JSON.stringify({"scores": [before.score, after.score], "defense": previews.map(func(p: Dictionary) -> int: return p.effective_score), "roll": roll, "outcomes": outcomes}))


func _danger_choice(session: Variant, alternative: bool = false) -> Dictionary:
	var snap: Variant = _snapshot(session)
	var target: Dictionary = snap.get_entity("world_threat.field_boar")
	var rows: Array = []
	Choice.propose(rows, "work", target.territory_id, "working", "测试注入：比较同一候选行动")
	if alternative:
		Choice.propose(rows, "home", SITE, "home", "测试注入：留在安全处")
	var config: Dictionary = Choice.PROFILE.duplicate(true)
	config.merge({"danger_hour": Intent.now(session.get_time_summary()), "situation_version": 1})
	return Choice.choose(rows, snap.get_entity(WHO), session.travel_routes, Daily.new(), snap, [], session.registry, config, {})


func _funding_purchase(base: Dictionary) -> void:
	var seller := "generated_resident.echo_landing.001"
	var fixture := base.duplicate(true)
	_entity(fixture, WHO).states.merge({"daily_activity": "seeking_work", "daily_intent_id": "work_supply:equipment:body_outer"}, true)
	_entity(fixture, seller).states.merge({"location_id": SITE, "daily_route_id": "", "daily_activity": "home"}, true)
	fixture.initial_items.append({"item_instance_id": "test.sale_stock", "item_def_id": "item.woven_reed_vest", "quantity": 1,
		"holder": {"kind": "entity", "id": seller}})
	var session: Variant = _prepared(fixture)
	var move := Result.new()
	for item: Dictionary in session.stores.item_store.list_items_for_owner(WHO):
		if item.item_def_id == Intent.Food.CURRENCY:
			move.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id, "expected_holder": item.holder,
				"new_holder": {"kind": "entity", "id": seller}, "source_fact_ids": ["test_injection.situation"]})
	move.mark_resolved("test_injection")
	_check(session.writer.apply_result(move, session.stores), "test injection: recipient starts without cash")
	_ask(session)
	var snap: Variant = _snapshot(session)
	var rejected := Opportunities.plan_purchase(snap, snap.get_entity(WHO), [], session.stores, session.get_time_summary())
	_check(rejected.get("event", {}).get("reason") == "unaffordable", "without help actual purchase is unaffordable")
	# Two finite gifts may be needed: funding is not a magical buy-equipment command.
	for index: int in range(2):
		var funds := _options(session, "fund")
		if not funds.is_empty():
			_check(session.PlayerLife.execute(session, funds[0].action_id).success, "legal cash transfer")
	snap = _snapshot(session)
	var purchase := Opportunities.plan_purchase(snap, snap.get_entity(WHO), [], session.stores, session.get_time_summary())
	_check(purchase.get("event", {}).get("fact_type") == "work_supply_purchased", "changed cash makes the ordinary NPC purchase feasible")
	if purchase.get("event", {}).get("fact_type") == "work_supply_purchased":
		_check(session.writer.apply_result(purchase.transaction, session.stores), "NPC pays actual seller using shared market")
		_check(session.stores.item_store.get_item("test.sale_stock").holder.id == WHO, "funded purchase transfers actual stock")


func _waiting_case(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	var places: Array = fixture.locations.values().filter(func(p: Dictionary) -> bool: return p.has("journey_host_id"))
	var place: Dictionary = places[0]
	var site := str(place.location_id if place.has("location_id") else fixture.locations.find_key(place))
	fixture.location_id = site
	fixture.player.location_id = site
	fixture.world_time = {"day": 1, "hour": 16}
	var host := str(place.journey_host_id)
	_entity(fixture, host).states.merge({"location_id": site, "daily_route_id": "", "daily_activity": "home", "hunger": "none"}, true)
	var session: Variant = _session(fixture)
	var remainder := Result.new()
	remainder.add_state_change({"entity_id": "player", "key": "player_action_minutes", "to": 50})
	remainder.mark_resolved("test_injection")
	_check(session.writer.apply_result(remainder, session.stores), "test injection: 16:50 at guesthouse")
	var closed: Array = session.PlayerLife.Services.options(session)
	_check(not closed[0].can_execute, "bed closed before 17")
	var waited := Actions.wait_here(session, 60)
	_check(waited.success and waited.minutes == 10 and waited.wait_interrupted, "opening or visible movement interrupts a one-hour wait at 17")
	_check(session.get_time_summary().hour == 17 and session.get_time_summary().minute == 0 and session.context.location_id == site, "waiting advances time in place, no walking round-trip")
	var services: Array = session.PlayerLife.Services.options(session)
	_check(services[0].can_execute, "present host can receive payment at opening")
