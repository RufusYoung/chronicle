extends RefCounted
class_name LakeTownRecoverySystem

const MICRO_REGION_ID := "lake_town"
const SHOP_ID := "old_chen_shop"
const OLD_CHEN_ID := "old_chen"
const CHEN_MI_ID := "chen_mi"
const MA_SHEN_ID := "ma_shen"
const LIU_ZHANGFANG_ID := "liu_zhangfang"
const TEST_ACTOR_ID := "test_actor"

const RECOVERY_IDS: Array[String] = [
	"chen_mi_stabilized_after_food_help",
	"old_chen_softened_after_actor_help",
	"ma_shen_kept_checking_on_chen_mi",
	"old_chen_reopened_shop_half_day",
	"creditor_delayed_collection_after_support",
]

const RELATIONSHIP_ECHO_IDS: Array[String] = [
	"chen_mi_trust_echo_for_actor",
	"chen_mi_avoidance_echo_for_actor",
	"old_chen_closes_door_to_actor",
]

const RELATIONSHIP_NUMERIC_FIELDS: Array[String] = [
	"trust",
	"fear",
	"gratitude",
	"resentment",
	"debt",
	"familiarity",
]


func tick_recovery(state: Variant) -> Array:
	var results: Array[Dictionary] = []
	if not state is WorldSimState:
		return results
	_ensure_recovery_state(state)
	for recovery_id: String in RECOVERY_IDS:
		if _can_apply_recovery(state, recovery_id):
			var result := apply_recovery(state, recovery_id)
			if bool(result.get("ok", false)):
				results.append(result)
	for echo_id: String in RELATIONSHIP_ECHO_IDS:
		if _can_apply_relationship_echo(state, echo_id):
			var result := apply_relationship_echo(state, echo_id)
			if bool(result.get("ok", false)):
				results.append(result)
	return results


func build_recovery_candidates(state: Variant) -> Array:
	var output: Array[Dictionary] = []
	if not state is WorldSimState:
		return output
	_ensure_recovery_state(state)
	for recovery_id: String in RECOVERY_IDS:
		if _can_apply_recovery(state, recovery_id):
			output.append({
				"id": recovery_id,
				"recovery_key": recovery_id,
				"source": "lake_town_structured_state",
			})
	return output


func apply_recovery(state: Variant, recovery_id: String) -> Dictionary:
	var result := _base_result(recovery_id, "recovery")
	if not state is WorldSimState:
		result["error"] = "invalid_world_state"
		return result
	_ensure_recovery_state(state)
	if not _can_apply_recovery(state, recovery_id):
		result["error"] = "missing_required_state"
		return result

	match recovery_id:
		"chen_mi_stabilized_after_food_help":
			_apply_chen_mi_stabilized(state, result)
		"old_chen_softened_after_actor_help":
			_apply_old_chen_softened(state, result)
		"ma_shen_kept_checking_on_chen_mi":
			_apply_ma_shen_kept_checking(state, result)
		"old_chen_reopened_shop_half_day":
			_apply_old_chen_reopened_half_day(state, result)
		"creditor_delayed_collection_after_support":
			_apply_creditor_delayed_collection(state, result)
		_:
			result["error"] = "unknown_recovery"
			return result
	result["ok"] = true
	return result


func has_recovery_happened(state: Variant, recovery_key: String) -> bool:
	if not state is WorldSimState:
		return false
	var recovery_state := state.micro_state.get(
		"recovery_state",
		{}
	) as Dictionary
	for entry_value: Variant in recovery_state.get("recovery_history", []):
		var entry := entry_value as Dictionary
		if String(entry.get("recovery_key", "")) == recovery_key:
			return true
	return false


func record_recovery(
		state: Variant,
		recovery_key: String,
		fact_id: String
	) -> void:
	if not state is WorldSimState or recovery_key == "" or fact_id == "":
		return
	if has_recovery_happened(state, recovery_key):
		return
	_ensure_recovery_state(state)
	var recovery_state := state.micro_state.get(
		"recovery_state",
		{}
	) as Dictionary
	var history := recovery_state.get("recovery_history", []) as Array
	history.append({
		"recovery_key": recovery_key,
		"fact_id": fact_id,
		"day": state.day,
		"kind": (
			"relationship_echo"
			if recovery_key in RELATIONSHIP_ECHO_IDS
			else "recovery"
		),
	})
	recovery_state["recovery_history"] = history
	recovery_state["last_recovery_day"] = state.day
	state.micro_state["recovery_state"] = recovery_state


func build_relationship_echoes(state: Variant) -> Array:
	var output: Array[Dictionary] = []
	if not state is WorldSimState:
		return output
	_ensure_recovery_state(state)
	for echo_id: String in RELATIONSHIP_ECHO_IDS:
		if _can_apply_relationship_echo(state, echo_id):
			output.append({
				"id": echo_id,
				"echo_key": echo_id,
				"source": "lake_town_relationship_state",
			})
	return output


