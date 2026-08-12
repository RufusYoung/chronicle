extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const GIVE_CHEN_MI_FOOD := "give_food_to_hungry_person:chen_mi"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rules := [BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	var baseline = SimSessionModel.new()
	var baseline_start: Dictionary = baseline.start_from_fixture_path(
		FIXTURE_PATH,
		rules
	)
	var baseline_day: Dictionary = baseline.advance_time(
		12,
		"resident_network_probe"
	)
	var baseline_snapshot: Variant = baseline.get_snapshot()
	_check(
		bool(baseline_start.get("success", false))
		and int(baseline_start.get("npc_need_profile_count", 0)) == 3
		and int(baseline_start.get("autonomous_action_rule_count", 0)) == 11
		and not baseline_snapshot.get_entity("market_porter").is_empty()
		and int(baseline.stores["state_store"].get_state(
			"north_quay_net_mender",
			"food_stock",
			-1
		)) >= 0,
		"1. 居民网络载入三种时间驱动、十一条规则和新增居民"
	)
	var baseline_rules := _decision_rules(baseline_day)
	_check(
		baseline_rules.has("food_producer_replenishes_local_stock")
		and baseline_rules.has("resident_completes_paid_work")
		and baseline_rules.has("hungry_resident_walks_to_food_supplier")
		and baseline_rules.has("hungry_resident_buys_food"),
		"2. 十二小时内同时发生生产、劳动收入、跨地觅食和交易"
	)
	_check(
		baseline_rules.has("blocked_resident_requests_food_help")
		and baseline_rules.has("blocked_resident_seeks_alternate_supplier")
		and _fact_count_for_actor(
			baseline,
			"resident_selected_alternate_food_supplier",
			"north_quay_record_keeper"
		) == 1,
		"3. 主供应失败后，闻简会先求助再自行改找备用食源"
	)
	_check(
		_fact_count_for_actor(
			baseline,
			"npc_completed_food_trade",
			"north_quay_record_keeper"
		) >= 1
		and _fact_count_for_actor(
			baseline,
			"npc_completed_food_trade",
			"market_porter"
		) >= 1
		and _all_trade_targets(baseline).has("north_quay_net_mender")
		and baseline.stores["exchange_store"].list_exchanges().size() >= 2,
		"4. 闻简和周拓都能从石苇处完成真实库存与零钱交换"
	)
	_check(
		_fact_count_for_actor(
			baseline,
			"resident_completed_paid_work",
			"north_quay_record_keeper"
		) >= 1
		and _fact_count_for_actor(
			baseline,
			"resident_completed_paid_work",
			"market_porter"
		) >= 1,
		"5. 两名消费者会在岗位挣钱，交易不再耗尽初始零钱后停止"
	)
	_check(
		not _observed_actor_rules(baseline_day).has(
			"north_quay_net_mender:food_producer_replenishes_local_stock"
		),
		"6. 玩家留在市场时不会直接获知北埠的异地生产"
	)
	baseline.context.set_current_location("north_quay_record_house")
	var quay_snapshot: Variant = baseline.get_snapshot()
	_check(
		not quay_snapshot.get_entity("north_quay_net_mender").is_empty()
		and _visible_trace_types(quay_snapshot).has("fresh_food_delivery")
		and _visible_rumor_keys(quay_snapshot).has("north_quay_fresh_catch"),
		"7. 玩家后来抵达北埠，可以从人物、鱼篓和传闻发现生产历史"
	)

	var first_day_production_count: int = baseline.stores["fact_store"] \
		.find_facts_by_type("local_food_was_produced").size()
	var first_day_work_count: int = baseline.stores["fact_store"] \
		.find_facts_by_type("resident_completed_paid_work").size()
	var first_day_exchange_count: int = baseline.stores["exchange_store"] \
		.list_exchanges().size()
	baseline.advance_time(24, "resident_network_continuity_probe")
	_check(
		baseline.stores["fact_store"].find_facts_by_type(
			"local_food_was_produced"
		).size() > first_day_production_count
		and baseline.stores["fact_store"].find_facts_by_type(
			"resident_completed_paid_work"
		).size() > first_day_work_count
		and baseline.stores["exchange_store"].list_exchanges().size()
			> first_day_exchange_count,
		"8. 推进到三十六小时后仍会产生新食物、新收入和新交易"
	)
	var rumor_count: int = baseline.stores["rumor_store"].list_rumors().size()
	var trace_count: int = baseline.stores["trace_store"].list_traces().size()
	_check(
		rumor_count <= 8 and trace_count <= 16,
		(
			"9. 重复生活循环刷新同类传闻与痕迹，不会无限积累"
			+ "（传闻 %d，痕迹 %d）"
			% [rumor_count, trace_count]
		)
	)

	var helped = SimSessionModel.new()
	helped.start_from_fixture_path(FIXTURE_PATH, rules)
	var help_result: Dictionary = helped.execute_action(GIVE_CHEN_MI_FOOD)
	helped.advance_time(4, "resident_network_helped_probe")
	_check(
		bool(help_result.get("success", false))
		and _trade_targets_for_actor(
			helped,
			"north_quay_record_keeper"
		).has("old_chen")
		and _fact_count_for_actor(
			helped,
			"resident_selected_alternate_food_supplier",
			"north_quay_record_keeper"
		) == 0,
		"10. 缓解陈米饥饿后老陈继续营业，闻简无需改找备用供应"
	)
	helped.advance_time(8, "resident_network_helped_continuity_probe")
	_check(
		_trade_targets_for_actor(
			baseline,
			"north_quay_record_keeper"
		) != _trade_targets_for_actor(
			helped,
			"north_quay_record_keeper"
		),
		"11. 同一居民在不同外部输入下形成不同交易对象和生活历史"
	)

	_finish()


func _decision_rules(tick_result: Dictionary) -> Array:
	var rows: Array = []
	for decision: Dictionary in tick_result.get("autonomous_decisions", []):
		rows.append(str(decision.get("rule_id", "")))
	return rows


func _observed_actor_rules(tick_result: Dictionary) -> Array:
	var rows: Array = []
	for decision: Dictionary in tick_result.get("autonomous_decisions", []):
		if not bool(decision.get("observed_by_player", false)):
			continue
		rows.append("%s:%s" % [
			str(decision.get("actor_id", "")),
			str(decision.get("rule_id", "")),
		])
	return rows


func _fact_count_for_actor(
		session: Variant,
		fact_type: String,
		actor_id: String
) -> int:
	var count := 0
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		fact_type
	):
		if str(fact.get("actor_id", "")) == actor_id:
			count += 1
	return count


