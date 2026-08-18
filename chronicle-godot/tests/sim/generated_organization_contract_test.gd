extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const SaveEnvelopeServiceModel = preload(
	"res://scripts/sim/save/save_envelope_service.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/generated_organization_contract.save.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline = _start_from_path(81001)
	_check(
		baseline != null and baseline.is_ready(),
		"1. G4-A 网络夹具通过正式 SimSession 生成并启动"
	)
	if baseline == null or not baseline.is_ready():
		_finish()
		return
	var report: Dictionary = baseline.organization_generation_report
	var organizations := _organizations(baseline)
	_check(
		int(report.get("organization_count", 0)) == 3
		and organizations.size() == 3
		and bool((report.get("integrity", {}) as Dictionary).get("ok", false)),
		"2. 三个聚落各生成一个正式组织并通过生成期完整性校验"
	)
	_check(
		_organization_positions_are_real(baseline, organizations),
		"3. 每个职位由同聚落真实成年人担任，成员不会被重复分配"
	)
	_check(
		_organization_resources_are_real(baseline, organizations),
		"4. 组织可访问的物资全部指向本地真实资源库存"
	)
	_check(
		_organization_sources_are_complete(baseline, organizations),
		"5. 组织、职位、关系与 Chronicle 均能追溯到生成事实"
	)
	var kinds := _organization_kinds(organizations)
	_check(
		kinds.size() >= 2
		and _organization_kind_at(
			organizations, "generated_settlement.wind_pass"
		) == "local_watch",
		"6. 产业、道路与地形需求形成不同组织，防御高地生成守路队"
	)

	var repeated = _start_from_path(81001)
	_check(
		repeated != null
		and str(repeated.organization_generation_report.get("signature", ""))
		== str(report.get("signature", ""))
		and _organization_store_signature(repeated)
		== _organization_store_signature(baseline),
		"7. 同一世界种子完全复现组织种类、职位成员与资源链接"
	)

	var counterfactual = _start_without_defensible_pass(81001)
	var counterfactual_organizations := _organizations(counterfactual)
	_check(
		counterfactual != null
		and _organization_kind_at(
			counterfactual_organizations, "generated_settlement.wind_pass"
		) != "local_watch"
		and not _has_kind(counterfactual_organizations, "local_watch"),
		"8. 移除防御地形与道路风险后不再生成守路队，而非固定写死组织"
	)

	var save_before: Dictionary = baseline.get_save_store_data()
	var save_report: Dictionary = baseline.save_to_path(SAVE_PATH, {
		"save_id": "save.test.generated_organization",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-18T12:00:00Z",
		"saved_at_utc": "2026-08-18T12:30:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	var restore_succeeded := bool(restore_report.get("success", false))
	var save_roundtrip_equal := restore_succeeded and _equivalent(
		save_before, restored.get_save_store_data()
	)
	var generation_report_restored := (
		restore_succeeded
		and str(restored.organization_generation_report.get("signature", ""))
		== str(report.get("signature", ""))
	)
	var reference_report: Dictionary = (
		restored.validate_persistent_references()
		if restore_succeeded
		else {"ok": false, "error": "restore_failed"}
	)
	var restored_references_valid := bool(reference_report.get("ok", false))
	if (
		not bool(save_report.get("ok", false))
		or not bool(restore_report.get("success", false))
		or not save_roundtrip_equal
		or not generation_report_restored
		or not restored_references_valid
	):
		print("[V5 GENERATED ORGANIZATION SAVE DIAGNOSTIC] %s" % JSON.stringify({
			"save_ok": save_report.get("ok", false),
			"restore_error": restore_report.get("error", ""),
			"store_equal": save_roundtrip_equal,
			"generation_report_restored": generation_report_restored,
			"references": reference_report,
			"hash": _save_hash_diagnostic(
				save_report.get("envelope", {}), SAVE_PATH
			),
		}))
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and save_roundtrip_equal
		and generation_report_restored
		and restored_references_valid,
		"9. 磁盘存档往返保留组织、职位、关系、物资链接与生成摘要"
	)

	var migration_session = _start_with_isolated_network(81001)
	for _hour: int in range(60):
		migration_session.advance_time(1, "generated_organization_migration")
	_check(
		_position_vacancies_follow_migration(migration_session),
		"10. 创始成员迁出时清空当前任职并留下职位离任事实，组织不保留伪现任成员"
	)

	var invalid_fixture := _load_fixture()
	(invalid_fixture["organization_generation"] as Dictionary)[
		"definition_path"
	] = "res://missing_organization_definition.json"
	var invalid = SimSessionModel.new()
	var invalid_start: Dictionary = invalid.start_from_fixture_data(
		invalid_fixture, RULE_PATHS
	)
	_check(
		not bool(invalid_start.get("success", false))
		and str(invalid_start.get("error", ""))
		== "organization_generation_failed"
		and str(invalid_start.get("generation_error", ""))
		== "organization_generation_definition_not_loaded",
		"11. 组织定义缺失时启动明确失败，不回退到无来源默认组织"
	)

	print("[V5 GENERATED ORGANIZATION SAMPLE] %s" % JSON.stringify({
		"organizations": report.get("organizations", []),
		"kinds": kinds.keys(),
	}))
	_finish()


func _start_from_path(seed: int) -> Variant:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": seed}
	)
	if not bool(start.get("success", false)):
		print("[V5 GENERATED ORGANIZATION START FAILURE] %s" % JSON.stringify(start))
		return null
	return session


func _start_without_defensible_pass(seed: int) -> Variant:
	var fixture := _load_fixture()
	fixture["challenge_seed"] = seed
	var network: Dictionary = fixture.get("settlement_network_generation", {})
	for site: Dictionary in network.get("sites", []):
		if str(site.get("site_id", "")) != "wind_pass":
			continue
		var terrain: Dictionary = site.get("terrain", {})
		var tags: Array = (terrain.get("tags", []) as Array).duplicate()
		tags.erase("defensible")
		terrain["tags"] = tags
		for traffic: Dictionary in site.get("traffic", []):
			traffic["risk"] = 0
	for link: Dictionary in network.get("links", []):
		if "wind_pass" in [
			str(link.get("site_a_id", "")), str(link.get("site_b_id", ""))
		]:
			link["risk"] = 0
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_data(fixture, RULE_PATHS)
	if not bool(start.get("success", false)):
		print("[V5 GENERATED ORGANIZATION COUNTERFACTUAL FAILURE] %s" % (
			JSON.stringify(start)
		))
		return null
	return session


func _start_with_isolated_network(seed: int) -> Variant:
	var session = _start_from_path(seed)
	if session == null:
		return null
	var runtime: Dictionary = session.get_settlement_network_summary()
	for link: Dictionary in runtime.get("links", []):
		link["capacity_per_day"] = 0.0
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)
	return session


