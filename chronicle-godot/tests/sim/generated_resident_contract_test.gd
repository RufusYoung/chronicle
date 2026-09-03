extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_resident_hamlet_fixture.json"
)
const FIRST_SEED := 61001
const SECOND_SEED := 61002
const ATTRIBUTE_KEYS := [
	"strength",
	"dexterity",
	"wisdom",
	"charisma",
	"constitution",
	"perception",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw_fixture := _read_json(FIXTURE_PATH)
	_check(
		_count_people(raw_fixture.get("entities", [])) == 0
		and int((raw_fixture.get("resident_generation", {}) as Dictionary).get(
			"resident_count", 0
		)) == 12,
		"1. 原始夹具只提供聚落锚点，没有预写居民"
	)

	var first = SimSessionModel.new()
	var first_start: Dictionary = first.start_from_fixture_path(
		FIXTURE_PATH, [], {"challenge_seed_override": FIRST_SEED}
	)
	_check(
		bool(first_start.get("success", false))
		and int(first_start.get("definition_count", 0)) == 106,
		"2. G2 夹具通过正式 SimSession 启动并注册 106 个定义"
	)
	if not bool(first_start.get("success", false)):
		_finish()
		return

	var report: Dictionary = first_start.get("resident_generation", {})
	var resident_ids: Array = report.get("resident_ids", [])
	var household_ids: Array = report.get("household_ids", [])
	_check(
		int(report.get("generation_seed", 0)) == FIRST_SEED
		and int(report.get("resident_count", 0)) == 12
		and int(report.get("household_count", 0)) in [3, 4]
		and bool((report.get("integrity", {}) as Dictionary).get("ok", false)),
		"3. 固定种子生成 12 名居民、3 至 4 个家庭并通过生成期完整性校验"
	)

	var profile_report := _resident_profile_report(
		first, resident_ids, household_ids
	)
	_check(
		bool(profile_report.get("ok", false)),
		"4. 每名居民都有唯一姓名、年龄、六维属性、性情、生计、家庭、住址和工作地"
	)
	var occupation_counts: Dictionary = report.get("occupation_counts", {})
	_check(
		int(occupation_counts.get("net_fisher", 0)) >= 1
		and int(occupation_counts.get("terrace_farmer", 0)) >= 1
		and int(occupation_counts.get("reed_weaver", 0)) >= 1,
		"5. 聚落至少生成渔业、农业和手工业三个基础生计角色"
	)
	_check(
		_all_residents_socially_linked(first, resident_ids)
		and first.stores["relationship_store"].relations.size() >= 12,
		"6. 居民按家庭建立双向关系，家庭户主之间也形成聚落联系"
	)
	_check(
		_generated_worker_items_are_owned(first, resident_ids)
		and bool(first.validate_persistent_references().get("ok", false)),
		"7. 劳动者初始物品与全部跨 Store 引用都指向真实实体"
	)

	var repeated = SimSessionModel.new()
	var repeated_start: Dictionary = repeated.start_from_fixture_path(
		FIXTURE_PATH, [], {"challenge_seed_override": FIRST_SEED}
	)
	_check(
		bool(repeated_start.get("success", false))
		and _equivalent(
			first.get_save_store_data(), repeated.get_save_store_data()
		)
		and _equivalent(
			first.resident_generation_report,
			repeated.resident_generation_report
		),
		"8. 同一世界种子生成完全相同的实体、状态、关系、物品和生成摘要"
	)

	var varied = SimSessionModel.new()
	var varied_start: Dictionary = varied.start_from_fixture_path(
		FIXTURE_PATH, [], {"challenge_seed_override": SECOND_SEED}
	)
	var varied_report: Dictionary = varied_start.get("resident_generation", {})
	_check(
		bool(varied_start.get("success", false))
		and str(varied_report.get("structure_signature", "")) != str(
			report.get("structure_signature", "")
		),
		"9. 不同种子会改变家庭规模、年龄、生计或家庭关系结构"
	)

	var hunger_before := _state_values(first, resident_ids, "hunger")
	var tick_result: Dictionary = first.advance_time(
		18, "generated_resident_life_probe"
	)
	var livelihood_facts: Array = first.stores["fact_store"].find_facts_by_type(
		"npc_livelihood_produced"
	)
	var meal_facts := _meal_facts(first)
	_check(
		bool(tick_result.get("success", false))
		and livelihood_facts.size() >= _generated_worker_count(first, resident_ids)
		and not meal_facts.is_empty()
		and _state_values(first, resident_ids, "hunger") != hunger_before
		and not _all_state_values_equal(first, resident_ids, "hunger", "extreme"),
		"10. 推进十八小时后，居民持续生产真实物品，并通过进食避免全员极度饥饿"
	)

	var before_save := first.get_save_store_data()
	var envelope: Dictionary = first.build_save_envelope({
		"save_id": "save.test.generated_residents",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-13T08:00:00Z",
		"saved_at_utc": "2026-08-13T16:00:00Z",
	})
	var bootstrap: Dictionary = envelope.get("bootstrap", {})
	var restored = SimSessionModel.new()
	var restore_result: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(envelope))
	)
	_check(
		str(bootstrap.get("fixture_path", "")) == ""
		and not (bootstrap.get("fixture_data", {}) as Dictionary).is_empty()
		and bool(restore_result.get("success", false))
		and _equivalent(restored.get_save_store_data(), before_save)
		and int(restored.resident_generation_report.get(
			"generation_seed", 0
		)) == FIRST_SEED
		and str(restored.resident_generation_report.get(
			"signature", ""
		)) == str(report.get("signature", ""))
		and _all_resident_locations_exist(restored, resident_ids),
		"11. 存档内含生成 bootstrap，往返后保留居民真值、种子和全部地点"
	)

	var broken_fixture := raw_fixture.duplicate(true)
	(broken_fixture.get("resident_generation", {}) as Dictionary)[
		"settlement_id"
	] = "missing_settlement"
	var broken_start: Dictionary = SimSessionModel.new().start_from_fixture_data(
		broken_fixture, []
	)
	_check(
		not bool(broken_start.get("success", false))
		and str(broken_start.get("error", "")) == "resident_generation_failed"
		and str(broken_start.get("generation_error", "")) == (
			"settlement_entity_missing"
		),
		"12. 生成配置引用不存在的聚落时明确拒绝启动"
	)

	var dangling = SimSessionModel.new()
	dangling.start_from_fixture_path(
		FIXTURE_PATH, [], {"challenge_seed_override": FIRST_SEED}
	)
	dangling.stores["state_store"].set_state(
		str(resident_ids.front()), "household_id", "missing_household"
	)
	var dangling_report: Dictionary = dangling.validate_persistent_references()
	_check(
		not bool(dangling_report.get("ok", false))
		and str(dangling_report.get("phase", "")) == "references"
		and str(dangling_report.get("error", "")).begins_with(
			"save_state_entity_reference_unknown:"
		),
		"13. 运行时出现悬空家庭引用时，正式存档引用检查明确拒绝"
	)

	print("[V5 GENERATED RESIDENT SAMPLE] %s" % JSON.stringify(
		_sample_roster(first, resident_ids)
	))
	_finish()


