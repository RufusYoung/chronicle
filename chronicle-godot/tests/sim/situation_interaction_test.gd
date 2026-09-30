extends "res://tests/sim/world_danger_contract_test.gd"

const NewAgent = preload("res://scripts/agent/agent_game_session.gd")
const Intent = preload("res://scripts/sim/situation/equipment_intents.gd")
const Actions = preload("res://scripts/sim/situation/situation_actions.gd")
const Choice = preload("res://scripts/sim/npc/resident_activity_choice.gd")
const WHO := "generated_resident.echo_landing.002"
const SITE := "generated_location.echo_landing.work_shed"


func _run() -> void:
	var agent := NewAgent.new()
	var response: Dictionary = agent.handle({"protocol": 1, "command": "start", "request_id": "start", "session_id": agent.session_id,
		"expected_revision": 0, "mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v1"})
	_check(response.ok, "prototype starts")
	var base: Dictionary = agent.model.session.fixture_source_data.duplicate(true)
	base.location_id = SITE
	base.player.location_id = SITE
	base.world_time = {"day": 1, "hour": 10}
	_entity(base, WHO).states.merge({"location_id": SITE, "daily_route_id": "", "visible": true,
		"daily_activity": "working", "fatigue": 0, "hunger": "none", "health": 100}, true)
	base.known_facts.append({"fact_id": "test_injection.situation", "fact_type": "test_injection",
		"summary": "测试注入：到场、物品和先前遇险用于机制反例；不是自然世界或真人试玩证据。"})
	base.initial_items.append({"item_instance_id": "test.spare", "item_def_id": "item.woven_reed_vest", "quantity": 1,
		"holder": {"kind": "entity", "id": "player"}})
	var session: Variant = _prepared(base)
	_check(not _options(session, "give").size(), "unspoken private demand does not expose giving action")
	_ask(session)
	_check(not _options(session, "give").is_empty(), "testimony plus own spare gear enables a gift")
	_check(not _options(session, "sell").is_empty(), "real buyer budget and actual gear enable a sale")
	_check(not _options(session, "fund").is_empty(), "own cash enables funding, not a fictional loan")
	var gifted: Dictionary = session.PlayerLife.execute(session, _options(session, "give")[0].action_id)
	_check(gifted.success, "gift commits: " + str(gifted.get("error", "")))
	_check(session.stores.item_store.get_item("test.spare").holder.id == WHO, "same physical item changes ownership")
	_check(_options(session, "give").is_empty(), "used option disappears without a completion flag")
	_check(not _snapshot(session).get_memories(WHO).filter(func(m: Dictionary) -> bool: return m.memory_type == "equipment_help").is_empty(), "recipient remembers actual help")
	var advanced: Dictionary = session.advance_time(1, "test_post_gift")
	_check(advanced.success, "world continues after gift")
	_check(_snapshot(session).get_equipment_loadout(WHO).slots.get("slot.body_outer") == "test.spare", "NPC independently wears gift on the next tick")
	_check(session.save_to_path("user://tests/situations/gift.json").ok, "native gift save")
	var restored := Session.new()
	var load_result: Dictionary = restored.load_from_path("user://tests/situations/gift.json")
	_check(load_result.get("success", false), "versioned prototype loads: " + str(load_result))
	if restored.initialized:
		session.advance_time(2, "same_continuation")
		restored.advance_time(2, "same_continuation")
		_check(_signature(session) == _signature(restored), "native ownership, memories, traces, clock and RNG continue identically")
	_sale_case(base)
	_repair_case(base)
	_privacy_and_capability_cases(base)
	_autonomous_help(base)
	_finish()


func _prepared(fixture: Dictionary) -> Variant:
	var session: Variant = _session(fixture)
	var remembered := Result.new()
	var threat: Dictionary = _snapshot(session).get_entity("world_threat.field_boar")
	var fact: Dictionary = Danger._fact("world_danger_contact", WHO, {"day": 1, "hour": 8}, threat, "测试注入：早先亲见危险")
	remembered.add_fact(fact)
	Danger._remember(remembered, WHO, threat, {"day": 1, "hour": 8}, fixture.world_danger, fact.fact_id)
	_check(session.writer.apply_result(remembered, session.stores), "test injection: prior witnessed danger")
	return session


func _options(session: Variant, intent: String) -> Array:
	return session.PlayerLife.options(session).filter(func(row: Dictionary) -> bool:
		return row.get("intent") == intent and row.get("subject_id") == WHO)


func _ask(session: Variant) -> void:
	var asks := _options(session, "ask")
	_check(not asks.is_empty(), "local person can be asked")
	if not asks.is_empty():
		var result: Dictionary = session.PlayerLife.execute(session, asks[0].action_id)
		_check(result.success, "inquiry uses legal execution")
		_check(result.get("player_life_feedback", {}).get("body", "").contains("护具"), "feedback contains the specific need, not 'you learned key information'")
		_check(_options(session, "ask").is_empty(), "unchanged inquiry is suppressed")


