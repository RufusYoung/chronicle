extends "res://tests/sim/world_danger_contract_test.gd"

const IntegrationOptions = preload("res://tests/sim/world_integration_contract_test.gd")
const Gear = preload("res://scripts/sim/equipment/resident_equipment.gd")
const Opportunities = preload("res://scripts/sim/economy/resident_work_opportunities.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")


func _run() -> void:
	var live := Live.new()
	_check(live.start(IntegrationOptions.options()).success, "integrated equipment fixture starts")
	if not live.is_ready():
		_finish()
		return
	var fixture: Dictionary = live.session.fixture_source_data.duplicate(true)
	var buyer := "generated_resident.echo_terrace.001"
	var seller := "generated_resident.echo_landing.002"
	var site := str(_entity(fixture, seller).states.workplace_id)
	fixture.world_time = {"day": 3, "hour": 12}
	_entity(fixture, buyer).states.merge({"location_id": site, "daily_route_id": "", "daily_activity": "seeking_work", "daily_intent_id": "work_supply:equipment:body_outer"}, true)
	_entity(fixture, seller).states.merge({"location_id": site, "daily_route_id": "", "daily_activity": "working"}, true)
	fixture.known_facts.append({"fact_id": "test_injection.gear", "fact_type": "test_injection", "summary": "测试注入：到场、现货和危险记忆反例；不是自然生产证据。"})
	fixture.initial_items.append({"item_instance_id": "test.gear.vest", "item_def_id": "item.woven_reed_vest", "quantity": 1, "holder": {"kind": "entity", "id": Storage.depot_id(seller)}})
	var session: Variant = _session(fixture)
	if not session.initialized:
		_finish()
		return
	var tick := {"day": 3, "hour": 12}
	_check(Gear.need(_snapshot(session), _snapshot(session).get_entity(buyer)).is_empty(), "unseen danger does not invent a purchase")
	var remembered := Result.new()
	var threat: Dictionary = _snapshot(session).get_entity("world_threat.field_boar")
	var contact: Dictionary = Danger._fact("world_danger_contact", buyer, {"day": 2, "hour": 12}, threat, "测试注入：先前亲见危险")
	remembered.add_fact(contact)
	Danger._remember(remembered, buyer, threat, {"day": 2, "hour": 12}, fixture.world_danger, contact.fact_id)
	_check(session.writer.apply_result(remembered, session.stores), "test injection: prior encounter memory")
	_spare_sale_case(fixture, remembered, buyer, seller)
	var snapshot: Variant = _snapshot(session)
	_check(Gear.need(snapshot, snapshot.get_entity(buyer)).get("recipe_id") == "equipment:body_outer", "known danger creates armor demand")
	var remote: Variant = _snapshot(session)
	remote.entities = remote.entities.duplicate(true)
	for entity: Dictionary in remote.entities:
		if entity.id == seller:
			entity.states.location_id = entity.states.home_location_id
	var missed := Opportunities.plan_purchase(remote, remote.get_entity(buyer), [], session.stores, tick)
	_check(missed.get("event", {}).get("reason") == "no_local_surplus", "absent seller prevents remote purchase of visible depot stock")
	var poor: Variant = _session(fixture)
	_check(poor.writer.apply_result(remembered, poor.stores), "test injection: same prior danger in affordability branch")
	var transfer := Result.new()
	for money: Dictionary in poor.stores.item_store.list_items_for_owner(buyer):
		if money.item_def_id == Food.CURRENCY:
			transfer.add_item_change({"operation": "transfer", "item_instance_id": money.item_instance_id,
				"expected_holder": money.holder, "new_holder": {"kind": "entity", "id": seller}, "source_fact_ids": ["test_injection.gear"]})
	transfer.mark_resolved("test_injection")
	_check(poor.writer.apply_result(transfer, poor.stores), "test injection: transfer buyer's cash without destroying currency")
	missed = Opportunities.plan_purchase(_snapshot(poor), _snapshot(poor).get_entity(buyer), [], poor.stores, tick)
	_check(missed.get("event", {}).get("reason") == "unaffordable", "real lack of coins prevents otherwise available gear purchase")
	var before := Food.balance(snapshot.get_items_for_holder(buyer), buyer)
	var seller_before := Food.balance(snapshot.get_items_for_holder(seller), seller)
	var plan := Opportunities.plan_purchase(snapshot, snapshot.get_entity(buyer), [], session.stores, tick)
	_check(plan.has("transaction") and plan.get("event", {}).get("fact_type") == "work_supply_purchased", "physical seller and real stock produce quote")
	if not plan.has("transaction"):
		_finish()
		return
	_check(session.writer.apply_result(plan.transaction, session.stores), "ordinary market transaction buys armor")
	snapshot = _snapshot(session)
	var paid := before - Food.balance(snapshot.get_items_for_holder(buyer), buyer)
	_check(paid > 0 and Food.balance(snapshot.get_items_for_holder(seller), seller) - seller_before == paid, "payment conserved between buyer and actual seller")
	_check(snapshot.get_item("test.gear.vest").holder.id == buyer, "purchased item changes physical holder")
	var worn: Variant = Gear.equip(snapshot, snapshot.get_entity(buyer), tick)
	_check(session.writer.apply_result(worn, session.stores), "resident wears owned armor")
	snapshot = _snapshot(session)
	_check(snapshot.get_equipment_loadout(buyer).slots["slot.body_outer"] == "test.gear.vest", "canonical body slot used")
	_check(Gear.equip(snapshot, snapshot.get_entity(buyer), tick).is_empty(), "equipped item does not emit infinite repeated actions")
	_check(Opportunities.reserved_for_work(snapshot, snapshot.get_entity(buyer), {}, Storage.depot_id(buyer)).get("test.gear.vest") == 1, "worn item is not offered for sale")
	var repair: Dictionary = fixture.resident_daily_life.maintenance_profiles.filter(func(p: Dictionary) -> bool: return str(p.work_recipe.recipe_id).begins_with("recipe.patch_fiber_gear"))[0]
	var item: Dictionary = snapshot.get_item("test.gear.vest")
	_check(not Recipe.repairable(item, repair.work_recipe.repairs[0], snapshot), "intact armor cannot consume a repair allowance")
	item.condition.durability = 3
	_check(Recipe.repairable(item, repair.work_recipe.repairs[0], snapshot), "worn but unbroken armor can be repaired")
	_check(not Recipe.repairable(item, {"query": {"tags_all": ["fiber_gear"]}, "restore": 4, "maximum_repairs": 2}, snapshot), "legacy repair remains broken-only")
	_lantern_case(fixture, buyer)
	_check(session.save_to_path("user://tests/world_integration_contract/equipment.json").ok, "native equipment purchase save")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/world_integration_contract/equipment.json").get("success", false), "native equipment and payment restore")
	_data_only_case()
	_maintenance_case(live.session.fixture_source_data, buyer)
	_finish()