func _resident_profile_report(
		session: Variant,
		resident_ids: Array,
		household_ids: Array
) -> Dictionary:
	var entities: Dictionary = session.stores["entity_store"].list_entities()
	var names: Dictionary = {}
	for household_id: String in household_ids:
		if (
			not entities.has(household_id)
			or str((entities[household_id] as Dictionary).get("type", ""))
				!= "household"
		):
			return {"ok": false, "error": "household_entity_missing"}
	for resident_id: String in resident_ids:
		var entity: Dictionary = entities.get(resident_id, {})
		var states: Dictionary = session.stores["state_store"].list_states(
			resident_id
		)
		var name := str(entity.get("display_name", ""))
		if name == "" or names.has(name):
			return {"ok": false, "error": "resident_name_invalid"}
		names[name] = true
		if int(states.get("age_years", -1)) < 0:
			return {"ok": false, "error": "resident_age_missing"}
		var age := int(states.get("age_years", -1))
		var birth_day := int(states.get("birth_day", 0))
		if (
			str(states.get("life_status", "")) != "alive"
			or not bool(states.get("alive", false))
			or int(states.get("life_expectancy_years", 0)) <= age
			or int(floor(float(1 - birth_day) / 365.0)) != age
			or str(states.get("life_stage", "")) == ""
		):
			return {"ok": false, "error": "resident_lifecycle_missing"}
		for key: String in ATTRIBUTE_KEYS:
			if int(states.get(key, 0)) < 2:
				return {"ok": false, "error": "resident_attribute_missing"}
		for key: String in [
			"temperament",
			"livelihood_status",
			"occupation_id",
			"household_id",
			"home_location_id",
			"workplace_id",
			"settlement_id",
		]:
			if str(states.get(key, "")) == "":
				return {"ok": false, "error": "resident_state_missing:%s" % key}
		if not household_ids.has(str(states.get("household_id", ""))):
			return {"ok": false, "error": "resident_household_unknown"}
		if session.context.get_location(str(states.get(
			"home_location_id", ""
		))).is_empty():
			return {"ok": false, "error": "resident_home_unknown"}
		if session.context.get_location(str(states.get(
			"workplace_id", ""
		))).is_empty():
			return {"ok": false, "error": "resident_workplace_unknown"}
	return {"ok": true}


