extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const CapacitySystemModel = preload(
	"res://scripts/sim/settlement/settlement_capacity_adaptation_system.gd"
)
const PopulationLifecycleSystemModel = preload(
	"res://scripts/sim/population/population_lifecycle_system.gd"
)
const FamilyGenerationSystemModel = preload(
	"res://scripts/sim/population/family_generation_system.gd"
)
const LaborSystemModel = preload(
	"res://scripts/sim/population/labor_absorption_system.gd"
)
const SettlementAbsorptionSystemModel = preload(
	"res://scripts/sim/migration/settlement_absorption_system.gd"
)
const TransactionWorldWriterModel = preload(
	"res://scripts/sim/transaction/transaction_world_writer.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_capacity_adaptation.save.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = _start(81001)
	var runtime: Dictionary = session.get_settlement_network_summary()
	var settlement_id := str((runtime.get("sites", []) as Array)[0].get(
		"settlement_id", ""
	))
	var plots := _construction_plots(session, settlement_id)
	_check(
		bool(runtime.get("capacity_adaptation", {}).get("enabled", false))
		and plots.size() == 6,
		"1. 生成网络携带容量适应规则，并为每个聚落预先落位可建地块"
	)
	var capacity_system = CapacitySystemModel.new()
	var default_rules: Dictionary = runtime.get("capacity_adaptation", {})
	var organization_support: Dictionary = capacity_system._organization_support(
		_snapshot(session, 1), settlement_id, default_rules
	)
	var base_housing_days := int(default_rules.get(
		"housing_pressure_days_required", 30
	))
	_check(
		not organization_support.is_empty()
		and int(organization_support.get("member_count", 0)) > 0
		and capacity_system._required_pressure_days(
			base_housing_days, organization_support
		) < base_housing_days
		and capacity_system._required_pressure_days(
			base_housing_days, {}
		) == base_housing_days
		and _has_fact_id(
			session, str(organization_support.get("source_fact_id", ""))
		),
		"2. 活跃组织按真实在岗成员缩短协调周期，无组织时居民仍按完整周期自建"
	)

	var housing_config := runtime.duplicate(true)
	var housing_rules: Dictionary = housing_config.get(
		"capacity_adaptation", {}
	).duplicate(true)
	housing_rules["housing_pressure_ratio_percent"] = 1
	housing_rules["housing_pressure_days_required"] = 1
	housing_rules["housing_construction_cooldown_days"] = 0
	housing_rules["labor_pressure_days_required"] = 999999
	housing_config["capacity_adaptation"] = housing_rules
	var capacity_before := int(session.stores["state_store"].get_state(
		settlement_id, "resident_capacity", 0
	))
	var construction_stock_before := _construction_stock(session, settlement_id)
	var housing_data := CapacitySystemModel.new().resolve_daily_tick(
		_snapshot(session, 50), {"day": 50, "elapsed_hours": 1},
		housing_config, session.npc_livelihood_profiles,
		session.context.get_locations()
	)
	var housing_applied := TransactionWorldWriterModel.new().apply_results(
		housing_data.get("results", []), session.stores
	)
	var dwelling := _latest_fact(
		session, "settlement_dwelling_constructed", settlement_id
	)
	var construction_stock_after: Dictionary = session.stores[
		"resource_stock_store"
	].get_stock(str(dwelling.get("resource_stock_id", "")))
	var dwelling_feature_id := "runtime_feature.dwelling.%s" % _safe_id(str(
		dwelling.get("home_location_id", "")
	))
	_check(
		housing_applied and not dwelling.is_empty()
		and int(session.stores["state_store"].get_state(
			settlement_id, "resident_capacity", 0
		)) > capacity_before
		and float(construction_stock_after.get("current", 0.0))
		< float(construction_stock_before.get("current", 0.0))
		and session.stores["entity_store"].has_entity(dwelling_feature_id)
		and str(dwelling.get("coordinator_organization_id", "")) == str(
			organization_support.get("organization_id", "")
		)
		and str(organization_support.get("source_fact_id", "")) in (
			dwelling.get("source_fact_ids", []) as Array
		),
		"3. 住房压力消耗真实材料建成住屋，并记录实际协调组织与来源"
	)
	var constructed_location: Dictionary = session.context.get_location(str(
		dwelling.get("home_location_id", "")
	))
	_check(
		SettlementAbsorptionSystemModel.new()._is_dwelling(
			_snapshot(session, 50), constructed_location
		),
		"4. 新建住屋进入家庭与迁入吸纳共用的真实住房判定，不只是展示事实"
	)

	var seeker_id := _employment_seeker(session, settlement_id)
	_inject_unemployment(session, seeker_id, 100)
	var closed_profiles := _profiles_without_open_slots(
		session, settlement_id
	)
	session.npc_livelihood_profiles = closed_profiles.duplicate(true)
	session.world_tick_adapter.configure_livelihood_profiles(closed_profiles)
	var labor_config := runtime.duplicate(true)
	var labor_rules: Dictionary = labor_config.get(
		"capacity_adaptation", {}
	).duplicate(true)
	labor_rules["housing_pressure_days_required"] = 999999
	labor_rules["labor_pressure_days_required"] = 1
	labor_rules["facility_expansion_cooldown_days"] = 0
	labor_config["capacity_adaptation"] = labor_rules
	var expansion_data := CapacitySystemModel.new().resolve_daily_tick(
		_snapshot(session, 100), {"day": 100, "elapsed_hours": 1},
		labor_config, closed_profiles, session.context.get_locations()
	)
	var expansion_applied := TransactionWorldWriterModel.new().apply_results(
		expansion_data.get("results", []), session.stores
	)
	var expansion := _latest_fact(
		session, "settlement_work_capacity_changed", settlement_id,
		"labor_pressure_expansion"
	)
	var labor_data := LaborSystemModel.new().resolve_daily_tick(
		_snapshot(session, 101), {"day": 101, "elapsed_hours": 1},
		labor_config, closed_profiles, session.context.get_locations()
	)
	var labor_applied := TransactionWorldWriterModel.new().apply_results(
		labor_data.get("results", []), session.stores
	)
	var employment := _latest_target_fact(
		session, "resident_employed", seeker_id
	)
	_check(
		expansion_applied and labor_applied and not expansion.is_empty()
		and int(expansion.get("capacity_delta", 0)) > 0
		and str(expansion.get("coordinator_organization_id", "")) == str(
			organization_support.get("organization_id", "")
		)
		and not employment.is_empty()
		and str(session.stores["state_store"].get_state(
			seeker_id, "livelihood_status", ""
		)) in ["employed", "self_employed"],
		"5. 组织协调就业扩建，随后由正式劳动力系统吸纳真实求职者"
	)

	var closure_profile := _profile_with_resource_worker(
		session, closed_profiles, settlement_id
	)
	var closure_stock_id := str((closure_profile.get(
		"resource_inputs", []
	) as Array)[0].get("stock_id", ""))
	var closure_stock: Dictionary = session.stores["resource_stock_store"].get_stock(
		closure_stock_id
	)
	var workers_before := _workers(
		session, settlement_id, str(closure_profile.get("occupation_id", ""))
	)
	session.stores["resource_stock_store"].apply_resource_change({
		"stock_id": closure_stock_id,
		"operation": "set",
		"amount": 0.0,
		"tick": 120 * 24,
	})
	var closure_data := CapacitySystemModel.new().resolve_daily_tick(
		_snapshot(session, 120), {"day": 120, "elapsed_hours": 1},
		labor_config, closed_profiles, session.context.get_locations()
	)
	var closure_applied := TransactionWorldWriterModel.new().apply_results(
		closure_data.get("results", []), session.stores
	)
	var closure := _latest_fact(
		session, "settlement_work_capacity_changed", settlement_id,
		"resource_depleted", str(closure_profile.get("occupation_id", ""))
	)
	var laid_off := _facts_for_type_and_settlement(
		session, "resident_laid_off", settlement_id
	)
	_check(
		closure_applied and not closure.is_empty()
		and int(closure.get("capacity_after", -1)) == 0
		and not workers_before.is_empty()
		and laid_off.size() >= workers_before.size()
		and _all_unemployed(session, workers_before),
		"6. 生产资源枯竭会把对应岗位关闭至零，并让实际在岗居民进入求职状态"
	)

	session.stores["resource_stock_store"].apply_resource_change({
		"stock_id": closure_stock_id,
		"operation": "set",
		"amount": float(closure_stock.get("capacity", 0.0)) * 0.8,
		"tick": 121 * 24,
	})
	var reopen_data := CapacitySystemModel.new().resolve_daily_tick(
		_snapshot(session, 121), {"day": 121, "elapsed_hours": 1},
		labor_config, closed_profiles, session.context.get_locations()
	)
	var reopen_applied := TransactionWorldWriterModel.new().apply_results(
		reopen_data.get("results", []), session.stores
	)
	var reopened := _latest_fact(
		session, "settlement_work_capacity_changed", settlement_id,
		"resource_recovered", str(closure_profile.get("occupation_id", ""))
	)
	_check(
		reopen_applied and not reopened.is_empty()
		and int(reopened.get("capacity_after", 0)) > 0,
		"7. 资源恢复后同一设施按关闭前容量重新开放，容量变化形成连续事实链"
	)

	var source_integrity := _capacity_sources_exist(session)
	var before_save: Dictionary = session.get_save_store_data()
	var save_report: Dictionary = session.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_capacity_adaptation",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-21T12:00:00Z",
		"saved_at_utc": "2026-08-21T13:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	_check(
		source_integrity
		and bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and _equivalent(before_save, restored.get_save_store_data())
		and bool(restored.validate_persistent_references().get("ok", false)),
		"8. 住宅、设施、裁员和复工的来源事实与运行实体可精确存档恢复"
	)

	var first_signature := _one_day_pressure_signature(83003)
	var repeat_signature := _one_day_pressure_signature(83003)
	var other_signature := _one_day_pressure_signature(84004)
	_check(
		first_signature != "" and first_signature == repeat_signature
		and first_signature != other_signature,
		"9. 相同种子容量适应结果精确复现，不同种子保留不同世界来源"
	)
	var natural_history := _natural_capacity_history(81001, 35 * 365)
	_check(
		bool(natural_history.get("ok", false))
		and int(natural_history.get("adaptation_count", 0)) > 0,
		"10. 无测试注入的 35 年人口与劳动力演化会自然触发聚落容量变化"
	)

	print("[V5 SETTLEMENT CAPACITY ADAPTATION SAMPLE] %s" % JSON.stringify({
		"dwelling": dwelling,
		"expansion": expansion,
		"closure": closure,
		"reopened": reopened,
		"laid_off_count": laid_off.size(),
		"natural_history": natural_history,
	}))
	_finish()


