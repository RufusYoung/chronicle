extends "res://tests/sim/work_recipe_contract_test.gd"

const Danger = preload("res://scripts/sim/combat/world_danger_system.gd")
const DangerSetup = preload("res://scripts/sim/combat/world_danger_setup.gd")


func _run() -> void:
	var live := Live.new()
	var started: Dictionary = live.start({"scenario": "echo_realm", "challenge_seed_override": 81001,
		"work_rules_version": 1, "world_danger_version": 1, "household_food_hauling_version": 1,
		"household_food_budget_version": 1, "resident_subsistence_version": 1, "worksite_food_storage_version": 1})
	_check(started.get("success", false), "explicit danger world starts: " + str(started.get("error", "")))
	if not live.is_ready():
		_finish()
		return
	var session: Variant = live.session
	var base: Dictionary = session.fixture_source_data
	_check(base.world_danger_generated.threat_ids.size() == 1, "finite threat exists before any actor meets it")
	_check(session.get_combat_encounter_options().is_empty(), "distant threat cannot offer a player fight")
	var advanced: Dictionary = session.advance_time(72, "passive_danger_test", {"scope_type": "global", "scope_id": ""})
	_check(advanced.get("success", false), "three autonomous days: " + str(advanced.get("error_reason", "")))
	var facts: Array = session.stores.fact_store.list_facts()
	for kind: String in ["world_danger_contact", "world_danger_round", "actor_injured_during_combat", "actor_rested_with_injury"]:
		var rows: Array = facts.filter(func(row: Dictionary) -> bool: return row.get("fact_type") == kind)
		print("DANGER_NATURAL ", kind, " ", rows.size())
		_check(not rows.is_empty(), "natural world produces " + kind)
	_check(session.save_to_path("user://tests/world_danger/day3.json").ok, "native save")
	var restored := Session.new()
	var loaded: Dictionary = restored.load_from_path("user://tests/world_danger/day3.json")
	_check(loaded.get("success", false), "native restore: " + str(loaded.get("error", "")))
	if loaded.get("success", false):
		session.advance_time(1, "continue", {"scope_type": "global", "scope_id": ""})
		restored.advance_time(1, "continue", {"scope_type": "global", "scope_id": ""})
		_check(_signature(session) == _signature(restored), "all native stores and clocks continue identically")
	_round_cases(base)
	_equipment_case(base)
	_unfed_rest_case(base)
	_rejected_saves(session)
	_finish()


