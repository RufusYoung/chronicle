extends "res://tests/sim/world_integration_contract_test.gd"

const Equipment = preload("res://scripts/sim/player/player_equipment.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Danger = preload("res://scripts/sim/combat/world_danger_system.gd")


func run() -> void:
	var model := Live.new()
	var settings := options()
	settings.integration_rules_version = 2
	var started: Dictionary = model.start(settings)
	check(started.get("success", false), "adventure world starts: " + str(started.get("error", "")))
	if not model.session.initialized:
		quit(1)
		return
	var session: Variant = model.session
	check(session.fixture_source_data.integration_rules.item_defs.size() == 12, "twelve equipment definitions in explicit bootstrap")
	check(session.registry.list_definitions("skill").has("skill.coast_craft"), "craft growth registered")
	var path := "user://tests/world_adventure_contract/initial.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(model.save_to_path(path, true).success, "adventure native save")
	var restored := Live.new()
	var loaded: Dictionary = restored.load_from_path(path)
	check(loaded.get("success", false), "adventure native restore: " + str(loaded.get("error", "")))
	var old := Live.new()
	check(old.start(options()).success, "previous integration remains usable")
	check(not old.session.registry.has_definition("skill", "skill.coast_craft"), "old worlds do not gain new progression")
	_equipment_boundaries(model.session)
	_trade_boundaries(model.session)
	_legal_crafting(model)
	_legal_subsistence_growth(settings)
	print("WORLD_ADVENTURE_CONTRACT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _legal_subsistence_growth(settings: Dictionary) -> void:
	var model := Live.new()
	check(model.start(settings).success, "fresh subsistence growth world")
	check(model.perform_travel("generated_route.echo_landing.commons_to_fishery").success, "reach real food source")
	check(model.act_player_life("gather:net_fisher").get("work_completed", false), "complete real subsistence")
	var journal := Equipment.journal(model.session)
	check(journal.features[1].state == "0级 · 4/8经验", "arrival and actual food gathering both grant survival practice")
	check(model.latest_result.get("growth_feedback", []).any(func(row: String) -> bool: return "行路经验" in row), "gathering growth is visible immediately")
	var store: Variant = model.session.stores.character_feature_store
	var has_npc_growth := false
	var snapshot: Variant = Builder.new().build_snapshot(model.session.context, model.session.stores, true)
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		if str(person.id).begins_with("generated_resident."):
			has_npc_growth = has_npc_growth or store.list_skill_progress(person.id).any(func(row: Dictionary) -> bool:
				return row.skill_def_id == "skill.coast_survival" and row.practice_xp > 0)
	check(has_npc_growth, "resident actual travel uses the same growth definition")


func _legal_crafting(model: Variant) -> void:
	var session: Variant = model.session
	var routes: Array = session.get_travel_options()
	for route: Dictionary in routes:
		if str(route.route_id).ends_with("commons_to_reed_craft"):
			check(model.perform_travel(route.route_id).success, "legal journey to local workshop")
	while session.stores.state_store.get_state(str(session.context.actor_id), "daily_travel_remaining", 0) > 0:
		check(model.act_player_life("continue").success, "legal journey continuation")
	var advanced: Array = session.PlayerLife.options(session, false).filter(func(o: Dictionary) -> bool: return o.action_id == "work:recipe.bound_reed_pike")
	check(advanced.size() == 1 and not advanced[0].can_execute and "1级" in str(advanced[0].blocked_reason), "untrained player sees explicit recipe requirement")
	var crafted: Dictionary = model.act_player_life("work:recipe.hand_twist_cord")
	check(crafted.get("work_completed", false), "legal handwork makes first tool from finite local reeds: " + str(crafted))
	var club: Dictionary = model.act_player_life("work:recipe.woven_sap")
	check(club.get("work_completed", false), "legal crafting creates weapon and wears the actual cord")
	var journal := Equipment.journal(session)
	check(journal.features[0].state == "1级 · 8/24经验", "two real completed recipes unlock craft rank one")
	var owned: Array = session.stores.item_store.list_items_for_owner(str(session.context.actor_id))
	check(owned.any(func(i: Dictionary) -> bool: return i.item_def_id == "item.light_reed_cord" and int(i.condition.durability) == 1), "first tool really lost one durability")
	var equip: Array = Equipment.options(session).filter(func(o: Dictionary) -> bool: return str(o.action_id).begins_with("equip:"))
	check(equip.size() == 1, "new weapon has a legal equip action")
	if equip.is_empty():
		return
	var id := str(equip[0].action_id)
	var equipped: Dictionary = model.act_player_life(id)
	check(equipped.get("success", false), "player wears produced weapon through formal action: " + str(equipped.get("error", "")))
	check(not model.act_player_life(id).get("success", true), "repeated equip action is no longer available")
	check(session.stores.equipment_store.get_equipped_item_id(str(session.context.actor_id), "main_hand") == equip[0].item_instance_id, "canonical slot holds real crafted object")
	var checkpoint := "user://tests/world_adventure_contract/crafted.json"
	check(model.save_to_path(checkpoint, true).success, "save real craft, experience, wear and equipment")
	var restored := Live.new()
	check(restored.load_from_path(checkpoint).get("success", false), "restore real craft progression")
	check(Equipment.journal(restored.session) == Equipment.journal(session), "native journal exactly preserves growth and equipment")
	check(model.act_player_life("unequip:main_hand").get("success", false), "player can take equipment off")
	check(session.stores.item_store.get_item(equip[0].item_instance_id).holder.id == session.context.actor_id, "unequip does not destroy or transfer item")


func _equipment_boundaries(base: Variant) -> void:
	var fixture: Dictionary = base.fixture_source_data.duplicate(true)
	fixture.initial_equipment_loadouts = []
	fixture.known_facts.append({"fact_id": "test.adventure_gear", "fact_type": "test_injection", "summary": "测试注入：逐一验证装备条件和槽位，不是自然获取证据。"})
	for definition: Dictionary in fixture.integration_rules.item_defs:
		fixture.initial_items.append({"item_instance_id": "test." + str(definition.item_def_id), "item_def_id": definition.item_def_id,
			"holder": {"kind": "entity", "id": "player"}, "quantity": 1})
	var session := Session.new()
	var started := session.start_from_fixture_data(fixture, base.rule_source_paths)
	check(started.get("success", false), "controlled all-gear counterexample starts: " + str(started.get("error", "")))
	if not started.get("success", false):
		return
	var combat := Danger.Combat.new()
	combat.configure(session.registry)
	var system := Danger.new()
	for definition: Dictionary in fixture.integration_rules.item_defs:
		var slot := str(definition.equip_slots[0])
		var snapshot: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
		var threat: Dictionary = snapshot.get_entity("world_threat.field_boar")
		var encounter := system.definition(snapshot, "player", threat, fixture.world_danger)
		var before := {}
		for approach: String in ["attack", "guard", "withdraw"]:
			before[approach] = combat.preview(encounter, snapshot, approach, "player").effective_score
		var change := Result.new()
		change.add_equipment_change({"operation": "equipment_set", "entity_id": "player", "slot_id": slot,
			"item_instance_id": "test." + str(definition.item_def_id), "source_fact_ids": ["test.adventure_gear"]})
		change.mark_resolved("test_injection")
		check(session.writer.apply_result(change, session.stores), "every defined gear fits its canonical slot: " + str(definition.display_name))
		snapshot = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
		var changed := false
		for approach: String in ["attack", "guard", "withdraw"]:
			changed = changed or combat.preview(encounter, snapshot, approach, "player").effective_score != before[approach]
		check(changed, "real combat consumer reads gear: " + str(definition.display_name))
		var clear := Result.new()
		clear.add_equipment_change({"operation": "equipment_clear", "entity_id": "player", "slot_id": slot, "source_fact_ids": ["test.adventure_gear"]})
		clear.mark_resolved("test_injection")
		check(session.writer.apply_result(clear, session.stores), "controlled equipment cleanup")
	check(not session.PlayerLife.execute(session, "equip:not_owned:main_hand").get("success", true), "forged item action rejected")


func _trade_boundaries(base: Variant) -> void:
	var fixture: Dictionary = base.fixture_source_data.duplicate(true)
	var buyer := "generated_resident.echo_landing.002"
	var depot := ""
	for entity: Dictionary in fixture.entities:
		if entity.get("stock_custodian_id") == buyer:
			depot = str(entity.id)
		if entity.id == buyer:
			entity.states.location_id = fixture.player.location_id if fixture.player.has("location_id") else "generated_location.echo_landing.commons"
			entity.states.daily_route_id = ""
	fixture.initial_items = fixture.initial_items.filter(func(i: Dictionary) -> bool:
		return i.holder.id not in [buyer, depot] or "rope" not in base.registry.get_definition("item", i.item_def_id).get("tags", []))
	fixture.initial_items.append({"item_instance_id": "test.player.sale_cord", "item_def_id": "item.light_reed_cord",
		"quantity": 1, "holder": {"kind": "entity", "id": "player"}})
	fixture.known_facts.append({"fact_id": "test.sale_cord", "fact_type": "test_injection", "summary": "测试注入：把缺工具的买方与持有现货的旅人放在一起；不冒称自然成交。"})
	var session := Session.new()
	var started := session.start_from_fixture_data(fixture, base.rule_source_paths)
	check(started.get("success", false), "controlled local tool trade starts")
	if not started.get("success", false):
		return
	var view: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	var sales: Array = session.PlayerLife.WorkTrade.options(session, view, view.get_entity("player"))
	sales = sales.filter(func(o: Dictionary) -> bool: return o.recipient_id == buyer and o.item_id == "test.player.sale_cord")
	check(sales.size() == 1, "actual missing tool creates one finite offer")
	if sales.is_empty():
		return
	var coins := session.PlayerLife.Food.balance(view.get_items_for_holder("player"), "player")
	var buyer_coins := session.PlayerLife.Food.balance(view.get_items_for_holder(buyer), buyer)
	check(sales[0].can_execute, "buyer can pay actual quote")
	var sold: Dictionary = session.PlayerLife.execute(session, sales[0].action_id)
	check(sold.get("success", false), "tool sale uses formal player action: " + str(sold.get("error", "")))
	view = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	check(session.PlayerLife.Food.balance(view.get_items_for_holder("player"), "player") - coins == int(sales[0].unit_price), "player receives existing buyer money")
	check(buyer_coins - session.PlayerLife.Food.balance(view.get_items_for_holder(buyer), buyer) == int(sales[0].unit_price), "same payment leaves buyer purse")
	check(view.get_item("test.player.sale_cord").holder.id == buyer, "tool reaches real buyer")
	check(not session.PlayerLife.execute(session, sales[0].action_id).get("success", true), "same item cannot be sold twice")
	for hour: int in range(24):
		var step: Dictionary = session.advance_time(1, "passive_after_controlled_sale")
		if not step.get("success", false):
			check(false, "world continues after controlled sale: " + str(step.get("error", "")))
			break
	var used: Array = session.stores.fact_store.list_facts().filter(func(f: Dictionary) -> bool:
		return f.get("actor_id") == buyer and f.get("tools_used", []).any(func(t: Dictionary) -> bool:
			return t.get("item_instance_id") == "test.player.sale_cord"))
	if used.is_empty():
		check(session.stores.item_store.get_item("test.player.sale_cord").holder.id == buyer,
			"counterexample: hunger can postpone work; purchased tool remains real property, not automatic production")
	print("CONTROLLED_TRADE_AUTONOMOUS_USES " + str(used.size()))
	var profile: Dictionary = session.npc_livelihood_profiles.filter(func(p: Dictionary) -> bool:
		return p.occupation_id == "reed_weaver" and p.settlement_id == "generated_settlement.echo_landing")[0]
	var ready := Result.new()
	ready.add_fact({"fact_id": "test.ready_after_sale", "fact_type": "test_injection", "summary": "测试注入：单独验证已购买工具的真实生产消费者；到场、身体和临近完工状态受控，不是自然复工。"})
	var values := {"location_id": profile.workplace_id, "daily_route_id": "", "daily_activity": "working",
		"daily_intent_id": "recipe:" + str(profile.work_recipe.recipe_id), "work_elapsed_recipe_id": profile.work_recipe.recipe_id,
		"livelihood_elapsed_hours": int(profile.work_interval_hours) - 1, "fatigue": 0, "hunger": "none", "health": 100}
	for key: String in values:
		ready.add_state_change({"entity_id": buyer, "key": key, "to": values[key]})
	ready.mark_resolved("test_injection")
	check(session.writer.apply_result(ready, session.stores), "controlled ready-to-work consumer state")
	view = session.PlayerLife.snapshot(session.context, session.stores, {"day": 3, "hour": 12})
	var resolved: Dictionary = session.PlayerLife.Livelihood.new().resolve_work_tick(view, [profile],
		{"day": 3, "hour": 12, "elapsed_hours": 1, "tick_event_id": "test.ready_after_sale"},
		session.fixture_source_data.resident_daily_life, session.registry)
	check(session.writer.apply_results(resolved.results, session.stores), "ordinary production consumes purchased tool through transaction")
	check(int(session.stores.item_store.get_item("test.player.sale_cord").condition.durability) < 2,
		"controlled consumer really wears purchased item, not a substitute")
