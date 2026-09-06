extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	for scenario: String in ["lake_town", "generated_network", "echo_realm"]:
		var model := Live.new()
		_check(model.start({"scenario": scenario, "challenge_seed_override": 81001}).success, scenario + " starts")
		_check(model.advance_time(6).success, scenario + " acquires runtime data")
		var snapshot: Variant = model.session.get_snapshot()
		var before := _state(model)
		var projected := JSON.stringify(snapshot.to_dict(), "", true, true)
		for key: String in snapshot.to_dict():
			_mutate(snapshot.get(key))
		_check(before == _state(model),
			scenario + " snapshot edits cannot reach live Stores or Context")
		_check(projected == JSON.stringify(model.session.get_snapshot().to_dict(), "", true, true),
			scenario + " a fresh snapshot retains every original projection field")
		var old: Variant = model.session.get_snapshot()
		var old_data := JSON.stringify(old.to_dict(), "", true, true)
		_check(model.advance_time(6).success, scenario + " next tick commits")
		_check(old_data == JSON.stringify(old.to_dict(), "", true, true), scenario + " commits cannot change an old snapshot")
		var current: Variant = model.session.get_snapshot()
		for holder: String in ["player", "missing"]:
			var expected: Array = current.get_items().filter(func(item: Dictionary) -> bool:
				return item.get("holder", {}) == {"kind": "entity", "id": holder})
			_check(JSON.stringify(expected, "", true, true) == JSON.stringify(current.get_items_for_holder(holder), "", true, true),
				scenario + " holder query retains order and full history: " + holder)
		var copies: Array = current.get_items_for_holder("player")
		var before_holder_edit := _state(model)
		var before_snapshot_edit := JSON.stringify(current.to_dict(), "", true, true)
		_mutate(copies)
		_check(before_holder_edit == _state(model)
			and before_snapshot_edit == JSON.stringify(current.to_dict(), "", true, true),
			scenario + " holder result edits cannot reach the snapshot or live world")
		_check(before != _state(model), "six additional hours did change the live world")
	print("SNAPSHOT_OWNERSHIP_RESULT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _state(model: Variant) -> String:
	# Wall-clock save metadata must not turn an isolation check into a timing test.
	return JSON.stringify(model.session.build_save_envelope({"save_id": "test.snapshot",
		"created_at_utc": "2000-01-01T00:00:00Z", "saved_at_utc": "2000-01-01T00:00:00Z"}), "", true, true)


func _mutate(value: Variant) -> void:
	if value is Dictionary:
		if value.is_read_only():
			return
		for key: Variant in value:
			_mutate(value[key])
		value.clear()
	elif value is Array:
		if value.is_read_only():
			return
		for child: Variant in value:
			_mutate(child)
		value.clear()


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
