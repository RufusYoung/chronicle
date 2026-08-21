extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const PopulationLifecycleSystemModel = preload(
	"res://scripts/sim/population/population_lifecycle_system.gd"
)
const FamilyGenerationSystemModel = preload(
	"res://scripts/sim/population/family_generation_system.gd"
)
const LaborAbsorptionSystemModel = preload(
	"res://scripts/sim/population/labor_absorption_system.gd"
)
const TransactionWorldWriterModel = preload(
	"res://scripts/sim/transaction/transaction_world_writer.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_labor_absorption.save.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = _start(81001)
	var minor_id := _minor_id(session)
	var settlement_id := str(session.stores["state_store"].get_state(
		minor_id, "settlement_id", ""
	))
	var runtime: Dictionary = session.get_settlement_network_summary()
	_check(
		not runtime.get("labor_absorption", {}).is_empty()
		and bool(runtime.get("labor_absorption", {}).get("enabled", false))
		and not session.npc_livelihood_profiles.is_empty(),
		"1. 生成聚落携带本地劳动力规则与产业岗位档案"
	)

	_configure_open_profiles(session, settlement_id)
	_inject_next_day_adult(session, minor_id)
	var adulthood_tick: Dictionary = session.advance_time(
		1, "labor_adulthood_test_injection"
	)
	_check(
		bool(adulthood_tick.get("success", false))
		and str(session.stores["state_store"].get_state(
			minor_id, "livelihood_status", ""
		)) == "unemployed"
		and _facts_for_target(
			session, "resident_reached_adulthood", minor_id
		).size() == 1
		and _facts_for_target(
			session, "resident_employed", minor_id
		).is_empty(),
		"2. 测试注入的居民成年当天先进入可观察的求职状态"
	)
	var hire_tick: Dictionary = session.advance_time(
		24, "labor_hiring_followup"
	)
	var employment := _latest_fact_for_target(
		session, "resident_employed", minor_id
	)
	var occupation_id := str(employment.get("occupation_id", ""))
	var workplace_id := str(employment.get("workplace_id", ""))
	_check(
		bool(hire_tick.get("success", false))
		and not employment.is_empty()
		and occupation_id not in ["", "unemployed", "dependent"]
		and workplace_id != ""
		and str(session.stores["state_store"].get_state(
			minor_id, "occupation_id", ""
		)) == occupation_id
		and str(session.stores["state_store"].get_state(
			minor_id, "workplace_id", ""
		)) == workplace_id,
		"3. 一天后岗位容量、能力和聚落产业把求职者写入真实职业与工作地"
	)
	var hired_entity: Dictionary = session.stores["entity_store"].get_entity(
		minor_id
	)
	_check(
		"generated_worker" in (hired_entity.get("tags", []) as Array)
		and "occupation_%s" % occupation_id in (
			hired_entity.get("tags", []) as Array
		)
		and _employment_sources_ok(session, employment)
		and _employment_relation_ok(session, minor_id, workplace_id)
		and _employment_chronicle_ok(session, minor_id),
		"4. 就业事务同步更新生产标签、来源事实、同事关系与家庭 Chronicle"
	)

	var profile := _profile(session, settlement_id, occupation_id)
	var interval := maxi(int(profile.get("work_interval_hours", 8)), 1)
	session.stores["state_store"].apply_state_change({
		"entity_id": minor_id,
		"key": "livelihood_elapsed_hours",
		"to": interval - 1,
	})
	var production_before := _facts_for_actor(
		session, "npc_livelihood_produced", minor_id
	).size()
	var production_tick: Dictionary = session.advance_time(
		1, "labor_production_test_injection"
	)
	_check(
		bool(production_tick.get("success", false))
		and _facts_for_actor(
			session, "npc_livelihood_produced", minor_id
		).size() > production_before,
		"5. 新就业居民由正式生计系统消耗工作周期并产生真实物品"
	)

	var no_slot := _no_slot_probe(82002)
	_check(
		bool(no_slot.get("ok", false))
		and int(no_slot.get("employment_count", -1)) == 0
		and int(no_slot.get("unmet_count", 0)) == 1,
		"6. 零岗位反事实保留失业并记录求职压力，不伪造职业"
	)
	var household_match := _household_continuity_probe(83003)
	_check(
		bool(household_match.get("ok", false))
		and str(household_match.get("occupation_id", "")) == str(
			household_match.get("household_occupation_id", "")
		),
		"7. 相同家庭已有的职业经验会在能力相近时影响岗位匹配"
	)

	var generations := _generational_labor_simulation(81001, 35 * 365)
	var generations_repeat := _generational_labor_simulation(81001, 35 * 365)
	var generations_other := _generational_labor_simulation(82002, 35 * 365)
	_check(
		bool(generations.get("ok", false))
		and int(generations.get("born_adult_hire_count", 0)) > 0
		and int(generations.get("maximum_hired_generation", 0)) >= 1,
		"8. 无成年测试注入的 35 年路径会让运行期出生者成年并进入本地岗位"
	)
	_check(
		str(generations.get("signature", "")) == str(
			generations_repeat.get("signature", "")
		)
		and str(generations.get("signature", "")) != str(
			generations_other.get("signature", "")
		),
		"9. 同种子就业史精确复现，不同种子形成不同代际劳动力史"
	)

	var before_save: Dictionary = session.get_save_store_data()
	var save_report: Dictionary = session.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_labor_absorption",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-21T10:00:00Z",
		"saved_at_utc": "2026-08-21T11:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and _equivalent(before_save, restored.get_save_store_data())
		and bool(restored.validate_persistent_references().get("ok", false))
		and str(restored.stores["state_store"].get_state(
			minor_id, "occupation_id", ""
		)) == occupation_id,
		"10. 存档往返精确保留新职业、生产历史、关系与来源引用"
	)

	print("[V5 LABOR ABSORPTION SAMPLE] %s" % JSON.stringify({
		"first_hired_resident": minor_id,
		"first_occupation": occupation_id,
		"family_match": household_match,
		"generational_labor": {
			"employment_count": int(generations.get("employment_count", 0)),
			"born_adult_hire_count": int(generations.get(
				"born_adult_hire_count", 0
			)),
			"maximum_hired_generation": int(generations.get(
				"maximum_hired_generation", 0
			)),
		},
	}))
	_finish()


