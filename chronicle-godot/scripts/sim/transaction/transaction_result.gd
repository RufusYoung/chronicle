extends RefCounted
class_name V5TransactionResult

var facts: Array = []
var facts_added: Array = []
var state_changes: Array = []
var relationship_changes: Array = []
var memories: Array = []
var memories_added: Array = []
var traces: Array = []
var traces_added: Array = []
var rumors: Array = []
var rumors_added: Array = []
var pressure_changes: Array = []
var obligations_added: Array = []
var exchanges_added: Array = []
var deferred_consequences_added: Array = []
var item_changes: Array = []
var region_changes: Array = []
var narrative_result: Dictionary = {}
var transaction_mode: String = ""
var contract_status: String = ""
var skip_reason: String = ""
var error_reason: String = ""


func is_empty() -> bool:
	return (
		facts.is_empty()
		and facts_added.is_empty()
		and state_changes.is_empty()
		and relationship_changes.is_empty()
		and memories.is_empty()
		and memories_added.is_empty()
		and traces.is_empty()
		and traces_added.is_empty()
		and rumors.is_empty()
		and rumors_added.is_empty()
		and pressure_changes.is_empty()
		and obligations_added.is_empty()
		and exchanges_added.is_empty()
		and deferred_consequences_added.is_empty()
		and item_changes.is_empty()
		and region_changes.is_empty()
		and narrative_result.is_empty()
	)


func add_fact(fact: Dictionary) -> void:
	var fact_copy := fact.duplicate(true)
	facts.append(fact_copy)
	facts_added.append(fact_copy)


func add_state_change(change: Dictionary) -> void:
	state_changes.append(change.duplicate(true))


func add_relationship_change(change: Dictionary) -> void:
	relationship_changes.append(change.duplicate(true))


func add_memory(memory: Dictionary) -> void:
	var memory_copy := memory.duplicate(true)
	memories.append(memory_copy)
	memories_added.append(memory_copy)


func add_trace(trace: Dictionary) -> void:
	var trace_copy := trace.duplicate(true)
	traces.append(trace_copy)
	traces_added.append(trace_copy)


func add_rumor_seed(rumor: Dictionary) -> void:
	var rumor_copy := rumor.duplicate(true)
	rumors.append(rumor_copy)
	rumors_added.append(rumor_copy)


func add_pressure_change(change: Dictionary) -> void:
	pressure_changes.append(change.duplicate(true))


func add_obligation(obligation: Dictionary) -> void:
	obligations_added.append(obligation.duplicate(true))


func add_exchange(exchange: Dictionary) -> void:
	exchanges_added.append(exchange.duplicate(true))


func add_deferred_consequence(consequence: Dictionary) -> void:
	deferred_consequences_added.append(consequence.duplicate(true))


func set_narrative_result(result: Dictionary) -> void:
	narrative_result = result.duplicate(true)


func mark_resolved(mode: String) -> void:
	transaction_mode = mode
	contract_status = "resolved"
	skip_reason = ""
	error_reason = ""


func mark_candidate_only(mode: String, reason: String = "candidate_only_rule") -> void:
	transaction_mode = mode
	contract_status = "candidate_only"
	skip_reason = reason
	error_reason = ""


func mark_invalid_contract(mode: String, reason: String) -> void:
	transaction_mode = mode
	contract_status = "invalid_contract"
	skip_reason = ""
	error_reason = reason


func to_dict() -> Dictionary:
	return {
		"facts": facts.duplicate(true),
		"facts_added": facts_added.duplicate(true),
		"state_changes": state_changes.duplicate(true),
		"relationship_changes": relationship_changes.duplicate(true),
		"memories": memories.duplicate(true),
		"memories_added": memories_added.duplicate(true),
		"traces": traces.duplicate(true),
		"traces_added": traces_added.duplicate(true),
		"rumors": rumors.duplicate(true),
		"rumors_added": rumors_added.duplicate(true),
		"pressure_changes": pressure_changes.duplicate(true),
		"obligations_added": obligations_added.duplicate(true),
		"exchanges_added": exchanges_added.duplicate(true),
		"deferred_consequences_added": deferred_consequences_added.duplicate(true),
		"item_changes": item_changes.duplicate(true),
		"region_changes": region_changes.duplicate(true),
		"narrative_result": narrative_result.duplicate(true),
		"transaction_mode": transaction_mode,
		"contract_status": contract_status,
		"skip_reason": skip_reason,
		"error_reason": error_reason,
	}


static func empty_candidate_only(candidate: Variant) -> Variant:
	var result = V5TransactionResult.new()
	result.mark_candidate_only(_candidate_string(candidate, "transaction_mode"), "candidate_only_rule")
	return result


static func invalid_contract(candidate: Variant, reason: String) -> Variant:
	var result = V5TransactionResult.new()
	result.mark_invalid_contract(_candidate_string(candidate, "transaction_mode"), reason)
	return result


static func _candidate_string(candidate: Variant, key: String) -> String:
	if candidate == null:
		return ""
	if candidate is Dictionary:
		var dictionary_value: Variant = (candidate as Dictionary).get(key)
		return "" if dictionary_value == null else str(dictionary_value)
	var object_value: Variant = candidate.get(key)
	return "" if object_value == null else str(object_value)
