extends SceneTree

var failures: Array[String] = []
var checks := 0

class CountedView extends "res://scripts/rebuild/v5_live_location_view_model.gd":
	var action_calls := 0
	var travel_calls := 0
	var status_calls := 0

	func _action_rows() -> Array:
		action_calls += 1
		return super._action_rows()

	func _travel_rows() -> Array:
		travel_calls += 1
		return super._travel_rows()

	func _region_status_rows(snapshot: Variant) -> Array:
		status_calls += 1
		return super._region_status_rows(snapshot)

class UnsharedView extends "res://scripts/rebuild/v5_live_location_view_model.gd":
	func _decision_view(snapshot: Variant, _projection: Dictionary = {}, _encounter_active: Variant = null) -> Dictionary:
		return super._decision_view(snapshot)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for scenario: String in ["lake_town", "generated_network"]:
		for seed_value: int in [81001, 82002]:
			var model := CountedView.new()
			var reference := UnsharedView.new()
			var options := {"scenario": scenario, "challenge_seed_override": seed_value}
			_check(model.start(options).success and reference.start(options).success, "both projections start")
			_compare(model, reference, scenario + " initial")
			if scenario == "lake_town":
				var id := "give_food_to_hungry_person:chen_mi"
				_check(model.perform_action(id).success and reference.perform_action(id).success, "legal action succeeds")
				_compare(model, reference, "after help")
				_check(not model.perform_action(id).success and not reference.perform_action(id).success, "stale action still rejected")
				_compare(model, reference, "after stale action")
			else:
				var routes: Array = model.build_view_data().travel_options
				var route_id := ""
				for route: Dictionary in routes:
					if route.get("can_travel", false):
						route_id = str(route.route_id)
						break
				_check(route_id != "", "generated world has a legal route")
				if route_id != "":
					_check(model.perform_travel(route_id).success and reference.perform_travel(route_id).success, "legal travel succeeds")
					_compare(model, reference, "after travel")
			_check(model.advance_time(1).success and reference.advance_time(1).success, "legal wait succeeds")
			_compare(model, reference, "after wait")
	print("WORLD_PROJECTION_REUSE_RESULT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _compare(model: CountedView, reference: Variant, label: String) -> void:
	var before := _state(model)
	model.action_calls = 0
	model.travel_calls = 0
	model.status_calls = 0
	var view := model.build_view_data()
	_check(model.action_calls == 1 and model.travel_calls == 1 and model.status_calls == 1,
		label + ": each expensive UI projection executes once")
	_check(JSON.stringify(view, "", true, true) == JSON.stringify(reference.build_view_data(), "", true, true),
		label + ": full shared/unshared view parity")
	_check(before == _state(model) and before == _state(reference), label + ": Stores, time, RNG and log parity")
	view.actions.clear()
	_check(not model.build_view_data().actions.is_empty(), label + ": returned arrays do not become cross-action caches")


func _state(model: Variant) -> String:
	var envelope: Dictionary = model.session.build_save_envelope()
	return JSON.stringify({"stores": envelope.stores, "session": envelope.session,
		"world_time": envelope.world_time, "rng_states": envelope.rng_states,
		"world_log": envelope.world_log}, "", true, true)


func _check(condition: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)
