extends RefCounted
class_name V5InvestigationResolver

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const ChronicleBuilderModel = preload(
	"res://scripts/sim/investigation/investigation_chronicle_builder.gd"
)

var chronicle_builder: Variant = ChronicleBuilderModel.new()


func resolve(
		definition: Dictionary,
		lead: Dictionary,
		option_type: String,
		snapshot: Variant,
		event_id: int,
		time_summary: Dictionary
) -> Variant:
	var result = TransactionResultModel.new()
	if str(lead.get("status", "")) != "open":
		result.mark_invalid_contract(
			"investigation",
			"investigation_lead_not_open"
		)
		return result
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var target_id := str(definition.get("target_entity_id", ""))
	var item_id := str(definition.get("required_item_id", ""))
	var item: Dictionary = snapshot.get_item(item_id)
	if item.is_empty() or str(item.get("owner_id", "")) != actor_id:
		result.mark_invalid_contract(
			"investigation",
			"required_investigation_item_not_owned"
		)
		return result

	var new_facts: Array = []
	var memory_id := ""
	match option_type:
		"defer":
			new_facts = _apply_defer(
				result,
				definition,
				lead,
				snapshot,
				event_id,
				time_summary
			)
			memory_id = "investigation_deferred_memory:%d" % event_id
			result.add_memory(_defer_memory(
				definition,
				actor_id,
				target_id,
				item_id,
				new_facts,
				memory_id,
				time_summary
			))
		"investigate":
			new_facts = _apply_investigation(
				result,
				definition,
				lead,
				snapshot,
				event_id,
				time_summary
			)
			memory_id = "investigation_completed_memory:%d" % event_id
			result.add_memory(_investigation_memory(
				definition,
				actor_id,
				target_id,
				item_id,
				new_facts,
				memory_id,
				time_summary
			))
		_:
			result.mark_invalid_contract(
				"investigation",
				"invalid_investigation_option_type"
			)
			return result

	var chronicle_entry: Dictionary = chronicle_builder.build_entry(
		definition,
		option_type,
		lead,
		snapshot,
		new_facts,
		memory_id,
		time_summary,
		event_id
	)
	if chronicle_entry.is_empty():
		result.mark_invalid_contract(
			"investigation",
			"investigation_chronicle_sources_incomplete"
		)
		return result
	result.add_chronicle_entry(chronicle_entry)

	var option: Dictionary = definition.get(option_type, {})
	var resumed := (
		option_type == "investigate"
		and str(lead.get("disposition", "")) == "deferred"
	)
	result.set_narrative_result({
		"title": str(
			option.get(
				"resumed_narrative_title"
					if resumed
					else "narrative_title",
				"调查方向"
			)
		),
		"summary": str(
			option.get(
				"resumed_narrative" if resumed else "narrative",
				"你对这条调查方向作出了选择。"
			)
		),
		"lead_id": str(lead.get("lead_id", "")),
		"option_type": option_type,
		"outcome": "resolved" if option_type == "investigate" else "deferred",
		"resumed_after_defer": resumed,
		"chronicle_entry_id": str(
			chronicle_entry.get("entry_id", "")
		),
	})
	result.mark_resolved("investigation")
	return result