func _all_trade_targets(session: Variant) -> Array:
	var rows: Array = []
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"npc_completed_food_trade"
	):
		var target_id := str(fact.get("target_id", ""))
		if target_id != "" and target_id not in rows:
			rows.append(target_id)
	rows.sort()
	return rows


func _trade_targets_for_actor(session: Variant, actor_id: String) -> Array:
	var rows: Array = []
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"npc_completed_food_trade"
	):
		if str(fact.get("actor_id", "")) != actor_id:
			continue
		var target_id := str(fact.get("target_id", ""))
		if target_id != "" and target_id not in rows:
			rows.append(target_id)
	rows.sort()
	return rows


func _visible_trace_types(snapshot: Variant) -> Array:
	var rows: Array = []
	for trace: Dictionary in snapshot.get_visible_traces():
		rows.append(str(trace.get("trace_type", "")))
	return rows


func _visible_rumor_keys(snapshot: Variant) -> Array:
	var rows: Array = []
	for rumor: Dictionary in snapshot.get_visible_rumors():
		rows.append(str(rumor.get("rumor_key", "")))
	return rows


func _finish() -> void:
	if failures.is_empty():
		print("[V5 NPC RESIDENT NETWORK RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 NPC RESIDENT NETWORK FAIL] " + failure)
		print(
			"[V5 NPC RESIDENT NETWORK RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 NPC RESIDENT NETWORK PASS] " + message)
	else:
		failures.append(message)
