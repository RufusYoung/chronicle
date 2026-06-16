extends RefCounted
class_name LakeTownLivingSurfaceBuilder

const TemplatesModel = preload(
	"res://scripts/dev/lake_town_living_surface_templates.gd"
)

const CORE_NPC_IDS: Array[String] = [
	"old_chen",
	"chen_mi",
	"ma_shen",
	"liu_zhangfang",
]
const LOCATION_IDS: Array[String] = [
	"old_chen_shop",
	"abandoned_granary",
	"lake_town_market",
	"ma_shen_home_temp",
]
const KEY_FACT_TYPES: Array[String] = [
	"lake_town_food_price_rising",
	"guard_locked_abandoned_granary",
	"chen_mi_blocked_by_guard_seal",
	"chen_mi_took_spoiled_grain",
	"old_chen_closed_shop_due_to_family_crisis",
	"chen_mi_ate_spoiled_grain",
	"chen_mi_collapsed_from_hunger",
	"old_chen_sold_shop_goods_for_food",
	"old_chen_took_chen_mi_to_seek_help",
	"ma_shen_emergency_food_for_chen_mi",
	"chen_mi_temporarily_stayed_with_ma_shen",
	"creditor_left_debt_notice",
	"chen_mi_found_empty_granary",
	"chen_mi_returned_empty_handed",
	"chen_mi_endured_hunger",
	"chen_mi_weakened_from_enduring_hunger",
	"lake_town_emergency_credit_food",
	"chen_mi_health_crashed_from_hunger",
]

var templates := TemplatesModel.new()


func build_living_surface_cards(run_result: Dictionary, day: int) -> Array:
	var context := _build_context(run_result, day)
	var cards: Array[Dictionary] = []
	for scene_value: Variant in context.get("narratable_states", []):
		var scene := scene_value as Dictionary
		var card := _build_scene_card(context, scene)
		if not card.is_empty():
			cards.append(card)
	if cards.is_empty():
		for fact_value: Variant in context.get("facts", []):
			var fact := fact_value as Dictionary
			if str(fact.get("type", "")) not in KEY_FACT_TYPES:
				continue
			var card := _build_fact_card(context, fact)
			if not card.is_empty():
				cards.append(card)
			if cards.size() >= 3:
				break
	if cards.is_empty() and not (context.get("facts", []) as Array).is_empty():
		var generic_fact := (context.get("facts", []) as Array)[0] as Dictionary
		var generic_card := _build_fact_card(context, generic_fact)
		if not generic_card.is_empty():
			cards.append(generic_card)
	if cards.is_empty():
		var state_card := _build_state_card(context)
		if not state_card.is_empty():
			cards.append(state_card)
	cards.sort_custom(_sort_cards_by_priority)
	return cards.slice(0, 3)


func build_primary_surface_card(
		run_result: Dictionary,
		day: int
	) -> Dictionary:
	var cards := build_living_surface_cards(run_result, day)
	if cards.is_empty():
		return {}
	return (cards[0] as Dictionary).duplicate(true)


func build_surface_day_list(run_result: Dictionary) -> Array:
	var rows: Array[Dictionary] = []
	var day_count := int(run_result.get("days", 30))
	for day: int in range(1, day_count + 1):
		var card := build_primary_surface_card(run_result, day)
		rows.append({
			"day": day,
			"has_card": not card.is_empty(),
			"title": str(card.get("title", "")),
			"severity": str(card.get("severity", "")),
			"card_type": str(card.get("card_type", "")),
		})
	return rows


func build_people_cards(run_result: Dictionary, day: int) -> Array:
	var snapshot := _snapshot_for_day(run_result, "npc_snapshots", day)
	var output: Array[Dictionary] = []
	for npc_id: String in CORE_NPC_IDS:
		var npc := snapshot.get(npc_id, {}) as Dictionary
		if npc.is_empty():
			continue
		output.append({
			"card_id": "people_%s_day_%02d" % [npc_id, day],
			"npc_id": npc_id,
			"title": templates.npc_name(npc_id),
			"summary": templates.build_person_line(npc_id, npc),
			"fields": _person_fields(npc_id, npc),
			"state_keys": _state_keys_for_person(npc_id),
			"severity": _person_severity(npc),
		})
	return output


