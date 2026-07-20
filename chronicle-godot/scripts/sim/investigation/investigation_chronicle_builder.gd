extends RefCounted
class_name V5InvestigationChronicleBuilder


func build_entry(
		definition: Dictionary,
		option_type: String,
		lead: Dictionary,
		snapshot: Variant,
		new_facts: Array,
		memory_id: String,
		time_summary: Dictionary,
		event_id: int
) -> Dictionary:
	var lead_id := str(lead.get("lead_id", ""))
	var actor_id := str(snapshot.get_player_value("id", "player"))
	if (
		lead_id == ""
		or str(lead.get("status", "")) != "open"
		or new_facts.is_empty()
	):
		return {}

	var fact_index := _fact_index(snapshot, new_facts)
	var source_fact_ids: Array[String] = []
	for fact_id_value: Variant in lead.get("source_fact_ids", []):
		var fact_id := str(fact_id_value)
		if fact_id == "" or not fact_index.has(fact_id):
			return {}
		_append_unique(source_fact_ids, fact_id)
	if (
		option_type == "investigate"
		and str(lead.get("disposition", "")) == "deferred"
	):
		var defer_fact_id := str(lead.get("defer_fact_id", ""))
		if defer_fact_id == "" or not fact_index.has(defer_fact_id):
			return {}
		_append_unique(source_fact_ids, defer_fact_id)
	for fact: Dictionary in new_facts:
		var fact_id := str(fact.get("fact_id", ""))
		if fact_id == "":
			return {}
		_append_unique(source_fact_ids, fact_id)

	var source_fact_types: Array[String] = []
	for fact_id: String in source_fact_ids:
		var fact: Dictionary = fact_index.get(fact_id, {})
		_append_unique(
			source_fact_types,
			str(fact.get("fact_type", ""))
		)

	var option: Dictionary = definition.get(option_type, {})
	var body_parts: Array[String] = []
	var claims: Array = []
	for fact: Dictionary in new_facts:
		var chronicle_summary := str(
			fact.get("chronicle_summary", "")
		)
		if chronicle_summary == "":
			return {}
		body_parts.append(chronicle_summary)
		var claim_fact_ids: Array[String] = [
			str(fact.get("fact_id", "")),
		]
		for cause_fact_id: Variant in fact.get("cause_fact_ids", []):
			_append_unique(claim_fact_ids, str(cause_fact_id))
		claims.append({
			"text": chronicle_summary,
			"fact_ids": claim_fact_ids,
			"item_ids": (
				lead.get("source_item_ids", []) as Array
			).duplicate(true),
		})

	var day := int(time_summary.get("day", 1))
	var hour := int(time_summary.get("hour", 0))
	var body := "第%d天%02d:00，%s" % [
		day,
		hour,
		"".join(body_parts),
	]
	return {
		"entry_id": "personal_chronicle:investigation:%s:%d"
			% [option_type, event_id],
		"entry_type": "personal_chronicle",
		"subject_id": actor_id,
		"title": str(
			option.get("chronicle_title", "一条调查方向")
		),
		"body": body,
		"day": day,
		"hour": hour,
		"location_id": str(snapshot.location.get("id", "")),
		"source_fact_ids": source_fact_ids,
		"source_fact_types": source_fact_types,
		"source_item_ids": (
			lead.get("source_item_ids", []) as Array
		).duplicate(true),
		"source_memory_ids": [memory_id] if memory_id != "" else [],
		"claims": claims,
		"branch": option_type,
		"resumed_after_defer": (
			option_type == "investigate"
			and str(lead.get("disposition", "")) == "deferred"
		),
		"tags": [
			"lake_town",
			"investigation",
			"public_granary",
			option_type,
		],
	}


func _fact_index(snapshot: Variant, new_facts: Array) -> Dictionary:
	var rows: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		var fact_id := str(fact.get("fact_id", ""))
		if fact_id != "":
			rows[fact_id] = fact.duplicate(true)
	for fact: Dictionary in new_facts:
		var fact_id := str(fact.get("fact_id", ""))
		if fact_id != "":
			rows[fact_id] = fact.duplicate(true)
	return rows


func _append_unique(rows: Array[String], value: String) -> void:
	if value != "" and value not in rows:
		rows.append(value)
