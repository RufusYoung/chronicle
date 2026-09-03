extends SceneTree

const Session = preload("res://scripts/sim/core/sim_session.gd")
const Industry = preload("res://scripts/sim/settlement/industry_lifecycle_system.gd")
const Catalog = preload("res://scripts/sim/settlement/industry_runtime_catalog.gd")
const Capacity = preload("res://scripts/sim/settlement/settlement_capacity_adaptation_system.gd")
const Work = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const Writer = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const FIXTURE := "res://data/sim/fixtures/generated_settlement_network_fixture.json"
const RULES := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json"
]
const SAVE := "user://tests/generated_industry_lifecycle.save.json"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = _start()
	var network: Dictionary = session.get_settlement_network_summary()
	var site: Dictionary = (network.get("sites", []) as Array)[0]
	var settlement := str(site.get("settlement_id", ""))
	_check(
		(
			_facts(session, "settlement_industry_founded").is_empty()
			and _profile(session, settlement, "cordage_maker").is_empty()
		),
		"initially absent industry has no phantom workplace or worker"
	)
	_tick(session, network, 1)
	_tick(session, network, 2)
	_check(
		_facts(session, "settlement_industry_founded").is_empty(),
		"demand alone cannot create an industry without practical experience"
	)
	_work(session, 12, 100)
	_check_work_day_scoring(session, network, settlement)
	var stocks_before: Dictionary = Capacity.new()._available_resource_amounts(_snapshot(session))
	_tick(session, network, 3)
	var founded := _facts(session, "settlement_industry_founded")
	_check(
		founded.size() == 1,
		"sustained risk, earned work experience and materials found one local industry"
	)
	if founded.is_empty():
		_finish()
		return
	var fact: Dictionary = founded[0]
	var founding_capacity: Array = _facts(session, "settlement_work_capacity_changed").filter(func(row: Dictionary) -> bool:
		return str(row.get("reason", "")) == "industry_founded")
	_check(founding_capacity.size() == 1 and "新产业开办" in str(founding_capacity[0].get("summary", "")),
		"new industry capacity receipt explains formation, not nonexistent unemployment pressure")
	var facility := str(fact.get("facility_entity_id", ""))
	var founder := str(fact.get("actor_id", ""))
	var construction_stock: Dictionary = session.stores["resource_stock_store"].get_stock(
		str(fact.get("resource_stock_id", ""))
	)
	_check(
		is_equal_approx(
			(
				float(stocks_before.get(str(fact.get("resource_stock_id", "")), 0))
				- float(construction_stock.get("current", 0))
			),
			float(fact.get("resource_cost", 0))
		),
		"construction material debit exactly matches the receipt"
	)
	var profile := _profile(session, settlement, "cordage_maker")
	_check(
		(
			not profile.is_empty()
			and (
				str(session.stores["state_store"].get_state(founder, "occupation_id", ""))
				== "cordage_maker"
			)
		),
		"founder actually changes occupation and joins the new workplace"
	)
	_check(
		_sources_exist(session, fact) and float(fact.get("resource_cost", 0)) > 0,
		"foundation cites real work and demand evidence and consumes construction materials"
	)
	var before: Dictionary = session.get_store_snapshots()
	_tick(session, network, 3)
	_check(
		before == session.get_store_snapshots(),
		"replaying the same daily evaluation does not duplicate construction or charges"
	)
	var routes: Array = session.get_travel_options()
	var has_route := routes.any(func(row: Dictionary) -> bool:
		return str(row.get("route_id", "")) == facility + ".visit")
	_check(
		has_route,
		"new workplace is reachable from the existing hub"
	)
	_check(
		bool(session.save_to_path(SAVE).get("ok", false)),
		"active industry saves through the normal envelope"
	)
	var restored = Session.new()
	_check(
		(
			bool(restored.load_from_path(SAVE).get("success", false))
			and _equivalent(restored.get_save_store_data(), session.get_save_store_data())
		),
		"active facility, profiles, employment and receipts survive save/load exactly"
	)
	var envelope: Dictionary = session.build_save_envelope({"source_kind": "test_fixture"})
	for corruption: String in ["resource", "product", "source", "location", "shape"]:
		var broken := envelope.duplicate(true)
		var broken_profile: Dictionary = broken["stores"]["entities"][facility]["industry_profile"]
		match corruption:
			"resource": broken_profile["resource_inputs"][0]["stock_id"] = "missing.stock"
			"product": broken_profile["products"][0]["item_def_id"] = "item.missing"
			"source": broken_profile["industry_source_fact_id"] = "missing.fact"
			"location": broken_profile["workplace_id"] = "missing.location"
			"shape": broken_profile["resource_inputs"] = "invalid"
		broken = session.save_envelope_service.finalize_envelope(broken)
		var rejected = Session.new()
		var load_report: Dictionary = rejected.load_from_save_envelope(broken)
		_check(
			str(load_report.get("phase", "")) == "references"
			and str(load_report.get("error", "")).begins_with("save_industry_")
			and not rejected.is_ready(),
			"invalid runtime industry profile is rejected during load: " + corruption
		)
	_work(restored, 12, 200)
	var has_production := _facts(restored, "npc_livelihood_produced").any(func(row: Dictionary) -> bool:
		return str(row.get("actor_id", "")) == founder and str(row.get("occupation_id", "")) == "cordage_maker")
	_check(
		has_production,
		"loaded new occupation produces through the existing livelihood system"
	)
	for link: Dictionary in network.get("links", []):
		link["risk"] = 0
	_tick(session, network, 4)
	_tick(session, network, 5)
	_check(
		_facts(session, "settlement_industry_retired").is_empty(),
		"brief demand loss does not instantly erase an industry"
	)
	_tick(session, network, 6)
	var retired_capacity: Array = _facts(session, "settlement_work_capacity_changed").filter(func(row: Dictionary) -> bool:
		return str(row.get("reason", "")) == "industry_retired")
	_check(retired_capacity.size() == 1 and "停止经营" in str(retired_capacity[0].get("summary", "")),
		"retirement capacity receipt describes closed jobs, not negative expansion")
	_check(
		(
			_facts(session, "settlement_industry_retired").size() == 1
			and _profile(session, settlement, "cordage_maker").is_empty()
		),
		"sustained demand loss retires the industry and removes recruitable profiles"
	)
	_check(
		(
			(
				str(session.stores["state_store"].get_state(founder, "livelihood_status", ""))
				== "unemployed"
			)
			and not bool(
				session.stores["state_store"].get_state(facility, "facility_operational", true)
			)
		),
		"retirement closes the facility and lays off its real worker"
	)
	var has_ruin_route: bool = session.get_travel_options().any(func(row: Dictionary) -> bool:
		return str(row.get("route_id", "")) == facility + ".visit" and "旧址" in str(row.get("label", "")))
	_check(
		has_ruin_route,
		"retired premises remain visitable historical places"
	)
	var count_before := _facts(session, "npc_livelihood_produced").size()
	_work(session, 1, 300)
	_check(
		_facts(session, "npc_livelihood_produced").slice(count_before).all(
			func(row: Dictionary) -> bool: return str(row.get("actor_id", "")) != founder
		),
		"retired workers cannot continue producing from stale startup profiles"
	)
	_check(bool(session.save_to_path(SAVE).get("ok", false)), "retired industry saves")
	var retired_restored = Session.new()
	_check(
		(
			bool(retired_restored.load_from_path(SAVE).get("success", false))
			and _equivalent(retired_restored.get_save_store_data(), session.get_save_store_data())
			and _profile(retired_restored, settlement, "cordage_maker").is_empty()
		),
		"loading cannot reopen a retired industry"
	)
	for link: Dictionary in network.get("links", []):
		link["risk"] = 5
	_tick(session, network, 7)
	_check(
		_facts(session, "settlement_industry_founded").size() == 1,
		"reentry cooldown prevents next-day reconstruction"
	)
	_tick(session, network, 8)
	var histories := _facts(session, "settlement_industry_founded")
	var new_profile := _profile(session, settlement, "cordage_maker")
	_check(
		(
			histories.size() == 2
			and str(histories[1].get("workplace_id", "")) != str(fact.get("workplace_id", ""))
			and (
				(
					int(new_profile.get("maximum_slots", 0))
					+ Capacity.new()._occupation_capacity_delta(
						_snapshot(session), settlement, "cordage_maker"
					)
				)
				== 2
			)
		),
		"renewed conditions pay for a distinct site with correct capacity, without erasing the old ruin"
	)
	var unused: Dictionary = Capacity.new()._next_construction_plot(
		session.context.get_locations(), Capacity.new()._built_plots(_snapshot(session)), settlement
	)
	_check(
		(
			str(unused.get("id", ""))
			not in [
				str(fact.get("workplace_id", "")), str(histories.back().get("workplace_id", ""))
			]
		),
		"housing and industry share land and do not overwrite active sites or ruins"
	)
	_counterfactuals()
	_initial_industry_retirement()
	var world = _start()
	_check(
		(
			bool(world.advance_time(24 * 4, "industry_contract").get("success", false))
			and not _facts(world, "settlement_industry_founded").is_empty()
		),
		"formal WorldTick discovers and founds the industry without manual lifecycle calls"
	)
	_check(
		bool(
			world.save_to_path("user://tests/generated_industry_active.save.json").get("ok", false)
		),
		"world-tick result is available for render verification"
	)
	_finish()


