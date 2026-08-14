extends RefCounted
class_name V5CombatEncounterResolver

const ActionContractResolverModel = preload(
	"res://scripts/sim/action/action_contract_resolver.gd"
)
const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)

const ROLL_MINIMUM := 1
const ROLL_MAXIMUM := 6

var action_resolver: Variant = ActionContractResolverModel.new()


func configure(registry: Variant) -> void:
	action_resolver.configure(registry)


func preview(
		encounter: Dictionary,
		snapshot: Variant,
		approach_id: String,
		actor_id: String = "player"
) -> Dictionary:
	var encounter_id := str(encounter.get("encounter_id", ""))
	var enemy: Dictionary = encounter.get("enemy", {})
	var approach := _approach(encounter, approach_id)
	if encounter_id == "":
		return _invalid_preview("missing_encounter_id")
	if enemy.is_empty() or str(enemy.get("entity_id", "")) == "":
		return _invalid_preview("missing_enemy")
	if approach.is_empty():
		return _invalid_preview("unknown_approach:%s" % approach_id)
	var score_target := str(approach.get("score_target", ""))
	if score_target == "":
		return _invalid_preview("missing_score_target:%s" % approach_id)

	var contract := _action_contract(
		encounter, enemy, approach, snapshot, actor_id
	)
	var evaluation: Dictionary = action_resolver.evaluate(
		snapshot,
		contract,
		actor_id,
		str(enemy.get("entity_id", ""))
	)
	var base_values: Dictionary = evaluation.get("base_values", {})
	var modified_values: Dictionary = evaluation.get("modified_values", {})
	var base_score := int(round(float(base_values.get(score_target, 0))))
	var effective_score := int(round(float(
		modified_values.get(score_target, base_score)
	)))
	var difficulty := _difficulty(enemy, approach)
	var required_roll := difficulty - effective_score
	var guard := int(round(float(modified_values.get(
		"combat.guard", base_values.get("combat.guard", 0)
	))))
	var potential_costs := _potential_costs(
		approach.get("failure", {}), enemy, snapshot, actor_id, guard
	)
	return {
		"ok": true,
		"encounter_id": encounter_id,
		"approach_id": approach_id,
		"approach_label": str(approach.get("label", approach_id)),
		"enemy_observation": {
			"entity_id": str(enemy.get("entity_id", "")),
			"display_name": str(enemy.get("display_name", "未知敌人")),
			"danger_label": str(enemy.get("danger_label", "未知")),
			"observable_features": (enemy.get(
				"observable_features", []
			) as Array).duplicate(true),
			"observable_tags": (enemy.get(
				"observable_tags", enemy.get("tags", [])
			) as Array).duplicate(true),
		},
		"score_target": score_target,
		"base_score": base_score,
		"effective_score": effective_score,
		"guard": guard,
		"difficulty": difficulty,
		"required_roll": required_roll,
		"success_possible": required_roll <= ROLL_MAXIMUM,
		"guaranteed_success": required_roll <= ROLL_MINIMUM,
		"risk_label": _risk_label(required_roll),
		"possible_costs": potential_costs,
		"base_values": base_values,
		"modified_values": modified_values,
		"requirements": evaluation.get("requirements", []),
		"can_execute": bool(evaluation.get("can_execute", true)),
		"blocked_reason": str(evaluation.get("blocked_reason", "")),
		"modifier_explanations": evaluation.get(
			"modifier_explanations", []
		),
		"modifier_evaluations": evaluation.get("modifier_evaluations", []),
	}


