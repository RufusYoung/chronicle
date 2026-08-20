extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const WorldTickAdapterModel = preload(
	"res://scripts/sim/world_tick/world_tick_adapter.gd"
)
const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const LiveLocationViewModel = preload(
	"res://scripts/rebuild/v5_live_location_view_model.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := (
	"user://tests/generated_multi_signal_organization_lifecycle.save.json"
)
const REED_ID := "generated_settlement.reed_bay"
const RIVER_ID := "generated_settlement.river_steps"
const REED_HUB_ID := "generated_location.reed_bay.commons"
const ROAD_ORGANIZATION_ID := (
	"runtime_organization.reed_bay.road_fellows.cycle1"
)
const WATCH_ORGANIZATION_ID := (
	"runtime_organization.reed_bay.pass_watch.cycle1"
)
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var migration_session = _start(81001)
	_check(
		migration_session != null
		and migration_session.is_ready()
		and _prototype(migration_session, "road_fellows").get(
			"lifecycle", {}
		).get("signal", {}).get("kind", "") == "recent_fact_count",
		"1. G4-C2-B 正式定义装载迁入事实窗口观察器"
	)
	if migration_session == null or not migration_session.is_ready():
		_finish()
		return
	var migration_adapter: Variant = _adapter(
		migration_session,
		[_prototype(migration_session, "road_fellows")],
		{}
	)
	var households := _household_ids(migration_session)
	_check(
		households.size() >= 3,
		"2. 迁入路径使用生成世界中的真实家庭作为测试注入主体"
	)
	if households.size() < 3:
		_finish()
		return
	_inject_migration(migration_session, str(households[0]), 1)
	_apply_tick(migration_adapter, migration_session, 1, "migration_day1")
	_check(
		_entity(migration_session, ROAD_ORGANIZATION_ID).is_empty()
		and _formation_observations(
			migration_session, "road_fellows"
		).size() == 1,
		"3. 一次迁入先形成社会观察，不立即生成同业会"
	)
	_apply_tick(migration_adapter, migration_session, 2, "migration_day2")
	var road_organization := _entity(
		migration_session, ROAD_ORGANIZATION_ID
	)
	_check(
		str(road_organization.get("lifecycle_status", "active")) == "active"
		and not (road_organization.get("founding_member_ids", []) as Array).is_empty()
		and _formation_signal(
			migration_session, ROAD_ORGANIZATION_ID
		) == "recent_incoming_households",
		"4. 迁入事实连续留在窗口内两日后，苇湾形成临时行路同业会"
	)

	_inject_migration(migration_session, str(households[1]), 3)
	_apply_tick(migration_adapter, migration_session, 3, "migration_day3")
	var effectiveness_rows := _facts(
		migration_session, "organization_effectiveness_evaluated"
	)
	migration_session.context.set_current_location(REED_HUB_ID)
	var view_model = LiveLocationViewModel.new(migration_session)
	view_model.latest_event_type = "world_tick"
	var effectiveness_view := JSON.stringify(view_model.build_view_data())
	_check(
		effectiveness_rows.size() == 1
		and int((effectiveness_rows[0] as Dictionary).get(
			"ineffective_streak", 0
		)) == 1
		and "效能复盘" in effectiveness_view,
		"5. 组织成立后未完成现实行动会留下效能事实，并进入地点面板"
	)
	_apply_tick(migration_adapter, migration_session, 4, "migration_day4")
	_check(
		_facts(migration_session, "organization_effectiveness_evaluated").size()
		== 2
		and "征集可用车夫" in str(_entity(
			migration_session, ROAD_ORGANIZATION_ID
		).get("goal", "")),
		"6. 连续两日无行动使同业会转向征集人手与运力，不再永久僵死"
	)
	_inject_migration(migration_session, str(households[2]), 5)
	_apply_tick(migration_adapter, migration_session, 5, "migration_day5")
	_apply_tick(migration_adapter, migration_session, 6, "migration_day6")
	var retired_road := _entity(migration_session, ROAD_ORGANIZATION_ID)
	_check(
		str(retired_road.get("lifecycle_status", "")) == "retired"
		and int(retired_road.get("retired_day", 0)) == 6
		and _has_retirement_summary(
			migration_session,
			ROAD_ORGANIZATION_ID,
			"没有完成转运协调"
		),
		"7. 迁入压力仍在但连续四日无执行能力时，同业会退场并保留失败史"
	)

	var quiet_migration = _start(81001)
	var quiet_migration_adapter: Variant = _adapter(
		quiet_migration,
		[_prototype(quiet_migration, "road_fellows")],
		{}
	)
	_apply_tick(quiet_migration_adapter, quiet_migration, 1, "quiet_migration1")
	_apply_tick(quiet_migration_adapter, quiet_migration, 2, "quiet_migration2")
	_check(
		_entity(quiet_migration, ROAD_ORGANIZATION_ID).is_empty(),
		"8. 相同种子没有迁入事实时不会生成同业会，迁入路径具备反事实差异"
	)

	var route_session = _start(81001)
	var pass_watch := _prototype(route_session, "pass_watch")
	pass_watch["required_any_industry_ids"] = []
	var route_lifecycle: Dictionary = pass_watch.get("lifecycle", {})
	route_lifecycle["required_all_terrain_tags"] = []
	var route_signal: Dictionary = route_lifecycle.get("signal", {})
	route_signal["settlement_ids"] = [REED_ID]
	route_lifecycle["signal"] = route_signal
	pass_watch["lifecycle"] = route_lifecycle
	var high_risk_network := _network_with_reed_risk(
		route_session.get_settlement_network_summary(), 3
	)
	var route_adapter: Variant = _adapter(
		route_session, [pass_watch], high_risk_network
	)
	_apply_tick(route_adapter, route_session, 1, "route_risk_day1")
	_apply_tick(route_adapter, route_session, 2, "route_risk_day2")
	var watch_organization := _entity(
		route_session, WATCH_ORGANIZATION_ID
	)
	_check(
		str(watch_organization.get("lifecycle_status", "active")) == "active"
		and _formation_signal(
			route_session, WATCH_ORGANIZATION_ID
		) == "maximum_adjacent_route_risk",
		"9. 相邻道路连续高风险形成守路队，来源信号不同于迁入同业会"
	)
	_apply_tick(route_adapter, route_session, 3, "route_patrol_day3")
	var patrols := _organization_facts(
		route_session, "organization_route_patrolled", WATCH_ORGANIZATION_ID
	)
	var route_recovery := _latest_observation(
		route_session, "pass_watch", "recovery"
	)
	_check(
		patrols.size() == 1
		and int(route_recovery.get("signal_value", 99)) == 2
		and str((patrols[0] as Dictionary).get("fact_id", "")) in (
			route_recovery.get("source_fact_ids", []) as Array
		),
		"10. 守路队消耗真实道路运力巡守后，有效风险下降并成为收尾信号来源"
	)
	_apply_tick(route_adapter, route_session, 4, "route_patrol_day4")
	_check(
		str(_entity(route_session, WATCH_ORGANIZATION_ID).get(
			"lifecycle_status", ""
		)) == "retired"
		and _organization_facts(
			route_session,
			"organization_runtime_retired",
			WATCH_ORGANIZATION_ID
		).size() == 1,
		"11. 道路风险连续受控后守路队软退场，行动与退场构成完整因果链"
	)

	var quiet_route = _start(81001)
	var quiet_pass_watch := _prototype(quiet_route, "pass_watch")
	quiet_pass_watch["required_any_industry_ids"] = []
	var quiet_lifecycle: Dictionary = quiet_pass_watch.get("lifecycle", {})
	quiet_lifecycle["required_all_terrain_tags"] = []
	var quiet_signal: Dictionary = quiet_lifecycle.get("signal", {})
	quiet_signal["settlement_ids"] = [REED_ID]
	quiet_lifecycle["signal"] = quiet_signal
	quiet_pass_watch["lifecycle"] = quiet_lifecycle
	var quiet_route_adapter: Variant = _adapter(
		quiet_route,
		[quiet_pass_watch],
		_network_with_reed_risk(
			quiet_route.get_settlement_network_summary(), 1
		)
	)
	_apply_tick(quiet_route_adapter, quiet_route, 1, "quiet_route1")
	_apply_tick(quiet_route_adapter, quiet_route, 2, "quiet_route2")
	_check(
		_entity(quiet_route, WATCH_ORGANIZATION_ID).is_empty(),
		"12. 相同种子低道路风险时不生成守路队，道路路径具备反事实差异"
	)

	var save_report: Dictionary = route_session.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_multi_signal_organization_lifecycle",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-20T10:00:00Z",
		"saved_at_utc": "2026-08-20T11:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and bool(restored.validate_persistent_references().get("ok", false))
		and _history_signature(restored) == _history_signature(route_session),
		"13. 存档往返精确保留道路信号、巡守行动、目标转向与退场历史"
	)

	_check(
		_history_signature(migration_session)
		!= _history_signature(route_session),
		"14. 同种子迁入压力与道路压力产生不同组织种类、行动和生命周期历史"
	)
	var seed_matrix := _multi_seed_matrix([81001, 82002, 83003])
	_check(
		(seed_matrix.get("errors", []) as Array).is_empty()
		and (seed_matrix.get("rows", []) as Array).size() == 3,
		"15. 三组种子均形成迁入同业会与道路守路队两条不同历史，异常数为零"
	)
	print("[V5 MULTI SIGNAL ORGANIZATION LIFECYCLE SAMPLE] %s" % JSON.stringify({
		"migration_history": _history_rows(migration_session),
		"route_history": _history_rows(route_session),
		"seed_matrix": seed_matrix,
	}))
	_finish()


