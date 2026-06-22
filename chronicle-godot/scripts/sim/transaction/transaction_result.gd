extends RefCounted
class_name V5TransactionResult

var facts: Array = []
var state_changes: Array = []
var relationship_changes: Array = []
var memories: Array = []
var traces: Array = []
var rumors: Array = []
var item_changes: Array = []
var region_changes: Array = []


func is_empty() -> bool:
	return (
		facts.is_empty()
		and state_changes.is_empty()
		and relationship_changes.is_empty()
		and memories.is_empty()
		and traces.is_empty()
		and rumors.is_empty()
		and item_changes.is_empty()
		and region_changes.is_empty()
	)


func to_dict() -> Dictionary:
	return {
		"facts": facts.duplicate(true),
		"state_changes": state_changes.duplicate(true),
		"relationship_changes": relationship_changes.duplicate(true),
		"memories": memories.duplicate(true),
		"traces": traces.duplicate(true),
		"rumors": rumors.duplicate(true),
		"item_changes": item_changes.duplicate(true),
		"region_changes": region_changes.duplicate(true),
	}
