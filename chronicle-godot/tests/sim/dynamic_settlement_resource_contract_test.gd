extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_site_fixture.json"
)
const BASE_SEED := 73001
const MULTI_SEEDS := [73001, 73002, 73003]
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline = SimSessionModel.new()
	var start: Dictionary = baseline.start_from_fixture_path(
		FIXTURE_PATH,
		RULE_PATHS,
		{"challenge_seed_override": BASE_SEED}
	)
	var report: Dictionary = start.get("settlement_generation", {})
	var initial_stocks: Array = baseline.stores[
		"resource_stock_store"
	].list_stocks()
	_check(
		bool(start.get("success", false))
		and initial_stocks.size() == 6
		and initial_stocks.size() == (
			report.get("resource_stock_ids", []) as Array
		).size()
		and _stocks_have_sources(initial_stocks),
		"1. 四类自然资源和两条交通运力生成六项有来源的长期库存"
	)
	_check(
		_bindings_reference_stocks(report, initial_stocks)
		and _facilities_expose_bound_stocks(baseline, initial_stocks),
		"2. 入选产业、职业、设施与具体库存互相引用，不只保留资源标签"
	)

	var initial_values := _stock_values(initial_stocks)
	var baseline_tick: Dictionary = baseline.advance_time(
		120,
		"dynamic_resource_baseline_probe",
		{"scope_type": "global", "scope_id": ""}
	)
	var baseline_stocks: Array = baseline.stores[
		"resource_stock_store"
	].list_stocks()
	_check(
		bool(baseline_tick.get("success", false))
		and int(baseline_tick.get("resource_result_count", 0)) > 0
		and _stock_changed(initial_values, baseline_stocks)
		and _stocks_in_bounds(baseline_stocks),
		"3. 五日生产和自然恢复持续改变库存，且水位从不越界"
	)
	_check(
		_fact_count(baseline, "npc_livelihood_produced") > 0
		and _production_facts_use_resources(baseline)
		and _resource_bound_products_have_provenance(baseline),
		"4. 生计产出在同一事实中记录资源消耗，物品来源仍可追溯"
	)
	_check(
		bool(baseline.validate_persistent_references().get("ok", false))
		and str(baseline.get_snapshot().get_region_state_value(
			"migration_tendency", ""
		)) in ["low", "medium", "high"],
		"5. 动态压力进入地区状态，跨 Store 引用在五日后仍完整"
	)

	var atomic_stock: Dictionary = baseline_stocks[0]
	var atomic_stock_id := str(atomic_stock.get("stock_id", ""))
	var atomic_before := float(atomic_stock.get("current", 0.0))
	var health_before := int(baseline.stores["state_store"].get_state(
		"player", "health", 0
	))
	var invalid_result = TransactionResultModel.new()
	invalid_result.add_resource_change({
		"operation": "consume",
		"stock_id": atomic_stock_id,
		"amount": atomic_before + 100.0,
	})
	invalid_result.add_state_change({
		"entity_id": "player", "key": "health", "to": 1,
	})
	invalid_result.mark_resolved("resource_atomicity_probe")
	var atomic_applied: bool = baseline.writer.apply_result(
		invalid_result, baseline.stores
	)
	_check(
		not atomic_applied
		and is_equal_approx(
			float(baseline.stores["resource_stock_store"].get_stock(
				atomic_stock_id
			).get("current", 0.0)),
			atomic_before
		)
		and int(baseline.stores["state_store"].get_state(
			"player", "health", 0
		)) == health_before,
		"6. 资源透支会让统一事务整体拒绝，库存和其他状态都不被部分写入"
	)

	var save_before := baseline.get_save_store_data()
	var envelope: Dictionary = baseline.build_save_envelope({
		"save_id": "save.test.dynamic_settlement_resources",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-14T08:00:00Z",
		"saved_at_utc": "2026-08-19T08:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_result: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(envelope))
	)
	_check(
		bool(restore_result.get("success", false))
		and _equivalent(restored.get_save_store_data(), save_before)
		and _equivalent(
			restored.get_snapshot().get_resource_stocks(),
			baseline.get_snapshot().get_resource_stocks()
		),
		"7. 存档往返精确保留库存水位、恢复参数、状态和最后变化"
	)

	var raw_fixture := _read_json(FIXTURE_PATH)
	var low_fish_fixture := raw_fixture.duplicate(true)
	low_fish_fixture["challenge_seed"] = BASE_SEED
	var generation: Dictionary = low_fish_fixture.get(
		"settlement_generation", {}
	)
	for resource: Dictionary in generation.get("resources", []):
		if "fish" in (resource.get("tags", []) as Array):
			resource["abundance"] = 1
			resource["reliability"] = 1
	var low_fish = SimSessionModel.new()
	var low_start: Dictionary = low_fish.start_from_fixture_data(
		low_fish_fixture, RULE_PATHS
	)
	var low_tick: Dictionary = low_fish.advance_time(
		120,
		"dynamic_resource_low_fish_probe",
		{"scope_type": "global", "scope_id": ""}
	)
	var low_fish_stock := _stock_with_tag(low_fish, "fish")
	var low_fish_before_recovery := low_fish_stock.duplicate(true)
	var blocked_facts := _fact_count(
		low_fish, "npc_livelihood_blocked_resource"
	)
	var baseline_fish_output := _occupation_fact_count(baseline, "net_fisher")
	var low_fish_output := _occupation_fact_count(low_fish, "net_fisher")
	var low_food_pressure_before_recovery := str(
		low_fish.get_snapshot().get_region_state_value("food_pressure", "low")
	)
	_check(
		bool(low_start.get("success", false))
		and bool(low_tick.get("success", false))
		and not low_fish_stock.is_empty()
		and blocked_facts > 0
		and low_fish_output < baseline_fish_output,
		"8. 低鱼量反事实会让渔业停产并减少真实渔获，不会凭职业无限生产"
	)
	_check(
		str(low_fish.get_snapshot().get_region_state_value(
			"food_pressure", "low"
		)) in ["medium", "high"]
		and _fact_count(
			low_fish, "settlement_resource_status_changed"
		) > 0
		and _resource_facility_changed(low_fish, low_fish_stock),
		"9. 资源短缺改变设施状态、粮食压力并形成可追溯事实"
	)

	var before_recovery := float(low_fish_stock.get("current", 0.0))
	low_fish.npc_livelihood_profiles = []
	low_fish.world_tick_adapter.configure_livelihood_profiles([])
	var recovery_tick: Dictionary = low_fish.advance_time(
		48,
		"dynamic_resource_recovery_probe",
		{"scope_type": "global", "scope_id": ""}
	)
	var recovered_stock := _stock_with_tag(low_fish, "fish")
	_check(
		bool(recovery_tick.get("success", false))
		and float(recovered_stock.get("current", 0.0)) > before_recovery
		and str(recovered_stock.get("status", "depleted")) != "depleted"
		and _resource_facility_operational(low_fish, recovered_stock),
		"10. 停止捕捞后鱼群按可靠性恢复，越过开工线后设施自动重启"
	)

	var seed_summaries: Array = []
	var multi_seed_ok := true
	for seed: int in MULTI_SEEDS:
		var session = SimSessionModel.new()
		var seed_start: Dictionary = session.start_from_fixture_path(
			FIXTURE_PATH, [], {"challenge_seed_override": seed}
		)
		var seed_tick: Dictionary = session.advance_time(
			72,
			"dynamic_resource_multi_seed_probe",
			{"scope_type": "global", "scope_id": ""}
		)
		var stocks: Array = session.stores[
			"resource_stock_store"
		].list_stocks()
		var valid := (
			bool(seed_start.get("success", false))
			and bool(seed_tick.get("success", false))
			and _stocks_in_bounds(stocks)
			and bool(session.validate_persistent_references().get("ok", false))
		)
		multi_seed_ok = multi_seed_ok and valid
		seed_summaries.append({
			"seed": seed,
			"valid": valid,
			"stocks": _stock_report(stocks),
			"blocked_production": _fact_count(
				session, "npc_livelihood_blocked_resource"
			),
			"food_pressure": session.get_snapshot().get_region_state_value(
				"food_pressure", ""
			),
		})
	_check(
		multi_seed_ok,
		"11. 三个种子各推进三日后均无负库存、超容量或悬空引用"
	)
	_check(
		_fact_count(low_fish, "settlement_resource_status_changed") >= 2
		and bool(low_fish.validate_persistent_references().get("ok", false)),
		"12. 同一库存能够经历短缺与恢复两个方向，世界历史保留完整"
	)

	print("[V5 DYNAMIC RESOURCE BASELINE] %s" % JSON.stringify({
		"settlement": report.get("settlement_name", ""),
		"stocks": _stock_report(baseline_stocks),
		"production_facts": _fact_count(baseline, "npc_livelihood_produced"),
		"blocked_facts": _fact_count(
			baseline, "npc_livelihood_blocked_resource"
		),
		"food_pressure": baseline.get_snapshot().get_region_state_value(
			"food_pressure", ""
		),
		"migration_tendency": baseline.get_snapshot().get_region_state_value(
			"migration_tendency", ""
		),
	}))
	print("[V5 DYNAMIC RESOURCE LOW FISH] %s" % JSON.stringify({
		"stock_before_recovery": low_fish_before_recovery,
		"stock_after_recovery": recovered_stock,
		"baseline_production": baseline_fish_output,
		"production_before_pause": low_fish_output,
		"blocked_before_pause": blocked_facts,
		"food_pressure_before_recovery": low_food_pressure_before_recovery,
		"food_pressure_after_recovery": low_fish.get_snapshot(
		).get_region_state_value("food_pressure", ""),
	}))
	print("[V5 DYNAMIC RESOURCE MULTI SEED] %s" % JSON.stringify(seed_summaries))
	_finish()


func _stocks_have_sources(stocks: Array) -> bool:
	for stock: Dictionary in stocks:
		if (
			str(stock.get("stock_id", "")) == ""
			or str(stock.get("source_id", "")) == ""
			or str(stock.get("settlement_id", "")) == ""
			or (stock.get("source_fact_ids", []) as Array).is_empty()
			or float(stock.get("capacity", 0.0)) <= 0.0
			or float(stock.get("recovery_per_hour", -1.0)) < 0.0
		):
			return false
	return true


func _bindings_reference_stocks(report: Dictionary, stocks: Array) -> bool:
	var stock_ids := {}
	for stock: Dictionary in stocks:
		stock_ids[str(stock.get("stock_id", ""))] = true
	var bindings: Dictionary = report.get("livelihood_resource_bindings", {})
	if bindings.is_empty():
		return false
	for occupation_id: String in bindings.keys():
		for binding: Dictionary in (bindings[occupation_id] as Array):
			if (
				not stock_ids.has(str(binding.get("stock_id", "")))
				or float(binding.get("amount_per_cycle", 0.0)) <= 0.0
			):
				return false
	return true


func _facilities_expose_bound_stocks(session: Variant, stocks: Array) -> bool:
	var bound_count := 0
	for stock: Dictionary in stocks:
		for feature_id: Variant in stock.get("facility_entity_ids", []):
			bound_count += 1
			var states: Dictionary = session.stores["state_store"].list_states(
				str(feature_id)
			)
			if str(stock.get("stock_id", "")) not in states.get(
				"resource_stock_ids", []
			):
				return false
	return bound_count >= 4


func _stock_values(stocks: Array) -> Dictionary:
	var rows := {}
	for stock: Dictionary in stocks:
		rows[str(stock.get("stock_id", ""))] = float(stock.get("current", 0.0))
	return rows


func _stock_changed(before: Dictionary, stocks: Array) -> bool:
	for stock: Dictionary in stocks:
		var stock_id := str(stock.get("stock_id", ""))
		if not is_equal_approx(
			float(before.get(stock_id, 0.0)), float(stock.get("current", 0.0))
		):
			return true
	return false


func _stocks_in_bounds(stocks: Array) -> bool:
	for stock: Dictionary in stocks:
		var current := float(stock.get("current", 0.0))
		var capacity := float(stock.get("capacity", 0.0))
		if current < -0.0001 or current > capacity + 0.0001:
			return false
	return true


func _production_facts_use_resources(session: Variant) -> bool:
	var bound_occupations: Dictionary = session.settlement_generation_report.get(
		"livelihood_resource_bindings", {}
	)
	var matched := 0
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"npc_livelihood_produced"
	):
		if str(fact.get("occupation_id", "")) not in bound_occupations:
			continue
		matched += 1
		if (fact.get("resource_inputs", []) as Array).is_empty():
			return false
	return matched > 0


