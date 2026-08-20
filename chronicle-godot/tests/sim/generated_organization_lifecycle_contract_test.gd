extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const WorldTickAdapterModel = preload(
	"res://scripts/sim/world_tick/world_tick_adapter.gd"
)
const SnapshotBuilderModel = preload(
	"res://scripts/sim/core/sim_snapshot_builder.gd"
)
const OrganizationResponseSystemModel = preload(
	"res://scripts/sim/organization/organization_response_system.gd"
)
const LiveLocationViewModel = preload(
	"res://scripts/rebuild/v5_live_location_view_model.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_organization_lifecycle.save.json"
const SETTLEMENT_ID := "generated_settlement.river_steps"
const HUB_ID := "generated_location.river_steps.commons"
const ORGANIZATION_ID := (
	"runtime_organization.river_steps.provision_circle.cycle1"
)
const SECOND_ORGANIZATION_ID := (
	"runtime_organization.river_steps.provision_circle.cycle2"
)
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = _start(81001)
	_check(
		session != null
		and session.is_ready()
		and _lifecycle_configured(session),
		"1. G4-C2 组织生命周期通过正式 SimSession 装载原型配置"
	)
	if session == null or not session.is_ready():
		_finish()
		return
	var adapter: Variant = _isolated_adapter(session)

	_inject_food_level(session, false)
	var day1 := _apply_tick(adapter, session, 1, "high_pressure_day1")
	_check(
		bool(day1.get("success", false))
		and _facts(session, "organization_lifecycle_signal_observed").size() == 1
		and _facts(session, "organization_runtime_formed").is_empty(),
		"2. 测试注入缺粮后的首日只积累社会压力，不瞬间生成组织"
	)
	var day1_fact_count := _facts(
		session, "organization_lifecycle_signal_observed"
	).size()
	_apply_tick(adapter, session, 1, "same_day_repeat")
	_check(
		_facts(session, "organization_lifecycle_signal_observed").size()
		== day1_fact_count
		and _facts(session, "organization_runtime_formed").is_empty(),
		"3. 同一日重复 Tick 不会复制压力观察或提前成立组织"
	)

	var day2 := _apply_tick(adapter, session, 2, "high_pressure_day2")
	var organization := _entity(session, ORGANIZATION_ID)
	var founder_ids: Array = organization.get("founding_member_ids", [])
	_check(
		bool(day2.get("success", false))
		and str(organization.get("lifecycle_status", "active")) == "active"
		and "runtime_organization" in (organization.get("tags", []) as Array)
		and founder_ids.size() >= 1,
		"4. 连续两日高粮压使河阶坞自行形成第一代临时共食会"
	)
	_check(
		_founders_are_real_local_adults(session, organization)
		and _organization_resources_are_real(session, organization)
		and _formation_sources_exist(session),
		"5. 创始职位由当地真实成年人承担，物资与成立事实均可追溯"
	)

	session.context.set_current_location(HUB_ID)
	var view_model = LiveLocationViewModel.new(session)
	view_model.latest_event_type = "world_tick"
	view_model.latest_result = day2.duplicate(true)
	var formation_view := JSON.stringify(view_model.build_view_data())
	_check(
		str(organization.get("display_name", "")) in formation_view
		and "latest_organization_lifecycle" in formation_view
		and "组织成立" in formation_view
		and "持续粮压" in formation_view,
		"6. 当前聚落界面直接说明组织为何成立，不把关键因果藏在后台"
	)

	_prepare_provisioning_stocks(session)
	var response := _apply_response(session, 2)
	var local_actions := _facts(
		session, "organization_local_provisions_transferred"
	)
	_check(
		bool(response.get("applied", false))
		and _has_actor(local_actions, ORGANIZATION_ID),
		"7. 新组织复用通用响应系统，能调拨真实库存而非只写成立文本"
	)

	var quiet = _start(81001)
	var quiet_adapter: Variant = _isolated_adapter(quiet)
	_apply_tick(quiet_adapter, quiet, 1, "quiet_counterfactual_day1")
	_apply_tick(quiet_adapter, quiet, 2, "quiet_counterfactual_day2")
	_check(
		_facts(quiet, "organization_runtime_formed").is_empty()
		and _entity(quiet, ORGANIZATION_ID).is_empty(),
		"8. 相同种子未遭持续粮压时不生成共食会，反事实路径不同"
	)

	_inject_food_level(session, true)
	var day3 := _apply_tick(adapter, session, 3, "recovery_day1")
	var recovery_goal := str(_entity(session, ORGANIZATION_ID).get("goal", ""))
	_check(
		bool(day3.get("success", false))
		and _facts(session, "organization_goal_changed").size() == 1
		and "准备结束临时职责" in recovery_goal,
		"9. 粮压首日缓解后组织先转向核清余项，不立即消失"
	)

	var day4 := _apply_tick(adapter, session, 4, "recovery_day2")
	var retired := _entity(session, ORGANIZATION_ID)
	_check(
		bool(day4.get("success", false))
		and str(retired.get("lifecycle_status", "")) == "retired"
		and int(retired.get("retired_day", 0)) == 4
		and _founder_roles_cleared(session, founder_ids),
		"10. 连续两日缓解后临时组织软退场，成员卸任而历史实体保留"
	)
	view_model.latest_result = day4.duplicate(true)
	var retirement_view := JSON.stringify(view_model.build_view_data())
	_check(
		"组织退场" in retirement_view
		and "结束临时职责" in retirement_view,
		"11. 界面展示组织退场及原因，退场组织不再冒充当前组织"
	)

	_inject_food_level(session, false)
	_apply_tick(adapter, session, 5, "cooldown_day1")
	_apply_tick(adapter, session, 6, "cooldown_day2")
	_check(
		_facts(session, "organization_runtime_formed").size() == 1
		and _entity(session, SECOND_ORGANIZATION_ID).is_empty(),
		"12. 退场后三日冷却阻止组织因短期波动反复开关"
	)
	_apply_tick(adapter, session, 7, "second_cycle_day1")
	_apply_tick(adapter, session, 8, "second_cycle_day2")
	_check(
		_facts(session, "organization_runtime_formed").size() == 2
		and str(_entity(session, SECOND_ORGANIZATION_ID).get(
			"lifecycle_status", "active"
		)) == "active",
		"13. 冷却后再次持续缺粮会形成第二代组织，而非复活已退场实体"
	)

	var save_before: Dictionary = session.get_save_store_data()
	var save_report: Dictionary = session.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_organization_lifecycle",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-20T08:00:00Z",
		"saved_at_utc": "2026-08-20T09:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	var reference_report: Dictionary = (
		restored.validate_persistent_references()
		if bool(restore_report.get("success", false))
		else {"ok": false, "error": "restore_failed"}
	)
	if (
		not bool(save_report.get("ok", false))
		or not bool(restore_report.get("success", false))
		or not bool(reference_report.get("ok", false))
	):
		print("[V5 ORGANIZATION LIFECYCLE SAVE DEBUG] %s" % JSON.stringify({
			"save_ok": bool(save_report.get("ok", false)),
			"save_error": str(save_report.get("error", "")),
			"restore_success": bool(restore_report.get("success", false)),
			"restore_error": str(restore_report.get("error", "")),
			"references": reference_report,
		}))
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and _equivalent(save_before, restored.get_save_store_data())
		and bool(reference_report.get("ok", false))
		and _lifecycle_signature(restored) == _lifecycle_signature(session),
		"14. 磁盘存档精确保留两代组织、退场状态、成员与来源事实"
	)

	print("[V5 ORGANIZATION LIFECYCLE SAMPLE] %s" % JSON.stringify({
		"formed": _facts(session, "organization_runtime_formed"),
		"goal_changed": _facts(session, "organization_goal_changed"),
		"retired": _facts(session, "organization_runtime_retired"),
		"response": local_actions,
	}))
	_finish()


