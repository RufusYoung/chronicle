extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const FamilyGenerationSystemModel = preload(
	"res://scripts/sim/population/family_generation_system.gd"
)
const PopulationLifecycleSystemModel = preload(
	"res://scripts/sim/population/population_lifecycle_system.gd"
)
const TransactionWorldWriterModel = preload(
	"res://scripts/sim/transaction/transaction_world_writer.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_family_generation.save.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const YEARS_TO_SIMULATE := 35

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var first := _simulate(81001, YEARS_TO_SIMULATE * 365)
	_check(
		bool(first.get("ok", false))
		and not (first.get("given_names", []) as Array).is_empty()
		and str(first.get("culture_id", "")) == "culture.north_border_lakes",
		"1. 家庭世代配置从正式居民定义取得文化、姓名池和确定性种子"
	)
	if not bool(first.get("ok", false)):
		print("[V5 FAMILY GENERATION FAILURE] %s" % JSON.stringify(first))
		_finish()
		return

	_check(
		int(first.get("conception_count", 0)) > 0
		and int(first.get("birth_count", 0)) > 0
		and int(first.get("active_population", 0)) != int(
			first.get("initial_population", 0)
		),
		"2. 无测试注入的长期推进会形成孕育、延迟出生和真实人口变化"
	)
	_check(
		int(first.get("partnership_count", 0)) > 0
		and int(first.get("formed_household_count", 0)) > 0
		and int(first.get("household_change_count", 0)) > 0,
		"3. 未结伴成年人会依据亲缘边界、关系和住房形成伴侣与新家庭"
	)
	_check(
		bool(first.get("newborn_contract_ok", false))
		and bool(first.get("kinship_contract_ok", false))
		and bool(first.get("birth_chronicle_ok", false)),
		"4. 新生儿拥有完整实体、生命周期、继承属性、亲子关系和家庭 Chronicle"
	)
	_check(
		int(first.get("maximum_generation", 0)) >= 2
		and int(first.get("second_generation_birth_count", 0)) > 0,
		"5. 第一代运行期新生儿成年后能够形成家庭并产生第二代"
	)
	var extinction_probe := _extinction_probe()
	_check(
		int(first.get("death_count", 0)) > 0
		and int(first.get("inheritance_count", 0)) > 0
		and bool(first.get("inheritance_contract_ok", false))
		and bool(extinction_probe.get("ok", false))
		and int(extinction_probe.get("extinguished_household_count", 0)) == 1,
		"6. 自然死亡会转移真实物品，测试注入的绝户家庭软退场且历史仍可追溯"
	)

	var repeated := _simulate(81001, YEARS_TO_SIMULATE * 365)
	var alternate := _simulate(82002, YEARS_TO_SIMULATE * 365)
	_check(
		bool(repeated.get("ok", false))
		and str(first.get("signature", "")) == str(
			repeated.get("signature", "")
		)
		and bool(alternate.get("ok", false))
		and str(first.get("signature", "")) != str(
			alternate.get("signature", "")
		),
		"7. 同一种子完整复现家族史，不同种子产生不同伴侣、出生与家庭历史"
	)

	var session: Variant = first.get("session")
	var before_save: Dictionary = session.get_save_store_data()
	var save_report: Dictionary = session.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_family_generation",
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
		and bool(restored.validate_persistent_references().get("ok", false)),
		"8. 多世代人物、家庭、亲缘、遗产和 Chronicle 可精确存档恢复"
	)
	var integration_probe := _world_tick_integration_probe()
	_check(
		bool(integration_probe.get("ok", false))
		and int(integration_probe.get("birth_count", 0)) > 0,
		"9. 缩短周期的测试注入证明家庭系统经正式 WorldTick 产生孕育与次日出生"
	)

	print("[V5 FAMILY GENERATION SAMPLE] %s" % JSON.stringify({
		"seed": 81001,
		"years": YEARS_TO_SIMULATE,
		"initial_population": int(first.get("initial_population", 0)),
		"active_population": int(first.get("active_population", 0)),
		"partnerships": int(first.get("partnership_count", 0)),
		"households_formed": int(first.get("formed_household_count", 0)),
		"conceptions": int(first.get("conception_count", 0)),
		"births": int(first.get("birth_count", 0)),
		"second_generation_births": int(first.get(
			"second_generation_birth_count", 0
		)),
		"deaths": int(first.get("death_count", 0)),
		"inheritances": int(first.get("inheritance_count", 0)),
		"households_extinguished": int(first.get(
			"extinguished_household_count", 0
		)),
		"maximum_generation": int(first.get("maximum_generation", 0)),
	}))
	_finish()