func _load_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _organizations(session: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if session == null:
		return rows
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		if "generated_organization" in (entity.get("tags", []) as Array):
			rows.append(entity)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return rows


func _organization_positions_are_real(
		session: Variant,
		organizations: Array[Dictionary]
) -> bool:
	var assigned: Dictionary = {}
	for organization: Dictionary in organizations:
		var organization_id := str(organization.get("id", ""))
		var settlement_id := str(organization.get("settlement_id", ""))
		var member_ids: Array = organization.get("founding_member_ids", [])
		var positions: Array = organization.get("positions", [])
		if member_ids.size() < 2 or positions.size() != member_ids.size():
			return false
		for position: Dictionary in positions:
			var member_id := str(position.get("founding_holder_id", ""))
			if assigned.has(member_id):
				return false
			assigned[member_id] = organization_id
			if (
				session.stores["entity_store"].get_entity(member_id).is_empty()
				or str(session.stores["state_store"].get_state(
					member_id, "settlement_id", ""
				)) != settlement_id
				or int(session.stores["state_store"].get_state(
					member_id, "age_years", 0
				)) < 18
				or str(session.stores["state_store"].get_state(
					member_id, "institution_role", ""
				)) != "%s::%s" % [
					organization_id, str(position.get("position_id", ""))
				]
			):
				return false
	return true


func _organization_resources_are_real(
		session: Variant,
		organizations: Array[Dictionary]
) -> bool:
	for organization: Dictionary in organizations:
		var settlement_id := str(organization.get("settlement_id", ""))
		var stock_ids: Array = organization.get("resource_stock_ids", [])
		if stock_ids.is_empty():
			return false
		for stock_value: Variant in stock_ids:
			var stock: Dictionary = session.stores[
				"resource_stock_store"
			].get_stock(str(stock_value))
			if (
				stock.is_empty()
				or str(stock.get("settlement_id", "")) != settlement_id
			):
				return false
	return true


func _organization_sources_are_complete(
		session: Variant,
		organizations: Array[Dictionary]
) -> bool:
	for organization: Dictionary in organizations:
		var organization_id := str(organization.get("id", ""))
		var source_fact_ids: Array = organization.get("source_fact_ids", [])
		if source_fact_ids.is_empty():
			return false
		for fact_id: Variant in source_fact_ids:
			if session.stores["fact_store"].get_fact(str(fact_id)).is_empty():
				return false
		for member_value: Variant in organization.get("founding_member_ids", []):
			var member_id := str(member_value)
			if (
				int(session.stores["relationship_store"].get_relation(
					organization_id, member_id, "familiarity", 0
				)) <= 0
				or int(session.stores["relationship_store"].get_relation(
					member_id, organization_id, "discipline_respect", 0
				)) <= 0
				or not _has_position_fact(session, organization_id, member_id)
			):
				return false
		if not _has_chronicle_subject(session, organization_id):
			return false
	return true


func _has_position_fact(
		session: Variant,
		organization_id: String,
		member_id: String
) -> bool:
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"organization_position_assigned"
	):
		if (
			str(fact.get("actor_id", "")) == organization_id
			and str(fact.get("target_id", "")) == member_id
			and not (fact.get("source_fact_ids", []) as Array).is_empty()
		):
			return true
	return false


