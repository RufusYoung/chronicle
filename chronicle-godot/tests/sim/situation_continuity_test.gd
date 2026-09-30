extends "res://tests/sim/situation_interaction_test.gd"

const Continuity = preload("res://scripts/sim/situation/situation_continuity.gd")
const OTHER := "generated_resident.echo_landing.001"
const HUB := "generated_location.echo_landing.commons"
const Daily = preload("res://scripts/sim/npc/resident_daily_life_system.gd")


func _snapshot(session: Variant) -> Variant:
	return session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())


func _run() -> void:
	var agent := NewAgent.new()
	var response: Dictionary = agent.handle({"protocol": 1, "command": "start", "request_id": "start", "session_id": agent.session_id,
		"expected_revision": 0, "mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v2"})
	_check(response.ok, "continuity profile starts through public protocol")
	if not response.ok:
		_finish()
		return
	var base: Dictionary = agent.model.session.fixture_source_data.duplicate(true)
	_check(base.situation_rules.version == 2, "new explicit rules, old saves not silently upgraded")
	_check(response.observation.has("people_leads"), "bounded heard/seen leads are public")
	_check(response.choices.all(func(c: Dictionary) -> bool: return not c.has("statement") and not c.has("profile") and not c.has("report") and not c.has("policy")), "public choices omit unspoken answers and internal execution payloads")
	var session: Variant = agent.model.session
	var before := _signature(session)
	Continuity.knowledge(session, _snapshot(session))
	Continuity.leads(session, _snapshot(session))
	_check(before == _signature(session), "reading and routing do not mutate truth or time")
	base.location_id = SITE
	base.player.location_id = SITE
	base.world_time = {"day": 1, "hour": 10}
	base.known_facts.append({"fact_id": "test_injection.continuity", "fact_type": "test_injection", "summary": "测试注入：控制见面与离场，只验证知识、物品与后续合同。"})
	for who: String in [WHO, OTHER]:
		_entity(base, who).states.merge({"location_id": SITE, "daily_route_id": "", "visible": true,
			"daily_activity": "working", "hunger": "none", "fatigue": 0, "health": 100}, true)
	base.initial_items.append({"item_instance_id": "test.spare", "item_def_id": "item.woven_reed_vest", "quantity": 1,
		"holder": {"kind": "entity", "id": "player"}})
	session = _prepared(base)
	var observation: Variant = Continuity.observe(_snapshot(session), session.get_time_summary(), session.context.locations)
	_check(session.writer.apply_result(observation, session.stores), "co-present people remember one another")
	_check(Continuity.sightings(_snapshot(session), OTHER).has(WHO), "NPC has actual first-hand location evidence")
	_check(Continuity.observe(_snapshot(session), session.get_time_summary(), session.context.locations).is_empty(), "unchanged observation is not spammed")
	_ask(session)
	_check(not Continuity.knowledge(session, _snapshot(session)).filter(func(r: Dictionary) -> bool: return r.kind == "danger").is_empty(), "specific testified danger becomes a lead")
	var gift: Dictionary = _options(session, "give")[0]
	_check(session.PlayerLife.execute(session, gift.action_id).success, "legal gift commits in continuity world")
	var equipped: Variant = Intent.Gear.equip(_snapshot(session), _snapshot(session).get_entity(WHO), session.get_time_summary())
	_check(session.writer.apply_result(equipped, session.stores), "shared autonomous equipment consumer uses the gift")
	var news := _options(session, "aftermath")
	_check(not news.is_empty(), "real downstream fact offers a personal follow-up")
	if not news.is_empty():
		_check(not news[0].has("summary") and not news[0].has("update"), "unheard full private testimony not embedded in action payload")
		var heard: Dictionary = session.PlayerLife.execute(session, news[0].action_id)
		_check(heard.success and heard.player_life_feedback.body.contains("穿戴"), "actual follow-up says what happened to the item")
		_check(_options(session, "aftermath").is_empty(), "same follow-up cannot repeat indefinitely")
	var movement := Result.new()
	movement.add_state_change({"entity_id": WHO, "key": "location_id", "to": HUB})
	movement.mark_resolved("test_injection")
	_check(session.writer.apply_result(movement, session.stores), "test injection: recipient leaves unwitnessed")
	var known: Dictionary = Continuity.sightings(_snapshot(session), "player")[WHO]
	_check(known.location_id == SITE, "last sighting does not track actual distant movement")
	var questions: Array = session.PlayerLife.options(session).filter(func(r: Dictionary) -> bool:
		return r.get("intent") == "whereabouts" and r.get("wanted_id") == WHO and r.subject_id == OTHER)
	_check(not questions.is_empty(), "can ask present witness about absent acquaintance")
	if not questions.is_empty():
		var answer: Dictionary = session.PlayerLife.execute(session, questions[0].action_id)
		_check(answer.success and answer.player_life_feedback.body.contains("之后有没有离开，我不知道"), "dated sighting explicitly preserves uncertainty")
		var answers: Array = session.stores.fact_store.list_facts().filter(func(f: Dictionary) -> bool: return f.get("fact_type") == "situation_whereabouts")
		_check(answers.back().known_location_id == SITE, "witness does not reveal true remote hub")
	_check(session.save_to_path("user://tests/situations/continuity.json").ok, "native knowledge/follow-up save")
	var restored := Session.new()
	var loaded: Dictionary = restored.load_from_path("user://tests/situations/continuity.json")
	_check(loaded.success, "native knowledge/follow-up load: " + str(loaded))
	if loaded.success:
		_check(JSON.parse_string(JSON.stringify(Continuity.knowledge(session, _snapshot(session)))) == JSON.parse_string(JSON.stringify(Continuity.knowledge(restored, _snapshot(restored)))), "knowledge and uncertainty survive persistence")
		session.advance_time(1, "same_continuation")
		restored.advance_time(1, "same_continuation")
		_check(_signature(session) == _signature(restored), "all stores and observations continue identically after load")
	var legacy := base.duplicate(true)
	legacy.situation_rules.version = 1
	var old: Variant = _session(legacy)
	_check(old.initialized and not Continuity.enabled(old), "version1 remains version1")
	_sacrifice_case(base)
	_pending_case(base)
	_information_cases(base)
	_zero_effect_advice(base)
	_private_lineage(base)
	_travel_case(agent)
	_finish()


