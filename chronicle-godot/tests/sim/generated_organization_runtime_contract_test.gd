extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_organization_runtime.save.json"
const ORGANIZATION_ID := "generated_organization.wind_pass.pass_watch"
const SETTLEMENT_ID := "generated_settlement.wind_pass"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var partial = _start_isolated(81001)
	_check(
		partial != null and partial.is_ready(),
		"1. G4-B 组织运行期合同通过正式 SimSession 启动"
	)
	if partial == null or not partial.is_ready():
		_finish()
		return
	_advance(partial, 36, "organization_runtime_vacancy")
	_check(
		_facts(partial, "organization_position_vacated").size() == 2
		and _facts(partial, "organization_position_filled").is_empty()
		and _position_holders(partial).is_empty(),
		"2. 第 2 天迁出先形成两个真实空缺，不在同日瞬间换人"
	)

	_advance(partial, 24, "organization_runtime_partial")
	var partial_filled := _facts(partial, "organization_position_filled")
	_check(
		partial_filled.size() == 1
		and _filled_facts_are_true(partial, partial_filled),
		"3. 持续迁出只剩一名成年候选时，组织只补入这一名真实居民"
	)
	_check(
		_staffing_pressure_value(partial) == 1
		and _has_sourceful_restaff_chronicle(partial),
		"4. 部分补位留下一个人员短缺压力，任职事实与 Chronicle 可追溯"
	)

	var full = _start_isolated(81001)
	_advance(full, 36, "organization_runtime_full_vacancy")
	_stop_further_migration(full)
	_advance(full, 24, "organization_runtime_full")
	var full_filled := _facts(full, "organization_position_filled")
	_check(
		full_filled.size() == 2
		and _position_holders(full).size() == 2
		and _filled_facts_are_true(full, full_filled)
		and _staffing_pressure_value(full) == 0,
		"5. 保留足够本地成年人时，两个职位由不同居民补满且不制造压力"
	)
	var fact_count_before := full_filled.size()
	_advance(full, 12, "organization_runtime_idempotency")
	_check(
		_facts(full, "organization_position_filled").size()
		== fact_count_before
		and _position_holders(full).size() == 2,
		"6. 已补职位不会在同日刷新或后续 Tick 重复任命"
	)

	var repeated = _start_isolated(81001)
	_advance(repeated, 36, "organization_runtime_repeat_vacancy")
	_stop_further_migration(repeated)
	_advance(repeated, 24, "organization_runtime_repeat")
	_check(
		_runtime_signature(repeated) == _runtime_signature(full),
		"7. 同一种子与同一压力路径完全复现补位成员和职位"
	)

	var save_before: Dictionary = full.get_save_store_data()
	var save_report: Dictionary = full.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_organization_runtime",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-18T14:00:00Z",
		"saved_at_utc": "2026-08-21T08:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and _equivalent(save_before, restored.get_save_store_data())
		and _runtime_signature(restored) == _runtime_signature(full)
		and bool(restored.validate_persistent_references().get("ok", false)),
		"8. 磁盘存档往返精确保留补位成员、关系、压力和来源历史"
	)

	var unavailable = _start_isolated(81001)
	_advance(unavailable, 36, "organization_runtime_unavailable_vacancy")
	_stop_further_migration(unavailable)
	_inject_candidate_unavailability(unavailable)
	_advance(unavailable, 24, "organization_runtime_unavailable")
	_check(
		_facts(unavailable, "organization_position_filled").is_empty()
		and _position_holders(unavailable).is_empty()
		and _staffing_pressure_value(unavailable) == 2
		and _facts(
			unavailable, "organization_recruitment_evaluated"
		).size() == 1,
		"9. 测试注入占用全部成年候选时保留两处空缺，不伪造补位成功"
	)

	print("[V5 ORGANIZATION RUNTIME SAMPLE] %s" % JSON.stringify({
		"partial": partial_filled,
		"full": full_filled,
		"full_holders": _position_holders(full),
		"unavailable_pressure": _staffing_pressure_value(unavailable),
	}))
	_finish()


func _start_isolated(seed: int) -> Variant:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		print("[V5 ORGANIZATION RUNTIME START FAILURE] %s" % JSON.stringify(start))
		return null
	var runtime: Dictionary = session.get_settlement_network_summary()
	for link: Dictionary in runtime.get("links", []):
		link["capacity_per_day"] = 0.0
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)
	return session