func _start(seed: int) -> Variant:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		print("[V5 ORGANIZATION LIFECYCLE START FAILURE] %s" % JSON.stringify(start))
		return null
	return session


func _isolated_adapter(session: Variant) -> Variant:
	var adapter = WorldTickAdapterModel.new()
	adapter.configure_organization_runtime(
		session.world_tick_adapter.organization_runtime_config
	)
	return adapter


func _apply_tick(
	adapter: Variant, session: Variant, day: int, source: String
) -> Dictionary:
	return adapter.apply_tick_event(session.context, session.stores, {
		"tick_event_id": "test.organization_lifecycle.%s.day%d" % [source, day],
		"tick_type": "test_event",
		"trigger_key": "test_organization_lifecycle",
		"scope_type": "global",
		"scope_id": "",
		"source": "generated_organization_lifecycle_contract_test",
		"label": "组织生命周期测试注入",
		"day": day,
		"hour": 8,
		"elapsed_hours": 0,
		"include_due_checks": false,
	})


func _inject_food_level(session: Variant, full: bool) -> void:
	for stock: Dictionary in session.stores[
		"resource_stock_store"
	].list_stocks():
		if (
			str(stock.get("settlement_id", "")) != SETTLEMENT_ID
			or "food" not in (stock.get("tags", []) as Array)
		):
			continue
		session.stores["resource_stock_store"].apply_resource_change({
			"operation": "set",
			"stock_id": str(stock.get("stock_id", "")),
			"amount": float(stock.get("capacity", 0.0)) if full else 0.0,
			"tick": 0,
			"reason": "test_injection_food_full" if full else "test_injection_food_empty",
		})


func _prepare_provisioning_stocks(session: Variant) -> void:
	var source_set := false
	for stock: Dictionary in session.stores[
		"resource_stock_store"
	].list_stocks():
		if (
			str(stock.get("settlement_id", "")) != SETTLEMENT_ID
			or "food" not in (stock.get("tags", []) as Array)
		):
			continue
		var is_reserve := str(stock.get("source_kind", "")) == "trade_reserve"
		var amount := 0.0
		if not is_reserve and not source_set:
			amount = minf(float(stock.get("capacity", 0.0)), 6.0)
			source_set = true
		session.stores["resource_stock_store"].apply_resource_change({
			"operation": "set",
			"stock_id": str(stock.get("stock_id", "")),
			"amount": amount,
			"tick": 0,
			"reason": "test_injection_provisioning_stock_shape",
		})


