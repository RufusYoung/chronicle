extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const PopulationLifecycleSystemModel = preload(
	"res://scripts/sim/population/population_lifecycle_system.gd"
)
const TransactionWorldWriterModel = preload(
	"res://scripts/sim/transaction/transaction_world_writer.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_population_lifecycle.save.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = _start_isolated(81001)
	_check(
		session != null and session.is_ready()
		and _all_residents_have_lifecycle_metadata(session),
		"1. 生成居民具备可复现的出生日、生命阶段、存活状态和寿命"
	)
	if session == null or not session.is_ready():
		_finish()
		return

	var minor_id := _minor_id(session)
	var dead_holder_id := _organization_holder_id(session)
	var dead_role := str(session.stores["state_store"].get_state(
		dead_holder_id, "institution_role", ""
	))
	var population_before := _active_population(session)
	_inject_lifecycle_probe(session, minor_id, dead_holder_id)
	var first_tick: Dictionary = session.advance_time(
		1, "population_lifecycle_test_injection"
	)
	_check(
		bool(first_tick.get("success", false))
		and not _facts_for_target(
			session, "resident_reached_adulthood", minor_id
		).is_empty()
		and int(session.stores["state_store"].get_state(
			minor_id, "age_years", 0
		)) == 18
		and str(session.stores["state_store"].get_state(
			minor_id, "livelihood_status", ""
		)) == "unemployed",
		"2. 测试注入的生日在每日结算中让未成年人真实成年并退出受抚养状态"
	)
	_check(
		not _facts_for_target(
			session, "resident_died", dead_holder_id
		).is_empty()
		and not session.stores["entity_store"].is_entity_active(dead_holder_id)
		and not _full_snapshot(session).is_entity_active(dead_holder_id)
		and not _full_snapshot(session).get_entity(dead_holder_id).is_empty()
		and str(session.stores["state_store"].get_state(
			dead_holder_id, "life_status", ""
		)) == "dead"
		and _active_population(session) == population_before - 1,
		"3. 健康归零会留下可追溯历史实体，但当前人口立即减少且死者退出活动快照"
	)
	var vacancy := _vacancy_for_holder(session, dead_holder_id)
	_check(
		not vacancy.is_empty()
		and str(vacancy.get("vacancy_reason", "")) == "holder_died"
		and str(session.stores["state_store"].get_state(
			dead_holder_id, "institution_role", "missing"
		)) == ""
		and str(vacancy.get("source_fact_ids", [""])[0]).begins_with(
			"fact.resident_died."
		),
		"4. 任职者死亡会清除当前职责，并用死亡事实形成真实组织空缺"
	)

	var production_after_death := _production_count(session, dead_holder_id)
	_advance(session, 24, "population_lifecycle_followup")
	var successor_id := _holder_for_role(session, dead_role)
	_check(
		_production_count(session, dead_holder_id) == production_after_death
		and successor_id != ""
		and successor_id != dead_holder_id
		and session.stores["entity_store"].is_entity_active(successor_id),
		"5. 死者后续不再生产，次日由存活成年居民接替空缺职位"
	)
	_check(
		_has_sourceful_family_chronicle(session, dead_holder_id)
		and bool(session.validate_persistent_references().get("ok", false)),
		"6. 死亡进入家庭 Chronicle，历史关系和持久引用保持完整"
	)

	var before_save: Dictionary = session.get_save_store_data()
	var save_report: Dictionary = session.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_population_lifecycle",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-21T08:00:00Z",
		"saved_at_utc": "2026-08-21T09:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and _equivalent(before_save, restored.get_save_store_data())
		and not restored.stores["entity_store"].is_entity_active(dead_holder_id)
		and _holder_for_role(restored, dead_role) == successor_id,
		"7. 存档往返精确保留死亡、历史实体、人口减少和组织继任"
	)

	var autonomous_first := _autonomous_lifespan_signature(81001)
	var autonomous_repeat := _autonomous_lifespan_signature(81001)
	_check(
		bool(autonomous_first.get("ok", false))
		and int(autonomous_first.get("aged_count", 0)) > 0
		and int(autonomous_first.get("death_count", 0)) > 0
		and str(autonomous_first.get("signature", "")) == str(
			autonomous_repeat.get("signature", "")
		),
		"8. 无测试注入推进到群体首个自然死亡日，年龄变化与死亡按同一种子完全复现"
	)

	print("[V5 POPULATION LIFECYCLE SAMPLE] %s" % JSON.stringify({
		"dead_holder_id": dead_holder_id,
		"successor_id": successor_id,
		"autonomous_lifespan": {
			"aged_count": int(autonomous_first.get("aged_count", 0)),
			"adult_count": int(autonomous_first.get("adult_count", 0)),
			"death_count": int(autonomous_first.get("death_count", 0)),
			"first_death_day": int(autonomous_first.get(
				"first_death_day", 0
			)),
			"event_day_count": int(autonomous_first.get(
				"event_day_count", 0
			)),
		},
	}))
	_finish()


