extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_settlement_absorption.save.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline = _start_isolated(false, 81001)
	_check(
		baseline != null and baseline.is_ready(),
		"1. G3-D 基线通过正式 SimSession 启动"
	)
	if baseline == null or not baseline.is_ready():
		_finish()
		return
	for _hour: int in range(60):
		baseline.advance_time(1, "settlement_absorption_contract")
	var migrations := _facts_of_type(baseline, "household_migrated")
	var housed_facts := _facts_of_type(baseline, "migrant_household_housed")
	var hired_facts := _facts_of_type(baseline, "migrant_reemployed")
	var absorbed_facts := _facts_of_type(
		baseline, "migrant_household_absorbed"
	)
	_check(
		not migrations.is_empty()
		and not housed_facts.is_empty()
		and not absorbed_facts.is_empty(),
		"2. 家庭抵达一天后进入住房与生计吸纳，而非永久停在公共集地"
	)
	var migration: Dictionary = migrations[0] if not migrations.is_empty() else {}
	var absorbed := _absorption_for_migration(
		absorbed_facts, str(migration.get("fact_id", ""))
	)
	_check(
		not absorbed.is_empty()
		and _housing_truth_matches(baseline, migration, absorbed)
		and _all_homes_within_capacity(baseline),
		"3. 整户成员与家庭实体入住真实目的地住屋，床位不超容量"
	)
	_check(
		_reemployment_truth_matches(baseline, migration, hired_facts),
		"4. 迁入劳动者只填补目的聚落真实职业槽位并绑定当地工作地"
	)
	_check(
		_social_embedding_has_sources(baseline, migration),
		"5. 借住与工作关系同时改变关系轴，并由迁移和安置事实追溯"
	)

	for _hour: int in range(24):
		baseline.advance_time(1, "settlement_absorption_followup")
	_check(
		_reemployed_workers_produce_locally(baseline, hired_facts)
		and bool(baseline.validate_persistent_references().get("ok", false)),
		"6. 再就业者会在新聚落继续生产，资源与跨 Store 引用保持完整"
	)

	var save_before: Dictionary = baseline.get_save_store_data()
	var save_report: Dictionary = baseline.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_settlement_absorption",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-18T08:00:00Z",
		"saved_at_utc": "2026-08-22T08:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and _equivalent(save_before, restored.get_save_store_data())
		and not _facts_of_type(
			restored, "migrant_household_absorbed"
		).is_empty(),
		"7. 磁盘存档往返精确保留住房、职业、关系和吸纳历史"
	)

	var blocked = _start_isolated(true, 81001)
	for _hour: int in range(60):
		blocked.advance_time(1, "settlement_absorption_blocked")
	var blocked_migrations := _facts_of_type(blocked, "household_migrated")
	var delayed := _facts_of_type(blocked, "migrant_absorption_evaluated")
	_check(
		not blocked_migrations.is_empty()
		and not delayed.is_empty()
		and _facts_of_type(blocked, "migrant_household_absorbed").is_empty()
		and _blocked_truth_matches(blocked, blocked_migrations[0]),
		"8. 零床位零岗位反事实保留临时安置与失业，不伪造吸纳成功"
	)
	_check(
		_has_pressure(blocked, "migrant_housing_need")
		and _has_pressure(blocked, "migrant_unemployment")
		and bool(blocked.validate_persistent_references().get("ok", false)),
		"9. 吸纳失败形成可追溯住房和失业压力且引用完整"
	)
	_check(
		_multi_seed_absorption_is_valid([81117, 81223, 81581]),
		"10. 三组不同种子均能迁移、评估吸纳并保持容量与引用约束"
	)

	print("[V5 SETTLEMENT ABSORPTION SAMPLE] %s" % JSON.stringify({
		"migration": migration,
		"housed": housed_facts[0] if not housed_facts.is_empty() else {},
		"reemployed": hired_facts,
		"absorbed": absorbed,
	}))
	_finish()


