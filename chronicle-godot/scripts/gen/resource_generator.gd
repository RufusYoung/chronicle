extends Node
class_name ResourceGenerator

var picker: WeightedPick = WeightedPick.new()

func gather_resource(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = region.get("resources", []) as Array
	return picker.pick_weighted(items, ctx)

func roll_loot(region: Dictionary, table_id: String, ctx: Dictionary = {}) -> Array:
	var tables: Array = region.get("loot_tables", []) as Array
	for t_any in tables:
		if not (t_any is Dictionary):
			continue
		var t: Dictionary = t_any as Dictionary
		if String(t.get("id", "")) != table_id:
			continue

		# rolls 解析（无 ? 语法）
		var min_roll: int = 1
		var max_roll: int = 1
		var rolls_any: Variant = t.get("rolls", null)
		if rolls_any is Dictionary:
			var rolls: Dictionary = rolls_any as Dictionary
			min_roll = int(rolls.get("min", 1))
			# 如果 max 没给，就用 min
			max_roll = int(rolls.get("max", min_roll))

		var n: int = randi_range(min_roll, max_roll)

		var out: Array = []
		var entries: Array = []
		var entries_any: Variant = t.get("entries", [])
		if entries_any is Array:
			entries = entries_any as Array

		for i in range(n):
			var pick_entry: Dictionary = picker.pick_weighted(entries, ctx)
			if pick_entry.is_empty():
				continue

			# qty 解析（无 ? 语法）
			var q: int = 1
			var qdef_any: Variant = pick_entry.get("qty", null)
			if qdef_any is Array:
				var qarr: Array = qdef_any as Array
				var qmin: int = 1
				var qmax: int = 1
				if qarr.size() >= 1:
					qmin = int(qarr[0])
					qmax = qmin
				if qarr.size() >= 2:
					qmax = int(qarr[1])
				q = randi_range(qmin, qmax)
			elif qdef_any != null:
				q = int(qdef_any)

			out.append({"item": pick_entry, "qty": q})
		return out

	return []
