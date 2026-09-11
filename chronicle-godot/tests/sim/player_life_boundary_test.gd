extends "res://tests/sim/work_recipe_contract_test.gd"

const Life = preload("res://scripts/sim/player/player_life.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "challenge_seed_override": 81001,
		"work_rules_version": 1, "world_danger_version": 1, "player_life_version": 1,
		"household_food_hauling_version": 1, "household_food_budget_version": 1,
		"resident_subsistence_version": 1, "worksite_food_storage_version": 1}).success, "boundary world starts")
	var session: Variant = live.session
	var base: Dictionary = session.fixture_source_data
	for mutation: String in ["missing_profile", "nested_mismatch", "invalid_compiled"]:
		var fixture := base.duplicate(true)
		match mutation:
			"missing_profile":
				fixture.erase("player_life")
				fixture.resident_daily_life.erase("player_life")
			"nested_mismatch": fixture.resident_daily_life.player_life.help_wage = 300
			"invalid_compiled": fixture.player_life_generated.version = 99
		_check(not Session.new().start_from_fixture_data(fixture, []).success, "reject changed behavior bootstrap: " + mutation)
	for route: Dictionary in session.get_travel_options():
		if int(route.hours) > 1:
			_check(session.travel(route.route_id).success, "real mid-route boundary")
			break
	for key: String in ["location_id", "daily_destination_id", "daily_travel_remaining", "settlement_id"]:
		var envelope: Dictionary = session.build_save_envelope()
		envelope.stores.states.player[key] = 99 if key == "daily_travel_remaining" else "missing_place"
		_check(not Session.new().load_from_save_envelope(Saves.new().finalize_envelope(envelope)).success, "reject corrupt body/journey reference: " + key)
	var fixture := base.duplicate(true)
	var profile: Dictionary = fixture.generated_livelihood_profiles.filter(func(p: Dictionary) -> bool: return p.get("occupation_id") == "net_fisher")[0]
	fixture.location_id = profile.workplace_id
	fixture.player.location_id = profile.workplace_id
	fixture.known_facts.append({"fact_id": "test_injection.hire_boundary", "fact_type": "test_injection",
		"summary": "测试注入：把旅人与潜在雇主置于同一作业地，再逐一检查离场、无钱与在途边界。"})
	var employer := _worker(fixture, profile)
	_entity(fixture, employer).states.location_id = profile.workplace_id
	var work_session: Variant = _session(fixture)
	var view: Variant = Life.snapshot(work_session.context, work_session.stores, work_session.get_time_summary())
	var player: Dictionary = view.get_entity("player")
	_check(Life.employers(view, player, Life.PROFILE).any(func(p: Dictionary) -> bool: return p.id == employer), "present funded employer eligible")
	for person: Dictionary in view.entities:
		if person.id == employer:
			person.states.daily_route_id = "test_injection.in_transit"
	_check(not Life.employers(view, player, Life.PROFILE).any(func(p: Dictionary) -> bool: return p.id == employer), "employer in transit is not present")
	var resolved: Dictionary = Life.Livelihood.new().resolve_work_tick(view, work_session.npc_livelihood_profiles,
		{"elapsed_hours": 1}, fixture.resident_daily_life, work_session.registry,
		{"actor": player, "profile": profile, "output_holder": employer})
	_check(resolved.get("error") == "controlled_work_recipient_unavailable", "shared resolver rejects remote delivery too")
	view = Life.snapshot(work_session.context, work_session.stores, work_session.get_time_summary())
	for item: Dictionary in view.items:
		if item.holder.id == employer and item.item_def_id == Life.Food.CURRENCY:
			item.quantity = 0
	_check(not Life.employers(view, player, Life.PROFILE).any(func(p: Dictionary) -> bool: return p.id == employer), "unfunded employer offers no wage")
	_check(Life.Treasury.new(view).balance("player") == 0, "denied work creates no player cash")
	var remote := {"livelihood_results": [{"facts_added": [{"fact_id": "test.remote", "fact_type": "npc_livelihood_produced",
		"location_id": "elsewhere", "summary": "Private remote production"}], "narrative_result": {"summary": "Everyone in the world ate"}}]}
	_check(Life.local_tick_summary(work_session, remote) == "", "worldwide totals and offsite production are not player knowledge")
	remote.livelihood_results[0].facts_added[0].location_id = work_session.context.location_id
	_check(Life.local_tick_summary(work_session, remote) == "Private remote production", "physical local work is visible")
	_finish()