func _simulate(seed: int, last_day: int) -> Dictionary:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		return {"ok": false, "error": start}
	var network: Dictionary = session.get_settlement_network_summary()
	var family_config: Dictionary = network.get("family_generation", {})
	var initial_population := _active_population(session)
	var family_system = FamilyGenerationSystemModel.new()
	var population_system = PopulationLifecycleSystemModel.new()
	var writer = TransactionWorldWriterModel.new()
	var scheduled_days := _scheduled_days(family_config, last_day)
	for day: int in scheduled_days:
		var tick_event := {"day": day, "elapsed_hours": 24}
		var population_data: Dictionary = population_system.resolve_daily_tick(
			_snapshot(session, day),
			tick_event,
			network.get("population_lifecycle", {})
		)
		if not writer.apply_results(
			population_data.get("results", []), session.stores
		):
			return {
				"ok": false,
				"error": "population_write_failed",
				"day": day,
				"report": writer.last_report,
			}
		var family_data: Dictionary = family_system.resolve_daily_tick(
			_snapshot(session, day),
			tick_event,
			network,
			session.context.get_locations()
		)
		if not writer.apply_results(
			family_data.get("results", []), session.stores
		):
			return {
				"ok": false,
				"error": "family_write_failed",
				"day": day,
				"report": writer.last_report,
			}
	session.current_day = last_day
	session.elapsed_hours_since_start = maxi(last_day - 1, 0) * 24
	var facts: Variant = session.stores["fact_store"]
	var births: Array = facts.find_facts_by_type("resident_born")
	var maximum_generation := 0
	var second_generation_birth_count := 0
	for birth: Dictionary in births:
		var generation := int(birth.get("generation_index", 0))
		maximum_generation = maxi(maximum_generation, generation)
		if generation >= 2:
			second_generation_birth_count += 1
	return {
		"ok": bool(session.validate_persistent_references().get("ok", false)),
		"session": session,
		"culture_id": str(family_config.get("culture_id", "")),
		"given_names": (family_config.get("given_names", []) as Array).duplicate(),
		"initial_population": initial_population,
		"active_population": _active_population(session),
		"partnership_count": facts.find_facts_by_type(
			"resident_partnership_formed"
		).size(),
		"formed_household_count": facts.find_facts_by_type(
			"household_formed"
		).size(),
		"household_change_count": facts.find_facts_by_type(
			"resident_household_changed"
		).size(),
		"conception_count": facts.find_facts_by_type(
			"resident_conceived"
		).size(),
		"birth_count": births.size(),
		"second_generation_birth_count": second_generation_birth_count,
		"maximum_generation": maximum_generation,
		"death_count": facts.find_facts_by_type("resident_died").size(),
		"inheritance_count": facts.find_facts_by_type(
			"resident_inheritance_transferred"
		).size(),
		"extinguished_household_count": facts.find_facts_by_type(
			"household_extinguished"
		).size(),
		"newborn_contract_ok": _newborn_contract_ok(session, births),
		"kinship_contract_ok": _kinship_contract_ok(session, births),
		"birth_chronicle_ok": _birth_chronicle_ok(session, births),
		"inheritance_contract_ok": _inheritance_contract_ok(session),
		"signature": _family_signature(session),
	}


