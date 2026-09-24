extends "res://tests/sim/journey_content_contract_test.gd"

const Session = preload("res://scripts/sim/core/sim_session.gd")
const Tx = preload("res://scripts/sim/transaction/transaction_result.gd")


func run() -> void:
	var model := Live.new()
	check(model.start(options()).success, "controlled counterexample world starts")
	if not model.is_ready():
		quit(1)
		return
	var session: Variant = model.session
	var rules: Dictionary = session.fixture_source_data.journey_rules
	var bad := rules.duplicate(true)
	bad.events[0].choices[0].success["free_gold"] = 100
	check(Setup.validate(bad, session.registry) == "journey_unknown_outcome_field", "unknown reward semantics cannot silently do nothing")
	bad = rules.duplicate(true)
	bad.events[0].choices[0].success.loot[0].quantity = 99
	check(Setup.validate(bad, session.registry) == "journey_loot_exceeds_source", "authored loot cannot exceed physical cache")
	bad = rules.duplicate(true)
	bad.events[0].location = "generated_location.echo_terrace.commons"
	check(Setup.validate(bad, session.registry) == "journey_loot_remote", "event cannot grant remotely stored loot")
	bad = rules.duplicate(true)
	bad.events[0].choices[0].check.difficulty = 1.5
	check(Setup.validate(bad, session.registry) == "journey_check_invalid", "fractional check definition rejected")
	bad = rules.duplicate(true)
	bad.caches[0].items[0] = "not an item"
	check(Setup.validate(bad, session.registry) == "journey_item_invalid", "malformed cache item returns an error rather than a script exception")
	var malformed: Dictionary = session.fixture_source_data.duplicate(true)
	malformed.journey_generated = {"signature": "bad"}
	check(Setup.configure(malformed, session.registry) == "journey_compiled_invalid", "malformed saved compilation fails without script exception")
	var third: Dictionary = session.fixture_source_data.duplicate(true)
	third.journey_rules.events.append({"id": "heldout_listen", "location": "generated_location.echo_landing.commons",
		"title": "Held-out definition", "body": "Data-only listening choice.", "choices": [
			{"id": "listen", "label": "Listen", "hint": "Learn", "hours": 0, "success": {"text": "A route was described.", "marks": ["heldout_route"]}},
			{"id": "leave", "label": "Leave", "hint": "No route", "hours": 0, "success": {"text": "Continue."}}]})
	third.journey_rules.events.append({"id": "heldout_use", "location": "generated_location.echo_landing.commons",
		"title": "Use knowledge", "body": "Only acquired knowledge opens this.", "requires": ["heldout_route"], "choices": [
			{"id": "use", "label": "Use", "hint": "Finish", "hours": 0, "success": {"text": "The information changes the available path."}}]})
	third.journey_generated.signature = Setup._signature(third)
	var extra := Session.new()
	check(extra.start_from_fixture_data(third, session.rule_source_paths).success, "held-out event definitions compile without engine changes")
	check(Journey.current(extra).get("id") == "heldout_listen", "new definition offered through same candidate mechanism")
	var hour: int = extra.elapsed_hours_since_start
	check(Journey.execute(extra, "adventure:heldout_listen:listen").success, "data-only knowledge acquisition")
	check(Journey.current(extra).get("id") == "heldout_use", "new knowledge changes subsequent candidate")
	check(Journey.execute(extra, "adventure:heldout_use:use").success and extra.elapsed_hours_since_start == hour, "distinct zero-time choices have noncolliding facts")
	check(not Journey.execute(extra, "adventure:heldout_listen:listen").success, "resolved data-only choice remains unavailable")
	check(Setup.validate_save(extra.fixture_source_data, extra.stores) == "", "held-out facts and source-linked knowledge validate")
	var decline := Session.new()
	check(decline.start_from_fixture_data(third, session.rule_source_paths).success, "same-start declined branch")
	check(Journey.execute(decline, "adventure:heldout_listen:leave").success, "decline accepted")
	check(Journey.current(decline).is_empty(), "decline does not secretly grant knowledge continuation")
	var host: String = session.fixture_source_data.journey_generated.bindings.landing_host_actor
	var home: String = session.fixture_source_data.journey_generated.bindings.landing_host
	check(go(model, home), "legal route to service location")
	var before: int = session.elapsed_hours_since_start
	check(not model.act_player_life("service:bed").success and session.elapsed_hours_since_start == before, "unfunded or unavailable bed spends no time")
	# Explicit isolated counterexample: moves only this test world's host away.
	var result := Tx.new()
	result.add_state_change({"entity_id": host, "key": "location_id", "to": "generated_location.echo_landing.landing"})
	result.mark_resolved("test_injection.absent_guesthouse_host")
	check(session.writer.apply_result(result, session.stores), "test injection: absent service host")
	var rng: int = session.challenge_rng.state
	check(not session.PlayerLife.Services.execute(session, "service:drink").success, "stale drink request rechecks physical host presence")
	check(session.elapsed_hours_since_start == before and session.challenge_rng.state == rng, "failed service request spends neither time nor RNG")
	print("JOURNEY_COUNTEREXAMPLES %d/%d %s" % [checks - failures.size(), checks, str(failures)])
	quit(0 if failures.is_empty() else 1)