func _all_residents_socially_linked(
		session: Variant,
		resident_ids: Array
) -> bool:
	var relations: Dictionary = session.stores["relationship_store"].relations
	for resident_id: String in resident_ids:
		var targets: Dictionary = relations.get(resident_id, {})
		if targets.is_empty():
			return false
		for target_id: String in targets.keys():
			if target_id not in resident_ids:
				return false
	return true


func _generated_worker_items_are_owned(
		session: Variant,
		resident_ids: Array
) -> bool:
	var item_owners: Dictionary = {}
	for item: Dictionary in session.stores["item_store"].list_items():
		var holder: Dictionary = item.get("holder", {})
		if str(holder.get("kind", "")) == "entity":
			item_owners[str(holder.get("id", ""))] = true
	for resident_id: String in resident_ids:
		var entity: Dictionary = session.stores["entity_store"].get_entity(
			resident_id
		)
		if "generated_worker" in (entity.get("tags", []) as Array):
			if not item_owners.has(resident_id):
				return false
	return not item_owners.is_empty()


func _generated_worker_count(session: Variant, resident_ids: Array) -> int:
	var count := 0
	for resident_id: String in resident_ids:
		var entity: Dictionary = session.stores["entity_store"].get_entity(
			resident_id
		)
		if "generated_worker" in (entity.get("tags", []) as Array):
			count += 1
	return count


func _meal_facts(session: Variant) -> Array:
	var rows: Array = session.stores["fact_store"].find_facts_by_type(
		"npc_self_meal"
	)
	rows.append_array(session.stores["fact_store"].find_facts_by_type(
		"npc_household_shared_food"
	))
	return rows


func _state_values(
		session: Variant,
		resident_ids: Array,
		state_key: String
) -> Array:
	var rows: Array = []
	for resident_id: String in resident_ids:
		rows.append(session.stores["state_store"].get_state(
			resident_id, state_key
		))
	return rows


func _all_state_values_equal(
		session: Variant,
		resident_ids: Array,
		state_key: String,
		expected: Variant
) -> bool:
	for resident_id: String in resident_ids:
		if session.stores["state_store"].get_state(
			resident_id, state_key
		) != expected:
			return false
	return true


func _all_resident_locations_exist(
		session: Variant,
		resident_ids: Array
) -> bool:
	for resident_id: String in resident_ids:
		var states: Dictionary = session.stores["state_store"].list_states(
			resident_id
		)
		for key: String in ["home_location_id", "workplace_id"]:
			if session.context.get_location(str(states.get(key, ""))).is_empty():
				return false
	return true


func _sample_roster(session: Variant, resident_ids: Array) -> Array:
	var rows: Array = []
	for resident_id: String in resident_ids.slice(0, 5):
		var entity: Dictionary = session.stores["entity_store"].get_entity(
			resident_id
		)
		var states: Dictionary = session.stores["state_store"].list_states(
			resident_id
		)
		rows.append({
			"name": entity.get("display_name", ""),
			"age": states.get("age_years", 0),
			"occupation": states.get("occupation_id", ""),
			"temperament": states.get("temperament", ""),
			"household": states.get("household_id", ""),
		})
	return rows


func _count_people(rows: Array) -> int:
	var count := 0
	for row: Dictionary in rows:
		if str(row.get("type", "")) == "person":
			count += 1
	return count


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value if value is Dictionary else {}


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
		print("[V5 GENERATED RESIDENT CONTRACT RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 GENERATED RESIDENT CONTRACT FAIL] " + failure)
		print(
			"[V5 GENERATED RESIDENT CONTRACT RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GENERATED RESIDENT CONTRACT PASS] " + label)
	else:
		failures.append(label)
