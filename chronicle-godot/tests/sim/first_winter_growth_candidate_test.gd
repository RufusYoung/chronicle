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
	patrol.start(FIXTURE, PROJECT)
	for day: int in range(7):
		patrol.execute_duty(
			"patrol_fog_line", {"risk_roll_override": 10}
		)
	var patrol_candidates := patrol.get_growth_candidates()
	var fog_reader := _candidate(
		patrol_candidates, "growth.first_winter.fog_reader"
	)
	_check(
		patrol.is_complete()
		and patrol_candidates.size() == 1
		and int(fog_reader.get("evidence_count", 0)) == 7
		and (fog_reader.get("source_fact_ids", []) as Array).size() == 7
		and str((fog_reader.get("reward_preview", {}) as Dictionary).get(
			"skill_def_id", ""
		)) == "skill.scouting",
		"1. Patrol facts produce one traceable route-specific candidate"
	)

	var social = ControllerModel.new()
	social.start(FIXTURE, PROJECT)
	for day: int in range(7):
		social.execute_duty("drill_with_elai")
	var social_candidates := social.get_growth_candidates()
	_check(
		social_candidates.size() == 1
		and not _candidate(
			social_candidates, "growth.first_winter.fire_circle"
		).is_empty()
		and _candidate(
			social_candidates, "growth.first_winter.fog_reader"
		).is_empty(),
		"2. A different lived route produces a different candidate"
	)

	var incomplete = ControllerModel.new()
	incomplete.start(FIXTURE, PROJECT)
	for day: int in range(3):
		incomplete.execute_duty(
			"patrol_fog_line", {"risk_roll_override": 10}
		)
	_check(
		incomplete.get_growth_candidates().is_empty(),
		"3. Candidate is withheld until the stage ends"
	)
	_finish()


func _candidate(rows: Array, candidate_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.get("candidate_id", "")) == candidate_id:
			return row
	return {}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GROWTH CANDIDATE PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GROWTH CANDIDATE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 GROWTH CANDIDATE FAIL] " + failure)
	print("[V5 GROWTH CANDIDATE RESULT] FAIL (%d)" % failures.size())
	quit(1)
