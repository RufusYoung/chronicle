extends RefCounted

static func enabled(session: Variant) -> bool:
	return int(session.fixture_source_data.get("journey_rules", {}).get("version", 0)) in [2, 3]


static func register_states(registry: Variant) -> bool:
	for key: String in ["player_action_minutes", "player_action_sequence"]:
		var definition := {"state_def_id": "state.entity." + key, "definition_version": 1,
			"key": key, "owner_kinds": ["entity"], "value_type": "int", "default": 0,
			"minimum": 0, "allowed_operations": ["set"], "persistence": "save", "ui_visibility": "detail"}
		if key == "player_action_minutes":
			definition["maximum"] = 59
		if not registry.register_definition("state", definition.state_def_id, definition):
			return false
	return true


static func stamp(session: Variant) -> String:
	var hour := str(session.elapsed_hours_since_start)
	return hour + "." + str(session.stores.state_store.get_state(str(session.context.actor_id), "player_action_sequence", 0)) if enabled(session) else hour


static func append(result: Variant, session: Variant, minutes: int = 10) -> void:
	if not enabled(session):
		return
	var actor := str(session.context.actor_id)
	var state: Variant = session.stores.state_store
	result.add_state_change({"entity_id": actor, "key": "player_action_minutes", "to": (int(state.get_state(actor, "player_action_minutes", 0)) + minutes) % 60})
	result.add_state_change({"entity_id": actor, "key": "player_action_sequence", "to": int(state.get_state(actor, "player_action_sequence", 0)) + 1})


static func advance(session: Variant, reason: String, minutes: int = 10) -> Dictionary:
	if not enabled(session):
		return session.advance_time(1, reason)
	# Short actions retain a native remainder; each crossed hour runs the ordinary world tick.
	var remainder := int(session.stores.state_store.get_state(str(session.context.actor_id), "player_action_minutes", 0))
	var crossed := minutes / 60 + (1 if remainder < minutes % 60 else 0)
	var result: Dictionary = session.advance_time(crossed, reason) if crossed > 0 else {"success": true, "hours": 0}
	result["minutes"] = minutes
	return result


static func decorate(session: Variant, rows: Array) -> void:
	if not enabled(session):
		return
	for row: Dictionary in rows:
		var id := str(row.action_id)
		if id.get_slice(":", 0) not in ["ask_local", "sell_food", "give_food", "buy", "eat", "inquire"]:
			continue
		row["hours"] = 0
		row["minutes"] = 10
		row["cost"] = "10分钟"
		for key: String in ["hint", "known_effect"]:
			row[key] = str(row.get(key, "")).replace("消耗1份和1小时", "消耗1份食物和10分钟")


static func validate(state: Dictionary) -> String:
	for key: String in ["player_action_minutes", "player_action_sequence"]:
		var value: Variant = state.get(key, 0)
		if not (value is int or value is float) or float(value) != floor(float(value)) or value < 0:
			return "save_short_action_clock_invalid"
	var minute := int(state.get("player_action_minutes", 0))
	return "" if minute < 60 and minute % 10 == 0 else "save_short_action_clock_invalid"