func _counterfactuals() -> void:
	for kind: String in ["no_demand", "no_materials", "no_land", "rejected_transaction"]:
		var session = _start()
		var network: Dictionary = session.get_settlement_network_summary()
		_work(session, 12, 400)
		if kind == "no_demand":
			for link: Dictionary in network.get("links", []):
				link["risk"] = 0
		_tick(session, network, 1)
		if kind == "no_materials":
			_drain_materials(session)
		var data: Dictionary = Industry.new().resolve_daily_tick(
			_snapshot(session),
			{"day": 2},
			network,
			session.npc_livelihood_profiles,
			[] if kind == "no_land" else session.context.get_locations()
		)
		if kind == "rejected_transaction":
			_drain_materials(session)
			var before: Dictionary = session.get_store_snapshots()
			_check(
				(
					not Writer.new().apply_results(data.get("results", []), session.stores)
					and session.get_store_snapshots() == before
				),
				"failed preflight leaves no half-created facility, job, fact or material charge"
			)
		else:
			_check(
				(
					Writer.new().apply_results(data.get("results", []), session.stores)
					and _facts(session, "settlement_industry_founded").is_empty()
				),
				kind + " blocks formation"
			)
	var session = _start()
	_work(session, 12, 500)
	var network: Dictionary = session.get_settlement_network_summary()
	var site: Dictionary = network["sites"][1]
	var prototype: Dictionary = (network["industry_archetypes"] as Array).filter(func(row: Dictionary) -> bool: return str(row.get("industry_id", "")) == "cordage")[0]
	var rules: Dictionary = network["industry_lifecycle"]["conditions"]["cordage"]
	var snapshot = _snapshot(session)
	var stock: Dictionary = Capacity.new()._select_construction_stock(
		snapshot,
		str(site["settlement_id"]),
		4.0,
		Capacity.new()._available_resource_amounts(snapshot)
	)
	_check(
		(
			not stock.is_empty()
			and (
				Industry
				. new()
				. _candidate(
					snapshot,
					network,
					site,
					prototype,
					rules,
					network["industry_lifecycle"],
					{"value": 5},
					Capacity.new()._available_resource_amounts(snapshot)
				)
				. is_empty()
			)
		),
		"construction timber cannot substitute for missing production fiber"
	)