func apply_relationship_echo(state: Variant, echo_id: String) -> Dictionary:
	var result := _base_result(echo_id, "relationship_echo")
	if not state is WorldSimState:
		result["error"] = "invalid_world_state"
		return result
	_ensure_recovery_state(state)
	if not _can_apply_relationship_echo(state, echo_id):
		result["error"] = "missing_required_state"
		return result

	match echo_id:
		"chen_mi_trust_echo_for_actor":
			_apply_chen_mi_trust_echo(state, result)
		"chen_mi_avoidance_echo_for_actor":
			_apply_chen_mi_avoidance_echo(state, result)
		"old_chen_closes_door_to_actor":
			_apply_old_chen_closes_door(state, result)
		_:
			result["error"] = "unknown_relationship_echo"
			return result
	result["ok"] = true
	return result


func get_micro_relationship(
		state: Variant,
		from_id: String,
		to_id: String
	) -> Dictionary:
	if (
		not state is WorldSimState
		or from_id == ""
		or to_id == ""
	):
		return {}
	_ensure_recovery_state(state)
	var relationships := state.micro_state.get(
		"micro_relationships",
		{}
	) as Dictionary
	var outgoing := relationships.get(from_id, {}) as Dictionary
	var relationship := _normalize_relationship(
		outgoing.get(to_id, {}) as Dictionary
	)
	outgoing[to_id] = relationship
	relationships[from_id] = outgoing
	state.micro_state["micro_relationships"] = relationships
	return relationship


func adjust_micro_relationship(
		state: Variant,
		from_id: String,
		to_id: String,
		delta: Dictionary,
		source_fact_id: String
	) -> void:
	if (
		not state is WorldSimState
		or from_id == ""
		or to_id == ""
		or source_fact_id == ""
	):
		return
	var relationship := get_micro_relationship(state, from_id, to_id)
	if relationship.is_empty():
		return
	var applied_delta: Dictionary = {}
	for field: String in RELATIONSHIP_NUMERIC_FIELDS:
		if not delta.has(field):
			continue
		var minimum := -100.0 if field == "trust" else 0.0
		var before := float(relationship.get(field, 0.0))
		var change := float(delta.get(field, 0.0))
		relationship[field] = clampf(before + change, minimum, 100.0)
		applied_delta[field] = change
	relationship["last_interaction_day"] = state.day
	var sources := relationship.get("source_fact_ids", []) as Array
	if not source_fact_id in sources:
		sources.append(source_fact_id)
	relationship["source_fact_ids"] = sources
	var history := relationship.get("history", []) as Array
	history.append({
		"day": state.day,
		"source_fact_id": source_fact_id,
		"delta": applied_delta,
	})
	relationship["history"] = history
	_store_relationship(state, from_id, to_id, relationship)


func add_relationship_tag(
		state: Variant,
		from_id: String,
		to_id: String,
		tag: String,
		source_fact_id: String
	) -> void:
	if tag == "" or source_fact_id == "":
		return
	var relationship := get_micro_relationship(state, from_id, to_id)
	if relationship.is_empty():
		return
	var tags := relationship.get("tags", []) as Array
	if not tag in tags:
		tags.append(tag)
	relationship["tags"] = tags
	var sources := relationship.get("source_fact_ids", []) as Array
	if not source_fact_id in sources:
		sources.append(source_fact_id)
	relationship["source_fact_ids"] = sources
	var history := relationship.get("history", []) as Array
	history.append({
		"day": state.day,
		"source_fact_id": source_fact_id,
		"tag": tag,
	})
	relationship["history"] = history
	relationship["last_interaction_day"] = state.day
	_store_relationship(state, from_id, to_id, relationship)


func _ensure_recovery_state(state: WorldSimState) -> void:
	if not state.micro_state.has("micro_relationships"):
		state.micro_state["micro_relationships"] = {}
	var relationships := state.micro_state.get(
		"micro_relationships",
		{}
	) as Dictionary
	for from_value: Variant in relationships.keys():
		var from_id := String(from_value)
		var outgoing := relationships.get(from_id, {}) as Dictionary
		for to_value: Variant in outgoing.keys():
			var to_id := String(to_value)
			outgoing[to_id] = _normalize_relationship(
				outgoing.get(to_id, {}) as Dictionary
			)
		relationships[from_id] = outgoing
	state.micro_state["micro_relationships"] = relationships

	var recovery_state := state.micro_state.get(
		"recovery_state",
		{}
	) as Dictionary
	var defaults := {
		"chen_mi_recovery_level": 0.0,
		"old_chen_recovery_level": 0.0,
		"shop_recovery_level": 0.0,
		"community_support": 0.0,
		"actor_reputation_in_lake_town": 0.0,
		"actor_reputation_tags": [],
		"recovery_history": [],
		"last_recovery_day": -1,
	}
	for key: String in defaults:
		if not recovery_state.has(key):
			recovery_state[key] = defaults[key]
	state.micro_state["recovery_state"] = recovery_state


