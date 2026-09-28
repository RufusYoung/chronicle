extends "res://tests/sim/player_local_life_contract_test.gd"

const JourneyContract = preload("res://tests/sim/journey_content_contract_test.gd")
const Brief = preload("res://scripts/sim/player/brief_actions.gd")


func _run() -> void:
	var model := Live.new()
	var config := JourneyContract.options()
	config.journey_rules_version = 2
	var start: Dictionary = model.start(config)
	_check(start.get("success", false), "explicit adventure v3 starts: " + str(start.get("error", "")))
	if not start.get("success", false):
		_finish()
		return
	var session: Variant = model.session
	var guide: Dictionary = model.build_view_data()
	_check(not guide.journey_guidance.directions.is_empty(), "new traveler has concrete public directions before labor")
	_check(guide.travel_options[0].purpose.contains("回水洞"), "adventure route is prioritized over work")
	var target := _setup_local(session)
	var tx := Tx.new()
	Life.set_state(tx, target, "hunger", "low")
	var depot := Local.Storage.stock_holder(session.get_snapshot(), target)
	if depot != "":
		for item: Dictionary in session.stores.item_store.list_items_for_owner(depot):
			if Life.Food.is_food(item):
				tx.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id, "new_holder": {"kind": "entity", "id": "player"}})
	tx.mark_resolved("test_injection.low_hunger_buyer")
	_check(session.writer.apply_result(tx, session.stores), "controlled reserve buyer is not starving and uses actual funds")
	var hour: int = session.elapsed_hours_since_start
	var asks: Array = Life.options(session).filter(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("ask_local:"))
	_check(asks.size() == 1 and asks[0].cost == "10分钟", "orientation is a single short conversation, not three duplicate questions")
	var ask: Dictionary = model.act_player_life(str(asks[0].action_id))
	_check(ask.success and session.elapsed_hours_since_start == hour and session.get_time_summary().minute == 10, "conversation takes ten minutes rather than moving everyone an hour")
	_check("哨棚" in ask.player_life_feedback.compact_body and "答复" in ask.player_life_feedback.title, "receipt gives a usable direction and names speaker")
	_check(not Life.options(session).any(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("ask_local:")), "same settlement introduction is consumed for all speakers")
	var sales: Array = Life.options(session).filter(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("sell_food:" + target))
	_check(not sales.is_empty(), "lightly hungry funded adult can buy reserves")
	if sales.is_empty():
		_finish()
		return
	sales.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.quantity) > int(b.quantity))
	var sale: Dictionary = sales[0]
	var before: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var old_money := Life.Food.balance(before.get_items_for_holder("player"), "player")
	var buyer_money := Life.Food.balance(before.get_items_for_holder(target), target)
	var buyer_food := Life.Food.food_quantity(before.get_items_for_holder(target), target)
	var executed: Dictionary = model.act_player_life(str(sale.action_id))
	var after: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var paid := int(sale.quantity) * int(sale.offer.unit_price)
	_check(executed.success and sale.quantity >= 2, "batch reserve sale executes")
	_check(Life.Food.balance(after.get_items_for_holder("player"), "player") == old_money + paid and Life.Food.balance(after.get_items_for_holder(target), target) == buyer_money - paid, "sale transfers finite copper exactly")
	_check(Life.Food.food_quantity(after.get_items_for_holder(target), target) == buyer_food + int(sale.quantity), "purchased food remains physically held, no fake sell sink")
	_check(session.get_time_summary().minute == 20, "trade advances the same short-action clock")
	_check(model.build_view_data().feedback.eyebrow.contains("10 分钟"), "visible receipt reports minutes, not zero or one hour")
	var remaining_sales: Array = Life.options(session).filter(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("sell_food:" + target))
	_check(remaining_sales.all(func(r: Dictionary) -> bool: return int(r.quantity) <= (8 if after.get_entity(target).has("guesthouse_rules") else 4) - buyer_food - int(sale.quantity) and int(r.quantity) * int(r.offer.unit_price) <= buyer_money - paid), "remaining offers are capped by actual reserve gap and remaining money")
	var path := "user://tests/journey_experience/partial.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_check(model.save_to_path(path, true).success, "save retains a partial hour")
	var restored := Live.new()
	var loaded: Dictionary = restored.load_from_path(path)
	_check(loaded.get("success", false), "native partial-hour load: " + str(loaded.get("error", "")))
	if not loaded.get("success", false):
		_finish()
		return
	_check(restored.session.get_time_summary() == session.get_time_summary(), "restored clock matches exactly")
	for denial: String in ["absent", "poor", "stocked"]:
		var blocked := Live.new()
		_check(blocked.load_from_path(path).success, "restore denial branch " + denial)
		var s: Variant = blocked.session
		var setup := Tx.new()
		var source := "test_injection.reserve_" + denial
		setup.add_fact({"fact_id": source, "fact_type": "test_injection", "summary": "测试注入：分别核实异地、无钱和储备已满时拒绝收粮。"})
		if denial == "absent":
			Life.set_state(setup, target, "location_id", "generated_location.echo_landing.landing")
		elif denial == "poor":
			for item: Dictionary in s.stores.item_store.list_items_for_owner(target):
				if item.item_def_id == "item.copper_coin":
					setup.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id, "new_holder": {"kind": "entity", "id": "player"}, "source_fact_ids": [source]})
		else:
			setup.add_item_change({"operation": "create", "item": {"item_instance_id": "test.reserve.full", "item_def_id": "item.fresh_fish_portion", "holder": {"kind": "entity", "id": target}, "quantity": 8}, "source_fact_ids": [source]})
		setup.mark_resolved("test_injection.reserve_" + denial)
		_check(s.writer.apply_result(setup, s.stores), "controlled denial commits " + denial)
		var clock_before: Dictionary = s.get_time_summary()
		_check(not Life.options(s).any(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("sell_food:" + target)), "no fabricated sale when " + denial)
		_check(not Life.execute(s, str(sale.action_id)).success and s.get_time_summary() == clock_before, "stale sale refused without spending time when " + denial)
	# Clock boundary counterexample; not described as legal player activity.
	for index: int in range(4):
		for s: Variant in [session, restored.session]:
			var clock := Tx.new()
			Brief.append(clock, s)
			clock.mark_resolved("test_injection.short_clock_boundary")
			_check(s.writer.apply_result(clock, s.stores) and Brief.advance(s, "test_injection.short_clock_boundary").success, "controlled short-clock boundary commits")
	_check(session.elapsed_hours_since_start == hour + 1 and session.get_time_summary().minute == 0, "six short actions advance one full shared world hour")
	_check(JourneyContract.equal_native(session.stores.state_store.to_save_data(), restored.session.stores.state_store.to_save_data()), "native continuation reproduces autonomous resident state")
	_check(not Life.options(session).any(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("ask_local:")), "world tick and changed stock do not reopen orientation")
	_check(Brief.validate({"player_action_minutes": 60}) != "" and Brief.validate({"player_action_minutes": 3}) != "", "corrupt minute remainders rejected")
	var old := Live.new()
	_check(old.start(JourneyContract.options()).success and not Brief.enabled(old.session), "previous journey version keeps old pace and market rules")
	_finish()
