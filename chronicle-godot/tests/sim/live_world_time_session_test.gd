extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const SimRunnerModel = preload("res://scripts/sim/core/sim_runner.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const SCENARIO_PATH := (
	"res://data/sim/fixtures/scenarios/lake_town_food_crisis_sequence.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rules := [BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	var session = SimSessionModel.new()
	var start_result: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH,
		rules
	)
	_check(
		bool(start_result.get("success", false))
		and int(session.get_time_summary().get("day", 0)) == 1
		and int(session.get_time_summary().get("hour", -1)) == 10
		and int(start_result.get("autonomous_action_rule_count", 0)) == 11,
		"1. SimSession 从 fixture 载入世界时间"
	)
	_check(
		session.stores["deferred_consequence_store"]
			.find_pending_consequences()
			.is_empty(),
		"2. 粮铺变化不再声明为固定延迟后果"
	)
	_check(
		not bool(session.get_snapshot().get_entity_state(
			"old_chen_shop_closing_shutters",
			"visible",
			true
		)),
		"3. 时间推进前，收铺门板尚未出现在现场"
	)

	var tick_result: Dictionary = session.advance_time(
		1,
		"after_short_wait",
		{"label": "在老陈铺子等待一小时"}
	)
	_check(
		bool(tick_result.get("success", false))
		and int(tick_result.get("matched_count", -1)) == 0
		and int(tick_result.get("triggered_count", -1)) == 0
		and int(tick_result.get("autonomous_decision_count", 0)) == 1
		and str((tick_result.get("autonomous_decisions", [])[0] as Dictionary).get(
			"rule_id",
			""
		)) == "merchant_rations_stock_for_hungry_dependent",
		"4. advance_time 让老陈根据共享状态自主选择保粮收铺"
	)
	_check(
		int(session.get_time_summary().get("hour", -1)) == 11
		and int(session.get_time_summary().get("world_tick_count", 0)) == 1,
		"5. 成功 Tick 后 Session 时钟前进一小时"
	)

	var snapshot: Variant = session.get_snapshot()
	_check(
		bool(snapshot.get_entity_state(
			"old_chen_shop_closing_shutters",
			"visible",
			false
		))
		and str(snapshot.get_entity_state(
			"old_chen_shop_price_notice",
			"price_level",
			""
		)) == "raised_again",
		"6. 世界 Tick 让门板出现并再次改高告示价格"
	)
	_check(
		session.stores["pressure_store"].get_pressure_value(
			"old_chen_shop",
			"market_shortage"
		) == 10
		and not session.stores["fact_store"].find_facts_by_type(
			"merchant_closed_shop_early"
		).is_empty(),
		"7. 世界 Tick 写入粮食压力和可追溯事实"
	)
	_check(
		session.get_world_log_entries().size() == 1
		and int(session.get_world_log_summary().get("tick_event_count", 0)) == 1
		and int(session.get_world_log_summary().get(
			"triggered_deferred_count",
			0
		)) == 0
		and int(session.get_world_log_summary().get(
			"autonomous_decision_count",
			0
		)) == 1,
		"8. Tick 日志并入持久 Session WorldLog"
	)

	var second_tick: Dictionary = session.advance_time(1, "after_short_wait")
	_check(
		bool(second_tick.get("success", false))
		and int(second_tick.get("triggered_count", -1)) == 0
		and int(second_tick.get("autonomous_decision_count", -1)) == 0
		and int(session.get_time_summary().get("hour", -1)) == 12
		and int(session.get_time_summary().get("elapsed_hours", -1)) == 2,
		"9. 后果只触发一次，但世界时间可以继续前进"
	)
	_check(
		session.stores["pressure_store"].get_pressure_value(
			"old_chen_shop",
			"market_shortage"
		) == 10
		and session.stores["fact_store"].find_facts_by_type(
			"merchant_closed_shop_early"
		).size() == 1,
		"10. 重复等待不会复制已触发的事实和压力"
	)

	var time_before_invalid: Dictionary = session.get_time_summary()
	var invalid_result: Dictionary = session.advance_world({}, 3)
	var invalid_metadata_result: Dictionary = session.advance_time(
		1,
		"after_short_wait",
		{"due_kinds": "invalid"}
	)
	_check(
		not bool(invalid_result.get("success", true))
		and not bool(invalid_metadata_result.get("success", true))
		and str(invalid_metadata_result.get("error_reason", ""))
			== "invalid_due_kinds"
		and int(session.get_time_summary().get("hour", -1))
			== int(time_before_invalid.get("hour", -2)),
		"11. 非法 Tick 或时间参数不推进世界时钟"
	)

	var summary: Dictionary = session.build_result_summary()
	_check(
		int(summary.get("steps_executed", -1)) == 0
		and int(summary.get("world_ticks_executed", 0)) == 2
		and int(summary.get("store_summary", {}).get("pressures", 0)) == 1,
		"12. 运行摘要区分玩家行动与世界 Tick"
	)

	var runner = SimRunnerModel.new()
	var runner_result: Dictionary = runner.run_sequence(
		FIXTURE_PATH,
		SCENARIO_PATH,
		rules
	)
	_check(
		bool(runner_result.get("success", false))
		and int(runner_result.get("steps_executed", 0)) == 3
		and int(runner_result.get("world_ticks_executed", -1)) == 0,
		"13. 原 SimRunner 序列保持兼容且不会暗中推进时间"
	)

	session.start_from_fixture_path(FIXTURE_PATH, rules)
	_check(
		int(session.get_time_summary().get("hour", -1)) == 10
		and int(session.get_time_summary().get("world_tick_count", -1)) == 0
		and session.stores["deferred_consequence_store"]
			.find_pending_consequences()
			.is_empty()
		and session.autonomous_action_rules.size() == 11,
		"14. 重载 fixture 会重置时钟并恢复 NPC 行动规则"
	)

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LIVE WORLD TIME SESSION RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 LIVE WORLD TIME SESSION FAIL] " + failure)
		print("[V5 LIVE WORLD TIME SESSION RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 LIVE WORLD TIME SESSION PASS] " + message)
	else:
		failures.append(message)