func _start_isolated(seed: int) -> Variant:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		print("[V5 POPULATION LIFECYCLE START FAILURE] %s" % JSON.stringify(start))
		return null
	var runtime: Dictionary = session.get_settlement_network_summary()
	for link: Dictionary in runtime.get("links", []):
		link["capacity_per_day"] = 0.0
	runtime["migration_delay_days"] = 99
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)
	return session


func _inject_lifecycle_probe(
		session: Variant, minor_id: String, dead_holder_id: String
) -> void:
	var state_store: Variant = session.stores["state_store"]
	for change: Dictionary in [
		{"entity_id": minor_id, "key": "age_years", "to": 17},
		{"entity_id": minor_id, "key": "birth_day", "to": 1 - 18 * 365},
		{"entity_id": minor_id, "key": "life_expectancy_years", "to": 90},
		{"entity_id": minor_id, "key": "livelihood_status", "to": "dependent"},
		{"entity_id": minor_id, "key": "occupation_id", "to": "dependent"},
		{"entity_id": dead_holder_id, "key": "health", "to": 0},
	]:
		state_store.apply_state_change(change)


func _autonomous_lifespan_signature(seed: int) -> Dictionary:
	var session = _start_isolated(seed)
	if session == null:
		return {"ok": false}
	var system = PopulationLifecycleSystemModel.new()
	var writer = TransactionWorldWriterModel.new()
	var config: Dictionary = session.get_settlement_network_summary().get(
		"population_lifecycle", {}
	)
	var first_death_day := _first_natural_death_day(session)
	var event_days := _lifecycle_event_days(session, first_death_day)
	for day: int in event_days:
		var data: Dictionary = system.resolve_daily_tick(
			_full_snapshot(session), {"day": day}, config
		)
		if not writer.apply_results(data.get("results", []), session.stores):
			return {"ok": false, "error": writer.last_report}
	var rows: Array[String] = []
	for fact_type: String in [
		"resident_aged", "resident_reached_adulthood", "resident_died"
	]:
		for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
			fact_type
		):
			rows.append("%s|%s|%d" % [
				fact_type,
				str(fact.get("target_id", "")),
				int(fact.get("day", 0)),
			])
	rows.sort()
	return {
		"ok": bool(session.validate_persistent_references().get("ok", false)),
		"aged_count": session.stores["fact_store"].find_facts_by_type(
			"resident_aged"
		).size(),
		"adult_count": session.stores["fact_store"].find_facts_by_type(
			"resident_reached_adulthood"
		).size(),
		"death_count": session.stores["fact_store"].find_facts_by_type(
			"resident_died"
		).size(),
		"first_death_day": first_death_day,
		"event_day_count": event_days.size(),
		"signature": ";".join(rows),
	}


func _first_natural_death_day(session: Variant) -> int:
	var first_day := 0
	for person: Dictionary in _full_snapshot(session).get_entities_by_type(
		"person"
	):
		if "generated_resident" not in (person.get("tags", []) as Array):
			continue
		var person_id := str(person.get("id", ""))
		var birth_day := int(session.stores["state_store"].get_state(
			person_id, "birth_day", 0
		))
		var life_expectancy := int(session.stores["state_store"].get_state(
			person_id, "life_expectancy_years", 80
		))
		var death_day := birth_day + life_expectancy * 365
		if death_day > 1 and (first_day == 0 or death_day < first_day):
			first_day = death_day
	return first_day


