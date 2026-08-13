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
	var patrol = _complete_route("patrol_fog_line", 7, {
		"risk_roll_override": 10,
	})
	var patrol_result: Dictionary = patrol.confirm_growth_candidate(
		"growth.first_winter.fog_reader"
	)
	var patrol_features: Variant = patrol.session.stores[
		"character_feature_store"
	]
	var scouting := _skill(patrol_features, "skill.scouting")
	var watch_mark := _mark(patrol_features, "mark.border_watch_habit")
	var lantern: Dictionary = patrol.session.stores["item_store"].get_item(
		"item_instance.seventh_outpost.player_patrol_lantern"
	)
	_check(
		bool(patrol_result.get("success", false))
		and int(scouting.get("practice_xp", 0)) == 68
		and int(scouting.get("rank", 0)) == 2
		and int(watch_mark.get("progress", 0)) == 12
		and str(watch_mark.get("stage_id", "")) == "integrated"
		and _history_has_growth_fact(lantern),
		"1. Fog growth derives skill XP, converts the mark, and records lantern history"
	)

	var labor = _complete_route("repair_east_wall", 3)
	for unused: int in range(4):
		labor.execute_duty("drill_with_elai")
	var labor_result: Dictionary = labor.confirm_growth_candidate(
		"growth.first_winter.steady_worker"
	)
	var labor_features: Variant = labor.session.stores[
		"character_feature_store"
	]
	var maintenance := _skill(labor_features, "skill.maintenance")
	var hammer: Dictionary = labor.session.stores["item_store"].get_item(
		"item_instance.seventh_outpost.player_repair_hammer"
	)
	var labor_ok := (
		bool(labor_result.get("success", false))
		and int(maintenance.get("practice_xp", 0)) == 36
		and int(maintenance.get("rank", 0)) == 1
		and _has_trait(labor_features, "trait.winter_work_callus")
		and _history_has_growth_fact(hammer)
	)
	_check(
		labor_ok,
		"2. Labor growth derives maintenance, a lasting trait, and hammer history"
	)

	var social = _complete_route("drill_with_elai", 7)
	var social_result: Dictionary = social.confirm_growth_candidate(
		"growth.first_winter.fire_circle"
	)
	var social_features: Variant = social.session.stores[
		"character_feature_store"
	]
	var cloak: Dictionary = social.session.stores["item_store"].get_item(
		"item_instance.seventh_outpost.player_winter_cloak"
	)
	_check(
		bool(social_result.get("success", false))
		and _has_trait(social_features, "trait.fire_circle_belonging")
		and _history_has_growth_fact(cloak),
		"3. Social growth derives belonging and records shared cloak history"
	)

	var invalid = _complete_route("patrol_fog_line", 7, {
		"risk_roll_override": 10,
	})
	var rule := _growth_rule(invalid, "growth.first_winter.fog_reader")
	var reward: Dictionary = rule.get("reward", {})
	reward["required_feature_derivations"] = {
		"skill_def_ids": ["skill.missing_growth_contract"],
	}
	var before: Dictionary = invalid.session.get_save_store_data()
	var rejected: Dictionary = invalid.confirm_growth_candidate(
		"growth.first_winter.fog_reader"
	)
	_check(
		not bool(rejected.get("success", false))
		and str(rejected.get("error", "")) == "growth_feature_derivation_invalid"
		and _equivalent(invalid.session.get_save_store_data(), before),
		"4. A missing derived reward rejects before any state mutation"
	)
	_finish()


func _complete_route(
		duty_id: String,
		count: int,
		options: Dictionary = {}
) -> Variant:
	var controller = ControllerModel.new()
	controller.start(FIXTURE, PROJECT)
	for unused: int in range(count):
		controller.execute_duty(duty_id, options)
	return controller


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


func _has_trait(store: Variant, trait_def_id: String) -> bool:
	for trait_instance: Dictionary in store.list_trait_instances("player"):
		if str(trait_instance.get("trait_def_id", "")) == trait_def_id:
			return true
	return false


func _history_has_growth_fact(item: Dictionary) -> bool:
	for entry: Dictionary in item.get("history", []):
		if "growth_confirmed" in str(entry.get("fact_id", "")):
			return true
	return false


func _growth_rule(controller: Variant, candidate_id: String) -> Dictionary:
	for rule: Dictionary in controller.definition.get(
		"growth_candidate_rules", []
	):
		if str(rule.get("candidate_id", "")) == candidate_id:
			return rule
	return {}


func _equivalent(left: Variant, right: Variant) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GROWTH REWARD MATRIX PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GROWTH REWARD MATRIX RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 GROWTH REWARD MATRIX FAIL] " + failure)
	print("[V5 GROWTH REWARD MATRIX RESULT] FAIL (%d)" % failures.size())
	quit(1)
