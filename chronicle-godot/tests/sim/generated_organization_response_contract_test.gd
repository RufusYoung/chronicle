extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_organization_response.save.json"
const PROVISION_ORGANIZATION_ID := (
	"generated_organization.reed_bay.provision_circle"
)
const TRADE_ORGANIZATION_ID := (
	"generated_organization.river_steps.road_fellows"
)
const WATCH_ORGANIZATION_ID := "generated_organization.wind_pass.pass_watch"
const REED_SETTLEMENT_ID := "generated_settlement.reed_bay"
const LINK_ID := "river_steps_wind_pass"
const REED_FOOD_SOURCE_ID := (
	"resource_stock.reed_bay.resource_reed_bay_fish"
)
const REED_FOOD_RESERVE_ID := "resource_stock.reed_bay.trade.food"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline = _start(81001)
	_check(
		baseline != null and baseline.is_ready(),
		"1. G4-B2 组织响应合同通过正式 SimSession 启动"
	)
	if baseline == null or not baseline.is_ready():
		_finish()
		return
	_check(
		_action_kind(baseline, PROVISION_ORGANIZATION_ID) == "local_provisioning"
		and _action_kind(baseline, TRADE_ORGANIZATION_ID) == "trade_coordination"
		and _action_kind(baseline, WATCH_ORGANIZATION_ID) == "route_patrol",
		"2. 同一世界种子按场址条件实际生成三种组织与三种响应合同"
	)

	_advance(baseline, 1, "organization_response_day1")
	var trade_actions := _facts(baseline, "organization_trade_coordinated")
	var patrol_actions := _facts(baseline, "organization_route_patrolled")
	_check(
		trade_actions.size() == 1
		and patrol_actions.size() == 1
		and _action_fact_is_sourceful(baseline, trade_actions[0])
		and _action_fact_is_sourceful(baseline, patrol_actions[0]),
		"3. 缺粮邻镇与高风险道路分别触发同业会协调和守路队巡守"
	)
	var action_count_before := _all_action_facts(baseline).size()
	_advance(baseline, 1, "organization_response_same_day")
	_check(
		_all_action_facts(baseline).size() == action_count_before,
		"4. 同一日重复 Tick 不会重复消耗运力或复制组织行动事实"
	)

	_advance_until_day(baseline, 2, "organization_response_effect_day2")
	var affected_trade := _affected_trade_fact(baseline, 2)
	_check(
		not affected_trade.is_empty()
		and float(affected_trade.get("organization_capacity_bonus", 0.0)) == 2.0
		and int(affected_trade.get("effective_route_risk", 99)) == 2
		and float(affected_trade.get(
			"organization_transport_cost_reduction", 0.0
		)) == 0.2,
		"5. 次日货运真实获得 2 点吞吐加成，并降低风险与运输消耗"
	)
	_check(
		_trade_sources_include_actions(
			baseline, affected_trade, trade_actions[0], patrol_actions[0]
		),
		"6. 受影响货运反向引用同业会与守路队行动事实，因果链完整"
	)

	var provisioning = _start(81001)
	_inject_local_food_shortage(provisioning)
	_advance(provisioning, 1, "organization_response_provisioning")
	var provision_actions := _facts(
		provisioning, "organization_local_provisions_transferred"
	)
	_check(
		provision_actions.size() == 1
		and float(provision_actions[0].get("amount", 0.0)) == 2.0
		and _provision_transfer_is_conserved(provisioning, provision_actions[0]),
		"7. 测试注入本地缺粮后，共食会等量转移真实食物与储备"
	)

	var unavailable = _start(81001)
	_inject_all_organizations_unstaffed(unavailable)
	_advance(unavailable, 1, "organization_response_unstaffed")
	_check(
		_all_action_facts(unavailable).is_empty(),
		"8. 测试注入全部职位缺员时不执行调粮、协调或巡守"
	)
	var closed_routes = _start(81001)
	_inject_closed_routes(closed_routes)
	_advance(closed_routes, 1, "organization_response_closed_routes")
	_check(
		_facts(closed_routes, "organization_trade_coordinated").is_empty()
		and _facts(closed_routes, "organization_route_patrolled").is_empty()
		and _facts(closed_routes, "settlement_trade_shipment").is_empty(),
		"9. 测试注入道路容量为零时，组织加成不会把封闭道路变成货路"
	)

	var repeated = _start(81001)
	_advance(repeated, 1, "organization_response_repeat_day1")
	_advance_until_day(repeated, 2, "organization_response_repeat_day2")
	_check(
		_response_signature(repeated) == _response_signature(baseline),
		"10. 相同种子与压力路径完全复现组织行动和道路后果"
	)

	var save_before: Dictionary = baseline.get_save_store_data()
	var save_report: Dictionary = baseline.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_organization_response",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-18T15:00:00Z",
		"saved_at_utc": "2026-08-22T08:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and _equivalent(save_before, restored.get_save_store_data())
		and _response_signature(restored) == _response_signature(baseline)
		and bool(restored.validate_persistent_references().get("ok", false)),
		"11. 磁盘存档精确保留组织响应、道路效果、资源变化与来源引用"
	)

	print("[V5 ORGANIZATION RESPONSE SAMPLE] %s" % JSON.stringify({
		"day1_trade_action": trade_actions[0] if not trade_actions.is_empty() else {},
		"day1_patrol_action": patrol_actions[0] if not patrol_actions.is_empty() else {},
		"day2_trade": affected_trade,
		"provisioning": provision_actions[0] if not provision_actions.is_empty() else {},
	}))
	_finish()