func _start_isolated(block_absorption: bool, seed: int) -> Variant:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		print("[V5 SETTLEMENT ABSORPTION START FAILURE] %s" % JSON.stringify(start))
		return null
	var runtime: Dictionary = session.get_settlement_network_summary()
	for link: Dictionary in runtime.get("links", []):
		link["capacity_per_day"] = 0.0
	if block_absorption:
		for site: Dictionary in runtime.get("sites", []):
			site["dwelling_capacity"] = 0
		for profile: Dictionary in session.npc_livelihood_profiles:
			profile["maximum_slots"] = 0
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)
	session.world_tick_adapter.configure_livelihood_profiles(
		session.npc_livelihood_profiles
	)
	return session


func _absorption_for_migration(facts: Array, migration_fact_id: String) -> Dictionary:
	for fact: Dictionary in facts:
		if str(fact.get("source_migration_fact_id", "")) == migration_fact_id:
			return fact.duplicate(true)
	return {}


func _housing_truth_matches(
		session: Variant,
		migration: Dictionary,
		absorbed: Dictionary
) -> bool:
	var home_id := str(absorbed.get("home_location_id", ""))
	var destination_id := str(migration.get("destination_settlement_id", ""))
	var destination_hub_id := str(migration.get("destination_location_id", ""))
	var household_id := str(migration.get("household_id", ""))
	var home: Dictionary = session.context.get_location(home_id)
	if (
		home_id == ""
		or home_id == destination_hub_id
		or not "settlement_dwelling" in (home.get("tags", []) as Array)
		or str(session.stores["state_store"].get_state(
			household_id, "location_id", ""
		)) != home_id
	):
		return false
	for member_value: Variant in migration.get("member_ids", []):
		var member_id := str(member_value)
		if (
			str(session.stores["state_store"].get_state(
				member_id, "settlement_id", ""
			)) != destination_id
			or str(session.stores["state_store"].get_state(
				member_id, "home_location_id", ""
			)) != home_id
		):
			return false
	return true


func _all_homes_within_capacity(session: Variant) -> bool:
	var capacity_by_settlement: Dictionary = {}
	for site: Dictionary in session.get_settlement_network_summary().get(
		"sites", []
	):
		capacity_by_settlement[str(site.get("settlement_id", ""))] = int(
			site.get("dwelling_capacity", 0)
		)
	var occupancy: Dictionary = {}
	var home_settlement: Dictionary = {}
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		if str(entity.get("type", "")) != "person":
			continue
		var person_id := str(entity.get("id", ""))
		var home_id := str(session.stores["state_store"].get_state(
			person_id, "home_location_id", ""
		))
		var settlement_id := str(session.stores["state_store"].get_state(
			person_id, "settlement_id", ""
		))
		if "settlement_dwelling" not in (
			session.context.get_location(home_id).get("tags", []) as Array
		):
			continue
		occupancy[home_id] = int(occupancy.get(home_id, 0)) + 1
		home_settlement[home_id] = settlement_id
	for home_id: String in occupancy.keys():
		if int(occupancy[home_id]) > int(capacity_by_settlement.get(
			str(home_settlement.get(home_id, "")), 0
		)):
			return false
	return true


func _reemployment_truth_matches(
		session: Variant,
		migration: Dictionary,
		hired_facts: Array
) -> bool:
	var migration_fact_id := str(migration.get("fact_id", ""))
	var destination_id := str(migration.get("destination_settlement_id", ""))
	var matched := 0
	for fact: Dictionary in hired_facts:
		if str(fact.get("source_migration_fact_id", "")) != migration_fact_id:
			continue
		var member_id := str(fact.get("target_id", ""))
		var occupation_id := str(fact.get("occupation_id", ""))
		var workplace_id := str(fact.get("workplace_id", ""))
		if (
			str(session.stores["state_store"].get_state(
				member_id, "settlement_id", ""
			)) != destination_id
			or str(session.stores["state_store"].get_state(
				member_id, "occupation_id", ""
			)) != occupation_id
			or str(session.stores["state_store"].get_state(
				member_id, "workplace_id", ""
			)) != workplace_id
			or session.context.get_location(workplace_id).is_empty()
			or not _profile_exists(
				session.npc_livelihood_profiles,
				destination_id,
				occupation_id,
				workplace_id
			)
		):
			return false
		matched += 1
	return matched > 0