func _resource_bound_products_have_provenance(session: Variant) -> bool:
	for item: Dictionary in session.stores["item_store"].list_items():
		if "livelihood_product" not in (item.get("tags", []) as Array):
			continue
		var source_fact_id := str((item.get("provenance", {}) as Dictionary).get(
			"created_by_fact_id", ""
		))
		if source_fact_id == "":
			return false
	return true


func _stock_with_tag(session: Variant, tag: String) -> Dictionary:
	for stock: Dictionary in session.stores[
		"resource_stock_store"
	].list_stocks():
		if tag in (stock.get("tags", []) as Array):
			return stock
	return {}


func _resource_facility_changed(session: Variant, stock: Dictionary) -> bool:
	for feature_id: Variant in stock.get("facility_entity_ids", []):
		if str(session.stores["state_store"].get_state(
			str(feature_id), "resource_status", "abundant"
		)) != "abundant":
			return true
	return false


func _resource_facility_operational(session: Variant, stock: Dictionary) -> bool:
	for feature_id: Variant in stock.get("facility_entity_ids", []):
		if not bool(session.stores["state_store"].get_state(
			str(feature_id), "facility_operational", false
		)):
			return false
	return not (stock.get("facility_entity_ids", []) as Array).is_empty()


func _occupation_fact_count(session: Variant, occupation_id: String) -> int:
	var count := 0
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"npc_livelihood_produced"
	):
		if str(fact.get("occupation_id", "")) == occupation_id:
			count += 1
	return count


func _fact_count(session: Variant, fact_type: String) -> int:
	return session.stores["fact_store"].find_facts_by_type(fact_type).size()


func _stock_report(stocks: Array) -> Array:
	var rows: Array = []
	for stock: Dictionary in stocks:
		rows.append({
			"label": stock.get("label", ""),
			"current": stock.get("current", 0.0),
			"capacity": stock.get("capacity", 0.0),
			"status": stock.get("status", ""),
			"industries": stock.get("industry_ids", []),
		})
	return rows


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


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
			if not _equivalent(
				(left as Array)[index], (right as Array)[index]
			):
				return false
		return true
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	return left == right


func _finish() -> void:
	if failures.is_empty():
		print("[V5 DYNAMIC RESOURCE CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 DYNAMIC RESOURCE CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 DYNAMIC RESOURCE CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 DYNAMIC RESOURCE CONTRACT FAIL] %s" % label)
