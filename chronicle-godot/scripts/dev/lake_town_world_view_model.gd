extends RefCounted
class_name LakeTownWorldViewModel

const LocalStoryPipelineModel = preload(
	"res://scripts/sim/local_story_pipeline.gd"
)
const LakeTownModuleModel = preload(
	"res://scripts/sim/modules/lake_town_food_crisis_module.gd"
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
const NPC_FIELDS: Array[String] = [
	"hunger",
	"fear",
	"health",
	"stress",
	"debt",
	"family_food",
	"location_id",
	"status_tags",
]
const LOCATION_STATE_FIELDS: Array[String] = [
	"is_open",
	"partial_open",
	"food_stock",
	"spoiled_grain_stock",
	"status_tags",
]
const FACT_LABELS := {
	"lake_town_food_price_rising": "粮价上涨",
	"chen_mi_took_spoiled_grain": "陈米取走发霉麦子",
	"old_chen_closed_shop_due_to_family_crisis": "老陈因家庭危机闭店",
	"chen_mi_ate_spoiled_grain": "陈米吃下发霉麦子",
	"chen_mi_fell_sick_from_spoiled_grain": "陈米因发霉麦子生病",
	"ma_shen_noticed_closed_shop": "玛婶注意到闭店",
	"ma_shen_brought_porridge": "玛婶送粥",
	"creditor_left_debt_notice": "刘账房留下催债告示",
	"old_chen_reopened_shop_half_day": "老陈半日开店",
	"ma_shen_helped_before_theft": "玛婶在取粮前帮助",
	"old_chen_bought_food_on_credit": "老陈赊账买粮",
	"chen_mi_found_empty_granary": "陈米发现空粮仓",
	"guard_locked_abandoned_granary": "守卫封锁废弃粮仓",
	"creditor_pressed_before_theft": "刘账房在取粮前催债",
	"chen_mi_endured_hunger": "陈米忍耐饥饿",
	"other_family_took_granary_grain": "另一户饥饿家庭先取粮",
	"chen_mi_blocked_by_guard_seal": "陈米被封条挡回",
	"guard_noticed_child_near_granary": "守卫注意到粮仓外的孩子",
	"chen_mi_returned_empty_handed": "陈米空手回到店门口",
	"old_chen_saw_chen_mi_empty_handed": "老陈看见陈米空手回来",
	"chen_mi_weakened_from_enduring_hunger": "陈米因饥饿变虚弱",
	"neighbor_noticed_silent_hungry_child": "邻居注意到沉默的孩子",
	"old_chen_tried_to_delay_debt": "老陈请求推迟债务",
	"creditor_refused_delay_request": "刘账房拒绝延期",
	"chen_mi_found_other_family_tracks": "陈米发现陌生家庭的脚印",
	"market_rumor_about_other_hungry_family": "集市传出饥饿家庭传闻",
	"old_chen_shop_forced_abnormal_closure": "老陈店铺异常关闭",
	"old_chen_shop_half_open_under_debt": "老陈店铺带债半开",
	"ma_shen_early_help_became_household_memory": "玛婶帮助成为家庭记忆",
	"old_chen_credit_purchase_raised_debt_pressure": "赊粮抬高债务压力",
	"old_chen_withheld_delay_request": "老陈没有说出口延期请求",
	"chen_mi_collapsed_from_hunger": "陈米倒在店门口",
	"ma_shen_emergency_food_for_chen_mi": "玛婶紧急给陈米送食",
	"old_chen_sold_shop_goods_for_food": "老陈卖掉店内物品换食物",
	"old_chen_took_chen_mi_to_seek_help": "老陈带陈米离店求助",
	"lake_town_emergency_credit_food": "湖湾镇提供临时救济赊食",
	"chen_mi_health_crashed_from_hunger": "陈米健康因饥饿严重恶化",
	"chen_mi_temporarily_stayed_with_ma_shen": "陈米暂住玛婶家",
	"chen_mi_hunger_unresolved_but_recorded": "持续饥饿被记录为坏结果",
}

var pipeline := LocalStoryPipelineModel.new()
var module := LakeTownModuleModel.new()


func build_view_data(seeds: Array, days: int = 30) -> Dictionary:
	var seed_runs: Array[Dictionary] = []
	var unresolved_count := 0
	var dangling_count := 0
	var impossible_count := 0
	for seed_value: Variant in seeds:
		var run := _simulate_seed(int(seed_value), days)
		seed_runs.append(run)
		var quality := run.get("quality_summary", {}) as Dictionary
		unresolved_count += (
			1
			if bool(quality.get("unresolved_extreme_hunger", false))
			else 0
		)
		dangling_count += (
			1
			if bool(quality.get("dangling_major_fact", false))
			else 0
		)
		impossible_count += (
			1
			if bool(quality.get("impossible_shop_state", false))
			else 0
		)
	return {
		"module": module.describe_module().duplicate(true),
		"days": maxi(days, 0),
		"seed_count": seed_runs.size(),
		"seeds": seed_runs,
		"quality_totals": {
			"unresolved_extreme_hunger": unresolved_count,
			"dangling_major_fact": dangling_count,
			"impossible_shop_state": impossible_count,
		},
	}


func build_seed_summary(run_result: Dictionary) -> Dictionary:
	if run_result.has("seed_summary"):
		return (
			run_result.get("seed_summary", {}) as Dictionary
		).duplicate(true)
	var signature := run_result.get("signature", {}) as Dictionary
	var audit := run_result.get("audit", {}) as Dictionary
	var fact_days := signature.get("fact_days", {}) as Dictionary
	return {
		"seed": int(run_result.get("seed", 0)),
		"outcome_class": String(
			signature.get("outcome_class", "")
		),
		"quality_flag_count": (
			audit.get("quality_flags", []) as Array
		).size(),
		"quality_flags": (
			audit.get("quality_flags", []) as Array
		).duplicate(),
		"bad_hunger_outcome": bool(
			audit.get("bad_hunger_outcome", false)
		),
		"has_grain_taking": _fact_happened(
			fact_days,
			"chen_mi_took_spoiled_grain"
		),
		"has_guard_lock": _fact_happened(
			fact_days,
			"guard_locked_abandoned_granary"
		),
		"has_empty_granary": _fact_happened(
			fact_days,
			"chen_mi_found_empty_granary"
		),
	}


func build_timeline(run_result: Dictionary) -> Array:
	if run_result.has("timeline"):
		return (
			run_result.get("timeline", []) as Array
		).duplicate(true)
	var state: Variant = run_result.get("state")
	if not state is WorldSimState:
		return []
	var rows: Array[Dictionary] = []
	for fact in state.world_facts:
		if _is_lake_town_fact(fact):
			rows.append(_fact_timeline_row(fact))
	rows.sort_custom(_sort_day_then_id)
	return rows


func build_day_detail(
		run_result: Dictionary,
		day: int
	) -> Dictionary:
	var day_details := (
		run_result.get("day_details", {}) as Dictionary
	)
	if day_details.has(str(day)):
		return (
			day_details.get(str(day), {}) as Dictionary
		).duplicate(true)
	return {
		"day": day,
		"facts": _rows_for_day(
			run_result.get("fact_rows", []) as Array,
			day
		),
		"traces": _rows_for_day(
			run_result.get("trace_rows", []) as Array,
			day
		),
		"memories": _rows_for_day(
			run_result.get("memory_rows", []) as Array,
			day
		),
		"narratable_states": _rows_for_day(
			run_result.get("narratable_rows", []) as Array,
			day
		),
		"npc_snapshot": build_npc_snapshot(run_result, day),
		"location_snapshot": build_location_snapshot(
			run_result,
			day
		),
		"quality_flags": [],
	}


func build_npc_snapshot(
		run_result: Dictionary,
		day: int
	) -> Dictionary:
	var snapshots := (
		run_result.get("npc_snapshots", {}) as Dictionary
	)
	return (
		snapshots.get(str(day), {}) as Dictionary
	).duplicate(true)


func build_location_snapshot(
		run_result: Dictionary,
		day: int
	) -> Dictionary:
	var snapshots := (
		run_result.get("location_snapshots", {}) as Dictionary
	)
	return (
		snapshots.get(str(day), {}) as Dictionary
	).duplicate(true)


func build_fact_rows(run_result: Dictionary) -> Array:
	return (
		run_result.get("fact_rows", []) as Array
	).duplicate(true)


func build_trace_rows(run_result: Dictionary) -> Array:
	return (
		run_result.get("trace_rows", []) as Array
	).duplicate(true)


func build_memory_rows(run_result: Dictionary) -> Array:
	return (
		run_result.get("memory_rows", []) as Array
	).duplicate(true)


func build_narratable_rows(run_result: Dictionary) -> Array:
	return (
		run_result.get("narratable_rows", []) as Array
	).duplicate(true)


func build_quality_summary(run_result: Dictionary) -> Dictionary:
	return (
		run_result.get("quality_summary", {}) as Dictionary
	).duplicate(true)


func _simulate_seed(seed_value: int, days: int) -> Dictionary:
	var state: WorldSimState = module.create_state_for_seed(seed_value)
	var profile := module.build_profile_for_seed(seed_value)
	module.initialize_module_state(state, profile)
	var day_details: Dictionary = {}
	var npc_snapshots: Dictionary = {}
	var location_snapshots: Dictionary = {}
	for _index: int in range(maxi(days, 0)):
		var tick := pipeline.tick_once(state, module)
		var day := int(tick.get("day", state.day))
		var npc_snapshot := _snapshot_npcs(state)
		var location_snapshot := _snapshot_locations(state)
		npc_snapshots[str(day)] = npc_snapshot
		location_snapshots[str(day)] = location_snapshot
		day_details[str(day)] = _build_tick_detail(
			state,
			tick,
			npc_snapshot,
			location_snapshot
		)

	var signature: Dictionary = module.build_history_signature(state)
	var audit: Dictionary = module.audit_quality(state, signature)
	var temporary_result := {
		"seed": seed_value,
		"signature": signature,
		"audit": audit,
	}
	var run := {
		"seed": seed_value,
		"days": maxi(days, 0),
		"seed_summary": build_seed_summary(temporary_result),
		"timeline": build_timeline({"state": state}),
		"day_details": day_details,
		"npc_snapshots": npc_snapshots,
		"location_snapshots": location_snapshots,
		"fact_rows": _fact_rows_from_state(state),
		"trace_rows": _trace_rows_from_state(state),
		"memory_rows": _memory_rows_from_state(state),
		"narratable_rows": _narratable_rows_from_state(state),
		"quality_summary": _quality_summary(audit),
		"profile": profile.duplicate(true),
		"raw_signature": signature.duplicate(true),
	}
	return run


func _build_tick_detail(
		state: WorldSimState,
		tick: Dictionary,
		npc_snapshot: Dictionary,
		location_snapshot: Dictionary
	) -> Dictionary:
	return {
		"day": int(tick.get("day", state.day)),
		"facts": _facts_for_ids(
			state,
			tick.get("created_fact_ids", []) as Array
		),
		"traces": _dictionary_rows_for_ids(
			state.traces,
			tick.get("created_trace_ids", []) as Array,
			"trace"
		),
		"memories": _dictionary_rows_for_ids(
			state.memories,
			tick.get("created_memory_ids", []) as Array,
			"memory"
		),
		"narratable_states": _dictionary_rows_for_ids(
			state.narratable_states,
			tick.get(
				"created_narratable_state_ids",
				[]
			) as Array,
			"narratable"
		),
		"npc_snapshot": npc_snapshot.duplicate(true),
		"location_snapshot": location_snapshot.duplicate(true),
		"quality_flags": (
			tick.get("quality_flags", []) as Array
		).duplicate(),
	}


func _snapshot_npcs(state: WorldSimState) -> Dictionary:
	var output: Dictionary = {}
	for npc_id: String in CORE_NPC_IDS:
		var npc := state.get_npc(npc_id)
		var row := {
			"id": npc_id,
			"name": String(npc.get("name", npc_id)),
		}
		for field: String in NPC_FIELDS:
			row[field] = _display_value(npc, field)
		output[npc_id] = row
	return output


func _snapshot_locations(state: WorldSimState) -> Dictionary:
	var output: Dictionary = {}
	for location_id: String in LOCATION_IDS:
		var location := state.get_location(location_id)
		var location_state := (
			location.get("state", {}) as Dictionary
		)
		var row := {
			"id": location_id,
			"name": String(location.get("name", location_id)),
		}
		for field: String in LOCATION_STATE_FIELDS:
			row[field] = _display_value(location_state, field)
		row["status_tags"] = (
			location_state.get(
				"status_tags",
				location.get("tags", [])
			) as Array
		).duplicate()
		row["traces"] = (
			location.get("traces", []) as Array
		).duplicate()
		output[location_id] = row
	return output


func _fact_rows_from_state(state: WorldSimState) -> Array:
	var rows: Array[Dictionary] = []
	for fact in state.world_facts:
		if _is_lake_town_fact(fact):
			rows.append(_fact_row(fact))
	rows.sort_custom(_sort_day_then_id)
	return rows


func _trace_rows_from_state(state: WorldSimState) -> Array:
	var rows: Array[Dictionary] = []
	for value: Variant in state.traces:
		rows.append(_trace_row(value as Dictionary))
	rows.sort_custom(_sort_day_then_id)
	return rows


func _memory_rows_from_state(state: WorldSimState) -> Array:
	var rows: Array[Dictionary] = []
	for value: Variant in state.memories:
		rows.append(_memory_row(value as Dictionary))
	rows.sort_custom(_sort_day_then_id)
	return rows


func _narratable_rows_from_state(state: WorldSimState) -> Array:
	var rows: Array[Dictionary] = []
	for value: Variant in state.narratable_states:
		rows.append(_narratable_row(value as Dictionary))
	rows.sort_custom(_sort_day_then_id)
	return rows


func _facts_for_ids(
		state: WorldSimState,
		ids: Array
	) -> Array:
	var rows: Array[Dictionary] = []
	for fact in state.world_facts:
		if fact.id in ids and _is_lake_town_fact(fact):
			rows.append(_fact_row(fact))
	return rows


func _dictionary_rows_for_ids(
		values: Array,
		ids: Array,
		row_type: String
	) -> Array:
	var rows: Array[Dictionary] = []
	for value: Variant in values:
		var data := value as Dictionary
		if String(data.get("id", "")) not in ids:
			continue
		match row_type:
			"trace":
				rows.append(_trace_row(data))
			"memory":
				rows.append(_memory_row(data))
			"narratable":
				rows.append(_narratable_row(data))
	return rows


func _fact_row(fact: WorldSimState.WorldFact) -> Dictionary:
	return {
		"id": fact.id,
		"fact_id": fact.id,
		"day": fact.day,
		"type": fact.type,
		"summary": String(
			FACT_LABELS.get(fact.type, fact.type)
		),
		"actors": fact.actors.duplicate(),
		"location_id": fact.location_id,
		"region_id": fact.region_id,
		"cause_fact_ids": fact.cause_fact_ids.duplicate(),
		"tags": fact.tags.duplicate(),
	}


func _fact_timeline_row(
		fact: WorldSimState.WorldFact
	) -> Dictionary:
	var row := _fact_row(fact)
	row["label"] = "Day %d | %s | %s" % [
		fact.day,
		fact.type,
		row.get("summary", fact.type),
	]
	return row


func _trace_row(trace: Dictionary) -> Dictionary:
	return {
		"id": String(trace.get("id", "")),
		"trace_id": String(trace.get("id", "")),
		"day": int(trace.get("created_day", 0)),
		"type": String(trace.get("type", "")),
		"location_id": String(trace.get("location_id", "")),
		"source_fact_id": String(
			trace.get("source_fact_id", "")
		),
		"description_tags": (
			trace.get("description_tags", []) as Array
		).duplicate(),
	}


func _memory_row(memory: Dictionary) -> Dictionary:
	var source_fact_id := String(memory.get("fact_id", ""))
	return {
		"id": String(memory.get("id", "")),
		"memory_id": String(memory.get("id", "")),
		"day": int(memory.get("created_day", 0)),
		"type": String(memory.get("type", "")),
		"owner_id": String(memory.get("owner_id", "")),
		"fact_id": source_fact_id,
		"source_fact_id": source_fact_id,
		"tags": (memory.get("tags", []) as Array).duplicate(),
	}


func _narratable_row(scene: Dictionary) -> Dictionary:
	var scene_id := String(scene.get("id", ""))
	return {
		"id": scene_id,
		"narratable_state_id": scene_id,
		"day": int(
			scene.get(
				"created_day",
				scene.get("resolved_day", 0)
			)
		),
		"title": String(
			scene.get("title", scene.get("label", scene_id))
		),
		"source_fact_ids": (
			scene.get("source_fact_ids", []) as Array
		).duplicate(),
		"trace_ids": (
			scene.get("trace_ids", []) as Array
		).duplicate(),
		"status": String(scene.get("status", "")),
		"location_id": String(scene.get("location_id", "")),
	}


func _quality_summary(audit: Dictionary) -> Dictionary:
	return {
		"quality_flags": (
			audit.get("quality_flags", []) as Array
		).duplicate(),
		"dangling_major_fact": bool(
			audit.get("dangling_major_fact", false)
		),
		"impossible_shop_state": bool(
			audit.get("impossible_shop_state", false)
		),
		"unresolved_extreme_hunger": bool(
			audit.get("unresolved_extreme_hunger", false)
		),
		"bad_hunger_outcome": bool(
			audit.get("bad_hunger_outcome", false)
		),
		"branch_closure_depth": int(
			audit.get("branch_closure_depth", 0)
		),
		"consequence_depth": int(
			audit.get("consequence_depth", 0)
		),
	}


func _is_lake_town_fact(fact: WorldSimState.WorldFact) -> bool:
	if fact.region_id == "lake_town":
		return true
	if fact.location_id in LOCATION_IDS:
		return true
	if String(fact.data.get("scope", "")) == "micro":
		return true
	for actor_id: String in fact.actors:
		if actor_id in CORE_NPC_IDS:
			return true
	return FACT_LABELS.has(fact.type)


func _rows_for_day(rows: Array, day: int) -> Array:
	var output: Array[Dictionary] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		if int(row.get("day", -1)) == day:
			output.append(row.duplicate(true))
	return output


func _display_value(data: Dictionary, field: String) -> Variant:
	if not data.has(field):
		return "-"
	var value: Variant = data[field]
	if value is Array:
		return (value as Array).duplicate()
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return value


func _fact_happened(
		fact_days: Dictionary,
		type_name: String
	) -> bool:
	return int(fact_days.get(type_name, -1)) >= 0


func _sort_day_then_id(a: Dictionary, b: Dictionary) -> bool:
	var day_a := int(a.get("day", 0))
	var day_b := int(b.get("day", 0))
	if day_a == day_b:
		return String(a.get("id", "")) < String(b.get("id", ""))
	return day_a < day_b
