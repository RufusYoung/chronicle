extends SceneTree

const LiveModel = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const OutpostModel = preload("res://scripts/rebuild/v5_seventh_outpost_view_model.gd")
const GIFT := "give_food_to_hungry_person:chen_mi"
const SAVE_PATH := "user://tests/player_agency_receipt.json"
var failures: Array[String] = []


class FailingTickSession:
	extends "res://scripts/sim/core/sim_session.gd"
	func advance_time(_hours: int, _trigger_key: String, _metadata: Dictionary = {}) -> Dictionary:
		return {"success": false, "error": "test_injected_tick_failure"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live := LiveModel.new()
	live.start()
	var legacy: Dictionary = live.session.execute_action(GIFT, {"source": "test_injection"})
	_check(legacy.get("success", false) and live.session.current_hour == 10,
		"The transaction-only contract remains explicit for simulation injection")
	live.start()
	for rule: Dictionary in live.session.rules:
		if str(rule.get("id", rule.get("rule_id", ""))) == "give_food_to_hungry_person":
			rule["hours"] = 2
	var quoted_cost := ""
	for row: Dictionary in live.build_view_data().actions:
		if str(row.get("action_id", "")) == GIFT:
			quoted_cost = str(row.get("cost", ""))
	_check("2 小时" in quoted_cost and "1 份食物" in quoted_cost,
		"Displayed cost uses the same duration as settlement, including rule overrides")
	var timed: Dictionary = live.session.execute_timed_action(GIFT, {"source": "test_injection"})
	_check(timed.get("success", false) and timed.get("hours", 0) == 2
		and timed.get("time_advanced", false) and live.session.current_hour == 12,
		"Session facade uses candidate duration, not a second UI clock")
	var count: int = live.session.get_world_log_entries().size()
	var stale: Dictionary = live.session.execute_timed_action(GIFT)
	_check(not stale.get("success", true) and live.session.current_hour == 12
		and live.session.get_world_log_entries().size() == count,
		"A consumed choice cannot advance time or mutate logs a second time")
	var interrupted := LiveModel.new(FailingTickSession.new())
	interrupted.start()
	var partial: Dictionary = interrupted.perform_action(GIFT)
	_check(partial.get("success", false) and not partial.get("time_advanced", true)
		and interrupted.session.current_hour == 10
		and "行动已经生效" in str(interrupted.build_view_data().feedback.summary_details),
		"Injected tick failure is distinguished from an unapplied action")
	var repeated: Dictionary = interrupted.perform_action(GIFT)
	_check(not repeated.get("success", true)
		and interrupted.session.get_snapshot().get_player_value("food_count", 0) == 2,
		"A failed world tick cannot be retried by consuming the same choice again")
	var outpost := OutpostModel.new()
	outpost.start()
	outpost.perform_duty("patrol_fog_line", {"source": "test_injection"})
	var before: Dictionary = outpost.build_view_data()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var saved: Dictionary = outpost.save_to_path(SAVE_PATH, {"source_kind": "player_save"})
	var restored := OutpostModel.new()
	var loaded: Dictionary = restored.load_from_path(SAVE_PATH)
	_check(saved.get("ok", false) and loaded.get("success", false),
		"Causal receipts round-trip through the existing save envelope")
	if loaded.get("success", false):
		var after: Dictionary = restored.build_view_data()
		_check(before.agency.direct_lines == after.agency.direct_lines
			and before.agency.world_lines == after.agency.world_lines
			and before.feedback == after.feedback
			and restored.controller.day_history[0].has("duty_transaction"),
			"Loading retains direct versus routine consequences and their cause labels")
	for failure: String in failures:
		push_error(failure)
	print("[PLAYER ACTION RECEIPT RESULT] %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PLAYER ACTION RECEIPT PASS] " + message)
	else:
		failures.append(message)