func _spare_sale_case(base: Dictionary, memory: Variant, buyer: String, seller: String) -> void:
	var fixture := base.duplicate(true)
	for item: Dictionary in fixture.initial_items:
		if item.item_instance_id == "test.gear.vest":
			item.holder.id = seller
	fixture.initial_equipment_loadouts.append({"entity_id": seller, "slots": {"body_outer": "test.gear.vest"}})
	fixture.initial_items.append({"item_instance_id": "test.gear.old_vest", "item_def_id": "item.woven_reed_vest",
		"quantity": 1, "holder": {"kind": "entity", "id": seller}, "condition": {"durability": 10, "maximum_durability": 16}})
	var session: Variant = _session(fixture)
	_check(session.writer.apply_result(memory, session.stores), "test injection: same danger in spare equipment branch")
	var snapshot: Variant = _snapshot(session)
	var offers := Opportunities.stock_offers(snapshot, snapshot.get_entity(seller), buyer, [], session.stores)
	_check(offers.any(func(o: Dictionary) -> bool: return o.item_instance_id == "test.gear.old_vest"),
		"personally carried spare equipment is saleable after upgrade")
	_check(not offers.any(func(o: Dictionary) -> bool: return o.item_instance_id == "test.gear.vest"),
		"currently worn armor remains reserved during spare sale")
	var plan := Opportunities.plan_purchase(snapshot, snapshot.get_entity(buyer), [], session.stores, {"day": 3, "hour": 12})
	_check(plan.get("event", {}).get("fact_type") == "work_supply_purchased", "spare produces ordinary physical quote")
	if plan.get("event", {}).get("fact_type") == "work_supply_purchased":
		_check(session.writer.apply_result(plan.transaction, session.stores), "spare trade commits through ordinary market")
		_check(session.stores.item_store.get_item("test.gear.old_vest").holder.id == buyer,
			"spare changes ownership without stripping seller's worn equipment")