func _extinction_probe() -> Dictionary:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": 83003}
	)
	if not bool(start.get("success", false)):
		return {"ok": false, "error": start}
	var snapshot: Variant = _snapshot(session, 2)
	var households: Array = snapshot.get_entities_by_type("household")
	if households.is_empty():
		return {"ok": false, "error": "household_missing"}
	var household_id := str((households[0] as Dictionary).get("id", ""))
	var member_ids: Array[String] = []
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if str(snapshot.get_entity_state(
			person_id, "household_id", ""
		)) == household_id:
			member_ids.append(person_id)
	if member_ids.is_empty():
		return {"ok": false, "error": "household_members_missing"}
	for member_id: String in member_ids:
		if not session.stores["state_store"].apply_state_change({
			"entity_id": member_id,
			"key": "health",
			"to": 0,
		}):
			return {"ok": false, "error": "health_injection_failed"}
	var writer = TransactionWorldWriterModel.new()
	var network: Dictionary = session.get_settlement_network_summary()
	var tick_event := {"day": 2, "elapsed_hours": 24}
	var population_data: Dictionary = PopulationLifecycleSystemModel.new(
	).resolve_daily_tick(
		_snapshot(session, 2),
		tick_event,
		network.get("population_lifecycle", {})
	)
	if not writer.apply_results(population_data.get("results", []), session.stores):
		return {"ok": false, "error": writer.last_report}
	var family_data: Dictionary = FamilyGenerationSystemModel.new(
	).resolve_daily_tick(
		_snapshot(session, 2),
		tick_event,
		network,
		session.context.get_locations()
	)
	if not writer.apply_results(family_data.get("results", []), session.stores):
		return {"ok": false, "error": writer.last_report}
	var extinction_facts: Array = session.stores[
		"fact_store"
	].find_facts_by_type("household_extinguished")
	return {
		"ok": (
			not session.stores["entity_store"].is_entity_active(household_id)
			and not session.stores["entity_store"].get_entity(
				household_id
			).is_empty()
			and bool(session.validate_persistent_references().get("ok", false))
		),
		"extinguished_household_count": extinction_facts.size(),
		"household_id": household_id,
	}


func _world_tick_integration_probe() -> Dictionary:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": 84004}
	)
	if not bool(start.get("success", false)):
		return {"ok": false, "error": start}
	var network: Dictionary = session.get_settlement_network_summary()
	var family: Dictionary = network.get("family_generation", {})
	family["partnership_interval_days"] = 999999
	family["conception_interval_days"] = 1
	family["conception_chance_percent"] = 100
	family["maximum_conceptions_per_settlement_per_cycle"] = 1
	family["gestation_days"] = 1
	family["birth_cooldown_days"] = 1
	family["maximum_parent_age"] = 100
	network["family_generation"] = family
	for site: Dictionary in network.get("sites", []):
		site["resident_capacity"] = 100
	session.settlement_network_runtime = network.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(network)
	var advance: Dictionary = session.advance_time(
		48, "family_generation_integration_test_injection"
	)
	var births: Array = session.stores["fact_store"].find_facts_by_type(
		"resident_born"
	)
	var all_births_active := true
	for birth: Dictionary in births:
		if not session.stores["entity_store"].is_entity_active(str(
			birth.get("resident_id", "")
		)):
			all_births_active = false
	return {
		"ok": (
			bool(advance.get("success", false))
			and all_births_active
			and bool(session.validate_persistent_references().get("ok", false))
		),
		"birth_count": births.size(),
	}


func _scheduled_days(config: Dictionary, last_day: int) -> Array[int]:
	var partnership_interval := maxi(int(config.get(
		"partnership_interval_days", 365
	)), 1)
	var conception_interval := maxi(int(config.get(
		"conception_interval_days", 90
	)), 1)
	var gestation_days := maxi(int(config.get("gestation_days", 280)), 1)
	var unique_days: Dictionary = {}
	for day: int in range(partnership_interval, last_day + 1, partnership_interval):
		unique_days[day] = true
	for day: int in range(conception_interval, last_day + 1, conception_interval):
		unique_days[day] = true
	for day: int in range(
		conception_interval + gestation_days,
		last_day + 1,
		conception_interval
	):
		unique_days[day] = true
	var rows: Array[int] = []
	for day_value: Variant in unique_days.keys():
		rows.append(int(day_value))
	rows.sort()
	return rows


