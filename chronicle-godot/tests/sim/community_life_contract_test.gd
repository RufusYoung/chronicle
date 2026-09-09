extends "res://tests/sim/work_recipe_contract_test.gd"

const Knowledge = preload("res://scripts/sim/npc/community_knowledge.gd")
const CommunityLife = preload("res://scripts/sim/npc/community_life.gd")
const Community = preload("res://scripts/sim/organization/local_cooperation.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Subsistence = preload("res://scripts/sim/npc/resident_subsistence.gd")
const Daily = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
const Choice = preload("res://scripts/sim/npc/resident_activity_choice.gd")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "challenge_seed_override": 81001, "work_rules_version": 1,
		"community_rules_version": 1, "household_food_hauling_version": 1, "household_food_budget_version": 1,
		"resident_subsistence_version": 1, "worksite_food_storage_version": 1}).success, "explicit community world starts")
	if not live.is_ready():
		_finish()
		return
	var base: Dictionary = live.session.fixture_source_data.duplicate(true)
	_check(base.community_generated.group_ids.size() == 2, "two local groups share actual generated residents, no extra civilization")
	_check(not base.resident_daily_life.food_access.adjacent_supply_known, "distant supply is not known at bootstrap")
	var legacy := Live.new()
	_check(legacy.start({"scenario": "echo_realm", "work_rules_version": 1}).success, "legacy work world still starts")
	_check(not legacy.session.fixture_source_data.has("community_generated"), "old rules do not gain messages or groups")
	for key: String in ["memory_hours", "maximum_hops", "maximum_reports"]:
		var invalid := Community.PROFILE.duplicate(true)
		invalid[key] = -1
		_check(Community.validate(invalid) != "", "reject malformed community config: " + key)
	var profile: Dictionary = base.generated_livelihood_profiles.filter(func(p: Dictionary) -> bool: return p.get("work_recipe", {}).get("recipe_id") == "recipe.net_fishing")[0]
	var seller := _worker(base, profile)
	var foreign: Dictionary = base.entities.filter(func(e: Dictionary) -> bool:
		return "generated_resident" in e.get("tags", []) and e.states.settlement_id != profile.settlement_id and int(e.states.age_years) >= 18)[0]
	_messages(base, seller, str(foreign.id), profile)
	_service_contact(base, seller, str(foreign.id), profile)
	_policy(base, seller, str(foreign.id), profile)
	_unavailable(base, str(foreign.id), profile)
	_check(CommunityLife._same_payload({"portions_seen": 1.0, "food_available": false}, {"portions_seen": 1, "food_available": false}), "native numeric type does not duplicate observation")
	_finish()


func _service_contact(base: Dictionary, seller: String, buyer: String, profile: Dictionary) -> void:
	var fixture := _meeting_fixture(base, seller, buyer, profile)
	_entity(fixture, seller).states.daily_activity = "working"
	_entity(fixture, buyer).states.daily_activity = "seeking_work"
	var session: Variant = _session(fixture)
	var tick := {"day": 3, "hour": 12}
	var observations := CommunityLife.new().observe(_snapshot(session), tick, fixture.community_rules)
	_check(session.writer.apply_results(observations.results, session.stores), "worksite owner observes actual supplies")
	var conversations := CommunityLife.new().converse(_snapshot(session), tick, fixture.community_rules)
	_check(session.writer.apply_results(conversations.results, session.stores), "ordinary service contact shares information")
	_check(not Knowledge.supply_reports(_snapshot(session), buyer, Knowledge.hour(tick)).is_empty(), "job enquiry is not an information dead end")
	_check(session.stores.state_store.get_state(seller, "daily_activity", "") == "socializing", "receiving a service conversation suspends that hour's production")
	var invalid: Dictionary = fixture.duplicate(true)
	invalid.resident_daily_life.community_rules.messages_enabled = false
	_check(Community.configure(invalid) == "community_rules_compiled_mismatch", "native bootstrap cannot disagree with compiled community rules")
	var config: Dictionary = fixture.community_rules.duplicate(true)
	config.maximum_hops = 5
	_check(Community.validate(config) != "", "message relay remains bounded")