func _lantern_case(base: Dictionary, actor: String) -> void:
	var fixture := base.duplicate(true)
	fixture.initial_items.append({"item_instance_id": "test.gear.lantern", "item_def_id": "item.patrol_lantern", "quantity": 1, "holder": {"kind": "entity", "id": actor}})
	fixture.initial_equipment_loadouts.append({"entity_id": actor, "slots": {"utility": "test.gear.lantern"}})
	var session: Variant = _session(fixture)
	if not session.initialized:
		return
	var snapshot: Variant = _snapshot(session)
	var threat: Dictionary = snapshot.get_entity("world_threat.field_boar")
	var resolver := Danger.Combat.new()
	resolver.configure(session.registry)
	var system := Danger.new()
	snapshot.world_time.hour = 12
	var day: Dictionary = resolver.preview(system.definition(snapshot, actor, threat, fixture.world_danger), snapshot, "withdraw", actor)
	snapshot.world_time.hour = 20
	var night: Dictionary = resolver.preview(system.definition(snapshot, actor, threat, fixture.world_danger), snapshot, "withdraw", actor)
	_check(int(night.get("effective_score", 0)) - int(day.get("effective_score", 0)) == 2, "lantern retreat passive changes real preview only in dim light")


func _data_only_case() -> void:
	var old := Live.new()
	var options := IntegrationOptions.options()
	options.erase("integration_rules_version")
	_check(old.start(options).success, "pre-integration bootstrap for data extension")
	var fixture: Dictionary = old.session.fixture_source_data.duplicate(true)
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim/raw/content/echo_port_integration_v1.json"))
	var definition: Dictionary = pack.item_defs[1].duplicate(true)
	definition.item_def_id = "item.test_fiber_guard"
	definition.display_name = "测试纤维护片"
	definition.modifiers[0].value = 3
	pack.item_defs.append(definition)
	var recipe: Dictionary = pack.recipes[0].duplicate(true)
	recipe.products[0].item_def_id = definition.item_def_id
	recipe.work_recipe.recipe_id = "recipe.test_fiber_guard"
	pack.recipes.append(recipe)
	fixture["integration_rules"] = pack
	var actor := "generated_resident.echo_landing.002"
	var person: Dictionary = _entity(fixture, actor)
	person.states.merge({"location_id": person.states.workplace_id, "daily_workplace_id": person.states.workplace_id,
		"daily_activity": "working", "daily_route_id": "", "daily_intent_id": "recipe:recipe.test_fiber_guard",
		"work_elapsed_recipe_id": "recipe.test_fiber_guard", "livelihood_elapsed_hours": 5, "fatigue": 0, "health": 100}, true)
	fixture.known_facts.append({"fact_id": "test_injection.data_gear", "fact_type": "test_injection", "summary": "测试注入：新增第三种装备定义并设置作业进度，不改运行时执行器。"})
	var session: Variant = _session(fixture)
	if not session.initialized:
		return
	var profile: Dictionary = session.fixture_source_data.generated_livelihood_profiles.filter(func(p: Dictionary) -> bool:
		return p.occupation_id == person.states.occupation_id and p.settlement_id == person.states.settlement_id)[0]
	var stock := str(profile.resource_inputs[0].stock_id)
	var before := float(_snapshot(session).get_resource_stock(stock).current)
	var tool: Dictionary = _tool(session, actor)
	var result := Work.new().resolve_work_tick(_snapshot(session), [profile], _tick(12), session.fixture_source_data.resident_daily_life, session.registry)
	_check(session.writer.apply_results(result.results, session.stores), "third definition uses ordinary work executor")
	var goods: Array = _snapshot(session).get_items_for_holder(Storage.depot_id(actor)).filter(func(i: Dictionary) -> bool: return i.item_def_id == definition.item_def_id)
	_check(goods.size() == 1, "third equipment really produced into owned stock")
	_check(float(_snapshot(session).get_resource_stock(stock).current) < before, "gear production spends finite raw material")
	_check(session.stores.item_store.get_item(tool.item_instance_id).condition.durability == int(tool.condition.durability) - 1, "gear production wears one tool without eating it")
	var snapshot: Variant = _snapshot(session)
	_check(session.writer.apply_result(Gear.equip(snapshot, snapshot.get_entity(actor), _tick(12)), session.stores), "new data-only gear withdraws and equips through common system")
	snapshot = _snapshot(session)
	_check(Gear.rating(snapshot.get_item(snapshot.get_equipment_loadout(actor).slots["slot.body_outer"]), "body_outer") == 3, "new modifier reaches equipment evaluation")
	var resolver := Danger.Combat.new()
	resolver.configure(session.registry)
	var encounter := Danger.new().definition(snapshot, actor, snapshot.get_entity("world_threat.field_boar"), session.fixture_source_data.world_danger)
	var preview: Dictionary = resolver.preview(encounter, snapshot, "guard", actor)
	_check(preview.get("modifier_evaluations", []).any(func(row: Dictionary) -> bool:
		return row.get("source_id") == goods[0].item_instance_id and row.get("applied", false) and row.get("value") == 3),
		"third data-only modifier reaches actual combat consumer without item-ID branch")
	_check(session.save_to_path("user://tests/world_integration_contract/data_only.json").ok, "embedded data-only gear save")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/world_integration_contract/data_only.json").get("success", false), "embedded third definition restores without external definition file")