func _start(seed: int) -> Variant:
	var session = SimSessionModel.new()
	var report: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(report.get("success", false)):
		push_error("capacity adaptation fixture failed: %s" % report)
	return session


func _snapshot(session: Variant, day: int) -> Variant:
	return session.snapshot_builder.build_snapshot(
		session.context, session.stores, true,
		{"day": day, "hour": 8, "period": "morning"}
	)


func _construction_plots(session: Variant, settlement_id: String) -> Array:
	var rows: Array = []
	for location: Dictionary in session.context.get_locations():
		if (
			str(location.get("settlement_id", "")) == settlement_id
			and "settlement_construction_plot" in (
				location.get("tags", []) as Array
			)
		):
			rows.append(location)
	return rows


func _construction_stock(session: Variant, settlement_id: String) -> Dictionary:
	var expected := ["building", "timber", "stone", "reeds", "fiber"]
	for stock: Dictionary in session.stores[
		"resource_stock_store"
	].list_stocks_for_settlement(settlement_id):
		for tag: Variant in stock.get("tags", []):
			if str(tag) in expected:
				return stock
	return {}


func _employment_seeker(session: Variant, settlement_id: String) -> String:
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		var entity_id := str(entity.get("id", ""))
		if (
			str(entity.get("type", "")) == "person"
			and str(session.stores["state_store"].get_state(
				entity_id, "settlement_id", ""
			)) == settlement_id
			and int(session.stores["state_store"].get_state(
				entity_id, "age_years", 0
			)) >= 18
			and str(session.stores["state_store"].get_state(
				entity_id, "livelihood_status", ""
			)) in ["employed", "self_employed"]
		):
			return entity_id
	return ""


