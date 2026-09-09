extends RefCounted
class_name V5CommunityKnowledge

const MEMORY_TYPE := "community_report"


static func hour(tick: Dictionary) -> int:
	return int(tick.get("day", 1)) * 24 + int(tick.get("hour", 0))


static func enabled(config: Dictionary) -> bool:
	return config.get("version", 0) == 1


static func latest(snapshot: Variant, owner: String, now: int) -> Dictionary:
	var rows := {}
	for memory: Dictionary in snapshot.get_memories(owner):
		if memory.get("memory_type") != MEMORY_TYPE:
			continue
		var key := str(memory.topic) + ":" + str(memory.subject_id)
		if int(memory.learned_hour) > now:
			continue
		if not rows.has(key) or int(memory.observed_hour) > int(rows[key].observed_hour) \
				or (memory.observed_hour == rows[key].observed_hour and int(memory.hops) < int(rows[key].hops)):
			rows[key] = memory
	for key: String in rows.keys():
		if int(rows[key].expires_hour) <= now:
			rows.erase(key)
	return rows


static func supply_reports(snapshot: Variant, owner: String, now: int) -> Array:
	return latest(snapshot, owner, now).values().filter(func(m: Dictionary) -> bool:
		return m.topic == "supply" and bool(m.payload.get("food_available", false)))


static func sources_at(snapshot: Variant, owner: String, location: String, now: int) -> Array:
	var sources: Array = []
	for report: Dictionary in supply_reports(snapshot, owner, now):
		if report.location_id == location and report.source_fact_id not in sources:
			sources.append(str(report.source_fact_id))
	return sources


static func group_for(snapshot: Variant, person: String) -> Dictionary:
	for group: Dictionary in snapshot.get_entities_by_type("institution"):
		if "local_cooperation" in group.get("tags", []) and person in group.get("member_ids", []) \
				and snapshot.is_entity_active(str(group.id)):
			return group
	return {}


static func known_policy(snapshot: Variant, person: String, now: int) -> Dictionary:
	var group := group_for(snapshot, person)
	if group.is_empty():
		return {}
	return latest(snapshot, person, now).get("policy:" + str(group.id), {})


