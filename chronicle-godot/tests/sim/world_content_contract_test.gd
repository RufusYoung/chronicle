extends "res://tests/sim/player_local_life_contract_test.gd"

const Content = preload("res://scripts/sim/generation/world_content_extension.gd")
const Incidents = preload("res://scripts/sim/player/local_incident_options.gd")
const OPTIONS := {"scenario": "echo_realm", "challenge_seed_override": 81001,
	"work_rules_version": 1, "world_danger_version": 1, "player_life_version": 2, "content_extension_version": 1,
	"household_food_hauling_version": 1, "household_food_budget_version": 1,
	"resident_subsistence_version": 1, "worksite_food_storage_version": 1}


func _run() -> void:
	var live := Live.new()
	var start: Dictionary = live.start(OPTIONS)
	_check(start.get("success", false), "versioned content starts: " + str(start.get("error", "")))
	if not live.is_ready():
		_finish()
		return
	var session: Variant = live.session
	var pack: Dictionary = session.fixture_source_data.content_extension
	_check(session.fixture_source_data.world_danger.seed == OPTIONS.challenge_seed_override, "content danger uses the selected world seed")
	_check(pack.item_defs.all(func(row: Dictionary) -> bool: return session.registry.has_definition("item", row.item_def_id)), "embedded definitions registered in ordinary item registry")
	var variants: Array = []
	for profile: Dictionary in session.fixture_source_data.generated_livelihood_profiles:
		variants.append_array(Recipe.variants(profile))
	_check(variants.filter(func(row: Dictionary) -> bool: return str(row.get("work_recipe", {}).get("recipe_id", "")) == "recipe.smoke_lake_fish").size() == 1, "fisher keeps raw production and a processing alternative")
	var base: Dictionary = session.fixture_source_data.duplicate(true)
	_validation_cases(base)
	for recipe_id: String in ["recipe.smoke_lake_fish", "recipe.roast_roots", "recipe.double_light_cords", "recipe.rebind_fiber_rope"]:
		_processing_case(base, recipe_id)
	for item_id: String in ["item.light_reed_cord", "item.doubled_reed_cord"]:
		_tool_extension_case(base, item_id)
	_incident_case(base)
	_worn_incident_case(base)
	_choice_case(base)
	_material_purchase_case(base)
	_locality_and_progress_case(base)
	_check(session.advance_time(48, "passive_content_probe").success, "natural two days advance without test injection")
	var counts := {}
	for fact: Dictionary in session.stores.fact_store.list_facts():
		if fact.has("recipe_id"):
			counts[fact.recipe_id] = int(counts.get(fact.recipe_id, 0)) + 1
	print("NATURAL_RECIPES " + JSON.stringify(counts))
	_check(session.save_to_path("user://tests/world_content/natural.json").ok, "content world saves")
	var restored := Session.new()
	var loaded: Dictionary = restored.load_from_path("user://tests/world_content/natural.json")
	_check(loaded.get("success", false), "embedded content restores: " + str(loaded.get("error", "")))
	if loaded.get("success", false):
		_check(session.advance_time(2, "continuation").success and restored.advance_time(2, "continuation").success, "both native branches continue")
		_check(_signature(session) == _signature(restored), "full content state continues identically")
	_finish()


