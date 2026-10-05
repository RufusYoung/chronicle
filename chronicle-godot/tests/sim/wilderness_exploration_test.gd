extends "res://tests/sim/interest_pursuit_test.gd"

const Wild = preload("res://scripts/sim/player/wilderness_exploration.gd")
const ShoreSetup = preload("res://scripts/sim/generation/wilderness_setup.gd")
const SHORE := "wilderness_location.north_shore_breach"


func _run() -> void:
	var game := NewAgent.new()
	var response := _call(game, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81002, "economy_variant": "world_situation_v4"})
	_check(response.ok, "explicit wilderness world starts: " + str(response.get("error", "")))
	if not response.ok:
		_finish()
		return
	var session: Variant = game.model.session
	_check(response.observation.wilderness.is_empty(), "remote site does not expose live stock or water")
	_check(session.fixture_source_data.journey_rules.events.is_empty(), "no authored event tree restored")
	var native: Dictionary = session.fixture_source_data.duplicate(true)
	var route := "wilderness_route.generated_location.echo_landing.commons." + SHORE
	response = _act_offered(game, response, route)
	_check(response.ok and response.observation.location.id == SHORE, "formal road reaches canon-anchored generated detail")
	_check(response.choices.filter(func(c: Dictionary) -> bool: return c.kind == "travel").size() == 2, "arrival has two real exits, not a forced return dead end")
	_check(response.observation.wilderness.features.all(func(f: Dictionary) -> bool: return not f.surveyed and f.items.is_empty()), "unknown contents stay hidden before survey")
	_check(Presentation.build(response).body.contains("眼前水况") and Presentation.build(response).choices.any(func(c: Dictionary) -> bool: return c.id == "shore_survey:rubble"), "same public surface presents conditions and legal survey")
	var before := _signature(session)
	_call(game, "observe")
	Wild.outlook(session)
	_check(_signature(session) == before, "observation is read only, including RNG")
	response = _act_offered(game, response, "shore_survey:rubble")
	_check(response.ok and response.observation.wilderness.features[0].surveyed, "real ten-minute survey reveals actual items")
	_check(not response.choices.any(func(c: Dictionary) -> bool: return c.id == "shore_survey:rubble"), "unchanged survey option disappears")
	_check(_call(game, "save", {"slot": "wilderness_survey", "overwrite": true}).ok, "wilderness native checkpoint")
	var restored := _call(game, "load", {"slot": "wilderness_survey"})
	if not restored.ok:
		print("RESTORE_ERROR ", restored.get("error", ""))
	elif restored.observation != response.observation:
		for key: String in response.observation:
			if response.observation[key] != restored.observation.get(key):
				print("RESTORE_DIFF ", key, " ", JSON.stringify(response.observation[key]), " / ", JSON.stringify(restored.observation.get(key)))
	_check(restored.ok and restored.observation == response.observation, "native resume preserves stock knowledge, water and choices")
	var sample := _controlled(native, true)
	_success_and_failure(sample)
	_environment(sample)
	_empty_and_third_definition(native)
	var old := NewAgent.new()
	var legacy := _call(old, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81002, "economy_variant": "world_situation_v3"})
	_check(legacy.ok and not old.model.session.fixture_source_data.has("wilderness_rules"), "v3 does not silently gain new world rules")
	_check(not old.model.session.context.locations.has(SHORE), "old geography is preserved")
	_check(_call(old, "save", {"slot": "wilderness_legacy_v3", "overwrite": true}).ok, "old utility world saves")
	_check(_call(old, "load", {"slot": "wilderness_legacy_v3"}).ok and not old.model.session.fixture_source_data.has("wilderness_rules"), "old native save stays old")
	var damaged := native.duplicate(true)
	damaged.wilderness_rules.sites[0].hours = 0
	_check(not Session.new().start_from_fixture_data(damaged, []).success, "invalid route time rejected")
	damaged = native.duplicate(true)
	damaged.wilderness_rules.sites[0].id = "bad:site"
	_check(not Session.new().start_from_fixture_data(damaged, []).success, "site delimiter cannot produce ambiguous action IDs")
	damaged = native.duplicate(true)
	damaged.wilderness_rules.sites[0].features[0].id = "bad:feature"
	_check(not Session.new().start_from_fixture_data(damaged, []).success, "feature delimiter rejected before action parsing")
	damaged = native.duplicate(true)
	damaged.initial_items.filter(func(i: Dictionary) -> bool: return str(i.item_instance_id).begins_with("wilderness_deposit."))[0].quantity += 1
	_check(not Session.new().start_from_fixture_data(damaged, []).success, "changed frozen deposit rejected")
	_finish()


