extends SceneTree

const Agent = preload("res://scripts/agent/agent_game_session.gd")
const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Base = preload("res://tests/sim/journey_content_contract_test.gd")
const Journey = preload("res://scripts/sim/player/journey_events.gd")
const Presentation = preload("res://scripts/rebuild/roaming_presentation.gd")
var failures: Array = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var agent := Agent.new()
	var response := agent.handle({"protocol": 1, "command": "start", "request_id": "start",
		"session_id": agent.session_id, "expected_revision": 0, "mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_roaming_v1"})
	check(response.ok, "new public roaming profile starts: " + str(response.get("error", "")))
	if not response.ok:
		quit(1)
		return
	var model: Variant = agent.model
	var session: Variant = model.session
	check(session.fixture_source_data.journey_rules.version == 3, "native bootstrap freezes new rules")
	check(Presentation.build(response).title == "风从三条路上来", "first focus is a situation, not labor")
	var choice_id := "player_life/adventure:arrival_signs:forest"
	response = agent.handle({"protocol": 1, "command": "act", "request_id": "first",
		"session_id": agent.session_id, "expected_revision": agent.revision, "choice_id": choice_id})
	check(response.ok, "player legally chooses an opening curiosity")
	check(session.elapsed_hours_since_start == 0 and session.get_time_summary().minute == 10, "short observation takes ten minutes, not an hour")
	check(not model.act_player_life("adventure:arrival_signs:forest").success, "answered opening does not repeat")
	check(Base.go(model, "journey_location.forest_edge"), "reach forest along a public road")
	check(model.act_player_life("adventure:forest_sound:tracks").success, "choose a different observation without fixed route")
	check(model.act_player_life("adventure:forest_satchel:take").success, "get adventure equipment without production")
	check(Journey.available(session, "player", "item.knotted_fiber_whip") > 0, "weapon physically transferred")
	check(Journey.available(session, "journey_cache.forest_satchel", "item.knotted_fiber_whip") == 0, "source cannot replenish")
	check(Base.go(model, "journey_location.broken_bridge"), "reach a second situation")
	var options: Array = Journey.options(session)
	check(not options.filter(func(c: Dictionary) -> bool: return c.action_id.ends_with(":ford"))[0].can_execute, "unknown ford not usable")
	var old_time: int = session.elapsed_hours_since_start
	check(model.act_player_life("adventure:bridge_crossing:round").success, "slower safe crossing remains available without crafting")
	check(session.elapsed_hours_since_start == old_time + 1, "one hour choice ticks autonomous world")
	check(model.act_player_life("adventure:bridge_equipment:vest").success, "choose armor over escape gear")
	check(not model.act_player_life("adventure:bridge_equipment:shoes").success, "mutually exclusive loot cannot be collected twice")
	var path := "user://tests/roaming_journey/native.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(model.save_to_path(path, true).success, "save full native world and minute remainder")
	var restored := Live.new()
	var loaded: Dictionary = restored.load_from_path(path)
	check(loaded.success, "native restores rules and choices: " + str(loaded.get("error", "")))
	if loaded.success:
		check(Base.equal_native(session.stores.item_store.to_save_data(), restored.session.stores.item_store.to_save_data()), "inventory and finite sources survive load")
		check(session.get_time_summary() == restored.session.get_time_summary(), "native minute clock preserved")
		check(Journey.current(session) == Journey.current(restored.session), "remaining situation preserved")
	var old := Live.new()
	check(old.start(Base.options()).success and old.session.fixture_source_data.journey_rules.version == 1, "older world stays on its own rules")
	check(not old.session.context.locations.has("journey_location.forest_edge"), "old world does not silently acquire new locations")
	check_minute_boundary()
	print("ROAMING_JOURNEY_CONTRACT %d/%d %s" % [checks - failures.size(), checks, str(failures)])
	quit(0 if failures.is_empty() else 1)


func check_minute_boundary() -> void:
	var agent := Agent.new()
	var opened := agent.handle({"protocol": 1, "command": "start", "request_id": "clock",
		"session_id": agent.session_id, "expected_revision": 0, "mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_roaming_v1"})
	check(opened.ok, "minute boundary world starts")
	var model: Variant = agent.model
	for index: int in range(7):
		var rows: Array = model.session.PlayerLife.Equipment.options(model.session)
		check(not rows.is_empty(), "legal clothing toggle available")
		if rows.is_empty():
			return
		check(model.act_player_life(rows[0].action_id).success, "clothing change settles")
		check(model.session.elapsed_hours_since_start == (index + 1) / 6, "ordinary world runs only on hour crossings")
		check(model.session.get_time_summary().minute == ((index + 1) * 10) % 60, "minute remainder retained")
	var before: Dictionary = model.session.get_time_summary().duplicate(true)
	var inventory: Array = model.session.stores.item_store.to_save_data().duplicate(true)
	check(not model.act_player_life("equip:missing:main_hand").success, "invalid equipment action rejected")
	check(model.session.get_time_summary() == before, "rejected action does not consume minutes")
	check(model.session.stores.item_store.to_save_data() == inventory, "changing clothes never creates repairs or items")
	var path := "user://tests/roaming_journey/equipped.json"
	check(model.save_to_path(path, true).success, "save equipped minute world")
	var restored := Live.new()
	check(restored.load_from_path(path).success, "restore equipped minute world")
	check(Base.equal_native(model.session.stores.equipment_store.to_save_data(), restored.session.stores.equipment_store.to_save_data()), "native equipment preserved")
	check(restored.session.get_time_summary() == before, "post-boundary clock preserved")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