func _default_relationship() -> Dictionary:
	return {
		"trust": 0.0,
		"fear": 0.0,
		"gratitude": 0.0,
		"resentment": 0.0,
		"debt": 0.0,
		"familiarity": 0.0,
		"last_interaction_day": -1,
		"tags": [],
		"source_fact_ids": [],
		"source_memory_ids": [],
		"history": [],
	}


func _normalize_relationship(existing: Dictionary) -> Dictionary:
	var relationship := _default_relationship()
	for key: Variant in existing:
		relationship[key] = existing[key]
	for field: String in RELATIONSHIP_NUMERIC_FIELDS:
		var minimum := -100.0 if field == "trust" else 0.0
		relationship[field] = clampf(
			float(relationship.get(field, 0.0)),
			minimum,
			100.0
		)
	for array_key: String in [
		"tags",
		"source_fact_ids",
		"source_memory_ids",
		"history",
	]:
		relationship[array_key] = (
			relationship.get(array_key, []) as Array
		).duplicate(true)
	relationship["last_interaction_day"] = int(
		relationship.get("last_interaction_day", -1)
	)
	return relationship


func _store_relationship(
		state: WorldSimState,
		from_id: String,
		to_id: String,
		relationship: Dictionary
	) -> void:
	var relationships := state.micro_state.get(
		"micro_relationships",
		{}
	) as Dictionary
	var outgoing := relationships.get(from_id, {}) as Dictionary
	outgoing[to_id] = relationship
	relationships[from_id] = outgoing
	state.micro_state["micro_relationships"] = relationships


func _can_apply_recovery(
		state: WorldSimState,
		recovery_id: String
	) -> bool:
	if has_recovery_happened(state, recovery_id):
		return false
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var ma_shen := state.get_npc(MA_SHEN_ID)
	var liu := state.get_npc(LIU_ZHANGFANG_ID)
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	var recovery_state := state.micro_state.get(
		"recovery_state",
		{}
	) as Dictionary
	match recovery_id:
		"chen_mi_stabilized_after_food_help":
			return (
				_has_fact_type(state, "actor_gave_food_to_chen_mi")
				and float(chen_mi.get("hunger", 100.0)) < 60.0
				and not _has_fact_type(
					state,
					"chen_mi_ate_spoiled_grain"
				)
			)
		"old_chen_softened_after_actor_help":
			var relationship := get_micro_relationship(
				state,
				OLD_CHEN_ID,
				TEST_ACTOR_ID
			)
			return (
				_has_fact_type(state, "actor_gave_food_to_chen_mi")
				and (
					float(old_chen.get("stress", 100.0)) < 90.0
					or float(relationship.get("trust", 0.0)) > 0.0
				)
				and not _has_fact_type(
					state,
					"chen_mi_fell_sick_from_spoiled_grain"
				)
			)
		"ma_shen_kept_checking_on_chen_mi":
			return (
				_has_fact_type(state, "ma_shen_brought_porridge")
				and float(ma_shen.get("concern", 0.0)) >= 50.0
				and (
					float(chen_mi.get("health", 100.0)) < 85.0
					or float(chen_mi.get("hunger", 0.0)) >= 55.0
				)
			)
		"old_chen_reopened_shop_half_day":
			return (
				not bool(shop_state.get("is_open", true))
				and float(
					recovery_state.get("old_chen_recovery_level", 0.0)
				) >= 25.0
				and (
					float(old_chen.get("family_food", 0.0)) > 0.0
					or _has_fact_type(state, "ma_shen_brought_porridge")
				)
				and float(old_chen.get("stress", 100.0)) < 95.0
			)
		"creditor_delayed_collection_after_support":
			return (
				_has_fact_type(state, "creditor_left_debt_notice")
				and (
					float(
						recovery_state.get("community_support", 0.0)
					) >= 20.0
					or float(
						recovery_state.get(
							"old_chen_recovery_level",
							0.0
						)
					) >= 25.0
				)
				and (
					bool(shop_state.get("partial_open", false))
					or _has_fact_type(
						state,
						"ma_shen_kept_checking_on_chen_mi"
					)
				)
				and float(liu.get("patience", 0.0)) > 0.0
			)
	return false