func _initial_industry_retirement() -> void:
	var session = _start()
	var network: Dictionary = session.get_settlement_network_summary()
	var settlement := str(network["sites"][0]["settlement_id"])
	network["industry_lifecycle"]["conditions"] = {
		"fishery": {"demand_tags": ["food"], "entry_demand_at_least": 999, "exit_demand_below": 0}
	}
	var profile := _profile(session, settlement, "net_fisher")
	var stock_id := str(profile["resource_inputs"][0]["stock_id"])
	var facility := Capacity.new()._facility_entity_id(
		_snapshot(session), str(profile["workplace_id"])
	)
	session.stores["resource_stock_store"].apply_resource_change(
		{"stock_id": stock_id, "operation": "set", "amount": 0.0}
	)
	for day: int in range(1, 4):
		_tick(session, network, day)
	_check(
		_profile(session, settlement, "net_fisher").is_empty(),
		"startup industries can also retire after prolonged resource loss"
	)
	session.stores["resource_stock_store"].apply_resource_change(
		{"stock_id": stock_id, "operation": "set", "amount": 10.0}
	)
	var data: Dictionary = Capacity.new().resolve_daily_tick(
		_snapshot(session),
		{"day": 4},
		network,
		session.npc_livelihood_profiles,
		session.context.get_locations()
	)
	_check(
		(
			Writer.new().apply_results(data.get("results", []), session.stores)
			and not bool(
				session.stores["state_store"].get_state(facility, "facility_operational", true)
			)
			and _profile(session, settlement, "net_fisher").is_empty()
		),
		"ordinary resource recovery cannot resurrect a retired startup industry"
	)


