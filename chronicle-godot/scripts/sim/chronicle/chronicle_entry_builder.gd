extends RefCounted
class_name V5ChronicleEntryBuilder


func build_personal_entry(
		definition: Dictionary,
		snapshot: Variant,
		item: Dictionary,
		recognition_fact: Dictionary,
		clue_fact: Dictionary,
		memory_id: String,
		time_summary: Dictionary,
		event_id: int
) -> Dictionary:
	var item_id := str(item.get("item_id", item.get("id", "")))
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var provenance: Dictionary = item.get("provenance", {})
	if (
		item_id == ""
		or str(item.get("owner_id", "")) != actor_id
		or str(provenance.get("discovered_at", "")) == ""
		or str(recognition_fact.get("fact_id", "")) == ""
		or str(clue_fact.get("fact_id", "")) == ""
	):
		return {}

	var prior_facts := _causal_facts(definition, snapshot, item_id)
	if not _has_required_causal_chain(definition, prior_facts, item_id):
		return {}

	var source_fact_ids: Array[String] = []
	var source_fact_types: Array[String] = []
	for fact: Dictionary in prior_facts:
		_append_unique(
			source_fact_ids,
			str(fact.get("fact_id", ""))
		)
		_append_unique(
			source_fact_types,
			str(fact.get("fact_type", ""))
		)
	for new_fact: Dictionary in [recognition_fact, clue_fact]:
		_append_unique(
			source_fact_ids,
			str(new_fact.get("fact_id", ""))
		)
		_append_unique(
			source_fact_types,
			str(new_fact.get("fact_type", ""))
		)

	var target_id := str(definition.get("target_entity_id", ""))
	var target: Dictionary = snapshot.get_entity(target_id)
	var target_name := str(
		target.get(
			"display_name",
			recognition_fact.get("source_display_name", target_id)
		)
	)
	var item_name := str(item.get("display_name", item_id))
	var discovery_location_name := str(
		definition.get(
			"discovery_location_name",
			provenance.get("discovered_at", "")
		)
	)
	var clue_summary := str(clue_fact.get("chronicle_summary", ""))
	if target_name == "" or discovery_location_name == "" or clue_summary == "":
		return {}

	var day := int(time_summary.get("day", 1))
	var hour := int(time_summary.get("hour", 0))
	var journey_claim := "第%d天%02d:00，你把从%s带回的%s拿给%s辨认。" % [
		day,
		hour,
		discovery_location_name,
		item_name,
		target_name,
	]
	return {
		"entry_id": "personal_chronicle:return_echo:%d" % event_id,
		"entry_type": "personal_chronicle",
		"subject_id": actor_id,
		"title": str(
			definition.get("chronicle_title", "被认出的旧物")
		),
		"body": journey_claim + clue_summary,
		"day": day,
		"hour": hour,
		"location_id": str(snapshot.location.get("id", "")),
		"source_fact_ids": source_fact_ids,
		"source_fact_types": source_fact_types,
		"source_item_ids": [item_id],
		"source_memory_ids": [memory_id] if memory_id != "" else [],
		"claims": [
			{
				"text": journey_claim,
				"fact_ids": _journey_fact_ids(prior_facts),
				"item_ids": [item_id],
			},
			{
				"text": clue_summary,
				"fact_ids": [
					str(recognition_fact.get("fact_id", "")),
					str(clue_fact.get("fact_id", "")),
				],
				"item_ids": [item_id],
			},
		],
		"tags": [
			"lake_town",
			"return_echo",
			"item_history",
			"local_history",
		],
	}


func _causal_facts(
		definition: Dictionary,
		snapshot: Variant,
		item_id: String
) -> Array:
	var rows: Array = []
	var required_route_ids: Array = definition.get("required_route_ids", [])
	var challenge_id := str(definition.get("required_challenge_id", ""))
	for fact: Dictionary in snapshot.get_facts():
		var fact_type := str(fact.get("fact_type", ""))
		var include := false
		if fact_type == "actor_traveled_route":
			include = str(fact.get("route_id", "")) in required_route_ids
		elif fact_type == "actor_prepared_for_challenge":
			include = (
				challenge_id != ""
				and str(fact.get("challenge_id", "")) == challenge_id
			)
		elif fact_type == "actor_attempted_challenge":
			include = (
				str(fact.get("challenge_id", "")) == challenge_id
				and str(fact.get("outcome", "")) == "success"
			)
		elif fact_type == "actor_discovered_item":
			include = str(fact.get("target_id", "")) == item_id
		if include:
			rows.append(fact.duplicate(true))
	return rows


func _has_required_causal_chain(
		definition: Dictionary,
		facts: Array,
		item_id: String
) -> bool:
	var found_routes: Array[String] = []
	var found_challenge := false
	var found_discovery := false
	var challenge_id := str(definition.get("required_challenge_id", ""))
	for fact: Dictionary in facts:
		match str(fact.get("fact_type", "")):
			"actor_traveled_route":
				_append_unique(
					found_routes,
					str(fact.get("route_id", ""))
				)
			"actor_attempted_challenge":
				found_challenge = found_challenge or (
					str(fact.get("challenge_id", "")) == challenge_id
					and str(fact.get("outcome", "")) == "success"
				)
			"actor_discovered_item":
				found_discovery = (
					found_discovery
					or str(fact.get("target_id", "")) == item_id
				)
	for route_id: Variant in definition.get("required_route_ids", []):
		if str(route_id) not in found_routes:
			return false
	return found_challenge and found_discovery


func _journey_fact_ids(facts: Array) -> Array[String]:
	var rows: Array[String] = []
	for fact: Dictionary in facts:
		_append_unique(rows, str(fact.get("fact_id", "")))
	return rows


func _append_unique(rows: Array[String], value: String) -> void:
	if value != "" and value not in rows:
		rows.append(value)
