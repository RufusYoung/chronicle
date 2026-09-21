extends "res://tests/sim/world_content_contract_test.gd"

const Body = preload("res://scripts/sim/npc/body_condition.gd")
const Needs = preload("res://scripts/sim/npc/npc_need_system.gd")
const Danger = preload("res://scripts/sim/combat/world_danger_system.gd")


func _run() -> void:
	var options := OPTIONS.duplicate(true)
	options.merge({"content_extension_version": 2, "body_rules_version": 1}, true)
	var live := Live.new()
	_check(live.start(options).success, "explicit body world starts")
	if not live.is_ready():
		_finish()
		return
	var session: Variant = live.session
	var base: Dictionary = session.fixture_source_data.duplicate(true)
	_check(base.body_rules_generated.actors.size() == 17, "one shared body rule for sixteen residents and traveller")
	_check(Body.validate_save(base, session.stores) == "", "new body identities valid")
	_check(session.advance_time(47, "unfed_observation").success, "unfed body and autonomous residents advance 47 hours")
	_check(session.get_snapshot().player.health == 92, "ignoring hunger loses real health, not merely a label")
	_check(session.get_snapshot().player.hunger_strain_hours == 5, "partial strain survives between pulses")
	_check(session.save_to_path("user://tests/body_condition/partial.json").ok, "native partial strain saved")
	var restored := Session.new()
	var loaded: Dictionary = restored.load_from_path("user://tests/body_condition/partial.json")
	_check(loaded.success, "native body restored: " + str(loaded.get("error", "")))
	_check(session.advance_time(1, "continue").success and restored.advance_time(1, "continue").success, "both worlds continue")
	_check(session.get_snapshot().player.health == 90 and restored.initialized and _signature(session) == _signature(restored), "native continuation including all residents identical")
	_reject_saves(session)
	_clock_boundary(base)
	_emergency(base)
	_npc_work(base)
	_combat(base)
	options.erase("body_rules_version")
	var old := Live.new()
	_check(old.start(options).success and old.session.advance_time(48, "legacy").success, "old content rules still run")
	_check(old.session.get_snapshot().player.health == 100 and not old.session.fixture_source_data.has("body_rules"), "old worlds do not silently acquire hunger damage")
	var invalid := base.duplicate(true)
	invalid.body_rules.health_floor = 0
	_check(not Session.new().start_from_fixture_data(invalid, []).success, "unversioned lethality change rejected")
	_finish()