func _apply_defer(
		result: Variant,
		definition: Dictionary,
		lead: Dictionary,
		snapshot: Variant,
		event_id: int,
		time_summary: Dictionary
) -> Array:
	var option: Dictionary = definition.get("defer", {})
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var target_id := str(definition.get("target_entity_id", ""))
	var fact := {
		"fact_id": "actor_deferred_investigation:%d" % event_id,
		"fact_type": str(
			option.get(
				"fact_type",
				"actor_deferred_investigation"
			)
		),
		"source_id": actor_id,
		"target_id": str(lead.get("lead_id", "")),
		"location_id": str(snapshot.location.get("id", "")),
		"item_id": str(definition.get("required_item_id", "")),
		"cause_fact_ids": (
			lead.get("source_fact_ids", []) as Array
		).duplicate(true),
		"summary": str(option.get("fact_summary", "")),
		"chronicle_summary": str(
			option.get("chronicle_summary", "")
		),
		"day": int(time_summary.get("day", 1)),
		"hour": int(time_summary.get("hour", 0)),
		"visibility": "known",
		"source_action": "investigation_defer",
	}
	result.add_fact(fact)
	result.add_state_change({
		"entity_id": target_id,
		"key": str(
			definition.get(
				"target_stance_state_key",
				"investigation_stance"
			)
		),
		"to": str(option.get("target_stance", "waiting")),
	})
	result.add_investigation_change({
		"operation": "update",
		"lead_id": str(lead.get("lead_id", "")),
		"fields": {
			"disposition": "deferred",
			"deferred_day": int(time_summary.get("day", 1)),
			"deferred_hour": int(time_summary.get("hour", 0)),
			"defer_fact_id": str(fact.get("fact_id", "")),
		},
		"history_entry": {
			"event_type": "deferred",
			"source_fact_id": str(fact.get("fact_id", "")),
			"day": int(time_summary.get("day", 1)),
			"hour": int(time_summary.get("hour", 0)),
		},
	})
	return [fact]


func _apply_investigation(
		result: Variant,
		definition: Dictionary,
		lead: Dictionary,
		snapshot: Variant,
		event_id: int,
		time_summary: Dictionary
) -> Array:
	var option: Dictionary = definition.get("investigate", {})
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var target_id := str(definition.get("target_entity_id", ""))
	var item_id := str(definition.get("required_item_id", ""))
	var resumed := str(lead.get("disposition", "")) == "deferred"
	var cause_fact_ids: Array = (
		lead.get("source_fact_ids", []) as Array
	).duplicate(true)
	var defer_fact_id := str(lead.get("defer_fact_id", ""))
	if resumed and defer_fact_id != "" and defer_fact_id not in cause_fact_ids:
		cause_fact_ids.append(defer_fact_id)
	var search_fact_id := "actor_investigated_granary_records:%d" % event_id
	var discovery_fact_id := "actor_found_granary_archive_reference:%d" % event_id
	var search_fact := {
		"fact_id": search_fact_id,
		"fact_type": str(
			option.get(
				"search_fact_type",
				"actor_investigated_granary_records"
			)
		),
		"source_id": actor_id,
		"target_id": target_id,
		"location_id": str(snapshot.location.get("id", "")),
		"item_id": item_id,
		"hours_spent": int(option.get("hours", 1)),
		"resumed_after_defer": resumed,
		"cause_fact_ids": cause_fact_ids,
		"summary": str(option.get("search_fact_summary", "")),
		"chronicle_summary": str(
			option.get(
				"chronicle_summary_after_defer"
					if resumed
					else "chronicle_summary",
				""
			)
		),
		"day": int(time_summary.get("day", 1)),
		"hour": int(time_summary.get("hour", 0)),
		"visibility": "known",
		"source_action": "investigation",
	}
	var discovery_fact := {
		"fact_id": discovery_fact_id,
		"fact_type": str(
			option.get(
				"discovery_fact_type",
				"actor_found_granary_archive_reference"
			)
		),
		"source_id": actor_id,
		"target_id": str(
			option.get("visible_entity_id", "")
		),
		"target_display_name": str(
			option.get("discovery_display_name", "档案线索")
		),
		"location_id": str(snapshot.location.get("id", "")),
		"item_id": item_id,
		"former_clerk_id": str(
			option.get("former_clerk_id", "")
		),
		"former_clerk_name": str(
			option.get("former_clerk_name", "")
		),
		"archive_location_id": str(
			option.get("archive_location_id", "")
		),
		"archive_location_name": str(
			option.get("archive_location_name", "")
		),
		"cause_fact_ids": [search_fact_id],
		"summary": str(option.get("discovery_fact_summary", "")),
		"chronicle_summary": str(
			option.get("discovery_chronicle_summary", "")
		),
		"day": int(time_summary.get("day", 1)),
		"hour": int(time_summary.get("hour", 0)),
		"visibility": "known",
		"source_action": "investigation",
	}
	result.add_fact(search_fact)
	result.add_fact(discovery_fact)
	var visible_entity_id := str(option.get("visible_entity_id", ""))
	if visible_entity_id != "":
		result.add_state_change({
			"entity_id": visible_entity_id,
			"key": "visible",
			"to": true,
		})
	result.add_state_change({
		"entity_id": target_id,
		"key": str(
			definition.get(
				"target_stance_state_key",
				"investigation_stance"
			)
		),
		"to": str(option.get("target_stance", "helped_search")),
	})
	for relation: Dictionary in option.get(
		"relationship_changes",
		[]
	):
		result.add_relationship_change({
			"source_id": target_id,
			"target_id": actor_id,
			"axis": str(relation.get("axis", "")),
			"delta": int(relation.get("delta", 0)),
			"source_fact_id": search_fact_id,
		})
	result.add_item_change({
		"operation": "append_history",
		"item_id": item_id,
		"history_entry": {
			"event_type": "used_to_trace_archive",
			"actor_id": actor_id,
			"location_id": str(snapshot.location.get("id", "")),
			"source_fact_id": discovery_fact_id,
			"day": int(time_summary.get("day", 1)),
			"hour": int(time_summary.get("hour", 0)),
		},
	})
	result.add_investigation_change({
		"operation": "update",
		"lead_id": str(lead.get("lead_id", "")),
		"fields": {
			"status": "resolved",
			"disposition": "investigated",
			"resolved_day": int(time_summary.get("day", 1)),
			"resolved_hour": int(time_summary.get("hour", 0)),
			"resolution_fact_id": discovery_fact_id,
			"resumed_after_defer": resumed,
		},
		"history_entry": {
			"event_type": "investigated",
			"source_fact_id": discovery_fact_id,
			"day": int(time_summary.get("day", 1)),
			"hour": int(time_summary.get("hour", 0)),
		},
	})
	return [search_fact, discovery_fact]