func _start(seed: int) -> Variant:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		print("[V5 LABOR ABSORPTION START FAILURE] %s" % JSON.stringify(start))
	return session


func _configure_open_profiles(session: Variant, settlement_id: String) -> void:
	var profiles: Array = session.npc_livelihood_profiles.duplicate(true)
	for profile: Dictionary in profiles:
		if str(profile.get("settlement_id", "")) == settlement_id:
			profile["maximum_slots"] = int(profile.get("maximum_slots", 0)) + 5
	session.npc_livelihood_profiles = profiles.duplicate(true)
	session.world_tick_adapter.configure_livelihood_profiles(profiles)
	var runtime: Dictionary = session.get_settlement_network_summary()
	var labor: Dictionary = runtime.get("labor_absorption", {})
	labor["maximum_hires_per_settlement_per_day"] = 99
	runtime["labor_absorption"] = labor
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)


func _inject_next_day_adult(session: Variant, resident_id: String) -> void:
	var home_id := str(session.stores["state_store"].get_state(
		resident_id, "home_location_id", ""
	))
	for change: Dictionary in [
		{"entity_id": resident_id, "key": "age_years", "to": 17},
		{"entity_id": resident_id, "key": "birth_day", "to": 1 - 18 * 365},
		{"entity_id": resident_id, "key": "life_expectancy_years", "to": 90},
		{"entity_id": resident_id, "key": "livelihood_status", "to": "dependent"},
		{"entity_id": resident_id, "key": "occupation_id", "to": "dependent"},
		{"entity_id": resident_id, "key": "workplace_id", "to": home_id},
	]:
		session.stores["state_store"].apply_state_change(change)


