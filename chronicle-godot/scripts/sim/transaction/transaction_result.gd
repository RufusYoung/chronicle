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
var item_changes: Array = []
var region_changes: Array = []
var narrative_result: Dictionary = {}


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


func set_narrative_result(result: Dictionary) -> void:
	narrative_result = result.duplicate(true)


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
		"item_changes": item_changes.duplicate(true),
		"region_changes": region_changes.duplicate(true),
		"narrative_result": narrative_result.duplicate(true),
	}
