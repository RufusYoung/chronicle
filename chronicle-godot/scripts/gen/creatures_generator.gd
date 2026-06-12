# res://scripts/gen/common/creatures_generator.gd
extends Node
class_name CreaturesGenerator

var picker: WeightedPick = WeightedPick.new()  # WeightedPick 需有 class_name

func choose_creature(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	# 读上下文，不修改它
	var use_ctx: Dictionary = ctx

	# pools
	var pools_any: Variant = region.get("pools", null)
	var pools: Dictionary = {}
	if pools_any is Dictionary:
		pools = pools_any as Dictionary

	# fauna 列表
	var items_any: Variant = pools.get("fauna", null)
	var items: Array = []
	if items_any is Array:
		items = items_any as Array

	return picker.pick_weighted(items, use_ctx)