func _maintenance_case(base: Dictionary, actor: String) -> void:
	var fixture := base.duplicate(true)
	var person: Dictionary = _entity(fixture, actor)
	var repair: Dictionary = fixture.resident_daily_life.maintenance_profiles.filter(func(p: Dictionary) -> bool:
		return p.settlement_id == person.states.settlement_id and str(p.work_recipe.recipe_id).begins_with("recipe.patch_fiber_gear"))[0]
	person.states.merge({"location_id": repair.workplace_id, "daily_activity": "working", "daily_route_id": "", "health": 100,
		"fatigue": 0, "livelihood_elapsed_hours": 1, "daily_intent_id": "repair:" + str(repair.work_recipe.recipe_id),
		"work_elapsed_recipe_id": repair.work_recipe.recipe_id}, true)
	fixture.initial_items.append({"item_instance_id": "test.maintenance.vest", "item_def_id": "item.woven_reed_vest", "quantity": 1,
		"holder": {"kind": "entity", "id": actor}, "condition": {"durability": 3, "maximum_durability": 16}})
	fixture.known_facts.append({"fact_id": "test_injection.maintenance", "fact_type": "test_injection", "summary": "测试注入：损伤、地点和作业进度，验证实际修补材料与次数限制。"})
	var session: Variant = _session(fixture)
	if not session.initialized:
		return
	for number: int in range(3):
		var stock := str(repair.resource_inputs[0].stock_id)
		var before := float(_snapshot(session).get_resource_stock(stock).current)
		var reset := Result.new()
		reset.add_item_change({"operation": "adjust_durability", "item_instance_id": "test.maintenance.vest", "to": 3, "source_fact_ids": ["test_injection.maintenance"]})
		reset.add_state_change({"entity_id": actor, "key": "livelihood_elapsed_hours", "to": 1})
		reset.mark_resolved("test_injection")
		_check(session.writer.apply_result(reset, session.stores), "test injection: isolated repeat wear and partial labor")
		var result := Work.new().resolve_work_tick(_snapshot(session), fixture.generated_livelihood_profiles, _tick(12 + number), fixture.resident_daily_life, session.registry)
		_check(session.writer.apply_results(result.results, session.stores), "maintenance transaction commits")
		var item: Dictionary = session.stores.item_store.get_item("test.maintenance.vest")
		var after := float(_snapshot(session).get_resource_stock(stock).current)
		if number < 2:
			_check(item.condition.durability == 7 and after < before, "partial gear repair restores four condition at a real resource cost")
		else:
			_check(item.condition.durability == 3 and after == before, "repair limit prevents indefinite renewal and wasted raw material")