func _messages(base: Dictionary, seller: String, buyer: String, profile: Dictionary) -> void:
	var fixture := _meeting_fixture(base, seller, buyer, profile)
	var session: Variant = _session(fixture)
	var config: Dictionary = fixture.community_rules
	var tick := {"day": 3, "hour": 12, "elapsed_hours": 1}
	var snapshot: Variant = _snapshot(session)
	var food_config: Dictionary = fixture.resident_daily_life.food_access
	_check(profile.workplace_id not in Food.known_supply_locations(snapshot, snapshot.get_entity(buyer), fixture.generated_livelihood_profiles, session.settlement_network_runtime, food_config, tick), "foreign inventory is unknown before hearing")
	var observed := CommunityLife.new().observe(snapshot, tick, config)
	_check(session.writer.apply_results(observed.results, session.stores), "private own observations commit")
	snapshot = _snapshot(session)
	_check(Knowledge.supply_reports(snapshot, buyer, Knowledge.hour(tick)).is_empty(), "another person's private observation does not leak")
	var conversations := CommunityLife.new().converse(snapshot, tick, config)
	_check(session.writer.apply_results(conversations.results, session.stores), "co-present conversation transfers reports")
	snapshot = _snapshot(session)
	var reports := Knowledge.supply_reports(snapshot, buyer, Knowledge.hour(tick))
	_check(reports.size() == 1 and reports[0].hops == 1, "receiver has one first-hand relayed supply report")
	_check(profile.workplace_id in Food.known_supply_locations(snapshot, snapshot.get_entity(buyer), fixture.generated_livelihood_profiles, session.settlement_network_runtime, food_config, tick), "heard location opens a real food search candidate")
	if not reports.is_empty():
		_check(reports[0].expires_hour == Knowledge.hour(tick) + int(config.memory_hours), "relaying does not refresh original expiry")
		_check(Knowledge.supply_reports(snapshot, buyer, int(reports[0].expires_hour)).is_empty(), "expired report cannot guide a new trip")
		_check(Knowledge.validate_memory(reports[0], session.stores, session.context.locations) == "", "message has a valid native evidence chain")
		var forged: Dictionary = reports[0].duplicate(true)
		forged.observed_hour = Knowledge.hour(tick) + 1
		_check(Knowledge.validate_memory(forged, session.stores, session.context.locations) != "", "reject future observation")
		forged = reports[0].duplicate(true)
		forged.payload.food_available = false
		_check(Knowledge.validate_memory(forged, session.stores, session.context.locations) != "", "reject payload detached from actual witness")
		forged = reports[0].duplicate(true)
		forged.expires_hour += 1
		_check(Knowledge.validate_memory(forged, session.stores, session.context.locations) != "", "reject relaying that extends expiry")
		_check(Knowledge.validate_memory(reports[0], session.stores, session.context.locations, config, Knowledge.hour(tick) - 1) != "", "reject a message learned after world time")
	_check(session.save_to_path("user://tests/community_life/messages.json").ok, "community native save")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/community_life/messages.json").success, "community native load")
	_check(_signature(session) == _signature(restored), "community full native state roundtrip")
	var remote := _meeting_fixture(base, seller, buyer, profile)
	_entity(remote, buyer).states.location_id = str(_entity(remote, buyer).states.home_location_id)
	var remote_session: Variant = _session(remote)
	_check(CommunityLife.new().converse(_snapshot(remote_session), tick, config).events.all(func(f: Dictionary) -> bool:
		return f.fact_type != "community_conversation" or not (f.actor_id == buyer and f.target_id == seller)), "distant actors do not converse")
	var distrusted := _meeting_fixture(base, seller, buyer, profile)
	var distrusted_session: Variant = _session(distrusted)
	var distrust := Result.new()
	distrust.add_relationship_change({"source_id": buyer, "target_id": seller, "axis": "trust", "to": -10})
	_check(distrusted_session.writer.apply_result(distrust, distrusted_session.stores), "test injection: receiver distrusts speaker")
	var data := CommunityLife.new().observe(_snapshot(distrusted_session), tick, config)
	_check(distrusted_session.writer.apply_results(data.results, distrusted_session.stores), "distrusted speaker still privately observes")
	data = CommunityLife.new().converse(_snapshot(distrusted_session), tick, config)
	_check(distrusted_session.writer.apply_results(data.results, distrusted_session.stores), "conversation can happen without accepting reports")
	_check(Knowledge.supply_reports(_snapshot(distrusted_session), buyer, Knowledge.hour(tick)).is_empty(), "negative trust blocks adoption of supply report")
	var actor: Dictionary = snapshot.get_entity(buyer)
	_check(CommunityLife.proposals(snapshot, actor, tick, config, session.settlement_network_runtime).is_empty(), "just conversed, company need is satisfied")
	_check(not CommunityLife.proposals(snapshot, actor, {"day": 7, "hour": 12}, config, session.settlement_network_runtime).is_empty(), "unmet company need later creates real visit candidates")


