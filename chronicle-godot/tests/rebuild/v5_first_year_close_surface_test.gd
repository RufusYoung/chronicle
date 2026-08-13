extends SceneTree

const ViewModelModel = preload(
	"res://scripts/rebuild/v5_seventh_outpost_view_model.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var transition_view_model = ViewModelModel.new()
	transition_view_model.start({}, "first_quarter")
	for unused: int in range(6):
		transition_view_model.perform_duty(
			"survey_thaw_routes", {"incident_roll_override": 100}
		)
	var transition_surface: Dictionary = transition_view_model.build_view_data()
	var enter_result: Dictionary = transition_view_model.enter_first_year_close()
	_check(
		bool(transition_surface.get("can_advance_phase", false))
		and bool(enter_result.get("success", false))
		and str(transition_view_model.build_view_data().get(
			"phase_id", ""
		)) == "first_year_close",
		"0. The visible first-quarter exit enters the annual phase"
	)

	var view_model = ViewModelModel.new()
	var start: Dictionary = view_model.start({}, "first_year_close")
	_check(
		bool(start.get("success", false)),
		"1. The annual phase can be opened as a standalone test surface"
	)
	var opening: Dictionary = view_model.build_view_data()
	_check(
		str(opening.get("phase_id", "")) == "first_year_close"
		and int(opening.get("calendar_days_per_step", 0)) == 30
		and str(opening.get("objective", "")).contains("273 天")
		and _has_person(opening.get("people", []), "messenger_nia")
		and str((opening.get("feedback", {}) as Dictionary).get(
			"body", ""
		)).contains("事实阈值"),
		"2. The surface explains monthly time compression and annual evidence thresholds"
	)
	for unused: int in range(9):
		var result: Dictionary = view_model.perform_duty(
			"month_preserve_rations", {"incident_roll_override": 100}
		)
		_check(
			bool(result.get("success", false)),
			"3.%d. The annual surface resolves one monthly choice" % (unused + 1)
		)
	var complete: Dictionary = view_model.build_view_data()
	var milestone: Dictionary = (
		complete.get("completion", {}) as Dictionary
	).get("milestone", {})
	_check(
		bool(complete.get("complete", false))
		and int(complete.get("world_day", 0)) == 365
		and bool(milestone.get("active", false))
		and not bool(milestone.get("resolved", false))
		and (milestone.get("outcomes", []) as Array).size() == 2,
		"4. The year-end surface exposes only the two outcomes earned by this route"
	)
	var resolution: Dictionary = view_model.resolve_milestone()
	var resolved: Dictionary = view_model.build_view_data()
	_check(
		bool(resolution.get("success", false))
		and bool(((resolved.get("completion", {}) as Dictionary).get(
			"milestone", {}
		) as Dictionary).get("resolved", false))
		and str((resolved.get("feedback", {}) as Dictionary).get(
			"body", ""
		)).contains("正式戍卒"),
		"5. Resolving the visible annual node returns descriptive feedback"
	)
	_finish()


func _has_person(people: Array, person_id: String) -> bool:
	for person: Dictionary in people:
		if str(person.get("id", "")) == person_id:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 FIRST YEAR SURFACE PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 FIRST YEAR SURFACE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 FIRST YEAR SURFACE FAIL] " + failure)
	print("[V5 FIRST YEAR SURFACE RESULT] FAIL (%d)" % failures.size())
	quit(1)
