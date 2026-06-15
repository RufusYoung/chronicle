extends RefCounted
class_name MicroActionResolver

const SCENE_ID := "chen_mi_hiding_spoiled_grain_scene"
const CHEN_MI_ID := "chen_mi"
const OLD_CHEN_ID := "old_chen"
const SHOP_ID := "old_chen_shop"
const MACRO_REGION_ID := "border_town"
const LOW_GRAIN_PRICE := 1.0

const ACTION_IDS: Array[String] = [
	"give_food_to_chen_mi",
	"ask_grain_origin",
	"report_to_guard",
	"ignore_chen_mi",
	"buy_spoiled_grain_low",
]


func build_action_candidates(
		state: Variant,
		actor_state: Dictionary,
		narratable_state_id: String
	) -> Array:
	var output: Array[Dictionary] = []
	if not state is WorldSimState:
		return output
	var scene := _find_open_scene(state, narratable_state_id)
	if scene.is_empty():
		return output
	for action_id: String in ACTION_IDS:
		if _requirements_met(state, actor_state, action_id, scene):
			output.append(_build_candidate(scene, actor_state, action_id))
	return output


func resolve_micro_action(
		state: Variant,
		actor_state: Dictionary,
		action_id: String,
		narratable_state_id: String
	) -> Dictionary:
	var failed := _base_result(action_id)
	if not state is WorldSimState:
		failed["error"] = "invalid_world_state"
		return failed
	var scene := _find_open_scene(state, narratable_state_id)
	if scene.is_empty() or not _requirements_met(
		state,
		actor_state,
		action_id,
		scene
	):
		failed["error"] = "missing_required_state"
		return failed

	var result := _base_result(action_id)
	match action_id:
		"give_food_to_chen_mi":
			_resolve_give_food(state, actor_state, scene, result)
		"ask_grain_origin":
			_resolve_ask_origin(state, actor_state, scene, result)
		"report_to_guard":
			_resolve_report_to_guard(state, actor_state, scene, result)
		"ignore_chen_mi":
			_resolve_ignore(state, actor_state, scene, result)
		"buy_spoiled_grain_low":
			_resolve_buy_grain(state, actor_state, scene, result)
		_:
			result["error"] = "unknown_action"
			return result
	result["ok"] = true
	return result


func can_resolve_action(
		state: Variant,
		actor_state: Dictionary,
		action_id: String,
		narratable_state_id: String
	) -> bool:
	if not state is WorldSimState:
		return false
	var scene := _find_open_scene(state, narratable_state_id)
	return (
		not scene.is_empty()
		and _requirements_met(state, actor_state, action_id, scene)
	)


func build_action_result_summary(
		before_state: Variant,
		after_state: Variant,
		result: Dictionary
	) -> Dictionary:
	if not before_state is WorldSimState or not after_state is WorldSimState:
		return result.duplicate(true)
	var summary := result.duplicate(true)
	var changes := _selected_state_changes(before_state, after_state)
	var action_changes := result.get("state_changes", {}) as Dictionary
	for key: Variant in action_changes:
		changes[key] = action_changes[key]
	summary["state_changes"] = changes
	summary["created_fact_types"] = _fact_types(
		after_state,
		result.get("created_fact_ids", []) as Array
	)
	summary["created_trace_types"] = _trace_types(
		after_state,
		result.get("created_trace_ids", []) as Array
	)
	summary["created_memory_types"] = _memory_types(
		after_state,
		result.get("created_memory_ids", []) as Array
	)
	return summary