func _start(seed: int) -> Variant:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		print("[V5 ORGANIZATION RESPONSE START FAILURE] %s" % JSON.stringify(start))
		return null
	return session


func _advance(session: Variant, hours: int, source: String) -> void:
	for _hour: int in range(hours):
		session.advance_time(1, source)


func _advance_until_day(session: Variant, day: int, source: String) -> void:
	var guard := 0
	while int(session.get_time_summary().get("day", 0)) < day and guard < 48:
		session.advance_time(1, source)
		guard += 1


func _action_kind(session: Variant, organization_id: String) -> String:
	var organization: Dictionary = session.stores[
		"entity_store"
	].get_entity(organization_id)
	return str((organization.get("runtime_response", {}) as Dictionary).get(
		"action_kind", ""
	))


func _facts(session: Variant, fact_type: String) -> Array:
	return session.stores["fact_store"].find_facts_by_type(fact_type)


func _all_action_facts(session: Variant) -> Array:
	var rows: Array = []
	for fact_type: String in [
		"organization_local_provisions_transferred",
		"organization_trade_coordinated",
		"organization_route_patrolled",
	]:
		rows.append_array(_facts(session, fact_type))
	return rows


func _action_fact_is_sourceful(session: Variant, fact: Dictionary) -> bool:
	var source_fact_ids: Array = fact.get("source_fact_ids", [])
	if source_fact_ids.is_empty():
		return false
	for value: Variant in source_fact_ids:
		if session.stores["fact_store"].get_fact(str(value)).is_empty():
			return false
	var stock_id := str(fact.get("traffic_stock_id", ""))
	var stock: Dictionary = session.stores["resource_stock_store"].get_stock(
		stock_id
	)
	return (
		not stock.is_empty()
		and str(stock.get("last_operation", "")) == "consume"
		and str(fact.get("fact_id", "")) in (
			stock.get("last_source_fact_ids", []) as Array
		)
	)


func _affected_trade_fact(session: Variant, day: int) -> Dictionary:
	for fact: Dictionary in _facts(session, "settlement_trade_shipment"):
		if (
			str(fact.get("link_id", "")) == LINK_ID
			and int(fact.get("day", 0)) == day
			and float(fact.get("organization_capacity_bonus", 0.0)) > 0.0
			and int(fact.get("effective_route_risk", 99))
			< int(fact.get("base_route_risk", 0))
		):
			return fact
	return {}


