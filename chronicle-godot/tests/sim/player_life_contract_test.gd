extends "res://tests/sim/work_recipe_contract_test.gd"

const Life = preload("res://scripts/sim/player/player_life.gd")


func _run() -> void:
	var live := Live.new()
	var started: Dictionary = live.start({"scenario": "echo_realm", "challenge_seed_override": 81001,
		"work_rules_version": 1, "world_danger_version": 1, "player_life_version": 1,
		"household_food_hauling_version": 1, "household_food_budget_version": 1,
		"resident_subsistence_version": 1, "worksite_food_storage_version": 1})
	_check(started.get("success", false), "explicit player life world starts: " + str(started.get("error", "")))
	if not live.is_ready():
		_finish()
		return
	var session: Variant = live.session
	_check(session.stores.state_store.get_state("player", "location_id", "") == session.context.location_id, "player body has authoritative position")
	var initial_food: int = session.get_snapshot().player.food_count
	var hunger: String = session.get_snapshot().player.hunger
	_check(session.advance_time(6, "legal_wait").success, "world and player share six real hours")
	_check(session.get_snapshot().player.hunger != hunger, "waiting creates actual hunger")
	_check(live.act_player_life("eat").success, "real owned meal is consumed")
	_check(session.get_snapshot().player.food_count == initial_food - 1, "meal is not free")
	_check(session.get_snapshot().player.hunger == "none", "meal reduces shared hunger scale")
	var food_site := ""
	for profile: Dictionary in session.npc_livelihood_profiles:
		if profile.get("work_output_food", false) and profile.workplace_id != "" \
				and profile.settlement_id == session.get_snapshot().player.settlement_id \
				and profile.occupation_id != "terrace_farmer":
			food_site = profile.workplace_id
	_check(food_site != "", "local alternative food site exists")
	print("PLAYER_FOOD_SITE ", food_site)
	for route: Dictionary in session.get_travel_options():
		if route.to_location_id != food_site:
			continue
		var travel: Dictionary = live.perform_travel(str(route.route_id))
		_check(travel.success, "legal departure: " + str(travel.get("error", "")))
		while int(session.get_snapshot().player.get("daily_travel_remaining", 0)) > 0:
			_check(session.save_to_path("user://tests/player_life/transit.json").ok, "native in-transit save")
			var loaded := Session.new()
			_check(loaded.load_from_path("user://tests/player_life/transit.json").success, "native in-transit restore")
			_check(session.get_travel_options().is_empty(), "no duplicate departure while traveling")
			_check(not Life.execute(session, "eat").success, "cannot dine or trade as if already at destination")
			_check(live.act_player_life("continue").success, "physical journey progresses")
		break
	_check(session.context.location_id == food_site, "arrival uses destination state")
	if session.current_hour >= 14:
		session.advance_time(24 - session.current_hour + 6, "legal_overnight_wait")
	var gathered := false
	for option: Dictionary in Life.options(session):
		print("PLAYER_OPTION ", option.label, " ", option.action_id, " ", option.blocked_reason)
		if option.action_id.begins_with("gather:") and option.can_execute:
			var before: int = session.get_snapshot().player.food_count
			var result: Dictionary = live.act_player_life(option.action_id)
			print("PLAYER_GATHER ", JSON.stringify(result))
			_check(result.success, "shared gathering resolver succeeds")
			gathered = session.get_snapshot().player.food_count > before
			break
	_check(gathered, "new food comes from real local work after starter food")
	_check(session.save_to_path("user://tests/player_life/after_work.json").ok, "native player life save")
	var restored := Session.new()
	var loaded: Dictionary = restored.load_from_path("user://tests/player_life/after_work.json")
	_check(loaded.get("success", false), "restore life state: " + str(loaded.get("error", "")))
	if loaded.get("success", false):
		session.advance_time(1, "continue")
		restored.advance_time(1, "continue")
		_check(_signature(session) == _signature(restored), "full native state continues identically")
	_paid_work(session.fixture_source_data, food_site)
	var stocked_fixture: Dictionary = session.fixture_source_data.duplicate(true)
	stocked_fixture.known_facts.append({"fact_id": "test_injection.player_food_stack", "fact_type": "test_injection",
		"summary": "测试注入：玩家预先持有与短工产物相同的食物，检查叠堆不会偷换收货人。"})
	stocked_fixture.initial_items.append({"item_instance_id": "test.player.existing_fish", "item_def_id": "item.fresh_fish_portion",
		"holder": {"kind": "entity", "id": "player"}, "quantity": 3})
	_paid_work(stocked_fixture, food_site)
	_journey_case(session.fixture_source_data)
	_resource_counterexample(session.fixture_source_data, food_site)
	_tool_case(session.fixture_source_data, food_site)
	_legacy_case()
	_finish()