func _build_candidate(
		scene: Dictionary,
		actor_state: Dictionary,
		action_id: String
	) -> Dictionary:
	var definitions := {
		"give_food_to_chen_mi": {
			"label": "给她食物",
			"targets": [CHEN_MI_ID, OLD_CHEN_ID],
			"required_state": {
				"actor.inventory.food_min": 1,
				"chen_mi.hunger_min": 50.0,
			},
			"visible_if": {"actor_has_food": true},
			"risk": 0.05,
			"outcome_preview": "消耗测试 actor 的食物并缓解陈米与老陈的压力。",
			"condition_summary": "需要 actor.inventory.food > 0",
		},
		"ask_grain_origin": {
			"label": "问粮从哪来的",
			"targets": [CHEN_MI_ID, "abandoned_granary"],
			"required_state": {
				"trace_types": ["child_hiding_bag", "spoiled_grain_bag"],
			},
			"visible_if": {"required_traces_visible": true},
			"risk": 0.15,
			"outcome_preview": "记录温和询问并留下废弃粮仓指向。",
			"condition_summary": "需要 child_hiding_bag 与 spoiled_grain_bag Trace",
		},
		"report_to_guard": {
			"label": "举报她",
			"targets": [CHEN_MI_ID, OLD_CHEN_ID, "wardens"],
			"required_state": {
				"guard_system": true,
				"fact_type": "chen_mi_took_spoiled_grain",
			},
			"visible_if": {"guard_system_exists": true},
			"risk": 0.7,
			"outcome_preview": "提高守卫关注并损害测试 actor 与老陈一家的信任。",
			"condition_summary": "需要守卫系统存在",
		},
		"ignore_chen_mi": {
			"label": "装作没看见",
			"targets": [CHEN_MI_ID, OLD_CHEN_ID],
			"required_state": {"scene_open": true},
			"visible_if": {"actor_can_leave": true},
			"risk": 0.35,
			"outcome_preview": "场景被看见但危机未解决，饥饿与压力不下降。",
			"condition_summary": "无特殊条件",
		},
		"buy_spoiled_grain_low": {
			"label": "趁机低价收购",
			"targets": [CHEN_MI_ID, "spoiled_grain"],
			"required_state": {
				"actor.money_min": LOW_GRAIN_PRICE,
				"chen_mi.inventory_contains": "spoiled_grain",
			},
			"visible_if": {"actor_has_money": true},
			"risk": 0.65,
			"outcome_preview": "将发霉麦子转给测试 actor，并加深陈米的不安。",
			"condition_summary": "需要 actor.money > 0 且陈米持有 spoiled_grain",
		},
	}
	var definition := definitions.get(action_id, {}) as Dictionary
	return {
		"id": action_id,
		"label": String(definition.get("label", action_id)),
		"source_narratable_state_id": String(scene.get("id", "")),
		"actor_id": String(actor_state.get("id", "")),
		"target_ids": (definition.get("targets", []) as Array).duplicate(),
		"required_state": (
			definition.get("required_state", {}) as Dictionary
		).duplicate(true),
		"visible_if": (
			definition.get("visible_if", {}) as Dictionary
		).duplicate(true),
		"risk": float(definition.get("risk", 0.0)),
		"outcome_preview": String(definition.get("outcome_preview", "")),
		"condition_summary": String(definition.get("condition_summary", "")),
		"world_cause": String(scene.get("world_cause", "")),
		"source_fact_ids": (
			scene.get("source_fact_ids", []) as Array
		).duplicate(),
		"trace_ids": (scene.get("trace_ids", []) as Array).duplicate(),
		"origin": "micro_world",
	}


func _requirements_met(
		state: WorldSimState,
		actor_state: Dictionary,
		action_id: String,
		scene: Dictionary
	) -> bool:
	if scene.is_empty() or bool(scene.get("action_locked", false)):
		return false
	var chen_mi := state.get_npc(CHEN_MI_ID)
	match action_id:
		"give_food_to_chen_mi":
			var inventory := actor_state.get("inventory", {}) as Dictionary
			return (
				int(inventory.get("food", 0)) > 0
				and float(chen_mi.get("hunger", 0.0)) >= 50.0
			)
		"ask_grain_origin":
			return (
				_has_trace_type(state, "child_hiding_bag")
				and _has_trace_type(state, "spoiled_grain_bag")
			)
		"report_to_guard":
			return _guard_system_exists(state) and _has_fact_type(
				state,
				"chen_mi_took_spoiled_grain"
			)
		"ignore_chen_mi":
			return true
		"buy_spoiled_grain_low":
			var actor_inventory := actor_state.get("inventory", {}) as Dictionary
			var chen_inventory := chen_mi.get("inventory", []) as Array
			return (
				float(actor_state.get("money", 0.0)) >= LOW_GRAIN_PRICE
				and "spoiled_grain" in chen_inventory
				and int(actor_inventory.get("spoiled_grain", 0)) >= 0
			)
	return false


