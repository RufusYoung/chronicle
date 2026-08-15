extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_settlement_network.save.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS
	)
	_check(bool(start.get("success", false)),
		"1. 三聚落网络通过正式 SimSession 生成并启动")
	if not bool(start.get("success", false)):
		print("[V5 SETTLEMENT NETWORK START FAILURE] %s" % JSON.stringify(start))
		_finish()
		return
	var settlement_report: Dictionary = start.get("settlement_generation", {})
	var resident_report: Dictionary = start.get("resident_generation", {})
	_check(
		int(settlement_report.get("site_count", 0)) == 3
		and int(settlement_report.get("link_count", 0)) == 2
		and int(resident_report.get("site_count", 0)) == 3,
		"2. 三个场址、两条区域连接和三批居民均由同一种子网络生成"
	)
	_check(
		_unique_ids(session.stores["entity_store"].list_entity_rows())
		and _all_routes_resolve(session),
		"3. 场址命名空间隔离居民与家庭 ID，全部道路端点引用真实地点"
	)
	var runtime: Dictionary = session.get_settlement_network_summary()
	_check(
		(runtime.get("sites", []) as Array).size() == 3
		and (runtime.get("links", []) as Array).size() == 2
		and _profiles_are_scoped(session.npc_livelihood_profiles),
		"4. 网络运行时保留场址和连接，同职业生计按所属聚落绑定库存"
	)
	var initial_stocks: Array = session.stores[
		"resource_stock_store"
	].list_stocks()
	_check(
		_count_source_kind(initial_stocks, "trade_reserve") == 9
		and _all_settlements_have_reserves(initial_stocks, runtime),
		"5. 每个聚落都生成三类可接收货物的真实贸易储备"
	)
	for _hour: int in range(72):
		session.advance_time(1, "network_contract")
	var trade_facts := _facts_of_type(session, "settlement_trade_shipment")
	_check(
		not trade_facts.is_empty()
		and _trade_facts_have_provenance(trade_facts),
		"6. 三日推进形成带两端库存、运力、数量和价格的跨聚落货流"
	)
	_check(
		bool(session.validate_persistent_references().get("ok", false))
		and _stocks_in_bounds(session.stores[
			"resource_stock_store"
		].list_stocks()),
		"7. 贸易后库存不透支、不超容，全部持久引用仍完整"
	)

	var isolated = SimSessionModel.new()
	var isolated_start: Dictionary = isolated.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS
	)
	var isolated_runtime: Dictionary = isolated.get_settlement_network_summary()
	for link: Dictionary in isolated_runtime.get("links", []):
		link["capacity_per_day"] = 0.0
	isolated.settlement_network_runtime = isolated_runtime.duplicate(true)
	isolated.world_tick_adapter.configure_settlement_network(isolated_runtime)
	for _hour: int in range(36):
		isolated.advance_time(1, "network_migration_counterfactual")
	var migration_facts := _facts_of_type(isolated, "household_migrated")
	_check(
		bool(isolated_start.get("success", false))
		and not migration_facts.is_empty(),
		"8. 保留道路但移除贸易容量后，连续短缺会促成真实家庭迁移"
	)
	var migration: Dictionary = (
		migration_facts[0] if not migration_facts.is_empty() else {}
	)
	_check(
		not migration.is_empty()
		and _migration_states_match(isolated, migration),
		"9. 迁移会同步改变整户聚落、住址、当前位置与工作状态，旧岗位不再生产"
	)
	var save_before := isolated.get_save_store_data()
	var save_report: Dictionary = isolated.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_settlement_network",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-15T08:00:00Z",
		"saved_at_utc": "2026-08-17T08:00:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_result: Dictionary = restored.load_from_path(SAVE_PATH)
	var save_matches := false
	if bool(restore_result.get("success", false)):
		save_matches = _equivalent(
			restored.get_save_store_data(), save_before
		)
	if not bool(restore_result.get("success", false)) or not save_matches:
		print("[V5 SETTLEMENT NETWORK RESTORE DIAGNOSTIC] %s" % JSON.stringify({
			"restore_result": restore_result,
			"save_matches": save_matches,
			"mismatch_keys": _save_mismatch_keys(
				save_before,
				restored.get_save_store_data() if restored.is_ready() else {}
			),
			"restored_migration_count": _facts_of_type(
				restored, "household_migrated"
			).size() if restored.is_ready() else -1,
		}))
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_result.get("success", false))
		and save_matches
		and not _facts_of_type(restored, "household_migrated").is_empty(),
		"10. 全精度磁盘存档保留三聚落网络、贸易水位与迁移后的居民真值"
	)
	var repeated = SimSessionModel.new()
	var repeated_start: Dictionary = repeated.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": 81001}
	)
	_check(
		bool(repeated_start.get("success", false))
		and str((repeated_start.get(
			"settlement_generation", {}
		) as Dictionary).get("signature", ""))
		== str(settlement_report.get("signature", "")),
		"11. 相同种子可复现完全一致的聚落网络生成签名"
	)
	_check(
		_multi_seed_networks_are_valid([81017, 81223, 81581]),
		"12. 三组不同种子均保持结构、人口、库存与货流约束"
	)
	_check(
		_invalid_networks_are_rejected(),
		"13. 重复道路或孤立场址会在生成阶段明确拒绝"
	)
	print("[V5 SETTLEMENT NETWORK SAMPLE] %s" % JSON.stringify({
		"settlements": settlement_report.get("sites", []),
		"residents": resident_report.get("resident_count", 0),
		"trade_count": trade_facts.size(),
		"trade_sample": trade_facts[0] if not trade_facts.is_empty() else {},
	}))
	_finish()