func _paid_work(base: Dictionary, food_site: String) -> void:
	var session: Variant = _session(base)
	for route: Dictionary in session.get_travel_options():
		if route.to_location_id == food_site:
			_check(session.travel(str(route.route_id)).success, "fresh paid-work branch follows real route")
			break
	var completed := false
	for index: int in range(3):
		if Life.options(session).any(func(option: Dictionary) -> bool: return option.action_id.begins_with("help:") and option.can_execute):
			break
		session.advance_time(1, "wait_for_local_workers")
	for option: Dictionary in Life.options(session):
		print("PAID_CANDIDATE ", option.action_id, " ", option.can_execute)
		if not option.action_id.begins_with("help:") or not option.can_execute:
			continue
		var employer: String = option.action_id.split(":")[1]
		var before: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
		var money := Life.Treasury.new(before)
		var player_coins := money.balance("player")
		var total_before := 0
		for item: Dictionary in before.get_items():
			if item.item_def_id == Life.Food.CURRENCY:
				total_before += int(item.quantity)
		var player_food: int = before.player.food_count
		var result := Life.execute(session, option.action_id)
		print("PAID_OUTCOME ", JSON.stringify(result))
		_check(result.success, "paid gathering completes through common work resolver")
		var after: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
		completed = Life.Treasury.new(after).balance("player") == player_coins + int(Life.PROFILE.help_wage)
		_check(completed, "employer pays real coins")
		var total_after := 0
		for item: Dictionary in after.get_items():
			if item.item_def_id == Life.Food.CURRENCY:
				total_after += int(item.quantity)
		_check(total_after == total_before, "wages transfer existing coins without minting")
		_check(after.player.food_count == player_food, "hired crop belongs to employer, not helper")
		var bought := false
		for buy: Dictionary in Life.options(session):
			print("AFTER_WORK_OPTION ", buy.label, " ", buy.blocked_reason)
			if buy.action_id.begins_with("buy:") and buy.can_execute:
				var purchased := Life.execute(session, buy.action_id)
				print("PLAYER_PURCHASE ", JSON.stringify(purchased.get("player_life_feedback", {})))
				_check(purchased.success, "earned coins purchase a present seller's stock")
				_check(session.get_snapshot().player.food_count == player_food + 1, "purchased food reaches real inventory")
				bought = purchased.success
				break
		_check(bought, "natural wage-to-food chain is actually exercised")
		var heard := false
		for hour: int in range(36):
			var reports: Array = Life.options(session).filter(func(row: Dictionary) -> bool: return row.action_id.begins_with("inquire:"))
			if not reports.is_empty():
				var report: Dictionary = reports[0]
				var update_id: String = report.report.update_id
				_check(Life.execute(session, report.action_id).success, "co-located person reports a real later use")
				_check(not Life.observed_followups(session).is_empty(), "known consequence is retained for UI and saves")
				_check(not Life.options(session).any(func(row: Dictionary) -> bool: return row.get("report", {}).get("update_id") == update_id), "already told update is not offered indefinitely")
				heard = true
				break
			session.advance_time(1, "wait_for_real_followup")
		_check(heard, "natural paid-work followup actually reaches the actor")
		break
	_check(completed, "natural local paid-work opportunity exists")