func _resolve_give_food(
		state: WorldSimState,
		actor_state: Dictionary,
		scene: Dictionary,
		result: Dictionary
	) -> void:
	var actor_inventory := actor_state.get("inventory", {}) as Dictionary
	var food_before := int(actor_inventory.get("food", 0))
	actor_inventory["food"] = food_before - 1
	actor_state["inventory"] = actor_inventory
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	chen_mi["hunger"] = maxf(0.0, float(chen_mi.get("hunger", 0.0)) - 35.0)
	chen_mi["fear"] = maxf(0.0, float(chen_mi.get("fear", 0.0)) - 10.0)
	_add_status_tag(chen_mi, "helped_by_actor")
	old_chen["stress"] = maxf(0.0, float(old_chen.get("stress", 0.0)) - 8.0)
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[OLD_CHEN_ID] = old_chen
	_change_trust(state, actor_state, CHEN_MI_ID, 20.0)
	_change_trust(state, actor_state, OLD_CHEN_ID, 8.0)
	var fact := _add_action_fact(
		state,
		scene,
		actor_state,
		"actor_gave_food_to_chen_mi",
		[CHEN_MI_ID, OLD_CHEN_ID],
		{
			"actor.inventory.food_delta": -1,
			"chen_mi.hunger_delta": -35.0,
			"chen_mi.fear_delta": -10.0,
			"old_chen.stress_delta": -8.0,
		},
		["micro_action", "aid", "food_crisis"]
	)
	_record_fact(result, fact)
	_record_memory(
		result,
		_add_memory(
			state,
			"chen_mi_remembers_actor_gave_food",
			CHEN_MI_ID,
			fact.id,
			0.9,
			["aid", "food", String(actor_state.get("id", ""))]
		)
	)
	_record_trace(
		result,
		_add_action_trace(
			state,
			"chen_mi_empty_food_wrap",
			fact.id,
			SHOP_ID,
			CHEN_MI_ID,
			["empty_wrap", "shared_food", "aid"]
		)
	)
	_mark_scene_resolved(state, scene, actor_state, "resolved_with_food")
	result["state_changes"] = {
		"actor.inventory.food": {"before": food_before, "after": food_before - 1},
	}


func _resolve_ask_origin(
		state: WorldSimState,
		actor_state: Dictionary,
		scene: Dictionary,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 4.0,
		0.0,
		100.0
	)
	_add_status_tag(chen_mi, "asked_about_grain")
	state.npcs[CHEN_MI_ID] = chen_mi
	var fact := _add_action_fact(
		state,
		scene,
		actor_state,
		"actor_asked_chen_mi_about_grain",
		[CHEN_MI_ID],
		{"chen_mi.fear_delta": 4.0, "granary_hint_revealed": true},
		["micro_action", "inquiry", "food_crisis"]
	)
	_record_fact(result, fact)
	_record_memory(
		result,
		_add_memory(
			state,
			"chen_mi_was_asked_about_grain",
			CHEN_MI_ID,
			fact.id,
			0.55,
			["questioned", "granary", String(actor_state.get("id", ""))]
		)
	)
	_record_trace(
		result,
		_add_action_trace(
			state,
			"granary_hint",
			fact.id,
			SHOP_ID,
			CHEN_MI_ID,
			["gray_grain_dust", "abandoned_granary", "spoken_hint"]
		)
	)
	_mark_scene_resolved(state, scene, actor_state, "origin_disclosed")


func _resolve_report_to_guard(
		state: WorldSimState,
		actor_state: Dictionary,
		scene: Dictionary,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 20.0,
		0.0,
		100.0
	)
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 12.0,
		0.0,
		100.0
	)
	_add_status_tag(chen_mi, "reported_to_guard")
	_add_status_tag(old_chen, "guard_attention")
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[OLD_CHEN_ID] = old_chen
	_change_trust(state, actor_state, CHEN_MI_ID, -25.0)
	_change_trust(state, actor_state, OLD_CHEN_ID, -15.0)
	var attention := state.micro_state.get("guard_attention", {}) as Dictionary
	attention["wardens"] = clampf(
		float(attention.get("wardens", 0.0)) + 25.0,
		0.0,
		100.0
	)
	state.micro_state["guard_attention"] = attention
	var fact := _add_action_fact(
		state,
		scene,
		actor_state,
		"actor_reported_chen_mi_to_guard",
		[CHEN_MI_ID, OLD_CHEN_ID, "wardens"],
		{
			"chen_mi.fear_delta": 20.0,
			"old_chen.stress_delta": 12.0,
			"wardens.attention_delta": 25.0,
		},
		["micro_action", "report", "guard_pressure"]
	)
	_record_fact(result, fact)
	_record_memory(
		result,
		_add_memory(
			state,
			"chen_mi_remembers_actor_reported_her",
			CHEN_MI_ID,
			fact.id,
			0.95,
			["reported", "guard", String(actor_state.get("id", ""))]
		)
	)
	_record_trace(
		result,
		_add_action_trace(
			state,
			"guard_attention_at_old_chen_shop",
			fact.id,
			SHOP_ID,
			"wardens",
			["guard_questions", "watched_shop", "reported_child"]
		)
	)
	_mark_scene_resolved(state, scene, actor_state, "reported_to_guard")