func _inject_unemployment(
		session: Variant, resident_id: String, day: int
) -> void:
	var home_id := str(session.stores["state_store"].get_state(
		resident_id, "home_location_id", ""
	))
	for change: Dictionary in [
		{"entity_id": resident_id, "key": "occupation_id", "to": "unemployed"},
		{"entity_id": resident_id, "key": "livelihood_status", "to": "unemployed"},
		{"entity_id": resident_id, "key": "workplace_id", "to": home_id},
	]:
		session.stores["state_store"].apply_state_change(change)
	session.stores["fact_store"].add_fact({
		"fact_id": "fact.test_employment_search.%s.day%d" % [
			_safe_id(resident_id), day,
		],
		"fact_type": "resident_employment_search_unmet",
		"actor_id": str(session.stores["state_store"].get_state(
			resident_id, "settlement_id", ""
		)),
		"target_id": resident_id,
		"day": day - 1,
		"reason": "test_injection",
	})


func _profiles_without_open_slots(
		session: Variant, settlement_id: String
) -> Array:
	var rows: Array = []
	for value: Variant in session.npc_livelihood_profiles:
		if not value is Dictionary:
			continue
		var profile := (value as Dictionary).duplicate(true)
		if str(profile.get("settlement_id", "")) == settlement_id:
			profile["maximum_slots"] = _workers(
				session, settlement_id, str(profile.get("occupation_id", ""))
			).size()
		rows.append(profile)
	return rows


