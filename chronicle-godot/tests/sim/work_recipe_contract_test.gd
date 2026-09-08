extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Builder = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Work = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const ItemSources = preload("res://scripts/sim/item/item_causal_sources.gd")
const WorkRules = preload("res://scripts/sim/economy/work_rules_setup.gd")
var checks := 0
var failures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "challenge_seed_override": 81001,
		"work_rules_version": 1, "household_food_hauling_version": 1,
		"household_food_budget_version": 1, "resident_subsistence_version": 1,
		"worksite_food_storage_version": 1}).success, "explicit work framework starts in canon world")
	if not live.is_ready():
		_finish()
		return
	var base: Dictionary = live.session.fixture_source_data.duplicate(true)
	var profiles: Array = base.generated_livelihood_profiles
	var fisher_profile: Dictionary = profiles.filter(func(p: Dictionary) -> bool: return p.get("work_recipe", {}).get("recipe_id") == "recipe.net_fishing")[0]
	var craft_profile: Dictionary = profiles.filter(func(p: Dictionary) -> bool: return p.get("work_recipe", {}).get("recipe_id") == "recipe.reed_cordage")[0]
	var fisher := _worker(base, fisher_profile)
	var crafter := _worker(base, craft_profile)
	_check(fisher != "" and crafter != "", "food and nonfood producers are generated people")
	_check(live.session.stores.entity_store.has_entity(Storage.depot_id(crafter)), "nonfood producer has actual owned stock container")
	for pair: Array in [[fisher, fisher_profile], [crafter, craft_profile]]:
		var fixture := _at_work(base, pair[0], pair[1])
		var session: Variant = _session(fixture)
		var actor := str(pair[0])
		var profile: Dictionary = pair[1]
		var tool := _tool(session, actor)
		var before := float(_snapshot(session).get_resource_stock(str(profile.resource_inputs[0].stock_id)).current)
		var data := Work.new().resolve_work_tick(_snapshot(session), [profile], _tick(12), fixture.resident_daily_life, session.registry)
		_check(session.writer.apply_results(data.results, session.stores), "same work resolver commits " + str(profile.work_recipe.recipe_id))
		var produced: Array = session.stores.fact_store.list_facts().filter(func(f: Dictionary) -> bool: return f.get("actor_id") == actor and f.get("recipe_id") == profile.work_recipe.recipe_id)
		_check(produced.size() == 1, "one source-backed production event")
		_check(_snapshot(session).get_resource_stock(str(profile.resource_inputs[0].stock_id)).current < before, "actual resource input consumed")
		_check(session.stores.item_store.get_item(str(tool.item_instance_id)).condition.durability == 3, "preserved tool wears once")
		_check(Storage.quantity(session.stores.item_store.list_items(), Storage.depot_id(actor), fixture.resident_daily_life.food_access.worksite_storage) > 0, "output is physically in worksite store")
		var worn := _at_work(base, actor, profile)
		for item: Dictionary in worn.initial_items:
			if item.item_instance_id == tool.item_instance_id:
				item["condition"] = {"durability": 0, "maximum_durability": 4}
		var stopped: Variant = _session(worn)
		var blocked := Work.new().resolve_work_tick(_snapshot(stopped), [profile], _tick(12), worn.resident_daily_life, stopped.registry)
		_check(stopped.writer.apply_results(blocked.results, stopped.stores), "worn tool records refusal without invalid transaction")
		_check(_snapshot(stopped).get_resource_stock(str(profile.resource_inputs[0].stock_id)).current == before, "worn tool consumes no raw materials")
		_check(stopped.stores.item_store.list_items_for_owner(Storage.depot_id(actor)).is_empty(), "broken tool cannot produce output")
		var absent := _at_work(base, actor, profile)
		_entity(absent, actor).states.location_id = _entity(absent, actor).states.home_location_id
		var remote: Variant = _session(absent)
		var plan := Recipe.new(_snapshot(remote), remote.registry).plan_inputs(profile, actor, "test.remote", 36)
		_check(not plan.ok and plan.missing.denial == "worker_not_at_worksite", "remote work rejected")
	_test_item_inputs_and_expansion(base, fisher, fisher_profile)
	_test_validation(live.session, fisher_profile)
	_test_item_sources()
	_check(live.advance_time(24).success, "unassisted first day advances with food and nonfood work")
	_check(live.session.save_to_path("user://tests/work_recipe/day1.json").ok, "native save includes versioned work definitions")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/work_recipe/day1.json").success, "versioned rules restore")
	_check(live.session.advance_time(1, "rf1", {}).success and restored.advance_time(1, "rf1", {}).success, "native branches advance")
	_check(_signature(live.session) == _signature(restored), "full native continuation agrees")
	var legacy := Live.new()
	_check(legacy.start({"scenario": "echo_realm"}).success and not legacy.session.fixture_source_data.has("work_rules"), "legacy start does not silently acquire work rules")
	_finish()


