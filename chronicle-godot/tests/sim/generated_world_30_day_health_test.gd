extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const TEST_SEEDS := [81001, 82002, 83003]
const SIMULATION_DAYS := 30
const CHECKPOINT_DAYS := [1, 7, 14, 21, 30]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reports: Array[Dictionary] = []
	var history_signatures: Dictionary = {}
	var pressure_signatures: Dictionary = {}
	for seed: int in TEST_SEEDS:
		var report := _simulate_seed(seed)
		reports.append(report)
		_check(
			bool(report.get("start_ok", false)),
			"seed %d 可以启动 30 日无人干预世界" % seed
		)
		_check(
			(report.get("tick_errors", []) as Array).is_empty(),
			"seed %d 的 720 个小时轮次全部完成" % seed
		)
		_check(
			(report.get("transaction_errors", []) as Array).is_empty(),
			"seed %d 的长期推进没有失败事务" % seed
		)
		_check(
			(report.get("integrity_errors", []) as Array).is_empty(),
			"seed %d 每日引用、库存、人口、任职与来源完整" % seed
		)
		var activity: Dictionary = report.get("autonomous_activity", {})
		var organization: Dictionary = report.get("organization", {})
		_check(
			int(activity.get("route_pressure_count", 0)) > 0
			and int(activity.get("organization_response_count", 0)) > 0,
			"seed %d 无需测试注入即可产生区域压力与组织回应" % seed
		)
		_check(
			int(organization.get("formed_count", 0)) > 0
			and int(organization.get("retired_count", 0)) > 0
			and (organization.get("cooldown_errors", []) as Array).is_empty(),
			"seed %d 的动态组织完成成立、应对与退场且未越过冷却期" % seed
		)
		_check(
			(report.get("migration", {}).get(
				"stale_unabsorbed", []
			) as Array).is_empty(),
			"seed %d 不存在超过三天仍无结果的迁入家庭" % seed
		)
		_check(
			bool(report.get("save_roundtrip_ok", false))
			and bool(report.get("save_continuation_ok", false)),
			"seed %d 的第 30 日存档可精确恢复并确定性续跑" % seed
		)
		history_signatures[str(report.get("history_signature", ""))] = true
		pressure_signatures[str(report.get("route_pressure_signature", ""))] = true
	history_signatures.erase("")
	pressure_signatures.erase("")
	_check(
		history_signatures.size() == TEST_SEEDS.size(),
		"三组种子产生互不相同的贸易、组织与迁移历史"
	)
	_check(
		pressure_signatures.size() >= 2,
		"三组种子的道路压力日期、成因或强度存在程序化差异"
	)

	print("[V5 GENERATED WORLD 30 DAY HEALTH SAMPLE] %s" % JSON.stringify({
		"simulation_days": SIMULATION_DAYS,
		"injected_behavior_count": 0,
		"seeds": reports,
	}))
	_finish()