func _sacrifice_case(base: Dictionary) -> void:
	var session: Variant = _prepared(base)
	_ask(session)
	var offers := _options(session, "give").filter(func(r: Dictionary) -> bool: return r.has("clear_slots"))
	_check(not offers.is_empty(), "own worn protection can be sacrificed instead of only spare goods")
	if offers.is_empty():
		return
	var offer: Dictionary = offers[0]
	var result: Dictionary = session.PlayerLife.execute(session, offer.action_id)
	_check(result.success, "worn gift clears loadout and transfers ownership atomically: " + str(result))
	_check(session.stores.item_store.get_item(offer.item_id).holder.id == WHO, "recipient owns the actual former player item")
	_check(not session.stores.equipment_store.get_loadout("player").slots.values().has(offer.item_id), "player loses old protection, not just a narrative cost")
	_check(not session.PlayerLife.execute(session, offer.action_id).success, "stale second gift cannot duplicate equipped item")
	_check(session.save_to_path("user://tests/situations/sacrifice.json").ok, "sacrifice persists without broken equipment references")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/situations/sacrifice.json").success, "sacrificed equipment native reload")


func _pending_case(base: Dictionary) -> void:
	var session: Variant = _prepared(base)
	_ask(session)
	var fund: Dictionary = _options(session, "fund")[0]
	_check(session.PlayerLife.execute(session, fund.action_id).success, "funding uses own coins")
	_check(Continuity.followup(_snapshot(session), WHO, "player").is_empty(), "no immediate fictional downstream result")
	session.advance_time(1, "test_pending_progress")
	var update := Continuity.followup(_snapshot(session), WHO, "player")
	_check(not update.is_empty(), "recipient can answer even when equipment was not obtained")
	if update.is_empty():
		return
	_check(update.kind == "pending", "unresolved funding is not called a successful purchase")
	var info: Dictionary = session.build_save_envelope()
	_check(Continuity.validate(session) == "", "untampered causal knowledge valid")
	var memory: Dictionary = {}
	for row: Dictionary in info.stores.memories:
		if row.get("memory_type") == "situation_sighting":
			memory = row
			break
	if not memory.is_empty():
		memory.location_id = "nonexistent_place"
		var corrupted := Session.new()
		_check(not corrupted.load_from_save_envelope(info).get("ok", false), "forged native envelope is rejected")
		session.stores.memory_store.load_save_data(info.stores.memories)
		_check(Continuity.validate(session) == "situation_sighting_reference_mismatch", "even a forged in-memory observation fails reference validation")