func _test_item_inputs_and_expansion(base: Dictionary, actor: String, original: Dictionary) -> void:
	var profile := original.duplicate(true)
	profile["products"] = [{"item_def_id": "item.travel_ration", "quantity": 22}]
	profile["resource_inputs"] = []
	profile["work_recipe"] = {"version": 1, "recipe_id": "test.data_only.third_recipe",
		"item_inputs": [{"query": {"tags_all": ["fish"], "capabilities_all": ["consume"]}, "quantity": 22}],
		"tools": [{"query": {"tags_all": ["rope"]}, "wear": 1}]}
	var fixture := _at_work(base, actor, profile)
	fixture.known_facts.append({"fact_id": "test_injection.work.input", "fact_type": "test_injection", "actor_id": actor})
	for index: int in range(2):
		fixture.initial_items.append({"item_instance_id": "test_injection.work.fish." + str(index), "item_def_id": "item.fresh_fish_portion",
			"holder": {"kind": "entity", "id": actor}, "quantity": 11,
			"provenance": {"source_kind": "test_injection", "created_by_fact_id": "test_injection.work.input"}})
	var session: Variant = _session(fixture)
	var tool := _tool(session, actor)
	var injected: Array = session.stores.item_store.to_save_data()
	for item: Dictionary in injected:
		if item.item_instance_id == tool.item_instance_id:
			item.quantity = 3
	_check(session.stores.item_store.load_save_data(injected).ok, "explicit tool-stack boundary injection")
	var before: Variant = _snapshot(session)
	var result := Work.new().resolve_work_tick(before, [profile], _tick(12), fixture.resident_daily_life, session.registry)
	_check(session.writer.apply_results(result.results, session.stores), "third data-only recipe consumes item inputs, no new runtime branch")
	_check(session.stores.item_store.get_item("test_injection.work.fish.0").quantity == 0 and session.stores.item_store.get_item("test_injection.work.fish.1").quantity == 0, "inputs consumed across two stacks")
	var originals: Dictionary = session.stores.item_store.get_item(str(tool.item_instance_id))
	_check(originals.quantity == 2 and originals.condition.durability == 4, "unused tools in stack retain durability")
	var parts: Array = session.stores.item_store.list_items().filter(func(i: Dictionary) -> bool: return i.item_def_id == "item.fiber_rope" and i.holder == {"kind": "entity", "id": actor} and i.condition.durability == 3)
	_check(parts.size() == 1 and parts[0].quantity == 1, "one tool split and worn without duplicating it")
	var outputs: Array = session.stores.item_store.list_items_for_owner(Storage.depot_id(actor)).filter(func(i: Dictionary) -> bool: return i.item_def_id == "item.travel_ration")
	_check(outputs.size() == 2 and int(outputs[0].quantity) + int(outputs[1].quantity) == 22, "third product is stored with legal max-stack splitting")
	var pick := Storage.new().plan_withdrawal(_snapshot(session), _snapshot(session).get_entity(actor), _tick(19), fixture.resident_daily_life.food_access.worksite_storage, session.stores)
	_check(pick.has("transaction") and session.writer.apply_result(pick.transaction, session.stores), "new food enters withdrawal without adding an item ID whitelist")
	var food_before := int(session.stores.item_store.list_items_for_owner(actor).filter(func(i: Dictionary) -> bool: return i.item_def_id == "item.travel_ration")[0].quantity)
	var meal := Work.new().resolve_household_support(_snapshot(session), _tick(20), fixture.resident_daily_life)
	_check(session.writer.apply_results(meal.results, session.stores), "third product reaches ordinary household use")
	var food_after := int(session.stores.item_store.list_items_for_owner(actor).filter(func(i: Dictionary) -> bool: return i.item_def_id == "item.travel_ration")[0].quantity)
	_check(food_after == food_before - 1, "third data-only product really feeds its owner")
	var no_input := Recipe.new(_snapshot(session), session.registry).plan_inputs(profile, actor, "test.no_input", 70)
	_check(not no_input.ok, "consumed inputs cannot satisfy another cycle")
	var conflict := original.duplicate(true)
	conflict.work_recipe = {"version": 1, "recipe_id": "test.overlap", "item_inputs": [
		{"query": {"tags_all": ["rope"]}, "quantity": 3}, {"query": {"tags_all": ["rope"]}, "quantity": 1}], "tools": []}
	_check(not Recipe.new(before, session.registry).plan_inputs(conflict, actor, "test.overlap", 72).ok, "overlapping selectors cannot double consume the same units")
	var rollback := Result.new()
	rollback.add_fact({"fact_id": "test.rollback", "fact_type": "test_injection"})
	rollback.add_item_change({"operation": "adjust_durability", "item_instance_id": tool.item_instance_id, "delta": -1, "source_fact_ids": ["test.rollback"]})
	rollback.add_item_change({"operation": "consume", "item_instance_id": "missing.item", "quantity": 1, "source_fact_ids": ["test.rollback"]})
	var saved := _signature(session)
	_check(not session.writer.apply_result(rollback, session.stores) and _signature(session) == saved, "failed compound work cannot leave partial wear or history")