func _simulate_seed(seed: int) -> Dictionary:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH,
		RULE_PATHS,
		{"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		return {
			"seed": seed,
			"start_ok": false,
			"start_error": start,
			"tick_errors": [],
			"transaction_errors": [],
			"integrity_errors": [],
		}

	var tick_errors: Array[String] = []
	var transaction_errors: Array[String] = []
	var integrity_errors: Array[String] = []
	var checkpoints: Array[Dictionary] = []
	for day_index: int in range(1, SIMULATION_DAYS + 1):
		var tick_result: Dictionary = session.advance_time(
			24,
			"generated_world_30_day_health",
			{
				"scope_type": "global",
				"scope_id": "",
				"source": "generated_world_30_day_health_test",
				"label": "30 day autonomous world health soak",
			}
		)
		if not bool(tick_result.get("success", false)):
			tick_errors.append("day%d:%s" % [
				day_index, str(tick_result.get("error_reason", "unknown_error"))
			])
		transaction_errors.append_array(
			_tick_transaction_errors(tick_result, day_index)
		)
		var audit := _audit_world(session, day_index)
		integrity_errors.append_array(audit.get("errors", []))
		if day_index in CHECKPOINT_DAYS:
			checkpoints.append(audit.get("metrics", {}))

	var organization_report := _organization_report(session)
	var final_world_day := int(session.get_time_summary().get("day", 0))
	var migration_report := _migration_report(session, final_world_day)
	var history_signature := _history_signature(session)
	var pressure_signature := _route_pressure_signature(session)
	var save_report := _save_roundtrip_report(session, seed)
	return {
		"seed": seed,
		"start_ok": true,
		"final_day": int(session.get_time_summary().get("day", 0)),
		"final_hour": int(session.get_time_summary().get("hour", 0)),
		"world_tick_count": int(session.get_time_summary().get(
			"world_tick_count", 0
		)),
		"tick_errors": tick_errors,
		"transaction_errors": transaction_errors,
		"integrity_errors": integrity_errors,
		"checkpoints": checkpoints,
		"organization": organization_report,
		"migration": migration_report,
		"autonomous_activity": _autonomous_activity_report(session),
		"history_signature": history_signature,
		"route_pressure_signature": pressure_signature,
		"save_roundtrip_ok": bool(save_report.get("roundtrip_ok", false)),
		"save_continuation_ok": bool(save_report.get(
			"continuation_ok", false
		)),
	}


func _audit_world(session: Variant, day_index: int) -> Dictionary:
	var errors: Array[String] = []
	var reference_report: Dictionary = session.validate_persistent_references()
	if not bool(reference_report.get("ok", false)):
		errors.append("day%d:persistent:%s" % [
			day_index, str(reference_report.get("error", "unknown_error"))
		])
	var resource_report: Dictionary = session.stores[
		"resource_stock_store"
	].validate_integrity()
	for error_value: Variant in resource_report.get("errors", []):
		errors.append("day%d:resource:%s" % [day_index, str(error_value)])
	for error: String in _fact_source_errors(session):
		errors.append("day%d:fact_source:%s" % [day_index, error])
	for error: String in _organization_source_errors(session):
		errors.append("day%d:organization_source:%s" % [day_index, error])
	for error: String in _role_integrity_errors(session):
		errors.append("day%d:role:%s" % [day_index, error])
	for error: String in _population_capacity_errors(session):
		errors.append("day%d:population:%s" % [day_index, error])
	for error: String in _active_organization_errors(session):
		errors.append("day%d:organization:%s" % [day_index, error])
	return {
		"errors": errors,
		"metrics": {
			"day": day_index,
			"fact_count": session.stores["fact_store"].list_facts().size(),
			"chronicle_count": session.stores[
				"chronicle_store"
			].to_save_data().size(),
			"item_count": session.stores["item_store"].to_save_data().size(),
			"population_by_settlement": _population_counts(session),
			"active_runtime_organization_count": _active_runtime_organizations(
				session
			).size(),
			"migration_count": _facts(session, "household_migrated").size(),
			"route_pressure_count": _facts(
				session, "regional_route_pressure_started"
			).size(),
			"organization_response_count": _organization_response_count(
				session
			),
			"absorbed_household_count": _facts(
				session, "migrant_household_absorbed"
			).size(),
		}
	}


func _tick_transaction_errors(
		tick_result: Dictionary, day_index: int
) -> Array[String]:
	var errors: Array[String] = []
	for result_key: String in [
		"results",
		"due_results",
		"need_results",
		"livelihood_results",
		"resource_results",
		"network_results",
		"social_followup_results",
		"autonomous_results",
	]:
		for value: Variant in tick_result.get(result_key, []):
			if not value is Dictionary:
				errors.append("day%d:%s:not_dictionary" % [
					day_index, result_key
				])
				continue
			var row: Dictionary = value
			if str(row.get("contract_status", "")) != "resolved":
				errors.append("day%d:%s:%s" % [
					day_index,
					result_key,
					str(row.get("error_reason", "unresolved_transaction")),
				])
	return errors