func resolve_attempt(
		encounter: Dictionary,
		snapshot: Variant,
		approach_id: String,
		roll: int,
		event_id: int,
		time_summary: Dictionary = {},
		actor_id: String = "player"
) -> Variant:
	var result = TransactionResultModel.new()
	var preview_data := preview(encounter, snapshot, approach_id, actor_id)
	if not bool(preview_data.get("ok", false)):
		result.mark_invalid_contract(
			"combat_encounter",
			str(preview_data.get("error", "invalid_encounter"))
		)
		return result
	if not bool(preview_data.get("can_execute", true)):
		result.mark_invalid_contract(
			"combat_encounter",
			str(preview_data.get("blocked_reason", "approach_blocked"))
		)
		return result
	if roll < ROLL_MINIMUM or roll > ROLL_MAXIMUM:
		result.mark_invalid_contract(
			"combat_encounter", "combat_roll_out_of_range"
		)
		return result

	var approach := _approach(encounter, approach_id)
	var enemy: Dictionary = encounter.get("enemy", {})
	var total := roll + int(preview_data.get("effective_score", 0))
	var difficulty := int(preview_data.get("difficulty", 0))
	var succeeded := total >= difficulty
	var outcome := "success" if succeeded else "failure"
	var consequence: Dictionary = approach.get(outcome, {})
	var fact_id := "fact.combat_encounter.%s.%d" % [
		_safe_id(str(encounter.get("encounter_id", "encounter"))), event_id,
	]
	var source_item_ids := _source_equipment_ids(
		preview_data.get("modifier_explanations", [])
	)
	var worn_item_id := _equipped_item_id(
		snapshot,
		actor_id,
		str(consequence.get("durability_slot", ""))
	)
	if worn_item_id != "" and worn_item_id not in source_item_ids:
		source_item_ids.append(worn_item_id)
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "actor_resolved_combat_encounter",
		"actor_id": actor_id,
		"source_id": actor_id,
		"target_id": str(enemy.get("entity_id", "")),
		"encounter_id": str(encounter.get("encounter_id", "")),
		"selection_group_id": str(encounter.get("selection_group_id", "")),
		"approach_id": approach_id,
		"roll": roll,
		"score_target": str(preview_data.get("score_target", "")),
		"base_score": int(preview_data.get("base_score", 0)),
		"effective_score": int(preview_data.get("effective_score", 0)),
		"difficulty": difficulty,
		"total": total,
		"margin": total - difficulty,
		"outcome": outcome,
		"nonlethal_contract": true,
		"source_item_ids": source_item_ids,
		"modifier_explanations": (
			preview_data.get("modifier_explanations", []) as Array
		).duplicate(true),
		"day": int(time_summary.get("day", 0)),
		"hour": int(time_summary.get("hour", 0)),
		"tick": int(time_summary.get("tick", event_id)),
		"summary": "%s以%s处理%s，检定 %d 对难度 %d，结果为%s。" % [
			_entity_name(snapshot, actor_id),
			str(preview_data.get("approach_label", approach_id)),
			str((preview_data.get("enemy_observation", {}) as Dictionary).get(
				"display_name", "敌人"
			)),
			total,
			difficulty,
			"成功" if succeeded else "失败",
		],
	})

	var applied_costs := _append_consequences(
		result,
		consequence,
		enemy,
		snapshot,
		actor_id,
		fact_id,
		int(preview_data.get("guard", 0)),
		time_summary
	)
	var default_summary := (
		"你稳住了局面，装备和身体都记下了这次交锋。"
		if succeeded
		else "你没能压住局面，但代价是伤势和装备磨损，而不是立即死亡。"
	)
	result.set_narrative_result({
		"title": str(consequence.get(
			"narrative_title", "遭遇处理成功" if succeeded else "遭遇处理受挫"
		)),
		"summary": str(consequence.get("narrative", default_summary)),
		"encounter_id": str(encounter.get("encounter_id", "")),
		"selection_group_id": str(encounter.get("selection_group_id", "")),
		"approach_id": approach_id,
		"outcome": outcome,
		"roll": roll,
		"base_score": int(preview_data.get("base_score", 0)),
		"effective_score": int(preview_data.get("effective_score", 0)),
		"difficulty": difficulty,
		"total": total,
		"modifier_explanations": preview_data.get(
			"modifier_explanations", []
		),
		"applied_costs": applied_costs,
	})
	result.mark_resolved("combat_encounter")
	return result


