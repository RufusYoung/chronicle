extends RefCounted
class_name V5TickEventSchema

const ALLOWED_TICK_TYPES := ["time_event", "manual_event", "test_event"]
const ALLOWED_SCOPE_TYPES := ["location", "institution", "region", "global"]


func normalize(event: Dictionary) -> Dictionary:
	var normalized := {
		"tick_event_id": _string_value(event, "tick_event_id"),
		"tick_type": _string_value(event, "tick_type"),
		"trigger_key": _string_value(event, "trigger_key"),
		"scope_type": _string_value(event, "scope_type"),
		"scope_id": _string_value(event, "scope_id"),
		"source": _string_value(event, "source"),
		"label": _string_value(event, "label"),
		"max_triggers": _int_value(event, "max_triggers", 0),
	}

	if event.has("day"):
		normalized["day"] = _int_value(event, "day", 0)
	if event.has("time_key"):
		normalized["time_key"] = _string_value(event, "time_key")

	return normalized


func validate(event: Dictionary) -> Dictionary:
	var normalized := normalize(event)
	var errors: Array = []
	var warnings: Array = []
	var tick_event_id := str(normalized.get("tick_event_id", ""))
	var tick_type := str(normalized.get("tick_type", ""))
	var trigger_key := str(normalized.get("trigger_key", ""))
	var scope_type := str(normalized.get("scope_type", ""))
	var scope_id := str(normalized.get("scope_id", ""))
	var max_triggers := int(normalized.get("max_triggers", 0))

	if tick_event_id == "":
		errors.append("missing_tick_event_id")
	if tick_type == "":
		errors.append("missing_tick_type")
	elif not (tick_type in ALLOWED_TICK_TYPES):
		errors.append("invalid_tick_type:%s" % tick_type)
	if trigger_key == "":
		errors.append("missing_trigger_key")
	if scope_type == "":
		errors.append("missing_scope_type")
	elif not (scope_type in ALLOWED_SCOPE_TYPES):
		errors.append("invalid_scope_type:%s" % scope_type)
	if scope_type != "" and scope_type != "global" and scope_id == "":
		errors.append("missing_scope_id")
	if max_triggers < 0:
		errors.append("invalid_max_triggers")

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"event": normalized,
	}


func _string_value(event: Dictionary, key: String) -> String:
	var value: Variant = event.get(key)
	return "" if value == null else str(value)


func _int_value(event: Dictionary, key: String, default_value: int) -> int:
	if not event.has(key):
		return default_value
	var value: Variant = event.get(key)
	if value == null or str(value) == "":
		return default_value
	return int(value)