func _has_chronicle_subject(session: Variant, subject_id: String) -> bool:
	for entry: Dictionary in session.stores["chronicle_store"].list_entries():
		if (
			str(entry.get("subject_id", "")) == subject_id
			and not (entry.get("source_fact_ids", []) as Array).is_empty()
		):
			return true
	return false


func _position_vacancies_follow_migration(session: Variant) -> bool:
	if session == null:
		return false
	var migrations: Array = session.stores["fact_store"].find_facts_by_type(
		"household_migrated"
	)
	var vacancies: Array = session.stores["fact_store"].find_facts_by_type(
		"organization_position_vacated"
	)
	if migrations.is_empty() or vacancies.is_empty():
		return false
	for vacancy: Dictionary in vacancies:
		var member_id := str(vacancy.get("target_id", ""))
		var organization_id := str(vacancy.get("organization_id", ""))
		var organization: Dictionary = session.stores[
			"entity_store"
		].get_entity(organization_id)
		var source_fact_ids: Array = vacancy.get("source_fact_ids", [])
		if (
			organization.is_empty()
			or member_id not in (
				organization.get("founding_member_ids", []) as Array
			)
			or str(session.stores["state_store"].get_state(
				member_id, "institution_role", ""
			)) != ""
			or str(session.stores["state_store"].get_state(
				member_id, "settlement_id", ""
			)) == str(organization.get("settlement_id", ""))
			or source_fact_ids.is_empty()
			or session.stores["fact_store"].get_fact(
				str(source_fact_ids[0])
			).is_empty()
		):
			return false
	return bool(session.validate_persistent_references().get("ok", false))


func _organization_kinds(organizations: Array[Dictionary]) -> Dictionary:
	var rows: Dictionary = {}
	for organization: Dictionary in organizations:
		rows[str(organization.get("organization_kind", ""))] = true
	return rows


func _organization_kind_at(
		organizations: Array[Dictionary],
		settlement_id: String
) -> String:
	for organization: Dictionary in organizations:
		if str(organization.get("settlement_id", "")) == settlement_id:
			return str(organization.get("organization_kind", ""))
	return ""


func _has_kind(organizations: Array[Dictionary], kind: String) -> bool:
	for organization: Dictionary in organizations:
		if str(organization.get("organization_kind", "")) == kind:
			return true
	return false


func _organization_store_signature(session: Variant) -> String:
	return JSON.stringify({
		"organizations": _organizations(session),
		"position_facts": session.stores["fact_store"].find_facts_by_type(
			"organization_position_assigned"
		),
		"relationships": session.stores["relationship_store"].to_save_data(),
	})


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


func _save_hash_diagnostic(memory_envelope: Variant, path: String) -> Dictionary:
	if not memory_envelope is Dictionary:
		return {"error": "memory_envelope_missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "disk_envelope_missing"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"error": "disk_envelope_invalid"}
	var memory_payload := (memory_envelope as Dictionary).duplicate(true)
	var disk_payload := (parsed as Dictionary).duplicate(true)
	var expected_hash := str((memory_payload.get(
		"integrity", {}
	) as Dictionary).get("payload_hash", ""))
	memory_payload.erase("integrity")
	disk_payload.erase("integrity")
	var service = SaveEnvelopeServiceModel.new()
	var memory_json: String = service._canonical_json(memory_payload)
	var disk_json: String = service._canonical_json(disk_payload)
	var difference_index := _first_string_difference(memory_json, disk_json)
	return {
		"expected": expected_hash,
		"memory": service._payload_hash(memory_payload),
		"disk": service._payload_hash(disk_payload),
		"memory_length": memory_json.length(),
		"disk_length": disk_json.length(),
		"difference_index": difference_index,
		"memory_excerpt": memory_json.substr(maxi(0, difference_index - 80), 180),
		"disk_excerpt": disk_json.substr(maxi(0, difference_index - 80), 180),
	}


func _first_string_difference(left: String, right: String) -> int:
	var limit := mini(left.length(), right.length())
	for index: int in range(limit):
		if left.unicode_at(index) != right.unicode_at(index):
			return index
	return limit


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GENERATED ORGANIZATION CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 GENERATED ORGANIZATION CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GENERATED ORGANIZATION CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 GENERATED ORGANIZATION CONTRACT FAIL] %s" % label)
