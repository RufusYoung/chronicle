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
const YEAR_PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_year_close.json"
)
const SECOND_YEAR_FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_second_year_reception_fixture.json"
)
const SECOND_YEAR_PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_second_year_reception.json"
)
const YEAR_FIXTURE_ID := "seventh_outpost_first_year_close"
const SECOND_YEAR_FIXTURE_ID := "seventh_outpost_second_year_reception"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var patrol_year: Variant = _second_year_after([
		"month_patrol_fog_line", "month_patrol_fog_line",
		"month_patrol_fog_line", "month_patrol_fog_line",
		"month_patrol_fog_line", "month_patrol_fog_line",
		"month_patrol_fog_line", "month_patrol_fog_line",
		"month_patrol_fog_line",
	])
	_check(
		patrol_year != null
		and patrol_year.is_ready()
		and int(patrol_year.session.current_day) == 365,
		"1. A resolved first year enters the shared second-year fixture on day 365"
	)
	if patrol_year == null or not patrol_year.is_ready():
		_finish()
		return
	var patrol_options := _option_availability(patrol_year)
	_check(
		bool(patrol_options.get("second_year_take_regular_watch", false))
		and bool(patrol_options.get("second_year_lead_elai_fog_watch", false))
		and not bool(patrol_options.get("second_year_hold_east_wall_round", false))
		and not bool(patrol_options.get("second_year_assign_relief_pairs", false)),
		"2. A patrol year unlocks only the regular and Elai watchmate duties"
	)
	_check(
		str(patrol_year.get_ritual().get("body", "")).contains("伊莱"),
		"3. The second-year roll call reads Elai's persisted watchmate role"
	)
	var patrol_result: Dictionary = patrol_year.execute_duty(
		"second_year_lead_elai_fog_watch"
	)
	_check(
		bool(patrol_result.get("success", false))
		and _narratives_contain(patrol_result, "伊莱先一步复查了雾线")
		and _has_fact_outcome(patrol_year, "elai_watchmate"),
		"4. Elai autonomously prechecks the fog line after the player duty settles"
	)

	var wall_year: Variant = _second_year_after([
		"month_maintain_wall", "month_maintain_wall", "month_maintain_wall",
		"month_patrol_fog_line", "month_patrol_fog_line",
		"month_patrol_fog_line", "month_patrol_fog_line",
		"month_patrol_fog_line", "month_patrol_fog_line",
	])
	var wall_options := _option_availability(wall_year)
	_check(
		wall_year != null
		and bool(wall_options.get("second_year_hold_east_wall_round", false))
		and _has_fact_outcome(wall_year, "hoke_relinquishes_wall_round"),
		"5. Repeated wall work unlocks the owned east-wall duty through year-end facts"
	)
	if wall_year == null:
		_finish()
		return
	var wall_result: Dictionary = wall_year.execute_duty(
		"second_year_hold_east_wall_round"
	)
	_check(
		bool(wall_result.get("success", false))
		and _narratives_contain(wall_result, "霍克留在庭院改墙巡簿"),
		"6. Hoke records the wall round instead of silently taking it back"
	)

	var roster_year: Variant = _second_year_after([
		"month_preserve_rations", "month_preserve_rations",
		"month_preserve_rations", "month_preserve_rations",
		"month_preserve_rations", "month_preserve_rations",
		"month_preserve_rations", "month_preserve_rations",
		"month_preserve_rations",
	])
	var roster_options := _option_availability(roster_year)
	_check(
		roster_year != null
		and bool(roster_options.get("second_year_assign_relief_pairs", false))
		and not bool(roster_options.get("second_year_lead_elai_fog_watch", false)),
		"7. A ration year unlocks relief-pair organization without inventing Elai's role"
	)
	var roster_result: Dictionary = roster_year.execute_duty(
		"second_year_assign_relief_pairs"
	)
	_check(
		bool(roster_result.get("success", false))
		and _narratives_contain(roster_result, "罗恩按替岗记号分了三组人"),
		"8. Ron independently uses the institutionalized relief-pair record"
	)
	for unused: int in range(2):
		roster_year.execute_duty("second_year_assign_relief_pairs")
	var saved: Dictionary = roster_year.build_save_envelope({
		"save_id": "save.test.second_year_reception",
		"source_kind": "player_save",
	})
	var restored = ControllerModel.new()
	var restore_report: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(saved))
	)
	_check(
		roster_year.is_complete()
		and int(roster_year.session.current_day) == 386
		and bool(restore_report.get("success", false))
		and restored.is_complete()
		and _has_fact_outcome(restored, "roll_call_support_web"),
		"9. Three weekly nodes reach day 386 and save reload retains cross-year history"
	)
	_finish()


func _second_year_after(year_duties: Array[String]) -> Variant:
	var quarter = ControllerModel.new()
	if not bool(quarter.start(
		QUARTER_FIXTURE, QUARTER_PROJECT
	).get("success", false)):
		return null
	for unused: int in range(6):
		if not bool(quarter.execute_duty(
			"survey_thaw_routes", {"incident_roll_override": 100}
		).get("success", false)):
			return null
	var year_transition: Dictionary = quarter.build_life_stage_transition(
		YEAR_FIXTURE_ID
	)
	var year = ControllerModel.new()
	if not bool(year.start(YEAR_FIXTURE, YEAR_PROJECT).get("success", false)):
		return null
	if not bool(TransitionServiceModel.new().apply_to_controller(
		year, year_transition
	).get("success", false)):
		return null
	for duty_id: String in year_duties:
		var duty_result: Dictionary = year.execute_duty(
			duty_id, {"incident_roll_override": 100}
		)
		if not bool(duty_result.get("success", false)):
			print("[V5 SECOND YEAR ROUTE DEBUG] duty=%s result=%s" % [
				duty_id, JSON.stringify(duty_result)
			])
			return null
	var milestone_result: Dictionary = year.resolve_milestone()
	if not bool(milestone_result.get("success", false)):
		print("[V5 SECOND YEAR ROUTE DEBUG] milestone=%s" % JSON.stringify(
			milestone_result
		))
		return null
	var second_year_transition: Dictionary = year.build_life_stage_transition(
		SECOND_YEAR_FIXTURE_ID
	)
	var second_year = ControllerModel.new()
	if not bool(second_year.start(
		SECOND_YEAR_FIXTURE, SECOND_YEAR_PROJECT
	).get("success", false)):
		return null
	var applied: Dictionary = TransitionServiceModel.new().apply_to_controller(
		second_year, second_year_transition
	)
	return second_year if bool(applied.get("success", false)) else null


func _option_availability(controller: Variant) -> Dictionary:
	var rows := {}
	if controller == null:
		return rows
	for option: Dictionary in controller.get_duty_options():
		rows[str(option.get("duty_id", ""))] = bool(
			option.get("can_execute", false)
		)
	return rows


func _narratives_contain(result: Dictionary, needle: String) -> bool:
	for narrative: Variant in result.get("npc_narratives", []):
		if str(narrative).contains(needle):
			return true
	return false


func _has_fact_outcome(controller: Variant, outcome_id: String) -> bool:
	for fact: Dictionary in controller.session.stores[
		"fact_store"
	].find_facts_by_type("life_project_milestone_resolved"):
		if outcome_id in (fact.get("outcome_ids", []) as Array):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SECOND YEAR RECEPTION PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SECOND YEAR RECEPTION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 SECOND YEAR RECEPTION FAIL] " + failure)
	print("[V5 SECOND YEAR RECEPTION RESULT] FAIL (%d)" % failures.size())
	quit(1)
