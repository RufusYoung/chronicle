extends "res://tests/sim/work_recipe_contract_test.gd"

const Choice = preload("res://scripts/sim/npc/resident_activity_choice.gd")
const Daily = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
const Opportunities = preload("res://scripts/sim/economy/resident_work_opportunities.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")
const Subsistence = preload("res://scripts/sim/npc/resident_subsistence.gd")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "challenge_seed_override": 81001, "work_rules_version": 1,
		"household_food_hauling_version": 1, "household_food_budget_version": 1,
		"resident_subsistence_version": 1, "worksite_food_storage_version": 1}).success, "new work and choice world starts")
	if not live.is_ready():
		_finish()
		return
	var base: Dictionary = live.session.fixture_source_data.duplicate(true)
	var profile: Dictionary = base.generated_livelihood_profiles.filter(func(p: Dictionary) -> bool: return p.get("work_recipe", {}).get("recipe_id") == "recipe.net_fishing")[0]
	var actor := _worker(base, profile)
	_choices(live.session, actor, profile)
	_repair(base, actor, profile)
	_purchase(base, actor, profile)
	_competing_buyers(base, actor, profile)
	_owned_stock_without_money(base, profile)
	_interruption(base, actor, profile)
	var envelope: Dictionary = live.session.build_save_envelope()
	envelope.definition_manifest.content_pack_version = 5
	for key: String in Choice.STATE_KEYS:
		envelope.definition_manifest.required_definition_ids.erase("state:state.character." + key)
	# An exact previous manifest adds definitions, not new-world behavior.
	var legacy := Live.new()
	_check(legacy.start({"scenario": "echo_realm"}).success, "previous behavior fixture starts")
	envelope = legacy.session.build_save_envelope()
	envelope.definition_manifest.content_pack_version = 5
	for key: String in Choice.STATE_KEYS:
		envelope.definition_manifest.required_definition_ids.erase("state:state.character." + key)
	var restored := Session.new()
	var report := restored.load_from_save_envelope(Saves.new().finalize_envelope(envelope))
	_check(report.success and Session.WORK_INTENT_DEFINITIONS_MIGRATION in report.migrations, "v5 exact manifest migrates explicitly")
	_check(not restored.fixture_source_data.resident_daily_life.has("activity_choice"), "migration does not turn on work or decision rules")
	_finish()


func _choices(session: Variant, actor_id: String, profile: Dictionary) -> void:
	var snapshot: Variant = _snapshot(session)
	var actor: Dictionary = snapshot.get_entity(actor_id)
	actor.states.location_id = profile.workplace_id
	actor.states.hunger = "none"
	actor.states.fatigue = 0
	snapshot.states[actor_id].location_id = profile.workplace_id
	for row: Dictionary in snapshot.entities:
		if row.id == actor_id:
			row.states.location_id = profile.workplace_id
	var router := Daily.new()
	var config: Dictionary = session.fixture_source_data.resident_daily_life
	var routes := router._routes(snapshot, session.settlement_network_runtime, session.context.locations, session.travel_routes, config)
	var work_and_rest: Array = []
	Choice.propose(work_and_rest, "work", profile.workplace_id, "working", "到岗谋生")
	Choice.propose(work_and_rest, "home", actor.states.home_location_id, "home", "暂无急事")
	var chosen := Choice.choose(work_and_rest, actor, routes, router, snapshot, [profile], session.registry, config.activity_choice, config.food_access)
	_check(chosen.kind == "work", "healthy equipped worker chooses income-producing work")
	var reversed := work_and_rest.duplicate(true)
	reversed.reverse()
	_check(Choice.choose(reversed, actor, routes, router, snapshot, [profile], session.registry, config.activity_choice, config.food_access).rule_id == chosen.rule_id,
		"candidate order does not determine life choice")
	_check(Subsistence.candidates(actor, [profile], config.food_access.subsistence, snapshot).is_empty(), "capable professional does not replace the same output with a dominated hand-gather recipe")
	Choice.propose(work_and_rest, "rest", actor.states.home_location_id, "resting", "身体需要休息")
	actor.states.fatigue = 9
	_check(Choice.choose(work_and_rest, actor, routes, router, snapshot, [profile], session.registry, config.activity_choice, config.food_access).kind == "rest",
		"exhausted worker chooses recovery over work")
	actor.states.fatigue = 0
	var daytime: Array = []
	Choice.propose(daytime, "rest", actor.states.home_location_id, "resting", "不在夜班")
	Choice.propose(daytime, "forage", profile.workplace_id, "foraging", "解决已知口粮不足")
	_check(Choice.choose(daytime, actor, routes, router, snapshot, [profile], session.registry, config.activity_choice, config.food_access).kind == "forage",
		"off-shift permission to rest does not override an available subsistence action")
	daytime[0]["mandatory_rest"] = true
	_check(Choice.choose(daytime, actor, routes, router, snapshot, [profile], session.registry, config.activity_choice, config.food_access).kind == "rest",
		"necessary bodily recovery remains stronger than optional subsistence")
	work_and_rest = work_and_rest.filter(func(r: Dictionary) -> bool: return r.kind != "rest")
	Choice.propose(work_and_rest, "care", actor.states.home_location_id, "home", "带粮回家照护")
	_check(Choice.choose(work_and_rest, actor, routes, router, snapshot, [profile], session.registry, config.activity_choice, config.food_access).kind == "care",
		"an available household delivery competes with work in the same ranker")
	var fixture := _at_work(session.fixture_source_data, actor_id, profile)
	_entity(fixture, actor_id).states.fatigue = 9
	var tired: Variant = _session(fixture)
	var result := Daily.new().resolve_tick(_snapshot(tired), _tick(12), config, tired.settlement_network_runtime,
		tired.context.locations, tired.travel_routes, tired.npc_livelihood_profiles, tired.registry)
	_check(tired.writer.apply_results(result.results, tired.stores), "actual daily-life adapter commits ranked choice")
	var fact: Dictionary = result.events.filter(func(f: Dictionary) -> bool: return f.actor_id == actor_id)[0]
	_check(fact.chosen_candidate.begins_with("rest:") and fact.alternatives.size() >= 2, "formal activity keeps chosen purpose and competing candidates")