func _fact_source_errors(session: Variant) -> Array[String]:
	var errors: Array[String] = []
	var fact_store: Variant = session.stores["fact_store"]
	for fact: Dictionary in fact_store.list_facts():
		var fact_id := str(fact.get("fact_id", ""))
		for source_value: Variant in fact.get("source_fact_ids", []):
			var source_id := str(source_value)
			if source_id == "" or fact_store.get_fact(source_id).is_empty():
				errors.append("%s->%s" % [fact_id, source_id])
	return errors


func _organization_source_errors(session: Variant) -> Array[String]:
	var errors: Array[String] = []
	var fact_store: Variant = session.stores["fact_store"]
	for organization: Dictionary in session.stores[
		"entity_store"
	].list_entity_rows():
		if "runtime_organization" not in (organization.get("tags", []) as Array):
			continue
		for source_value: Variant in organization.get("source_fact_ids", []):
			var source_id := str(source_value)
			if source_id == "" or fact_store.get_fact(source_id).is_empty():
				errors.append("%s->%s" % [
				str(organization.get("id", "")), source_id
			])
	return errors


func _role_integrity_errors(session: Variant) -> Array[String]:
	var errors: Array[String] = []
	var occupied_roles: Dictionary = {}
	var entity_store: Variant = session.stores["entity_store"]
	var state_store: Variant = session.stores["state_store"]
	for person: Dictionary in entity_store.list_entity_rows():
		if str(person.get("type", "")) != "person":
			continue
		var person_id := str(person.get("id", ""))
		var role := str(state_store.get_state(
			person_id, "institution_role", ""
		))
		if role == "":
			continue
		var parts := role.split("::")
		if parts.size() != 2:
			errors.append("%s:malformed:%s" % [person_id, role])
			continue
		var organization_id := str(parts[0])
		var position_id := str(parts[1])
		var organization: Dictionary = entity_store.get_entity(organization_id)
		if organization.is_empty():
			errors.append("%s:unknown:%s" % [person_id, organization_id])
			continue
		if str(organization.get("lifecycle_status", "active")) == "retired":
			errors.append("%s:retired:%s" % [person_id, organization_id])
		if not _organization_has_position(organization, position_id):
			errors.append("%s:unknown_position:%s" % [person_id, role])
		if occupied_roles.has(role):
			errors.append("%s:duplicate_holder:%s" % [person_id, role])
		occupied_roles[role] = person_id
	return errors


func _organization_has_position(
		organization: Dictionary, position_id: String
) -> bool:
	for value: Variant in organization.get("positions", []):
		if value is Dictionary and str((value as Dictionary).get(
			"position_id", ""
		)) == position_id:
			return true
	return false


func _population_capacity_errors(session: Variant) -> Array[String]:
	var errors: Array[String] = []
	var counts := _population_counts(session)
	for site: Dictionary in session.get_settlement_network_summary().get(
		"sites", []
	):
		var settlement_id := str(site.get("settlement_id", ""))
		var population := int(counts.get(settlement_id, 0))
		var capacity := int(site.get("resident_capacity", 0))
		if population > capacity:
			errors.append("%s:%d>%d" % [
				settlement_id, population, capacity
			])
	return errors


func _population_counts(session: Variant) -> Dictionary:
	var counts: Dictionary = {}
	var state_store: Variant = session.stores["state_store"]
	for person: Dictionary in session.stores[
		"entity_store"
	].list_entity_rows():
		if str(person.get("type", "")) != "person":
			continue
		var settlement_id := str(state_store.get_state(
			str(person.get("id", "")), "settlement_id", ""
		))
		if settlement_id != "":
			counts[settlement_id] = int(counts.get(settlement_id, 0)) + 1
	return counts


func _active_organization_errors(session: Variant) -> Array[String]:
	var errors: Array[String] = []
	var active_pairs: Dictionary = {}
	for organization: Dictionary in _active_runtime_organizations(session):
		var key := "%s::%s" % [
			str(organization.get("settlement_id", "")),
			str(organization.get("prototype_id", "")),
		]
		active_pairs[key] = int(active_pairs.get(key, 0)) + 1
	for key: String in active_pairs.keys():
		if int(active_pairs[key]) > 1:
			errors.append("duplicate_active_pair:%s" % key)
	return errors