func build_location_cards(run_result: Dictionary, day: int) -> Array:
	var snapshot := _snapshot_for_day(run_result, "location_snapshots", day)
	var output: Array[Dictionary] = []
	for location_id: String in LOCATION_IDS:
		var location := snapshot.get(location_id, {}) as Dictionary
		if location.is_empty():
			continue
		output.append({
			"card_id": "location_%s_day_%02d" % [location_id, day],
			"location_id": location_id,
			"title": templates.location_name(location_id),
			"summary": templates.build_location_line(location_id, location),
			"fields": _location_fields(location_id, location),
			"state_keys": _state_keys_for_location(location_id),
			"severity": _location_severity(location),
		})
	return output


func _build_scene_card(context: Dictionary, scene: Dictionary) -> Dictionary:
	var source_ids := _strings(scene.get("source_fact_ids", []))
	var trace_ids := _strings(scene.get("trace_ids", []))
	var memory_ids := _strings(scene.get("memory_ids", []))
	var facts := _rows_by_ids(
		context.get("all_facts", []) as Array,
		source_ids,
		"fact_id"
	)
	var traces := _rows_by_ids(
		context.get("all_traces", []) as Array,
		trace_ids,
		"trace_id"
	)
	var memories := _rows_by_ids(
		context.get("all_memories", []) as Array,
		memory_ids,
		"memory_id"
	)
	var card_context := context.duplicate(true)
	card_context["facts"] = facts
	card_context["traces"] = traces
	card_context["memories"] = memories
	card_context["primary_scene"] = scene.duplicate(true)
	card_context["fact_types"] = _fact_types(facts)
	return _compose_card(
		card_context,
		"scene_%s_day_%02d" % [
			str(scene.get("id", "")),
			int(context.get("day", 0)),
		],
		str(scene.get("title", "湖湾镇今日局面")),
		str(scene.get("location_id", "")),
		source_ids,
		trace_ids,
		memory_ids,
		[str(scene.get("narratable_state_id", scene.get("id", "")))]
	)


func _build_fact_card(context: Dictionary, fact: Dictionary) -> Dictionary:
	var fact_id := str(fact.get("fact_id", fact.get("id", "")))
	var traces := _rows_for_source(
		context.get("all_traces", []) as Array,
		fact_id
	)
	var memories := _rows_for_source(
		context.get("all_memories", []) as Array,
		fact_id
	)
	var card_context := context.duplicate(true)
	card_context["facts"] = [fact.duplicate(true)]
	card_context["traces"] = traces
	card_context["memories"] = memories
	card_context["primary_fact"] = fact.duplicate(true)
	card_context["fact_types"] = [str(fact.get("type", ""))]
	return _compose_card(
		card_context,
		"fact_%s_day_%02d" % [
			fact_id,
			int(context.get("day", 0)),
		],
		templates.build_fact_line(fact, card_context),
		str(fact.get("location_id", "")),
		[fact_id],
		_ids(traces, "trace_id"),
		_ids(memories, "memory_id"),
		[]
	)


func _build_state_card(context: Dictionary) -> Dictionary:
	var npc_snapshot := context.get("npc_snapshot", {}) as Dictionary
	var old_chen := npc_snapshot.get("old_chen", {}) as Dictionary
	var chen_mi := npc_snapshot.get("chen_mi", {}) as Dictionary
	var location_snapshot := context.get("location_snapshot", {}) as Dictionary
	var shop := location_snapshot.get("old_chen_shop", {}) as Dictionary
	var severe := (
		_number(chen_mi.get("hunger", 0.0)) >= 90.0
		or _number(old_chen.get("stress", 0.0)) >= 90.0
		or _number(old_chen.get("debt", 0.0)) >= 90.0
		or (shop.has("is_open") and not bool(shop.get("is_open", true)))
	)
	if not severe:
		return {}
	var support_facts := _recent_rows(
		context.get("all_facts", []) as Array,
		int(context.get("day", 0)),
		3
	)
	var support_traces := _recent_rows(
		context.get("all_traces", []) as Array,
		int(context.get("day", 0)),
		3
	)
	if support_facts.is_empty() and support_traces.is_empty():
		return {}
	var card_context := context.duplicate(true)
	card_context["facts"] = support_facts.slice(0, 2)
	card_context["traces"] = support_traces.slice(0, 4)
	card_context["fact_types"] = _fact_types(card_context["facts"] as Array)
	card_context["state_reason"] = "湖湾镇今天没有新的重大事实，但前几天留下的压力仍在延续。"
	return _compose_card(
		card_context,
		"state_day_%02d" % int(context.get("day", 0)),
		"湖湾镇的压力还在继续",
		"old_chen_shop",
		_ids(card_context["facts"] as Array, "fact_id"),
		_ids(card_context["traces"] as Array, "trace_id"),
		[],
		[]
	)


