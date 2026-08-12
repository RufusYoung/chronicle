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
	var patrol = ControllerModel.new()
	var start: Dictionary = patrol.start(FIXTURE, PROJECT)
	_check(
		bool(start.get("success", false))
		and patrol.get_day() == 1
		and patrol.get_duration_days() == 7,
		"1. First winter starts as a seven-day life project"
	)

	var initial_options: Array = patrol.get_duty_options()
	_check(
		_has_duty(initial_options, "patrol_fog_line")
		and _has_duty(initial_options, "drill_with_elai")
		and not _has_duty(initial_options, "rest_in_infirmary"),
		"2. Duties come from current state instead of a fixed day script"
	)

	patrol.session.stores["state_store"].set_state(
		"player", "perception", 7
	)
	var blocked_option := _find_duty(
		patrol.get_duty_options(), "patrol_fog_line"
	)
	var blocked_result: Dictionary = patrol.execute_duty(
		"patrol_fog_line"
	)
	_check(
		not bool(blocked_option.get("can_execute", true))
		and "感知不足" in str(blocked_option.get("blocked_reason", ""))
		and str(blocked_result.get("error", "")) == "duty_blocked"
		and patrol.get_day() == 1,
		"3. Attribute-gated duty explains failure and cannot advance the day"
	)
	patrol.session.stores["state_store"].set_state(
		"player", "perception", 10
	)

	var patrol_npc_reactions := 0
	for day: int in range(7):
		var result: Dictionary = patrol.execute_duty("patrol_fog_line")
		_check(
			bool(result.get("success", false)),
			"4.%d. Patrol path advances service day %d" % [day + 1, day + 1]
		)
		patrol_npc_reactions += (
			result.get("npc_narratives", []) as Array
		).size()
	_check(
		patrol.is_complete()
		and patrol.day_history.size() == 7
		and patrol.get_day() == 8,
		"5. Seven duties complete the first-winter slice without a fixed event"
	)
	var scouting_rows: Array = patrol.session.get_snapshot().get_skill_progress(
		"player"
	)
	_check(
		scouting_rows.size() == 1
		and str((scouting_rows[0] as Dictionary).get("skill_def_id", ""))
			== "skill.scouting"
		and int((scouting_rows[0] as Dictionary).get("practice_xp", 0)) == 56
		and int((scouting_rows[0] as Dictionary).get("rank", -1)) == 1
		and ((scouting_rows[0] as Dictionary).get(
			"source_fact_ids",
			[]
		) as Array).size() == 7,
		"5a. Seven patrol facts produce traceable scouting practice and rank"
	)

	var patrol_status: Dictionary = patrol.get_status()
	var patrol_completion: Dictionary = patrol.get_completion_summary()
	_check(
		_status_value(patrol_status, "border_pressure") <= 5
		and bool(patrol_completion.get("active", false))
		and "雾线暂时退远" in _completion_text(patrol_completion),
		"6. Repeated patrol produces a low-pressure evidence-based summary"
	)
	_check(
		patrol_npc_reactions > 0
		and patrol.session.stores["fact_store"].find_facts_by_type(
			"npc_autonomous_action"
		).size() > 0,
		"7. NPCs independently react to service state during the same week "
		+ "(configured=%d, narratives=%d, actions=%d)" % [
			patrol.session.autonomous_action_rules.size(),
			patrol_npc_reactions,
			patrol.session.stores["fact_store"].find_facts_by_type(
				"npc_autonomous_action"
			).size(),
		]
	)

	var social = ControllerModel.new()
	_check(
		bool(social.start(FIXTURE, PROJECT).get("success", false)),
		"8. A second service life starts from the same world state"
	)
	var social_sequence := [
		"drill_with_elai",
		"share_hard_bread",
		"drill_with_elai",
		"share_hard_bread",
		"drill_with_elai",
		"rest_in_infirmary",
		"drill_with_elai",
	]
	for duty_id: String in social_sequence:
		var options := social.get_duty_options()
		if not _duty_can_execute(options, duty_id):
			duty_id = "drill_with_elai"
		var result: Dictionary = social.execute_duty(duty_id)
		_check(
			bool(result.get("success", false)),
			"9. Social path executes available state-driven duty"
		)

	var social_status: Dictionary = social.get_status()
	var social_completion: Dictionary = social.get_completion_summary()
	var elai_trust := int(
		social.session.stores["relationship_store"].get_relation(
			"recruit_elai", "player", "trust", 0
		)
	)
	_check(
		elai_trust >= 12
		and _status_value(social_status, "border_pressure")
			> _status_value(patrol_status, "border_pressure"),
		"10. Social duties build companionship while allowing border pressure"
	)
	_check(
		_completion_text(social_completion)
			!= _completion_text(patrol_completion)
		and social.duty_counts != patrol.duty_counts,
		"11. Same seven days produce different history and completion text"
	)
	_check(
		social.session.stores["chronicle_store"].list_entries().size() == 1
		and social.session.stores["memory_store"].list_memories(
			"player"
		).size() == 7,
		"12. Completion is backed by seven memories and a chronicle entry"
	)

	_finish()


func _find_duty(options: Array, duty_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("duty_id", "")) == duty_id:
			return option
	return {}


func _has_duty(options: Array, duty_id: String) -> bool:
	return not _find_duty(options, duty_id).is_empty()


func _duty_can_execute(options: Array, duty_id: String) -> bool:
	return bool(_find_duty(options, duty_id).get("can_execute", false))


func _status_value(status: Dictionary, key: String) -> int:
	for row: Dictionary in status.get("rows", []):
		if str(row.get("key", "")) == key:
			return int(row.get("value", 0))
	return 0


func _completion_text(completion: Dictionary) -> String:
	return "\n".join(completion.get("lines", []))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SEVENTH OUTPOST LIFE PROJECT PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SEVENTH OUTPOST LIFE PROJECT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 SEVENTH OUTPOST LIFE PROJECT FAIL] " + failure)
	print(
		"[V5 SEVENTH OUTPOST LIFE PROJECT RESULT] FAIL (%d)"
		% failures.size()
	)
	quit(1)