func _no_slot_probe(seed: int) -> Dictionary:
	var session = _start(seed)
	var resident_id := _minor_id(session)
	_inject_adult_seeker(session, resident_id)
	var profiles: Array = session.npc_livelihood_profiles.duplicate(true)
	for profile: Dictionary in profiles:
		profile["maximum_slots"] = 0
	var network: Dictionary = session.get_settlement_network_summary()
	var config: Dictionary = network.get("labor_absorption", {})
	config["minimum_search_days"] = 0
	network["labor_absorption"] = config
	var data: Dictionary = LaborAbsorptionSystemModel.new().resolve_daily_tick(
		_snapshot(session, 2), {"day": 2, "elapsed_hours": 24},
		network, profiles, session.context.get_locations()
	)
	var writer = TransactionWorldWriterModel.new()
	var applied := writer.apply_results(data.get("results", []), session.stores)
	return {
		"ok": (
			applied
			and str(session.stores["state_store"].get_state(
				resident_id, "livelihood_status", ""
			)) == "unemployed"
			and bool(session.validate_persistent_references().get("ok", false))
		),
		"employment_count": _facts_for_target(
			session, "resident_employed", resident_id
		).size(),
		"unmet_count": _facts_for_target(
			session, "resident_employment_search_unmet", resident_id
		).size(),
	}


func _household_continuity_probe(seed: int) -> Dictionary:
	var session = _start(seed)
	var pair := _dependent_with_working_household_member(session)
	if pair.is_empty():
		return {"ok": false, "error": "working_household_pair_missing"}
	var resident_id := str(pair.get("resident_id", ""))
	var worker_id := str(pair.get("worker_id", ""))
	var settlement_id := str(session.stores["state_store"].get_state(
		resident_id, "settlement_id", ""
	))
	var household_occupation_id := str(session.stores["state_store"].get_state(
		worker_id, "occupation_id", ""
	))
	_inject_adult_seeker(session, resident_id)
	for attribute: String in [
		"strength", "dexterity", "wisdom", "charisma", "constitution", "perception"
	]:
		session.stores["state_store"].apply_state_change({
			"entity_id": resident_id, "key": attribute, "to": 6
		})
	var profiles: Array = []
	var alternative_added := false
	for source: Dictionary in session.npc_livelihood_profiles:
		if str(source.get("settlement_id", "")) != settlement_id:
			continue
		if (
			str(source.get("occupation_id", "")) == household_occupation_id
			or not alternative_added
		):
			var profile := source.duplicate(true)
			profile["maximum_slots"] = 999
			profiles.append(profile)
			if str(source.get("occupation_id", "")) != household_occupation_id:
				alternative_added = true
	var network: Dictionary = session.get_settlement_network_summary()
	var config: Dictionary = network.get("labor_absorption", {})
	config["minimum_search_days"] = 0
	config["maximum_hires_per_settlement_per_day"] = 99
	config["household_occupation_bonus"] = 1000
	config["open_slot_score_weight"] = 0
	network["labor_absorption"] = config
	var data: Dictionary = LaborAbsorptionSystemModel.new().resolve_daily_tick(
		_snapshot(session, 2), {"day": 2, "elapsed_hours": 24},
		network, profiles, session.context.get_locations()
	)
	var writer = TransactionWorldWriterModel.new()
	var applied := writer.apply_results(data.get("results", []), session.stores)
	var employment := _latest_fact_for_target(
		session, "resident_employed", resident_id
	)
	return {
		"ok": (
			applied
			and bool(employment.get("household_occupation_match", false))
			and bool(session.validate_persistent_references().get("ok", false))
		),
		"resident_id": resident_id,
		"occupation_id": str(employment.get("occupation_id", "")),
		"household_occupation_id": household_occupation_id,
	}