func _compose_card(
		context: Dictionary,
		card_id: String,
		title: String,
		location_id: String,
		source_fact_ids: Array,
		trace_ids: Array,
		memory_ids: Array,
		narratable_state_ids: Array
	) -> Dictionary:
	if source_fact_ids.is_empty() and trace_ids.is_empty():
		return {}
	var fact_types := context.get("fact_types", []) as Array
	var severity := _severity_for(context)
	var card_type := _card_type_for(fact_types, severity)
	var traces := context.get("traces", []) as Array
	var facts := context.get("facts", []) as Array
	var memories := context.get("memories", []) as Array
	var trace_lines := _trace_lines(traces)
	var visible_details := _unique_lines(
		trace_lines + _fact_lines(facts)
	).slice(0, 6)
	return {
		"card_id": card_id,
		"seed": int(context.get("seed", 0)),
		"day": int(context.get("day", 0)),
		"title": title,
		"subtitle": "湖湾镇 · Day %d" % int(context.get("day", 0)),
		"location_id": location_id,
		"location_name": templates.location_name(location_id),
		"scene_summary": templates.build_summary(card_type, context),
		"visible_details": visible_details,
		"people_present": _people_lines(context),
		"location_state_lines": _location_lines(context),
		"trace_lines": trace_lines,
		"memory_echo_lines": _memory_lines(memories),
		"cause_lines": _cause_lines(facts),
		"quality_lines": _quality_lines(context),
		"source_fact_ids": _strings(source_fact_ids),
		"trace_ids": _strings(trace_ids),
		"memory_ids": _strings(memory_ids),
		"narratable_state_ids": _strings(narratable_state_ids),
		"state_keys": _state_keys_for_card(context),
		"tone_tags": _tone_tags(facts, severity),
		"severity": severity,
		"card_type": card_type,
	}


func _build_context(run_result: Dictionary, day: int) -> Dictionary:
	var facts := _rows_for_day(run_result.get("fact_rows", []) as Array, day)
	var traces := _rows_for_day(run_result.get("trace_rows", []) as Array, day)
	var memories := _rows_for_day(
		run_result.get("memory_rows", []) as Array,
		day
	)
	var scenes := _rows_for_day(
		run_result.get("narratable_rows", []) as Array,
		day
	)
	return {
		"seed": int(run_result.get("seed", 0)),
		"day": day,
		"facts": facts,
		"traces": traces,
		"memories": memories,
		"narratable_states": scenes,
		"fact_types": _fact_types(facts),
		"all_facts": (
			run_result.get("fact_rows", []) as Array
		).duplicate(true),
		"all_traces": (
			run_result.get("trace_rows", []) as Array
		).duplicate(true),
		"all_memories": (
			run_result.get("memory_rows", []) as Array
		).duplicate(true),
		"npc_snapshot": _snapshot_for_day(
			run_result,
			"npc_snapshots",
			day
		),
		"location_snapshot": _snapshot_for_day(
			run_result,
			"location_snapshots",
			day
		),
		"quality_summary": (
			run_result.get("quality_summary", {}) as Dictionary
		).duplicate(true),
	}


func _snapshot_for_day(
		run_result: Dictionary,
		snapshot_key: String,
		day: int
	) -> Dictionary:
	var snapshots := run_result.get(snapshot_key, {}) as Dictionary
	return (
		snapshots.get(str(day), {}) as Dictionary
	).duplicate(true)


func _rows_for_day(rows: Array, day: int) -> Array:
	var output: Array[Dictionary] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		if int(row.get("day", -1)) == day:
			output.append(row.duplicate(true))
	return output


func _recent_rows(rows: Array, day: int, days_back: int) -> Array:
	var output: Array[Dictionary] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		var row_day := int(row.get("day", -1))
		if row_day >= day - days_back and row_day <= day:
			output.append(row.duplicate(true))
	output.sort_custom(_sort_day_then_id)
	return output


func _rows_by_ids(rows: Array, ids: Array, id_key: String) -> Array:
	var output: Array[Dictionary] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		if str(row.get(id_key, row.get("id", ""))) in ids:
			output.append(row.duplicate(true))
	return output


func _rows_for_source(rows: Array, source_fact_id: String) -> Array:
	var output: Array[Dictionary] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		if str(row.get("source_fact_id", "")) == source_fact_id:
			output.append(row.duplicate(true))
	return output


func _fact_types(facts: Array) -> Array[String]:
	var output: Array[String] = []
	for fact_value: Variant in facts:
		var type_name := str((fact_value as Dictionary).get("type", ""))
		if type_name != "" and type_name not in output:
			output.append(type_name)
	return output