func _start(seed: int) -> Variant:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		print("[V5 MULTI SIGNAL START FAILURE] %s" % JSON.stringify(start))
		return null
	return session


func _adapter(
		session: Variant, prototypes: Array, network_config: Dictionary
) -> Variant:
	var adapter = WorldTickAdapterModel.new()
	var config: Dictionary = (
		session.world_tick_adapter.organization_runtime_config.duplicate(true)
	)
	config["lifecycle_prototypes"] = prototypes.duplicate(true)
	adapter.configure_organization_runtime(config)
	if not network_config.is_empty():
		adapter.configure_settlement_network(network_config)
	return adapter


func _apply_tick(
	adapter: Variant, session: Variant, day: int, source: String
) -> Dictionary:
	return adapter.apply_tick_event(session.context, session.stores, {
		"tick_event_id": "test.multi_signal.%s.day%d" % [source, day],
		"tick_type": "test_event",
		"trigger_key": "test_multi_signal_organization_lifecycle",
		"scope_type": "global",
		"scope_id": "",
		"source": "generated_multi_signal_organization_lifecycle_contract_test",
		"label": "多信号组织生命周期测试注入",
		"day": day,
		"hour": 8,
		"elapsed_hours": 0,
		"include_due_checks": false,
	})


func _inject_migration(session: Variant, household_id: String, day: int) -> void:
	var fact_id := "fact.test_injected_household_migrated.%s.day%d" % [
		_safe_id(household_id), day
	]
	var result = TransactionResultModel.new()
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "household_migrated",
		"actor_id": household_id,
		"target_id": REED_ID,
		"household_id": household_id,
		"member_ids": [],
		"source_settlement_id": RIVER_ID,
		"destination_settlement_id": REED_ID,
		"destination_location_id": REED_HUB_ID,
		"link_id": "reed_bay_river_steps",
		"pressure_days": 2,
		"day": day,
		"summary": "测试注入记录一户家庭沿道路迁入苇湾。",
	})
	result.mark_resolved("test_injected_household_migration")
	if not session.writer.apply_result(result, session.stores):
		failures.append("迁入事实测试注入失败：%s" % fact_id)


