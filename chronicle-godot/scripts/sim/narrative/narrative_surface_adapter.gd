extends RefCounted
class_name V5NarrativeSurfaceAdapter


func build_transaction_summary(result: Variant, _context: Variant) -> Dictionary:
	var fact_types := _fact_types(result)
	var memory_types := _memory_types(result)
	var primary_fact := "" if fact_types.is_empty() else fact_types[0]

	match primary_fact:
		"actor_gave_food_to_target":
			return _summary(
				"给食物",
				"对方接过食物，饥饿缓和了一些。感激和信任有所上升。",
				fact_types,
				memory_types,
				"quiet"
			)
		"actor_reported_discipline_violation":
			return _summary(
				"报告军纪问题",
				"罗恩听完报告，把口粮记录折了起来。小队里可能会有人听说这件事。",
				fact_types,
				memory_types,
				"tense"
			)
		"actor_concealed_discipline_violation":
			return _summary(
				"隐瞒军纪问题",
				"伊莱意识到你没有把事情说出去。他欠下了一个不轻的人情。",
				fact_types,
				memory_types,
				"low_voice"
			)
		"actor_read_object":
			return _summary(
				"阅读记录",
				"你读完了眼前的文字，并记住了其中的关键信息。",
				fact_types,
				memory_types,
				"focused"
			)
		"actor_inspected_trace":
			return _summary(
				"检查痕迹",
				"你检查了痕迹，它指向刚刚发生过的事情。",
				fact_types,
				memory_types,
				"observant"
			)
		_:
			return _summary("行动结果", "行动已经记录为事实。", fact_types, memory_types, "neutral")


func _summary(
	title: String,
	body: String,
	fact_types: Array,
	memory_types: Array,
	tone: String
) -> Dictionary:
	return {
		"title": title,
		"body": body,
		"fact_types": fact_types.duplicate(true),
		"memory_types": memory_types.duplicate(true),
		"tone": tone,
	}


func _fact_types(result: Variant) -> Array:
	var types: Array = []
	for fact: Dictionary in result.facts_added:
		var fact_type := str(fact.get("fact_type", ""))
		if fact_type != "" and fact_type not in types:
			types.append(fact_type)
	return types


func _memory_types(result: Variant) -> Array:
	var types: Array = []
	for memory: Dictionary in result.memories_added:
		var memory_type := str(memory.get("memory_type", ""))
		if memory_type != "" and memory_type not in types:
			types.append(memory_type)
	return types