func _locality_and_progress_case(base: Dictionary) -> void:
	var session: Variant = _session(base)
	var home: String = session.get_snapshot().player.settlement_id
	_check(session.advance_time(12, "legal_wait_until_evening").success, "wait until territorial threat is inactive")
	for fragment: String in [".network.", "commons_to_terrace_farming"]:
		var routes: Array = session.get_travel_options().filter(func(r: Dictionary) -> bool: return fragment in str(r.route_id))
		_check(not routes.is_empty(), "physical route to neighboring workplace: " + fragment)
		if routes.is_empty():
			return
		_check(session.travel(routes[0].route_id).success, "legal departure to neighbor")
		while session.get_snapshot().player.get("daily_route_id", "") != "":
			_check(Life.execute(session, "continue").success, "legal travel continuation")
	_check(session.get_snapshot().player.settlement_id == home, "arrival does not change membership or home")
	var rows := Life.options(session, false)
	_check(rows.any(func(r: Dictionary) -> bool: return r.action_id == "work:recipe.roast_roots"), "neighbor's local processing is visible")
	_check(rows.any(func(r: Dictionary) -> bool: return r.action_id == "gather:terrace_farmer"), "neighbor's local harvesting is visible")
	var view: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var actor: Dictionary = view.get_entity("player")
	var local: Dictionary = Life.gather_profiles(session, view, actor)[0]
	_check(Life.content_resource_denial(session, view, actor, local) == "没有该资源的生产使用权", "showing a local job never grants outsider resource rights")
	var progress_actor: Dictionary = actor.duplicate(true)
	progress_actor.states.merge({"daily_intent_id": "work:recipe.reed_cordage", "subsistence_elapsed_hours": 3,
		"subsistence_workplace_id": actor.states.location_id}, true)
	var option := Life.work_option(progress_actor, "work:recipe.reed_cordage", "编绳", "扣取真实材料", "", 4)
	_check(option.hours == 1 and option.work_progress.completed_hours == 3 and "尚需1小时" in option.hint, "public choice shows remaining work instead of charging the full duration")
	_check(Life.work_option(progress_actor, "gather:terrace_farmer", "采集", "", "", 4).hours == 4, "changing jobs does not inherit another job's labor")
	progress_actor.states.subsistence_workplace_id = "elsewhere"
	_check(Life.work_option(progress_actor, "work:recipe.reed_cordage", "编绳", "", "", 4).hours == 4, "remote partial work cannot be resumed locally")
	_check(session.save_to_path("user://tests/world_content/neighbor.json").ok, "native neighboring workplace save")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/world_content/neighbor.json").success, "native neighboring workplace restore")
	_check(JSON.stringify(Life.options(restored)) == JSON.stringify(Life.options(session)), "local candidates persist without changing membership")


func _profile(base: Dictionary, recipe_id: String) -> Dictionary:
	for primary: Dictionary in base.generated_livelihood_profiles:
		for variant: Dictionary in Recipe.variants(primary):
			if variant.get("work_recipe", {}).get("recipe_id") == recipe_id:
				return {"primary": primary, "variant": variant, "actor": _worker(base, primary)}
	return {}