func _active_runtime_organizations(session: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entity: Dictionary in session.stores[
		"entity_store"
	].list_entity_rows():
		if (
			"runtime_organization" in (entity.get("tags", []) as Array)
			and str(entity.get("lifecycle_status", "active")) != "retired"
		):
			rows.append(entity)
	return rows


func _organization_report(session: Variant) -> Dictionary:
	var formed := _facts(session, "organization_runtime_formed")
	var retired := _facts(session, "organization_runtime_retired")
	var cycles_by_pair: Dictionary = {}
	for fact: Dictionary in formed:
		var key := "%s::%s" % [
			str(fact.get("settlement_id", "")),
			str(fact.get("prototype_id", "")),
		]
		cycles_by_pair[key] = int(cycles_by_pair.get(key, 0)) + 1
	return {
		"formed_count": formed.size(),
		"goal_changed_count": _facts(
			session, "organization_goal_changed"
		).size(),
		"goal_reactivated_count": _facts(
			session, "organization_goal_reactivated"
		).size(),
		"effectiveness_review_count": _facts(
			session, "organization_effectiveness_evaluated"
		).size(),
		"retired_count": retired.size(),
		"active_count": _active_runtime_organizations(session).size(),
		"cycles_by_pair": cycles_by_pair,
		"cooldown_errors": _organization_cooldown_errors(session),
	}


func _autonomous_activity_report(session: Variant) -> Dictionary:
	return {
		"route_pressure_count": _facts(
			session, "regional_route_pressure_started"
		).size(),
		"route_pressure_causes": _fact_value_counts(
			_facts(session, "regional_route_pressure_started"), "cause_id"
		),
		"organization_response_count": _organization_response_count(session),
		"route_patrol_count": _facts(
			session, "organization_route_patrolled"
		).size(),
		"trade_coordination_count": _facts(
			session, "organization_trade_coordinated"
		).size(),
		"provisioning_count": _facts(
			session, "organization_provisions_distributed"
		).size(),
	}


func _organization_response_count(session: Variant) -> int:
	return (
		_facts(session, "organization_route_patrolled").size()
		+ _facts(session, "organization_trade_coordinated").size()
		+ _facts(session, "organization_provisions_distributed").size()
	)


func _fact_value_counts(facts: Array, key: String) -> Dictionary:
	var counts: Dictionary = {}
	for fact: Dictionary in facts:
		var value := str(fact.get(key, ""))
		if value != "":
			counts[value] = int(counts.get(value, 0)) + 1
	return counts


func _organization_cooldown_errors(session: Variant) -> Array[String]:
	var errors: Array[String] = []
	var retire_day_by_id: Dictionary = {}
	for fact: Dictionary in _facts(session, "organization_runtime_retired"):
		retire_day_by_id[str(fact.get("organization_id", ""))] = int(
			fact.get("day", 0)
		)
	var formations_by_pair: Dictionary = {}
	for fact: Dictionary in _facts(session, "organization_runtime_formed"):
		var key := "%s::%s" % [
			str(fact.get("settlement_id", "")),
			str(fact.get("prototype_id", "")),
		]
		if not formations_by_pair.has(key):
			formations_by_pair[key] = []
		(formations_by_pair[key] as Array).append(fact)
	for key: String in formations_by_pair.keys():
		var rows: Array = formations_by_pair[key]
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("day", 0)) < int(b.get("day", 0))
		)
		for index: int in range(1, rows.size()):
			var previous: Dictionary = rows[index - 1]
			var current: Dictionary = rows[index]
			var previous_id := str(previous.get("organization_id", ""))
			if not retire_day_by_id.has(previous_id):
				errors.append("%s:reformed_before_retirement" % key)
				continue
			var gap := int(current.get("day", 0)) - int(
				retire_day_by_id[previous_id]
			)
			if gap < 3:
				errors.append("%s:cooldown_gap_%d" % [key, gap])
	return errors


