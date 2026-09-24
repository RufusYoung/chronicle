extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Contract = preload("res://tests/sim/journey_content_contract_test.gd")
const Journey = preload("res://scripts/sim/player/journey_events.gd")
const Money = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")
var checks := 0
var failures: Array = []
var model: Variant
var transcript: Array = []
var output := "user://tests/journey_life_playthrough"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	model = Live.new()
	var setup: Dictionary = Contract.options()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--journey-seed="):
			setup.challenge_seed_override = int(argument.get_slice("=", 1))
			output += "_" + str(setup.challenge_seed_override)
	check(model.start(setup).success, "legal new adventure starts")
	if not model.is_ready():
		quit(1)
		return
	move("generated_location.echo_landing.landing")
	act("adventure:shore_box:hook")
	move("generated_location.echo_landing.road_yard")
	act("adventure:road_cord:collect")
	if not failures.is_empty():
		quit(1)
		return
	var host: String = model.session.fixture_source_data.journey_generated.bindings.landing_host_actor
	var home: String = model.session.fixture_source_data.journey_generated.bindings.landing_host
	move(home)
	for hour: int in range(18):
		if Journey.host_present(model.session, host) and Journey.within_hours(int(model.session.current_hour), [18, 6]):
			break
		if not Journey.host_present(model.session, host):
			check(not model.session.PlayerLife.Services.options(model.session)[0].can_execute, "absent host cannot sell accommodation")
		model.advance_time(1)
	var coins: int = Money.new(model.session.get_snapshot()).balance("player")
	act("adventure:return_cord:return")
	check(Money.new(model.session.get_snapshot()).balance("player") == coins + 4, "real resident pays for returned rope")
	var give_facts: Array = model.session.stores.fact_store.list_facts().filter(func(f: Dictionary) -> bool: return f.get("fact_type") == "journey_choice" and f.get("event_id") == "return_cord")
	var source: String = give_facts[0].fact_id if not give_facts.is_empty() else ""
	act("adventure:night_talk:listen")
	check("cave_safe_ledge" in Journey.knowledge(model.session).marks, "night conversation provides actionable knowledge")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	check(model.save_to_path(output + "/night_choice.json", true).success, "save before choosing drink versus lodging")
	var drinks: int = Journey.available(model.session, host, "item.hearth_malt_drink")
	act("service:drink")
	check(Journey.available(model.session, host, "item.hearth_malt_drink") == drinks - 1, "tavern consumes finite host-owned drink")
	check(not Journey.current(model.session).get("id") == "night_talk", "same completed conversation does not recur")
	check(not model.act_player_life("service:bed").success, "spending on a drink can leave too little money for a bed")
	check(model.load_from_path(output + "/night_choice.json").success, "alternative legal branch reloads same native night, no injection")
	transcript.append({"branch": "reload night_choice; choose bed instead of drink"})
	var time: int = model.session.elapsed_hours_since_start
	act("service:bed")
	check(model.session.elapsed_hours_since_start == time + 4, "paid bed advances four shared-world hours")
	move("journey_location.lake_cave")
	act("adventure:cave_marks:skip")
	act("adventure:cave_bundle:ledge")
	check(Journey.available(model.session, "player", "item.rescue_harness") == 1, "night knowledge produces a different safe adventure choice")
	move("generated_location.echo_landing.watch_post")
	act("adventure:beacon_marks:study")
	move("journey_location.old_beacon")
	act("adventure:beacon_climb:known")
	act("adventure:beacon_view:remember")
	check(Journey.available(model.session, "player", "item.reed_buckler") == 1, "knowledge opens risk-free route to a usable shield")
	var equips: Array = model.session.PlayerLife.Equipment.options(model.session).filter(func(row: Dictionary) -> bool: return row.item_instance_id != "" and model.session.stores.item_store.get_item(row.item_instance_id).item_def_id == "item.reed_buckler")
	if not equips.is_empty():
		act(str(equips[0].action_id))
	check(not equips.is_empty(), "found equipment can enter existing equipment system")
	move("generated_location.echo_landing.landing")
	transcript.append({"segment": "bounded passive followup observation, not core player journey"})
	for hour: int in range(120):
		var uses: Array = model.session.stores.fact_store.list_facts().filter(func(f: Dictionary) -> bool:
			return f.get("fact_type") == "npc_livelihood_produced" and f.get("actor_id") == host and source in f.get("source_fact_ids", []))
		if not uses.is_empty():
			check(true, "resident naturally uses returned physical rope in later production")
			break
		if hour == 119:
			check(false, "resident naturally uses returned physical rope within 120 hours")
		model.advance_time(1)
	var view: Variant = model.session.PlayerLife.snapshot(model.session.context, model.session.stores, model.session.get_time_summary())
	var reports: Array = model.session.PlayerLife.available_reports(model.session, view).filter(func(row: Dictionary) -> bool: return row.contribution_id == source)
	if not reports.is_empty():
		act("inquire:" + str(reports[0].speaker_id))
	check(not reports.is_empty(), "in-person followup connects the adventure to later resident work")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	check(model.save_to_path(output + "/journey.json", true).success, "legal play native checkpoint")
	var restored := Live.new()
	check(restored.load_from_path(output + "/journey.json").success, "legal play checkpoint restores")
	var file := FileAccess.open(output + "/transcript.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"kind": "scripted_legal_play_not_human", "checks": checks, "failures": failures, "transcript": transcript}, "\t", true, true))
	print("JOURNEY_LIFE_PLAYTHROUGH %d/%d %s" % [checks - failures.size(), checks, str(failures)])
	quit(0 if failures.is_empty() else 1)


func move(target: String) -> void:
	check(Contract.go(model, target), "legal travel: " + target)
	transcript.append({"travel": target, "time": model.session.get_time_summary()})


func act(id: String) -> void:
	var result: Dictionary = model.act_player_life(id)
	if not result.get("success", false):
		print(JSON.stringify(result))
	check(result.get("success", false), "legal action: " + id + " " + str(result.get("error", "")))
	transcript.append({"action": id, "time": model.session.get_time_summary(), "result": result.get("player_life_feedback", result)})


func check(passed: bool, label: String) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures.append(label)
