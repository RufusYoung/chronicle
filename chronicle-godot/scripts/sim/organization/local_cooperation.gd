extends RefCounted
class_name V5LocalCooperation

const Knowledge = preload("res://scripts/sim/npc/community_knowledge.gd")
const Life = preload("res://scripts/sim/npc/community_life.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const PROFILE := {"version": 1, "messages_enabled": true, "social_enabled": true, "policy_enabled": true,
	"memory_hours": 48, "observation_hours": 12, "visit_retry_hours": 12,
	"conversation_retry_hours": 8, "maximum_hops": 4, "maximum_reports": 6,
	"minimum_report_trust": 0, "reserve_portions": 6, "open_portions": 2,
	"relief_portions": 1, "policy_review_hours": 12, "aid_enabled": true,
	"aid_portions": 4, "aid_retained_portions": 6, "aid_travel_hours": 6, "aid_retry_hours": 48}


static func validate(config: Variant) -> String:
	if not config is Dictionary:
		return "community_rules_not_dictionary"
	if config.is_empty():
		return ""
	if config.get("version") != 1:
		return "unsupported_community_rules_version"
	for key: String in PROFILE:
		var value: Variant = config.get(key)
		if key.ends_with("_enabled"):
			if not value is bool:
				return "invalid_community_rules_flag:" + key
		elif not (value is int or value is float) or not is_finite(float(value)) or float(value) != float(int(value)) or int(value) < 0:
			return "invalid_community_rules_number:" + key
	if int(config.memory_hours) < 1 or int(config.observation_hours) < 1 or int(config.visit_retry_hours) < 1 \
			or int(config.conversation_retry_hours) < 1 or int(config.maximum_hops) not in range(1, 5) \
			or int(config.maximum_reports) not in range(1, 17) or int(config.policy_review_hours) < 1 \
			or config.reserve_portions < config.open_portions or config.open_portions < config.relief_portions \
			or int(config.aid_portions) < 1 or int(config.aid_travel_hours) < 1 or int(config.aid_retry_hours) < 1:
		return "invalid_community_rules_bounds"
	return ""


static func configure(fixture: Dictionary) -> String:
	var config: Variant = fixture.get("community_rules", {})
	var error := validate(config)
	if error != "" or config.is_empty():
		if config is Dictionary and config.is_empty() and not fixture.get("resident_daily_life", {}).get("community_rules", {}).is_empty():
			return "community_rules_missing_bootstrap_contract"
		return error
	if not fixture.has("work_rules_generated"):
		return "community_rules_require_work_framework"
	if fixture.has("community_generated"):
		if fixture.get("resident_daily_life", {}).get("community_rules", {}) != config or fixture.get("resident_daily_life", {}).get("food_access", {}).get("community_rules", {}) != config:
			return "community_rules_compiled_mismatch"
		for kind: String in ["social", "aid"]:
			if not Knowledge._integer(fixture.resident_daily_life.get("activity_choice", {}).get("weights", {}).get(kind)):
				return "community_rules_missing_choice_weight:" + kind
		return ""
	fixture.resident_daily_life["community_rules"] = config.duplicate(true)
	fixture.resident_daily_life.activity_choice.weights["social"] = 28
	fixture.resident_daily_life.activity_choice.weights["aid"] = 58
	fixture.resident_daily_life.food_access["community_rules"] = config.duplicate(true)
	fixture.resident_daily_life.food_access.adjacent_supply_known = false
	fixture.resident_daily_life.food_access.subsistence["unavailable_quote_version"] = 1
	fixture.resident_daily_life.food_access.household_budget["community_aid_feedback_version"] = 1
	var groups: Array = []
	for site: Dictionary in fixture.get("settlement_network_runtime", {}).get("sites", []):
		var members: Array = fixture.entities.filter(func(e: Dictionary) -> bool:
			return "generated_resident" in e.get("tags", []) and e.get("states", {}).get("settlement_id") == site.settlement_id)
		var adults: Array = members.filter(func(e: Dictionary) -> bool: return int(e.states.get("age_years", 0)) >= 18)
		if adults.is_empty():
			continue
		adults.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var free_a: bool = a.states.get("occupation_id") == "retired"
			var free_b: bool = b.states.get("occupation_id") == "retired"
			return free_a if free_a != free_b else str(a.id) < str(b.id))
		var id := "local_cooperation." + str(site.settlement_id)
		var name := ""
		for entity: Dictionary in fixture.entities:
			if entity.id == site.settlement_id:
				name = str(entity.display_name)
		var group := {"id": id, "type": "institution", "role": "local_cooperation",
			"display_name": name + "互助会", "description": "湖上自由民聚落内形成的地方互助组织，成员保有自己的货物和钱。负责人依据亲闻近况调整售粮约定，约定仍需当面传达。",
			"tags": ["local_cooperation"], "canon_faction_id": "lake_freemen", "settlement_id": site.settlement_id,
			"member_ids": members.map(func(e: Dictionary) -> String: return str(e.id)), "representative_id": adults[0].id,
			"runtime_response": {"cooperation_policy": "open", "policy_fact_id": ""}, "states": {"location_id": site.hub_location_id, "visible": true}}
		fixture.entities.append(group)
		groups.append(id)
	fixture["community_generated"] = {"version": 1, "group_ids": groups,
		"scope": "Generated local freemen mutual-aid groups, not new nations or dwarf/elf institutions. No extra people, money, goods, or distant stock knowledge."}
	return ""