func _generational_labor_simulation(seed: int, last_day: int) -> Dictionary:
	var session = _start(seed)
	var network: Dictionary = session.get_settlement_network_summary()
	var population_system = PopulationLifecycleSystemModel.new()
	var family_system = FamilyGenerationSystemModel.new()
	var labor_system = LaborAbsorptionSystemModel.new()
	var writer = TransactionWorldWriterModel.new()
	for day: int in _scheduled_days(
		network.get("family_generation", {}), last_day
	):
		var tick_event := {"day": day, "elapsed_hours": 24}
		var population: Dictionary = population_system.resolve_daily_tick(
			_snapshot(session, day), tick_event,
			network.get("population_lifecycle", {})
		)
		if not writer.apply_results(population.get("results", []), session.stores):
			return {"ok": false, "error": writer.last_report, "day": day}
		var family: Dictionary = family_system.resolve_daily_tick(
			_snapshot(session, day), tick_event, network,
			session.context.get_locations()
		)
		if not writer.apply_results(family.get("results", []), session.stores):
			return {"ok": false, "error": writer.last_report, "day": day}
		var labor: Dictionary = labor_system.resolve_daily_tick(
			_snapshot(session, day), tick_event, network,
			session.npc_livelihood_profiles, session.context.get_locations()
		)
		if not writer.apply_results(labor.get("results", []), session.stores):
			return {"ok": false, "error": writer.last_report, "day": day}
	var employments: Array = session.stores[
		"fact_store"
	].find_facts_by_type("resident_employed")
	var born_adult_hire_count := 0
	var maximum_hired_generation := 0
	var signature_rows: Array[String] = []
	for employment: Dictionary in employments:
		var resident_id := str(employment.get("resident_id", ""))
		var generation := int(session.stores["state_store"].get_state(
			resident_id, "generation_index", 0
		))
		if resident_id.begins_with("born_resident."):
			born_adult_hire_count += 1
			maximum_hired_generation = maxi(
				maximum_hired_generation, generation
			)
		signature_rows.append("%s|%s|%d|%d" % [
			resident_id,
			str(employment.get("occupation_id", "")),
			int(employment.get("day", 0)),
			generation,
		])
	signature_rows.sort()
	return {
		"ok": bool(session.validate_persistent_references().get("ok", false)),
		"employment_count": employments.size(),
		"born_adult_hire_count": born_adult_hire_count,
		"maximum_hired_generation": maximum_hired_generation,
		"signature": ";".join(signature_rows),
	}


func _scheduled_days(config: Dictionary, last_day: int) -> Array[int]:
	var partnership_interval := maxi(int(config.get(
		"partnership_interval_days", 365
	)), 1)
	var conception_interval := maxi(int(config.get(
		"conception_interval_days", 90
	)), 1)
	var gestation_days := maxi(int(config.get("gestation_days", 280)), 1)
	var unique: Dictionary = {}
	for day: int in range(partnership_interval, last_day + 1, partnership_interval):
		unique[day] = true
	for day: int in range(conception_interval, last_day + 1, conception_interval):
		unique[day] = true
	for day: int in range(
		conception_interval + gestation_days,
		last_day + 1,
		conception_interval
	):
		unique[day] = true
	var rows: Array[int] = []
	for value: Variant in unique.keys():
		rows.append(int(value))
	rows.sort()
	return rows


func _inject_adult_seeker(session: Variant, resident_id: String) -> void:
	var home_id := str(session.stores["state_store"].get_state(
		resident_id, "home_location_id", ""
	))
	for change: Dictionary in [
		{"entity_id": resident_id, "key": "age_years", "to": 18},
		{"entity_id": resident_id, "key": "life_stage", "to": "adult"},
		{"entity_id": resident_id, "key": "livelihood_status", "to": "unemployed"},
		{"entity_id": resident_id, "key": "occupation_id", "to": "unemployed"},
		{"entity_id": resident_id, "key": "workplace_id", "to": home_id},
	]:
		session.stores["state_store"].apply_state_change(change)


