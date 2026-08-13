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
	var clean = ControllerModel.new()
	clean.start(FIXTURE, PROJECT)
	var clean_result: Dictionary = clean.execute_duty(
		"patrol_fog_line", {"risk_roll_override": 10}
	)
	var clean_outcome: Dictionary = clean_result.get("risk_outcome", {})
	_check(
		bool(clean_result.get("success", false))
		and str(clean_outcome.get("tier_id", "")) == "clean"
		and int(clean_outcome.get("risk", -1)) == 4
		and int(clean_outcome.get("roll", 0)) == 10
		and str(clean_result.get("summary", "")).contains("没有让一次误判"),
		"1. Modified risk produces a visible clean outcome"
	)

	var setback = ControllerModel.new()
	setback.start(FIXTURE, PROJECT)
	var before_fatigue := int(
		setback.session.get_snapshot().get_player_value("fatigue", 0)
	)
	var setback_result: Dictionary = setback.execute_duty(
		"patrol_fog_line", {"risk_roll_override": 1}
	)
	var setback_outcome: Dictionary = setback_result.get("risk_outcome", {})
	var after = setback.session.get_snapshot()
	_check(
		bool(setback_result.get("success", false))
		and str(setback_outcome.get("tier_id", "")) == "setback"
		and int(after.get_player_value("fatigue", 0)) == before_fatigue + 3
		and _fact_tier(after, "life_project_risk_resolved") == "setback"
		and str(setback_result.get("summary", "")).contains("壕沟边失足"),
		"2. Failed roll atomically applies consequence and traceable fact"
	)
	_check(
		_has_fact(after, "actor_completed_border_watch")
		and _mark_progress(after, "mark.border_watch_habit") == 1,
		"3. Patrol outcome also advances its accumulated mark"
	)
	_finish()


func _fact_tier(snapshot: Variant, fact_type: String) -> String:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) == fact_type:
			return str(fact.get("outcome_tier", ""))
	return ""


func _has_fact(snapshot: Variant, fact_type: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) == fact_type:
			return true
	return false


func _mark_progress(snapshot: Variant, mark_def_id: String) -> int:
	for mark: Dictionary in snapshot.mark_instances:
		if str(mark.get("mark_def_id", "")) == mark_def_id:
			return int(mark.get("progress", 0))
	return 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 RISK OUTCOME PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 RISK OUTCOME RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 RISK OUTCOME FAIL] " + failure)
	print("[V5 RISK OUTCOME RESULT] FAIL (%d)" % failures.size())
	quit(1)
