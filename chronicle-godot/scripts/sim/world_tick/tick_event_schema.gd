extends RefCounted
class_name V5TickEventSchema

const ALLOWED_TICK_TYPES := [
	"time_event",
	"manual_event",
	"life_project_day",
	"test_event",
]
const ALLOWED_SCOPE_TYPES := ["location", "institution", "region", "global"]
const ALLOWED_DUE_KINDS := ["obligation", "exchange"]


func normalize(event: Dictionary) -> Dictionary:
	var normalized := {
		"tick_event_id": _string_value(event, "tick_event_id"),
		"tick_type": _string_value(event, "tick_type"),
		"trigger_key": _string_value(event, "trigger_key"),
		"scope_type": _string_value(event, "scope_type"),
		"scope_id": _string_value(event, "scope_id"),
		"source": _string_value(event, "source"),
		"label": _string_value(event, "label"),
		"elapsed_hours": _int_value(event, "elapsed_hours", 0),
		"max_triggers": _int_value(event, "max_triggers", 0),
		"include_due_checks": _bool_value(event, "include_due_checks", false),
		"due_kinds": _due_kinds_value(event),
	}

	if event.has("day"):
		normalized["day"] = _int_value(event, "day", 0)
	if event.has("hour"):
		normalized["hour"] = _int_value(event, "hour", 0)
	if event.has("start_day"):
		normalized["start_day"] = _int_value(event, "start_day", 0)
	if event.has("start_hour"):
		normalized["start_hour"] = _int_value(event, "start_hour", 0)
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
	var elapsed_hours := int(normalized.get("elapsed_hours", 0))
	var due_kinds: Array = normalized.get("due_kinds", [])

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
	if elapsed_hours < 0:
		errors.append("invalid_elapsed_hours")
	if normalized.has("day") and int(normalized.get("day", 0)) < 1:
		errors.append("invalid_day")
	if normalized.has("hour") and int(normalized.get("hour", 0)) not in range(24):
		errors.append("invalid_hour")
	if normalized.has("start_day") and int(normalized.get("start_day", 0)) < 1:
		errors.append("invalid_start_day")
	if (
		normalized.has("start_hour")
		and int(normalized.get("start_hour", 0)) not in range(24)
	):
		errors.append("invalid_start_hour")
	if event.has("include_due_checks") and not (event.get("include_due_checks") is bool):
		errors.append("invalid_include_due_checks")
	if event.has("due_kinds") and not (event.get("due_kinds") is Array):
		errors.append("invalid_due_kinds")
	for due_kind: Variant in due_kinds:
		var due_kind_text := str(due_kind)
		if not (due_kind_text in ALLOWED_DUE_KINDS):
			errors.append("invalid_due_kind:%s" % due_kind_text)

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


func _bool_value(event: Dictionary, key: String, default_value: bool) -> bool:
	if not event.has(key):
		return default_value
	var value: Variant = event.get(key)
	return value if value is bool else default_value


func _due_kinds_value(event: Dictionary) -> Array:
	if not event.has("due_kinds"):
		return ["obligation", "exchange"]
	var value: Variant = event.get("due_kinds")
	return (value as Array).duplicate(true) if value is Array else []