func _resolve_ignore(
		state: WorldSimState,
		actor_state: Dictionary,
		scene: Dictionary,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	_add_status_tag(chen_mi, "scene_ignored")
	state.npcs[CHEN_MI_ID] = chen_mi
	var fact := _add_action_fact(
		state,
		scene,
		actor_state,
		"actor_ignored_chen_mi_scene",
		[CHEN_MI_ID, OLD_CHEN_ID],
		{
			"chen_mi.hunger_delta": 0.0,
			"old_chen.stress_delta": 0.0,
			"crisis_resolved": false,
		},
		["micro_action", "ignored", "unresolved_crisis"]
	)
	_record_fact(result, fact)
	_record_memory(
		result,
		_add_memory(
			state,
			"scene_was_ignored",
			String(actor_state.get("id", "test_actor")),
			fact.id,
			0.35,
			["ignored", "unresolved", CHEN_MI_ID]
		)
	)
	_mark_scene_resolved(state, scene, actor_state, "seen_but_unresolved")


func _resolve_buy_grain(
		state: WorldSimState,
		actor_state: Dictionary,
		scene: Dictionary,
		result: Dictionary
	) -> void:
	var money_before := float(actor_state.get("money", 0.0))
	actor_state["money"] = money_before - LOW_GRAIN_PRICE
	var actor_inventory := actor_state.get("inventory", {}) as Dictionary
	var actor_grain_before := int(actor_inventory.get("spoiled_grain", 0))
	actor_inventory["spoiled_grain"] = actor_grain_before + 1
	actor_state["inventory"] = actor_inventory
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var chen_inventory := chen_mi.get("inventory", []) as Array
	chen_inventory.erase("spoiled_grain")
	chen_mi["inventory"] = chen_inventory
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 12.0,
		0.0,
		100.0
	)
	chen_mi["hunger"] = maxf(
		0.0,
		float(chen_mi.get("hunger", 0.0)) - 3.0
	)
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 8.0,
		0.0,
		100.0
	)
	_add_status_tag(chen_mi, "grain_taken_by_actor")
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[OLD_CHEN_ID] = old_chen
	_change_trust(state, actor_state, CHEN_MI_ID, -20.0)
	_change_trust(state, actor_state, OLD_CHEN_ID, -10.0)
	var fact := _add_action_fact(
		state,
		scene,
		actor_state,
		"actor_bought_spoiled_grain_low",
		[CHEN_MI_ID, OLD_CHEN_ID],
		{
			"actor.money_delta": -LOW_GRAIN_PRICE,
			"actor.inventory.spoiled_grain_delta": 1,
			"chen_mi.inventory.spoiled_grain_delta": -1,
			"chen_mi.fear_delta": 12.0,
			"old_chen.stress_delta": 8.0,
		},
		["micro_action", "exploitative_trade", "spoiled_food"]
	)
	_record_fact(result, fact)
	_record_memory(
		result,
		_add_memory(
			state,
			"chen_mi_remembers_actor_took_grain",
			CHEN_MI_ID,
			fact.id,
			0.85,
			["grain_taken", "low_price", String(actor_state.get("id", ""))]
		)
	)
	_record_trace(
		result,
		_add_action_trace(
			state,
			"missing_spoiled_grain_bag",
			fact.id,
			SHOP_ID,
			CHEN_MI_ID,
			["missing_bag", "low_price_trade", "spoiled_grain"]
		)
	)
	_mark_scene_resolved(state, scene, actor_state, "grain_bought_low")
	result["state_changes"] = {
		"actor.money": {
			"before": money_before,
			"after": money_before - LOW_GRAIN_PRICE,
		},
		"actor.inventory.spoiled_grain": {
			"before": actor_grain_before,
			"after": actor_grain_before + 1,
		},
	}


