extends RefCounted

const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")


static func validate(definitions: Variant) -> String:
	if not definitions is Array:
		return "incidents_not_array"
	var ids := {}
	for definition: Variant in definitions:
		if not definition is Dictionary:
			return "incident_not_dictionary"
		for key: String in definition:
			if key not in ["id", "title", "body", "condition", "cooldown_hours", "responses"]:
				return "unsupported_incident_field:" + key
		for key: String in ["id", "title", "body"]:
			if not definition.get(key) is String or str(definition[key]).strip_edges() == "":
				return "invalid_incident_text:" + key
		if ids.has(definition.id) or ":" in definition.id or not Recipe._integer(definition.get("cooldown_hours"), 1):
			return "invalid_incident_identity_or_cooldown"
		ids[definition.id] = true
		if definition.get("condition") not in ["worn_owned_tool", "present_food_need"]:
			return "unsupported_incident_condition"
		if not definition.get("responses") is Array or definition.responses.size() < 2:
			return "incident_requires_alternatives"
		var responses := {}
		for response: Variant in definition.responses:
			if not response is Dictionary or response.keys().any(func(key: String) -> bool: return key not in ["id", "label", "action_prefix"]):
				return "unsupported_incident_response"
			for key: String in ["id", "label", "action_prefix"]:
				if not response.get(key) is String or str(response[key]).strip_edges() == "":
					return "invalid_incident_response:" + key
			if responses.has(response.id) or ":" in response.id \
					or response.action_prefix not in ["rest", "eat", "gather:", "work:", "give_food:", "sell_food:"]:
				return "unsupported_incident_action"
			responses[response.id] = true
	return ""


static func decorate(session: Variant, base: Array) -> Array:
	var definitions: Array = session.fixture_source_data.get("content_extension", {}).get("incidents", [])
	if definitions.is_empty():
		return base
	var now: int = session.elapsed_hours_since_start
	for definition: Dictionary in definitions:
		var recent: bool = session.stores.fact_store.list_facts().any(func(fact: Dictionary) -> bool:
			return fact.get("fact_type") == "local_incident_resolved" and fact.get("incident_id") == definition.id \
				and now - int(fact.elapsed_hours) < int(definition.cooldown_hours))
		if recent or not eligible(session, str(definition.condition)):
			continue
		var choices: Array = []
		var replaced: Array = []
		for response: Dictionary in definition.responses:
			for action: Dictionary in base:
				var matches_action: bool = str(action.action_id).begins_with(response.action_prefix) if str(response.action_prefix).ends_with(":") else action.action_id == response.action_prefix
				if not matches_action or action.action_id in replaced:
					continue
				var row := action.duplicate(true)
				row["action_id"] = "incident:%s:%s" % [definition.id, response.id]
				row["label"] = "%s · %s" % [definition.title, response.label]
				row["hint"] = "%s\n%s：%s" % [definition.body, action.label, action.hint]
				row["known_effect"] = row.hint
				row["wrapped_action_id"] = action.action_id
				row["incident_id"] = definition.id
				choices.append(row)
				replaced.append(action.action_id)
				break
		if choices.size() < 2 or not choices.any(func(row: Dictionary) -> bool: return row.can_execute):
			continue
		choices.append_array(base.filter(func(row: Dictionary) -> bool: return row.action_id not in replaced))
		return choices
	return base


static func eligible(session: Variant, condition: String) -> bool:
	var snapshot: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	var actor: Dictionary = snapshot.get_entity(str(session.context.actor_id))
	if actor.states.get("daily_route_id", "") != "" or not session.get_combat_encounter_options().is_empty():
		return false
	if condition == "worn_owned_tool":
		return snapshot.get_items_for_holder(str(actor.id)).any(func(item: Dictionary) -> bool:
			return "rope" in item.get("tags", []) and int(item.get("condition", {}).get("durability", 0)) == 1)
	return int(snapshot.player.food_count) > 2 and session.PlayerLife.Local.present(snapshot, actor).any(func(person: Dictionary) -> bool:
		return session.PlayerLife.Local.wants_food(snapshot, person))


static func execute(session: Variant, id: String) -> Dictionary:
	var matches := decorate(session, session.PlayerLife.options(session, false)).filter(func(row: Dictionary) -> bool: return row.action_id == id)
	if matches.is_empty():
		return {"success": false, "error": "incident_no_longer_available"}
	var selected: Dictionary = matches[0]
	var before: int = session.stores.fact_store.list_facts().size()
	var outcome: Dictionary = session.PlayerLife.execute(session, str(selected.wrapped_action_id))
	if not outcome.get("success", false):
		return outcome
	var sources: Array = []
	for fact: Dictionary in session.stores.fact_store.list_facts().slice(before):
		if fact.get("actor_id") == session.context.actor_id or fact.get("contributor_id") == session.context.actor_id:
			sources.append(fact.fact_id)
	var result := Result.new()
	result.add_fact({"fact_id": "fact.local_incident.%s.%d" % [selected.incident_id, session.elapsed_hours_since_start],
		"fact_type": "local_incident_resolved", "incident_id": selected.incident_id, "actor_id": session.context.actor_id,
		"location_id": session.context.location_id, "day": session.current_day, "hour": session.current_hour,
		"elapsed_hours": session.elapsed_hours_since_start, "action_id": selected.wrapped_action_id,
		"source_fact_ids": sources, "summary": selected.label + "；实际成本和结果以本次行动结算为准。"})
	result.mark_resolved("local_incident_resolved")
	if not session.writer.apply_result(result, session.stores):
		outcome["incident_recorded"] = false
		outcome["warning"] = "行动已结算，但插曲记录失败：" + str(result.error_reason)
		return outcome
	outcome["incident_recorded"] = true
	return outcome