func _can_apply_relationship_echo(
		state: WorldSimState,
		echo_id: String
	) -> bool:
	if has_recovery_happened(state, echo_id):
		return false
	var chen_to_actor := get_micro_relationship(
		state,
		CHEN_MI_ID,
		TEST_ACTOR_ID
	)
	var old_to_actor := get_micro_relationship(
		state,
		OLD_CHEN_ID,
		TEST_ACTOR_ID
	)
	var positive_fact := _latest_fact(
		state,
		[
			"actor_gave_food_to_chen_mi",
			"chen_mi_stabilized_after_food_help",
		]
	)
	var negative_fact := _latest_fact(
		state,
		[
			"actor_reported_chen_mi_to_guard",
			"actor_bought_spoiled_grain_low",
		]
	)
	match echo_id:
		"chen_mi_trust_echo_for_actor":
			return (
				positive_fact != null
				and state.day > positive_fact.day
				and (
					_has_memory_type(
						state,
						"chen_mi_remembers_actor_gave_food"
					)
					or _has_memory_type(
						state,
						"chen_mi_remembers_food_help_after_crisis"
					)
				)
				and (
					float(chen_to_actor.get("gratitude", 0.0)) >= 20.0
					or float(chen_to_actor.get("trust", 0.0)) >= 25.0
				)
			)
		"chen_mi_avoidance_echo_for_actor":
			return (
				negative_fact != null
				and state.day > negative_fact.day
				and (
					_has_memory_type(
						state,
						"chen_mi_remembers_actor_reported_her"
					)
					or _has_memory_type(
						state,
						"chen_mi_remembers_actor_took_grain"
					)
					or float(
						chen_to_actor.get("resentment", 0.0)
					) >= 20.0
					or float(chen_to_actor.get("fear", 0.0)) >= 20.0
				)
			)
		"old_chen_closes_door_to_actor":
			return (
				negative_fact != null
				and state.day > negative_fact.day
				and float(old_to_actor.get("trust", 0.0)) < 0.0
				and not state.get_location(SHOP_ID).is_empty()
			)
	return false


