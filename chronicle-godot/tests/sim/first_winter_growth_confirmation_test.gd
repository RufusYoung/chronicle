extends SceneTree

const ControllerModel = preload(
	"res://scripts/sim/life_project/life_project_controller.gd"
)
const FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_winter.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var incomplete = ControllerModel.new()
	incomplete.start(FIXTURE, PROJECT)
	var incomplete_before: Dictionary = incomplete.session.get_save_store_data()
	var incomplete_result: Dictionary = incomplete.confirm_growth_candidate(
		"growth.first_winter.fog_reader"
	)
	_check(
		not bool(incomplete_result.get("success", false))
		and str(incomplete_result.get("error", "")) == "project_not_complete"
		and _equivalent(
			incomplete.session.get_save_store_data(), incomplete_before
		),
		"1. Growth cannot be confirmed before the stage ends"
	)

	var patrol = _complete_patrol_route()
	var unavailable_before: Dictionary = patrol.session.get_save_store_data()
	var unavailable: Dictionary = patrol.confirm_growth_candidate(
		"growth.first_winter.fire_circle"
	)
	_check(
		not bool(unavailable.get("success", false))
		and str(unavailable.get("error", "")) == "growth_candidate_not_available"
		and _equivalent(
			patrol.session.get_save_store_data(), unavailable_before
		),
		"2. A reward outside the lived route is rejected without mutation"
	)

	var confirmed: Dictionary = patrol.confirm_growth_candidate(
		"growth.first_winter.fog_reader"
	)
	var feature_store: Variant = patrol.session.stores[
		"character_feature_store"
	]
	var growth_facts: Array = patrol.session.stores[
		"fact_store"
	].find_facts_by_type("life_project_growth_confirmed")
	_check(
		bool(confirmed.get("success", false))
		and int(patrol.session.stores["state_store"].get_state(
			"player", "perception", 0
		)) == 11
		and _has_talent(feature_store, "talent.fog_line_reader")
		and growth_facts.size() == 1
		and str((growth_facts[0] as Dictionary).get(
			"candidate_id", ""
		)) == "growth.first_winter.fog_reader"
		and patrol.session.stores["chronicle_store"].list_entries().size() == 2,
		"3. Confirmation atomically writes attribute, talent, fact, and Chronicle"
	)

	var confirmed_candidates: Array = patrol.get_growth_candidates()
	var confirmed_before: Dictionary = patrol.session.get_save_store_data()
	var repeated: Dictionary = patrol.confirm_growth_candidate(
		"growth.first_winter.fog_reader"
	)
	_check(
		confirmed_candidates.size() == 1
		and bool((confirmed_candidates[0] as Dictionary).get("confirmed", false))
		and not bool(repeated.get("success", false))
		and str(repeated.get("error", "")) == "growth_already_confirmed"
		and _equivalent(patrol.session.get_save_store_data(), confirmed_before),
		"4. The confirmed candidate remains visible but cannot be claimed twice"
	)

	var envelope: Dictionary = patrol.build_save_envelope({
		"save_id": "save.test.first_winter_growth",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-13T08:00:00Z",
		"saved_at_utc": "2026-08-13T08:01:00Z",
	})
	var restored = ControllerModel.new()
	var restore_report: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(envelope))
	)
	var restored_repeat: Dictionary = restored.confirm_growth_candidate(
		"growth.first_winter.fog_reader"
	)
	_check(
		bool(restore_report.get("success", false))
		and _has_talent(
			restored.session.stores["character_feature_store"],
			"talent.fog_line_reader"
		)
		and int(restored.session.stores["state_store"].get_state(
			"player", "perception", 0
		)) == 11
		and bool((restored.get_growth_candidates()[0] as Dictionary).get(
			"confirmed", false
		))
		and str(restored_repeat.get("error", "")) == "growth_already_confirmed",
		"5. Save restore preserves the reward and repeat protection"
	)

	var rollback = _complete_patrol_route()
	var rollback_rule := _growth_rule(
		rollback, "growth.first_winter.fog_reader"
	)
	(rollback_rule.get("reward", {}) as Dictionary)["talent_grants"] = [{
		"owner_entity_id": "player",
		"talent_def_id": "talent.steady_hands",
	}]
	var rollback_before: Dictionary = rollback.session.get_save_store_data()
	var rejected: Dictionary = rollback.confirm_growth_candidate(
		"growth.first_winter.fog_reader"
	)
	_check(
		not bool(rejected.get("success", false))
		and str(rejected.get("error", "")) == "growth_transaction_rejected"
		and _equivalent(rollback.session.get_save_store_data(), rollback_before),
		"6. A conflicting talent grant rolls back every preceding change"
	)
	_finish()


func _complete_patrol_route() -> Variant:
	var controller = ControllerModel.new()
	controller.start(FIXTURE, PROJECT)
	for day: int in range(7):
		controller.execute_duty(
			"patrol_fog_line", {"risk_roll_override": 10}
		)
	return controller


func _growth_rule(controller: Variant, candidate_id: String) -> Dictionary:
	for rule: Dictionary in controller.definition.get(
		"growth_candidate_rules", []
	):
		if str(rule.get("candidate_id", "")) == candidate_id:
			return rule
	return {}


func _has_talent(store: Variant, talent_def_id: String) -> bool:
	for assignment: Dictionary in store.list_talent_assignments("player"):
		if str(assignment.get("talent_def_id", "")) == talent_def_id:
			return true
	return false


func _equivalent(left: Variant, right: Variant) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GROWTH CONFIRMATION PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GROWTH CONFIRMATION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 GROWTH CONFIRMATION FAIL] " + failure)
	print("[V5 GROWTH CONFIRMATION RESULT] FAIL (%d)" % failures.size())
	quit(1)
