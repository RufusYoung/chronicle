# res://scripts/gen/npc_interactions.gd
extends Node
class_name NpcInteractions

var picker: WeightedPick = WeightedPick.new()  # WeightedPick 需有 class_name

func choose_npc_interaction(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var candidates: Array = []

	# 1) 先看顶层 encounters
	var enc_any: Variant = region.get("encounters", null)
	if enc_any is Array:
		_collect_npc_encounters(enc_any as Array, candidates)

	# 2) 若还没有，尝试 pools.encounters
	if candidates.is_empty():
		var pools_any: Variant = region.get("pools", null)
		if pools_any is Dictionary:
			var pools: Dictionary = pools_any as Dictionary
			var p_enc_any: Variant = pools.get("encounters", null)
			if p_enc_any is Array:
				_collect_npc_encounters(p_enc_any as Array, candidates)

	# 3) 加权挑一条（没有就返回 {}）
	if candidates.is_empty():
		return {}
	return picker.pick_weighted(candidates, ctx)

func _collect_npc_encounters(source: Array, out: Array) -> void:
	for e in source:
		if e is Dictionary:
			var tags_any: Variant = (e as Dictionary).get("tags", null)
			if tags_any is Array:
				var tags: Array = tags_any as Array
				if "npc" in tags:
					out.append(e)