func _multi_seed_networks_are_valid(seeds: Array) -> bool:
	var signatures: Dictionary = {}
	for seed_value: Variant in seeds:
		var session = SimSessionModel.new()
		var start: Dictionary = session.start_from_fixture_path(
			FIXTURE_PATH,
			RULE_PATHS,
			{"challenge_seed_override": int(seed_value)}
		)
		if not bool(start.get("success", false)):
			return false
		var report: Dictionary = start.get("settlement_generation", {})
		var signature := str(report.get("signature", ""))
		if signature == "" or signatures.has(signature):
			return false
		signatures[signature] = true
		for _hour: int in range(24):
			session.advance_time(1, "network_multi_seed_contract")
		if (
			_facts_of_type(session, "settlement_trade_shipment").is_empty()
			or not _stocks_in_bounds(session.stores[
				"resource_stock_store"
			].list_stocks())
			or not bool(session.validate_persistent_references().get("ok", false))
			or not _populations_fit_capacity(session)
		):
			return false
	return signatures.size() == seeds.size()


func _invalid_networks_are_rejected() -> bool:
	var duplicate_fixture := _read_json(FIXTURE_PATH)
	var duplicate_config: Dictionary = duplicate_fixture.get(
		"settlement_network_generation", {}
	)
	var duplicate_links: Array = duplicate_config.get("links", [])
	duplicate_links.append((duplicate_links[0] as Dictionary).duplicate(true))
	duplicate_config["links"] = duplicate_links
	duplicate_fixture["settlement_network_generation"] = duplicate_config
	var duplicate_start: Dictionary = SimSessionModel.new().start_from_fixture_data(
		duplicate_fixture, RULE_PATHS
	)

	var disconnected_fixture := _read_json(FIXTURE_PATH)
	var disconnected_config: Dictionary = disconnected_fixture.get(
		"settlement_network_generation", {}
	)
	var disconnected_links: Array = disconnected_config.get("links", [])
	disconnected_config["links"] = [
		(disconnected_links[0] as Dictionary).duplicate(true)
	]
	disconnected_fixture["settlement_network_generation"] = disconnected_config
	var disconnected_start: Dictionary = SimSessionModel.new().start_from_fixture_data(
		disconnected_fixture, RULE_PATHS
	)
	return (
		not bool(duplicate_start.get("success", false))
		and "network_link_duplicate" in str(duplicate_start.get(
			"generation_error", ""
		))
		and not bool(disconnected_start.get("success", false))
		and str(disconnected_start.get(
			"generation_error", ""
		)) == "network_sites_not_connected"
	)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _populations_fit_capacity(session: Variant) -> bool:
	var counts: Dictionary = {}
	var entity_store: Variant = session.stores["entity_store"]
	var state_store: Variant = session.stores["state_store"]
	for person: Dictionary in entity_store.list_entity_rows():
		if str(person.get("type", "")) != "person":
			continue
		var settlement_id := str(state_store.get_state(
			str(person.get("id", "")), "settlement_id", ""
		))
		if settlement_id != "":
			counts[settlement_id] = int(counts.get(settlement_id, 0)) + 1
	for site: Dictionary in session.get_settlement_network_summary().get(
		"sites", []
	):
		if int(counts.get(str(site.get("settlement_id", "")), 0)) > int(
			site.get("resident_capacity", 0)
		):
			return false
	return true