func _profile_with_resource_worker(
		session: Variant, profiles: Array, settlement_id: String
) -> Dictionary:
	for value: Variant in profiles:
		if not value is Dictionary:
			continue
		var profile: Dictionary = value
		if (
			str(profile.get("settlement_id", "")) == settlement_id
			and not (profile.get("resource_inputs", []) as Array).is_empty()
			and not _workers(
				session, settlement_id, str(profile.get("occupation_id", ""))
			).is_empty()
		):
			return profile
	return {}


func _workers(
		session: Variant, settlement_id: String, occupation_id: String
) -> Array[String]:
	var rows: Array[String] = []
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		var entity_id := str(entity.get("id", ""))
		if (
			str(entity.get("type", "")) == "person"
			and str(session.stores["state_store"].get_state(
				entity_id, "settlement_id", ""
			)) == settlement_id
			and str(session.stores["state_store"].get_state(
				entity_id, "occupation_id", ""
			)) == occupation_id
			and str(session.stores["state_store"].get_state(
				entity_id, "livelihood_status", ""
			)) in ["employed", "self_employed"]
		):
			rows.append(entity_id)
	rows.sort()
	return rows


func _all_unemployed(session: Variant, resident_ids: Array[String]) -> bool:
	for resident_id: String in resident_ids:
		if str(session.stores["state_store"].get_state(
			resident_id, "livelihood_status", ""
		)) != "unemployed":
			return false
	return true


func _latest_fact(
		session: Variant,
		fact_type: String,
		settlement_id: String,
		reason: String = "",
		occupation_id: String = ""
) -> Dictionary:
	var rows := _facts_for_type_and_settlement(
		session, fact_type, settlement_id
	)
	for index: int in range(rows.size() - 1, -1, -1):
		var fact: Dictionary = rows[index]
		if reason != "" and str(fact.get("reason", "")) != reason:
			continue
		if occupation_id != "" and str(fact.get(
			"occupation_id", ""
		)) != occupation_id:
			continue
		return fact
	return {}


func _latest_target_fact(
		session: Variant, fact_type: String, target_id: String
) -> Dictionary:
	var rows: Array = session.stores["fact_store"].find_facts_by_type(fact_type)
	for index: int in range(rows.size() - 1, -1, -1):
		if str((rows[index] as Dictionary).get("target_id", "")) == target_id:
			return rows[index]
	return {}


func _facts_for_type_and_settlement(
		session: Variant, fact_type: String, settlement_id: String
) -> Array:
	var rows: Array = []
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		fact_type
	):
		if str(fact.get("settlement_id", fact.get(
			"target_id", ""
		))) == settlement_id:
			rows.append(fact)
	return rows


