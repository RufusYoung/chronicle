extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Base = preload("res://tests/sim/world_integration_contract_test.gd")
const Journey = preload("res://scripts/sim/player/journey_events.gd")
const Setup = preload("res://scripts/sim/generation/journey_content_setup.gd")
var checks := 0
var failures: Array = []


static func options(seed: int = 81001) -> Dictionary:
	var result := Base.options(seed)
	result.integration_rules_version = 2
	result["journey_rules_version"] = 1
	return result


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var model := Live.new()
	var started: Dictionary = model.start(options())
	check(started.success, "new explicit journey world starts: " + str(started.get("error", "")))
	if not started.success:
		quit(1)
		return
	var session: Variant = model.session
	check(session.context.locations.has("journey_location.lake_cave"), "canon-anchored local exploration site exists")
	check(session.context.locations["journey_location.lake_cave"].canon_origin.place_id == "echo_port", "new detail inherits authored region, not a new canon capital")
	var original: Dictionary = session.fixture_source_data.duplicate(true)
	var path := "user://tests/journey_content/initial.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(model.save_to_path(path, true).success, "native initial save")
	var restored := Live.new()
	var loaded: Dictionary = restored.load_from_path(path)
	check(loaded.success, "native initial load: " + str(loaded.get("error", "")))
	if not loaded.success:
		quit(1)
		return
	check(JSON.stringify(JSON.parse_string(JSON.stringify(restored.session.fixture_source_data)), "", true) == JSON.stringify(JSON.parse_string(JSON.stringify(original)), "", true), "load preserves compiled world and finite stock")
	check(go(model, "generated_location.echo_landing.landing"), "formal travel reaches shore")
	check(Journey.current(session).get("id") == "shore_box", "local short event has a concrete situation")
	var rng: int = session.challenge_rng.state
	var hour: int = session.elapsed_hours_since_start
	for index: int in range(3):
		Journey.options(session)
		model.build_view_data()
	check(rng == session.challenge_rng.state and hour == session.elapsed_hours_since_start, "previews spend neither time nor random rolls")
	check(not model.act_player_life("adventure:cliff_pack:detour").success, "remote event cannot be executed")
	check(model.save_to_path(path, true).success, "save at an unresolved choice")
	check(restored.load_from_path(path).success, "restore same choice")
	var before: int = Journey.available(session, "player", "item.light_reed_cord")
	var action := model.act_player_life("adventure:shore_box:hook")
	check(action.success, "safe slower retrieval succeeds: " + str(action.get("error", "")))
	check(session.elapsed_hours_since_start == hour + 2, "safer alternative spends two real world hours")
	check(action.get("hours") == 2 and "耗时 2 小时" in model.build_view_data().feedback.eyebrow, "receipt shows actual time cost after an adventure")
	check(Journey.available(session, "player", "item.light_reed_cord") == before + 2, "finite rope physically transferred")
	check(Journey.available(session, "journey_cache.shore_box", "item.light_reed_cord") == 0, "source cache depleted")
	check(not model.act_player_life("adventure:shore_box:hook").success, "resolved loot cannot be repeated")
	check(restored.act_player_life("adventure:shore_box:hook").success, "same native continuation succeeds")
	check(equal_native(session.stores.item_store.to_save_data(), restored.session.stores.item_store.to_save_data()), "native continuation has identical items")
	check(go(model, "journey_location.lake_cave"), "formal route reaches cave")
	check(model.act_player_life("adventure:cave_marks:skip").success, "declining study consumes no time and exposes continuation")
	check(Journey.current(session).get("id") == "cave_bundle", "conditional next node is available")
	var knowledge_option: Array = Journey.options(session).filter(func(row: Dictionary) -> bool: return row.action_id == "adventure:cave_bundle:ledge")
	check(not knowledge_option[0].can_execute, "unknown safe route cannot be used")
	check(model.save_to_path(path, true).success, "native before a random rope attempt")
	check(restored.load_from_path(path).success, "restore random attempt")
	var first: Dictionary = model.act_player_life("adventure:cave_bundle:rope")
	var second: Dictionary = restored.act_player_life("adventure:cave_bundle:rope")
	check(first.success and second.success, "rope attempt executes regardless of roll outcome")
	check(first.player_life_feedback.body == second.player_life_feedback.body, "native RNG continuation gives same outcome")
	check("磨损1" in first.player_life_feedback.body, "actual rope wear shown in receipt")
	check(equal_native(session.stores.item_store.to_save_data(), restored.session.stores.item_store.to_save_data()), "worn physical tool identical after reload")
	check(session.stores.item_store.list_items_for_owner("player").any(func(item: Dictionary) -> bool: return item.item_def_id == "item.light_reed_cord" and int(item.quantity) == 1 and int(item.condition.durability) < int(item.condition.maximum_durability)), "wear splits one rope rather than damaging whole stack")
	check(model.save_to_path(path, true).success, "save after actual loot and wear")
	check(restored.load_from_path(path).success, "restore after actual loot and wear")
	var old := Live.new()
	check(old.start(Base.options()).success, "older world still starts")
	check(Journey.options(old.session).is_empty() and not old.session.context.locations.has("journey_location.lake_cave"), "older bootstrap never acquires journey rules")
	var corrupt := original.duplicate(true)
	corrupt.journey_rules.events[0].choices[0].check.difficulty = 3
	check(Setup.configure(corrupt, session.registry) == "journey_signature_mismatch", "changed event rules fail compiled signature")
	print("JOURNEY_CONTENT_CONTRACT %d/%d %s" % [checks - failures.size(), checks, str(failures)])
	quit(0 if failures.is_empty() else 1)


static func go(model: Variant, target: String) -> bool:
	for attempt: int in range(24):
		var session: Variant = model.session
		if session.stores.state_store.get_state("player", "daily_route_id", "") != "":
			if not model.act_player_life("continue").get("success", false):
				return false
			continue
		if session.context.location_id == target:
			return true
		var queue: Array = [[str(session.context.location_id), []]]
		var seen := {}
		var path: Array = []
		while not queue.is_empty():
			var entry: Array = queue.pop_front()
			if entry[0] == target:
				path = entry[1]
				break
			if seen.has(entry[0]):
				continue
			seen[entry[0]] = true
			for route: Dictionary in session.fixture_source_data.travel_routes:
				if route.from_location_id == entry[0]:
					queue.append([str(route.to_location_id), entry[1] + [str(route.route_id)]])
		if path.is_empty() or not model.perform_travel(str(path[0])).get("success", false):
			return false
	return false


func check(passed: bool, label: String) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures.append(label)


static func equal_native(a: Variant, b: Variant) -> bool:
	return JSON.stringify(JSON.parse_string(JSON.stringify(a, "", true, true)), "", true, true) == JSON.stringify(JSON.parse_string(JSON.stringify(b, "", true, true)), "", true, true)