func _fact_lines(facts: Array) -> Array[String]:
	var output: Array[String] = []
	for fact_value: Variant in facts:
		output.append(templates.build_fact_line(fact_value as Dictionary))
	return output


func _trace_lines(traces: Array) -> Array[String]:
	var output: Array[String] = []
	for trace_value: Variant in traces:
		output.append(templates.build_trace_line(trace_value as Dictionary))
	return _unique_lines(output)


func _people_lines(context: Dictionary) -> Array[String]:
	var snapshot := context.get("npc_snapshot", {}) as Dictionary
	var output: Array[String] = []
	for npc_id: String in CORE_NPC_IDS:
		var npc := snapshot.get(npc_id, {}) as Dictionary
		if not npc.is_empty():
			output.append(templates.build_person_line(npc_id, npc))
	return output


func _location_lines(context: Dictionary) -> Array[String]:
	var snapshot := context.get("location_snapshot", {}) as Dictionary
	var output: Array[String] = []
	for location_id: String in LOCATION_IDS:
		var location := snapshot.get(location_id, {}) as Dictionary
		if not location.is_empty():
			output.append(
				templates.build_location_line(location_id, location)
			)
	return output


func _memory_lines(memories: Array) -> Array[String]:
	var output: Array[String] = []
	for memory_value: Variant in memories:
		var memory := memory_value as Dictionary
		var owner := templates.npc_name(str(memory.get("owner_id", "")))
		output.append(
			"%s 记住了 %s。"
			% [owner, str(memory.get("source_fact_id", ""))]
		)
	return output


func _cause_lines(facts: Array) -> Array[String]:
	var output: Array[String] = []
	for fact_value: Variant in facts:
		var fact := fact_value as Dictionary
		output.append(
			"来源事实：Day %d · %s · %s"
			% [
				int(fact.get("day", 0)),
				str(fact.get("type", "")),
				str(fact.get("fact_id", fact.get("id", ""))),
			]
		)
		var causes := fact.get("cause_fact_ids", []) as Array
		if not causes.is_empty():
			output.append("上游事实：%s" % ", ".join(causes))
	return output


func _quality_lines(context: Dictionary) -> Array[String]:
	var quality := context.get("quality_summary", {}) as Dictionary
	var flags := quality.get("quality_flags", []) as Array
	var output: Array[String] = []
	if flags.is_empty():
		output.append("质量审计：未发现 dangling / impossible / unresolved 标记。")
	else:
		output.append("质量审计：%s" % ", ".join(flags))
	if bool(quality.get("bad_hunger_outcome", false)):
		output.append("饥饿坏结果：已记录。")
	return output