func _trade_sources_include_actions(
		session: Variant,
		trade_fact: Dictionary,
		coordination_fact: Dictionary,
		patrol_fact: Dictionary
) -> bool:
	var sources: Array = trade_fact.get("source_fact_ids", [])
	for action_fact: Dictionary in [coordination_fact, patrol_fact]:
		var fact_id := str(action_fact.get("fact_id", ""))
		if fact_id not in sources or session.stores["fact_store"].get_fact(
			fact_id
		).is_empty():
			return false
	return true


func _inject_local_food_shortage(session: Variant) -> void:
	session.stores["resource_stock_store"].apply_resource_change({
		"operation": "set",
		"stock_id": REED_FOOD_SOURCE_ID,
		"amount": 5.0,
		"tick": 0,
		"reason": "test_injection_food_shortage",
	})
	session.stores["resource_stock_store"].apply_resource_change({
		"operation": "set",
		"stock_id": REED_FOOD_RESERVE_ID,
		"amount": 0.0,
		"tick": 0,
		"reason": "test_injection_food_shortage",
	})


func _provision_transfer_is_conserved(
		session: Variant, fact: Dictionary
) -> bool:
	var fact_id := str(fact.get("fact_id", ""))
	var amount := float(fact.get("amount", 0.0))
	var source: Dictionary = session.stores["resource_stock_store"].get_stock(
		str(fact.get("source_stock_id", ""))
	)
	var destination: Dictionary = session.stores[
		"resource_stock_store"
	].get_stock(str(fact.get("destination_stock_id", "")))
	return (
		amount > 0.0
		and is_equal_approx(float(source.get("last_delta", 0.0)), -amount)
		and is_equal_approx(float(destination.get("last_delta", 0.0)), amount)
		and fact_id in (source.get("last_source_fact_ids", []) as Array)
		and fact_id in (destination.get("last_source_fact_ids", []) as Array)
	)


func _inject_all_organizations_unstaffed(session: Variant) -> void:
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		var entity_id := str(entity.get("id", ""))
		if (
			str(entity.get("type", "")) == "person"
			and str(session.stores["state_store"].get_state(
				entity_id, "institution_role", ""
			)).begins_with("generated_organization.")
		):
			session.stores["state_store"].apply_state_change({
				"entity_id": entity_id,
				"key": "institution_role",
				"to": "",
			})


func _inject_closed_routes(session: Variant) -> void:
	var runtime: Dictionary = session.get_settlement_network_summary()
	for link: Dictionary in runtime.get("links", []):
		link["capacity_per_day"] = 0.0
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)


func _response_signature(session: Variant) -> String:
	var rows: Array[Dictionary] = []
	for fact: Dictionary in _all_action_facts(session):
		rows.append({
			"fact_type": str(fact.get("fact_type", "")),
			"organization_id": str(fact.get("organization_id", "")),
			"link_id": str(fact.get("link_id", "")),
			"amount": float(fact.get("amount", 0.0)),
			"day": int(fact.get("day", 0)),
		})
	for fact: Dictionary in _facts(session, "settlement_trade_shipment"):
		if (
			str(fact.get("link_id", "")) == LINK_ID
			and float(fact.get("organization_capacity_bonus", 0.0)) > 0.0
		):
			rows.append({
				"fact_type": "affected_trade",
				"organization_id": "",
				"link_id": LINK_ID,
				"amount": float(fact.get("amount", 0.0)),
				"day": int(fact.get("day", 0)),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	return JSON.stringify(rows)


func _equivalent(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		if (left as Dictionary).size() != (right as Dictionary).size():
			return false
		for key: Variant in (left as Dictionary).keys():
			if (
				not (right as Dictionary).has(key)
				or not _equivalent(
					(left as Dictionary).get(key),
					(right as Dictionary).get(key)
				)
			):
				return false
		return true
	if left is Array and right is Array:
		if (left as Array).size() != (right as Array).size():
			return false
		for index: int in range((left as Array).size()):
			if not _equivalent((left as Array)[index], (right as Array)[index]):
				return false
		return true
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	return left == right


func _finish() -> void:
	if failures.is_empty():
		print("[V5 ORGANIZATION RESPONSE CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 ORGANIZATION RESPONSE CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 ORGANIZATION RESPONSE CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 ORGANIZATION RESPONSE CONTRACT FAIL] %s" % label)