func _sale_case(base: Dictionary) -> void:
	var session: Variant = _prepared(base)
	_ask(session)
	var snapshot: Variant = _snapshot(session)
	var before_player := Intent.Food.balance(snapshot.get_items_for_holder("player"), "player")
	var before_buyer := Intent.Food.balance(snapshot.get_items_for_holder(WHO), WHO)
	var sale: Dictionary = _options(session, "sell")[0]
	var sold: Dictionary = session.PlayerLife.execute(session, sale.action_id)
	_check(sold.success, "sale is an ordinary conserved market transaction: " + str(sold.get("error", "")))
	snapshot = _snapshot(session)
	_check(Intent.Food.balance(snapshot.get_items_for_holder("player"), "player") == before_player + int(sale.price)
		and Intent.Food.balance(snapshot.get_items_for_holder(WHO), WHO) == before_buyer - int(sale.price), "seller gain equals buyer payment")
	_check(snapshot.get_item("test.spare").holder.id == WHO, "sale delivers actual armor")
	_check(not session.PlayerLife.execute(session, sale.action_id).success, "stale repeated sale is rejected")


func _repair_case(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	fixture.initial_items.append({"item_instance_id": "test.worn", "item_def_id": "item.woven_reed_vest", "quantity": 1,
		"holder": {"kind": "entity", "id": WHO}, "condition": {"durability": 3, "maximum_durability": 16}})
	fixture.initial_equipment_loadouts.append({"entity_id": WHO, "slots": {"body_outer": "test.worn"}})
	var session: Variant = _prepared(fixture)
	var repairs := _options(session, "repair")
	_check(not repairs.is_empty(), "visibly worn gear with shared recipe and real materials offers repair")
	if repairs.is_empty():
		return
	var repair: Dictionary = repairs[0]
	var stock := str(repair.profile.resource_inputs[0].stock_id)
	var before := float(_snapshot(session).get_resource_stock(stock).current)
	var done: Dictionary = session.PlayerLife.execute(session, repair.action_id)
	_check(done.success and done.get("work_completed", false), "two-hour repair completes while owner stays: " + str(done))
	_check(session.stores.item_store.get_item("test.worn").condition.durability == 7, "repair restores four actual durability")
	_check(float(_snapshot(session).get_resource_stock(stock).current) < before, "repair spends finite raw material")
	_check(session.stores.item_store.get_item("test.worn").holder.id == WHO, "repair does not steal the item")
	_check(_options(session, "repair").is_empty(), "repaired condition removes repeated repair")


func _privacy_and_capability_cases(base: Dictionary) -> void:
	var bare := base.duplicate(true)
	bare.initial_items = bare.initial_items.filter(func(i: Dictionary) -> bool:
		return i.item_instance_id != "test.spare")
	var session: Variant = _prepared(bare)
	var poor := Result.new()
	for item: Dictionary in session.stores.item_store.list_items_for_owner("player"):
		if item.item_def_id == Intent.Food.CURRENCY:
			poor.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id, "expected_holder": item.holder,
				"new_holder": {"kind": "entity", "id": WHO}, "source_fact_ids": ["test_injection.situation"]})
	poor.mark_resolved("test_injection")
	_check(session.writer.apply_result(poor, session.stores), "test injection: conserved player cash removal")
	_ask(session)
	_check(_options(session, "give").is_empty() and _options(session, "sell").is_empty() and _options(session, "fund").is_empty(), "same need, different player resources: no impossible generosity or sale")
	_check(not _options(session, "caution").is_empty(), "cash-poor player can still advise or leave")
	var advice: Dictionary = session.PlayerLife.execute(session, _options(session, "caution")[0].action_id)
	_check(advice.success and _options(session, "caution").is_empty(), "advice is recorded once, without promising obedience")
	var remote := base.duplicate(true)
	_entity(remote, WHO).states.location_id = "generated_location.echo_terrace.work_shed"
	var absent: Variant = _prepared(remote)
	_check(absent.Situations.build(absent).all(func(row: Dictionary) -> bool: return row.subject_id != WHO), "remote goal, injury and inventory cannot leak into local situation")
	_check(_options(absent, "repair").is_empty() and _options(absent, "ask").is_empty(), "absent person cannot be spoken to or repaired")
	var corrupt := base.duplicate(true)
	corrupt.situation_rules.version = 99
	_check(not Session.new().start_from_fixture_data(corrupt, []).success, "unknown situation rules are rejected")


func _autonomous_help(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	var giver := "generated_resident.echo_landing.001"
	_entity(fixture, giver).states.merge({"location_id": SITE, "daily_route_id": "", "daily_activity": "home", "hunger": "none"}, true)
	for item: Dictionary in fixture.initial_items:
		if item.item_instance_id == "test.spare":
			item.holder.id = giver
	var session: Variant = _prepared(fixture)
	var trust := Result.new()
	trust.add_relationship_change({"source_id": giver, "target_id": WHO, "axis": "trust", "delta": 40})
	trust.mark_resolved("test_injection")
	_check(session.writer.apply_result(trust, session.stores), "test injection: established friendship")
	var snapshot: Variant = _snapshot(session)
	_check(session.writer.apply_result(Intent.requests(snapshot, session.get_time_summary(), session.context.locations), session.stores), "world-origin request without a player action")
	snapshot = _snapshot(session)
	var support: Variant = Intent.assistance(snapshot, snapshot.get_entity(giver), session.get_time_summary())
	_check(not support.is_empty() and session.writer.apply_result(support, session.stores), "friend can give real spare equipment without player intervention")
	_check(session.stores.item_store.get_item("test.spare").holder.id == WHO, "autonomous help uses same item ownership contract")
	snapshot = _snapshot(session)
	_check(Intent.assistance(snapshot, snapshot.get_entity(giver), session.get_time_summary()).is_empty(), "friend does not repeat assistance infinitely")