func _action_contract(
		encounter: Dictionary,
		enemy: Dictionary,
		approach: Dictionary,
		snapshot: Variant,
		actor_id: String
) -> Dictionary:
	var action_tags: Array = ["combat"]
	for tag: Variant in approach.get("action_tags", []):
		if tag not in action_tags:
			action_tags.append(tag)
	var context_tags: Array = (encounter.get("context_tags", []) as Array).duplicate()
	for tag: Variant in enemy.get("observable_tags", enemy.get("tags", [])):
		var enemy_tag := "enemy_%s" % str(tag)
		if enemy_tag not in context_tags:
			context_tags.append(enemy_tag)
	return {
		"action_id": "combat.%s.%s" % [
			str(encounter.get("encounter_id", "encounter")),
			str(approach.get("approach_id", "approach")),
		],
		"label": str(approach.get("label", "处理遭遇")),
		"action_tags": action_tags,
		"context_tags": context_tags,
		"requirements": approach.get("requirements", []),
		"base_values": _base_values(snapshot, actor_id, approach),
		"modifiers": approach.get("modifiers", []),
	}


func _base_values(
		snapshot: Variant, actor_id: String, approach: Dictionary
) -> Dictionary:
	var strength := _attribute(snapshot, actor_id, "strength")
	var dexterity := _attribute(snapshot, actor_id, "dexterity")
	var wisdom := _attribute(snapshot, actor_id, "wisdom")
	var charisma := _attribute(snapshot, actor_id, "charisma")
	var constitution := _attribute(snapshot, actor_id, "constitution")
	var perception := _attribute(snapshot, actor_id, "perception")
	return {
		"combat.attack": strength + int(floor(float(dexterity) / 2.0))
			+ int(approach.get("attack_bonus", 0)),
		"combat.guard": constitution + int(floor(float(perception) / 2.0))
			+ int(approach.get("guard_bonus", 0)),
		"combat.escape": dexterity + int(floor(float(perception) / 2.0))
			+ int(approach.get("escape_bonus", 0)),
		"combat.influence": charisma + int(floor(float(wisdom) / 2.0))
			+ int(approach.get("influence_bonus", 0)),
		"combat.control": wisdom + int(floor(float(perception) / 2.0))
			+ int(approach.get("control_bonus", 0)),
	}


func _append_consequences(
		result: Variant,
		consequence: Dictionary,
		enemy: Dictionary,
		snapshot: Variant,
		actor_id: String,
		fact_id: String,
		guard: int,
		time_summary: Dictionary
) -> Dictionary:
	var costs := _potential_costs(
		consequence, enemy, snapshot, actor_id, guard
	)
	var health_loss := int(costs.get("health_loss", 0))
	if health_loss > 0:
		result.add_state_change({
			"entity_id": actor_id,
			"key": "health",
			"delta": -health_loss,
		})
	var fatigue_gain := int(costs.get("fatigue_gain", 0))
	if fatigue_gain > 0:
		result.add_state_change({
			"entity_id": actor_id,
			"key": "fatigue",
			"delta": fatigue_gain,
		})
	var injury := str(costs.get("injury", ""))
	if injury != "":
		result.add_fact({
			"fact_id": "%s.injury" % fact_id,
			"fact_type": "actor_injured_during_combat",
			"actor_id": actor_id,
			"source_id": actor_id,
			"target_id": str(enemy.get("entity_id", "")),
			"injury": injury,
			"source_fact_ids": [fact_id],
			"day": int(time_summary.get("day", 0)),
			"hour": int(time_summary.get("hour", 0)),
			"tick": int(time_summary.get("tick", 0)),
			"summary": "%s在遭遇中受了%s。" % [
				_entity_name(snapshot, actor_id),
				str(consequence.get("injury_label", injury)),
			],
		})
	_append_equipment_wear(
		result, snapshot, actor_id, fact_id, costs, time_summary
	)
	_append_configured_state_changes(
		result,
		consequence.get("state_changes", []),
		actor_id,
		str(enemy.get("entity_id", "")),
		snapshot
	)
	_append_configured_facts(
		result,
		consequence.get("additional_facts", []),
		actor_id,
		str(enemy.get("entity_id", "")),
		fact_id,
		time_summary
	)
	return costs