func _travel_case(agent: Variant) -> void:
	var session: Variant = agent.model.session
	var roads: Array = session.get_travel_options().filter(func(r: Dictionary) -> bool: return r.can_travel and r.hours > 1)
	_check(not roads.is_empty(), "natural start has a real multi-hour road")
	if roads.is_empty():
		return
	var before: int = session.elapsed_hours_since_start
	var traveled: Dictionary = session.travel(roads[0].route_id)
	_check(traveled.success and int(traveled.hours) == int(roads[0].hours), "uninterrupted travel resolves entire offered road")
	_check(session.elapsed_hours_since_start - before == int(roads[0].hours), "no road time is skipped")
	_check(session.context.location_id == roads[0].to_location_id, "road continuation stops at arrival")
	_check(session.save_to_path("user://tests/situations/travel_v2.json").ok, "later day knowledge saves")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/situations/travel_v2.json").success, "later day knowledge restores against saved time")


func _information_cases(base: Dictionary) -> void:
	var session: Variant = _prepared(base)
	var danger := str(_snapshot(session).get_entity("world_threat.field_boar").territory_id)
	var facts := Result.new()
	facts.add_fact({"fact_id": "test.old_request", "fact_type": "equipment_request", "actor_id": WHO, "location_id": SITE,
		"day": 1, "hour": 1, "query": {"tags_all": ["armor_outer"]}, "danger_location_id": danger, "goal": "test", "summary": "测试注入：旧口信"})
	facts.add_fact({"fact_id": "test.new_intention", "fact_type": "situation_inquiry", "actor_id": "player", "subject_id": WHO, "location_id": SITE,
		"day": 1, "hour": 9, "stated_destination_id": HUB, "danger_location_id": danger, "summary": "测试注入：后来的当面询问"})
	facts.add_fact({"fact_id": "test.read_old_request", "fact_type": "situation_notice_read", "actor_id": "player", "subject_id": WHO, "location_id": SITE,
		"day": 1, "hour": 10, "observed_hour": 25, "query": {"tags_all": ["armor_outer"]}, "danger_location_id": danger, "goal": "test",
		"source_fact_ids": ["test.old_request"], "summary": "测试注入：刚读到旧口信"})
	facts.mark_resolved("test_injection")
	_check(session.writer.apply_result(facts, session.stores), "test injection: old public notice read after newer personal inquiry")
	var knowledge := Continuity.knowledge(session, _snapshot(session))
	_check(knowledge.any(func(k: Dictionary) -> bool: return k.kind == "intention" and k.location_id == HUB and k.observed_hour == 33), "old notice does not erase newer stated destination")
	_check(knowledge.any(func(k: Dictionary) -> bool: return k.kind == "danger" and k.observed_hour == 33), "reading an old notice does not make old danger fresh")
	_check(Continuity.validate(session) == "", "public notice has matching dated source")
	var info: Dictionary = session.build_save_envelope()
	for fact: Dictionary in info.stores.facts:
		if fact.fact_id == "test.read_old_request":
			fact.observed_hour = 10
	_check(not Session.new().load_from_save_envelope(info).get("ok", false), "forged notice timestamp cannot upgrade stale information")
	_check(Continuity.update_key({"fact_type": "npc_livelihood_produced", "recipe_id": "one", "hour": 4}, "gift") \
		== Continuity.update_key({"fact_type": "npc_livelihood_produced", "recipe_id": "one", "hour": 8}, "gift"), "same later production cycle does not repeatedly become a new follow-up")


