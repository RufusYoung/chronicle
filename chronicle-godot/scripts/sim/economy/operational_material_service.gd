extends RefCounted
class_name V5OperationalMaterialService

const EPSILON := 0.0001

var snapshot: Variant = null
var day := 0
var tick := 0
var rules: Array[Dictionary] = []
var facts_by_id: Dictionary = {}
var reserved_item_ids: Dictionary = {}
var fulfilled_obligation_ids: Dictionary = {}
var planned_open_keys: Dictionary = {}


func configure(
		source_snapshot: Variant,
		rules_value: Variant,
		current_day: int,
		current_tick: int
) -> void:
	snapshot = source_snapshot
	day = current_day
	tick = current_tick
	rules.clear()
	facts_by_id.clear()
	reserved_item_ids.clear()
	fulfilled_obligation_ids.clear()
	planned_open_keys.clear()
	if rules_value is Array:
		for value: Variant in rules_value:
			if value is Dictionary and bool(value.get("enabled", true)):
				rules.append((value as Dictionary).duplicate(true))
	rules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("use_id", "")) < str(b.get("use_id", "")))
	for fact: Dictionary in snapshot.get_facts():
		facts_by_id[str(fact.get("fact_id", ""))] = fact.duplicate(true)


func rule_for_item(item_def_id: String, use_id: String = "") -> Dictionary:
	for rule: Dictionary in rules:
		if (
			str(rule.get("item_def_id", "")) == item_def_id
			and (use_id == "" or str(rule.get("use_id", "")) == use_id)
		):
			return rule.duplicate(true)
	return {}


func plan_uses(
		trigger_fact_type: String,
		scope_id: String,
		owner_id: String
) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	for rule: Dictionary in rules:
		if str(rule.get("trigger_fact_type", "")) != trigger_fact_type:
			continue
		var demand := _oldest_open_demand(rule, scope_id, owner_id)
		if demand.is_empty():
			continue
		var item_plan := _select_item(rule, scope_id, owner_id)
		if item_plan.is_empty():
			continue
		plans.append({
			"rule": rule.duplicate(true),
			"demand": demand,
			"item": item_plan.get("item", {}).duplicate(true),
			"purchase_fact": item_plan.get("purchase_fact", {}).duplicate(true),
		})
	return plans


func usable_quantity(
		rule: Dictionary,
		scope_id: String,
		owner_id: String
) -> int:
	var quantity := 0
	for item: Dictionary in _sorted_items():
		if not _item_matches_rule(item, rule, scope_id, owner_id):
			continue
		quantity += int(item.get("quantity", 0))
	return quantity


func transport_cost_reduction(plans: Array[Dictionary]) -> float:
	var total := 0.0
	for plan: Dictionary in plans:
		total += maxf(float((plan.get("rule", {}) as Dictionary).get(
			"transport_cost_reduction", 0.0
		)), 0.0)
	return total


