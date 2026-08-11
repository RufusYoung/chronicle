extends RefCounted
class_name V5NpcNeedSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


func resolve_tick(
		snapshot: Variant,
		profiles: Array,
		tick_event: Dictionary
) -> Dictionary:
	var elapsed_hours := maxi(int(tick_event.get("elapsed_hours", 0)), 0)
	if elapsed_hours == 0:
		return _empty_result()

	var results: Array = []
	var changes: Array = []
	var observed_result_indexes: Array = []
	for profile_value: Variant in profiles:
		if not (profile_value is Dictionary):
			continue
		var profile := profile_value as Dictionary
		for actor: Dictionary in snapshot.get_entities():
			if not _actor_matches(actor, profile.get("actor", {}), snapshot):
				continue
			for need_value: Variant in profile.get("needs", []):
				if not (need_value is Dictionary):
					continue
				var resolved := _resolve_need(
					actor,
					profile,
					need_value as Dictionary,
					snapshot,
					tick_event,
					elapsed_hours
				)
				var result: Variant = resolved.get("result")
				if result == null or result.is_empty():
					continue
				var result_index := results.size()
				results.append(result)
				if bool(resolved.get("changed", false)):
					var change: Dictionary = resolved.get("change", {})
					change["result_index"] = result_index
					changes.append(change)
					if bool(change.get("observed_by_player", false)):
						observed_result_indexes.append(result_index)

	return {
		"change_count": changes.size(),
		"changes": changes,
		"results": results,
		"observed_result_indexes": observed_result_indexes,
	}


func _resolve_need(
		actor: Dictionary,
		profile: Dictionary,
		need: Dictionary,
		snapshot: Variant,
		tick_event: Dictionary,
		elapsed_hours: int
) -> Dictionary:
	var actor_id := str(actor.get("id", ""))
	var need_key := str(need.get("key", ""))
	var clock_key := str(
		need.get("clock_key", "%s_elapsed_hours" % need_key)
	)
	if actor_id == "" or need_key == "":
		return {}

	var current_value: Variant = snapshot.get_entity_state(
		actor_id,
		need_key,
		null
	)
	if current_value == null:
		return {}
	var scale: Array = need.get(
		"scale",
		["none", "low", "medium", "high", "extreme"]
	)
	var current_index := scale.find(current_value)
	if current_index < 0:
		return {}

	var interval_hours := maxi(int(need.get("interval_hours", 1)), 1)
	var interval_state_key := str(need.get("interval_state_key", ""))
	if interval_state_key != "":
		interval_hours = maxi(int(snapshot.get_entity_state(
			actor_id,
			interval_state_key,
			interval_hours
		)), 1)
	var old_clock := maxi(int(snapshot.get_entity_state(
		actor_id,
		clock_key,
		0
	)), 0)
	var accumulated := old_clock + elapsed_hours
	var step_count := int(accumulated / interval_hours)
	var new_clock := posmod(accumulated, interval_hours)

	var result: Variant = TransactionResultModel.new()
	if new_clock != old_clock or step_count > 0:
		result.add_state_change({
			"entity_id": actor_id,
			"key": clock_key,
			"to": new_clock,
			"reason": "npc_need_clock_advanced",
		})

	var direction := str(need.get("direction", "increase"))
	var new_index := current_index
	if direction == "decrease":
		new_index = maxi(current_index - step_count, 0)
	else:
		new_index = mini(current_index + step_count, scale.size() - 1)
	var new_value: Variant = scale[new_index]
	var changed: bool = new_value != current_value
	if not changed:
		if not result.is_empty():
			result.mark_resolved("npc_need_progress")
		return {"result": result, "changed": false}

	var location_id := str(actor.get("location_id", ""))
	var observed_by_player := location_id == str(snapshot.location.get("id", ""))
	var values := {
		"actor_id": actor_id,
		"actor_display_name": str(actor.get("display_name", actor_id)),
		"need_key": need_key,
		"from": str(current_value),
		"to": str(new_value),
		"location_id": location_id,
		"tick_event_id": str(tick_event.get("tick_event_id", "")),
		"profile_id": str(profile.get("profile_id", "")),
	}
	result.add_state_change({
		"entity_id": actor_id,
		"key": need_key,
		"to": new_value,
		"reason": "npc_need_changed_with_time",
	})
	result.add_fact({
		"fact_id": "npc_need_changed:%s:%s:%s" % [
			actor_id,
			need_key,
			values["tick_event_id"],
		],
		"fact_type": "npc_need_changed",
		"actor_id": actor_id,
		"need_key": need_key,
		"from": current_value,
		"to": new_value,
		"location_id": location_id,
		"source_profile_id": values["profile_id"],
		"observed_by_player": observed_by_player,
	})
	var narrative: Dictionary = need.get("narrative", {})
	if not narrative.is_empty():
		result.set_narrative_result(_resolve_dictionary(narrative, values))
	result.mark_resolved("npc_need_progress")
	return {
		"result": result,
		"changed": true,
		"change": {
			"actor_id": actor_id,
			"actor_display_name": values["actor_display_name"],
			"need_key": need_key,
			"from": current_value,
			"to": new_value,
			"step_count": step_count,
			"location_id": location_id,
			"observed_by_player": observed_by_player,
		},
	}


func _actor_matches(
		actor: Dictionary,
		query_value: Variant,
		snapshot: Variant
) -> bool:
	if not (query_value is Dictionary):
		return true
	var query := query_value as Dictionary
	var actor_id := str(actor.get("id", ""))
	if actor_id == "":
		return false
	if query.has("type") and str(actor.get("type", "")) != str(query.get("type", "")):
		return false
	var tags: Array = actor.get("tags", [])
	for tag: Variant in query.get("tags_all", []):
		if not (tag in tags):
			return false
	var state_equals: Dictionary = query.get("state_equals", {})
	for key_value: Variant in state_equals.keys():
		var key := str(key_value)
		if snapshot.get_entity_state(actor_id, key, null) != state_equals[key_value]:
			return false
	return true


func _resolve_dictionary(source: Dictionary, values: Dictionary) -> Dictionary:
	var resolved: Dictionary = {}
	for key_value: Variant in source.keys():
		var value: Variant = source[key_value]
		if value is String:
			var text := str(value)
			for binding_key: Variant in values.keys():
				text = text.replace(
					"{%s}" % str(binding_key),
					str(values[binding_key])
				)
			resolved[key_value] = text
		else:
			resolved[key_value] = value
	return resolved


func _empty_result() -> Dictionary:
	return {
		"change_count": 0,
		"changes": [],
		"results": [],
		"observed_result_indexes": [],
	}