func _prototype(session: Variant, prototype_id: String) -> Dictionary:
	if session == null:
		return {}
	for value: Variant in session.world_tick_adapter.organization_runtime_config.get(
		"lifecycle_prototypes", []
	):
		if (
			value is Dictionary
			and str((value as Dictionary).get("prototype_id", ""))
			== prototype_id
		):
			return (value as Dictionary).duplicate(true)
	return {}


func _network_with_reed_risk(network: Dictionary, risk: int) -> Dictionary:
	var updated := network.duplicate(true)
	var links: Array = updated.get("links", [])
	for index: int in range(links.size()):
		var link: Dictionary = (links[index] as Dictionary).duplicate(true)
		link["risk"] = (
			risk
			if str(link.get("link_id", "")) == "reed_bay_river_steps"
			else 1
		)
		links[index] = link
	updated["links"] = links
	return updated


func _multi_seed_matrix(seeds: Array) -> Dictionary:
	var rows: Array[Dictionary] = []
	var errors: Array[String] = []
	for seed_value: Variant in seeds:
		var seed := int(seed_value)
		var migration = _start(seed)
		if migration == null:
			errors.append("migration_start_failed:%d" % seed)
			continue
		var households := _household_ids(migration)
		if households.is_empty():
			errors.append("migration_household_missing:%d" % seed)
			continue
		var migration_adapter: Variant = _adapter(
			migration, [_prototype(migration, "road_fellows")], {}
		)
		_inject_migration(migration, str(households[0]), 1)
		_apply_tick(migration_adapter, migration, 1, "seed_migration1_%d" % seed)
		_apply_tick(migration_adapter, migration, 2, "seed_migration2_%d" % seed)
		var road_formed := not _entity(
			migration, ROAD_ORGANIZATION_ID
		).is_empty()

		var route = _start(seed)
		if route == null:
			errors.append("route_start_failed:%d" % seed)
			continue
		var watch := _prototype(route, "pass_watch")
		watch["required_any_industry_ids"] = []
		var lifecycle: Dictionary = watch.get("lifecycle", {})
		lifecycle["required_all_terrain_tags"] = []
		var definition: Dictionary = lifecycle.get("signal", {})
		definition["settlement_ids"] = [REED_ID]
		lifecycle["signal"] = definition
		watch["lifecycle"] = lifecycle
		var route_adapter: Variant = _adapter(
			route,
			[watch],
			_network_with_reed_risk(route.get_settlement_network_summary(), 3)
		)
		_apply_tick(route_adapter, route, 1, "seed_route1_%d" % seed)
		_apply_tick(route_adapter, route, 2, "seed_route2_%d" % seed)
		_apply_tick(route_adapter, route, 3, "seed_route3_%d" % seed)
		var watch_formed := not _entity(
			route, WATCH_ORGANIZATION_ID
		).is_empty()
		var watch_acted := not _organization_facts(
			route, "organization_route_patrolled", WATCH_ORGANIZATION_ID
		).is_empty()
		var histories_differ := (
			_history_signature(migration) != _history_signature(route)
		)
		if not road_formed:
			errors.append("road_fellows_not_formed:%d" % seed)
		if not watch_formed:
			errors.append("pass_watch_not_formed:%d" % seed)
		if not watch_acted:
			errors.append("pass_watch_not_acted:%d" % seed)
		if not histories_differ:
			errors.append("organization_histories_equal:%d" % seed)
		rows.append({
			"seed": seed,
			"road_fellows_formed": road_formed,
			"pass_watch_formed": watch_formed,
			"pass_watch_acted": watch_acted,
			"histories_differ": histories_differ,
		})
	return {"rows": rows, "errors": errors}


