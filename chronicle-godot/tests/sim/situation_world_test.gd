extends "res://tests/sim/situation_contract_test.gd"

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")


func run() -> void:
	var summaries: Array = []
	for variant: String in ["untouched", "initial_protection", "no_active_threat"]:
		var wall_started := Time.get_ticks_msec()
		var agent := Agent.new()
		var started := request(agent, "start", {"mode": "world", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v1"})
		check(started.ok, "world starts " + variant)
		var session: Variant = agent.model.session
		if variant != "untouched":
			var setup := Result.new()
			var fact_id := "test_injection.initial_conditions." + variant
			setup.add_fact({"fact_id": fact_id, "fact_type": "test_injection", "summary": "测试注入：只更改初始装备或威胁存活状态；规则和后续控制均相同。"})
			if variant == "initial_protection":
				for entity: Dictionary in session.stores.entity_store.list_entities().values():
					if int(session.stores.state_store.get_state(str(entity.id), "age_years", 0)) < 16 or "generated_resident" not in entity.get("tags", []):
						continue
					for item: String in ["item.woven_reed_vest", "item.knotted_fiber_whip"]:
						setup.add_item_change({"operation": "create", "source_fact_ids": [fact_id], "item": {
							"item_instance_id": "test.initial." + str(entity.id) + "." + item, "item_def_id": item,
							"quantity": 1, "holder": {"kind": "entity", "id": entity.id}}})
			else:
				setup.add_state_change({"entity_id": "world_threat.field_boar", "key": "health", "to": 0})
				setup.add_state_change({"entity_id": "world_threat.field_boar", "key": "alive", "to": false})
			setup.mark_resolved("test_injection")
			check(session.writer.apply_result(setup, session.stores), "declared initial-condition variant " + variant)
		var advanced: Dictionary = session.advance_time(72, "passive_situation_world", {"scope_type": "global", "scope_id": ""})
		check(advanced.success, "three autonomous days without any player actions " + variant)
		var facts: Array = session.stores.fact_store.list_facts()
		var summary := {"variant": variant, "requests": 0, "contacts": 0, "equipment": 0, "work": 0, "aid": 0, "repairs": 0}
		for fact: Dictionary in facts:
			var key: String = {"equipment_request": "requests", "world_danger_contact": "contacts", "resident_equipped": "equipment",
				"npc_livelihood_produced": "work", "equipment_given": "aid", "npc_work_maintained": "repairs"}.get(str(fact.get("fact_type", "")), "")
			if key != "":
				summary[key] += 1
			if fact.get("fact_type") == "equipment_request":
				check(not fact.source_fact_ids.is_empty() and fact.source_fact_ids.all(func(id: String) -> bool:
					return facts.any(func(source: Dictionary) -> bool: return source.fact_id == id)), "request has real earlier causal evidence")
		check(session.fixture_source_data.journey_rules.events.is_empty(), "no story IDs in any branch " + variant)
		check(summary.work > 0, "residents continue to work without waiting for player " + variant)
		summaries.append(summary)
		print("SITUATION_WORLD " + JSON.stringify(summary))
		check(session.save_to_path("user://tests/situations/world_" + variant + ".json").ok, "world native save " + variant)
		var restored := Session.new()
		var loaded: Dictionary = restored.load_from_path("user://tests/situations/world_" + variant + ".json")
		check(loaded.get("success", false), "world native restore " + variant + ":" + str(loaded.get("error", "")))
		print("SITUATION_WORLD_TIMING " + JSON.stringify({"variant": variant, "wall_ms": Time.get_ticks_msec() - wall_started}))
	check(summaries[0].requests > 0 and summaries[0].contacts > 0, "unmodified world spontaneously produces the equipment-danger situation")
	check(summaries[1].requests < summaries[0].requests, "initial protection changes later requests under identical rules")
	check(summaries[2].contacts == 0 and summaries[2].requests == 0, "without active danger the supposed story never appears")
	finish()
