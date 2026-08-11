extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const GIVE_CHEN_MI_FOOD := "give_food_to_hungry_person:chen_mi"
const GIVE_WEN_JIAN_FOOD := (
	"give_food_to_hungry_person:north_quay_record_keeper"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rules := [BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	var blocked = SimSessionModel.new()
	var blocked_start: Dictionary = blocked.start_from_fixture_path(
		FIXTURE_PATH,
		rules
	)
	var blocked_arrival: Dictionary = blocked.advance_time(
		3,
		"emergent_life_probe"
	)
	var blocked_snapshot: Variant = blocked.get_snapshot()
	_check(
		bool(blocked_start.get("success", false))
		and int(blocked_start.get("npc_need_profile_count", 0)) > 0
		and int(blocked_arrival.get("need_change_count", 0)) > 0
		and str(blocked_snapshot.get_entity_state(
			"north_quay_record_keeper",
			"hunger",
			""
		)) == "high",
		"1. 流逝三小时会先让闻简的饥饿从中等自然增长到高"
	)
	_check(
		str(blocked_snapshot.get_entity_state(
			"north_quay_record_keeper",
			"location_id",
			""
		)) == "old_chen_shop"
		and not blocked_snapshot.get_entity(
			"north_quay_record_keeper"
		).is_empty()
		and _decision_rules(blocked_arrival).has(
			"hungry_resident_walks_to_food_supplier"
		),
		"2. 饥饿与断粮会让闻简真实离开档房并抵达粮铺"
	)
	_check(
		blocked.stores["trace_store"].find_traces_by_type(
			"abandoned_workplace"
		).size() == 1
		and blocked.stores["fact_store"].find_facts_by_type(
			"npc_traveled_for_food"
		).size() == 1,
		"3. 异地移动会留下可追溯事实和原地点痕迹"
	)

	var blocked_request: Dictionary = blocked.advance_time(
		1,
		"emergent_life_probe"
	)
	_check(
		_decision_rules(blocked_request).has(
			"blocked_resident_requests_food_help"
		)
		and blocked.stores["rumor_store"].find_rumors_by_source_fact(
			"resident_requested_food_help"
		).size() == 1
		and blocked.stores["fact_store"].find_facts_by_type(
			"npc_completed_food_trade"
		).is_empty(),
		"4. 粮铺收门时闻简无法交易，只能求助并形成传闻"
	)
	var help_options: Array = blocked.get_action_options()
	var help_result: Dictionary = blocked.execute_action(GIVE_WEN_JIAN_FOOD)
	_check(
		_has_action(help_options, GIVE_WEN_JIAN_FOOD)
		and bool(help_result.get("success", false))
		and str(blocked.get_snapshot().get_entity_state(
			"north_quay_record_keeper",
			"hunger",
			""
		)) == "medium",
		"5. 玩家能用既有通用行动介入求助，而不是观看后台报告"
	)
	var helped_return: Dictionary = blocked.advance_time(
		1,
		"emergent_life_probe"
	)
	_check(
		_decision_rules(helped_return).has("fed_resident_returns_home")
		and str(blocked.stores["state_store"].get_state(
			"north_quay_record_keeper",
			"location_id",
			""
		)) == "north_quay_record_house",
		"6. 玩家缓解饥饿后，闻简会依据职责自行返回档房"
	)
	blocked.context.set_current_location("north_quay_record_house")
	var returned_snapshot: Variant = blocked.get_snapshot()
	_check(
		not returned_snapshot.get_entity(
			"north_quay_record_keeper"
		).is_empty()
		and _visible_trace_types(returned_snapshot).has(
			"abandoned_workplace"
		),
		"7. 玩家后来抵达档房时，能同时见到返家的闻简和离场痕迹"
	)

	var trading = SimSessionModel.new()
	trading.start_from_fixture_path(FIXTURE_PATH, rules)
	var chen_help: Dictionary = trading.execute_action(GIVE_CHEN_MI_FOOD)
	var trading_arrival: Dictionary = trading.advance_time(
		3,
		"emergent_life_probe"
	)
	_check(
		bool(chen_help.get("success", false))
		and _decision_rules(trading_arrival).has(
			"merchant_keeps_trading_after_dependent_hunger_eases"
		)
		and _decision_rules(trading_arrival).has(
			"hungry_resident_walks_to_food_supplier"
		),
		"8. 帮助陈米会让同一段时间产生营业与来客并存的不同局面"
	)
	trading.context.set_current_location("north_quay_record_house")
	var trade_tick: Dictionary = trading.advance_time(
		1,
		"emergent_life_probe"
	)
	_check(
		_decision_rules(trade_tick).has("hungry_resident_buys_food")
		and int(trading.stores["state_store"].get_state(
			"north_quay_record_keeper",
			"food_stock",
			0
		)) == 1
		and str(trading.stores["state_store"].get_state(
			"north_quay_record_keeper",
			"hunger",
			""
		)) == "medium"
		and int(trading.stores["state_store"].get_state(
			"old_chen",
			"food_stock",
			0
		)) == 2
		and trading.stores["exchange_store"].list_exchanges().size() == 1,
		"9. 营业路径会完成真实资源转移和已结算交易"
	)
	_check(
		int(trade_tick.get("observed_autonomous_decision_count", -1)) == 0,
		"10. 玩家留在档房时不会直接获知粮铺里的异地交易"
	)
	trading.context.set_current_location("old_chen_shop")
	var trade_snapshot: Variant = trading.get_snapshot()
	_check(
		_visible_rumor_ids(trade_snapshot).has(
			"resident_bought_food"
		)
		and _visible_trace_types(trade_snapshot).has("food_trade"),
		"11. 玩家后来到粮铺时，会从传闻和成交痕迹发现异地交易"
	)
	var trading_return: Dictionary = trading.advance_time(
		1,
		"emergent_life_probe"
	)
	_check(
		_decision_rules(trading_return).has("fed_resident_returns_home")
		and str(trading.stores["state_store"].get_state(
			"north_quay_record_keeper",
			"location_id",
			""
		)) == "north_quay_record_house",
		"12. 交易完成后闻简继续自己的生活链，而不是停在剧情终点"
	)

	var long_blocked = SimSessionModel.new()
	long_blocked.start_from_fixture_path(FIXTURE_PATH, rules)
	var long_blocked_tick: Dictionary = long_blocked.advance_time(
		4,
		"emergent_life_probe"
	)
	_check(
		int(long_blocked_tick.get("simulation_round_count", 0)) == 4
		and _decision_rules(long_blocked_tick).has(
			"hungry_resident_walks_to_food_supplier"
		)
		and _decision_rules(long_blocked_tick).has(
			"blocked_resident_requests_food_help"
		)
		and str(long_blocked.get_snapshot().get_entity_state(
			"north_quay_record_keeper",
			"location_id",
			""
		)) == "old_chen_shop",
		"13. 一次推进四小时也会逐小时完成离岗与求助，不依赖连续点击"
	)

	var long_trading = SimSessionModel.new()
	long_trading.start_from_fixture_path(FIXTURE_PATH, rules)
	long_trading.execute_action(GIVE_CHEN_MI_FOOD)
	var long_trade_tick: Dictionary = long_trading.advance_time(
		4,
		"emergent_life_probe"
	)
	_check(
		_decision_rules(long_trade_tick).has(
			"hungry_resident_walks_to_food_supplier"
		)
		and _decision_rules(long_trade_tick).has("hungry_resident_buys_food")
		and int(long_trading.stores["state_store"].get_state(
			"north_quay_record_keeper",
			"food_stock",
			0
		)) == 1
		and long_trading.stores["exchange_store"].list_exchanges().size() == 1,
		"14. 一次推进四小时也会完成营业分支的真实交易"
	)

	_finish()


func _decision_rules(tick_result: Dictionary) -> Array:
	var rows: Array = []
	for decision: Dictionary in tick_result.get("autonomous_decisions", []):
		rows.append(str(decision.get("rule_id", "")))
	return rows


func _has_action(options: Array, action_id: String) -> bool:
	for option: Dictionary in options:
		if str(option.get("action_id", "")) == action_id:
			return true
	return false


func _visible_trace_types(snapshot: Variant) -> Array:
	var rows: Array = []
	for trace: Dictionary in snapshot.get_visible_traces():
		rows.append(str(trace.get("trace_type", "")))
	return rows


func _visible_rumor_ids(snapshot: Variant) -> Array:
	var rows: Array = []
	for rumor: Dictionary in snapshot.get_visible_rumors():
		rows.append(str(rumor.get("rumor_key", "")))
	return rows


func _finish() -> void:
	if failures.is_empty():
		print("[V5 NPC EMERGENT LIFE LOOP RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 NPC EMERGENT LIFE LOOP FAIL] " + failure)
		print(
			"[V5 NPC EMERGENT LIFE LOOP RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 NPC EMERGENT LIFE LOOP PASS] " + message)
	else:
		failures.append(message)