func _processing_case(base: Dictionary, id: String) -> void:
	var entry := _profile(base, id)
	var profile: Dictionary = entry.variant
	var actor := str(entry.actor)
	var fixture := _at_work(base, actor, entry.primary)
	_entity(fixture, actor).states.merge({"daily_intent_id": "recipe:" + id,
		"work_elapsed_recipe_id": id, "livelihood_elapsed_hours": int(profile.work_interval_hours) - 1}, true)
	fixture.known_facts.append({"fact_id": "test_injection.content.inputs", "fact_type": "test_injection", "summary": "测试注入：备齐配方材料并置于现场，检查共享作业的实际扣取与用途。"})
	var input: Dictionary = profile.work_recipe.item_inputs[0]
	fixture.initial_items.append({"item_instance_id": "test.content.material", "item_def_id": input.query.item_def_id,
		"holder": {"kind": "entity", "id": actor}, "quantity": input.quantity,
		"provenance": {"source_kind": "test_injection", "created_by_fact_id": "test_injection.content.inputs"}})
	var session: Variant = _session(fixture)
	if not session.is_ready():
		return
	var before_input := _quantity(session, actor, str(input.query.item_def_id))
	var resolved := Work.new().resolve_work_tick(_snapshot(session), [entry.primary], _tick(12), fixture.resident_daily_life, session.registry)
	_check(session.writer.apply_results(resolved.results, session.stores), id + " uses shared work transaction")
	_check(_quantity(session, actor, str(input.query.item_def_id)) == before_input - int(input.quantity), id + " consumes exact physical inputs")
	var product: Dictionary = profile.products[0]
	_check(_quantity(session, Storage.depot_id(actor), str(product.item_def_id)) == int(product.quantity), id + " stores exact finished batch")
	_check(session.stores.fact_store.list_facts().filter(func(fact: Dictionary) -> bool: return fact.get("recipe_id") == id and fact.get("fact_type") == "npc_livelihood_produced").size() == 1, id + " has one production, not both recipe variants")
	var plan := Recipe.new(_snapshot(session), session.registry).plan_inputs(profile, actor, "test.no_material", 40)
	_check(not plan.ok, id + " cannot repeat after material is consumed")
	if "food" in session.registry.get_definition("item", product.item_def_id).get("tags", []):
		_market_product_case(session, actor, str(product.item_def_id))
		var withdrawal := Storage.new().plan_withdrawal(_snapshot(session), _snapshot(session).get_entity(actor), _tick(19), fixture.resident_daily_life.food_access.worksite_storage, session.stores)
		_check(withdrawal.has("transaction") and session.writer.apply_result(withdrawal.transaction, session.stores), id + " enters ordinary food withdrawal")
		var count := _quantity(session, actor, str(product.item_def_id))
		var meal := Work.new().resolve_household_support(_snapshot(session), _tick(20), fixture.resident_daily_life)
		_check(session.writer.apply_results(meal.results, session.stores), id + " reaches ordinary household meal resolver")
		_check(_quantity(session, actor, str(product.item_def_id)) == count - 1, id + " is actually eaten")
	var absent := _at_work(base, actor, entry.primary)
	_entity(absent, actor).states.location_id = _entity(absent, actor).states.home_location_id
	var remote: Variant = _session(absent)
	_check(Recipe.new(_snapshot(remote), remote.registry).plan_inputs(profile, actor, "test.remote", 40).missing.denial == "worker_not_at_worksite", id + " cannot process remotely")


func _quantity(session: Variant, holder: String, definition: String) -> int:
	var total := 0
	for item: Dictionary in session.stores.item_store.list_items_for_owner(holder):
		if item.item_def_id == definition:
			total += int(item.quantity)
	return total


func _tool_extension_case(base: Dictionary, item_id: String) -> void:
	var entry := _profile(base, "recipe.net_fishing")
	var actor := str(entry.actor)
	var fixture := _at_work(base, actor, entry.primary)
	fixture.initial_items = fixture.initial_items.filter(func(item: Dictionary) -> bool: return item.get("holder", {}).get("id") != actor or item.item_def_id != "item.fiber_rope")
	fixture.known_facts.append({"fact_id": "test_injection.content.tool", "fact_type": "test_injection", "summary": "测试注入：仅替换现场工具，验证同一用途读取实际耐久。"})
	fixture.initial_items.append({"item_instance_id": "test.content.tool", "item_def_id": item_id, "quantity": 1,
		"holder": {"kind": "entity", "id": actor}, "provenance": {"source_kind": "test_injection", "created_by_fact_id": "test_injection.content.tool"}})
	var session: Variant = _session(fixture)
	var maximum := int(session.registry.get_definition("item", item_id).durability.maximum)
	var work := Work.new().resolve_work_tick(_snapshot(session), [entry.primary], _tick(12), fixture.resident_daily_life, session.registry)
	_check(session.writer.apply_results(work.results, session.stores), item_id + " works as an existing rope capability")
	_check(session.stores.item_store.get_item("test.content.tool").condition.durability == maximum - 1, item_id + " wears its own definition durability")
	var tx := Tx.new()
	tx.add_item_change({"operation": "adjust_durability", "item_instance_id": "test.content.tool", "to": 0, "source_fact_ids": ["test_injection.content.tool"]})
	tx.mark_resolved("test_injection")
	_check(session.writer.apply_result(tx, session.stores), "test injection exhausts " + item_id)
	_check(not Recipe.new(_snapshot(session), session.registry).plan_inputs(entry.primary, actor, "test.worn", 40).ok, item_id + " stops work at zero durability")
	var repair: Dictionary = fixture.resident_daily_life.maintenance_profiles.filter(func(row: Dictionary) -> bool: return row.settlement_id == entry.primary.settlement_id)[0]
	_check(Recipe.repairable(session.stores.item_store.get_item("test.content.tool"), repair.work_recipe.repairs[0], _snapshot(session)), item_id + " uses existing limited-repair capability")
	tx = Tx.new()
	for pair: Array in [["location_id", repair.workplace_id], ["daily_intent_id", "repair:" + str(repair.work_recipe.recipe_id)],
		["livelihood_elapsed_hours", 0]]:
		Life.set_state(tx, actor, pair[0], pair[1])
	tx.mark_resolved("test_injection")
	_check(session.writer.apply_result(tx, session.stores), "test injection places worn tool at repair site")
	var stock := str(repair.resource_inputs[0].stock_id)
	var before_material := float(_snapshot(session).get_resource_stock(stock).current)
	for hour: int in [14, 15]:
		var result := Work.new().resolve_work_tick(_snapshot(session), session.npc_livelihood_profiles, _tick(hour), fixture.resident_daily_life, session.registry)
		_check(session.writer.apply_results(result.results, session.stores), item_id + " commits real repair labor")
	var fixed: Dictionary = session.stores.item_store.get_item("test.content.tool")
	_check(fixed.condition.durability == 2 and _snapshot(session).get_resource_stock(stock).current == before_material - 1, item_id + " consumes fiber and restores only two durability")
	fixed.condition.durability = 0
	_check(not Recipe.repairable(fixed, repair.work_recipe.repairs[0], _snapshot(session)), item_id + " cannot repair indefinitely")


