extends Node
class_name V5LifeStageTransitionRelay

var pending_transition: Dictionary = {}


func store_transition(data: Dictionary) -> void:
	pending_transition = data.duplicate(true)


func consume_transition() -> Dictionary:
	var result := pending_transition.duplicate(true)
	pending_transition.clear()
	return result


func has_transition() -> bool:
	return not pending_transition.is_empty()


func clear() -> void:
	pending_transition.clear()