func _lifecycle_event_days(session: Variant, last_day: int) -> Array[int]:
	var unique_days: Dictionary = {}
	for person: Dictionary in _full_snapshot(session).get_entities_by_type(
		"person"
	):
		if "generated_resident" not in (person.get("tags", []) as Array):
			continue
		var person_id := str(person.get("id", ""))
		var current_age := int(session.stores["state_store"].get_state(
			person_id, "age_years", 0
		))
		var birth_day := int(session.stores["state_store"].get_state(
			person_id, "birth_day", 0
		))
		var life_expectancy := int(session.stores["state_store"].get_state(
			person_id, "life_expectancy_years", 80
		))
		for age: int in range(current_age + 1, life_expectancy + 1):
			var birthday := birth_day + age * 365
			if birthday > last_day:
				break
			if birthday > 0:
				unique_days[birthday] = true
	var days: Array[int] = []
	for day_value: Variant in unique_days.keys():
		days.append(int(day_value))
	days.sort()
	return days


func _all_residents_have_lifecycle_metadata(session: Variant) -> bool:
	var residents: Array = _full_snapshot(session).get_entities_by_type("person")
	if residents.is_empty():
		return false
	for person: Dictionary in residents:
		if "generated_resident" not in (person.get("tags", []) as Array):
			continue
		var person_id := str(person.get("id", ""))
		var age := int(session.stores["state_store"].get_state(
			person_id, "age_years", -1
		))
		var birth_day := int(session.stores["state_store"].get_state(
			person_id, "birth_day", 0
		))
		if (
			int(floor(float(1 - birth_day) / 365.0)) != age
			or int(session.stores["state_store"].get_state(
				person_id, "life_expectancy_years", 0
			)) <= age
			or str(session.stores["state_store"].get_state(
				person_id, "life_status", ""
			)) != "alive"
		):
			return false
	return true


func _minor_id(session: Variant) -> String:
	for person: Dictionary in _full_snapshot(session).get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if int(session.stores["state_store"].get_state(
			person_id, "age_years", 0
		)) < 18:
			return person_id
	return ""


func _organization_holder_id(session: Variant) -> String:
	for person: Dictionary in _full_snapshot(session).get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if "::" in str(session.stores["state_store"].get_state(
			person_id, "institution_role", ""
		)):
			return person_id
	return ""


func _active_population(session: Variant) -> int:
	return _full_snapshot(session).get_entities_by_type("person").size()


func _facts_for_target(
		session: Variant, fact_type: String, target_id: String
) -> Array:
	var rows: Array = []
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		fact_type
	):
		if str(fact.get("target_id", "")) == target_id:
			rows.append(fact)
	return rows


func _vacancy_for_holder(session: Variant, holder_id: String) -> Dictionary:
	var rows := _facts_for_target(
		session, "organization_position_vacated", holder_id
	)
	return {} if rows.is_empty() else rows.back()


func _holder_for_role(session: Variant, role: String) -> String:
	for person: Dictionary in _full_snapshot(session).get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if str(session.stores["state_store"].get_state(
			person_id, "institution_role", ""
		)) == role:
			return person_id
	return ""


func _production_count(session: Variant, actor_id: String) -> int:
	var count := 0
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"npc_livelihood_produced"
	):
		if str(fact.get("actor_id", "")) == actor_id:
			count += 1
	return count


func _has_sourceful_family_chronicle(
		session: Variant, dead_id: String
) -> bool:
	for entry: Dictionary in session.stores["chronicle_store"].list_entries():
		if (
			str(entry.get("entry_id", "")).begins_with(
				"chronicle.resident_death.%s" % _safe_id(dead_id)
			)
			and not (entry.get("source_fact_ids", []) as Array).is_empty()
		):
			return true
	return false


func _advance(session: Variant, hours: int, source: String) -> void:
	for _hour: int in range(hours):
		session.advance_time(1, source)


func _full_snapshot(session: Variant) -> Variant:
	return session.snapshot_builder.build_snapshot(
		session.context, session.stores, true, session.get_time_summary()
	)


func _safe_id(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace(":", "_")


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
		print("[V5 POPULATION LIFECYCLE CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 POPULATION LIFECYCLE CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 POPULATION LIFECYCLE CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 POPULATION LIFECYCLE CONTRACT FAIL] %s" % label)