func _controlled(base: Dictionary, with_rope: bool) -> Dictionary:
	var fixture := base.duplicate(true)
	fixture.location_id = SHORE
	fixture.player.merge({"location_id": SHORE, "fatigue": 0, "dexterity": 20, "health": 100, "hunger": "none"}, true)
	fixture.world_time = {"day": 1, "hour": 10}
	fixture.wilderness_generated.sites.north_shore_breach.phase_offset = 0
	fixture.initial_items = fixture.initial_items.filter(func(i: Dictionary) -> bool: return not str(i.item_instance_id).begins_with("wilderness_deposit."))
	var id := "wilderness_deposit.north_shore_breach.rubble.item.test"
	fixture.initial_items.append({"item_instance_id": id, "item_def_id": "item.reed_quarterstaff", "quantity": 1,
		"holder": {"kind": "entity", "id": "wilderness_deposit.north_shore_breach.rubble"}})
	fixture.wilderness_generated.item_ids = [id]
	if with_rope:
		fixture.initial_items.append({"item_instance_id": "test.wilderness.rope", "item_def_id": "item.light_reed_cord", "quantity": 2,
			"holder": {"kind": "entity", "id": "player"}, "condition": {"durability": 2}})
	fixture.wilderness_generated.signature = ShoreSetup.signature(fixture)
	fixture.known_facts.append({"fact_id": "test.wilderness.fixture", "fact_type": "test_injection", "summary": "测试注入：声明体力、属性、实物与水况初态，不是自然发现。"})
	return fixture


func _success_and_failure(fixture: Dictionary) -> void:
	var session: Variant = _session(fixture)
	_check(Wild.execute(session, "shore_survey:rubble").success, "controlled survey executes")
	var before := _signature(session)
	_check(not Wild.execute(session, "shore_survey:rubble").success and _signature(session) == before, "repeat survey rejected without time charge")
	var option: Dictionary = Wild.options(session).filter(func(r: Dictionary) -> bool: return r.action_id.ends_with(":rope"))[0]
	var hand: Dictionary = Wild.options(session).filter(func(r: Dictionary) -> bool: return r.action_id.ends_with(":hand"))[0]
	_check(option.minutes > hand.minutes and option.hint.contains("磨损1") and hand.hint.contains("耗2疲劳"), "two methods expose different real costs")
	var response := Wild.execute(session, option.action_id)
	_check(response.success and response.player_life_feedback.title.contains("取回"), "successful check takes a real item")
	_check(session.stores.item_store.get_item("wilderness_deposit.north_shore_breach.rubble.item.test").holder.id == "player", "physical item transferred, not minted reward")
	_check(Wild.stock(session, "wilderness_deposit.north_shore_breach.rubble").is_empty(), "deposit depleted")
	_check(session.stores.item_store.get_item("test.wilderness.rope").quantity == 1 and session.stores.item_store.get_item("test.wilderness.rope").condition.durability == 2, "only one rope split from stack")
	_check(session.stores.item_store.list_items_for_owner("player").any(func(i: Dictionary) -> bool: return i.item_def_id == "item.light_reed_cord" and i.condition.durability == 1), "used rope really wears")
	_check(int(session.stores.state_store.get_state("player", "fatigue", 0)) == 1, "rope method actual fatigue consumer")
	_check(Wild.options(session).all(func(r: Dictionary) -> bool: return not str(r.action_id).begins_with("shore_take:rubble")), "empty deposit cannot be harvested again")
	_check(session.save_to_path("user://tests/wilderness/depleted.json").ok, "depleted native save")
	var loaded := Session.new()
	_check(loaded.load_from_path("user://tests/wilderness/depleted.json").success, "depleted native restore")
	_check(_signature(loaded) == _signature(session) and Wild.stock(loaded, "wilderness_deposit.north_shore_breach.rubble").is_empty(), "restore neither replenishes goods nor repairs tools")
	_check(Wild.notes(loaded).all(func(n: Dictionary) -> bool: return n.items.all(func(i: Dictionary) -> bool: return i.quantity == 0)), "remembered survey subtracts own later collection without reading remote stock")
	_check(loaded.travel("wilderness_route." + SHORE + ".generated_location.echo_landing.commons").success, "leave with recovered item")
	_check(loaded.travel("wilderness_route.generated_location.echo_landing.commons." + SHORE).success and Wild.stock(loaded, "wilderness_deposit.north_shore_breach.rubble").is_empty(), "physically returning does not respawn stock")
	var broken := fixture.duplicate(true)
	broken.player.dexterity = 1
	var failed: Variant = _session(broken)
	Wild.execute(failed, "shore_survey:rubble")
	var offered: Dictionary = Wild.options(failed).filter(func(r: Dictionary) -> bool: return r.action_id.ends_with(":hand"))[0]
	var attempt := Wild.execute(failed, offered.action_id)
	_check(attempt.success and attempt.player_life_feedback.title == "失足后撤回", "failed check is a settled physical result, not protocol error")
	_check(failed.stores.state_store.get_state("player", "health", 100) < 100 and not Wild.stock(failed, "wilderness_deposit.north_shore_breach.rubble").is_empty(), "failure hurts body but does not invent or destroy loot")
	_check(Wild.options(failed).filter(func(r: Dictionary) -> bool: return r.action_id == offered.action_id).all(func(r: Dictionary) -> bool: return not r.can_execute), "failed footing prevents immediate bare-handed reroll loop")
	_check(failed.get_travel_options().any(func(r: Dictionary) -> bool: return r.can_travel), "failure leaves a legal physical exit")
	# The caller's fixture contains test rope; explicitly remove that controlled input.
	var dry := _controlled(fixture, false)
	dry.initial_items = dry.initial_items.filter(func(i: Dictionary) -> bool: return i.item_instance_id != "test.wilderness.rope")
	var missing: Variant = _session(dry)
	Wild.execute(missing, "shore_survey:rubble")
	_check(Wild.options(missing).filter(func(r: Dictionary) -> bool: return r.action_id.ends_with(":rope")).all(func(r: Dictionary) -> bool: return not r.can_execute), "missing rope is denied without free equipment")
	before = _signature(missing)
	_check(not Wild.execute(missing, option.action_id).success and before == _signature(missing), "unoffered rope attempt has no side effects")
	var move := Result.new()
	move.add_state_change({"entity_id": "wilderness_deposit.north_shore_breach.rubble", "key": "location_id", "to": "generated_location.echo_landing.commons"})
	move.mark_resolved("test_injection")
	_check(missing.writer.apply_result(move, missing.stores), "test injection: container moved away")
	_check(not Wild.options(missing).any(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("shore_take:rubble")), "remote container is not readable or lootable through stale feature binding")