func _repair(base: Dictionary, actor: String, original: Dictionary) -> void:
	var repair: Dictionary = base.resident_daily_life.maintenance_profiles.filter(func(p: Dictionary) -> bool: return p.settlement_id == original.settlement_id)[0]
	var fixture := _at_work(base, actor, repair)
	var states: Dictionary = _entity(fixture, actor).states
	states.workplace_id = original.workplace_id
	states.daily_intent_id = "repair:" + str(repair.work_recipe.recipe_id)
	states.work_elapsed_recipe_id = original.work_recipe.recipe_id
	for item: Dictionary in fixture.initial_items:
		if item.holder.id == actor and item.item_def_id == "item.fiber_rope":
			item.condition = {"durability": 0}
	var session: Variant = _session(fixture)
	var tool := _tool(session, actor)
	var stock := str(repair.resource_inputs[0].stock_id)
	var initial := float(_snapshot(session).get_resource_stock(stock).current)
	for hour: int in [12, 13]:
		var result := Work.new().resolve_work_tick(_snapshot(session), session.npc_livelihood_profiles, _tick(hour), fixture.resident_daily_life, session.registry)
		_check(session.writer.apply_results(result.results, session.stores), "repair uses ordinary work executor hour %d" % hour)
	var fixed: Dictionary = session.stores.item_store.get_item(str(tool.item_instance_id))
	_check(fixed.condition.durability == 2 and _snapshot(session).get_resource_stock(stock).current == initial - 1, "repair actually restores partial durability and consumes material")
	_check(session.stores.fact_store.find_facts_by_type("npc_work_maintained").size() == 1, "one source-backed maintenance event")
	fixed.condition.durability = 0
	_check(not Recipe.repairable(fixed, repair.work_recipe.repairs[0], _snapshot(session)), "used repair allowance cannot become infinite rejuvenation")
	_check(session.save_to_path("user://tests/work_activity/repair.json").ok, "repair history and unfinished-purpose state persist")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/work_activity/repair.json").success and _signature(session) == _signature(restored), "repair full native roundtrip agrees")