func _stop_further_migration(session: Variant) -> void:
	var runtime: Dictionary = session.get_settlement_network_summary()
	runtime["migration_delay_days"] = 99
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)


func _inject_candidate_unavailability(session: Variant) -> void:
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		var entity_id := str(entity.get("id", ""))
		if (
			str(entity.get("type", "")) == "person"
			and str(session.stores["state_store"].get_state(
				entity_id, "settlement_id", ""
			)) == SETTLEMENT_ID
			and int(session.stores["state_store"].get_state(
				entity_id, "age_years", 0
			)) >= 18
		):
			session.stores["state_store"].apply_state_change({
				"entity_id": entity_id,
				"key": "institution_role",
				"to": "test_injection::unavailable",
			})


func _advance(session: Variant, hours: int, source: String) -> void:
	for _hour: int in range(hours):
		session.advance_time(1, source)


func _facts(session: Variant, fact_type: String) -> Array:
	return session.stores["fact_store"].find_facts_by_type(fact_type)


func _position_holders(session: Variant) -> Dictionary:
	var holders: Dictionary = {}
	var organization: Dictionary = session.stores[
		"entity_store"
	].get_entity(ORGANIZATION_ID)
	for position: Dictionary in organization.get("positions", []):
		var position_id := str(position.get("position_id", ""))
		var expected_role := "%s::%s" % [ORGANIZATION_ID, position_id]
		for entity: Dictionary in session.stores[
			"entity_store"
		].list_entity_rows():
			var entity_id := str(entity.get("id", ""))
			if (
				str(entity.get("type", "")) == "person"
				and str(session.stores["state_store"].get_state(
					entity_id, "institution_role", ""
				)) == expected_role
			):
				holders[position_id] = entity_id
	return holders


func _filled_facts_are_true(session: Variant, facts: Array) -> bool:
	var seen_members: Dictionary = {}
	for fact: Dictionary in facts:
		var member_id := str(fact.get("target_id", ""))
		var position_id := str(fact.get("position_id", ""))
		var source_fact_ids: Array = fact.get("source_fact_ids", [])
		if (
			seen_members.has(member_id)
			or source_fact_ids.is_empty()
			or str(session.stores["fact_store"].get_fact(
				str(source_fact_ids[0])
			).get("fact_type", "")) != "organization_position_vacated"
			or str(session.stores["state_store"].get_state(
				member_id, "settlement_id", ""
			)) != SETTLEMENT_ID
			or int(session.stores["state_store"].get_state(
				member_id, "age_years", 0
			)) < 18
			or str(session.stores["state_store"].get_state(
				member_id, "institution_role", ""
			)) != "%s::%s" % [ORGANIZATION_ID, position_id]
			or int(session.stores["relationship_store"].get_relation(
				ORGANIZATION_ID, member_id, "familiarity", 0
			)) <= 0
		):
			return false
		seen_members[member_id] = true
	return not facts.is_empty()


func _staffing_pressure_value(session: Variant) -> int:
	var total := 0
	for pressure: Dictionary in session.stores[
		"pressure_store"
	].list_pressures():
		if (
			str(pressure.get("scope_id", "")) == ORGANIZATION_ID
			and str(pressure.get("pressure_type", ""))
			== "organization_staffing_need"
		):
			total += int(pressure.get("value", 0))
	return total


func _has_sourceful_restaff_chronicle(session: Variant) -> bool:
	for entry: Dictionary in session.stores["chronicle_store"].list_entries():
		if (
			str(entry.get("subject_id", "")) == ORGANIZATION_ID
			and "chronicle.organization_restaffed" in str(entry.get(
				"entry_id", ""
			))
			and not (entry.get("source_fact_ids", []) as Array).is_empty()
		):
			return true
	return false


func _runtime_signature(session: Variant) -> String:
	var rows: Array[Dictionary] = []
	for fact: Dictionary in _facts(session, "organization_position_filled"):
		rows.append({
			"position_id": str(fact.get("position_id", "")),
			"member_id": str(fact.get("target_id", "")),
			"day": int(fact.get("day", 0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("position_id", "")) < str(b.get("position_id", ""))
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
		print("[V5 ORGANIZATION RUNTIME CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 ORGANIZATION RUNTIME CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 ORGANIZATION RUNTIME CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 ORGANIZATION RUNTIME CONTRACT FAIL] %s" % label)