func _environment(fixture: Dictionary) -> void:
	var session: Variant = _session(fixture)
	var site := Wild.site_here(session)
	var before := _signature(session)
	var dry := Wild.conditions(session, site)
	_check(dry.phase == 0 and Wild.conditions(session, site, 120).phase == 1 and Wild.conditions(session, site, 240).phase == 2, "water changes with shared elapsed clock, not visit flags")
	_check(before == _signature(session), "forecast does not advance or mutate world")
	var feature: Dictionary = site.features[1]
	var item: Dictionary = session.stores.item_store.get_item("wilderness_deposit.north_shore_breach.rubble.item.test")
	session.elapsed_hours_since_start = 4
	_check(Wild.attempt_plan(session, site, feature, item, "rope").denial.contains("淹没"), "test injection: high water rejects narrow ledge even with rope")
	_check(session.get_travel_options().all(func(r: Dictionary) -> bool: return r.can_travel), "high-water denial never traps actor behind imaginary route lock")
	session.elapsed_hours_since_start = 6
	_check(Wild.attempt_plan(session, site, feature, item, "rope").denial == "", "later retreating water reopens same physical access")
	var waited := Wild.execute(session, "shore_wait")
	_check(waited.success and waited.minutes == 120 and Wild.conditions(session, site).phase == 1, "wait-to-water uses formal shared world ticks and stops at visible phase change")
	_check(waited.player_life_feedback.body.contains("回水"), "waiting outcome states what actually changed")


func _empty_and_third_definition(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	fixture.wilderness_rules.sites[0].features.append({"id": "test_ridge", "name": "测试注入第三地形", "description": "仅验证相同规则。", "exposure": 1, "items": []})
	for id: String in fixture.wilderness_generated.sites.values().map(func(s: Dictionary) -> String: return str(s.location_id)):
		fixture.locations.erase(id)
	fixture.entities = fixture.entities.filter(func(e: Dictionary) -> bool: return e.id not in fixture.wilderness_generated.entity_ids)
	fixture.initial_items = fixture.initial_items.filter(func(i: Dictionary) -> bool: return i.item_instance_id not in fixture.wilderness_generated.item_ids)
	fixture.travel_routes = fixture.travel_routes.filter(func(r: Dictionary) -> bool: return r.route_id not in fixture.wilderness_generated.route_ids)
	fixture.erase("wilderness_generated")
	var session: Variant = _session(fixture)
	_check(session.travel("wilderness_route.generated_location.echo_landing.commons." + SHORE).success, "third definition reached through formal travel")
	_check(Wild.execute(session, "shore_survey:test_ridge").success, "third data-only feature uses shared survey")
	_check(Wild.outlook(session).body.contains("已查过，眼下没有可取的东西"), "empty prospect is disclosed, not filled with guaranteed reward")
	_check(Wild.options(session).all(func(r: Dictionary) -> bool: return not str(r.action_id).contains("test_ridge")), "empty observation closes without a task-completion reward")


func _finish() -> void:
	print("WILDERNESS_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