func _append_equipment_wear(
		result: Variant,
		snapshot: Variant,
		actor_id: String,
		fact_id: String,
		costs: Dictionary,
		time_summary: Dictionary
) -> void:
	var loss := int(costs.get("durability_loss", 0))
	var slot_id := str(costs.get("durability_slot", ""))
	if loss <= 0 or slot_id == "":
		return
	var item: Dictionary = snapshot.get_equipped_item(actor_id, slot_id)
	if item.is_empty():
		return
	var condition: Dictionary = item.get("condition", {})
	var maximum := int(condition.get("maximum_durability", 0))
	if maximum <= 0:
		return
	var current := int(condition.get("durability", maximum))
	var next := maxi(current - loss, 0)
	result.add_item_change({
		"operation": "adjust_durability",
		"item_instance_id": str(item.get("item_instance_id", "")),
		"to": next,
		"source_fact_ids": [fact_id],
		"updated_tick": int(time_summary.get("tick", 0)),
	})
	if next == 0:
		result.add_equipment_change({
			"operation": "equipment_clear",
			"entity_id": actor_id,
			"slot_id": slot_id,
			"source_fact_ids": [fact_id],
			"updated_tick": int(time_summary.get("tick", 0)),
		})


func _append_configured_state_changes(
		result: Variant,
		change_values: Variant,
		actor_id: String,
		enemy_id: String,
		snapshot: Variant
) -> void:
	if not change_values is Array:
		return
	for change_value: Variant in change_values:
		if not change_value is Dictionary:
			continue
		var change := (change_value as Dictionary).duplicate(true)
		var entity_id := str(change.get("entity_id", ""))
		if entity_id == "actor":
			entity_id = actor_id
		elif entity_id == "enemy":
			entity_id = enemy_id
		if entity_id == "" or str(change.get("key", "")) == "":
			continue
		if not change.has("to") and not change.has("delta"):
			continue
		change["entity_id"] = entity_id
		if (
			change.has("to")
			and snapshot.get_entity_state(
				entity_id, str(change.get("key", "")), null
			) == change.get("to")
		):
			continue
		result.add_state_change(change)


func _append_configured_facts(
		result: Variant,
		fact_values: Variant,
		actor_id: String,
		enemy_id: String,
		source_fact_id: String,
		time_summary: Dictionary
) -> void:
	if not fact_values is Array:
		return
	var index := 0
	for fact_value: Variant in fact_values:
		if not fact_value is Dictionary:
			continue
		var fact_type := str((fact_value as Dictionary).get("fact_type", ""))
		if fact_type == "":
			continue
		index += 1
		var fact := (fact_value as Dictionary).duplicate(true)
		fact["fact_id"] = "%s.consequence.%d" % [source_fact_id, index]
		fact["source_id"] = str(fact.get("source_id", actor_id))
		var target_id := str(fact.get("target_id", enemy_id))
		if target_id == "actor":
			target_id = actor_id
		elif target_id == "enemy":
			target_id = enemy_id
		fact["target_id"] = target_id
		fact["source_fact_ids"] = [source_fact_id]
		fact["observed_by_player"] = bool(fact.get(
			"observed_by_player", true
		))
		fact["day"] = int(time_summary.get("day", 0))
		fact["hour"] = int(time_summary.get("hour", 0))
		fact["tick"] = int(time_summary.get("tick", 0))
		result.add_fact(fact)