func _migration_report(session: Variant, final_day: int) -> Dictionary:
	var migrations := _facts(session, "household_migrated")
	var absorbed_ids: Dictionary = {}
	for fact: Dictionary in _facts(session, "migrant_household_absorbed"):
		absorbed_ids[str(fact.get("source_migration_fact_id", ""))] = true
	var stale: Array[Dictionary] = []
	for migration: Dictionary in migrations:
		var fact_id := str(migration.get("fact_id", ""))
		var age_days := final_day - int(migration.get("day", 0))
		if age_days > 3 and not absorbed_ids.has(fact_id):
			stale.append({
				"fact_id": fact_id,
				"household_id": str(migration.get("household_id", "")),
				"destination_settlement_id": str(migration.get(
					"destination_settlement_id", ""
				)),
				"age_days": age_days,
			})
	return {
		"migration_count": migrations.size(),
		"absorbed_count": absorbed_ids.size(),
		"stale_unabsorbed": stale,
	}


func _history_signature(session: Variant) -> String:
	var rows: Array[Dictionary] = []
	for fact_type: String in [
		"settlement_trade_shipment",
		"household_migrated",
		"migrant_household_absorbed",
		"organization_runtime_formed",
		"organization_goal_changed",
		"organization_goal_reactivated",
		"organization_runtime_retired",
	]:
		for fact: Dictionary in _facts(session, fact_type):
			rows.append({
				"fact_type": fact_type,
				"fact_id": str(fact.get("fact_id", "")),
				"day": int(fact.get("day", 0)),
				"actor_id": str(fact.get("actor_id", "")),
				"target_id": str(fact.get("target_id", "")),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	return JSON.stringify(rows).sha256_text()


func _route_pressure_signature(session: Variant) -> String:
	var rows: Array[Dictionary] = []
	for fact: Dictionary in _facts(
		session, "regional_route_pressure_started"
	):
		rows.append({
			"link_id": str(fact.get("link_id", "")),
			"cause_id": str(fact.get("cause_id", "")),
			"risk_increase": int(fact.get("risk_increase", 0)),
			"capacity_penalty": float(fact.get("capacity_penalty", 0.0)),
			"start_day": int(fact.get("start_day", 0)),
			"until_day": int(fact.get("until_day", 0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	return JSON.stringify(rows).sha256_text()


func _save_roundtrip_report(session: Variant, seed: int) -> Dictionary:
	var save_path := "user://tests/generated_world_30_day_health_%d.save.json" % seed
	var before: Dictionary = session.get_save_store_data()
	var save_report: Dictionary = session.save_to_path(save_path, {
		"save_id": "save.test.generated_world_30_day_health.%d" % seed,
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-20T12:00:00Z",
		"saved_at_utc": "2026-09-19T12:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(save_path)
	var roundtrip_ok := (
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and bool(restored.validate_persistent_references().get("ok", false))
		and _equivalent(before, restored.get_save_store_data())
	)
	if not roundtrip_ok:
		return {"roundtrip_ok": false, "continuation_ok": false}
	var original_tick: Dictionary = session.advance_time(
		1, "generated_world_health_save_continuation"
	)
	var restored_tick: Dictionary = restored.advance_time(
		1, "generated_world_health_save_continuation"
	)
	return {
		"roundtrip_ok": true,
		"continuation_ok": (
			bool(original_tick.get("success", false))
			and bool(restored_tick.get("success", false))
			and _equivalent(
				session.get_save_store_data(), restored.get_save_store_data()
			)
		),
	}


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


func _facts(session: Variant, fact_type: String) -> Array:
	return session.stores["fact_store"].find_facts_by_type(fact_type)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GENERATED WORLD 30 DAY HEALTH PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 GENERATED WORLD 30 DAY HEALTH FAIL] %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GENERATED WORLD 30 DAY HEALTH RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 GENERATED WORLD 30 DAY HEALTH RESULT] FAIL %d" % failures.size())
	quit(1)
