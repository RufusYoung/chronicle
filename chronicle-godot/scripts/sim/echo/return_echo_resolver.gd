extends RefCounted
class_name V5ReturnEchoResolver

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const ChronicleEntryBuilderModel = preload(
	"res://scripts/sim/chronicle/chronicle_entry_builder.gd"
)

var chronicle_builder: Variant = ChronicleEntryBuilderModel.new()


func resolve(
		definition: Dictionary,
		snapshot: Variant,
		event_id: int,
		time_summary: Dictionary
) -> Variant:
	var result = TransactionResultModel.new()
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var target_id := str(definition.get("target_entity_id", ""))
	var item_id := str(definition.get("required_item_id", ""))
	var item: Dictionary = snapshot.get_item(item_id)
	if item.is_empty() or str(item.get("owner_id", "")) != actor_id:
		result.mark_invalid_contract(
			"return_echo",
			"required_owned_item_not_found"
		)
		return result

	var target: Dictionary = snapshot.get_entity(target_id)
	if target.is_empty():
		result.mark_invalid_contract("return_echo", "target_not_found")
		return result

	var day := int(time_summary.get("day", 1))
	var hour := int(time_summary.get("hour", 0))
	var recognition_fact_id := "item_recognized_on_return:%d" % event_id
	var clue_fact_id := "local_history_revealed_by_item:%d" % event_id
	var prior_fact_ids := _prior_fact_ids(definition, snapshot, item_id)
	var origin_id := str(
		(item.get("provenance", {}) as Dictionary).get("created_for", "")
	)
	var recognition_fact := {
		"fact_id": recognition_fact_id,
		"fact_type": str(
			definition.get(
				"recognition_fact_type",
				"item_recognized_on_return"
			)
		),
		"source_id": target_id,
		"source_display_name": str(target.get("display_name", target_id)),
		"target_id": item_id,
		"target_display_name": str(item.get("display_name", item_id)),
		"origin_id": origin_id,
		"origin_display_name": str(
			definition.get("recognized_origin_name", origin_id)
		),
		"location_id": str(snapshot.location.get("id", "")),
		"cause_fact_ids": prior_fact_ids,
		"day": day,
		"hour": hour,
		"visibility": "known",
		"source_action": "return_echo",
	}
	var clue_data: Dictionary = definition.get("local_history_clue", {})
	var clue_fact := {
		"fact_id": clue_fact_id,
		"fact_type": str(
			clue_data.get(
				"fact_type",
				"local_history_revealed_by_item"
			)
		),
		"source_id": target_id,
		"target_id": str(clue_data.get("subject_id", origin_id)),
		"item_id": item_id,
		"summary": str(clue_data.get("summary", "")),
		"chronicle_summary": str(
			clue_data.get("chronicle_summary", "")
		),
		"location_id": str(snapshot.location.get("id", "")),
		"cause_fact_ids": [recognition_fact_id],
		"day": day,
		"hour": hour,
		"visibility": "known",
		"source_action": "return_echo",
	}
	result.add_fact(recognition_fact)
	result.add_fact(clue_fact)
	var lead_data: Dictionary = definition.get("investigation_lead", {})
	if not lead_data.is_empty():
		var lead_opened_fact_id := "investigation_lead_opened:%d" % event_id
		var lead_opened_fact := {
			"fact_id": lead_opened_fact_id,
			"fact_type": "investigation_lead_opened",
			"source_id": target_id,
			"target_id": str(lead_data.get("lead_id", "")),
			"item_id": item_id,
			"location_id": str(snapshot.location.get("id", "")),
			"cause_fact_ids": [recognition_fact_id, clue_fact_id],
			"summary": str(lead_data.get("opened_fact_summary", "")),
			"day": day,
			"hour": hour,
			"visibility": "known",
			"source_action": "return_echo",
		}
		result.add_fact(lead_opened_fact)
		var lead := lead_data.duplicate(true)
		lead["status"] = "open"
		lead["disposition"] = "fresh"
		lead["opened_day"] = day
		lead["opened_hour"] = hour
		lead["source_fact_ids"] = [
			recognition_fact_id,
			clue_fact_id,
			lead_opened_fact_id,
		]
		lead["source_item_ids"] = [item_id]
		lead["history"] = [{
			"event_type": "opened",
			"source_fact_id": lead_opened_fact_id,
			"day": day,
			"hour": hour,
		}]
		result.add_investigation_change({
			"operation": "create",
			"lead": lead,
		})

	var completion_state_key := str(
		definition.get("completion_state_key", "return_echo_completed")
	)
	result.add_state_change({
		"entity_id": target_id,
		"key": completion_state_key,
		"to": true,
	})
	for relation: Dictionary in definition.get(
		"relationship_changes",
		[]
	):
		result.add_relationship_change({
			"source_id": target_id,
			"target_id": actor_id,
			"axis": str(relation.get("axis", "")),
			"delta": int(relation.get("delta", 0)),
			"source_fact_id": recognition_fact_id,
		})

	var memory_id := "return_echo_memory:%d" % event_id
	result.add_memory({
		"memory_id": memory_id,
		"owner_id": target_id,
		"memory_type": str(
			definition.get(
				"memory_type",
				"recognized_returned_historical_item"
			)
		),
		"subject_id": actor_id,
		"item_id": item_id,
		"location_id": str(snapshot.location.get("id", "")),
		"source_fact_ids": [recognition_fact_id, clue_fact_id],
		"summary": str(
			definition.get(
				"memory_summary",
				"对方带回了一件与本地旧事有关的物品。"
			)
		),
		"day": day,
		"hour": hour,
	})
	result.add_item_change({
		"operation": "append_history",
		"item_id": item_id,
		"history_entry": {
			"event_type": "recognized_by",
			"actor_id": target_id,
			"location_id": str(snapshot.location.get("id", "")),
			"source_fact_id": recognition_fact_id,
			"day": day,
			"hour": hour,
		},
	})

	var chronicle_entry: Dictionary = (
		chronicle_builder.build_personal_entry(
			definition,
			snapshot,
			item,
			recognition_fact,
			clue_fact,
			memory_id,
			time_summary,
			event_id
		)
	)
	if chronicle_entry.is_empty():
		result.mark_invalid_contract(
			"return_echo",
			"chronicle_causal_chain_incomplete"
		)
		return result
	result.add_chronicle_entry(chronicle_entry)
	result.set_narrative_result({
		"title": str(
			definition.get("narrative_title", "旧物被认了出来")
		),
		"summary": str(
			definition.get(
				"narrative",
				"眼前的人认出了你带回的旧物。"
			)
		),
		"echo_id": str(definition.get("echo_id", "")),
		"outcome": "recognized",
		"item_id": item_id,
		"target_id": target_id,
		"clue_fact_id": clue_fact_id,
		"chronicle_entry_id": str(
			chronicle_entry.get("entry_id", "")
		),
	})
	result.mark_resolved("return_echo")
	return result


func _prior_fact_ids(
		definition: Dictionary,
		snapshot: Variant,
		item_id: String
) -> Array[String]:
	var rows: Array[String] = []
	var required_route_ids: Array = definition.get("required_route_ids", [])
	var challenge_id := str(definition.get("required_challenge_id", ""))
	for fact: Dictionary in snapshot.get_facts():
		var fact_type := str(fact.get("fact_type", ""))
		var include := false
		if fact_type == "actor_traveled_route":
			include = str(fact.get("route_id", "")) in required_route_ids
		elif fact_type == "actor_prepared_for_challenge":
			include = str(fact.get("challenge_id", "")) == challenge_id
		elif fact_type == "actor_attempted_challenge":
			include = (
				str(fact.get("challenge_id", "")) == challenge_id
				and str(fact.get("outcome", "")) == "success"
			)
		elif fact_type == "actor_discovered_item":
			include = str(fact.get("target_id", "")) == item_id
		if include:
			var fact_id := str(fact.get("fact_id", ""))
			if fact_id != "" and fact_id not in rows:
				rows.append(fact_id)
	return rows
