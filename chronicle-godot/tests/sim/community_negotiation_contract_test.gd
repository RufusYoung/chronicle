extends "res://tests/sim/community_assistance_contract_test.gd"

const IntegrationOptions = preload("res://tests/sim/world_integration_contract_test.gd")


func _run() -> void:
	var live := Live.new()
	_check(live.start(IntegrationOptions.options()).success, "negotiation world starts")
	if not live.is_ready():
		_finish()
		return
	var fixture: Dictionary = live.session.fixture_source_data.duplicate(true)
	fixture.world_time = {"day": 3, "hour": 10}
	var donor := "generated_resident.echo_landing.001"
	var receiver := "generated_resident.echo_terrace.001"
	var site := str(_entity(fixture, donor).states.workplace_id)
	_entity(fixture, donor).states.merge({"location_id": site, "daily_activity": "socializing", "daily_route_id": "", "hunger": "high"}, true)
	_entity(fixture, receiver).states.hunger = "high"
	fixture.initial_items.append({"item_instance_id": "test.negotiation.food", "item_def_id": "item.fresh_fish_portion", "quantity": 20, "holder": {"kind": "entity", "id": Storage.depot_id(donor)}})
	fixture.known_facts.append({"fact_id": "test_injection.negotiation", "fact_type": "test_injection", "summary": "测试注入：控制到场、余粮和时点，验证拒绝后消息往返；不是自然世界证据。"})
	var session: Variant = _session(fixture)
	if not session.initialized:
		_finish()
		return
	var tick := {"day": 3, "hour": 8}
	var config: Dictionary = fixture.community_rules.duplicate(true)
	config.conversation_retry_hours = 1
	var budget: Dictionary = fixture.resident_daily_life.food_access.household_budget
	_check(session.writer.apply_results(Budget.new().observe(_snapshot(session), tick, budget).results, session.stores), "firsthand household demand")
	_check(session.writer.apply_results(CommunityLife.new().observe(_snapshot(session), tick, config, budget).results, session.stores), "request has physical pantry source")
	_place(session, receiver, site, "socializing")
	_check(session.writer.apply_results(CommunityLife.new().converse(_snapshot(session), tick, config).results, session.stores), "initial request physically heard")
	_check(session.writer.apply_results(Community.new().resolve_tick(_snapshot(session), tick, config).results, session.stores), "own local needs establish reserve policy")
	var requests := Assistance.requests(_snapshot(session), _snapshot(session).get_entity(donor), tick, config, budget)
	_check(requests.size() == 1 and requests[0].community_withheld, "reserve policy refuses original amount")
	if requests.is_empty():
		_finish()
		return
	var router := Daily.new()
	var routes: Array = router._routes(_snapshot(session), session.settlement_network_runtime, session.context.locations, session.world_tick_adapter.daily_life_routes, fixture.resident_daily_life)
	var route_finder := func(a: String, b: String) -> Dictionary: return router._next_edge(routes, a, b)
	var hauling: Dictionary = fixture.resident_daily_life.food_access.hauling.duplicate(true)
	hauling.fee = 0
	requests[0]["self_delivery"] = true
	var refused := _order(session, donor, requests[0], tick, hauling, route_finder)
	_check(refused.has("transaction") and session.writer.apply_result(refused.transaction, session.stores), "refusal is recorded without goods movement")
	tick.hour = 9
	_check(session.writer.apply_results(CommunityLife.new().observe(_snapshot(session), tick, config, budget).results, session.stores), "donor forms bounded counteroffer from own refusal")
	var replies: Array = _snapshot(session).get_facts_by_actor(donor).filter(func(f: Dictionary) -> bool: return f.get("topic") == "aid_reply")
	_check(replies.size() == 1 and replies[0].payload.maximum_portions == 2, "one refusal creates one conditional two-portion reply")
	_check(not Knowledge.latest(_snapshot(session), receiver, Knowledge.hour(tick)).has("aid_reply:" + donor), "reply is not telepathically received")
	var ordinary: Variant = _snapshot(session)
	ordinary.entities = ordinary.entities.duplicate(true)
	for entity: Dictionary in ordinary.entities:
		if "local_cooperation" in entity.get("tags", []) and entity.get("representative_id") == donor:
			entity.representative_id = "generated_resident.echo_landing.006"
	var visits := CommunityLife.proposals(ordinary, ordinary.get_entity(donor), tick, config, session.settlement_network_runtime)
	_check(visits.any(func(row: Dictionary) -> bool:
		return row.goal == replies[0].payload.meeting_location_id and replies[0].fact_id in row.source_fact_ids),
		"ordinary nonrepresentative can choose to convey own reply without waiting for loneliness")
	_place(session, donor, site, "socializing")
	_place(session, receiver, site, "socializing")
	_check(session.writer.apply_results(CommunityLife.new().converse(_snapshot(session), tick, config).results, session.stores), "reply crosses actual second conversation")
	tick.hour = 10
	_check(session.writer.apply_results(CommunityLife.new().observe(_snapshot(session), tick, config, budget).results, session.stores), "requester revises still-unmet need")
	var counter: Dictionary = Knowledge.latest(_snapshot(session), receiver, Knowledge.hour(tick)).get("need:" + receiver, {})
	_check(counter.get("payload", {}).get("delivery_request", {}).get("quantity") == 2, "heard reply bounds counterproposal")
	_check(Assistance.requests(_snapshot(session), _snapshot(session).get_entity(donor), tick, config, budget).is_empty(), "unheard counterproposal cannot bypass refusal")
	_check(session.writer.apply_results(CommunityLife.new().converse(_snapshot(session), tick, config).results, session.stores), "counterproposal crosses return conversation")
	requests = Assistance.requests(_snapshot(session), _snapshot(session).get_entity(donor), tick, config, budget)
	_check(requests.size() == 1 and not requests[0].community_withheld and requests[0].pantry_portions == 2, "known bounded agreement reopens cooperation")
	if requests.is_empty():
		_finish()
		return
	var report: Dictionary = Knowledge.latest(_snapshot(session), donor, Knowledge.hour(tick))["need:" + receiver]
	_check(not Assistance._negotiated(_snapshot(session), _snapshot(session).get_entity(donor), report, config, Knowledge.hour(tick) + 48), "expired reply cannot authorize later agreement")
	var forged := report.duplicate(true)
	forged.payload.delivery_request.quantity = 3
	_check(not Assistance._negotiated(_snapshot(session), _snapshot(session).get_entity(donor), forged, config, Knowledge.hour(tick)), "larger demand cannot masquerade as accepted counterproposal")
	requests[0]["self_delivery"] = true
	var accepted := _order(session, donor, requests[0], tick, hauling, route_finder)
	_check(accepted.has("transaction") and session.writer.apply_result(accepted.transaction, session.stores), "renewed cooperation uses actual hauling contract")
	var order := Hauling.active_order(_snapshot(session), donor)
	_check(not order.is_empty() and order.get("negotiation_reply_id", "") != "", "in-transit goods retain agreement provenance")
	_check(session.validate_persistent_references().ok, "all request reply and contract references validate")
	_check(session.save_to_path("user://tests/world_integration_contract/negotiation.json").ok, "native negotiated delivery save")
	var restored := Session.new()
	var loaded: Dictionary = restored.load_from_path("user://tests/world_integration_contract/negotiation.json")
	_check(loaded.get("success", false), "native negotiated delivery restore: " + str(loaded.get("error", "")))
	if loaded.get("success", false):
		var metadata := {"scope_type": "global", "scope_id": "", "source": "test_injection"}
		_check(restored.advance_time(12, "negotiated_delivery_continuation", metadata).success,
			"controlled agreement continues twelve hours through ordinary world clock")
		var delivered: Array = _snapshot(restored).get_facts().filter(func(f: Dictionary) -> bool:
			return f.get("fact_type") == "food_hauling_stocked" and f.get("exchange_id") == order.exchange_id)
		_check(delivered.size() == 1 and delivered[0].quantity == 2 and delivered[0].negotiation_reply_id == order.negotiation_reply_id,
			"negotiated two portions travel and reach actual pantry without moving carrier in test")
		_check(restored.advance_time(24, "negotiated_meal_continuation", metadata).success,
			"recipient household continues its own day after delivery")
		var facts: Array = _snapshot(restored).get_facts()
		var receipts: Array = []
		for fact: Dictionary in facts:
			if fact.get("fact_type") == "household_pantry_taken" and not delivered.is_empty() \
					and delivered[0].fact_id in fact.get("source_fact_ids", []):
				receipts.append(fact.fact_id)
		_check(not receipts.is_empty(), "household physically takes food descended from negotiated delivery")
		_check(facts.any(func(f: Dictionary) -> bool:
			return f.get("fact_type") in ["npc_self_meal", "npc_household_shared_food"] \
				and f.get("source_fact_ids", []).any(func(id: String) -> bool: return id in receipts)),
			"negotiated delivery is consumed through ordinary household meal mechanism")
		_check(restored.validate_persistent_references().ok, "delivered negotiation retains valid native provenance")
	_finish()


func _order(session: Variant, donor: String, request: Dictionary, tick: Dictionary, hauling: Dictionary, routes: Callable) -> Dictionary:
	var snapshot: Variant = _snapshot(session)
	return Hauling.new()._try_order(snapshot, snapshot.get_entity(donor), snapshot.get_entity(donor), snapshot.get_entity(Storage.depot_id(donor)), request, tick, hauling, session.stores, routes)
