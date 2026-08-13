extends SceneTree

const ControllerModel = preload(
	"res://scripts/sim/life_project/life_project_controller.gd"
)
const TransitionServiceModel = preload(
	"res://scripts/sim/save/life_stage_transition_service.gd"
)
const SOURCE_FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const TARGET_FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_after_first_winter_transition_fixture.json"
)
const TARGET_FIXTURE_ID := "seventh_outpost_after_first_winter_transition"
const PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_winter.json"
)
const TARGET_PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_post_winter_transition_contract.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source = ControllerModel.new()
	source.start(SOURCE_FIXTURE, PROJECT)
	for unused: int in range(7):
		source.execute_duty("patrol_fog_line", {"risk_roll_override": 10})
	source.confirm_growth_candidate("growth.first_winter.fog_reader")
	var transition: Dictionary = source.build_life_stage_transition(
		TARGET_FIXTURE_ID
	)
	_check(
		int(transition.get("schema_version", 0)) == 2
		and str(transition.get("target_fixture_id", "")) == TARGET_FIXTURE_ID
		and not (transition.get("equipment_loadouts", {}) as Dictionary).is_empty(),
		"1. A confirmed first winter builds a target-specific transition package"
	)

	var target = ControllerModel.new()
	target.start(TARGET_FIXTURE, TARGET_PROJECT)
	var applied: Dictionary = TransitionServiceModel.new().apply_to_controller(
		target, transition
	)
	var features: Variant = target.session.stores["character_feature_store"]
	var lantern: Dictionary = target.session.stores["item_store"].get_item(
		"item_instance.seventh_outpost.player_patrol_lantern"
	)
	_check(
		bool(applied.get("success", false))
		and int(target.session.stores["state_store"].get_state(
			"player", "perception", 0
		)) == 11
		and _has_talent(features, "talent.fog_line_reader")
		and int(_skill(features, "skill.scouting").get("practice_xp", 0)) == 68
		and str(_mark(features, "mark.border_watch_habit").get(
			"stage_id", ""
		)) == "integrated"
		and _history_has_growth_fact(lantern)
		and target.session.stores["equipment_store"].get_equipped_item_id(
			"player", "utility"
		) == "item_instance.seventh_outpost.player_patrol_lantern"
		and _has_fact(target.session, "actor_entered_life_stage"),
		"2. Growth, history, equipment, and the transition fact enter the target atomically"
	)
	var continued: Dictionary = target.execute_duty(
		"patrol_fog_line", {"risk_roll_override": 10}
	)
	_check(
		bool(continued.get("success", false))
		and target.get_day() == 2
		and int(_skill(features, "skill.scouting").get(
			"practice_xp", 0
		)) == 76,
		"3. The transitioned character can continue simulation with earned growth"
	)

	var envelope: Dictionary = target.build_save_envelope({
		"save_id": "save.test.first_winter.transition",
		"source_kind": "test_fixture",
	})
	var restored = ControllerModel.new()
	var restore_report: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(envelope))
	)
	_check(
		bool(restore_report.get("success", false))
		and _has_talent(
			restored.session.stores["character_feature_store"],
			"talent.fog_line_reader"
		)
		and _history_has_growth_fact(restored.session.stores[
			"item_store"
		].get_item("item_instance.seventh_outpost.player_patrol_lantern")),
		"4. The continued transition survives SaveEnvelope restore"
	)

	var rejected_target = ControllerModel.new()
	rejected_target.start(TARGET_FIXTURE, TARGET_PROJECT)
	var before: Dictionary = rejected_target.session.get_save_store_data()
	var invalid := transition.duplicate(true)
	var items: Array = invalid.get("items", [])
	var damaged_item := (items[0] as Dictionary).duplicate(true)
	var history: Array = (damaged_item.get("history", []) as Array).duplicate(true)
	history.append({
		"fact_id": "fact.missing.transition.reference",
		"event_type": "corrupt_test",
	})
	damaged_item["history"] = history
	items[0] = damaged_item
	invalid["items"] = items
	var rejected: Dictionary = TransitionServiceModel.new().apply_to_controller(
		rejected_target, invalid
	)
	_check(
		not bool(rejected.get("success", false))
		and str(rejected.get("phase", "")) == "preflight"
		and _equivalent(rejected_target.session.get_save_store_data(), before),
		"5. A late invalid reference leaves the real target session untouched"
	)
	_finish()


func _has_talent(store: Variant, talent_def_id: String) -> bool:
	for assignment: Dictionary in store.list_talent_assignments("player"):
		if str(assignment.get("talent_def_id", "")) == talent_def_id:
			return true
	return false


func _skill(store: Variant, skill_def_id: String) -> Dictionary:
	for progress: Dictionary in store.list_skill_progress("player"):
		if str(progress.get("skill_def_id", "")) == skill_def_id:
			return progress
	return {}


func _mark(store: Variant, mark_def_id: String) -> Dictionary:
	for mark: Dictionary in store.list_mark_instances("player"):
		if str(mark.get("mark_def_id", "")) == mark_def_id:
			return mark
	return {}


func _has_fact(session: Variant, fact_type: String) -> bool:
	return not session.stores["fact_store"].find_facts_by_type(
		fact_type
	).is_empty()


func _history_has_growth_fact(item: Dictionary) -> bool:
	for entry: Dictionary in item.get("history", []):
		if "growth_confirmed" in str(entry.get("fact_id", "")):
			return true
	return false


func _equivalent(left: Variant, right: Variant) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GROWTH TRANSITION PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GROWTH TRANSITION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 GROWTH TRANSITION FAIL] " + failure)
	print("[V5 GROWTH TRANSITION RESULT] FAIL (%d)" % failures.size())
	quit(1)