func _profile_exists(
		profiles: Array,
		settlement_id: String,
		occupation_id: String,
		workplace_id: String
) -> bool:
	for profile: Dictionary in profiles:
		if (
			str(profile.get("settlement_id", "")) == settlement_id
			and str(profile.get("occupation_id", "")) == occupation_id
			and str(profile.get("workplace_id", "")) == workplace_id
		):
			return true
	return false


func _social_embedding_has_sources(
		session: Variant, migration: Dictionary
) -> bool:
	var migration_fact_id := str(migration.get("fact_id", ""))
	var sourceful_host := false
	for fact: Dictionary in _facts_of_type(
		session, "migrant_host_relation_formed"
	):
		if migration_fact_id in (fact.get("source_fact_ids", []) as Array):
			sourceful_host = true
	var sourceful_work := false
	for fact: Dictionary in _facts_of_type(
		session, "migrant_work_relation_formed"
	):
		if migration_fact_id in (fact.get("source_fact_ids", []) as Array):
			sourceful_work = true
	return sourceful_host and sourceful_work


func _reemployed_workers_produce_locally(
		session: Variant, hired_facts: Array
) -> bool:
	var hires_by_actor: Dictionary = {}
	for fact: Dictionary in hired_facts:
		hires_by_actor[str(fact.get("target_id", ""))] = fact
	for production: Dictionary in _facts_of_type(
		session, "npc_livelihood_produced"
	):
		var actor_id := str(production.get("actor_id", ""))
		if not hires_by_actor.has(actor_id):
			continue
		var hire: Dictionary = hires_by_actor[actor_id]
		if (
			int(production.get("day", 0)) >= int(hire.get("day", 0))
			and str(production.get("location_id", ""))
			== str(hire.get("workplace_id", ""))
		):
			return true
	return false


func _blocked_truth_matches(session: Variant, migration: Dictionary) -> bool:
	var hub_id := str(migration.get("destination_location_id", ""))
	for member_value: Variant in migration.get("member_ids", []):
		var member_id := str(member_value)
		if (
			str(session.stores["state_store"].get_state(
				member_id, "home_location_id", ""
			)) != hub_id
			or (
				"generated_worker" in (
					session.stores["entity_store"].get_entity(
						member_id
					).get("tags", []) as Array
				)
				and str(session.stores["state_store"].get_state(
					member_id, "livelihood_status", ""
				)) != "unemployed"
			)
		):
			return false
	return true


func _has_pressure(session: Variant, pressure_type: String) -> bool:
	for pressure: Dictionary in session.stores["pressure_store"].list_pressures():
		if str(pressure.get("pressure_type", "")) == pressure_type:
			return true
	return false


func _multi_seed_absorption_is_valid(seeds: Array) -> bool:
	for seed_value: Variant in seeds:
		var session = _start_isolated(false, int(seed_value))
		if session == null:
			return false
		for _hour: int in range(60):
			session.advance_time(1, "settlement_absorption_multi_seed")
		var seed_migrations := _facts_of_type(session, "household_migrated")
		var seed_evaluations := _facts_of_type(
			session, "migrant_absorption_evaluated"
		)
		var capacity_valid := _all_homes_within_capacity(session)
		var reference_report: Dictionary = session.validate_persistent_references()
		if (
			seed_migrations.is_empty()
			or seed_evaluations.is_empty()
			or not capacity_valid
			or not bool(reference_report.get("ok", false))
		):
			print("[V5 SETTLEMENT ABSORPTION SEED FAILURE] %s" % JSON.stringify({
				"seed": int(seed_value),
				"migration_count": seed_migrations.size(),
				"evaluation_count": seed_evaluations.size(),
				"capacity_valid": capacity_valid,
				"reference_report": reference_report,
			}))
			return false
	return true


func _facts_of_type(session: Variant, fact_type: String) -> Array:
	return session.stores["fact_store"].find_facts_by_type(fact_type)


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
		print("[V5 SETTLEMENT ABSORPTION CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 SETTLEMENT ABSORPTION CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SETTLEMENT ABSORPTION CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 SETTLEMENT ABSORPTION CONTRACT FAIL] %s" % label)