func _defer_memory(
		definition: Dictionary,
		actor_id: String,
		target_id: String,
		item_id: String,
		facts: Array,
		memory_id: String,
		time_summary: Dictionary
) -> Dictionary:
	var option: Dictionary = definition.get("defer", {})
	return _memory(
		option,
		actor_id,
		target_id,
		item_id,
		facts,
		memory_id,
		time_summary,
		"remembers_traveler_deferred_granary_records"
	)


func _investigation_memory(
		definition: Dictionary,
		actor_id: String,
		target_id: String,
		item_id: String,
		facts: Array,
		memory_id: String,
		time_summary: Dictionary
) -> Dictionary:
	var option: Dictionary = definition.get("investigate", {})
	return _memory(
		option,
		actor_id,
		target_id,
		item_id,
		facts,
		memory_id,
		time_summary,
		"remembers_searching_granary_records_together"
	)


func _memory(
		option: Dictionary,
		actor_id: String,
		target_id: String,
		item_id: String,
		facts: Array,
		memory_id: String,
		time_summary: Dictionary,
		default_type: String
) -> Dictionary:
	var source_fact_ids: Array[String] = []
	for fact: Dictionary in facts:
		source_fact_ids.append(str(fact.get("fact_id", "")))
	return {
		"memory_id": memory_id,
		"owner_id": target_id,
		"memory_type": str(
			option.get("memory_type", default_type)
		),
		"subject_id": actor_id,
		"item_id": item_id,
		"source_fact_ids": source_fact_ids,
		"summary": str(option.get("memory_summary", "")),
		"day": int(time_summary.get("day", 1)),
		"hour": int(time_summary.get("hour", 0)),
	}