func _incident_case(base: Dictionary) -> void:
	var session: Variant = _session(base)
	var target := _setup_local(session)
	var before := _signature(session)
	var rows := Life.options(session)
	_check(_signature(session) == before, "observing conditional incidents does not mutate the world")
	var choices := rows.filter(func(row: Dictionary) -> bool: return row.get("incident_id") == "food_at_hand")
	_check(choices.size() == 2, "local food need offers sale and gift, not a mandatory story")
	if choices.size() != 2:
		return
	var selected: Dictionary = choices.filter(func(row: Dictionary) -> bool: return row.action_id.ends_with(":offer"))[0]
	_check(str(selected.wrapped_action_id).begins_with("sell_food:" + target), "incident identifies the actual present buyer")
	var coins := Life.Treasury.new(_snapshot(session)).balance("player")
	var amount: int = selected.offer.unit_price * selected.quantity
	var outcome := Life.execute(session, selected.action_id)
	_check(outcome.success and outcome.get("incident_recorded", false), "incident executes the real food sale once")
	_check(Life.Treasury.new(_snapshot(session)).balance("player") == coins + amount, "incident awards no invented money beyond actual payment")
	_check(not Life.options(session).any(func(row: Dictionary) -> bool: return row.get("incident_id") == "food_at_hand"), "resolved incident disappears during its cooldown")
	_check(not Life.execute(session, selected.action_id).success, "stale incident cannot be clicked indefinitely")
	_check(not Life.observed_followups(session).is_empty(), "underlying recipient meal remains visible")
	_check(session.save_to_path("user://tests/world_content/incident.json").ok, "incident saves natively")
	var loaded := Session.new()
	var restored: Dictionary = loaded.load_from_path("user://tests/world_content/incident.json")
	_check(restored.success, "incident restores: " + str(restored.get("error", "")))
	_check(restored.success and not Life.options(loaded).any(func(row: Dictionary) -> bool: return row.get("incident_id") == "food_at_hand"), "native load preserves incident cooldown")