func _unique_ids(entities: Array) -> bool:
	var seen: Dictionary = {}
	for entity: Dictionary in entities:
		var entity_id := str(entity.get("id", ""))
		if entity_id == "" or seen.has(entity_id):
			return false
		seen[entity_id] = true
	return true


func _all_routes_resolve(session: Variant) -> bool:
	for route: Dictionary in session.travel_routes:
		if (
			session.context.get_location(str(route.get("from_location_id", ""))).is_empty()
			or session.context.get_location(str(route.get("to_location_id", ""))).is_empty()
		):
			return false
	return true


func _profiles_are_scoped(profiles: Array) -> bool:
	var keys: Dictionary = {}
	for profile: Dictionary in profiles:
		var settlement_id := str(profile.get("settlement_id", ""))
		var occupation_id := str(profile.get("occupation_id", ""))
		if settlement_id == "" or occupation_id == "":
			return false
		var key := "%s::%s" % [settlement_id, occupation_id]
		if keys.has(key):
			return false
		keys[key] = true
	return not keys.is_empty()


func _count_source_kind(stocks: Array, source_kind: String) -> int:
	var count := 0
	for stock: Dictionary in stocks:
		if str(stock.get("source_kind", "")) == source_kind:
			count += 1
	return count


func _all_settlements_have_reserves(stocks: Array, runtime: Dictionary) -> bool:
	var counts: Dictionary = {}
	for stock: Dictionary in stocks:
		if str(stock.get("source_kind", "")) == "trade_reserve":
			var settlement_id := str(stock.get("settlement_id", ""))
			counts[settlement_id] = int(counts.get(settlement_id, 0)) + 1
	for site: Dictionary in runtime.get("sites", []):
		if int(counts.get(str(site.get("settlement_id", "")), 0)) != 3:
			return false
	return true


func _facts_of_type(session: Variant, fact_type: String) -> Array:
	var rows: Array = []
	for fact: Dictionary in session.stores["fact_store"].list_facts():
		if str(fact.get("fact_type", "")) == fact_type:
			rows.append(fact.duplicate(true))
	return rows


func _trade_facts_have_provenance(facts: Array) -> bool:
	for fact: Dictionary in facts:
		if (
			str(fact.get("source_settlement_id", "")) == ""
			or str(fact.get("destination_settlement_id", "")) == ""
			or str(fact.get("source_stock_id", "")) == ""
			or str(fact.get("destination_stock_id", "")) == ""
			or str(fact.get("transport_stock_id", "")) == ""
			or float(fact.get("amount", 0.0)) <= 0.0
			or float(fact.get("unit_price", 0.0)) <= 0.0
		):
			return false
	return true


func _migration_states_match(session: Variant, migration: Dictionary) -> bool:
	var destination_id := str(migration.get("destination_settlement_id", ""))
	var destination_location_id := str(migration.get(
		"destination_location_id", ""
	))
	var household_id := str(migration.get("household_id", ""))
	var snapshot: Variant = session.get_snapshot()
	if str(snapshot.get_entity_state(
		household_id, "location_id", ""
	)) != destination_location_id:
		return false
	for member_value: Variant in migration.get("member_ids", []):
		var member_id := str(member_value)
		if (
			str(snapshot.get_entity_state(member_id, "settlement_id", ""))
			!= destination_id
			or str(snapshot.get_entity_state(member_id, "location_id", ""))
			!= destination_location_id
			or str(snapshot.get_entity_state(member_id, "home_location_id", ""))
			!= destination_location_id
			or str(snapshot.get_entity_state(member_id, "workplace_id", ""))
			!= destination_location_id
		):
			return false
		var livelihood_status := str(snapshot.get_entity_state(
			member_id, "livelihood_status", ""
		))
		if livelihood_status in ["employed", "self_employed"]:
			return false
	return true


func _stocks_in_bounds(stocks: Array) -> bool:
	for stock: Dictionary in stocks:
		var current := float(stock.get("current", 0.0))
		var capacity := float(stock.get("capacity", 0.0))
		if current < -0.0001 or current > capacity + 0.0001:
			return false
	return true


func _save_mismatch_keys(left: Dictionary, right: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for value: Variant in left.keys():
		var key := str(value)
		if JSON.stringify(left.get(key), "", true, true) != JSON.stringify(
			right.get(key), "", true, true
		):
			keys.append(key)
	return keys


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
		print("[V5 SETTLEMENT NETWORK CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 SETTLEMENT NETWORK CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SETTLEMENT NETWORK CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 SETTLEMENT NETWORK CONTRACT FAIL] %s" % label)