static func validate_memory(memory: Dictionary, stores: Dictionary, locations: Dictionary, config: Dictionary = {}, now: int = -1) -> String:
	if memory.get("memory_type") != MEMORY_TYPE:
		return ""
	for key: String in ["observed_hour", "learned_hour", "expires_hour", "hops"]:
		var value: Variant = memory.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != float(int(value)) or int(value) < 0:
			return "save_community_memory_time_invalid"
	if memory.observed_hour > memory.learned_hour or memory.expires_hour <= memory.observed_hour or int(memory.hops) > int(config.get("maximum_hops", 4)):
		return "save_community_memory_time_invalid"
	if int(memory.expires_hour) != int(memory.observed_hour) + int(config.get("memory_hours", 48)) or (now >= 0 and int(memory.learned_hour) > now):
		return "save_community_memory_time_invalid"
	if memory.get("topic") not in ["supply", "need", "policy"] or not memory.get("payload") is Dictionary \
			or not locations.has(str(memory.get("location_id", ""))):
		return "save_community_memory_shape_invalid"
	var payload: Dictionary = memory.payload
	if memory.topic == "need" and (not payload.get("needs_food") is bool or not payload.get("family_need") is bool):
		return "save_community_memory_payload_invalid"
	if payload.has("meeting_location_id") and not locations.has(str(payload.meeting_location_id)):
		return "save_community_memory_payload_invalid"
	if memory.topic == "supply" and (not payload.get("food_available") is bool or not _integer(payload.get("portions_seen"))):
		return "save_community_memory_payload_invalid"
	if memory.topic == "policy" and (payload.get("policy") not in ["open", "reserve", "relief"] or not _integer(payload.get("retained_portions"))):
		return "save_community_memory_payload_invalid"
	for key: String in ["owner_id", "subject_id", "reporter_id"]:
		if not stores.entity_store.has_entity(str(memory.get(key, ""))):
			return "save_community_memory_person_unknown"
		if (key != "subject_id" or memory.topic != "policy") and stores.entity_store.get_entity(str(memory[key])).get("type") != "person":
			return "save_community_memory_person_unknown"
	var fact: Dictionary = stores.fact_store.get_fact(str(memory.get("source_fact_id", "")))
	var root: Dictionary = stores.fact_store.get_fact(str(memory.get("root_fact_id", "")))
	if fact.is_empty() or root.is_empty() or memory.source_fact_id not in memory.get("source_fact_ids", []) \
			or root.get("fact_type") not in ["community_observation", "community_policy_changed"]:
		return "save_community_memory_source_invalid"
	if root.get("topic") != memory.topic or root.get("subject_id") != memory.subject_id \
			or root.get("payload") != memory.payload or hour(root) != int(memory.observed_hour) \
			or root.get("location_id") != memory.location_id:
		return "save_community_memory_root_mismatch"
	if payload.has("delivery_request"):
		if not payload.delivery_request is Dictionary:
			return "save_community_delivery_request_invalid"
		var request: Dictionary = payload.delivery_request
		var pantry: Dictionary = stores.entity_store.get_entity(str(request.get("pantry_id", "")))
		var observation: Dictionary = stores.fact_store.get_fact(str(request.get("pantry_source_fact_id", "")))
		if not _integer(request.get("quantity")) or int(request.quantity) < 1 or not request.get("recipient_ids") is Array \
				or request.recipient_ids.is_empty() or observation.get("fact_type") != "household_pantry_observed" \
				or observation.get("actor_id") != memory.subject_id or observation.get("pantry_id") != request.pantry_id \
				or observation.fact_id not in root.get("source_fact_ids", []) or hour(observation) > hour(root) \
				or int(request.quantity) > int(observation.get("missing_portions", 0)) \
				or pantry.get("stock_location_id") != request.get("home_location_id") or "household_food_store" not in pantry.get("tags", []):
			return "save_community_delivery_request_invalid"
		var seen := {}
		for recipient: Variant in request.recipient_ids:
			if not recipient is String or seen.has(recipient) or recipient not in observation.get("recipient_ids", []):
				return "save_community_delivery_request_invalid"
			seen[recipient] = true
	if int(memory.hops) == 0:
		if fact != root or fact.get("actor_id") != memory.owner_id or memory.reporter_id != memory.owner_id:
			return "save_community_direct_observation_invalid"
	elif fact.get("fact_type") != "community_message_heard" or fact.get("actor_id") != memory.owner_id \
			or fact.get("target_id") != memory.reporter_id or fact.get("root_fact_id") != memory.root_fact_id \
			or int(fact.get("hops", -1)) != int(memory.hops) or hour(fact) != int(memory.learned_hour):
		return "save_community_transmission_invalid"
	var current := fact
	var hops := int(memory.hops)
	while hops > 0:
		var sources: Array = current.get("source_fact_ids", [])
		if sources.size() != 2:
			return "save_community_transmission_invalid"
		var conversation: Dictionary = stores.fact_store.get_fact(str(sources[0]))
		var previous: Dictionary = stores.fact_store.get_fact(str(sources[1]))
		if conversation.get("fact_type") != "community_conversation" or conversation.get("actor_id") != current.get("actor_id") \
				or conversation.get("target_id") != current.get("target_id") or conversation.get("location_id") != current.get("location_id") \
				or hour(conversation) != hour(current) or previous.get("actor_id") != current.get("target_id") or hour(previous) > hour(current):
			return "save_community_transmission_invalid"
		if current.get("fact_type") != "community_message_heard" or current.get("root_fact_id") != root.fact_id \
				or current.get("subject_id") != memory.subject_id or current.get("topic") != memory.topic or int(current.get("hops", -1)) != hops:
			return "save_community_transmission_invalid"
		current = previous
		hops -= 1
	if current != root:
		return "save_community_transmission_invalid"
	return ""


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value)) and int(value) >= 0
