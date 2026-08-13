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
	var controller = ControllerModel.new()
	var start: Dictionary = controller.start(FIXTURE, PROJECT)
	_check(bool(start.get("success", false)), "1. First winter starts")
	if not bool(start.get("success", false)):
		push_error("[V5 RESOURCE DUTY START REPORT] %s" % str(start))
		_finish()
		return

	var before = controller.session.get_snapshot()
	var repair: Dictionary = controller.execute_duty("repair_east_wall")
	var after_repair = controller.session.get_snapshot()
	var hammer: Dictionary = after_repair.get_item(
		"item_instance.seventh_outpost.player_repair_hammer"
	)
	_check(
		bool(repair.get("success", false))
		and _quantity(before, "item.wall_timber_bundle") == 4
		and _quantity(after_repair, "item.wall_timber_bundle") == 3
		and int((hammer.get("condition", {}) as Dictionary).get("durability", 0)) == 66
		and (hammer.get("history", []) as Array).size() == 1,
		"2. Wall repair consumes timber and records hammer wear"
	)
	_check(
		_has_fact(after_repair, "actor_repaired_outpost_wall")
		and _mark_progress(after_repair, "mark.winter_wall_callus") == 1
		and _skill_xp(after_repair, "skill.maintenance") == 8,
		"3. Wall repair fact drives mark and maintenance practice"
	)

	var archery: Dictionary = controller.execute_duty("practice_wall_archery")
	var after_archery = controller.session.get_snapshot()
	_check(
		bool(archery.get("success", false))
		and _quantity(after_archery, "item.arrow_material_bundle") == 3
		and _skill_xp(after_archery, "skill.archery") == 8,
		"4. Archery consumes arrow material and records practice"
	)

	var blocked = ControllerModel.new()
	blocked.start(FIXTURE, PROJECT)
	blocked.session.stores["item_store"].items[
		"item_instance.seventh_outpost.wall_timber"
	]["quantity"] = 0
	blocked.session.stores["item_store"].items[
		"item_instance.seventh_outpost.wall_timber"
	]["holder"] = {"kind": "destroyed", "id": ""}
	var option := _find_duty(blocked.get_duty_options(), "repair_east_wall")
	var rejected: Dictionary = blocked.execute_duty("repair_east_wall")
	_check(
		not bool(option.get("can_execute", true))
		and str(option.get("blocked_reason", "")).contains("修墙木料")
		and str(rejected.get("error", "")) == "duty_blocked"
		and blocked.get_day() == 1,
		"5. Missing timber is explained and cannot advance the day"
	)

	_finish()


func _quantity(snapshot: Variant, item_def_id: String) -> int:
	var quantity := 0
	for item: Dictionary in snapshot.get_items():
		if str(item.get("item_def_id", "")) == item_def_id:
			quantity += int(item.get("quantity", 0))
	return quantity


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


func _skill_xp(snapshot: Variant, skill_def_id: String) -> int:
	for skill: Dictionary in snapshot.skill_progress:
		if str(skill.get("skill_def_id", "")) == skill_def_id:
			return int(skill.get("practice_xp", 0))
	return 0


func _find_duty(options: Array, duty_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("duty_id", "")) == duty_id:
			return option
	return {}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 RESOURCE DUTY PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 RESOURCE DUTY RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 RESOURCE DUTY FAIL] " + failure)
	print("[V5 RESOURCE DUTY RESULT] FAIL (%d)" % failures.size())
	quit(1)