func _journey_case(base: Dictionary) -> void:
	var session: Variant = _session(base)
	var exercised := false
	for route: Dictionary in session.get_travel_options():
		if int(route.hours) <= 1:
			continue
		var started: Dictionary = session.travel(str(route.route_id))
		_check(started.success, "multi-hour legal departure")
		_check(int(session.get_snapshot().player.daily_travel_remaining) == int(route.hours) - 1, "first hour does not teleport to end")
		_check(session.save_to_path("user://tests/player_life/journey.json").ok, "save while physically in transit")
		var restored := Session.new()
		var loaded: Dictionary = restored.load_from_path("user://tests/player_life/journey.json")
		_check(loaded.get("success", false), "restore mid-route: " + str(loaded.get("error", "")))
		_check(session.get_travel_options().is_empty(), "no nested travel")
		_check(not session.recover_from_danger().success, "direct recovery entry cannot bypass journey")
		_check(not Life.execute(session, "eat").success, "cannot use ground actions mid-route")
		if loaded.get("success", false):
			session.advance_time(1, "resume_journey")
			restored.advance_time(1, "resume_journey")
			_check(_signature(session) == _signature(restored), "journey and all residents resume identically")
		exercised = true
		break
	_check(exercised, "a real long route was tested")


func _resource_counterexample(base: Dictionary, site: String) -> void:
	var fixture := base.duplicate(true)
	fixture.location_id = site
	fixture.player.location_id = site
	fixture.known_facts.append({"fact_id": "test_injection.player_life.exhaustion", "fact_type": "test_injection",
		"summary": "测试注入：耗尽现场资源且暂时关闭自然补充，检验玩家与居民都不能无投入生产。"})
	for stock: Dictionary in fixture.initial_resource_stocks:
		stock.current = 0
		stock.recovery_per_hour = 0
	var session: Variant = _session(fixture)
	var before: int = session.get_snapshot().player.food_count
	var exercised := false
	for option: Dictionary in Life.options(session):
		if option.action_id.begins_with("gather:") and option.can_execute:
			var outcome := Life.execute(session, option.action_id)
			_check(outcome.success, "failed physical attempt still consumes actual time")
			_check(session.get_snapshot().player.food_count == before, "exhausted commons cannot create player food")
			_check(session.elapsed_hours_since_start > 0, "failed work is not a free scouting action")
			exercised = true
			break
	_check(exercised, "resource counterexample exercised")


func _legacy_case() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm"}).success, "legacy default still starts")
	var before: Variant = live.session.get_snapshot().player.get("hunger", null)
	live.session.advance_time(6, "legacy_wait")
	_check(live.session.get_snapshot().player.get("hunger", null) == before, "old world does not silently gain player hunger")
	_check(Life.options(live.session).is_empty(), "old world does not gain new life actions")