func _capacity_sources_exist(session: Variant) -> bool:
	var known: Dictionary = {}
	for fact: Dictionary in session.stores["fact_store"].list_facts():
		known[str(fact.get("fact_id", ""))] = true
	for fact_type: String in [
		"settlement_dwelling_constructed", "settlement_work_capacity_changed",
		"resident_laid_off",
	]:
		for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
			fact_type
		):
			if (fact.get("source_fact_ids", []) as Array).is_empty():
				return false
			for source: Variant in fact.get("source_fact_ids", []):
				if not known.has(str(source)):
					return false
	return true


func _has_fact_id(session: Variant, fact_id: String) -> bool:
	if fact_id == "":
		return false
	for fact: Dictionary in session.stores["fact_store"].list_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _one_day_pressure_signature(seed: int) -> String:
	var session = _start(seed)
	var runtime: Dictionary = session.get_settlement_network_summary()
	var settlement_id := str((runtime.get("sites", []) as Array)[0].get(
		"settlement_id", ""
	))
	var rules: Dictionary = runtime.get("capacity_adaptation", {}).duplicate(true)
	rules["housing_pressure_ratio_percent"] = 1
	rules["housing_pressure_days_required"] = 1
	rules["housing_construction_cooldown_days"] = 0
	rules["labor_pressure_days_required"] = 999999
	runtime["capacity_adaptation"] = rules
	var data := CapacitySystemModel.new().resolve_daily_tick(
		_snapshot(session, 10), {"day": 10, "elapsed_hours": 1}, runtime,
		session.npc_livelihood_profiles, session.context.get_locations()
	)
	TransactionWorldWriterModel.new().apply_results(
		data.get("results", []), session.stores
	)
	var fact := _latest_fact(
		session, "settlement_dwelling_constructed", settlement_id
	)
	return JSON.stringify(fact, "", true) if not fact.is_empty() else ""


