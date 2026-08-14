extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
)
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const GROUP_ID := "mist_salt_well_entry"
const CLAIMANT_ID := "mist_salt_well_claimant"
const BOAR_ID := "mist_salt_well_brine_boar"
const BOAR_NEGOTIATE := "combat:mist_salt_well_brine_boar:negotiate"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var default_session = SimSessionModel.new()
	var default_start: Dictionary = default_session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS
	)
	_check(
		bool(default_start.get("success", false))
		and int(default_start.get(
			"combat_encounter_definition_count", 0
		)) == 2,
		"1. 会话加载同一地点的两个正式遭遇候选"
	)
	var no_history_fixture := _fixture_data()
	no_history_fixture["location"] = _fixture_location(
		no_history_fixture, "mist_salt_well"
	)
	var no_history_session = SimSessionModel.new()
	var no_history_start: Dictionary = (
		no_history_session.start_from_fixture_data(
			no_history_fixture, RULE_PATHS
		)
	)
	var no_history_options: Array = (
		no_history_session.get_combat_encounter_options()
	)
	var no_history_report: Dictionary = (
		(no_history_session.get_combat_encounter_director_summary().get(
			"reports", {}
		) as Dictionary).get(GROUP_ID, {})
	)
	_check(
		bool(no_history_start.get("success", false))
		and no_history_options.is_empty()
		and int(no_history_report.get("eligible_candidate_count", -1)) == 0
		and _rejected_for_reason(
			no_history_report,
			CLAIMANT_ID,
			"missing_fact_type:lu_huai_recorded_departure_for_mist_salt_well"
		)
		and _rejected_for_reason(
			no_history_report,
			BOAR_ID,
			"missing_fact_type:lu_huai_recorded_departure_for_mist_salt_well"
		),
		"1a. 没有陆槐记录时即使身在旧井也不会凭空出现候选"
	)
	_check(
		_reach_well(default_session),
		"2. 默认种子沿正式调查和远行流程抵达旧井"
	)
	var default_options: Array = default_session.get_combat_encounter_options()
	var default_summary: Dictionary = (
		default_session.get_combat_encounter_director_summary()
	)
	var default_report: Dictionary = (
		default_summary.get("reports", {}) as Dictionary
	).get(GROUP_ID, {})
	_check(
		default_options.size() == 3
		and _all_encounter(default_options, CLAIMANT_ID)
		and int(default_report.get("candidate_count", 0)) == 2
		and int(default_report.get("eligible_candidate_count", 0)) == 2
		and str(default_report.get("selected_encounter_id", ""))
			== CLAIMANT_ID,
		"3. 种子 516 从两个合格候选中稳定选出盐雾拾荒客"
	)
	var repeated_options: Array = default_session.get_combat_encounter_options()
	_check(
		_all_encounter(repeated_options, CLAIMANT_ID)
		and str(default_session.combat_encounter_selections.get(
			GROUP_ID, ""
		)) == CLAIMANT_ID,
		"4. 界面反复刷新不会改抽另一个遭遇"
	)

	var envelope: Dictionary = default_session.build_save_envelope({
		"save_id": "save.test.combat_encounter_director",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-14T15:00:00Z",
		"saved_at_utc": "2026-08-14T15:01:00Z",
	})
	var restored = SimSessionModel.new()
	var restore: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(envelope))
	)
	var restored_options: Array = restored.get_combat_encounter_options()
	_check(
		bool(restore.get("success", false))
		and restored.combat_encounter_seed == 516
		and str(restored.combat_encounter_selections.get(GROUP_ID, ""))
			== CLAIMANT_ID
		and _all_encounter(restored_options, CLAIMANT_ID),
		"5. 未解决候选经过存档往返仍保持原选择"
	)

	var alternate_session = SimSessionModel.new()
	var alternate_start: Dictionary = alternate_session.start_from_fixture_path(
		FIXTURE_PATH,
		RULE_PATHS,
		{"challenge_seed_override": 517}
	)
	_check(
		bool(alternate_start.get("success", false))
		and _reach_well(alternate_session),
		"6. 相同世界内容可以用另一正式种子抵达同一地点"
	)
	var alternate_options: Array = (
		alternate_session.get_combat_encounter_options()
	)
	var alternate_preview: Dictionary = (
		(alternate_options[0] as Dictionary).get("preview", {})
		if not alternate_options.is_empty()
		else {}
	)
	_check(
		alternate_options.size() == 3
		and _all_encounter(alternate_options, BOAR_ID)
		and "charging" in (
			(alternate_preview.get(
				"enemy_observation", {}
			) as Dictionary).get("observable_tags", []) as Array
		),
		"7. 种子 517 选择盐壳獠豕并只暴露它的可观察特征"
	)

	var low_pressure_fixture := _fixture_data()
	(low_pressure_fixture.get("region_state", {}) as Dictionary)[
		"food_pressure"
	] = "stable"
	var pressure_session = SimSessionModel.new()
	var pressure_start: Dictionary = pressure_session.start_from_fixture_data(
		low_pressure_fixture, RULE_PATHS
	)
	_check(
		bool(pressure_start.get("success", false))
		and _reach_well(pressure_session),
		"8. 低粮压世界沿同一流程抵达旧井"
	)
	var pressure_options: Array = pressure_session.get_combat_encounter_options()
	var pressure_summary: Dictionary = (
		pressure_session.get_combat_encounter_director_summary()
	)
	var pressure_report: Dictionary = (
		pressure_summary.get("reports", {}) as Dictionary
	).get(GROUP_ID, {})
	_check(
		_all_encounter(pressure_options, BOAR_ID)
		and int(pressure_report.get("eligible_candidate_count", 0)) == 1
		and _rejected_for_reason(
			pressure_report,
			CLAIMANT_ID,
			"region_state_mismatch:food_pressure"
		),
		"9. 地区粮压不高时拾荒客被排除，只剩野兽候选"
	)

	var result: Dictionary = pressure_session.execute_combat_encounter_option(
		BOAR_NEGOTIATE,
		{"source": "test_injection", "roll_override": 3}
	)
	var resolved_fact := _resolved_fact(pressure_session)
	_check(
		bool(result.get("success", false))
		and str(result.get("outcome", "")) == "success"
		and str(resolved_fact.get("selection_group_id", "")) == GROUP_ID
		and pressure_session.get_combat_encounter_options().is_empty(),
		"10. 被选遭遇结算后消费整个独占组，不串出第二个候选"
	)
	var stale: Dictionary = pressure_session.execute_combat_encounter_option(
		"combat:mist_salt_well_claimant:negotiate"
	)
	_check(
		not bool(stale.get("success", true))
		and str(stale.get("error", ""))
			== "combat_encounter_option_not_found"
		and pressure_session.combat_encounter_count == 1,
		"11. 未被选择的候选不能在结算后补做或污染日志"
	)

	_finish()