func _purchase(base: Dictionary, actor: String, profile: Dictionary) -> void:
	var craft: Dictionary = base.generated_livelihood_profiles.filter(func(p: Dictionary) -> bool: return p.get("work_recipe", {}).get("recipe_id") == "recipe.reed_cordage" and p.settlement_id == profile.settlement_id)[0]
	var seller := _worker(base, craft)
	var fixture := _at_work(base, seller, craft)
	var buyer: Dictionary = _entity(fixture, actor)
	buyer.states.merge({"location_id": craft.workplace_id, "daily_intent_id": "work_supply", "daily_activity": "seeking_work", "daily_route_id": ""}, true)
	for item: Dictionary in fixture.initial_items:
		if item.holder.id == actor and item.item_def_id == "item.fiber_rope":
			item.condition = {"durability": 0}
	var session: Variant = _session(fixture)
	var produced := Work.new().resolve_work_tick(_snapshot(session), [craft], _tick(12), fixture.resident_daily_life, session.registry)
	_check(session.writer.apply_results(produced.results, session.stores), "seller creates a rope from real labor and reeds")
	var before := _signature(session)
	var absent: Variant = _snapshot(session)
	for entity: Dictionary in absent.entities:
		if entity.id == seller:
			entity.states.location_id = entity.states.home_location_id
			absent.states[seller].location_id = entity.states.home_location_id
	var denied := Opportunities.plan_purchase(absent, absent.get_entity(actor), session.npc_livelihood_profiles, session.stores, _tick(13))
	_check(denied.has("event") and denied.event.fact_type == "work_supply_unmet" and _signature(session) == before, "no remote seller trade or speculative world write")
	var plan := Opportunities.plan_purchase(_snapshot(session), _snapshot(session).get_entity(actor), session.npc_livelihood_profiles, session.stores, _tick(13))
	_check(plan.has("transaction") and plan.event.fact_type == "work_supply_purchased", "onsite buyer can obtain a produced tool through real quote")
	var old_money := _coins(session, actor)
	var seller_money := _coins(session, seller)
	_check(session.writer.apply_result(plan.transaction, session.stores), "atomic work-supply payment and physical transfer commit")
	_check(_coins(session, actor) == old_money - 5 and _coins(session, seller) == seller_money + 5, "no reward money minted by tool demand")
	_check(Opportunities.need(_snapshot(session), _snapshot(session).get_entity(actor), session.npc_livelihood_profiles).is_empty(), "purchased tool removes shortage and permits return-to-work candidate")
	_check(not session.writer.apply_result(plan.transaction, session.stores), "same purchase cannot be applied twice")
	var poor_fixture := fixture.duplicate(true)
	var poor: Variant = _session(poor_fixture)
	var transfer := Result.new()
	transfer.add_fact({"fact_id": "test_injection.empty_wallet", "fact_type": "test_injection"})
	for item: Dictionary in poor.stores.item_store.list_items_for_owner(actor):
		if item.item_def_id == "item.copper_coin":
			transfer.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id,
				"expected_holder": item.holder, "new_holder": {"kind": "entity", "id": seller}, "source_fact_ids": ["test_injection.empty_wallet"]})
	_check(poor.writer.apply_result(transfer, poor.stores), "test injection moves wallet without destroying money or references")
	var stock_result := Work.new().resolve_work_tick(_snapshot(poor), [craft], _tick(12), poor_fixture.resident_daily_life, poor.registry)
	_check(poor.writer.apply_results(stock_result.results, poor.stores), "unaffordable control retains real stock")
	var refused := Opportunities.plan_purchase(_snapshot(poor), _snapshot(poor).get_entity(actor), poor.npc_livelihood_profiles, poor.stores, _tick(13))
	_check(refused.event.reason == "unaffordable", "a real seller cannot supply a buyer without payment")


func _interruption(base: Dictionary, actor: String, profile: Dictionary) -> void:
	var fixture := _at_work(base, actor, profile)
	_entity(fixture, actor).states.livelihood_elapsed_hours = 0
	var session: Variant = _session(fixture)
	var first := Work.new().resolve_work_tick(_snapshot(session), [profile], _tick(10), fixture.resident_daily_life, session.registry)
	_check(session.writer.apply_results(first.results, session.stores), "first work hour commits only progress")
	var pause := Result.new()
	pause.add_state_change({"entity_id": actor, "key": "daily_activity", "to": "resting"})
	_check(session.writer.apply_result(pause, session.stores), "test injection interrupts activity")
	var interrupted := Work.new().resolve_work_tick(_snapshot(session), [profile], _tick(11), fixture.resident_daily_life, session.registry)
	_check(interrupted.results.is_empty() and session.stores.state_store.get_state(actor, "livelihood_elapsed_hours") == 1, "rest cannot simultaneously count as work")
	var resume := Result.new()
	resume.add_state_change({"entity_id": actor, "key": "daily_activity", "to": "working"})
	session.writer.apply_result(resume, session.stores)
	for hour: int in [12, 13, 14]:
		var step := Work.new().resolve_work_tick(_snapshot(session), [profile], _tick(hour), fixture.resident_daily_life, session.registry)
		_check(session.writer.apply_results(step.results, session.stores), "resume same workplace and recipe")
	_check(session.stores.fact_store.find_facts_by_type("npc_livelihood_produced").size() == 1, "one full work block, no bonus production for pause or resume")