func _test_validation(session: Variant, original: Dictionary) -> void:
	var profile := original.duplicate(true)
	profile.work_recipe.tools[0].query = {"unimplemented_power": "anything"}
	_check(Recipe.validate_profile(profile, session.registry) != "", "unknown query semantic rejected")
	profile = original.duplicate(true)
	profile.work_recipe.tools[0].wear = 0
	_check(Recipe.validate_profile(profile, session.registry) != "", "zero-wear tool role rejected")
	profile = original.duplicate(true)
	profile.products[0].item_def_id = "item.copper_coin"
	_check(Recipe.validate_profile(profile, session.registry) != "", "recipe cannot mint payment")
	profile = original.duplicate(true)
	profile.resource_inputs = []
	_check(Recipe.validate_profile(profile, session.registry) != "", "material-free production rejected")
	profile = original.duplicate(true)
	profile.resource_inputs.append(profile.resource_inputs[0].duplicate(true))
	_check(Recipe.validate_profile(profile, session.registry) != "", "duplicate resource demand rejected before reservation")
	profile = original.duplicate(true)
	profile.products = []
	profile.work_recipe.repairs = 7
	_check(Recipe.validate_profile(profile, session.registry) == "invalid_work_recipe_repairs", "malformed repairs rejected without script exception")
	var malformed: Dictionary = session.fixture_source_data.duplicate(true)
	malformed.work_rules.overrides[0].products = [7]
	_check(WorkRules.configure(malformed, session.registry) == "invalid_work_rule_product", "malformed data-only output rejected before compiling traits")
	malformed = session.fixture_source_data.duplicate(true)
	malformed.erase("work_rules_generated")
	malformed.work_rules.maintenance[0].resource_tags_all = [7]
	_check(WorkRules.configure(malformed, session.registry) == "invalid_maintenance_resource_tag", "malformed maintenance selector rejected before matching")
	malformed = session.fixture_source_data.duplicate(true)
	malformed.work_rules = 7
	var rejected: Dictionary = Session.new().start_from_fixture_data(malformed, [])
	_check(not rejected.success and rejected.error == "work_rules_not_dictionary", "formal start rejects malformed work configuration without entering generation")


func _test_item_sources() -> void:
	var sources: Array = []
	ItemSources.append_to(sources, {"provenance": {"created_by_fact_id": "original.batch"}, "history": [
		{"event_type": "quantity_increased", "fact_id": "later.production"},
		{"event_type": "stack_split", "fact_id": "earlier.withdrawal"}]})
	_check(sources == ["original.batch", "later.production", "earlier.withdrawal"], "mixed inventory preserves contributing production after partial withdrawal")
	ItemSources.append_to(sources, {"provenance": {"created_by_fact_id": "original.batch"}})
	_check(sources.size() == 3, "shared ancestry is deduplicated")


func _at_work(source: Dictionary, actor: String, profile: Dictionary) -> Dictionary:
	var fixture := source.duplicate(true)
	var person := _entity(fixture, actor)
	person.states.merge({"location_id": profile.workplace_id, "workplace_id": profile.workplace_id,
		"daily_route_id": "", "daily_activity": "working", "fatigue": 0, "health": 100,
		"hunger": "high", "livelihood_elapsed_hours": int(profile.work_interval_hours) - 1}, true)
	for index: int in range(fixture.generated_livelihood_profiles.size()):
		var existing: Dictionary = fixture.generated_livelihood_profiles[index]
		if existing.occupation_id == profile.occupation_id and existing.settlement_id == profile.settlement_id:
			fixture.generated_livelihood_profiles[index] = profile.duplicate(true)
	return fixture


func _worker(fixture: Dictionary, profile: Dictionary) -> String:
	for person: Dictionary in fixture.entities:
		if person.get("type") == "person" and person.get("states", {}).get("settlement_id") == profile.settlement_id \
				and person.get("states", {}).get("occupation_id") == profile.occupation_id:
			return str(person.id)
	return ""


func _entity(fixture: Dictionary, id: String) -> Dictionary:
	return fixture.entities.filter(func(e: Dictionary) -> bool: return e.id == id)[0]


func _tool(session: Variant, actor: String) -> Dictionary:
	return session.stores.item_store.list_items_for_owner(actor).filter(func(i: Dictionary) -> bool: return i.item_def_id == "item.fiber_rope")[0]


func _session(fixture: Dictionary) -> Variant:
	var session := Session.new()
	var result: Dictionary = session.start_from_fixture_data(fixture, [])
	_check(result.success, "controlled fixture loads through formal session")
	if not result.success:
		print(JSON.stringify(result))
	return session


func _snapshot(session: Variant) -> Variant:
	return Builder.new().build_snapshot(session.context, session.stores, true)


func _tick(hour: int) -> Dictionary:
	return {"day": 2, "hour": hour, "elapsed_hours": 1, "tick_event_id": "test_injection.recipe.%d" % hour}


func _signature(session: Variant) -> String:
	var e: Dictionary = session.build_save_envelope()
	return JSON.stringify(JSON.parse_string(JSON.stringify({"stores": e.stores, "session": e.session,
		"world_time": e.world_time, "rng_states": e.rng_states, "world_log": e.world_log}, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)


func _finish() -> void:
	print("WORK_RECIPE_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