func resolve_tick(snapshot: Variant, tick: Dictionary, config: Dictionary) -> Dictionary:
	var result := Result.new()
	if not Knowledge.enabled(config) or not bool(config.get("policy_enabled", true)):
		return Life._resolved(result)
	var now := Knowledge.hour(tick)
	for group: Dictionary in snapshot.get_entities_by_type("institution"):
		if "local_cooperation" not in group.get("tags", []) or not snapshot.is_entity_active(str(group.id)):
			continue
		var leader: Dictionary = snapshot.get_entity(str(group.representative_id))
		if not Life._present(leader) or leader.states.get("daily_activity") in ["working", "foraging", "resting"]:
			continue
		var previous: Dictionary = {}
		var runtime: Dictionary = group.get("runtime_response", {})
		for fact: Dictionary in snapshot.get_facts_by_actor(str(leader.id)):
			if fact.fact_id == runtime.get("policy_fact_id", ""):
				previous = fact
		if not previous.is_empty() and now - Knowledge.hour(previous) < int(config.policy_review_hours):
			continue
		var own_needs := 0
		var other_needs := 0
		var sources: Array = []
		for memory: Dictionary in Knowledge.latest(snapshot, str(leader.id), now).values():
			if memory.topic != "need":
				continue
			if bool(memory.payload.get("needs_food", false)):
				if memory.subject_id in group.member_ids:
					own_needs += 1
				else:
					other_needs += 1
			sources.append(str(memory.source_fact_id))
		if sources.is_empty():
			continue
		var policy := "reserve" if own_needs > 0 else ("relief" if other_needs > 0 else "open")
		if policy == runtime.get("cooperation_policy") and not previous.is_empty() and now - Knowledge.hour(previous) < int(config.memory_hours):
			continue
		var retained := int(config.reserve_portions if policy == "reserve" else (config.relief_portions if policy == "relief" else config.open_portions))
		var description := "先留住 %d 份口粮，再对外出售" % retained
		if policy == "relief":
			description = "听说邻聚落缺粮，在自己不缺粮时少留一些余粮对外出售"
		var fact := Life._fact("community_policy_changed", str(leader.id), tick)
		fact.merge({"target_id": group.id, "subject_id": group.id, "topic": "policy", "location_id": leader.states.location_id,
			"payload": {"policy": policy, "retained_portions": retained, "description": description},
			"source_fact_ids": sources, "previous_policy": runtime.get("cooperation_policy"),
			"known_member_needs": own_needs, "known_neighbor_needs": other_needs,
			"summary": "%s依据自己听到的近况提出约定：%s。尚未听说的人继续原来的安排。" % [group.display_name, description]})
		result.add_fact(fact)
		result.add_memory(Life.direct_memory(fact, int(config.memory_hours)))
		result.add_entity_change({"operation": "update", "entity_id": group.id,
			"fields": {"runtime_response": {"cooperation_policy": policy, "policy_fact_id": fact.fact_id}}, "source_fact_ids": [fact.fact_id]})
	return Life._resolved(result)


static func validate_references(fixture: Dictionary, stores: Dictionary, locations: Dictionary) -> String:
	for id: Variant in fixture.get("community_generated", {}).get("group_ids", []):
		var group: Dictionary = stores.entity_store.get_entity(str(id))
		if "local_cooperation" not in group.get("tags", []) or not group.get("member_ids") is Array or group.member_ids.is_empty() \
				or group.get("representative_id") not in group.member_ids or not locations.has(str(stores.state_store.get_state(str(id), "location_id", ""))):
			return "save_community_group_invalid"
		var seen := {}
		for member: Variant in group.member_ids:
			if not member is String or seen.has(member) or stores.entity_store.get_entity(str(member)).get("type") != "person":
				return "save_community_members_invalid"
			seen[member] = true
		if int(stores.state_store.get_state(str(group.representative_id), "age_years", 0)) < 18:
			return "save_community_representative_invalid"
		var runtime: Dictionary = group.get("runtime_response", {})
		if runtime.get("cooperation_policy") not in ["open", "reserve", "relief"]:
			return "save_community_policy_invalid"
		var source := str(runtime.get("policy_fact_id", ""))
		if source == "":
			if runtime.cooperation_policy != "open":
				return "save_community_policy_without_source"
			continue
		var fact: Dictionary = stores.fact_store.get_fact(source)
		if fact.get("fact_type") != "community_policy_changed" or fact.get("actor_id") != group.representative_id \
				or fact.get("subject_id") != id or fact.get("payload", {}).get("policy") != runtime.cooperation_policy:
			return "save_community_policy_source_invalid"
	for memory: Dictionary in stores.memory_store.memories:
		if memory.get("memory_type") != "community_aid_received":
			continue
		var taken: Dictionary = stores.fact_store.get_fact(str(memory.get("source_fact_id", "")))
		var receipt: Dictionary = stores.fact_store.get_fact(str(memory.get("delivery_fact_id", "")))
		if taken.get("fact_type") != "household_pantry_taken" or taken.get("actor_id") != memory.get("owner_id") \
				or receipt.get("fact_type") != "food_hauling_stocked" or not receipt.has("community_request_id") \
				or receipt.get("payer_id") != memory.get("target_id") or receipt.get("pantry_id") != taken.get("pantry_id") \
				or receipt.get("fact_id") not in taken.get("source_fact_ids", []):
			return "save_community_receipt_memory_invalid"
	return ""