func _add_action_fact(
		state: WorldSimState,
		scene: Dictionary,
		actor_state: Dictionary,
		type_name: String,
		target_ids: Array,
		effects: Dictionary,
		tags: Array
	) -> WorldSimState.WorldFact:
	var actors: Array = [String(actor_state.get("id", "test_actor"))]
	for target_id: Variant in target_ids:
		if not target_id in actors:
			actors.append(String(target_id))
	return state.add_fact(
		type_name,
		"lake_town",
		"wardens" if type_name == "actor_reported_chen_mi_to_guard" else "",
		{
			"scope": "micro",
			"actors": actors,
			"location_id": SHOP_ID,
			"cause_fact_ids": (
				scene.get("source_fact_ids", []) as Array
			).duplicate(),
			"effects": effects.duplicate(true),
			"tags": tags.duplicate(),
			"importance": 0.75,
			"world_cause": String(scene.get("world_cause", "")),
			"source_narratable_state_id": String(scene.get("id", "")),
			"source_trace_ids": (
				scene.get("trace_ids", []) as Array
			).duplicate(),
		}
	)


func _add_action_trace(
		state: WorldSimState,
		type_name: String,
		source_fact_id: String,
		location_id: String,
		npc_id: String,
		description_tags: Array
	) -> Dictionary:
	var trace := {
		"id": "trace_d%02d_%03d_%s" % [
			state.day,
			state.traces.size() + 1,
			type_name,
		],
		"type": type_name,
		"source_fact_id": source_fact_id,
		"location_id": location_id,
		"npc_id": npc_id,
		"visibility": 0.9,
		"freshness": 1.0,
		"description_tags": description_tags.duplicate(),
		"created_day": state.day,
	}
	state.traces.append(trace)
	var location := state.get_location(location_id)
	if not location.is_empty():
		var trace_ids := location.get("traces", []) as Array
		trace_ids.append(trace["id"])
		location["traces"] = trace_ids
		state.locations[location_id] = location
	return trace


func _add_memory(
		state: WorldSimState,
		type_name: String,
		owner_id: String,
		fact_id: String,
		emotional_weight: float,
		tags: Array
	) -> Dictionary:
	var memory := {
		"id": "memory_d%02d_%03d_%s" % [
			state.day,
			state.memories.size() + 1,
			type_name,
		],
		"type": type_name,
		"owner_id": owner_id,
		"fact_id": fact_id,
		"emotional_weight": clampf(emotional_weight, 0.0, 1.0),
		"decay": 0.0,
		"tags": tags.duplicate(),
		"created_day": state.day,
	}
	state.memories.append(memory)
	var owner := state.get_npc(owner_id)
	if not owner.is_empty():
		var memory_ids := owner.get("memories", []) as Array
		memory_ids.append(memory["id"])
		owner["memories"] = memory_ids
		state.npcs[owner_id] = owner
	return memory


func _change_trust(
		state: WorldSimState,
		actor_state: Dictionary,
		target_id: String,
		delta: float
	) -> void:
	var actor_id := String(actor_state.get("id", "test_actor"))
	var relationships := (
		state.micro_state.get("micro_relationships", {}) as Dictionary
	)
	var actor_relationships := relationships.get(actor_id, {}) as Dictionary
	var relationship := actor_relationships.get(
		target_id,
		{"trust": 0.0, "last_interaction_day": 0}
	) as Dictionary
	relationship["trust"] = clampf(
		float(relationship.get("trust", 0.0)) + delta,
		-100.0,
		100.0
	)
	relationship["last_interaction_day"] = state.day
	actor_relationships[target_id] = relationship
	relationships[actor_id] = actor_relationships
	state.micro_state["micro_relationships"] = relationships


func _mark_scene_resolved(
		state: WorldSimState,
		scene: Dictionary,
		actor_state: Dictionary,
		resolution_state: String
	) -> void:
	for index: int in range(state.narratable_states.size()):
		var candidate := state.narratable_states[index]
		if String(candidate.get("id", "")) != String(scene.get("id", "")):
			continue
		candidate["status"] = resolution_state
		candidate["action_locked"] = true
		candidate["resolved_day"] = state.day
		candidate["resolved_by_actor_id"] = String(
			actor_state.get("id", "test_actor")
		)
		state.narratable_states[index] = candidate
		return