func _minor_id(session: Variant) -> String:
	for person: Dictionary in _snapshot(session, 1).get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			person_id != "player"
			and int(session.stores["state_store"].get_state(
				person_id, "age_years", 99
			)) < 18
		):
			return person_id
	return ""


func _dependent_with_working_household_member(session: Variant) -> Dictionary:
	var snapshot: Variant = _snapshot(session, 1)
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var resident_id := str(person.get("id", ""))
		if int(snapshot.get_entity_state(resident_id, "age_years", 99)) >= 18:
			continue
		var household_id := str(snapshot.get_entity_state(
			resident_id, "household_id", ""
		))
		for worker: Dictionary in snapshot.get_entities_by_type("person"):
			var worker_id := str(worker.get("id", ""))
			if (
				str(snapshot.get_entity_state(
					worker_id, "household_id", ""
				)) == household_id
				and str(snapshot.get_entity_state(
					worker_id, "livelihood_status", ""
				)) in ["employed", "self_employed"]
			):
				return {"resident_id": resident_id, "worker_id": worker_id}
	return {}


func _profile(
		session: Variant, settlement_id: String, occupation_id: String
) -> Dictionary:
	for profile: Dictionary in session.npc_livelihood_profiles:
		if (
			str(profile.get("settlement_id", "")) == settlement_id
			and str(profile.get("occupation_id", "")) == occupation_id
		):
			return profile
	return {}


func _employment_sources_ok(session: Variant, employment: Dictionary) -> bool:
	var sources: Array = employment.get("source_fact_ids", [])
	if sources.size() < 2:
		return false
	var fact_ids: Dictionary = {}
	for fact: Dictionary in session.stores["fact_store"].list_facts():
		fact_ids[str(fact.get("fact_id", ""))] = true
	for source: Variant in sources:
		if not fact_ids.has(str(source)):
			return false
	return true


func _employment_relation_ok(
		session: Variant, resident_id: String, workplace_id: String
) -> bool:
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"resident_work_relation_formed"
	):
		if (
			str(fact.get("actor_id", "")) == resident_id
			and str(fact.get("workplace_id", "")) == workplace_id
		):
			return true
	return false


func _employment_chronicle_ok(session: Variant, resident_id: String) -> bool:
	for entry: Dictionary in session.stores["chronicle_store"].list_entries():
		if str(entry.get("entry_id", "")).begins_with(
			"chronicle.resident_employed.%s." % _safe_id(resident_id)
		):
			return not (entry.get("source_fact_ids", []) as Array).is_empty()
	return false


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


func _facts_for_actor(
		session: Variant, fact_type: String, actor_id: String
) -> Array:
	var rows: Array = []
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		fact_type
	):
		if str(fact.get("actor_id", "")) == actor_id:
			rows.append(fact)
	return rows


func _latest_fact_for_target(
		session: Variant, fact_type: String, target_id: String
) -> Dictionary:
	var rows := _facts_for_target(session, fact_type, target_id)
	return {} if rows.is_empty() else rows[-1]


func _snapshot(session: Variant, day: int) -> Variant:
	return session.snapshot_builder.build_snapshot(
		session.context,
		session.stores,
		true,
		{"day": day, "hour": 8, "period": "morning"}
	)


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
	if left is float or right is float:
		return is_equal_approx(float(left), float(right))
	return left == right


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 LABOR ABSORPTION PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LABOR ABSORPTION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 LABOR ABSORPTION FAIL] " + failure)
	print("[V5 LABOR ABSORPTION RESULT] FAIL %d" % failures.size())
	quit(1)
