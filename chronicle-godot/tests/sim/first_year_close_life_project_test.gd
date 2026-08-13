extends SceneTree

const ControllerModel = preload(
	"res://scripts/sim/life_project/life_project_controller.gd"
)
const TransitionServiceModel = preload(
	"res://scripts/sim/save/life_stage_transition_service.gd"
)
const QUARTER_FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_quarter_fixture.json"
)
const QUARTER_PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_quarter.json"
)
const YEAR_FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_year_close_fixture.json"
)
const YEAR_FIXTURE_ID := "seventh_outpost_first_year_close"
const YEAR_PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_year_close.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var patrol_year: Variant = _year_after_quarter()
	_check(
		patrol_year != null and patrol_year.is_ready(),
		"1. A completed first quarter enters the first-year monthly phase"
	)
	if patrol_year == null or not patrol_year.is_ready():
		_finish()
		return

	_check(
		patrol_year.get_duration_days() == 9
		and patrol_year.get_calendar_days_for_step(1) == 30
		and patrol_year.get_calendar_days_for_step(9) == 33,
		"2. The annual phase declares eight 30-day months and a 33-day final month"
	)
	var start_world_day := int(patrol_year.session.current_day)
	for step: int in range(9):
		var result: Dictionary = patrol_year.execute_duty(
			"month_patrol_fog_line", {"incident_roll_override": 100}
		)
		_check(
			bool(result.get("success", false)),
			"3.%d. Monthly patrol resolves through the life-project transaction" % (step + 1)
		)
	_check(
		patrol_year.is_complete()
		and int(patrol_year.session.current_day) == start_world_day + 273
		and int(patrol_year.session.current_day) == 365
		and _settlement_days(patrol_year) == [30, 30, 30, 30, 30, 30, 30, 30, 33],
		"4. Nine monthly choices advance the world from day 92 to day 365"
	)

	var patrol_milestone: Dictionary = patrol_year.get_milestone_summary()
	var patrol_outcome_ids := _outcome_ids(patrol_milestone)
	_check(
		"first_year_regular" in patrol_outcome_ids
		and "elai_watchmate" in patrol_outcome_ids
		and "hoke_relinquishes_wall_round" not in patrol_outcome_ids
		and "roll_call_support_web" not in patrol_outcome_ids,
		"5. Repeated patrol creates Elai's annual change without inventing unrelated outcomes"
	)
	var patrol_resolution: Dictionary = patrol_year.resolve_milestone()
	var duplicate_resolution: Dictionary = patrol_year.resolve_milestone()
	_check(
		bool(patrol_resolution.get("success", false))
		and not bool(duplicate_resolution.get("success", false))
		and str(duplicate_resolution.get("error", "")) == "project_milestone_already_resolved"
		and str(patrol_year.session.stores["state_store"].get_state(
			"player", "institution_role", ""
		)) == "outpost_regular"
		and str(patrol_year.session.stores["state_store"].get_state(
			"recruit_elai", "institution_role", ""
		)) == "watchmate",
		"6. Annual changes commit once and change the actual character states"
	)
	_check(
		patrol_year.session.stores["fact_store"].find_facts_by_type(
			"life_project_milestone_resolved"
		).size() == 1
		and _has_chronicle_entry(
			patrol_year, "seventh_outpost_first_year_close:milestone"
		),
		"7. Year-end resolution leaves one fact and one Chronicle entry"
	)

	var saved: Dictionary = patrol_year.build_save_envelope({
		"save_id": "save.test.first_year_close",
		"source_kind": "player_save",
	})
	var restored = ControllerModel.new()
	var restore_report: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(saved))
	)
	_check(
		bool(restore_report.get("success", false))
		and bool(restored.get_milestone_summary().get("resolved", false))
		and str(restored.session.stores["state_store"].get_state(
			"recruit_elai", "institution_role", ""
		)) == "watchmate",
		"8. Save reload retains the resolved annual state without a second reward"
	)

	var ration_year: Variant = _year_after_quarter()
	for unused: int in range(9):
		ration_year.execute_duty(
			"month_preserve_rations", {"incident_roll_override": 100}
		)
	var ration_ids := _outcome_ids(ration_year.get_milestone_summary())
	_check(
		"first_year_regular" in ration_ids
		and "roll_call_support_web" in ration_ids
		and "elai_watchmate" not in ration_ids,
		"9. A ration-centered year produces a different state-backed annual history"
	)
	_finish()


func _year_after_quarter() -> Variant:
	var quarter = ControllerModel.new()
	if not bool(quarter.start(QUARTER_FIXTURE, QUARTER_PROJECT).get(
		"success", false
	)):
		return null
	for unused: int in range(6):
		var result: Dictionary = quarter.execute_duty(
			"survey_thaw_routes", {"incident_roll_override": 100}
		)
		if not bool(result.get("success", false)):
			return null
	var transition: Dictionary = quarter.build_life_stage_transition(
		YEAR_FIXTURE_ID
	)
	if transition.is_empty():
		return null
	var year = ControllerModel.new()
	if not bool(year.start(YEAR_FIXTURE, YEAR_PROJECT).get("success", false)):
		return null
	var applied: Dictionary = TransitionServiceModel.new().apply_to_controller(
		year, transition
	)
	return year if bool(applied.get("success", false)) else null


func _settlement_days(controller: Variant) -> Array:
	var rows: Array = []
	for fact: Dictionary in controller.session.stores[
		"fact_store"
	].find_facts_by_type("life_project_day_settled"):
		if str(fact.get("project_id", "")) == "seventh_outpost_first_year_close":
			rows.append(int(fact.get("calendar_days", 0)))
	return rows


func _outcome_ids(summary: Dictionary) -> Array[String]:
	var rows: Array[String] = []
	for outcome: Dictionary in summary.get("outcomes", []):
		rows.append(str(outcome.get("outcome_id", "")))
	return rows


func _has_chronicle_entry(controller: Variant, entry_id: String) -> bool:
	for entry: Dictionary in controller.session.stores[
		"chronicle_store"
	].list_entries_for_subject("player"):
		if str(entry.get("entry_id", "")) == entry_id:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 FIRST YEAR CLOSE PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 FIRST YEAR CLOSE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 FIRST YEAR CLOSE FAIL] " + failure)
	print("[V5 FIRST YEAR CLOSE RESULT] FAIL (%d)" % failures.size())
	quit(1)