func plan_item_ids(plans: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for plan: Dictionary in plans:
		var item_id := str((plan.get("item", {}) as Dictionary).get(
			"item_instance_id", ""
		))
		_append_unique(ids, item_id)
	return ids


func plan_source_fact_ids(plans: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for plan: Dictionary in plans:
		var demand: Dictionary = plan.get("demand", {})
		for fact_id: Variant in demand.get("source_fact_ids", []):
			_append_unique(ids, str(fact_id))
		var purchase_fact_id := str((plan.get(
			"purchase_fact", {}
		) as Dictionary).get("fact_id", ""))
		_append_unique(ids, purchase_fact_id)
	return ids


func append_uses(
		result: Variant,
		plans: Array[Dictionary],
		work_fact_id: String,
		applied_transport_cost_reduction: float
) -> Dictionary:
	var remaining_effect := maxf(applied_transport_cost_reduction, 0.0)
	var events: Array = []
	var used_item_ids: Array[String] = []
	for plan: Dictionary in plans:
		var rule: Dictionary = plan.get("rule", {})
		var nominal_effect := maxf(float(rule.get(
			"transport_cost_reduction", 0.0
		)), 0.0)
		var applied_effect := minf(nominal_effect, remaining_effect)
		if applied_effect <= EPSILON:
			continue
		remaining_effect -= applied_effect
		var event := _append_use(
			result, plan, work_fact_id, applied_effect
		)
		if event.is_empty():
			continue
		events.append(event)
		_append_unique(used_item_ids, str(event.get("item_instance_id", "")))
	return {"events": events, "item_instance_ids": used_item_ids}


func append_next_demands(
		result: Variant,
		trigger_fact_type: String,
		scope_id: String,
		owner_id: String,
		work_fact_id: String
) -> Array:
	var events: Array = []
	for rule: Dictionary in rules:
		if str(rule.get("trigger_fact_type", "")) != trigger_fact_type:
			continue
		var key := _open_key(rule, scope_id, owner_id)
		if _has_open_demand(rule, scope_id, owner_id):
			continue
		var use_id := str(rule.get("use_id", "operational_material"))
		var obligation_id := "obligation.operational_material.%s.%s.%s.day%d" % [
			_safe_id(use_id), _safe_id(scope_id), _safe_id(owner_id), day,
		]
		var demand_fact_id := "fact.%s.opened" % obligation_id
		var item_name := str(rule.get(
			"item_display_name", rule.get("item_def_id", "作业材料")
		))
		var work_label := str(rule.get("work_label", "下一轮作业"))
		result.add_fact({
			"fact_id": demand_fact_id,
			"fact_type": "operational_material_demand_opened",
			"actor_id": owner_id,
			"target_id": owner_id,
			"scope_type": str(rule.get("scope_type", "route")),
			"scope_id": scope_id,
			"use_id": use_id,
			"item_def_id": str(rule.get("item_def_id", "")),
			"quantity_required": maxi(int(rule.get("quantity_required", 1)), 1),
			"needed_from_day": day + maxi(int(rule.get("lead_days", 1)), 1),
			"source_fact_ids": [work_fact_id],
			"day": day,
			"tick": tick,
			"summary": "%s的实际货运形成了下一轮%s需求，需要 %d 份%s。" % [
				_entity_name(owner_id), work_label,
				maxi(int(rule.get("quantity_required", 1)), 1), item_name,
			],
		})
		result.add_obligation({
			"obligation_id": obligation_id,
			"owner_id": owner_id,
			"target_id": owner_id,
			"obligation_type": "operational_material_demand",
			"status": "open",
			"material_status": "needed",
			"scope_type": str(rule.get("scope_type", "route")),
			"scope_id": scope_id,
			"use_id": use_id,
			"item_def_id": str(rule.get("item_def_id", "")),
			"quantity_required": maxi(int(rule.get("quantity_required", 1)), 1),
			"accepted_purpose_ids": (
				rule.get("accepted_purpose_ids", []) as Array
			).duplicate(true),
			"opened_day": day,
			"needed_from_day": day + maxi(int(rule.get("lead_days", 1)), 1),
			"opened_by_fact_id": demand_fact_id,
			"source_fact_ids": [work_fact_id, demand_fact_id],
		})
		planned_open_keys[key] = obligation_id
		events.append({
			"event_type": "operational_material_demand_opened",
			"obligation_id": obligation_id,
			"fact_id": demand_fact_id,
			"owner_id": owner_id,
			"scope_id": scope_id,
			"use_id": use_id,
			"item_def_id": str(rule.get("item_def_id", "")),
			"day": day,
		})
	return events


func _append_use(
		result: Variant,
		plan: Dictionary,
		work_fact_id: String,
		applied_transport_cost_reduction: float
) -> Dictionary:
	var rule: Dictionary = plan.get("rule", {})
	var demand: Dictionary = plan.get("demand", {})
	var item: Dictionary = plan.get("item", {})
	var purchase_fact: Dictionary = plan.get("purchase_fact", {})
	var obligation_id := str(demand.get("obligation_id", ""))
	var item_id := str(item.get("item_instance_id", ""))
	if obligation_id == "" or item_id == "":
		return {}
	var holder: Dictionary = item.get("holder", {})
	var holder_id := str(holder.get("id", ""))
	var use_fact_id := "fact.%s.fulfilled" % obligation_id
	var source_fact_ids: Array[String] = [work_fact_id]
	for fact_id: Variant in demand.get("source_fact_ids", []):
		_append_unique(source_fact_ids, str(fact_id))
	_append_unique(source_fact_ids, str(purchase_fact.get("fact_id", "")))
	var condition: Dictionary = item.get("condition", {})
	var maximum := int(condition.get("maximum_durability", 0))
	var before := int(condition.get("durability", maximum))
	var loss := maxi(int(rule.get("durability_loss_per_cycle", 0)), 0)
	var after := maxi(before - loss, 0) if maximum > 0 else before
	var consumed_quantity := 0
	if maximum <= 0:
		consumed_quantity = maxi(int(rule.get(
			"consume_quantity_per_cycle", 0
		)), 0)
	var retired := (
		maximum > 0
		and loss > 0
		and after == 0
		and bool(rule.get("consume_when_worn_out", false))
	)
	var item_name := str(item.get("display_name", rule.get(
		"item_display_name", item.get("item_def_id", "作业材料")
	)))
	var wear_summary := (
		"耐久由 %d 降至 %d" % [before, after]
		if maximum > 0
		else "消耗 %d 份" % consumed_quantity
	)
	result.add_fact({
		"fact_id": use_fact_id,
		"fact_type": "operational_material_used",
		"actor_id": holder_id,
		"target_id": str(demand.get("owner_id", "")),
		"scope_type": str(demand.get("scope_type", "route")),
		"scope_id": str(demand.get("scope_id", "")),
		"use_id": str(rule.get("use_id", "")),
		"item_instance_id": item_id,
		"item_def_id": str(item.get("item_def_id", "")),
		"demand_obligation_id": obligation_id,
		"procurement_fact_id": str(purchase_fact.get("fact_id", "")),
		"work_fact_id": work_fact_id,
		"durability_before": before,
		"durability_after": after,
		"consumed_quantity": consumed_quantity,
		"transport_cost_reduction": applied_transport_cost_reduction,
		"source_fact_ids": source_fact_ids,
		"day": day,
		"tick": tick,
		"summary": "%s在实际货运中使用了%s，%s，本批少消耗 %.2f 份道路运力。" % [
			_entity_name(holder_id), item_name, wear_summary,
			applied_transport_cost_reduction,
		],
	})
	result.add_obligation_update({
		"obligation_id": obligation_id,
		"status": "fulfilled",
		"material_status": "used",
		"fulfilled_by_fact_id": use_fact_id,
		"fulfilled_work_fact_id": work_fact_id,
		"fulfilled_item_instance_id": item_id,
		"fulfilled_day": day,
		"resolution_count_delta": 1,
	})
	if maximum > 0 and loss > 0:
		result.add_item_change({
			"operation": "adjust_durability",
			"item_instance_id": item_id,
			"to": after,
			"expected_holder": holder.duplicate(true),
			"source_fact_ids": [use_fact_id],
			"updated_tick": tick,
		})
	if consumed_quantity > 0:
		result.add_item_change({
			"operation": "consume",
			"item_instance_id": item_id,
			"quantity": mini(consumed_quantity, int(item.get("quantity", 0))),
			"expected_holder": holder.duplicate(true),
			"source_fact_ids": [use_fact_id],
			"updated_tick": tick,
		})
	if retired:
		var retired_fact_id := "fact.operational_material_retired.%s.day%d" % [
			_safe_id(item_id), day,
		]
		result.add_fact({
			"fact_id": retired_fact_id,
			"fact_type": "operational_material_worn_out",
			"actor_id": holder_id,
			"target_id": str(demand.get("owner_id", "")),
			"scope_type": str(demand.get("scope_type", "route")),
			"scope_id": str(demand.get("scope_id", "")),
			"use_id": str(rule.get("use_id", "")),
			"item_instance_id": item_id,
			"item_def_id": str(item.get("item_def_id", "")),
			"source_fact_ids": [use_fact_id],
			"day": day,
			"tick": tick,
			"summary": "%s在持续作业后已经磨损报废，并退出可用库存。" % item_name,
		})
		result.add_item_change({
			"operation": "consume",
			"item_instance_id": item_id,
			"quantity": mini(
				maxi(int(rule.get("quantity_required", 1)), 1),
				int(item.get("quantity", 0))
			),
			"expected_holder": holder.duplicate(true),
			"source_fact_ids": [retired_fact_id],
			"updated_tick": tick,
		})
	reserved_item_ids[item_id] = true
	fulfilled_obligation_ids[obligation_id] = true
	return {
		"event_type": "operational_material_used",
		"fact_id": use_fact_id,
		"obligation_id": obligation_id,
		"actor_id": holder_id,
		"owner_id": str(demand.get("owner_id", "")),
		"scope_id": str(demand.get("scope_id", "")),
		"use_id": str(rule.get("use_id", "")),
		"item_instance_id": item_id,
		"durability_before": before,
		"durability_after": after,
		"retired": retired,
		"transport_cost_reduction": applied_transport_cost_reduction,
		"day": day,
	}


func _oldest_open_demand(
		rule: Dictionary,
		scope_id: String,
		owner_id: String
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for obligation: Dictionary in snapshot.get_open_obligations():
		var obligation_id := str(obligation.get("obligation_id", ""))
		if (
			fulfilled_obligation_ids.has(obligation_id)
			or not _demand_matches(obligation, rule, scope_id, owner_id)
			or int(obligation.get("needed_from_day", 0)) > day
		):
			continue
		candidates.append(obligation.duplicate(true))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a.get("opened_day", 0))
		var right := int(b.get("opened_day", 0))
		return left < right if left != right else str(a.get(
			"obligation_id", ""
		)) < str(b.get("obligation_id", "")))
	return {} if candidates.is_empty() else candidates[0]


func _has_open_demand(
		rule: Dictionary,
		scope_id: String,
		owner_id: String
) -> bool:
	var key := _open_key(rule, scope_id, owner_id)
	if planned_open_keys.has(key):
		return true
	for obligation: Dictionary in snapshot.get_open_obligations():
		var obligation_id := str(obligation.get("obligation_id", ""))
		if (
			not fulfilled_obligation_ids.has(obligation_id)
			and _demand_matches(obligation, rule, scope_id, owner_id)
		):
			return true
	return false


func _demand_matches(
		obligation: Dictionary,
		rule: Dictionary,
		scope_id: String,
		owner_id: String
) -> bool:
	return (
		str(obligation.get("obligation_type", ""))
			== "operational_material_demand"
		and str(obligation.get("use_id", "")) == str(rule.get("use_id", ""))
		and str(obligation.get("item_def_id", ""))
			== str(rule.get("item_def_id", ""))
		and str(obligation.get("scope_id", "")) == scope_id
		and str(obligation.get("owner_id", "")) == owner_id
	)


func _select_item(
		rule: Dictionary,
		scope_id: String,
		owner_id: String
) -> Dictionary:
	for item: Dictionary in _sorted_items():
		var item_id := str(item.get("item_instance_id", ""))
		if reserved_item_ids.has(item_id):
			continue
		if not _item_matches_rule(item, rule, scope_id, owner_id):
			continue
		return {
			"item": item.duplicate(true),
			"purchase_fact": _purchase_fact(item, rule, scope_id),
		}
	return {}


func _item_matches_rule(
		item: Dictionary,
		rule: Dictionary,
		scope_id: String,
		owner_id: String
) -> bool:
	var holder: Dictionary = item.get("holder", {})
	if (
		str(item.get("item_def_id", "")) != str(rule.get("item_def_id", ""))
		or str(holder.get("kind", "")) != "entity"
		or int(item.get("quantity", 0)) < maxi(int(rule.get(
			"quantity_required", 1
		)), 1)
		or not _holder_can_supply(str(holder.get("id", "")), owner_id)
	):
		return false
	var condition: Dictionary = item.get("condition", {})
	var maximum := int(condition.get("maximum_durability", 0))
	if maximum > 0:
		if int(item.get("quantity", 0)) != 1:
			return false
		if int(condition.get("durability", maximum)) <= 0:
			return false
	elif int(rule.get("consume_quantity_per_cycle", 0)) <= 0:
		return false
	var purchase_fact := _purchase_fact(item, rule, scope_id)
	return (
		not bool(rule.get("require_acquisition_purpose", true))
		or not purchase_fact.is_empty()
	)


func _purchase_fact(
		item: Dictionary,
		rule: Dictionary,
		scope_id: String
) -> Dictionary:
	var accepted_types: Array = rule.get("purchase_fact_types", [])
	var accepted_purposes: Array = rule.get("accepted_purpose_ids", [])
	var history_fact_ids: Array[String] = []
	var provenance: Dictionary = item.get("provenance", {})
	_append_unique(history_fact_ids, str(provenance.get(
		"created_by_fact_id", ""
	)))
	for entry: Dictionary in item.get("history", []):
		_append_unique(history_fact_ids, str(entry.get("fact_id", "")))
	var candidates: Array[Dictionary] = []
	for fact_id: String in history_fact_ids:
		var fact: Dictionary = facts_by_id.get(fact_id, {})
		if (
			str(fact.get("fact_type", "")) not in accepted_types
			or str(fact.get("purpose_target_id", "")) != scope_id
			or (
				not accepted_purposes.is_empty()
				and str(fact.get("purpose_id", "")) not in accepted_purposes
			)
		):
			continue
		candidates.append(fact.duplicate(true))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a.get("day", 0))
		var right := int(b.get("day", 0))
		return left > right if left != right else str(a.get(
			"fact_id", ""
		)) > str(b.get("fact_id", "")))
	return {} if candidates.is_empty() else candidates[0]