func _clock_boundary(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	fixture.player.merge({"hunger": "high", "hunger_elapsed_hours": 5, "health": 41}, true)
	fixture.known_facts.append({"fact_id": "test.body.clock", "fact_type": "test_injection", "summary": "测试注入：同一身体跨越极饿边界，检验批量时间与健康下限。"})
	var session: Variant = _session(fixture)
	var view: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var tick := {"day": 1, "hour": 15, "elapsed_hours": 7, "tick_event_id": "test.body.batch"}
	var data: Dictionary = Needs.new().resolve_tick(view, session.npc_need_profiles, tick, [view.get_entity("player")])
	_check(session.writer.apply_results(data.results, session.stores), "batched need step commits")
	_check(session.get_snapshot().player.health == 40, "only six of seven hours were extreme; hunger alone stops at 40")
	_check(session.get_snapshot().player.get("hunger_strain_hours", 0) == 0, "batch boundary leaves correct partial clock")
	var pulse := Tx.new()
	Life.set_state(pulse, "player", "health", 20)
	pulse.mark_resolved("test_injection")
	_check(session.writer.apply_result(pulse, session.stores), "controlled injury below hunger floor")
	view = Life.snapshot(session.context, session.stores, session.get_time_summary())
	tick.elapsed_hours = 6
	tick.tick_event_id = "test.body.low"
	data = Needs.new().resolve_tick(view, session.npc_need_profiles, tick, [view.get_entity("player")])
	_check(session.writer.apply_results(data.results, session.stores) and session.get_snapshot().player.health == 20, "floor never heals injuries or creates health")


func _emergency(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	fixture.player.merge({"health": 40, "hunger": "extreme", "hunger_elapsed_hours": 0, "fatigue": 0}, true)
	fixture.initial_items = fixture.initial_items.filter(func(i: Dictionary) -> bool: return i.get("holder", {}).get("id") != "player" or i.item_def_id != "item.travel_ration")
	fixture.known_facts.append({"fact_id": "test.body.emergency", "fact_type": "test_injection", "summary": "测试注入：无粮、极饿且健康40的开局，之后全部使用正式行动自救。"})
	var session: Variant = _session(fixture)
	_check(session.get_snapshot().player.food_count == 0, "no free food regranted")
	var routes: Array = session.get_travel_options().filter(func(r: Dictionary) -> bool: return "commons_to_fishery" in r.route_id)
	_check(session.travel(routes[0].route_id).success, "exhausted traveller can physically reach local commons")
	var before: int = session.get_snapshot().player.fatigue
	var rows: Array = Life.options(session).filter(func(r: Dictionary) -> bool: return r.action_id == "gather:net_fisher")
	_check(rows.size() == 1 and rows[0].can_execute and "极饿额外增加2" in rows[0].hint, "emergency gathering remains legal with explicit added fatigue")
	_check(Life.execute(session, "gather:net_fisher").success, "real four-hour gathering")
	_check(session.get_snapshot().player.food_count == 4, "four actual portions, not a free rescue reward")
	_check(session.get_snapshot().player.fatigue == before + 3, "starving work charges actual shared fatigue")
	_check(Life.execute(session, "eat").success, "eat gathered food")
	_check(session.get_snapshot().player.hunger == "medium" and session.get_snapshot().player.health == 40, "eating stops strain but does not instantly heal")
	_check(Life.execute(session, "rest").success, "nourished recovery remains possible")
	_check(session.get_snapshot().player.health > 40 and session.get_snapshot().player.food_count <= 3, "health recovery consumes real nourishment and time")
	_check(session.save_to_path("user://tests/body_condition/emergency.json").ok, "self-rescue world saves")


func _npc_work(base: Dictionary) -> void:
	var profile: Dictionary = base.generated_livelihood_profiles.filter(func(p: Dictionary) -> bool: return p.get("work_recipe", {}).get("recipe_id") == "recipe.net_fishing")[0]
	var id := _worker(base, profile)
	for hunger: String in ["low", "extreme"]:
		var fixture := _at_work(base, id, profile)
		_entity(fixture, id).states.hunger = hunger
		fixture.known_facts.append({"fact_id": "test.body.work", "fact_type": "test_injection", "summary": "测试注入：相同工具与作业进度，仅改变居民饥饿。"})
		var session: Variant = _session(fixture)
		var data: Dictionary = Work.new().resolve_work_tick(_snapshot(session), [profile], _tick(12), fixture.resident_daily_life, session.registry)
		_check(session.writer.apply_results(data.results, session.stores), "NPC work commits " + hunger)
		_check(session.stores.state_store.get_state(id, "fatigue", 0) == (3 if hunger == "extreme" else 1), "NPC has same hunger work cost as player " + hunger)


func _combat(base: Dictionary) -> void:
	var threat: Dictionary = _entity(base, "world_threat.field_boar")
	for id: String in ["player", str(base.body_rules_generated.actors[0])]:
		var scores := {}
		for hunger: String in ["low", "extreme"]:
			var fixture := base.duplicate(true)
			fixture.known_facts.append({"fact_id": "test.body.combat", "fact_type": "test_injection", "summary": "测试注入：相同防守门槛和骰点，只有饥饿不同。"})
			if id == "player":
				fixture.location_id = threat.states.location_id
				fixture.player.merge({"location_id": threat.states.location_id, "hunger": hunger}, true)
			else:
				_entity(fixture, id).states.merge({"location_id": threat.states.location_id, "hunger": hunger, "daily_route_id": ""}, true)
			var session: Variant = _session(fixture)
			var view: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
			var definition: Dictionary = Danger.new().definition(view, id, view.get_entity(str(threat.id)), fixture.world_danger)
			var resolver := Danger.Combat.new()
			resolver.configure(session.registry)
			for approach: String in ["attack", "guard", "withdraw"]:
				var preview: Dictionary = resolver.preview(definition, view, approach, id)
				_check(preview.ok, "public combat preview resolves")
				if hunger == "low":
					scores[approach] = preview.effective_score
				else:
					_check(preview.effective_score == scores[approach] - (0 if approach == "withdraw" else 2), "same-body real score changes, escape kept viable: " + approach)
			var controlled_config: Dictionary = fixture.world_danger.duplicate(true)
			controlled_config.threat.attack = int(scores.guard) + 3
			var result: Variant = Danger.new().resolve_round(view, id, view.get_entity(str(threat.id)), "guard", 3, session.get_time_summary(), controlled_config, session.registry)
			_check(session.writer.apply_result(result, session.stores), "same-roll actual combat commits")
			_check(result.narrative_result.get("outcome") == ("success" if hunger == "low" else "failure"), "hunger changes actual same-roll outcome, not just its preview")


func _reject_saves(session: Variant) -> void:
	var service := preload("res://scripts/sim/save/save_envelope_service.gd").new()
	for value: Variant in [-1, 6, 1.5, "2"]:
		var envelope: Dictionary = session.build_save_envelope()
		envelope.stores.states.player["hunger_strain_hours"] = value
		_check(not Session.new().load_from_save_envelope(service.finalize_envelope(envelope)).success, "invalid body clock rejected: " + str(value))
	var envelope: Dictionary = session.build_save_envelope()
	envelope.stores.states.player.erase("body_rules_version")
	_check(not Session.new().load_from_save_envelope(service.finalize_envelope(envelope)).success, "deleting body flag cannot bypass saved rules")


func _finish() -> void:
	print("BODY_CONDITION_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