func _potential_costs(
		consequence_value: Variant,
		enemy: Dictionary,
		snapshot: Variant,
		actor_id: String,
		guard: int
) -> Dictionary:
	var consequence: Dictionary = (
		consequence_value if consequence_value is Dictionary else {}
	)
	var current_health := int(_state_value(
		snapshot, actor_id, "health", 100
	))
	var apply_enemy_pressure := bool(consequence.get(
		"apply_enemy_pressure",
		int(consequence.get("base_health_loss", 0)) > 0
	))
	var pressure_damage := (
		maxi(int(enemy.get("attack", 0)) - guard, 0)
		if apply_enemy_pressure
		else 0
	)
	var requested_loss := maxi(
		int(consequence.get("base_health_loss", 0)) + pressure_damage,
		0
	)
	var health_loss := mini(requested_loss, maxi(current_health - 1, 0))
	var costs := {
		"health_loss": health_loss,
		"fatigue_gain": maxi(int(consequence.get("fatigue_gain", 0)), 0),
		"injury": str(consequence.get("injury", "")),
		"injury_label": str(consequence.get(
			"injury_label", consequence.get("injury", "")
		)),
		"durability_loss": maxi(int(consequence.get(
			"durability_loss", 0
		)), 0),
		"durability_slot": str(consequence.get("durability_slot", "")),
		"nonlethal": true,
	}
	var descriptions: Array[String] = []
	if health_loss > 0:
		descriptions.append("健康最多损失 %d，保留至少 1 点" % health_loss)
	if int(costs.get("fatigue_gain", 0)) > 0:
		descriptions.append("疲劳增加 %d" % int(costs.get("fatigue_gain", 0)))
	if str(costs.get("injury", "")) != "":
		descriptions.append("可能留下%s" % str(costs.get("injury_label", "伤势")))
	if int(costs.get("durability_loss", 0)) > 0:
		descriptions.append("%s装备耐久最多损失 %d" % [
			str(costs.get("durability_slot", "对应栏位")),
			int(costs.get("durability_loss", 0)),
		])
	costs["descriptions"] = descriptions
	return costs


func _approach(encounter: Dictionary, approach_id: String) -> Dictionary:
	var source: Variant = encounter.get("approaches", [])
	if source is Dictionary:
		var keyed: Variant = (source as Dictionary).get(approach_id, {})
		if keyed is Dictionary:
			var row := (keyed as Dictionary).duplicate(true)
			row["approach_id"] = approach_id
			return row
	if source is Array:
		for value: Variant in source:
			if value is Dictionary and str(
				(value as Dictionary).get("approach_id", "")
			) == approach_id:
				return (value as Dictionary).duplicate(true)
	return {}


func _difficulty(enemy: Dictionary, approach: Dictionary) -> int:
	if approach.has("difficulty"):
		return int(approach.get("difficulty", 10))
	return int(enemy.get(str(approach.get(
		"difficulty_key", "defense"
	)), 10))


func _attribute(snapshot: Variant, actor_id: String, key: String) -> int:
	return int(_state_value(snapshot, actor_id, key, 0))


func _state_value(
		snapshot: Variant,
		actor_id: String,
		key: String,
		default_value: Variant
) -> Variant:
	if actor_id == str(snapshot.get_player_value("id", "player")):
		return snapshot.get_player_value(key, default_value)
	return snapshot.get_entity_state(actor_id, key, default_value)


func _source_equipment_ids(explanations: Array) -> Array[String]:
	var rows: Array[String] = []
	for explanation: Dictionary in explanations:
		if str(explanation.get("source_kind", "")) != "equipment":
			continue
		var item_id := str(explanation.get("source_id", ""))
		if item_id != "" and item_id not in rows:
			rows.append(item_id)
	return rows


func _equipped_item_id(
		snapshot: Variant, actor_id: String, slot_id: String
) -> String:
	if slot_id == "":
		return ""
	return str(snapshot.get_equipped_item(
		actor_id, slot_id
	).get("item_instance_id", ""))


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	var entity: Dictionary = snapshot.get_entity(entity_id)
	return str(entity.get("display_name", entity_id))


func _risk_label(required_roll: int) -> String:
	if required_roll <= ROLL_MINIMUM:
		return "有利"
	if required_roll <= 3:
		return "可控"
	if required_roll <= ROLL_MAXIMUM:
		return "危险"
	return "极险"


func _invalid_preview(error: String) -> Dictionary:
	return {"ok": false, "error": error}


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")
