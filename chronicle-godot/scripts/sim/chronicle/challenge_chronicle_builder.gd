extends RefCounted
class_name V5ChallengeChronicleBuilder


func build_entry(
		challenge: Dictionary,
		snapshot: Variant,
		new_facts: Array,
		time_summary: Dictionary,
		event_id: int
) -> Dictionary:
	var success: Dictionary = challenge.get("success", {})
	var definition: Dictionary = success.get("chronicle", {})
	if definition.is_empty():
		return {}

	var challenge_id := str(challenge.get("challenge_id", ""))
	var route_id := str(definition.get("required_route_id", ""))
	var item: Dictionary = success.get("item", {})
	var item_id := str(item.get("item_id", item.get("id", "")))
	if challenge_id == "" or route_id == "" or item_id == "":
		return {}

	var source_facts: Array[Dictionary] = []
	var route_fact := _latest_route_fact(snapshot.get_facts(), route_id)
	if route_fact.is_empty():
		return {}
	source_facts.append(route_fact)

	var preparation_fact := _latest_challenge_fact(
		snapshot.get_facts(),
		"actor_prepared_for_challenge",
		challenge_id
	)
	if not preparation_fact.is_empty():
		source_facts.append(preparation_fact)
	for fact: Dictionary in new_facts:
		if str(fact.get("challenge_id", "")) == challenge_id:
			source_facts.append(fact.duplicate(true))

	if not _has_successful_attempt(source_facts, challenge_id):
		return {}
	if not _has_item_discovery(source_facts, item_id):
		return {}

	var source_fact_ids: Array[String] = []
	var source_fact_types: Array[String] = []
	for fact: Dictionary in source_facts:
		_append_unique(
			source_fact_ids,
			str(fact.get("fact_id", ""))
		)
		_append_unique(
			source_fact_types,
			str(fact.get("fact_type", ""))
		)

	for required_type_value: Variant in definition.get(
		"required_fact_types",
		[]
	):
		if str(required_type_value) not in source_fact_types:
			return {}

	var claims: Array = []
	for claim_value: Variant in definition.get("claims", []):
		if not claim_value is Dictionary:
			return {}
		var claim := claim_value as Dictionary
		var claim_fact_ids: Array[String] = []
		for fact_type_value: Variant in claim.get("fact_types", []):
			var fact_type := str(fact_type_value)
			var fact_id := _fact_id_for_type(source_facts, fact_type)
			if fact_id == "":
				return {}
			_append_unique(claim_fact_ids, fact_id)
		claims.append({
			"text": str(claim.get("text", "")),
			"fact_ids": claim_fact_ids,
			"item_ids": [item_id],
		})

	var day := int(time_summary.get("day", 1))
	var hour := int(time_summary.get("hour", 0))
	return {
		"entry_id": "personal_chronicle:challenge:%s:%d"
			% [challenge_id, event_id],
		"entry_type": "personal_chronicle",
		"subject_id": str(snapshot.get_player_value("id", "player")),
		"title": str(definition.get("title", "一次现场发现")),
		"body": "第%d天%02d:00，%s" % [
			day,
			hour,
			str(definition.get("body", "")),
		],
		"day": day,
		"hour": hour,
		"location_id": str(snapshot.location.get("id", "")),
		"source_fact_ids": source_fact_ids,
		"source_fact_types": source_fact_types,
		"source_item_ids": [item_id],
		"source_memory_ids": [],
		"claims": claims,
		"branch": (
			"prepared"
			if not preparation_fact.is_empty()
			else "direct"
		),
		"tags": (
			definition.get("tags", []) as Array
		).duplicate(true),
	}


func _latest_route_fact(facts: Array, route_id: String) -> Dictionary:
	for index: int in range(facts.size() - 1, -1, -1):
		var fact := facts[index] as Dictionary
		if (
			str(fact.get("fact_type", "")) == "actor_traveled_route"
			and str(fact.get("route_id", "")) == route_id
		):
			return fact.duplicate(true)
	return {}


func _latest_challenge_fact(
		facts: Array,
		fact_type: String,
		challenge_id: String
) -> Dictionary:
	for index: int in range(facts.size() - 1, -1, -1):
		var fact := facts[index] as Dictionary
		if (
			str(fact.get("fact_type", "")) == fact_type
			and str(fact.get("challenge_id", "")) == challenge_id
		):
			return fact.duplicate(true)
	return {}


func _has_successful_attempt(
		facts: Array[Dictionary],
		challenge_id: String
) -> bool:
	for fact: Dictionary in facts:
		if (
			str(fact.get("fact_type", ""))
				== "actor_attempted_challenge"
			and str(fact.get("challenge_id", "")) == challenge_id
			and str(fact.get("outcome", "")) == "success"
		):
			return true
	return false


func _has_item_discovery(
		facts: Array[Dictionary],
		item_id: String
) -> bool:
	for fact: Dictionary in facts:
		if (
			str(fact.get("fact_type", "")) == "actor_discovered_item"
			and str(fact.get("target_id", "")) == item_id
		):
			return true
	return false


func _fact_id_for_type(
		facts: Array[Dictionary],
		fact_type: String
) -> String:
	for fact: Dictionary in facts:
		if str(fact.get("fact_type", "")) == fact_type:
			return str(fact.get("fact_id", ""))
	return ""


func _append_unique(rows: Array[String], value: String) -> void:
	if value != "" and value not in rows:
		rows.append(value)
