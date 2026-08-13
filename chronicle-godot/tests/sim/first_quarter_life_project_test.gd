extends SceneTree

const ControllerModel = preload(
	"res://scripts/sim/life_project/life_project_controller.gd"
)
const TransitionServiceModel = preload(
	"res://scripts/sim/save/life_stage_transition_service.gd"
)
const WINTER_FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const WINTER_PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_winter.json"
)
const QUARTER_FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_quarter_fixture.json"
)
const QUARTER_FIXTURE_ID := "seventh_outpost_first_quarter"
const QUARTER_PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_quarter.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fog_quarter: Variant = _quarter_after_winter(
		["patrol_fog_line", "patrol_fog_line", "patrol_fog_line",
		 "patrol_fog_line", "patrol_fog_line", "patrol_fog_line",
		 "patrol_fog_line"],
		"growth.first_winter.fog_reader"
	)
	_check(
		fog_quarter != null and fog_quarter.is_ready(),
		"1. Confirmed first winter enters the formal first quarter"
	)
	if fog_quarter == null or not fog_quarter.is_ready():
		_finish()
		return

	var fog_options: Array = fog_quarter.get_duty_options()
	_check(
		fog_quarter.get_calendar_days_per_step() == 14
		and fog_quarter.get_duration_days() == 6
		and _has_duty(fog_options, "read_thaw_tracks")
		and not _has_duty(fog_options, "lead_thaw_repair")
		and not _has_duty(fog_options, "redraw_watch_pairs"),
		"2. Quarter exposes only the echo duty earned by the winter route"
	)
	var start_world_day := int(fog_quarter.session.current_day)
	var start_tick_count := int(fog_quarter.session.world_tick_count)
	var start_lantern_history := (
		fog_quarter.session.stores["item_store"].get_item(
			"item_instance.seventh_outpost.player_patrol_lantern"
		).get("history", []) as Array
	).size()
	for step: int in range(6):
		var result: Dictionary = fog_quarter.execute_duty(
			"read_thaw_tracks", {"incident_roll_override": 100}
		)
		_check(
			bool(result.get("success", false)),
			"3.%d. Growth echo advances one quarter step" % (step + 1)
		)
	_check(
		fog_quarter.is_complete()
		and int(fog_quarter.session.current_day) == start_world_day + 84
		and int(fog_quarter.session.world_tick_count) == start_tick_count + 6
		and fog_quarter.day_history.size() == 6,
		"4. Six fortnight steps advance 84 calendar days with six bounded world settlements"
	)
	_check(
		str(fog_quarter.session.stores["state_store"].get_state(
			"recruit_elai", "fear", "medium"
		)) == "low"
		and int(fog_quarter.session.stores["state_store"].get_state(
			"seventh_outpost", "border_pressure", 12
		)) <= 2,
		"5. The winter skill changes both a fixed person and the outpost"
	)
	var lantern_history: Array = fog_quarter.session.stores[
		"item_store"
	].get_item(
		"item_instance.seventh_outpost.player_patrol_lantern"
	).get("history", [])
	_check(
		lantern_history.size() == start_lantern_history + 6
		and _fact_count(
			fog_quarter, "actor_mapped_thaw_tracks"
		) == 6
		and _quarter_settlement_days(fog_quarter) == [14, 14, 14, 14, 14, 14],
		"6. Each quarter echo leaves facts, item history, and calendar evidence"
	)
	_check(
		fog_quarter.session.stores["memory_store"].list_memories(
			"player"
		).size() == 13
		and fog_quarter.session.stores["chronicle_store"].list_entries_for_subject(
			"player"
		).size() == 3
		and "读迹方法已被写进北坡巡查图" in _completion_text(fog_quarter),
		"7. Winter and quarter memories resolve into a state-backed Chronicle summary"
	)
	var save_envelope: Dictionary = fog_quarter.build_save_envelope({
		"save_id": "save.test.first_quarter",
		"source_kind": "player_save",
	})
	var restored_quarter = ControllerModel.new()
	var restore_report: Dictionary = restored_quarter.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(save_envelope))
	)
	var restarted_quarter = ControllerModel.new()
	var restart_report: Dictionary = restarted_quarter.start(
		QUARTER_FIXTURE, QUARTER_PROJECT
	)
	var restart_transition_report: Dictionary = (
		TransitionServiceModel.new().apply_to_controller(
			restarted_quarter, restored_quarter.get_entry_transition()
		)
	)
	_check(
		bool(restore_report.get("success", false))
		and bool(restart_report.get("success", false))
		and bool(restart_transition_report.get("success", false))
		and _has_duty(
			restarted_quarter.get_duty_options(), "read_thaw_tracks"
		)
		and int(restarted_quarter.session.stores["item_store"].get_item(
			"item_instance.seventh_outpost.wall_timber"
		).get("quantity", -1)) == _transition_item_quantity(
			fog_quarter.get_entry_transition(),
			"item_instance.seventh_outpost.wall_timber"
		),
		"7a. Save restore retains the original quarter-entry snapshot for a truthful restart"
	)

	var worker_quarter: Variant = _quarter_after_winter(
		["repair_east_wall", "repair_east_wall", "repair_east_wall",
		 "rest_in_infirmary", "audit_rations_with_marta",
		 "drill_with_elai", "drill_with_elai"],
		"growth.first_winter.steady_worker"
	)
	var worker_options: Array = worker_quarter.get_duty_options()
	var hoke_before := int(worker_quarter.session.stores[
		"state_store"
	].get_state("veteran_hoke", "fatigue", 0))
	var worker_result: Dictionary = worker_quarter.execute_duty(
		"lead_thaw_repair", {"incident_roll_override": 100}
	)
	_check(
		_has_duty(worker_options, "lead_thaw_repair")
		and not _has_duty(worker_options, "read_thaw_tracks")
		and bool(worker_result.get("success", false))
		and int(worker_quarter.session.stores["state_store"].get_state(
			"veteran_hoke", "fatigue", 0
		)) < hoke_before,
		"8. Steady-worker growth unlocks a material-saving duty and relieves Hoke"
	)

	var fire_quarter: Variant = _quarter_after_winter(
		["drill_with_elai", "drill_with_elai", "drill_with_elai",
		 "drill_with_elai", "drill_with_elai", "drill_with_elai",
		 "drill_with_elai"],
		"growth.first_winter.fire_circle"
	)
	var fire_options: Array = fire_quarter.get_duty_options()
	var morale_before := int(fire_quarter.session.stores[
		"state_store"
	].get_state("seventh_outpost", "morale", 0))
	var fire_result: Dictionary = fire_quarter.execute_duty(
		"redraw_watch_pairs", {"incident_roll_override": 100}
	)
	_check(
		_has_duty(fire_options, "redraw_watch_pairs")
		and not _has_duty(fire_options, "read_thaw_tracks")
		and bool(fire_result.get("success", false))
		and int(fire_quarter.session.stores["state_store"].get_state(
			"seventh_outpost", "morale", 0
		)) >= morale_before
		and str(fire_quarter.session.stores["state_store"].get_state(
			"recruit_elai", "fear", "medium"
		)) == "low",
		"9. Fire-circle growth turns belonging into a formal watch-roster consequence"
	)
	_finish()


