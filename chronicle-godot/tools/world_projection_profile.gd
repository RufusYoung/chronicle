extends SceneTree
## Read-only profiling of the real projection methods, outside regression discovery.

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
var output := "user://tests/world_projection_profile"
var rows: Array = []
var failures: Array[String] = []

class UnsharedDecision extends "res://scripts/rebuild/v5_live_location_view_model.gd":
	func _decision_view(snapshot: Variant, _projection: Dictionary = {}, _encounter_active: Variant = null) -> Dictionary:
		return super._decision_view(snapshot)

class MeasuredBuilder extends "res://scripts/sim/core/sim_snapshot_builder.gd":
	var calls := 0
	var elapsed_usec := 0

	func build_snapshot(context: Variant, stores: Dictionary, all_entities: bool = false,
			world_time: Dictionary = {}) -> Variant:
		var began := Time.get_ticks_usec()
		var result: Variant = super.build_snapshot(context, stores, all_entities, world_time)
		calls += 1
		elapsed_usec += Time.get_ticks_usec() - began
		return result


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var checkpoint := "user://tests/world_runtime_probe/day7.json"
	if not OS.get_cmdline_user_args().is_empty():
		checkpoint = OS.get_cmdline_user_args()[0]
	for phase: String in ["initial", "day7"]:
		var model := Live.new()
		var opened: Dictionary = (model.start({"scenario": "generated_network", "challenge_seed_override": 81001})
			if phase == "initial" else model.load_from_path(checkpoint))
		if not opened.get("success", false):
			failures.append("Cannot open " + phase + ": " + str(opened))
			continue
		var initial_state := _state(model)
		var baseline := JSON.stringify(model.build_view_data(), "", true, true)
		var builder := MeasuredBuilder.new()
		model.session.snapshot_builder = builder
		var snapshot: Variant = model.session.get_snapshot()
		rows.append({"world": phase, "counts": model.session.get_store_summary()})
		var measured: Variant = _measure(phase, "full_projection", model.build_view_data, builder, 20)
		if JSON.stringify(measured, "", true, true) != baseline:
			failures.append(phase + ": instrumentation changed projection")
		var probes := {
			"snapshot": model.session.get_snapshot,
			"action_candidates": model.session.get_action_candidates,
			"action_rows": model._action_rows,
			"decision": model._decision_view.bind(snapshot),
			"agency": model._agency_view,
			"risk": model._risk_view,
			"travel": model._travel_rows,
			"player": model._player_view.bind(snapshot),
			"knowledge": model._knowledge_rows.bind(snapshot),
			"feedback": model._feedback_view,
			"world_log_copy": model.session.get_world_log_entries,
		}
		for label: String in probes:
			_measure(phase, label, probes[label], builder, 5)
		if _state(model) != initial_state:
			failures.append(phase + ": profiling mutated Stores, time, RNG or log")
		var unshared := UnsharedDecision.new()
		var reference_opened: Dictionary = (unshared.start({"scenario": "generated_network", "challenge_seed_override": 81001})
			if phase == "initial" else unshared.load_from_path(checkpoint))
		if not reference_opened.get("success", false):
			failures.append(phase + ": cannot load unshared reference")
			continue
		var reference_builder := MeasuredBuilder.new()
		unshared.session.snapshot_builder = reference_builder
		var reference_state := _state(unshared)
		var reference_view: Variant = _measure(phase, "unshared_full_projection", unshared.build_view_data, reference_builder, 20)
		if JSON.stringify(reference_view, "", true, true) != baseline or _state(unshared) != reference_state:
			failures.append(phase + ": shared/unshared projection parity failed")
		print("PROJECTION_PROFILE_WORLD " + phase)
	var file := FileAccess.open(output + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info(),
		"processor": OS.get_processor_name(), "checkpoint": checkpoint,
		"rows": rows, "failures": failures,
		"scope": "Warm read-only projection cost, not action latency or cold startup. Component probes overlap and must not be added together."}, "  "))
	file.close()
	print("PROJECTION_PROFILE_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func _measure(world: String, label: String, operation: Callable,
		builder: MeasuredBuilder, repeats: int) -> Variant:
	builder.calls = 0
	builder.elapsed_usec = 0
	var durations: Array[float] = []
	var result: Variant
	for iteration: int in repeats:
		var began := Time.get_ticks_usec()
		result = operation.call()
		durations.append((Time.get_ticks_usec() - began) / 1000.0)
	durations.sort()
	rows.append({"world": world, "phase": label, "repeats": repeats,
		"p50_ms": durations[ceili(repeats * 0.5) - 1],
		"p95_ms": durations[ceili(repeats * 0.95) - 1],
		"max_ms": durations[-1], "snapshot_calls": builder.calls,
		"snapshot_ms_total": builder.elapsed_usec / 1000.0})
	return result


func _state(model: Variant) -> String:
	var envelope: Dictionary = model.session.build_save_envelope()
	return JSON.stringify({"stores": envelope.stores, "session": envelope.session,
		"world_time": envelope.world_time, "rng_states": envelope.rng_states,
		"world_log": envelope.world_log}, "", true, true)