func _zero_effect_advice(base: Dictionary) -> void:
	var session: Variant = _prepared(base)
	_ask(session)
	_check(session.PlayerLife.execute(session, _options(session, "caution")[0].action_id).success, "advice can be heard without obedience")
	var snapshot: Variant = _snapshot(session)
	var reset := Result.new()
	reset.add_relationship_change({"source_id": WHO, "target_id": "player", "axis": "trust", "delta": -int(snapshot.get_relation(WHO, "player", "trust", 0))})
	reset.mark_resolved("test_injection")
	_check(session.writer.apply_result(reset, session.stores), "test injection: zero trust isolates an ineffective warning")
	snapshot = _snapshot(session)
	var rows: Array = []
	Choice.propose(rows, "work", str(snapshot.get_entity("world_threat.field_boar").territory_id), "working", "测试注入：相同候选")
	var config: Dictionary = Choice.PROFILE.duplicate(true)
	config.merge({"danger_hour": Intent.now(session.get_time_summary()), "situation_version": 2})
	var chosen := Choice.choose(rows, snapshot.get_entity(WHO), session.travel_routes, Daily.new(), snapshot, [], session.registry, config, {})
	_check(not chosen.factors.has("heard_caution"), "zero-weight advice does not add a decision factor")
	_check(chosen.source_fact_ids.all(func(id: String) -> bool: return snapshot.get_fact(id).get("fact_type") != "situation_advice"), "ineffective advice is not advertised as a cause of later work")


func _private_lineage(base: Dictionary) -> void:
	var session: Variant = _prepared(base)
	var result := Result.new()
	result.add_fact({"fact_id": "test.remote_gift", "fact_type": "situation_fund", "actor_id": "player", "subject_id": WHO,
		"day": 1, "hour": 8, "location_id": SITE, "summary": "测试注入：给甲的资助，乙并不知情"})
	result.add_fact({"fact_id": "test.remote_purchase", "fact_type": "resident_food_purchased", "actor_id": OTHER,
		"day": 1, "hour": 9, "location_id": HUB, "source_fact_ids": ["test.remote_gift"], "summary": "测试注入：钱物经手，但乙不知上游来源"})
	result.mark_resolved("test_injection")
	_check(session.writer.apply_result(result, session.stores), "test injection: upstream transaction lineage without personal knowledge")
	var snapshot: Variant = _snapshot(session)
	_check(Continuity.contribution(snapshot, ["test.remote_purchase"], "player") == "test.remote_gift", "internal audit can trace the real upstream record")
	_check(Continuity.contribution(snapshot, ["test.remote_purchase"], "player", OTHER) == "", "third-party witness cannot infer private upstream contribution")
	_check(Continuity.followup(snapshot, OTHER, "player").is_empty(), "no omniscient NPC update from unwitnessed money circulation")
	_check(Continuity.known_contribution(snapshot, snapshot.get_fact("test.remote_gift"), WHO), "actual recipient knows the direct assistance")
	_check(session.PlayerLife.options(session).all(func(c: Dictionary) -> bool: return not str(c.action_id).begins_with("inquire:")), "v2 does not also expose legacy omniscient follow-up payloads")
