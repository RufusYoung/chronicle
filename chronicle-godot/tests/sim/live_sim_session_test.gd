extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const SimRunnerModel = preload("res://scripts/sim/core/sim_runner.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const LAKE_TOWN_FIXTURE_PATH := (
	"res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
)
const LAKE_TOWN_SCENARIO_PATH := (
	"res://data/sim/fixtures/scenarios/lake_town_food_crisis_sequence.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw_rule_paths := [BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	var session = SimSessionModel.new()
	var start_result: Dictionary = session.start_from_fixture_path(
		LAKE_TOWN_FIXTURE_PATH,
		raw_rule_paths
	)
	_check(
		bool(start_result.get("success", false))
		and str(start_result.get("fixture_id", "")) == "lake_town_food_crisis",
		"1. SimSession 能从 fixture 启动并持续持有世界"
	)

	var initial_options: Array = session.get_action_options()
	_check(
		_has_action(initial_options, "give_food_to_hungry_person:chen_mi")
		and _has_action(
			initial_options,
			"read_visible_readable_object:old_chen_shop_price_notice"
		),
		"2. Session 能把当前行动候选转换为 UI 可读字典"
	)

	var give_result: Dictionary = session.execute_action(
		"give_food_to_hungry_person:chen_mi"
	)
	_check(
		bool(give_result.get("success", false))
		and str(give_result.get("contract_status", "")) == "resolved",
		"3. 玩家可以按 action_id 执行当前候选"
	)
	_check(
		session.stores["state_store"].get_state("chen_mi", "hunger") == "medium"
		and not session.stores["state_store"].list_states("player").has("food_count")
		and int(session.get_snapshot().get_player_value("food_count", -1)) == 2,
		"4. 饥饿写回 StateStore，口粮消耗写回 ItemStore"
	)
	_check(
		not _has_action(
			session.get_action_options(),
			"give_food_to_hungry_person:chen_mi"
		),
		"5. 状态变化后，过期候选不会再次出现"
	)

	var stale_log_count := session.get_world_log_entries().size()
	var stale_result: Dictionary = session.execute_action(
		"give_food_to_hungry_person:chen_mi"
	)
	_check(
		not bool(stale_result.get("success", true))
		and str(stale_result.get("error", "")) == "candidate_not_found"
		and session.get_world_log_entries().size() == stale_log_count,
		"6. Session 拒绝已经失效的玩家行动且不污染世界日志"
	)

	var read_result: Dictionary = session.execute_action(
		"read_visible_readable_object:old_chen_shop_price_notice"
	)
	var trace_result: Dictionary = session.execute_action(
		"inspect_visible_trace:gray_grain_powder"
	)
	_check(
		bool(read_result.get("success", false))
		and bool(trace_result.get("success", false)),
		"7. 同一 Session 可以连续执行不同玩家行动"
	)

	var approach_result: Dictionary = session.execute_action(
		"approach_visible_person:chen_mi"
	)
	_check(
		bool(approach_result.get("success", false))
		and str(approach_result.get("contract_status", "")) == "resolved",
		"8. 接近人物会产生可读结果并成为一次性事实"
	)

	var snapshot: Variant = session.get_snapshot()
	_check(
		snapshot.get_facts().size() == 4
		and snapshot.get_memories("chen_mi").size() == 1
		and snapshot.get_memories("player").size() == 2
		and int(snapshot.get_relation("chen_mi", "player", "gratitude", 0)) >= 10,
		"9. 新快照能读到连续行动留下的事实、记忆与关系"
	)
	_check(
		session.get_world_log_entries().size() == 4
		and int(session.get_world_log_summary().get("resolved_count", 0)) == 4
		and int(session.get_world_log_summary().get("candidate_only_count", 0)) == 0,
		"10. WorldLog 持续记录四次已结算玩家行动"
	)

	var summary: Dictionary = session.build_result_summary()
	_check(
		int(summary.get("steps_executed", 0)) == 4
		and int(summary.get("store_summary", {}).get("facts", 0)) == 4
		and str(summary.get("candidate_context_source", "")) == "SimSnapshot",
		"11. Session 能输出供 UI、存档和测试使用的运行摘要"
	)
	_check(
		not (session.stores["fact_store"] is Node)
		and not (session.stores["state_store"] is Node),
		"12. 世界 Store 仍是纯数据对象，没有写入 Godot 场景树"
	)

	var runner = SimRunnerModel.new()
	var runner_result: Dictionary = runner.run_sequence(
		LAKE_TOWN_FIXTURE_PATH,
		LAKE_TOWN_SCENARIO_PATH,
		raw_rule_paths
	)
	_check(
		bool(runner_result.get("success", false))
		and int(runner_result.get("steps_executed", 0)) == 3
		and int(runner_result.get("candidate_generation_count", 0)) == 3
		and int(runner_result.get("store_summary", {}).get("facts", 0)) == 3,
		"13. 原 SimRunner 已通过同一个 SimSession 保持兼容"
	)
	_check(
		_world_log_has_fact(runner_result, "actor_gave_food_to_target")
		and _world_log_has_fact(runner_result, "actor_read_object")
		and _world_log_has_fact(runner_result, "actor_inspected_trace"),
		"14. Runner 兼容路径仍写入原有三类湖湾镇事实"
	)

	var failed_reload: Dictionary = session.start_from_fixture_data({}, raw_rule_paths)
	_check(
		not bool(failed_reload.get("success", true))
		and not session.is_ready()
		and session.get_action_options().is_empty()
		and session.get_world_log_entries().is_empty(),
		"15. 加载无效世界时清空旧 Session，不会继续操作残留状态"
	)

	_finish()


func _has_action(options: Array, action_id: String) -> bool:
	for option: Dictionary in options:
		if str(option.get("action_id", "")) == action_id:
			return true
	return false


func _world_log_has_fact(result: Dictionary, fact_type: String) -> bool:
	for entry: Dictionary in result.get("world_log", []):
		if fact_type in (entry.get("facts_added", []) as Array):
			return true
	return false


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LIVE SIM SESSION RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 LIVE SIM SESSION FAIL] " + failure)
		print("[V5 LIVE SIM SESSION RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 LIVE SIM SESSION PASS] " + message)
	else:
		failures.append(message)
