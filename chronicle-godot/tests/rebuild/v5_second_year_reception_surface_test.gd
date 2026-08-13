extends SceneTree

const ViewModelModel = preload(
	"res://scripts/rebuild/v5_seventh_outpost_view_model.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var view_model = ViewModelModel.new()
	var start: Dictionary = view_model.start({}, "first_year_close")
	for unused: int in range(9):
		view_model.perform_duty(
			"month_preserve_rations", {"incident_roll_override": 100}
		)
	var resolved: Dictionary = view_model.resolve_milestone()
	var year_end: Dictionary = view_model.build_view_data()
	_check(
		bool(start.get("success", false))
		and bool(resolved.get("success", false))
		and bool(year_end.get("can_advance_phase", false)),
		"1. Resolved year-end data exposes the second-year transition"
	)
	var entered: Dictionary = view_model.enter_second_year_reception()
	var opening: Dictionary = view_model.build_view_data()
	_check(
		bool(entered.get("success", false))
		and str(opening.get("phase_id", "")) == "second_year_reception"
		and int(opening.get("world_day", 0)) == 365
		and str(opening.get("objective", "")).contains("21 天")
		and str((opening.get("feedback", {}) as Dictionary).get(
			"body", ""
		)).contains("NPC"),
		"2. The visible surface explains that the phase validates cross-year causality"
	)
	_check(
		_action_available(opening, "second_year_take_regular_watch")
		and _action_available(opening, "second_year_assign_relief_pairs")
		and not _action_available(opening, "second_year_lead_elai_fog_watch"),
		"3. The action panel reflects the ration-year outcome instead of a fixed branch"
	)
	var duty_result: Dictionary = view_model.perform_duty(
		"second_year_assign_relief_pairs"
	)
	var after_duty: Dictionary = view_model.build_view_data()
	_check(
		bool(duty_result.get("success", false))
		and _details_contain(after_duty, "罗恩按替岗记号"),
		"4. Action feedback displays Ron's autonomous response after settlement"
	)
	for unused: int in range(2):
		view_model.perform_duty("second_year_assign_relief_pairs")
	var complete: Dictionary = view_model.build_view_data()
	_check(
		bool(complete.get("complete", false))
		and int(complete.get("world_day", 0)) == 386
		and bool((complete.get("completion", {}) as Dictionary).get(
			"active", false
		)),
		"5. Three visible weekly duties complete the reception phase on day 386"
	)
	_finish()


func _action_available(view: Dictionary, duty_id: String) -> bool:
	for action: Dictionary in view.get("actions", []):
		if str(action.get("duty_id", "")) == duty_id:
			return bool(action.get("can_execute", false))
	return false


func _details_contain(view: Dictionary, needle: String) -> bool:
	var feedback: Dictionary = view.get("feedback", {})
	for detail: Variant in feedback.get("details", []):
		if str(detail).contains(needle):
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SECOND YEAR SURFACE PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SECOND YEAR SURFACE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 SECOND YEAR SURFACE FAIL] " + failure)
	print("[V5 SECOND YEAR SURFACE RESULT] FAIL (%d)" % failures.size())
	quit(1)