func _holder_can_supply(holder_id: String, owner_id: String) -> bool:
	if holder_id == "" or not snapshot.is_entity_active(holder_id):
		return false
	if holder_id == owner_id:
		return true
	var holder_entity: Dictionary = snapshot.get_entity(holder_id)
	var settlement_id := str(holder_entity.get(
		"settlement_id",
		snapshot.get_entity_state(holder_id, "settlement_id", "")
	))
	if settlement_id != owner_id:
		return false
	if str(holder_entity.get("type", "")) != "institution":
		return false
	var prefix := holder_id + "::"
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			str(snapshot.get_entity_state(
				person_id, "life_status", "alive"
			)) == "alive"
			and str(snapshot.get_entity_state(
				person_id, "institution_role", ""
			)).begins_with(prefix)
		):
			return true
	return false


func _sorted_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for value: Variant in snapshot.get_items():
		if value is Dictionary:
			items.append((value as Dictionary).duplicate(true))
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("item_instance_id", "")) < str(b.get(
			"item_instance_id", ""
		)))
	return items


func _open_key(rule: Dictionary, scope_id: String, owner_id: String) -> String:
	return "%s|%s|%s" % [str(rule.get("use_id", "")), scope_id, owner_id]


func _entity_name(entity_id: String) -> String:
	var entity: Dictionary = snapshot.get_entity(entity_id)
	return str(entity.get("display_name", entity_id))


func _append_unique(rows: Array[String], value: String) -> void:
	if value != "" and value not in rows:
		rows.append(value)


func _safe_id(value: String) -> String:
	return value.replace(".", "_").replace(":", "_").replace("/", "_")
