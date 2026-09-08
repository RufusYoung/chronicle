extends RefCounted


static func append_to(sources: Array, item: Dictionary) -> void:
	_add(sources, str(item.get("provenance", {}).get("created_by_fact_id", "")))
	var history: Array = item.get("history", [])
	# Mixed stacks retain contributing batches, not exclusive per-unit ancestry.
	for entry: Dictionary in history:
		if entry.get("event_type") == "quantity_increased":
			_add(sources, str(entry.get("fact_id", "")))
	if not history.is_empty():
		_add(sources, str(history.back().get("fact_id", "")))


static func _add(sources: Array, fact_id: String) -> void:
	if fact_id != "" and fact_id not in sources:
		sources.append(fact_id)
