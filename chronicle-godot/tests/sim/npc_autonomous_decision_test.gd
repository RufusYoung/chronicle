extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const GIVE_FOOD_ACTION := "give_food_to_hungry_person:chen_mi"

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
	var baseline_tick: Dictionary = baseline.advance_time(1, "after_short_wait")
	_check(
		bool(baseline_start.get("success", false))
		and int(baseline_start.get("autonomous_action_rule_count", 0)) == 2
		and baseline.stores["deferred_consequence_store"]
			.find_pending_consequences()
			.is_empty(),
		"1. 粮铺行为来自自主行动规则，不再来自预排延迟剧情"
	)
	_check(
		_selected_rule(baseline_tick)
			== "merchant_rations_stock_for_hungry_dependent"
		and bool(baseline.get_snapshot().get_entity_state(
			"old_chen_shop_closing_shutters",
			"visible",
			false
		)),
		"2. 缺粮且陈米挨饿时，老陈选择收铺保粮"
	)
	_check(
		_factor_labels(baseline_tick).has("镇上的粮食压力很高")
		and _factor_labels(baseline_tick).has("陈米仍在挨饿"),
		"3. 自主决定保留可解释的效用来源"
	)

	var helped = SimSessionModel.new()
	helped.start_from_fixture_path(FIXTURE_PATH, rules)
	var help_result: Dictionary = helped.execute_action(GIVE_FOOD_ACTION)
	var helped_tick: Dictionary = helped.advance_time(1, "after_short_wait")
	var helped_snapshot: Variant = helped.get_snapshot()
	_check(
		bool(help_result.get("success", false))
		and helped_snapshot.get_entity_state("chen_mi", "hunger", "")
			== "medium"
		and _selected_rule(helped_tick)
			== "merchant_keeps_trading_after_dependent_hunger_eases",
		"4. 外部行动只改变饥饿状态，老陈随后自行选择继续营业"
	)
	_check(
		not bool(helped_snapshot.get_entity_state(
			"old_chen_shop_closing_shutters",
			"visible",
			false
		))
		and str(helped_snapshot.get_entity_state(
			"old_chen_shop_price_notice",
			"price_level",
			""
		)) != "raised_again"
		and helped.stores["fact_store"].find_facts_by_type(
			"merchant_kept_shop_open"
		).size() == 1
		and helped.stores["fact_store"].find_facts_by_type(
			"merchant_closed_shop_early"
		).is_empty(),
		"5. 帮助路径产生不同世界事实，而不是改写同一段收铺文案"
	)

	var loader = SimRegistryModel.new()
	var low_pressure_fixture: Dictionary = loader.load_json(FIXTURE_PATH)
	low_pressure_fixture["region_state"]["food_pressure"] = "low"
	var low_pressure = SimSessionModel.new()
	low_pressure.start_from_fixture_data(low_pressure_fixture, rules)
	var low_pressure_tick: Dictionary = low_pressure.advance_time(
		1,
		"after_short_wait"
	)
	_check(
		int(low_pressure_tick.get("autonomous_decision_count", -1)) == 0
		and low_pressure.stores["fact_store"].find_facts_by_type(
			"merchant_closed_shop_early"
		).is_empty()
		and not bool(low_pressure.get_snapshot().get_entity_state(
			"old_chen_shop_closing_shutters",
			"visible",
			false
		)),
		"6. 区域压力不足时，等待不会硬触发预设剧情"
	)

	var global_fixture: Dictionary = loader.load_json(FIXTURE_PATH)
	var global_entities: Array = global_fixture.get("entities", [])
	global_entities.append_array([
		{
			"id": "granary_merchant",
			"location_id": "abandoned_granary",
			"display_name": "仓边商人",
			"type": "person",
			"tags": ["person", "merchant", "local_family"],
			"states": {
				"visible": false,
				"shop_policy": "open",
				"decision_enabled": true,
				"dependent_id": "granary_dependent",
				"workplace_id": "granary_stall",
				"price_notice_id": "granary_price_notice",
				"closing_detail_id": "granary_closing_detail",
			},
		},
		{
			"id": "granary_dependent",
			"location_id": "abandoned_granary",
			"display_name": "仓边商人的孩子",
			"type": "person",
			"tags": ["person", "child", "local_family"],
			"states": {"visible": false, "hunger": "high"},
		},
		{
			"id": "granary_price_notice",
			"location_id": "abandoned_granary",
			"display_name": "仓边价牌",
			"type": "readable_notice",
			"states": {"visible": false},
		},
		{
			"id": "granary_closing_detail",
			"location_id": "abandoned_granary",
			"display_name": "仓边门板",
			"type": "environment_detail",
			"states": {"visible": false},
		},
	])
	global_fixture["entities"] = global_entities
	var global_session = SimSessionModel.new()
	global_session.start_from_fixture_data(global_fixture, rules)
	var global_tick: Dictionary = global_session.advance_time(
		1,
		"after_short_wait"
	)
	_check(
		int(global_tick.get("autonomous_decision_count", 0)) == 2
		and int(global_tick.get(
			"observed_autonomous_decision_count",
			0
		)) == 1
		and _fact_count_for_actor(
			global_session,
			"merchant_closed_shop_early",
			"old_chen"
		) == 1
		and _fact_count_for_actor(
			global_session,
			"merchant_closed_shop_early",
			"granary_merchant"
		) == 1
		and bool(global_session.stores["state_store"].get_state(
			"granary_closing_detail",
			"visible",
			false
		)),
		"7. 同一通用规则会驱动异地商人，且不依赖玩家当前地点"
	)

	_finish()


func _selected_rule(tick_result: Dictionary) -> String:
	var decisions: Array = tick_result.get("autonomous_decisions", [])
	if decisions.is_empty():
		return ""
	return str((decisions[0] as Dictionary).get("rule_id", ""))


func _factor_labels(tick_result: Dictionary) -> Array:
	var rows: Array = []
	var decisions: Array = tick_result.get("autonomous_decisions", [])
	if decisions.is_empty():
		return rows
	for factor: Dictionary in (decisions[0] as Dictionary).get(
		"matched_factors",
		[]
	):
		rows.append(str(factor.get("label", "")))
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


func _finish() -> void:
	if failures.is_empty():
		print("[V5 NPC AUTONOMOUS DECISION RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 NPC AUTONOMOUS DECISION FAIL] " + failure)
		print(
			"[V5 NPC AUTONOMOUS DECISION RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 NPC AUTONOMOUS DECISION PASS] " + message)
	else:
		failures.append(message)