func _choice_case(base: Dictionary) -> void:
	var entry := _profile(base, "recipe.smoke_lake_fish")
	var fixture := _at_work(base, str(entry.actor), entry.primary)
	_entity(fixture, str(entry.actor)).states.daily_intent_id = "recipe:recipe.smoke_lake_fish"
	var session: Variant = _session(fixture)
	var snapshot: Variant = _snapshot(session)
	var actor: Dictionary = snapshot.get_entity(str(entry.actor))
	_check(Life.Work.need_for_profile(snapshot, actor, entry.primary).is_empty(), "previous processing intent does not make raw fishing falsely lack inputs")
	_check(not Life.Work.need_for_profile(snapshot, actor, entry.variant).is_empty(), "processing still requires owned raw fish")
	_check(not Life.Work.knows_work_blocked(snapshot, actor, entry.primary, _tick(12)), "possible base work remains a candidate")
	var demand := Life.Work.need(snapshot, actor, [entry.primary])
	actor.states.daily_intent_id = demand.intent_id
	_check(str(demand.intent_id).begins_with("work_supply:"), "procurement intent retains the selected recipe")
	_check(Life.Work.assigned_profile(actor, [entry.primary]).work_recipe.recipe_id == entry.variant.work_recipe.recipe_id, "arriving to buy material does not revert to the primary recipe")
	_check(Life.Work.need(snapshot, actor, [entry.primary]).query == demand.query, "same real material is still needed at procurement time")
	_check("鲜鱼×3" in Recipe.input_summary(entry.variant, session.registry) and "无需消耗工具耐久" in Recipe.input_summary(entry.variant, session.registry), "decision information names actual material cost, not invented tool wear")


func _worn_incident_case(base: Dictionary) -> void:
	for response: String in ["gather", "work"]:
		var session: Variant = _session(base)
		var route: Dictionary = session.get_travel_options().filter(func(row: Dictionary) -> bool: return str(row.route_id).ends_with("commons_to_fishery"))[0]
		_check(session.travel(route.route_id).success, "worn-tool case reaches the fishery through ordinary travel")
		var tx := Tx.new()
		tx.add_fact({"fact_id": "test_injection.frayed_cord", "fact_type": "test_injection", "summary": "测试注入：旅人在渔场持有最后一格耐久的细苇绳。"})
		tx.add_item_change({"operation": "create", "item": {"item_instance_id": "test.frayed_cord", "item_def_id": "item.light_reed_cord",
			"holder": {"kind": "entity", "id": "player"}, "quantity": 1, "condition": {"durability": 1}}, "source_fact_ids": ["test_injection.frayed_cord"]})
		tx.mark_resolved("test_injection")
		_check(session.writer.apply_result(tx, session.stores), "explicit worn-tool setup")
		var choices := Life.options(session).filter(func(row: Dictionary) -> bool: return row.get("incident_id") == "fraying_cord")
		_check(choices.size() == 2 and choices.all(func(row: Dictionary) -> bool: return row.can_execute), "worn cord offers paid-in-time work and tool-free gathering")
		var result := Life.execute(session, "incident:fraying_cord:" + response)
		_check(result.success, "worn incident executes underlying " + response)
		_check(session.stores.item_store.get_item("test.frayed_cord").condition.durability == (1 if response == "gather" else 0), "alternative changes actual tool consumption: " + response)
		_check(not Life.options(session).any(func(row: Dictionary) -> bool: return row.get("incident_id") == "fraying_cord"), "worn incident resolves without forcing another step")