func _apply_chen_mi_stabilized(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var health_before := float(chen_mi.get("health", 100.0))
	var fear_before := float(chen_mi.get("fear", 0.0))
	chen_mi["health"] = minf(100.0, health_before + 4.0)
	chen_mi["fear"] = maxf(0.0, fear_before - 8.0)
	_add_status(chen_mi, "stabilized_by_actor_help")
	state.npcs[CHEN_MI_ID] = chen_mi
	_change_recovery_metric(state, "chen_mi_recovery_level", 35.0)
	_change_reputation(state, 6.0, "helped_chen_mi_recover")
	var action_fact := _find_fact(state, "actor_gave_food_to_chen_mi")
	var fact := _add_recovery_fact(
		state,
		"chen_mi_stabilized_after_food_help",
		[CHEN_MI_ID, TEST_ACTOR_ID],
		[action_fact.id],
		{
			"chen_mi.health_delta": 4.0,
			"chen_mi.fear_delta": -8.0,
			"chen_mi_recovery_level_delta": 35.0,
		},
		["recovery", "food_help", "child"]
	)
	adjust_micro_relationship(
		state,
		CHEN_MI_ID,
		TEST_ACTOR_ID,
		{"trust": 8.0, "gratitude": 10.0, "familiarity": 5.0},
		fact.id
	)
	add_relationship_tag(
		state,
		CHEN_MI_ID,
		TEST_ACTOR_ID,
		"stabilized_by_help",
		fact.id
	)
	var trace := _add_trace(
		state,
		"folded_food_wrap_kept_by_chen_mi",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		["folded_wrap", "remembered_help", "kept_object"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_remembers_food_help_after_crisis",
		CHEN_MI_ID,
		fact.id,
		0.95,
		["food_help", "recovery", TEST_ACTOR_ID]
	)
	_add_narratable_state(
		state,
		"chen_mi_remembers_help_scene",
		"陈米把那张食物包装纸仔细折好留了下来",
		fact,
		[trace],
		[CHEN_MI_ID, TEST_ACTOR_ID]
	)
	_finish_result(state, result, fact, [trace], [memory])


func _apply_old_chen_softened(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var stress_before := float(old_chen.get("stress", 0.0))
	old_chen["stress"] = maxf(0.0, stress_before - 12.0)
	_add_status(old_chen, "actor_help_acknowledged")
	state.npcs[OLD_CHEN_ID] = old_chen
	_change_recovery_metric(state, "old_chen_recovery_level", 30.0)
	_change_recovery_metric(state, "shop_recovery_level", 10.0)
	_change_reputation(state, 5.0, "old_chen_acknowledged_help")
	var action_fact := _find_fact(state, "actor_gave_food_to_chen_mi")
	var stable_fact := _find_fact(
		state,
		"chen_mi_stabilized_after_food_help"
	)
	var causes: Array = [action_fact.id]
	if stable_fact != null:
		causes.append(stable_fact.id)
	var fact := _add_recovery_fact(
		state,
		"old_chen_softened_after_actor_help",
		[OLD_CHEN_ID, TEST_ACTOR_ID],
		causes,
		{
			"old_chen.stress_delta": -12.0,
			"old_chen_recovery_level_delta": 30.0,
			"shop_recovery_level_delta": 10.0,
		},
		["recovery", "family", "acknowledged_help"]
	)
	adjust_micro_relationship(
		state,
		OLD_CHEN_ID,
		TEST_ACTOR_ID,
		{"trust": 10.0, "gratitude": 10.0, "familiarity": 5.0},
		fact.id
	)
	add_relationship_tag(
		state,
		OLD_CHEN_ID,
		TEST_ACTOR_ID,
		"helped_family",
		fact.id
	)
	var trace := _add_trace(
		state,
		"shop_door_unlatched_for_actor",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		["unlatched_door", "recognized_helper", "family_relief"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_actor_helped_chen_mi",
		OLD_CHEN_ID,
		fact.id,
		0.9,
		["actor_help", "family", TEST_ACTOR_ID]
	)
	_finish_result(state, result, fact, [trace], [memory])


func _apply_ma_shen_kept_checking(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	chen_mi["fear"] = maxf(
		0.0,
		float(chen_mi.get("fear", 0.0)) - 5.0
	)
	old_chen["stress"] = maxf(
		0.0,
		float(old_chen.get("stress", 0.0)) - 10.0
	)
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[OLD_CHEN_ID] = old_chen
	_change_recovery_metric(state, "community_support", 30.0)
	_change_recovery_metric(state, "old_chen_recovery_level", 25.0)
	var porridge_fact := _find_fact(state, "ma_shen_brought_porridge")
	var fact := _add_recovery_fact(
		state,
		"ma_shen_kept_checking_on_chen_mi",
		[MA_SHEN_ID, CHEN_MI_ID, OLD_CHEN_ID],
		[porridge_fact.id],
		{
			"community_support_delta": 30.0,
			"old_chen_recovery_level_delta": 25.0,
			"chen_mi.fear_delta": -5.0,
			"old_chen.stress_delta": -10.0,
		},
		["recovery", "neighbor", "community_support"]
	)
	adjust_micro_relationship(
		state,
		MA_SHEN_ID,
		OLD_CHEN_ID,
		{"trust": 8.0, "familiarity": 12.0},
		fact.id
	)
	add_relationship_tag(
		state,
		MA_SHEN_ID,
		OLD_CHEN_ID,
		"kept_checking_on_family",
		fact.id
	)
	var trace := _add_trace(
		state,
		"neighbor_visit_marks",
		fact.id,
		SHOP_ID,
		MA_SHEN_ID,
		["repeated_footprints", "neighbor_visit", "continued_concern"]
	)
	var memories: Array = [
		_add_memory(
			state,
			"kept_checking_on_chen_mi",
			MA_SHEN_ID,
			fact.id,
			0.75,
			["neighbor", "continued_support", CHEN_MI_ID]
		),
		_add_memory(
			state,
			"chen_mi_remembers_ma_shen_checking",
			CHEN_MI_ID,
			fact.id,
			0.8,
			["neighbor", "care", MA_SHEN_ID]
		),
	]
	_finish_result(state, result, fact, [trace], memories)


func _apply_old_chen_reopened_half_day(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	shop_state["is_open"] = true
	shop_state["partial_open"] = true
	shop_state["partial_open_since_day"] = state.day
	shop["state"] = shop_state
	var tags := shop.get("tags", []) as Array
	if not "half_open" in tags:
		tags.append("half_open")
	shop["tags"] = tags
	state.locations[SHOP_ID] = shop
	var old_chen := state.get_npc(OLD_CHEN_ID)
	_add_status(old_chen, "shop_half_open")
	state.npcs[OLD_CHEN_ID] = old_chen
	_change_recovery_metric(state, "shop_recovery_level", 40.0)
	var cause := _latest_fact(
		state,
		[
			"old_chen_softened_after_actor_help",
			"ma_shen_kept_checking_on_chen_mi",
			"ma_shen_brought_porridge",
		]
	)
	var fact := _add_recovery_fact(
		state,
		"old_chen_reopened_shop_half_day",
		[OLD_CHEN_ID],
		[cause.id],
		{
			"old_chen_shop.is_open": true,
			"old_chen_shop.partial_open": true,
			"shop_recovery_level_delta": 40.0,
		},
		["recovery", "shop", "half_open"]
	)
	var traces: Array = [
		_add_trace(
			state,
			"half_open_shop_door",
			fact.id,
			SHOP_ID,
			OLD_CHEN_ID,
			["half_open_door", "limited_hours", "cautious_recovery"]
		),
		_add_trace(
			state,
			"limited_goods_on_shelf",
			fact.id,
			SHOP_ID,
			OLD_CHEN_ID,
			["sparse_shelf", "limited_goods", "food_crisis_continues"]
		),
	]
	var memory := _add_memory(
		state,
		"old_chen_remembers_reopening_half_day",
		OLD_CHEN_ID,
		fact.id,
		0.7,
		["shop", "partial_recovery", "family_crisis"]
	)
	_add_narratable_state(
		state,
		"half_open_old_chen_shop_scene",
		"老陈把店门开了一半，货架上只摆着少量东西",
		fact,
		traces,
		[OLD_CHEN_ID, CHEN_MI_ID]
	)
	_finish_result(state, result, fact, traces, [memory])


func _apply_creditor_delayed_collection(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var liu := state.get_npc(LIU_ZHANGFANG_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	liu["patience"] = minf(
		100.0,
		float(liu.get("patience", 0.0)) + 15.0
	)
	old_chen["stress"] = maxf(
		0.0,
		float(old_chen.get("stress", 0.0)) - 8.0
	)
	state.npcs[LIU_ZHANGFANG_ID] = liu
	state.npcs[OLD_CHEN_ID] = old_chen
	state.micro_state["debt_pressure"] = maxf(
		0.0,
		float(state.micro_state.get("debt_pressure", 0.0)) - 20.0
	)
	var notice_fact := _find_fact(state, "creditor_left_debt_notice")
	var support_fact := _latest_fact(
		state,
		[
			"old_chen_reopened_shop_half_day",
			"ma_shen_kept_checking_on_chen_mi",
		]
	)
	var fact := _add_recovery_fact(
		state,
		"creditor_delayed_collection_after_support",
		[LIU_ZHANGFANG_ID, OLD_CHEN_ID],
		[notice_fact.id, support_fact.id],
		{
			"liu_zhangfang.patience_delta": 15.0,
			"old_chen.stress_delta": -8.0,
			"debt_pressure_delta": -20.0,
		},
		["recovery", "debt", "delayed_collection"]
	)
	var trace := _add_trace(
		state,
		"crossed_out_due_date_on_notice",
		fact.id,
		SHOP_ID,
		LIU_ZHANGFANG_ID,
		["crossed_out_date", "collection_delayed", "debt_remains"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_delayed_collection",
		OLD_CHEN_ID,
		fact.id,
		0.75,
		["debt", "temporary_relief", LIU_ZHANGFANG_ID]
	)
	_add_narratable_state(
		state,
		"delayed_debt_collection_scene",
		"催债告示上的期限被划掉，旁边补写了一个更晚的日期",
		fact,
		[trace],
		[OLD_CHEN_ID, LIU_ZHANGFANG_ID]
	)
	_finish_result(state, result, fact, [trace], [memory])


func _apply_chen_mi_trust_echo(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var source := _latest_fact(
		state,
		[
			"chen_mi_stabilized_after_food_help",
			"actor_gave_food_to_chen_mi",
		]
	)
	var fact := _add_echo_fact(
		state,
		"chen_mi_trust_echo_for_actor",
		[CHEN_MI_ID, TEST_ACTOR_ID],
		[source.id],
		{
			"chen_mi_to_actor.trust_delta": 8.0,
			"chen_mi_to_actor.familiarity_delta": 15.0,
		},
		["relationship_echo", "trust", "remembered_help"]
	)
	adjust_micro_relationship(
		state,
		CHEN_MI_ID,
		TEST_ACTOR_ID,
		{"trust": 8.0, "familiarity": 15.0},
		fact.id
	)
	add_relationship_tag(
		state,
		CHEN_MI_ID,
		TEST_ACTOR_ID,
		"recognizes_helper",
		fact.id
	)
	_change_reputation(state, 5.0, "remembered_as_helper")
	var trace := _add_trace(
		state,
		"small_wave_from_chen_mi",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		["small_wave", "recognition", "cautious_trust"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_recalls_actor_kindness",
		CHEN_MI_ID,
		fact.id,
		0.95,
		["kindness", "recognition", TEST_ACTOR_ID]
	)
	_add_narratable_state(
		state,
		"chen_mi_recognizes_actor_scene",
		"陈米认出了曾经给她食物的人",
		fact,
		[trace],
		[CHEN_MI_ID, TEST_ACTOR_ID],
		["comfort_chen_mi"]
	)
	_finish_result(state, result, fact, [trace], [memory])


func _apply_chen_mi_avoidance_echo(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var source := _latest_fact(
		state,
		[
			"actor_reported_chen_mi_to_guard",
			"actor_bought_spoiled_grain_low",
		]
	)
	var fact := _add_echo_fact(
		state,
		"chen_mi_avoidance_echo_for_actor",
		[CHEN_MI_ID, TEST_ACTOR_ID],
		[source.id],
		{
			"chen_mi_to_actor.trust_delta": -10.0,
			"chen_mi_to_actor.fear_delta": 10.0,
			"chen_mi_to_actor.resentment_delta": 12.0,
		},
		["relationship_echo", "avoidance", "remembered_harm"]
	)
	adjust_micro_relationship(
		state,
		CHEN_MI_ID,
		TEST_ACTOR_ID,
		{
			"trust": -10.0,
			"fear": 10.0,
			"resentment": 12.0,
			"familiarity": 8.0,
		},
		fact.id
	)
	add_relationship_tag(
		state,
		CHEN_MI_ID,
		TEST_ACTOR_ID,
		"avoids_actor",
		fact.id
	)
	_change_reputation(
		state,
		-10.0,
		(
			"reported_chen_mi"
			if source.type == "actor_reported_chen_mi_to_guard"
			else "exploited_chen_mi"
		)
	)
	var trace := _add_trace(
		state,
		"chen_mi_avoids_actor_gaze",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		["averted_gaze", "fear", "remembered_harm"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_recalls_actor_harm",
		CHEN_MI_ID,
		fact.id,
		0.98,
		["harm", "avoidance", TEST_ACTOR_ID]
	)
	_add_narratable_state(
		state,
		"chen_mi_avoids_actor_scene",
		"陈米看见那个人靠近时避开了目光",
		fact,
		[trace],
		[CHEN_MI_ID, TEST_ACTOR_ID]
	)
	_finish_result(state, result, fact, [trace], [memory])


func _apply_old_chen_closes_door(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	shop_state["actor_access_blocked"] = true
	shop_state["door_closed_to_actor"] = true
	shop["state"] = shop_state
	state.locations[SHOP_ID] = shop
	var source := _latest_fact(
		state,
		[
			"chen_mi_avoidance_echo_for_actor",
			"actor_reported_chen_mi_to_guard",
			"actor_bought_spoiled_grain_low",
		]
	)
	var negative_action := _latest_fact(
		state,
		[
			"actor_reported_chen_mi_to_guard",
			"actor_bought_spoiled_grain_low",
		]
	)
	var causes: Array = [negative_action.id]
	if source.id != negative_action.id:
		causes.append(source.id)
	var fact := _add_echo_fact(
		state,
		"old_chen_closes_door_to_actor",
		[OLD_CHEN_ID, TEST_ACTOR_ID],
		causes,
		{
			"old_chen_shop.actor_access_blocked": true,
			"old_chen_to_actor.trust_delta": -8.0,
			"old_chen_to_actor.resentment_delta": 12.0,
		},
		["relationship_echo", "closed_door", "family_protection"]
	)
	adjust_micro_relationship(
		state,
		OLD_CHEN_ID,
		TEST_ACTOR_ID,
		{"trust": -8.0, "fear": 5.0, "resentment": 12.0},
		fact.id
	)
	add_relationship_tag(
		state,
		OLD_CHEN_ID,
		TEST_ACTOR_ID,
		"refuses_actor",
		fact.id
	)
	_change_reputation(state, -8.0, "old_chen_refuses_actor")
	var trace := _add_trace(
		state,
		"shop_door_closed_when_actor_near",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		["closed_to_actor", "refusal", "family_protection"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_actor_harmed_family",
		OLD_CHEN_ID,
		fact.id,
		0.95,
		["family_harm", "refusal", TEST_ACTOR_ID]
	)
	_add_narratable_state(
		state,
		"old_chen_refuses_actor_scene",
		"老陈看见那个人靠近时把店门重新合上",
		fact,
		[trace],
		[OLD_CHEN_ID, TEST_ACTOR_ID]
	)
	_finish_result(state, result, fact, [trace], [memory])


func _add_recovery_fact(
		state: WorldSimState,
		type_name: String,
		actors: Array,
		cause_ids: Array,
		effects: Dictionary,
		tags: Array
	) -> WorldSimState.WorldFact:
	return _add_structured_fact(
		state,
		type_name,
		actors,
		cause_ids,
		effects,
		tags,
		"recovery_key"
	)


func _add_echo_fact(
		state: WorldSimState,
		type_name: String,
		actors: Array,
		cause_ids: Array,
		effects: Dictionary,
		tags: Array
	) -> WorldSimState.WorldFact:
	return _add_structured_fact(
		state,
		type_name,
		actors,
		cause_ids,
		effects,
		tags,
		"relationship_echo_key"
	)


func _add_structured_fact(
		state: WorldSimState,
		type_name: String,
		actors: Array,
		cause_ids: Array,
		effects: Dictionary,
		tags: Array,
		key_name: String
	) -> WorldSimState.WorldFact:
	var filtered_causes: Array[String] = []
	for cause_value: Variant in cause_ids:
		var cause_id := String(cause_value)
		if cause_id != "" and not cause_id in filtered_causes:
			filtered_causes.append(cause_id)
	var fact_data := {
		"scope": "micro",
		"actors": actors.duplicate(),
		"location_id": SHOP_ID,
		"cause_fact_ids": filtered_causes,
		"effects": effects.duplicate(true),
		"tags": tags.duplicate(),
		"importance": 0.8,
		"world_cause": "lake_town_recovery_echo",
	}
	fact_data[key_name] = type_name
	return state.add_fact(
		type_name,
		MICRO_REGION_ID,
		"",
		fact_data
	)


func _add_trace(
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


func _add_narratable_state(
		state: WorldSimState,
		scene_id: String,
		title: String,
		fact: WorldSimState.WorldFact,
		traces: Array,
		npc_ids: Array,
		action_hints: Array = []
	) -> void:
	if _narratable_exists(state, scene_id):
		return
	var trace_ids: Array[String] = []
	for trace_value: Variant in traces:
		var trace := trace_value as Dictionary
		trace_ids.append(String(trace.get("id", "")))
	state.narratable_states.append({
		"id": scene_id,
		"type": "micro_recovery_scene",
		"title": title,
		"location_id": SHOP_ID,
		"npc_ids": npc_ids.duplicate(),
		"trace_ids": trace_ids,
		"source_fact_ids": [fact.id],
		"world_cause": "lake_town_recovery_echo",
		"importance": fact.importance,
		"status": "open",
		"action_locked": false,
		"available_actions_hint": action_hints.duplicate(),
		"created_day": state.day,
	})


func _finish_result(
		state: WorldSimState,
		result: Dictionary,
		fact: WorldSimState.WorldFact,
		traces: Array,
		memories: Array
	) -> void:
	record_recovery(state, fact.type, fact.id)
	result["fact_id"] = fact.id
	(result["created_fact_ids"] as Array).append(fact.id)
	for trace_value: Variant in traces:
		var trace := trace_value as Dictionary
		(result["created_trace_ids"] as Array).append(
			String(trace.get("id", ""))
		)
	for memory_value: Variant in memories:
		var memory := memory_value as Dictionary
		(result["created_memory_ids"] as Array).append(
			String(memory.get("id", ""))
		)


func _change_recovery_metric(
		state: WorldSimState,
		key: String,
		delta: float
	) -> void:
	var recovery_state := state.micro_state.get(
		"recovery_state",
		{}
	) as Dictionary
	var value := float(recovery_state.get(key, 0.0)) + delta
	recovery_state[key] = clampf(value, 0.0, 100.0)
	state.micro_state["recovery_state"] = recovery_state


func _change_reputation(
		state: WorldSimState,
		delta: float,
		tag: String
	) -> void:
	var recovery_state := state.micro_state.get(
		"recovery_state",
		{}
	) as Dictionary
	recovery_state["actor_reputation_in_lake_town"] = clampf(
		float(
			recovery_state.get("actor_reputation_in_lake_town", 0.0)
		) + delta,
		-100.0,
		100.0
	)
	var tags := recovery_state.get("actor_reputation_tags", []) as Array
	if tag != "" and not tag in tags:
		tags.append(tag)
	recovery_state["actor_reputation_tags"] = tags
	state.micro_state["recovery_state"] = recovery_state


func _find_fact(
		state: WorldSimState,
		type_name: String
	) -> WorldSimState.WorldFact:
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact := state.world_facts[index]
		if fact.type == type_name:
			return fact
	return null


func _latest_fact(
		state: WorldSimState,
		type_names: Array
	) -> WorldSimState.WorldFact:
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact := state.world_facts[index]
		if fact.type in type_names:
			return fact
	return null


func _has_fact_type(state: WorldSimState, type_name: String) -> bool:
	return _find_fact(state, type_name) != null


func _has_memory_type(state: WorldSimState, type_name: String) -> bool:
	for memory_value: Variant in state.memories:
		var memory := memory_value as Dictionary
		if String(memory.get("type", "")) == type_name:
			return true
	return false


func _add_status(npc: Dictionary, tag: String) -> void:
	var tags := npc.get("status_tags", []) as Array
	if not tag in tags:
		tags.append(tag)
	npc["status_tags"] = tags


func _narratable_exists(state: WorldSimState, scene_id: String) -> bool:
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if String(scene.get("id", "")) == scene_id:
			return true
	return false


func _base_result(rule_id: String, kind: String) -> Dictionary:
	return {
		"ok": false,
		"rule_id": rule_id,
		"kind": kind,
		"fact_id": "",
		"created_fact_ids": [],
		"created_trace_ids": [],
		"created_memory_ids": [],
		"error": "",
	}