func _apply_response(session: Variant, day: int) -> Dictionary:
	var snapshot = SnapshotBuilderModel.new().build_snapshot(
		session.context, session.stores, true
	)
	var data: Dictionary = OrganizationResponseSystemModel.new().resolve_tick(
		snapshot,
		{
			"tick_event_id": "test.dynamic_organization_response.day%d" % day,
			"day": day,
			"hour": 9,
		},
		session.world_tick_adapter.organization_runtime_config,
		session.get_settlement_network_summary()
	)
	var applied := false
	for result: Variant in data.get("results", []):
		if session.writer.apply_result(result, session.stores):
			applied = true
	return {"applied": applied, "data": data}


func _lifecycle_configured(session: Variant) -> bool:
	var config: Dictionary = session.world_tick_adapter.organization_runtime_config
	if not bool(config.get("lifecycle_enabled", false)):
		return false
	for value: Variant in config.get("lifecycle_prototypes", []):
		if (
			value is Dictionary
			and str((value as Dictionary).get("prototype_id", ""))
			== "provision_circle"
			and not ((value as Dictionary).get(
				"lifecycle", {}
			) as Dictionary).is_empty()
		):
			return true
	return false


func _entity(session: Variant, entity_id: String) -> Dictionary:
	if session == null:
		return {}
	return session.stores["entity_store"].get_entity(entity_id)


func _facts(session: Variant, fact_type: String) -> Array:
	if session == null:
		return []
	return session.stores["fact_store"].find_facts_by_type(fact_type)


func _founders_are_real_local_adults(
	session: Variant, organization: Dictionary
) -> bool:
	var founders: Array = organization.get("founding_member_ids", [])
	if founders.is_empty():
		return false
	for position: Dictionary in organization.get("positions", []):
		var member_id := str(position.get("founding_holder_id", ""))
		if member_id == "":
			continue
		if (
			str(_entity(session, member_id).get("type", "")) != "person"
			or str(session.stores["state_store"].get_state(
				member_id, "settlement_id", ""
			)) != SETTLEMENT_ID
			or int(session.stores["state_store"].get_state(
				member_id, "age_years", 0
			)) < 18
			or str(session.stores["state_store"].get_state(
				member_id, "institution_role", ""
			)) != "%s::%s" % [
				ORGANIZATION_ID, str(position.get("position_id", ""))
			]
			or int(session.stores["relationship_store"].get_relation(
				ORGANIZATION_ID, member_id, "familiarity", 0
			)) <= 0
		):
			return false
	return true


func _organization_resources_are_real(
	session: Variant, organization: Dictionary
) -> bool:
	var stock_ids: Array = organization.get("resource_stock_ids", [])
	if stock_ids.is_empty():
		return false
	for value: Variant in stock_ids:
		var stock: Dictionary = session.stores[
			"resource_stock_store"
		].get_stock(str(value))
		if (
			stock.is_empty()
			or str(stock.get("settlement_id", "")) != SETTLEMENT_ID
		):
			return false
	return true


func _formation_sources_exist(session: Variant) -> bool:
	var facts := _facts(session, "organization_runtime_formed")
	if facts.size() != 1:
		return false
	for source_value: Variant in (facts[0] as Dictionary).get(
		"source_fact_ids", []
	):
		var source: Dictionary = session.stores["fact_store"].get_fact(
			str(source_value)
		)
		if (
			source.is_empty()
			or str(source.get("fact_type", ""))
			!= "organization_lifecycle_signal_observed"
		):
			return false
	return true


func _has_actor(facts: Array, organization_id: String) -> bool:
	for fact: Dictionary in facts:
		if str(fact.get("organization_id", "")) == organization_id:
			return true
	return false


func _founder_roles_cleared(session: Variant, founder_ids: Array) -> bool:
	for member_value: Variant in founder_ids:
		if str(session.stores["state_store"].get_state(
			str(member_value), "institution_role", ""
		)).begins_with(ORGANIZATION_ID):
			return false
	return true


func _lifecycle_signature(session: Variant) -> String:
	var rows: Array[Dictionary] = []
	for fact_type: String in [
		"organization_runtime_formed",
		"organization_goal_changed",
		"organization_runtime_retired",
	]:
		for fact: Dictionary in _facts(session, fact_type):
			rows.append({
				"fact_type": fact_type,
				"organization_id": str(fact.get("organization_id", "")),
				"day": int(fact.get("day", 0)),
				"source_fact_ids": (
					fact.get("source_fact_ids", []) as Array
				).duplicate(),
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
		print("[V5 ORGANIZATION LIFECYCLE CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 ORGANIZATION LIFECYCLE CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 ORGANIZATION LIFECYCLE CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 ORGANIZATION LIFECYCLE CONTRACT FAIL] %s" % label)