func _policy(base: Dictionary, seller: String, buyer: String, profile: Dictionary) -> void:
	var group: Dictionary = base.entities.filter(func(e: Dictionary) -> bool: return "local_cooperation" in e.get("tags", []) and seller in e.member_ids)[0]
	var leader := str(group.representative_id)
	if leader == seller:
		leader = str(base.entities.filter(func(e: Dictionary) -> bool:
			return e.id != seller and e.id in group.member_ids and int(e.get("states", {}).get("age_years", 0)) >= 18)[0].id)
	var fixture := _meeting_fixture(base, seller, leader, profile)
	_entity(fixture, str(group.id)).representative_id = leader
	_entity(fixture, seller).states.daily_activity = "socializing"
	_entity(fixture, leader).states.hunger = "high"
	_entity(fixture, leader).states.daily_activity = "home"
	_entity(fixture, buyer).states.location_id = profile.workplace_id
	_entity(fixture, buyer).states.daily_activity = "seeking_food"
	var session: Variant = _session(fixture)
	var tick := {"day": 3, "hour": 12, "elapsed_hours": 1}
	var config: Dictionary = fixture.community_rules
	var food_config: Dictionary = fixture.resident_daily_life.food_access
	var snapshot: Variant = _snapshot(session)
	var before := Food.new()._seller_offers(snapshot, snapshot.get_entity(seller), buyer, Storage.depot_id(seller), profile.workplace_id, food_config, session.stores, {}, false, tick)
	_check(not before.is_empty() and int(before[0].surplus) == 3, "before hearing restriction seller offers actual surplus")
	var observations := CommunityLife.new().observe(snapshot, tick, config)
	_check(session.writer.apply_results(observations.results, session.stores), "representative observes own actual hunger")
	var policies := Community.new().resolve_tick(_snapshot(session), tick, config)
	_check(session.writer.apply_results(policies.results, session.stores), "local shortage changes group policy via transaction")
	_check(Knowledge.known_policy(_snapshot(session), seller, Knowledge.hour(tick)).is_empty(), "policy does not telepathically reach members")
	var conversation := CommunityLife.new().converse(_snapshot(session), tick, config)
	_check(session.writer.apply_results(conversation.results, session.stores), "policy travels through actual meeting")
	snapshot = _snapshot(session)
	var known := Knowledge.known_policy(snapshot, seller, Knowledge.hour(tick))
	_check(not known.is_empty() and known.payload.policy == "reserve", "member now knows reserve rule")
	var after := Food.new()._seller_offers(snapshot, snapshot.get_entity(seller), buyer, Storage.depot_id(seller), profile.workplace_id, food_config, session.stores, {}, false, tick)
	_check(after.is_empty(), "heard reserve rule actually prevents foreign purchase of reserved food")
	var late := {"day": 6, "hour": 12, "elapsed_hours": 1}
	after = Food.new()._seller_offers(snapshot, snapshot.get_entity(seller), buyer, Storage.depot_id(seller), profile.workplace_id, food_config, session.stores, {}, false, late)
	_check(not after.is_empty(), "outdated rule knowledge cannot permanently freeze trade")


func _unavailable(base: Dictionary, actor_id: String, profile: Dictionary) -> void:
	var fixture := _meeting_fixture(base, actor_id, _worker(base, profile), profile)
	_entity(fixture, actor_id).states.hunger = "high"
	var session: Variant = _session(fixture)
	var config: Dictionary = fixture.resident_daily_life.food_access.subsistence
	var tick := {"day": 3, "hour": 12, "elapsed_hours": 1}
	var observation := Food.new()._unmet(_snapshot(session).get_entity(actor_id), profile.workplace_id, "no_local_surplus", tick)
	_check(session.writer.apply_result(observation.transaction, session.stores), "test injection: a real-style failed local quote is recorded")
	var snapshot: Variant = _snapshot(session)
	var decision := Subsistence.decision(snapshot, snapshot.get_entity(actor_id), snapshot.get_items_for_holder(actor_id), {}, config, tick)
	_check(not decision.is_empty() and observation.transaction.facts_added[0].fact_id in decision.source_fact_ids, "having coins no longer blocks adaptive self-provisioning after no stock")
	var legacy_config := config.duplicate(true)
	legacy_config.erase("unavailable_quote_version")
	_check(Subsistence.decision(snapshot, snapshot.get_entity(actor_id), snapshot.get_items_for_holder(actor_id), {}, legacy_config, tick).is_empty(), "old subsistence rule remains unchanged")


func _meeting_fixture(base: Dictionary, seller: String, buyer: String, profile: Dictionary) -> Dictionary:
	var fixture := base.duplicate(true)
	fixture["world_time"] = {"day": 3, "hour": 12}
	for id: String in [seller, buyer]:
		_entity(fixture, id).states.merge({"location_id": profile.workplace_id, "daily_route_id": "", "daily_activity": "home", "hunger": "low"}, true)
	_entity(fixture, buyer).states.daily_activity = "socializing"
	fixture.initial_items.append({"item_instance_id": "test.community.food", "item_def_id": "item.fresh_fish_portion",
		"quantity": 5, "holder": {"kind": "entity", "id": Storage.depot_id(seller)}})
	fixture.known_facts.append({"fact_id": "test_injection.community_fixture", "fact_type": "test_injection", "summary": "测试注入：控制人物到场、食物和身体状态，验证消息与交易规则，不是自然模拟。"})
	return fixture