func _material_purchase_case(base: Dictionary) -> void:
	var fisher := _profile(base, "recipe.smoke_lake_fish")
	var craft := _profile(base, "recipe.reed_cordage")
	var buyer := str(fisher.actor)
	var seller := str(craft.actor)
	var fixture := _at_work(base, seller, craft.primary)
	_entity(fixture, buyer).states.merge({"location_id": craft.primary.workplace_id, "daily_intent_id": "work_supply:recipe.smoke_lake_fish",
		"daily_activity": "seeking_work", "daily_route_id": ""}, true)
	fixture.known_facts.append({"fact_id": "test_injection.processing_market", "fact_type": "test_injection", "summary": "测试注入：加工者到场采购，摊主持有三份鲜鱼；沿用双方原有的钱。"})
	fixture.initial_items.append({"item_instance_id": "test.market.fish", "item_def_id": "item.fresh_fish_portion", "quantity": 3,
		"holder": {"kind": "entity", "id": Storage.depot_id(seller)}, "provenance": {"source_kind": "test_injection", "created_by_fact_id": "test_injection.processing_market"}})
	var session: Variant = _session(fixture)
	var unfunded := Life.Work.plan_purchase(_snapshot(session), _snapshot(session).get_entity(buyer), session.npc_livelihood_profiles, session.stores, _tick(12))
	_check(unfunded.get("event", {}).get("reason") == "unaffordable", "processing material can be available but unaffordable")
	var funding := Tx.new()
	for item: Dictionary in session.stores.item_store.list_items_for_owner(seller):
		if item.item_def_id == "item.copper_coin":
			funding.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id,
				"new_holder": {"kind": "entity", "id": buyer}, "source_fact_ids": ["test_injection.processing_market"]})
	funding.mark_resolved("test_injection")
	_check(session.writer.apply_result(funding, session.stores), "funded counterexample transfers existing seller money, never mints it")
	var before_buyer := Life.Treasury.new(_snapshot(session)).balance(buyer)
	var before_seller := Life.Treasury.new(_snapshot(session)).balance(seller)
	var plan := Life.Work.plan_purchase(_snapshot(session), _snapshot(session).get_entity(buyer), session.npc_livelihood_profiles, session.stores, _tick(12))
	_check(plan.has("event") and plan.event.fact_type == "work_supply_purchased", "processing intent buys raw material, not a replacement rope")
	if not plan.has("event") or plan.event.fact_type != "work_supply_purchased":
		print("PROCESSING_PURCHASE_DIAGNOSTIC " + JSON.stringify({"plan": plan.get("event", {}), "buyer_coins": before_buyer, "demand": Life.Work.need(_snapshot(session), _snapshot(session).get_entity(buyer), session.npc_livelihood_profiles)}))
		return
	_check(session.writer.apply_result(plan.transaction, session.stores), "processing material purchase commits")
	var cost := before_buyer - Life.Treasury.new(_snapshot(session)).balance(buyer)
	_check(cost > 0 and Life.Treasury.new(_snapshot(session)).balance(seller) - before_seller == cost, "material acquisition transfers existing money")
	_check(_quantity(session, buyer, "item.fresh_fish_portion") == 3, "buyer physically carries all three processing inputs")
	_check(Life.Work.need(_snapshot(session), _snapshot(session).get_entity(buyer), session.npc_livelihood_profiles).is_empty(), "correct recipe shortage clears after actual purchase")
	_check(not Recipe.new(_snapshot(session), session.registry).plan_inputs(fisher.variant, buyer, "test.remote", 40).ok, "purchase site does not remotely execute the processing job")