func _tool_case(base: Dictionary, food_site: String) -> void:
	var fixture := base.duplicate(true)
	var shop := ""
	for profile: Dictionary in fixture.generated_livelihood_profiles:
		if profile.settlement_id == fixture.player.settlement_id and profile.get("work_recipe", {}).get("recipe_id") == "recipe.reed_cordage":
			shop = profile.workplace_id
	fixture.location_id = shop
	fixture.player.location_id = shop
	fixture.known_facts.append({"fact_id": "test_injection.player_tool_budget", "fact_type": "test_injection",
		"summary": "测试注入：玩家在作坊附近开始，从已有金库转移20枚铜币，只检验实际现货购买、工具使用与修补，不作为自然谋生证据。"})
	var needed := 20
	for item: Dictionary in fixture.initial_items:
		if item.item_def_id == "item.copper_coin" and needed > 0:
			var amount := mini(needed, maxi(int(item.quantity) - 1, 0))
			item.quantity -= amount
			needed -= amount
	_check(needed == 0, "test budget is transferred, not minted")
	fixture.initial_items.append({"item_instance_id": "test.player.tool_coins", "item_def_id": "item.copper_coin",
		"holder": {"kind": "entity", "id": "player"}, "quantity": 20})
	var session: Variant = _session(fixture)
	var purchased := false
	for hour: int in range(60):
		var view: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
		for offer: Dictionary in Life.offers(view, view.get_entity("player"), fixture.resident_daily_life.food_access, session.stores, session.npc_livelihood_profiles):
			if offer.get("item", {}).get("item_def_id") != "item.fiber_rope" or int(offer.item.condition.durability) < 1:
				continue
			var result := Life.execute(session, "buy:" + str(offer.item_instance_id))
			_check(result.success, "player purchases actual locally produced rope")
			purchased = result.success
			break
		if purchased:
			break
		session.advance_time(1, "wait_for_rope_stock")
	_check(purchased, "a maker's real surplus is offered after retaining their own tool")
	if not purchased:
		return
	_go(session, "to_commons")
	_go(session, "commons_to_fishery")
	_check(session.context.location_id == food_site, "carry purchased tool along real roads")
	_daylight(session)
	var ropes: Array = session.get_snapshot().get_player_items().filter(func(item: Dictionary) -> bool: return item.item_def_id == "item.fiber_rope")
	var rope_id: String = ropes[0].item_instance_id
	var durability: int = ropes[0].condition.durability
	var food: int = session.get_snapshot().player.food_count
	var made := Life.execute(session, "work:recipe.net_fishing")
	print("PLAYER_TOOL_WORK ", JSON.stringify(made))
	_check(made.success, "same recipe works for the controlled actor")
	_check(session.get_snapshot().player.food_count - food > 4, "real tool increases yield over hand gathering")
	_check(session.stores.item_store.get_item(rope_id).condition.durability == durability - 1, "tool use actually wears the purchased instance")
	for cycle: int in range(durability - 1):
		_daylight(session)
		while int(session.get_snapshot().player.fatigue) >= 6:
			Life.execute(session, "rest")
		if session.get_snapshot().player.hunger in ["high", "extreme"]:
			Life.execute(session, "eat")
		_daylight(session)
		var worked := Life.execute(session, "work:recipe.net_fishing")
		_check(worked.success, "continue using the same finite tool")
	_check(session.stores.item_store.get_item(rope_id).condition.durability == 0, "tool is genuinely exhausted by production")
	_check(not Life.execute(session, "work:recipe.net_fishing").success, "broken tool cannot produce another batch")
	_go(session, "to_commons")
	_go(session, "commons_to_reed_craft")
	while int(session.get_snapshot().player.fatigue) >= 6:
		Life.execute(session, "rest")
	_daylight(session)
	var repaired := false
	for option: Dictionary in Life.options(session):
		print("PLAYER_REPAIR_OPTION ", option.action_id, " ", option.blocked_reason)
		if option.action_id.begins_with("repair:") and option.can_execute:
			var repair := Life.execute(session, option.action_id)
			print("PLAYER_TOOL_REPAIR ", JSON.stringify(repair))
			_check(repair.success, "shared maintenance uses real local inputs")
			repaired = session.stores.item_store.get_item(rope_id).condition.durability > 0
			break
	_check(repaired, "maintenance restores actual tool condition")
	_check(session.save_to_path("user://tests/player_life/tool_work.json").ok, "save real tool trade/work/repair")
	_check(Session.new().load_from_path("user://tests/player_life/tool_work.json").success, "native restore after tool maintenance")


func _go(session: Variant, hint: String) -> void:
	for route: Dictionary in session.get_travel_options():
		if hint in str(route.route_id):
			_check(session.travel(str(route.route_id)).success, "legal tool journey " + hint)
			while int(session.get_snapshot().player.get("daily_travel_remaining", 0)) > 0:
				Life.execute(session, "continue")
			return
	_check(false, "missing legal route " + hint)


func _daylight(session: Variant) -> void:
	if session.current_hour < 6:
		session.advance_time(6 - session.current_hour, "wait_for_daylight")
	elif session.current_hour > 12:
		session.advance_time(24 - session.current_hour + 6, "wait_for_daylight")