func _household_ids(session: Variant) -> Array[String]:
	var rows: Array[String] = []
	var entities: Dictionary = session.stores["entity_store"].list_entities()
	for entity_id: String in entities.keys():
		var entity: Dictionary = entities[entity_id]
		if str(entity.get("type", "")) == "household":
			rows.append(entity_id)
	rows.sort()
	return rows


func _formation_observations(
	session: Variant, prototype_id: String
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for fact: Dictionary in _facts(
		session, "organization_lifecycle_signal_observed"
	):
		if (
			str(fact.get("prototype_id", "")) == prototype_id
			and str(fact.get("phase", "")) == "formation"
		):
			rows.append(fact)
	return rows


func _latest_observation(
	session: Variant, prototype_id: String, phase: String
) -> Dictionary:
	var latest: Dictionary = {}
	for fact: Dictionary in _facts(
		session, "organization_lifecycle_signal_observed"
	):
		if (
			str(fact.get("prototype_id", "")) != prototype_id
			or str(fact.get("phase", "")) != phase
		):
			continue
		if latest.is_empty() or int(fact.get("day", 0)) > int(
			latest.get("day", 0)
		):
			latest = fact
	return latest


func _formation_signal(session: Variant, organization_id: String) -> String:
	for fact: Dictionary in _organization_facts(
		session, "organization_runtime_formed", organization_id
	):
		return str(fact.get("signal_key", ""))
	return ""


func _organization_facts(
	session: Variant, fact_type: String, organization_id: String
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for fact: Dictionary in _facts(session, fact_type):
		if str(fact.get("organization_id", "")) == organization_id:
			rows.append(fact)
	return rows


func _history_rows(session: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for fact_type: String in [
		"organization_runtime_formed",
		"organization_effectiveness_evaluated",
		"organization_goal_changed",
		"organization_trade_coordinated",
		"organization_route_patrolled",
		"organization_runtime_retired",
	]:
		for fact: Dictionary in _facts(session, fact_type):
			if "runtime_organization" not in str(fact.get(
				"organization_id", ""
			)):
				continue
			rows.append({
				"fact_type": fact_type,
				"organization_id": str(fact.get("organization_id", "")),
				"signal_key": str(fact.get("signal_key", "")),
				"day": int(fact.get("day", 0)),
				"ineffective_streak": int(fact.get(
					"ineffective_streak", 0
				)),
				"source_fact_ids": (
					fact.get("source_fact_ids", []) as Array
				).duplicate(),
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	return rows


func _has_retirement_summary(
		session: Variant, organization_id: String, expected_text: String
) -> bool:
	for fact: Dictionary in _organization_facts(
		session, "organization_runtime_retired", organization_id
	):
		if expected_text in str(fact.get("summary", "")):
			return true
	return false


func _history_signature(session: Variant) -> String:
	return JSON.stringify(_history_rows(session))


func _entity(session: Variant, entity_id: String) -> Dictionary:
	if session == null:
		return {}
	return session.stores["entity_store"].get_entity(entity_id)


func _facts(session: Variant, fact_type: String) -> Array:
	if session == null:
		return []
	return session.stores["fact_store"].find_facts_by_type(fact_type)


func _safe_id(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace(":", "_").replace(".", "_")


func _finish() -> void:
	if failures.is_empty():
		print("[V5 MULTI SIGNAL ORGANIZATION LIFECYCLE CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 MULTI SIGNAL ORGANIZATION LIFECYCLE CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 MULTI SIGNAL ORGANIZATION LIFECYCLE CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 MULTI SIGNAL ORGANIZATION LIFECYCLE CONTRACT FAIL] %s" % label)