func _state_keys_for_card(context: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for npc_id: String in CORE_NPC_IDS:
		keys.append_array(_state_keys_for_person(npc_id))
	for location_id: String in LOCATION_IDS:
		keys.append_array(_state_keys_for_location(location_id))
	return keys


func _state_keys_for_person(npc_id: String) -> Array[String]:
	return [
		"npc.%s.hunger" % npc_id,
		"npc.%s.fear" % npc_id,
		"npc.%s.health" % npc_id,
		"npc.%s.stress" % npc_id,
		"npc.%s.debt" % npc_id,
		"npc.%s.family_food" % npc_id,
		"npc.%s.location_id" % npc_id,
		"npc.%s.status_tags" % npc_id,
	]


func _state_keys_for_location(location_id: String) -> Array[String]:
	return [
		"location.%s.is_open" % location_id,
		"location.%s.partial_open" % location_id,
		"location.%s.food_stock" % location_id,
		"location.%s.spoiled_grain_stock" % location_id,
		"location.%s.status_tags" % location_id,
		"location.%s.traces" % location_id,
	]


func _person_fields(npc_id: String, npc: Dictionary) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	for field: String in [
		"hunger",
		"fear",
		"health",
		"stress",
		"debt",
		"family_food",
	]:
		if not npc.has(field) or str(npc.get(field, "-")) == "-":
			continue
		fields.append({
			"field": field,
			"value": npc.get(field),
			"level": templates.value_level(npc.get(field)),
		})
	fields.append({
		"field": "location_id",
		"value": npc.get("location_id", "-"),
		"label": templates.location_name(str(npc.get("location_id", ""))),
	})
	fields.append({
		"field": "status_tags",
		"value": (npc.get("status_tags", []) as Array).duplicate(),
	})
	return fields


func _location_fields(
		location_id: String,
		location: Dictionary
	) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	for field: String in [
		"is_open",
		"partial_open",
		"food_stock",
		"spoiled_grain_stock",
		"status_tags",
		"traces",
	]:
		if location.has(field):
			fields.append({
				"field": field,
				"value": _value_copy(location.get(field)),
			})
	return fields


func _severity_for(context: Dictionary) -> String:
	var fact_types := context.get("fact_types", []) as Array
	var npc_snapshot := context.get("npc_snapshot", {}) as Dictionary
	var chen_mi := npc_snapshot.get("chen_mi", {}) as Dictionary
	if (
		"chen_mi_health_crashed_from_hunger" in fact_types
		or bool(
			(context.get("quality_summary", {}) as Dictionary).get(
				"bad_hunger_outcome",
				false
			)
		)
	):
		return "bad_outcome"
	if (
		"chen_mi_collapsed_from_hunger" in fact_types
		or _number(chen_mi.get("hunger", 0.0)) >= 95.0
	):
		return "critical"
	if (
		"ma_shen_emergency_food_for_chen_mi" in fact_types
		or "chen_mi_temporarily_stayed_with_ma_shen" in fact_types
		or "lake_town_emergency_credit_food" in fact_types
	):
		return "recovery"
	if (
		"old_chen_closed_shop_due_to_family_crisis" in fact_types
		or "guard_locked_abandoned_granary" in fact_types
		or "chen_mi_blocked_by_guard_seal" in fact_types
		or "creditor_left_debt_notice" in fact_types
	):
		return "tense"
	return "calm"


func _card_type_for(fact_types: Array, severity: String) -> String:
	if severity == "bad_outcome":
		return "quality_warning"
	if severity == "critical":
		return "crisis"
	if severity == "recovery":
		return "recovery"
	if (
		"old_chen_closed_shop_due_to_family_crisis" in fact_types
		or "old_chen_shop_forced_abnormal_closure" in fact_types
	):
		return "closure"
	if not fact_types.is_empty():
		return "daily_surface"
	return "memory_echo"


func _person_severity(npc: Dictionary) -> String:
	if (
		_number(npc.get("hunger", 0.0)) >= 95.0
		or _number(npc.get("health", 100.0)) <= 35.0
	):
		return "critical"
	if (
		_number(npc.get("hunger", 0.0)) >= 70.0
		or _number(npc.get("stress", 0.0)) >= 85.0
		or _number(npc.get("debt", 0.0)) >= 85.0
	):
		return "tense"
	return "calm"


func _location_severity(location: Dictionary) -> String:
	if (
		location.has("is_open")
		and str(location.get("is_open", "-")) != "-"
		and not bool(location.get("is_open", true))
	):
		return "tense"
	return "calm"


func _tone_tags(facts: Array, severity: String) -> Array[String]:
	var output: Array[String] = [severity]
	for fact_value: Variant in facts:
		var fact := fact_value as Dictionary
		for tag_value: Variant in fact.get("tags", []):
			var tag := str(tag_value)
			if tag != "" and tag not in output:
				output.append(tag)
	return output


func _ids(rows: Array, id_key: String) -> Array[String]:
	var output: Array[String] = []
	for row_value: Variant in rows:
		var id_value := str((row_value as Dictionary).get(id_key, ""))
		if id_value != "" and id_value not in output:
			output.append(id_value)
	return output


func _strings(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value: Variant in values:
		var text := str(value)
		if text != "" and text not in output:
			output.append(text)
	return output


func _unique_lines(lines: Array) -> Array[String]:
	var output: Array[String] = []
	for value: Variant in lines:
		var text := str(value)
		if text != "" and text not in output:
			output.append(text)
	return output


func _value_copy(value: Variant) -> Variant:
	if value is Array:
		return (value as Array).duplicate()
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return value


func _number(value: Variant) -> float:
	if value is String and str(value) == "-":
		return 0.0
	return float(value)


func _sort_cards_by_priority(a: Dictionary, b: Dictionary) -> bool:
	var priority := {
		"bad_outcome": 0,
		"critical": 1,
		"recovery": 2,
		"tense": 3,
		"calm": 4,
	}
	var left := int(priority.get(str(a.get("severity", "calm")), 9))
	var right := int(priority.get(str(b.get("severity", "calm")), 9))
	if left == right:
		return str(a.get("card_id", "")) < str(b.get("card_id", ""))
	return left < right


func _sort_day_then_id(a: Dictionary, b: Dictionary) -> bool:
	var day_a := int(a.get("day", 0))
	var day_b := int(b.get("day", 0))
	if day_a == day_b:
		return str(a.get("id", "")) < str(b.get("id", ""))
	return day_a < day_b
