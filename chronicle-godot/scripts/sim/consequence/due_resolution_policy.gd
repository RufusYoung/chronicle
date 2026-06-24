extends RefCounted
class_name V5DueResolutionPolicy

const TARGET_KIND_OBLIGATION := "obligation"
const TARGET_KIND_EXCHANGE := "exchange"
const OBLIGATION_RESOLUTIONS := ["fulfilled", "breached", "keep_due"]
const EXCHANGE_RESOLUTIONS := ["settled", "failed", "keep_due"]


func normalize(decision: Dictionary) -> Dictionary:
	return {
		"resolution_id": _string_value(decision, "resolution_id"),
		"target_kind": _string_value(decision, "target_kind"),
		"target_id": _string_value(decision, "target_id"),
		"resolution": _string_value(decision, "resolution"),
		"reason": _string_value(decision, "reason"),
		"source": _string_value(decision, "source"),
		"resolver_actor_id": _string_value(decision, "resolver_actor_id"),
		"tick_event_id": _string_value(decision, "tick_event_id"),
		"trigger_key": _string_value(decision, "trigger_key"),
		"scope_type": _string_value(decision, "scope_type"),
		"scope_id": _string_value(decision, "scope_id"),
	}


func validate(decision: Dictionary) -> Dictionary:
	var normalized := normalize(decision)
	var errors: Array = []
	var warnings: Array = []
	var resolution_id := str(normalized.get("resolution_id", ""))
	var target_kind := str(normalized.get("target_kind", ""))
	var target_id := str(normalized.get("target_id", ""))
	var resolution := str(normalized.get("resolution", ""))

	if resolution_id == "":
		errors.append("missing_resolution_id")
	if target_kind == "":
		errors.append("missing_target_kind")
	elif not (target_kind in [TARGET_KIND_OBLIGATION, TARGET_KIND_EXCHANGE]):
		errors.append("invalid_target_kind:%s" % target_kind)
	if target_id == "":
		errors.append("missing_target_id")
	if resolution == "":
		errors.append("missing_resolution")
	elif target_kind == TARGET_KIND_OBLIGATION and not (resolution in OBLIGATION_RESOLUTIONS):
		errors.append("invalid_obligation_resolution:%s" % resolution)
	elif target_kind == TARGET_KIND_EXCHANGE and not (resolution in EXCHANGE_RESOLUTIONS):
		errors.append("invalid_exchange_resolution:%s" % resolution)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"decision": normalized,
	}


func _string_value(decision: Dictionary, key: String) -> String:
	var value: Variant = decision.get(key)
	return "" if value == null else str(value)