func _market_product_case(source: Variant, seller: String, item_id: String) -> void:
	var session := Session.new()
	_check(session.load_from_save_envelope(source.build_save_envelope()).success, "produced food market branch uses native state")
	var view: Variant = _snapshot(session)
	var buyers: Array = view.get_entities_by_type("person").filter(func(row: Dictionary) -> bool:
		return row.id != seller and int(row.states.get("age_years", 0)) >= 18 and Life.Treasury.new(view).balance(str(row.id)) >= 6)
	_check(not buyers.is_empty(), "food market test finds an existing funded buyer")
	if buyers.is_empty():
		return
	var buyer := str(buyers[0].id)
	var tx := Tx.new()
	Life.set_state(tx, buyer, "location_id", view.get_entity(seller).states.location_id)
	Life.set_state(tx, buyer, "daily_route_id", "")
	Life.set_state(tx, buyer, "hunger", "high")
	tx.mark_resolved("test_injection")
	_check(session.writer.apply_result(tx, session.stores), "test injection brings actual buyer to food seller")
	view = _snapshot(session)
	var offers: Array = Life.Work.stock_offers(view, view.get_entity(seller), buyer, session.npc_livelihood_profiles, session.stores).filter(func(row: Dictionary) -> bool: return row.item.item_def_id == item_id)
	_check(not offers.is_empty(), item_id + " automatically receives a real market quote")
	if offers.is_empty():
		return
	var offer: Dictionary = offers[0]
	var old_coins := Life.Treasury.new(view).balance(buyer)
	var seller_coins := Life.Treasury.new(view).balance(seller)
	var plan := Life.Work.Market.new().plan_trade(offer.policy, {"buyer_entity_id": buyer, "item_instance_id": offer.item_instance_id,
		"quantity": 1, "quoted_unit_price": offer.unit_price, "maximum_total_price": old_coins,
		"exchange_id": "test.exchange.processed_food", "purpose_id": "ordinary_food_purchase", "source_fact_ids": []}, session.stores, {"elapsed_hours": 50, "day": 2})
	_check(plan.success and session.writer.apply_result(plan.transaction, session.stores), item_id + " sells through ordinary market transaction")
	_check(_quantity(session, buyer, item_id) == 1 and Life.Treasury.new(_snapshot(session)).balance(buyer) == old_coins - int(offer.unit_price)
		and Life.Treasury.new(_snapshot(session)).balance(seller) == seller_coins + int(offer.unit_price), item_id + " has physical ownership and exact payer/seller money")
	var meals := Work.new().resolve_household_support(_snapshot(session), _tick(20), session.fixture_source_data.resident_daily_life)
	_check(session.writer.apply_results(meals.results, session.stores), item_id + " purchased batch enters real meals")
	_check(_quantity(session, buyer, item_id) == 0, item_id + " purchased food is consumed rather than only logged")


func _validation_cases(base: Dictionary) -> void:
	var pack: Dictionary = base.content_extension
	for mutation: String in ["unknown_item_effect", "unknown_npc_need", "unknown_monster_behavior", "unknown_incident_result", "unknown_work_field", "duplicate_npc", "invalid_mass"]:
		var changed := pack.duplicate(true)
		match mutation:
			"unknown_item_effect": changed.item_defs[0]["nutrition_magic"] = 10
			"unknown_npc_need": changed.resident_variants[0].states["ambition"] = 10
			"unknown_monster_behavior": changed.world_danger.threat["teleport"] = true
			"unknown_incident_result": changed.incidents[0].responses[0]["reward"] = 10
			"unknown_work_field": changed.work_rules.overrides[0]["bonus_money"] = 10
			"duplicate_npc": changed.resident_variants.append(changed.resident_variants[0])
			"invalid_mass": changed.item_defs[0].base_mass = INF
		_check(Content.validate(changed) != "", mutation + " rejected instead of ignored")
	for bad_product: Variant in [{}, {"quantity": 1}, {"quantity": 1, "item_def_id": "item.missing"}, 7]:
		var malformed := base.duplicate(true)
		malformed.work_rules.overrides[0].recipe_variants[0].products = [bad_product]
		_check(WorkRules.configure(malformed, _registry_for(base)) == "invalid_recipe_variant_product", "malformed variant output fails before trait compilation")
	var changed := base.duplicate(true)
	changed.content_extension.item_defs[0].base_value += 1
	_check(not Session.new().start_from_fixture_data(changed, []).success, "changed definition cannot reuse an old compiled content marker")
	changed = base.duplicate(true)
	changed.world_danger.threat.start_hour += 1
	_check(not Session.new().start_from_fixture_data(changed, []).success, "embedded content and compiled danger cannot diverge")
	var options := OPTIONS.duplicate(true)
	options.erase("content_extension_version")
	var legacy := Live.new()
	_check(legacy.start(options).success and not legacy.session.registry.has_definition("item", "item.smoked_lake_fish"), "old v2 worlds do not silently acquire new items or recipes")


func _registry_for(base: Dictionary) -> Variant:
	var session := Session.new()
	session.start_from_fixture_data(base, [])
	return session.registry


func _finish() -> void:
	print("WORLD_CONTENT_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
