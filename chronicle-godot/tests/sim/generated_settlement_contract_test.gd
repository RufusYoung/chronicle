extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_site_fixture.json"
)
const FIRST_SEED := 73001
const SEEDS := [73001, 73002, 73003, 73004, 73005]
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw_fixture := _read_json(FIXTURE_PATH)
	_check(
		(raw_fixture.get("locations", {}) as Dictionary).is_empty()
		and (raw_fixture.get("entities", []) as Array).is_empty()
		and not (raw_fixture.get("settlement_generation", {}) as Dictionary).is_empty(),
		"1. 原始场址没有预写聚落、设施、道路或居民"
	)

	var first = SimSessionModel.new()
	var first_start: Dictionary = first.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": FIRST_SEED}
	)
	var report: Dictionary = first_start.get("settlement_generation", {})
	var resident_report: Dictionary = first_start.get("resident_generation", {})
	_check(
		bool(first_start.get("success", false))
		and bool(report.get("integrity", {}).get("ok", false))
		and bool(resident_report.get("integrity", {}).get("ok", false)),
		"2. 正式 SimSession 先生成聚落再生成居民，两层完整性校验均通过"
	)
	_check(
		int(report.get("resident_capacity", 0)) >= int(
			report.get("population_target", 0)
		)
		and int(report.get("population_target", 0)) == int(
			resident_report.get("resident_count", -1)
		)
		and int(report.get("resource_support", 0)) > 0
		and int(report.get("traffic_capacity", 0)) == 5,
		"3. 人口目标由地形、资源和交通承载力反推且不超过容量"
	)

	var location_ids: Array = report.get("generated_location_ids", [])
	var route_ids: Array = report.get("generated_route_ids", [])
	var industry_ids: Array = report.get("industry_ids", [])
	_check(
		location_ids.size() >= 4
		and route_ids.size() == (location_ids.size() - 1) * 2
		and industry_ids.size() == location_ids.size() - 1
		and _all_locations_exist(first, location_ids)
		and _all_routes_reference_generated_locations(first, route_ids, location_ids),
		"4. 产业生成可执行设施及双向内部道路，全部地点引用真实存在"
	)
	_check(
		_all_generated_residents_use_bound_workplaces(
			first,
			resident_report.get("resident_ids", []),
			report.get("workplace_bindings", {}),
			location_ids
		)
		and _all_generated_workplaces_staffed(
			first,
			resident_report.get("resident_ids", []),
			report.get("workplace_bindings", {})
		),
		"5. 生成居民只进入实际形成的产业，工作地点来自聚落生成绑定"
	)
	_check(
		_has_fact_type(first, "settlement_generated")
		and _fact_count(first, "settlement_industry_selected") == industry_ids.size()
		and not str(report.get("signature", "")).is_empty()
		and not first.get_action_options().is_empty(),
		"6. 容量与产业选择写入带种子和来源的事实及生成签名"
	)

	var hub_options: Array = first.get_travel_options()
	var outward_route_id := str((hub_options.front() as Dictionary).get(
		"route_id", ""
	)) if not hub_options.is_empty() else ""
	var travel_result: Dictionary = first.travel(outward_route_id)
	var destination: Variant = first.get_snapshot()
	_check(
		hub_options.size() == industry_ids.size()
		and bool(travel_result.get("success", false))
		and "generated_facility" in destination.location.get("tags", [])
		and not destination.get_visible_entities().is_empty()
		and not first.get_action_options().is_empty()
		and first.get_travel_options().size() == 1,
		"7. 正式旅行可从生成集地进入设施，现场有可观察对象并能返回"
	)

	var tick_result: Dictionary = first.advance_time(
		18, "generated_settlement_livelihood_probe"
	)
	_check(
		bool(tick_result.get("success", false))
		and _fact_count(first, "npc_livelihood_produced") > 0,
		"8. 生成设施承接正式生计循环，居民会在其中生产真实物品"
	)

	var repeated = SimSessionModel.new()
	var repeated_start: Dictionary = repeated.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": FIRST_SEED}
	)
	_check(
		bool(repeated_start.get("success", false))
		and _equivalent(
			repeated.settlement_generation_report,
			report
		)
		and _equivalent(
			repeated.resident_generation_report,
			resident_report
		),
		"9. 同一场址与种子产生完全相同的聚落和居民生成摘要"
	)

	var signatures := {}
	var multi_seed_ok := true
	for seed: int in SEEDS:
		var session = SimSessionModel.new()
		var start: Dictionary = session.start_from_fixture_path(
			FIXTURE_PATH, [], {"challenge_seed_override": seed}
		)
		var seed_report: Dictionary = start.get("settlement_generation", {})
		if (
			not bool(start.get("success", false))
			or not bool(seed_report.get("integrity", {}).get("ok", false))
			or int(seed_report.get("population_target", 0)) > int(
				seed_report.get("resident_capacity", 0)
			)
		):
			multi_seed_ok = false
		signatures[str(seed_report.get("signature", ""))] = true
	_check(
		multi_seed_ok and signatures.size() >= 2,
		"10. 五个种子全部满足容量与完整性约束，并形成至少两种结构"
	)

	var road_fixture := raw_fixture.duplicate(true)
	road_fixture["challenge_seed"] = 73100
	var site: Dictionary = road_fixture.get("settlement_generation", {})
	site["terrain"] = {
		"terrain_id": "river_terrace",
		"tags": ["riverside", "fertile", "roadside"],
		"habitable_area": 4,
		"flood_exposure": 1,
	}
	site["resources"] = [
		{
			"resource_id": "resource.deep_soil",
			"tags": ["soil", "roots", "food"],
			"abundance": 5,
			"reliability": 5,
		},
		{
			"resource_id": "resource.road_timber",
			"tags": ["timber"],
			"abundance": 3,
			"reliability": 4,
		},
	]
	site["traffic"] = [
		{
			"traffic_id": "traffic.main_cart_road",
			"mode": "road",
			"capacity": 5,
			"reliability": 5,
			"risk": 1,
		},
	]
	var road_start: Dictionary = SimSessionModel.new().start_from_fixture_data(
		road_fixture, []
	)
	var road_report: Dictionary = road_start.get("settlement_generation", {})
	_check(
		bool(road_start.get("success", false))
		and "terrace_farming" in road_report.get("industry_ids", [])
		and "road_carting" in road_report.get("industry_ids", [])
		and "fishery" not in road_report.get("industry_ids", []),
		"11. 改变地形、资源和交通会因明确分数来源改变产业结构"
	)

	var before_save := first.get_save_store_data()
	var envelope: Dictionary = first.build_save_envelope({
		"save_id": "save.test.generated_settlement",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-14T08:00:00Z",
		"saved_at_utc": "2026-08-14T16:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_result: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(envelope))
	)
	_check(
		bool(restore_result.get("success", false))
		and _equivalent(restored.get_save_store_data(), before_save)
		and str(restored.settlement_generation_report.get(
			"signature", ""
		)) == str(report.get("signature", ""))
		and str(restored.context.location_id) == str(first.context.location_id),
		"12. 存档往返保留聚落、居民、当前位置及两层生成报告，不会重抽"
	)

	var social_result: Dictionary = first.advance_time(
		102,
		"generated_settlement_social_exchange_probe",
		{"scope_type": "global", "scope_id": ""}
	)
	var social_exchange_count := (
		_fact_count(first, "npc_cross_household_shared_food")
		+ _fact_count(first, "npc_cross_household_food_request_failed")
	)
	_check(
		bool(social_result.get("success", false))
		and social_exchange_count > 0
		and bool(first.validate_persistent_references().get("ok", false)),
		"13. 推进五天后生成家庭发生真实食物援助或求助受挫且引用完整"
	)

	var broken_fixture := raw_fixture.duplicate(true)
	(broken_fixture.get("settlement_generation", {}) as Dictionary)[
		"terrain"
	] = {"terrain_id": "missing_terrain"}
	var broken_start: Dictionary = SimSessionModel.new().start_from_fixture_data(
		broken_fixture, []
	)
	_check(
		not bool(broken_start.get("success", false))
		and str(broken_start.get("error", "")) == "settlement_generation_failed"
		and str(broken_start.get("generation_error", "")).begins_with(
			"terrain_profile_unknown:"
		),
		"14. 未定义地形会在聚落生成阶段明确拒绝，不产生半成品世界"
	)

	print("[V5 GENERATED SETTLEMENT SAMPLE] %s" % JSON.stringify({
		"name": report.get("settlement_name", ""),
		"capacity": report.get("resident_capacity", 0),
		"population": report.get("population_target", 0),
		"industries": industry_ids,
		"pressures": report.get("derived_pressures", {}),
	}))
	_finish()


func _all_locations_exist(session: Variant, location_ids: Array) -> bool:
	for location_value: Variant in location_ids:
		if session.context.get_location(str(location_value)).is_empty():
			return false
	return true


func _all_routes_reference_generated_locations(
		session: Variant, route_ids: Array, location_ids: Array
) -> bool:
	var found := {}
	for route: Dictionary in session.travel_routes:
		var route_id := str(route.get("route_id", ""))
		if route_id not in route_ids:
			continue
		if (
			str(route.get("from_location_id", "")) not in location_ids
			or str(route.get("to_location_id", "")) not in location_ids
		):
			return false
		found[route_id] = true
	return found.size() == route_ids.size()


func _all_generated_residents_use_bound_workplaces(
		session: Variant,
		resident_ids: Array,
		bindings: Dictionary,
		location_ids: Array
) -> bool:
	for resident_value: Variant in resident_ids:
		var resident_id := str(resident_value)
		var occupation_id := str(session.stores["state_store"].get_state(
			resident_id, "occupation_id", ""
		))
		var status := str(session.stores["state_store"].get_state(
			resident_id, "livelihood_status", ""
		))
		if status not in ["employed", "self_employed"]:
			continue
		if not bindings.has(occupation_id):
			return false
		var workplace_id := str(session.stores["state_store"].get_state(
			resident_id, "workplace_id", ""
		))
		if workplace_id != str(bindings[occupation_id]):
			return false
		if workplace_id not in location_ids:
			return false
	return true


func _all_generated_workplaces_staffed(
		session: Variant, resident_ids: Array, bindings: Dictionary
) -> bool:
	var staffed := {}
	for resident_value: Variant in resident_ids:
		var resident_id := str(resident_value)
		var status := str(session.stores["state_store"].get_state(
			resident_id, "livelihood_status", ""
		))
		if status not in ["employed", "self_employed"]:
			continue
		staffed[str(session.stores["state_store"].get_state(
			resident_id, "workplace_id", ""
		))] = true
	for workplace_value: Variant in bindings.values():
		if not staffed.has(str(workplace_value)):
			return false
	return true


func _has_fact_type(session: Variant, fact_type: String) -> bool:
	return _fact_count(session, fact_type) > 0


func _fact_count(session: Variant, fact_type: String) -> int:
	return session.stores["fact_store"].find_facts_by_type(fact_type).size()


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
		print("[V5 GENERATED SETTLEMENT CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 GENERATED SETTLEMENT CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GENERATED SETTLEMENT CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 GENERATED SETTLEMENT CONTRACT FAIL] %s" % label)