func _check_work_day_scoring(session: Variant, network: Dictionary, settlement: String) -> void:
	var snapshot = _snapshot(session)
	var config: Dictionary = network["industry_lifecycle"]
	var rules: Dictionary = config["conditions"]["cordage"]
	var normal: Dictionary = Industry.new()._experienced_founder(snapshot, settlement, rules, config)
	var other: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "npc_livelihood_produced"
			and str(fact.get("actor_id", "")) != str(normal.get("resident_id", ""))
			and str(snapshot.get_entity_state(str(fact.get("actor_id", "")), "settlement_id", "")) == settlement
			and str(fact.get("occupation_id", "")) in rules["experience_occupations"]
		):
			other = fact
			break
	for index: int in 100:
		var extra := other.duplicate(true)
		extra["fact_id"] = "fact.test.same_day_cycle.%d" % index
		snapshot.facts.append(extra)
	var with_extra_cycles: Dictionary = Industry.new()._experienced_founder(snapshot, settlement, rules, config)
	_check(
		not other.is_empty() and not normal.is_empty()
		and str(normal.get("resident_id", "")) == str(with_extra_cycles.get("resident_id", "")),
		"test-injected extra cycles on the same day cannot outweigh actual days of practice"
	)


func _start() -> Variant:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var config: Dictionary = fixture["settlement_network_generation"]["industry_lifecycle"]
	config["entry_days_required"] = 2
	config["exit_days_required"] = 3
	config["reentry_cooldown_days"] = 2
	config["minimum_experience_cycles"] = 1
	config["organization_coordination_max_reduction_days"] = 0
	config["conditions"] = {"cordage": config["conditions"]["cordage"]}
	config["conditions"]["cordage"]["demand_kind"] = "route_risk"
	fixture["settlement_network_generation"]["autonomous_pressure"]["enabled"] = false
	for link: Dictionary in fixture["settlement_network_generation"]["links"]:
		link["risk"] = 5
	var session = Session.new()
	_check(
		bool(session.start_from_fixture_data(fixture, RULES).get("success", false)),
		"fixture starts"
	)
	return session


func _snapshot(session: Variant) -> Variant:
	return session.snapshot_builder.build_snapshot(session.context, session.stores, true)


func _tick(session: Variant, network: Dictionary, day: int) -> void:
	var data: Dictionary = Industry.new().resolve_daily_tick(
		_snapshot(session),
		{"day": day},
		network,
		session.npc_livelihood_profiles,
		session.context.get_locations()
	)
	var writer = Writer.new()
	_check(
		writer.apply_results(data.get("results", []), session.stores),
		"industry day %d commits: %s" % [day, JSON.stringify(writer.last_report)]
	)


func _work(session: Variant, hours: int, sequence: int) -> void:
	for hour: int in range(hours):
		var data: Dictionary = Work.new().resolve_work_tick(
			_snapshot(session),
			session.npc_livelihood_profiles,
			{
				"day": 1,
				"elapsed_hours": 1,
				"tick_event_id": "industry_test_%d_%d" % [sequence, hour]
			}
		)
		var writer = Writer.new()
		if not writer.apply_results(data.get("results", []), session.stores):
			_check(false, JSON.stringify(writer.last_report))


func _profile(session: Variant, settlement: String, occupation: String) -> Dictionary:
	for profile: Dictionary in Catalog.profiles(
		_snapshot(session), session.npc_livelihood_profiles
	):
		if (
			str(profile.get("settlement_id", "")) == settlement
			and str(profile.get("occupation_id", "")) == occupation
		):
			return profile
	return {}


func _facts(session: Variant, type: String) -> Array:
	return session.stores["fact_store"].list_facts().filter(
		func(row: Dictionary) -> bool: return str(row.get("fact_type", "")) == type
	)


func _sources_exist(session: Variant, fact: Dictionary) -> bool:
	var ids: Array = session.stores["fact_store"].list_facts().map(
		func(row: Dictionary) -> String: return str(row.get("fact_id", ""))
	)
	return (fact.get("source_fact_ids", []) as Array).all(
		func(id: Variant) -> bool: return str(id) in ids
	)


func _drain_materials(session: Variant) -> void:
	for stock: Dictionary in session.stores["resource_stock_store"].list_stocks():
		if Capacity.new()._has_any_tag(stock.get("tags", []), Capacity.CONSTRUCTION_TAGS):
			session.stores["resource_stock_store"].apply_resource_change(
				{"stock_id": stock.get("stock_id", ""), "operation": "set", "amount": 0.0}
			)


func _check(condition: bool, message: String) -> void:
	print("[INDUSTRY %s] %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		failures.append(message)


func _equivalent(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _finish() -> void:
	print("[INDUSTRY RESULT] %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