func _competing_buyers(base: Dictionary, first: String, profile: Dictionary) -> void:
	var craft: Dictionary = base.generated_livelihood_profiles.filter(func(p: Dictionary) -> bool: return p.get("work_recipe", {}).get("recipe_id") == "recipe.reed_cordage" and p.settlement_id == profile.settlement_id)[0]
	var seller := _worker(base, craft)
	var fixture := _at_work(base, seller, craft)
	var second := ""
	for person: Dictionary in fixture.entities:
		if person.get("type") == "person" and person.get("states", {}).get("occupation_id") == profile.occupation_id \
				and person.get("states", {}).get("settlement_id") == profile.settlement_id and person.id != first:
			second = str(person.id)
	_check(second != "", "two independent generated buyers exist")
	for buyer: String in [first, second]:
		_entity(fixture, buyer).states.merge({"location_id": craft.workplace_id, "daily_activity": "seeking_work", "daily_intent_id": "work_supply", "daily_route_id": ""}, true)
		for item: Dictionary in fixture.initial_items:
			if item.holder.id == buyer and item.item_def_id == "item.fiber_rope":
				item.condition = {"durability": 0}
	var session: Variant = _session(fixture)
	var made := Work.new().resolve_work_tick(_snapshot(session), [craft], _tick(12), fixture.resident_daily_life, session.registry)
	_check(session.writer.apply_results(made.results, session.stores), "contested goods are produced once")
	var a := Opportunities.plan_purchase(_snapshot(session), _snapshot(session).get_entity(first), session.npc_livelihood_profiles, session.stores, _tick(13))
	var b := Opportunities.plan_purchase(_snapshot(session), _snapshot(session).get_entity(second), session.npc_livelihood_profiles, session.stores, _tick(13))
	_check(a.event.fact_type == "work_supply_purchased" and b.event.fact_type == "work_supply_purchased", "both quotes observe the same unreserved supply")
	_check(session.writer.apply_result(a.transaction, session.stores), "first buyer obtains actual tool")
	var before := _signature(session)
	_check(not session.writer.apply_result(b.transaction, session.stores) and _signature(session) == before,
		"second concurrent quote cannot spend money or reuse the transferred tool")


func _owned_stock_without_money(base: Dictionary, profile: Dictionary) -> void:
	var craft: Dictionary = base.generated_livelihood_profiles.filter(func(p: Dictionary) -> bool: return p.get("work_recipe", {}).get("recipe_id") == "recipe.reed_cordage" and p.settlement_id == profile.settlement_id)[0]
	var owner := _worker(base, craft)
	var fixture := _at_work(base, owner, craft)
	_entity(fixture, owner).states.location_id = _entity(fixture, owner).states.home_location_id
	_entity(fixture, owner).states.daily_activity = "home"
	fixture.known_facts.append({"fact_id": "test_injection.owned_spare", "fact_type": "test_injection", "actor_id": owner})
	fixture.initial_items.append({"item_instance_id": "test_injection.owned_spare", "item_def_id": "item.fiber_rope", "quantity": 1,
		"holder": {"kind": "entity", "id": Storage.depot_id(owner)}, "provenance": {"created_by_fact_id": "test_injection.owned_spare"}})
	for item: Dictionary in fixture.initial_items:
		if item.holder.id == owner and item.item_def_id == "item.fiber_rope":
			item.condition = {"durability": 0}
	var session: Variant = _session(fixture)
	var no_cash := Result.new()
	no_cash.add_fact({"fact_id": "test_injection.owner_without_cash", "fact_type": "test_injection"})
	for item: Dictionary in session.stores.item_store.list_items_for_owner(owner):
		if item.item_def_id == "item.copper_coin":
			no_cash.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id,
				"new_holder": {"kind": "entity", "id": craft.settlement_id}, "source_fact_ids": ["test_injection.owner_without_cash"]})
	_check(session.writer.apply_result(no_cash, session.stores), "explicit cash-poor control preserves total money")
	var config: Dictionary = fixture.resident_daily_life
	var decision := Daily.new().resolve_tick(_snapshot(session), _tick(12), config, session.settlement_network_runtime,
		session.context.locations, session.travel_routes, session.npc_livelihood_profiles, session.registry)
	_check(session.writer.apply_results(decision.results, session.stores), "cash-poor owner still makes a legal daily choice")
	_check(session.stores.state_store.get_state(owner, "daily_goal_id") == craft.workplace_id \
		and session.stores.state_store.get_state(owner, "daily_intent_id") == "work_supply", "own stock retrieval does not require buyer money")


func _coins(session: Variant, actor: String) -> int:
	var total := 0
	for item: Dictionary in session.stores.item_store.list_items_for_owner(actor):
		if item.item_def_id == "item.copper_coin":
			total += int(item.quantity)
	return total