func _natural_capacity_history(seed: int, last_day: int) -> Dictionary:
	var session = _start(seed)
	var network: Dictionary = session.get_settlement_network_summary()
	var population_system = PopulationLifecycleSystemModel.new()
	var family_system = FamilyGenerationSystemModel.new()
	var capacity_system = CapacitySystemModel.new()
	var labor_system = LaborSystemModel.new()
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
			return {"ok": false, "day": day, "error": writer.last_report}
		var family: Dictionary = family_system.resolve_daily_tick(
			_snapshot(session, day), tick_event, network,
			session.context.get_locations()
		)
		if not writer.apply_results(family.get("results", []), session.stores):
			return {"ok": false, "day": day, "error": writer.last_report}
		var labor: Dictionary = labor_system.resolve_daily_tick(
			_snapshot(session, day), tick_event, network,
			session.npc_livelihood_profiles, session.context.get_locations()
		)
		if not writer.apply_results(labor.get("results", []), session.stores):
			return {"ok": false, "day": day, "error": writer.last_report}
		if not _capacity_pressure_possible(session, network):
			continue
		var required_window := maxi(
			int((network.get("capacity_adaptation", {}) as Dictionary).get(
				"housing_pressure_days_required", 30
			)),
			int((network.get("capacity_adaptation", {}) as Dictionary).get(
				"labor_pressure_days_required", 14
			))
		)
		for pressure_day: int in range(
			day, mini(day + required_window + 1, last_day + 1)
		):
			var pressure_tick := {"day": pressure_day, "elapsed_hours": 24}
			var capacity: Dictionary = capacity_system.resolve_daily_tick(
				_snapshot(session, pressure_day), pressure_tick, network,
				session.npc_livelihood_profiles, session.context.get_locations()
			)
			if not writer.apply_results(
				capacity.get("results", []), session.stores
			):
				return {
					"ok": false,
					"day": pressure_day,
					"error": writer.last_report,
				}
			var followup_labor: Dictionary = labor_system.resolve_daily_tick(
				_snapshot(session, pressure_day), pressure_tick, network,
				session.npc_livelihood_profiles, session.context.get_locations()
			)
			if not writer.apply_results(
				followup_labor.get("results", []), session.stores
			):
				return {
					"ok": false,
					"day": pressure_day,
					"error": writer.last_report,
				}
		if (
			not session.stores["fact_store"].find_facts_by_type(
				"settlement_dwelling_constructed"
			).is_empty()
			or not session.stores["fact_store"].find_facts_by_type(
				"settlement_work_capacity_changed"
			).is_empty()
		):
			break
	var dwellings: Array = session.stores["fact_store"].find_facts_by_type(
		"settlement_dwelling_constructed"
	)
	var capacity_changes: Array = session.stores[
		"fact_store"
	].find_facts_by_type("settlement_work_capacity_changed")
	var expansions := 0
	for fact: Dictionary in capacity_changes:
		if str(fact.get("reason", "")) == "labor_pressure_expansion":
			expansions += 1
	return {
		"ok": bool(session.validate_persistent_references().get("ok", false)),
		"dwelling_count": dwellings.size(),
		"work_capacity_change_count": capacity_changes.size(),
		"facility_expansion_count": expansions,
		"adaptation_count": dwellings.size() + expansions,
		"active_population": _active_population(session),
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


func _capacity_pressure_possible(
		session: Variant, network: Dictionary
) -> bool:
	var snapshot: Variant = _snapshot(session, 1)
	var rules: Dictionary = network.get("capacity_adaptation", {})
	var housing_ratio := clampi(int(rules.get(
		"housing_pressure_ratio_percent", 85
	)), 1, 100)
	var minimum_unemployed := maxi(int(rules.get(
		"minimum_unemployed_for_expansion", 1
	)), 1)
	for site: Dictionary in network.get("sites", []):
		var settlement_id := str(site.get("settlement_id", ""))
		var population := 0
		var unemployed := 0
		var workers: Dictionary = {}
		for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
			var entity_id := str(entity.get("id", ""))
			if (
				str(entity.get("type", "")) != "person"
				or str(session.stores["state_store"].get_state(
					entity_id, "settlement_id", ""
				)) != settlement_id
				or str(session.stores["state_store"].get_state(
					entity_id, "life_status", "alive"
				)) != "alive"
			):
				continue
			population += 1
			var status := str(session.stores["state_store"].get_state(
				entity_id, "livelihood_status", ""
			))
			if status == "unemployed":
				unemployed += 1
			elif status in ["employed", "self_employed"]:
				var occupation_id := str(session.stores["state_store"].get_state(
					entity_id, "occupation_id", ""
				))
				workers[occupation_id] = int(workers.get(occupation_id, 0)) + 1
		var capacity := int(session.stores["state_store"].get_state(
			settlement_id, "resident_capacity", 0
		))
		if capacity > 0 and population * 100 >= capacity * housing_ratio:
			return true
		if unemployed < minimum_unemployed:
			continue
		var open_slots := 0
		for profile: Dictionary in session.npc_livelihood_profiles:
			if str(profile.get("settlement_id", "")) != settlement_id:
				continue
			var occupation_id := str(profile.get("occupation_id", ""))
			var dynamic_delta := CapacitySystemModel.new()._occupation_capacity_delta(
				snapshot, settlement_id, occupation_id
			)
			open_slots += maxi(
				int(profile.get("maximum_slots", 0)) + dynamic_delta
				- int(workers.get(occupation_id, 0)),
				0
			)
		if open_slots <= 0:
			return true
	return false


func _active_population(session: Variant) -> int:
	var count := 0
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		var entity_id := str(entity.get("id", ""))
		if (
			str(entity.get("type", "")) == "person"
			and entity_id != "player"
			and session.stores["entity_store"].is_entity_active(entity_id)
			and str(session.stores["state_store"].get_state(
				entity_id, "life_status", "alive"
			)) == "alive"
		):
			count += 1
	return count


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
		print("[V5 SETTLEMENT CAPACITY ADAPTATION PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SETTLEMENT CAPACITY ADAPTATION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 SETTLEMENT CAPACITY ADAPTATION FAIL] " + failure)
	print("[V5 SETTLEMENT CAPACITY ADAPTATION RESULT] FAIL %d" % failures.size())
	quit(1)