func _round_cases(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	var threat_id := "world_threat.field_boar"
	var threat: Dictionary = _entity(fixture, threat_id)
	var actor: Dictionary = fixture.entities.filter(func(row: Dictionary) -> bool:
		return "generated_resident" in row.get("tags", []) and row.states.workplace_id == threat.territory_id)[0]
	actor.states.merge({"location_id": threat.territory_id, "daily_route_id": "", "health": 100, "fatigue": 0, "dexterity": 12, "perception": 12}, true)
	fixture.known_facts.append({"fact_id": "test_injection.world_danger", "fact_type": "test_injection",
		"summary": "测试注入：控制双方到场与骰点，验证连续战斗和伤后合同。"})
	var session: Variant = _session(fixture)
	if not session.initialized:
		return
	var tick := {"day": 1, "hour": 10}
	var snapshot: Variant = _snapshot(session)
	var system := Danger.new()
	var config: Dictionary = fixture.world_danger
	var initial_health := int(snapshot.get_entity_state(threat_id, "health", 0))
	var result: Variant = system.resolve_round(snapshot, actor.id, snapshot.get_entity(threat_id), "guard", 6, tick, config, session.registry)
	_check(session.writer.apply_result(result, session.stores), "guard uses ordinary transaction")
	_check(session.stores.state_store.get_state(actor.id, "danger_advantage", 0) == 2, "guard creates a real next-round advantage")
	_check(session.stores.state_store.get_state(threat_id, "health", 0) == initial_health, "guard does not invent attack damage")
	tick.hour = 11
	snapshot = _snapshot(session)
	var preview: Dictionary = system.options(snapshot, actor.id, tick, config, session.registry)[0].preview
	_check(preview.effective_score >= preview.base_score, "guard advantage enters the shared attack contract")
	result = system.resolve_round(snapshot, actor.id, snapshot.get_entity(threat_id), "attack", 6, tick, config, session.registry)
	_check(session.writer.apply_result(result, session.stores), "attack commits")
	_check(session.stores.state_store.get_state(threat_id, "health", 0) < initial_health, "attack changes persistent threat health")
	_check(session.stores.state_store.get_state(actor.id, "danger_advantage", 0) == 0, "attack spends preparation")
	tick.hour = 12
	snapshot = _snapshot(session)
	result = system.resolve_round(snapshot, actor.id, snapshot.get_entity(threat_id), "withdraw", 6, tick, config, session.registry)
	_check(session.writer.apply_result(result, session.stores), "withdrawal commits")
	_check(session.stores.state_store.get_state(actor.id, "location_id", "") == threat.territory_id, "withdrawal does not teleport home")
	_check(session.stores.state_store.get_state(actor.id, "danger_opponent_id", "bad") == "", "successful withdrawal ends current engagement")
	_check(Danger.opponent(_snapshot(session), actor.id, tick, config).is_empty(), "withdrawal grants a real departure window")
	var dead: Dictionary = threat.duplicate(true)
	dead.states.alive = false
	_check(not Danger.active(dead, tick, config), "an entity marked dead cannot threaten anyone")


func _equipment_case(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	var actor: Dictionary = fixture.entities.filter(func(row: Dictionary) -> bool:
		return "generated_resident" in row.get("tags", []) and row.states.get("occupation_id") == "terrace_farmer")[0]
	var id := str(actor.id)
	var enemy := "world_threat.field_boar"
	actor.states.merge({"location_id": _entity(fixture, enemy).territory_id, "daily_route_id": "", "health": 100,
		"strength": 8, "dexterity": 6, "perception": 6, "constitution": 10, "fatigue": 0}, true)
	fixture.known_facts.append({"fact_id": "test_injection.equipment", "fact_type": "test_injection", "summary": "测试注入：仅比较同一身体穿戴装备前后的战斗，不是自然拾取。"})
	var bare: Variant = _session(fixture)
	fixture.initial_items.append({"item_instance_id": "test.spear", "item_def_id": "item.outpost_boar_spear",
		"holder": {"kind": "entity", "id": id}, "quantity": 1})
	fixture.initial_items.append({"item_instance_id": "test.armor", "item_def_id": "item.waxed_winter_cloak",
		"holder": {"kind": "entity", "id": id}, "quantity": 1})
	fixture.initial_equipment_loadouts.append({"entity_id": id, "slots": {"main_hand": "test.spear", "body_outer": "test.armor"}})
	var armed: Variant = _session(fixture)
	if not bare.initialized or not armed.initialized:
		return
	var tick := {"day": 1, "hour": 10}
	var system := Danger.new()
	var a: Dictionary = system.options(_snapshot(bare), id, tick, fixture.world_danger, bare.registry)[0].preview
	var b: Dictionary = system.options(_snapshot(armed), id, tick, fixture.world_danger, armed.registry)[0].preview
	_check(int(b.effective_score) - int(a.effective_score) == 6, "NPC weapon base bonus and conditional anti-charge passive both apply")
	var result: Variant = system.resolve_round(_snapshot(armed), id, _snapshot(armed).get_entity(enemy), "attack", 1, tick, fixture.world_danger, armed.registry)
	_check(armed.writer.apply_result(result, armed.stores), "armed NPC attack commits")
	_check(result.narrative_result.outcome == "success", "equipment changes same-body low-roll outcome")
	_check(armed.stores.item_store.get_item("test.spear").condition.durability == 89, "actual equipped weapon wears")
	tick.hour = 11
	result = system.resolve_round(_snapshot(armed), id, _snapshot(armed).get_entity(enemy), "withdraw", 1, tick, fixture.world_danger, armed.registry)
	_check(armed.writer.apply_result(result, armed.stores), "failed withdrawal commits injury through shared resolver")
	_check(armed.stores.item_store.get_item("test.armor").condition.durability == 98, "body_outer armor receives real damage, not a nonexistent body slot")
	_check(Danger.wounds(_snapshot(armed), id).size() == 1, "injury belongs to NPC CharacterFeatureStore")
	var absent: Variant = _snapshot(bare)
	var invalid: Variant = system.resolve_round(absent, "generated_resident.echo_landing.001", absent.get_entity(enemy), "attack", 6, tick, fixture.world_danger, bare.registry)
	_check(invalid.contract_status == "invalid_contract", "remote actor cannot attack this threat")


func _unfed_rest_case(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	fixture.initial_items = fixture.initial_items.filter(func(item: Dictionary) -> bool:
		return item.get("holder", {}).get("id") != "player" or item.item_def_id != "item.travel_ration")
	fixture.player.merge({"health": 80, "fatigue": 3}, true)
	fixture.known_facts.append({"fact_id": "test_injection.unfed_rest", "fact_type": "test_injection", "summary": "测试注入：无口粮且疲劳的身体，只应恢复疲劳。"})
	var session: Variant = _session(fixture)
	_check(session.recover_from_danger().get("success", false), "unfed rest remains a legal way to reduce fatigue")
	_check(session.get_snapshot().get_player_value("health") == 80, "unfed rest cannot create health recovery")
	_check(session.get_snapshot().get_player_value("fatigue") == 2, "unfed rest reduces actual fatigue")
	_check(session.get_snapshot().get_player_value("food_count") == 0, "compiled bootstrap and rest cannot regrant starting food")
	fixture = base.duplicate(true)
	fixture.player.merge({"health": 100, "fatigue": 3}, true)
	session = _session(fixture)
	_check(session.recover_from_danger().get("success", false), "healthy but tired actor can rest")
	_check(session.get_snapshot().get_player_value("food_count") == 2 and session.get_snapshot().get_player_value("fatigue") == 2, "fatigue-only rest does not waste scarce recovery food")


func _rejected_saves(session: Variant) -> void:
	var envelope: Dictionary = session.build_save_envelope()
	var service := preload("res://scripts/sim/save/save_envelope_service.gd").new()
	var memory_index := -1
	for i: int in range(envelope.stores.memories.size()):
		if envelope.stores.memories[i].get("memory_type") == "world_danger_seen":
			memory_index = i
			break
	_check(memory_index >= 0, "native world has real private danger memories")
	if memory_index >= 0:
		var invalid := envelope.duplicate(true)
		invalid.stores.memories[memory_index].expires_hour += 1000
		_check(not Session.new().load_from_save_envelope(service.finalize_envelope(invalid)).get("success", false), "cannot extend remembered danger forever by editing a native save")
	var invalid := envelope.duplicate(true)
	invalid.stores.states.player["danger_opponent_id"] = "world_threat.field_boar"
	_check(not Session.new().load_from_save_envelope(service.finalize_envelope(invalid)).get("success", false), "cannot restore an opponent at a different location")
	invalid = envelope.duplicate(true)
	var traits: Array = invalid.stores.character_features.trait_instances
	if not traits.is_empty():
		traits[0]["recovery_progress"] = 12
		traits[0]["stage_id"] = "healed"
		traits[0]["status"] = "resolved"
		_check(not Session.new().load_from_save_envelope(service.finalize_envelope(invalid)).get("success", false), "cannot fabricate twelve recovery hours without their actual source facts")
		traits[0].erase("recovery_fact_ids")
		_check(not Session.new().load_from_save_envelope(service.finalize_envelope(invalid)).get("success", false), "deleting recovery provenance cannot bypass native validation")