func _find_open_scene(
		state: WorldSimState,
		narratable_state_id: String
	) -> Dictionary:
	if narratable_state_id != SCENE_ID:
		return {}
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if (
			String(scene.get("id", "")) == narratable_state_id
			and not bool(scene.get("action_locked", false))
		):
			return scene
	return {}


func _guard_system_exists(state: WorldSimState) -> bool:
	var region := state.get_region(MACRO_REGION_ID)
	return (
		region != null
		and region.owner_faction_id == "wardens"
		and state.get_faction("wardens") != null
	)


func _has_fact_type(state: WorldSimState, type_name: String) -> bool:
	for fact: WorldSimState.WorldFact in state.world_facts:
		if fact.type == type_name:
			return true
	return false


func _has_trace_type(state: WorldSimState, type_name: String) -> bool:
	for trace_value: Variant in state.traces:
		var trace := trace_value as Dictionary
		if String(trace.get("type", "")) == type_name:
			return true
	return false


func _add_status_tag(npc: Dictionary, tag: String) -> void:
	var tags := npc.get("status_tags", []) as Array
	if not tag in tags:
		tags.append(tag)
	npc["status_tags"] = tags


func _base_result(action_id: String) -> Dictionary:
	return {
		"ok": false,
		"action_id": action_id,
		"created_fact_ids": [],
		"created_trace_ids": [],
		"created_memory_ids": [],
		"state_changes": {},
		"error": "",
	}


func _record_fact(result: Dictionary, fact: WorldSimState.WorldFact) -> void:
	(result["created_fact_ids"] as Array).append(fact.id)


func _record_trace(result: Dictionary, trace: Dictionary) -> void:
	(result["created_trace_ids"] as Array).append(String(trace.get("id", "")))


func _record_memory(result: Dictionary, memory: Dictionary) -> void:
	(result["created_memory_ids"] as Array).append(String(memory.get("id", "")))


func _selected_state_changes(
		before_state: WorldSimState,
		after_state: WorldSimState
	) -> Dictionary:
	var before := _selected_state(before_state)
	var after := _selected_state(after_state)
	var output: Dictionary = {}
	for key: Variant in before:
		if before[key] != after.get(key):
			output[key] = {"before": before[key], "after": after.get(key)}
	return output


func _selected_state(state: WorldSimState) -> Dictionary:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var shop := state.get_location(SHOP_ID)
	return {
		"chen_mi.hunger": float(chen_mi.get("hunger", 0.0)),
		"chen_mi.fear": float(chen_mi.get("fear", 0.0)),
		"chen_mi.inventory": (
			chen_mi.get("inventory", []) as Array
		).duplicate(),
		"chen_mi.status_tags": (
			chen_mi.get("status_tags", []) as Array
		).duplicate(),
		"old_chen.stress": float(old_chen.get("stress", 0.0)),
		"old_chen.status_tags": (
			old_chen.get("status_tags", []) as Array
		).duplicate(),
		"old_chen_shop.traces": (
			shop.get("traces", []) as Array
		).duplicate(),
		"micro_relationships": (
			state.micro_state.get("micro_relationships", {}) as Dictionary
		).duplicate(true),
		"guard_attention": (
			state.micro_state.get("guard_attention", {}) as Dictionary
		).duplicate(true),
		"narratable_states": state.narratable_states.duplicate(true),
	}


func _fact_types(state: WorldSimState, ids: Array) -> Array[String]:
	var output: Array[String] = []
	for id_value: Variant in ids:
		for fact: WorldSimState.WorldFact in state.world_facts:
			if fact.id == String(id_value):
				output.append(fact.type)
				break
	return output


func _trace_types(state: WorldSimState, ids: Array) -> Array[String]:
	var output: Array[String] = []
	for id_value: Variant in ids:
		for trace_value: Variant in state.traces:
			var trace := trace_value as Dictionary
			if String(trace.get("id", "")) == String(id_value):
				output.append(String(trace.get("type", "")))
				break
	return output


func _memory_types(state: WorldSimState, ids: Array) -> Array[String]:
	var output: Array[String] = []
	for id_value: Variant in ids:
		for memory_value: Variant in state.memories:
			var memory := memory_value as Dictionary
			if String(memory.get("id", "")) == String(id_value):
				output.append(String(memory.get("type", "")))
				break
	return output