func _fixture_data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		FIXTURE_PATH
	))
	return parsed if parsed is Dictionary else {}


func _fixture_location(fixture: Dictionary, location_id: String) -> Dictionary:
	for location_value: Variant in fixture.get("locations", []):
		if (
			location_value is Dictionary
			and str((location_value as Dictionary).get("id", ""))
				== location_id
		):
			return (location_value as Dictionary).duplicate(true)
	return {}


func _reach_well(session: Variant) -> bool:
	var results: Array[Dictionary] = [
		session.travel("old_chen_shop_to_abandoned_granary"),
		session.execute_challenge_option("prepare_granary_entry"),
		session.execute_challenge_option(
			"enter_abandoned_granary",
			{"source": "test_injection", "roll_override": 3}
		),
		session.travel("abandoned_granary_to_old_chen_shop"),
		session.execute_return_echo_option(
			"show_granary_measure_token_to_chen_mi"
		),
		session.execute_investigation_option(
			"investigate_public_granary_seal_records"
		),
		session.execute_action(
			"read_visible_readable_object:old_chen_public_granary_tax_deed"
		),
		session.advance_time(6, "wait_for_north_quay_ferry"),
		session.travel("old_chen_shop_to_north_quay_record_house"),
		session.execute_challenge_option("prepare_flooded_archive_search"),
		session.execute_challenge_option(
			"search_flooded_archive_stack",
			{"source": "test_injection", "roll_override": 1}
		),
		session.execute_challenge_option(
			"prepare_mist_salt_well_expedition"
		),
		session.travel("north_quay_record_house_to_mist_salt_well"),
	]
	for result: Dictionary in results:
		if not bool(result.get("success", false)):
			return false
	return str(session.context.location_id) == "mist_salt_well"


func _all_encounter(options: Array, encounter_id: String) -> bool:
	if options.is_empty():
		return false
	for option_value: Variant in options:
		if (
			not option_value is Dictionary
			or str((option_value as Dictionary).get("encounter_id", ""))
				!= encounter_id
		):
			return false
	return true


func _rejected_for_reason(
		report: Dictionary, encounter_id: String, reason: String
) -> bool:
	for rejected_value: Variant in report.get("rejected", []):
		if not rejected_value is Dictionary:
			continue
		var rejected := rejected_value as Dictionary
		if (
			str(rejected.get("encounter_id", "")) == encounter_id
			and reason in (rejected.get("reasons", []) as Array)
		):
			return true
	return false


func _resolved_fact(session: Variant) -> Dictionary:
	var facts: Array = session.stores["fact_store"].find_facts_by_type(
		"actor_resolved_combat_encounter"
	)
	return facts[0] if not facts.is_empty() else {}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 COMBAT ENCOUNTER DIRECTOR PASS] " + message)
	else:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 COMBAT ENCOUNTER DIRECTOR RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 COMBAT ENCOUNTER DIRECTOR FAIL] " + failure)
	print(
		"[V5 COMBAT ENCOUNTER DIRECTOR RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)