func _quarter_after_winter(
		sequence: Array[String], candidate_id: String
) -> Variant:
	var source = ControllerModel.new()
	if not bool(source.start(WINTER_FIXTURE, WINTER_PROJECT).get(
		"success", false
	)):
		return null
	for duty_id: String in sequence:
		var chosen_id := duty_id
		if not _duty_can_execute(source.get_duty_options(), chosen_id):
			chosen_id = "drill_with_elai"
		var duty_result: Dictionary = source.execute_duty(
			chosen_id, {"risk_roll_override": 10}
		)
		if not bool(duty_result.get("success", false)):
			return null
	var growth: Dictionary = source.confirm_growth_candidate(candidate_id)
	if not bool(growth.get("success", false)):
		return null
	var transition: Dictionary = source.build_life_stage_transition(
		QUARTER_FIXTURE_ID
	)
	var target = ControllerModel.new()
	if not bool(target.start(QUARTER_FIXTURE, QUARTER_PROJECT).get(
		"success", false
	)):
		return null
	var applied: Dictionary = TransitionServiceModel.new().apply_to_controller(
		target, transition
	)
	return target if bool(applied.get("success", false)) else null


func _has_duty(options: Array, duty_id: String) -> bool:
	for option: Dictionary in options:
		if str(option.get("duty_id", "")) == duty_id:
			return true
	return false


func _duty_can_execute(options: Array, duty_id: String) -> bool:
	for option: Dictionary in options:
		if str(option.get("duty_id", "")) == duty_id:
			return bool(option.get("can_execute", false))
	return false


func _fact_count(controller: Variant, fact_type: String) -> int:
	return controller.session.stores["fact_store"].find_facts_by_type(
		fact_type
	).size()


func _quarter_settlement_days(controller: Variant) -> Array:
	var rows: Array = []
	for fact: Dictionary in controller.session.stores[
		"fact_store"
	].find_facts_by_type("life_project_day_settled"):
		if str(fact.get("project_id", "")) == "seventh_outpost_first_quarter":
			rows.append(int(fact.get("calendar_days", 0)))
	return rows


func _transition_item_quantity(
		transition: Dictionary, item_instance_id: String
) -> int:
	for item: Dictionary in transition.get("items", []):
		if str(item.get("item_instance_id", "")) == item_instance_id:
			return int(item.get("quantity", -2))
	return -2


func _completion_text(controller: Variant) -> String:
	return "\n".join(controller.get_completion_summary().get("lines", []))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 FIRST QUARTER PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 FIRST QUARTER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 FIRST QUARTER FAIL] " + failure)
	print("[V5 FIRST QUARTER RESULT] FAIL (%d)" % failures.size())
	quit(1)