func _newborn_contract_ok(session: Variant, births: Array) -> bool:
	if births.is_empty():
		return false
	for birth: Dictionary in births:
		var resident_id := str(birth.get("resident_id", ""))
		var entity: Dictionary = session.stores["entity_store"].get_entity(
			resident_id
		)
		var states: Dictionary = session.stores["state_store"].list_states(
			resident_id
		)
		if (
			entity.is_empty()
			or "born_resident" not in (entity.get("tags", []) as Array)
			or int(states.get("generation_index", 0)) < 1
			or int(states.get("birth_day", 0)) != int(birth.get("day", -1))
			or str(states.get("life_status", "")) != "alive"
			or str(states.get("household_id", "")) == ""
			or str(states.get("settlement_id", "")) == ""
		):
			return false
		for attribute: String in [
			"strength", "dexterity", "wisdom", "charisma",
			"constitution", "perception"
		]:
			if int(states.get(attribute, 0)) < 2:
				return false
	return true


func _kinship_contract_ok(session: Variant, births: Array) -> bool:
	var kinship: Array = session.stores["fact_store"].find_facts_by_type(
		"runtime_kinship_formed"
	)
	for birth: Dictionary in births:
		var resident_id := str(birth.get("resident_id", ""))
		var birth_fact_id := str(birth.get("fact_id", ""))
		var has_parent := false
		var has_child := false
		for fact: Dictionary in kinship:
			if birth_fact_id not in (fact.get("source_fact_ids", []) as Array):
				continue
			if (
				str(fact.get("target_id", "")) == resident_id
				and str(fact.get("relationship_kind", "")) == "parent_of"
			):
				has_parent = true
			if (
				str(fact.get("actor_id", "")) == resident_id
				and str(fact.get("relationship_kind", "")) == "child_of"
			):
				has_child = true
		if not has_parent or not has_child:
			return false
	return true


func _birth_chronicle_ok(session: Variant, births: Array) -> bool:
	var source_ids: Dictionary = {}
	for entry: Dictionary in session.stores["chronicle_store"].list_entries():
		for source_id: Variant in entry.get("source_fact_ids", []):
			source_ids[str(source_id)] = true
	for birth: Dictionary in births:
		if not source_ids.has(str(birth.get("fact_id", ""))):
			return false
	return not births.is_empty()


func _inheritance_contract_ok(session: Variant) -> bool:
	var rows: Array = session.stores["fact_store"].find_facts_by_type(
		"resident_inheritance_transferred"
	)
	if rows.is_empty():
		return false
	for fact: Dictionary in rows:
		var heir_id := str(fact.get("heir_id", ""))
		for item_value: Variant in fact.get("item_instance_ids", []):
			var item: Dictionary = session.stores["item_store"].get_item(
				str(item_value)
			)
			var holder: Dictionary = item.get("holder", {})
			if (
				str(holder.get("kind", "")) != "entity"
				or str(holder.get("id", "")) != heir_id
			):
				return false
	return true


func _family_signature(session: Variant) -> String:
	var rows: Array[String] = []
	for fact_type: String in [
		"resident_partnership_formed",
		"household_formed",
		"resident_conceived",
		"resident_born",
		"resident_died",
		"resident_inheritance_transferred",
		"household_extinguished",
	]:
		for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
			fact_type
		):
			rows.append("%s|%s|%s|%d|%d" % [
				fact_type,
				str(fact.get("actor_id", "")),
				str(fact.get("target_id", "")),
				int(fact.get("day", 0)),
				int(fact.get("generation_index", 0)),
			])
	rows.sort()
	return ";".join(rows)


func _active_population(session: Variant) -> int:
	return _snapshot(session, session.current_day).get_entities_by_type(
		"person"
	).size()


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
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	return left == right


func _finish() -> void:
	if failures.is_empty():
		print("[V5 FAMILY GENERATION CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 FAMILY GENERATION CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 FAMILY GENERATION CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 FAMILY GENERATION CONTRACT FAIL] %s" % label)
