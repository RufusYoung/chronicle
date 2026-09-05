extends RefCounted
class_name V5NpcSocialFollowupSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)

const REPAYMENT_HOUR := 6
const CONFLICT_HOUR := 20
const MINIMUM_REPAYMENT_DEBT := 4
const MINIMUM_CONFLICT_FAILURES := 2
const MINIMUM_CONFLICT_RESENTMENT := 3
const FamilyFood = preload("res://scripts/sim/npc/household_provisioning.gd")
var family_config: Dictionary = {}


func resolve_tick(snapshot: Variant, tick_event: Dictionary, daily_life_config: Dictionary = {}) -> Dictionary:
	family_config = daily_life_config.get("food_access", {}).get("household_provisioning", {})
	if int(tick_event.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var result = TransactionResultModel.new()
	var events: Array = []
	var repayment_count := 0
	var conflict_count := 0
	var hour := int(tick_event.get("hour", 0))
	if hour == REPAYMENT_HOUR or _physical_social():
		repayment_count = _append_debt_repayments(
			result, snapshot, tick_event, events
		)
	if hour == CONFLICT_HOUR:
		conflict_count = _append_food_conflicts(
			result, snapshot, tick_event, events
		)
	if result.is_empty():
		return {"results": [], "events": events}
	result.set_narrative_result({
		"title": "邻里往来有了后续",
		"summary": "这次结算出现 %d 次实物偿还和 %d 次缺粮争执。" % [
			repayment_count, conflict_count,
		],
		"tone": "ordinary_social_consequence",
	})
	result.mark_resolved("npc_social_followup")
	return {"results": [result], "events": events}


func _append_debt_repayments(
		result: Variant,
		snapshot: Variant,
		tick_event: Dictionary,
		events: Array
) -> int:
	var day := int(tick_event.get("day", 0))
	var households := _households(snapshot)
	var available_quantity := _available_item_quantities(snapshot)
	var pairs := _food_debt_pairs(snapshot)
	var repaid_debtors: Dictionary = {}
	var count := 0
	for pair: Dictionary in pairs:
		var debtor_id := str(pair.get("debtor_id", ""))
		var creditor_id := str(pair.get("creditor_id", ""))
		if (
			debtor_id == ""
			or creditor_id == ""
			or repaid_debtors.has(debtor_id)
			or int(snapshot.get_relation(
				debtor_id, creditor_id, "debt", 0
			)) < MINIMUM_REPAYMENT_DEBT
			or _has_repayment_for_debtor_day(snapshot, debtor_id, day)
		):
			continue
		var household_id := str(snapshot.get_entity_state(
			debtor_id, "household_id", ""
		))
		if household_id == "" or not households.has(household_id):
			continue
		var payers: Array = households[household_id]
		if _physical_social():
			if not _co_present(snapshot, debtor_id, creditor_id):
				continue
			if not FamilyFood.request(snapshot, snapshot.get_entity(debtor_id), tick_event, family_config).is_empty():
				continue
			payers = [debtor_id]
		var item := _repayment_item(
			snapshot, payers, available_quantity
		)
		if item.is_empty():
			continue
		var payer_id := str(item.get("holder_id", debtor_id))
		var item_id := str(item.get("item_instance_id", ""))
		var fact_id := "fact.npc_food_debt_repaid.%s.%s.day_%d" % [
			_safe_id(debtor_id), _safe_id(creditor_id), day,
		]
		var exchange_id := "exchange.npc_food_debt_repayment.%s.%s.day_%d" % [
			_safe_id(debtor_id), _safe_id(creditor_id), day,
		]
		var source_fact_id := str(pair.get("source_fact_id", ""))
		result.add_fact({
			"fact_id": fact_id,
			"fact_type": "npc_food_debt_repaid",
			"actor_id": payer_id,
			"debtor_id": debtor_id,
			"target_id": creditor_id,
			"household_id": household_id,
			"creditor_household_id": str(snapshot.get_entity_state(
				creditor_id, "household_id", ""
			)),
			"item_instance_id": item_id,
			"item_def_id": str(item.get("item_def_id", "")),
			"quantity": 1,
			"debt_reduction": 2,
			"exchange_id": exchange_id,
			"source_fact_ids": [source_fact_id],
			"day": day,
			"hour": int(tick_event.get("hour", 0)),
			"tick_event_id": str(tick_event.get("tick_event_id", "")),
			"summary": "%s从家中拿出一份%s，替%s还给%s。" % [
				_entity_name(snapshot, payer_id),
				str(item.get("display_name", item.get("item_def_id", "物品"))),
				_entity_name(snapshot, debtor_id),
				_entity_name(snapshot, creditor_id),
			],
		})
		if _physical_social():
			result.facts_added.back()["location_id"] = str(snapshot.get_entity_state(debtor_id, "location_id", ""))
			result.facts_added.back()["summary"] = "%s在碰面时拿出自己的一份%s还给%s。" % [
				_entity_name(snapshot, debtor_id), item.get("display_name", "财物"), _entity_name(snapshot, creditor_id)]
		_append_item_transfer(
			result, item, creditor_id, fact_id, tick_event
		)
		result.add_relationship_change({
			"source_id": debtor_id,
			"target_id": creditor_id,
			"axis": "debt",
			"delta": -2,
		})
		result.add_relationship_change({
			"source_id": debtor_id,
			"target_id": creditor_id,
			"axis": "trust",
			"delta": 1,
		})
		result.add_exchange({
			"exchange_id": exchange_id,
			"exchange_type": "in_kind_food_debt_repayment",
			"status": "settled",
			"party_a": debtor_id,
			"party_b": creditor_id,
			"payer_id": payer_id,
			"scope_type": "settlement",
			"scope_id": _settlement_id(snapshot),
			"created_tick": _tick_value(tick_event),
			"settled_tick": _tick_value(tick_event),
			"source_fact_ids": [fact_id, source_fact_id],
			"terms": {
				"item_def_id": str(item.get("item_def_id", "")),
				"quantity": 1,
				"debt_reduction": 2,
			},
		})
		result.add_trace({
			"trace_id": "trace.npc_food_debt_repaid.%s.%s.day_%d" % [
				_safe_id(debtor_id), _safe_id(creditor_id), day,
			],
			"trace_type": "returned_goods_bundle",
			"actor_id": payer_id,
			"target_id": creditor_id,
			"location_id": str(snapshot.get_entity_state(
				creditor_id, "home_location_id", ""
			)),
			"source_fact_id": fact_id,
			"source_fact_ids": [fact_id],
			"source_fact_type": "npc_food_debt_repaid",
			"display_name": "还回邻家的实物",
			"description": "一份从受助家庭送回来的物品，抵掉了部分食物人情。",
			"visible": false,
			"inspectable": true,
			"freshness": "fresh",
			"tags": ["repayment", "neighbor_exchange", "generated_trace"],
		})
		available_quantity[item_id] = int(
			available_quantity.get(item_id, 0)
		) - 1
		repaid_debtors[debtor_id] = true
		events.append({
			"event_type": "food_debt_repaid",
			"actor_id": payer_id,
			"debtor_id": debtor_id,
			"target_id": creditor_id,
			"item_instance_id": item_id,
			"fact_id": fact_id,
			"exchange_id": exchange_id,
		})
		count += 1
	return count


func _append_food_conflicts(
		result: Variant,
		snapshot: Variant,
		tick_event: Dictionary,
		events: Array
) -> int:
	var day := int(tick_event.get("day", 0))
	var settlement_id := _settlement_id(snapshot)
	var count := 0
	for pair: Dictionary in _failed_request_pairs(snapshot):
		var actor_id := str(pair.get("actor_id", ""))
		var target_id := str(pair.get("target_id", ""))
		if _physical_social() and not _co_present(snapshot, actor_id, target_id):
			continue
		var source_fact_ids: Array = pair.get("source_fact_ids", [])
		var fact_id := "fact.npc_food_request_conflict.%s.%s.day_%d" % [
			_safe_id(actor_id), _safe_id(target_id), day,
		]
		if (
			source_fact_ids.size() < MINIMUM_CONFLICT_FAILURES
			or int(pair.get("latest_failure_day", -1)) != day
			or int(snapshot.get_relation(
				actor_id, target_id, "resentment", 0
			)) < MINIMUM_CONFLICT_RESENTMENT
			or _snapshot_has_fact(snapshot, fact_id)
		):
			continue
		result.add_fact({
			"fact_id": fact_id,
			"fact_type": "npc_food_request_conflict",
			"actor_id": actor_id,
			"target_id": target_id,
			"settlement_id": settlement_id,
			"failed_request_count": source_fact_ids.size(),
			"resentment_before": int(snapshot.get_relation(
				actor_id, target_id, "resentment", 0
			)),
			"source_fact_ids": source_fact_ids.duplicate(true),
			"day": day,
			"hour": int(tick_event.get("hour", 0)),
			"tick_event_id": str(tick_event.get("tick_event_id", "")),
			"summary": "%s再次空手而回后，与%s为先前的食物求助争执起来。" % [
				_entity_name(snapshot, actor_id),
				_entity_name(snapshot, target_id),
			],
		})
		result.add_relationship_change({
			"source_id": actor_id,
			"target_id": target_id,
			"axis": "resentment",
			"delta": 2,
		})
		result.add_relationship_change({
			"source_id": target_id,
			"target_id": actor_id,
			"axis": "fear",
			"delta": 1,
		})
		result.add_pressure_change({
			"pressure_id": "pressure.generated_food_relief.%s.%s.day_%d" % [
				_safe_id(actor_id), _safe_id(target_id), day,
			],
			"scope_id": settlement_id,
			"scope_type": "settlement",
			"domain": "social_welfare",
			"pressure_type": "food_relief_demand",
			"value": 2,
			"source_fact_id": fact_id,
			"day": day,
		})
		result.add_trace({
			"trace_id": "trace.npc_food_request_conflict.%s.%s.day_%d" % [
				_safe_id(actor_id), _safe_id(target_id), day,
			],
			"trace_type": "food_request_argument",
			"actor_id": actor_id,
			"target_id": target_id,
			"location_id": str(snapshot.get_entity_state(
				actor_id, "home_location_id", ""
			)),
			"source_fact_id": fact_id,
			"source_fact_ids": [fact_id],
			"source_fact_type": "npc_food_request_conflict",
			"display_name": "争执后没有收起的空篮",
			"description": "空篮被重重搁在门边，附近的人已经知道两家为食物起过争执。",
			"visible": false,
			"inspectable": true,
			"freshness": "fresh",
			"tags": ["food_conflict", "relief_demand", "generated_trace"],
		})
		events.append({
			"event_type": "food_request_conflict",
			"actor_id": actor_id,
			"target_id": target_id,
			"fact_id": fact_id,
		})
		count += 1
	return count


func _physical_social() -> bool:
	return FamilyFood.enabled(family_config) and int(family_config.get("social_presence_version", 0)) == 1


func _co_present(snapshot: Variant, first: String, second: String) -> bool:
	for id: String in [first, second]:
		if not bool(snapshot.get_entity_state(id, "alive", false)) \
				or str(snapshot.get_entity_state(id, "daily_route_id", "")) != "":
			return false
	var location := str(snapshot.get_entity_state(first, "location_id", ""))
	return location != "" and location == str(snapshot.get_entity_state(second, "location_id", ""))


func _food_debt_pairs(snapshot: Variant) -> Array:
	var rows: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) != "npc_cross_household_shared_food":
			continue
		var debtor_id := str(fact.get("requester_id", ""))
		var creditor_id := str(fact.get("actor_id", ""))
		if debtor_id == "" or creditor_id == "":
			continue
		var key := "%s>%s" % [debtor_id, creditor_id]
		rows[key] = {
			"debtor_id": debtor_id,
			"creditor_id": creditor_id,
			"source_fact_id": str(fact.get("fact_id", "")),
			"debt": int(snapshot.get_relation(
				debtor_id, creditor_id, "debt", 0
			)),
		}
	var pairs: Array = rows.values()
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_debt := int(a.get("debt", 0))
		var b_debt := int(b.get("debt", 0))
		if a_debt != b_debt:
			return a_debt > b_debt
		return "%s>%s" % [a.get("debtor_id", ""), a.get("creditor_id", "")] < (
			"%s>%s" % [b.get("debtor_id", ""), b.get("creditor_id", "")]
		)
	)
	return pairs


func _failed_request_pairs(snapshot: Variant) -> Array:
	var rows: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) != (
			"npc_cross_household_food_request_failed"
		):
			continue
		var actor_id := str(fact.get("actor_id", ""))
		var target_id := str(fact.get("target_id", ""))
		if actor_id == "" or target_id == "":
			continue
		var key := "%s>%s" % [actor_id, target_id]
		if not rows.has(key):
			rows[key] = {
				"actor_id": actor_id,
				"target_id": target_id,
				"source_fact_ids": [],
				"latest_failure_day": -1,
			}
		var row: Dictionary = rows[key]
		(row["source_fact_ids"] as Array).append(str(fact.get("fact_id", "")))
		row["latest_failure_day"] = maxi(
			int(row.get("latest_failure_day", -1)),
			int(fact.get("day", -1))
		)
		rows[key] = row
	var pairs: Array = rows.values()
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return "%s>%s" % [a.get("actor_id", ""), a.get("target_id", "")] < (
			"%s>%s" % [b.get("actor_id", ""), b.get("target_id", "")]
		)
	)
	return pairs


func _repayment_item(
		snapshot: Variant,
		household_members: Array,
		available_quantity: Dictionary
) -> Dictionary:
	var candidates: Array = []
	for item: Dictionary in snapshot.get_items():
		var item_id := str(item.get("item_instance_id", ""))
		var holder: Dictionary = item.get("holder", {})
		var holder_id := str(holder.get("id", ""))
		var quantity := int(available_quantity.get(item_id, 0))
		if (
			str(holder.get("kind", "")) != "entity"
			or holder_id not in household_members
			or quantity <= 0
			or "food" in (item.get("tags", []) as Array)
		):
			continue
		var item_def_id := str(item.get("item_def_id", ""))
		var is_coin := item_def_id == "item.copper_coin"
		var is_livelihood_product := "livelihood_product" in (
			item.get("tags", []) as Array
		)
		if not is_coin and not is_livelihood_product:
			continue
		if is_coin and quantity <= 1:
			continue
		if int(item.get("quantity", 0)) > 1 and quantity <= 1:
			continue
		var row := item.duplicate(true)
		row["holder_id"] = holder_id
		row["repayment_score"] = (
			3 if item_def_id == "item.woven_reed_mat"
			else 2 if item_def_id == "item.marsh_herb_bundle"
			else 1
		)
		candidates.append(row)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := int(a.get("repayment_score", 0))
		var b_score := int(b.get("repayment_score", 0))
		if a_score != b_score:
			return a_score > b_score
		return str(a.get("item_instance_id", "")) < str(
			b.get("item_instance_id", "")
		)
	)
	return {} if candidates.is_empty() else (candidates[0] as Dictionary)


func _append_item_transfer(
		result: Variant,
		item: Dictionary,
		creditor_id: String,
		fact_id: String,
		tick_event: Dictionary
) -> void:
	var change := {
		"item_instance_id": str(item.get("item_instance_id", "")),
		"new_holder": {"kind": "entity", "id": creditor_id},
		"source_fact_ids": [fact_id],
		"updated_tick": _tick_value(tick_event),
	}
	if int(item.get("quantity", 0)) == 1:
		change["operation"] = "transfer"
	else:
		change["operation"] = "split_stack"
		change["quantity"] = 1
		change["new_item_instance_id"] = "item_instance.repayment.%s" % _safe_id(
			fact_id
		)
	result.add_item_change(change)


func _has_repayment_for_debtor_day(
		snapshot: Variant,
		debtor_id: String,
		day: int
) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "npc_food_debt_repaid"
			and str(fact.get("debtor_id", "")) == debtor_id
			and int(fact.get("day", 0)) == day
		):
			return true
	return false


func _households(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		var household_id := str(snapshot.get_entity_state(
			person_id, "household_id", ""
		))
		if household_id == "":
			continue
		if not rows.has(household_id):
			rows[household_id] = []
		(rows[household_id] as Array).append(person_id)
	return rows


func _available_item_quantities(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for item: Dictionary in snapshot.get_items():
		rows[str(item.get("item_instance_id", ""))] = int(item.get(
			"quantity", 0
		))
	return rows


func _snapshot_has_fact(snapshot: Variant, fact_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _settlement_id(snapshot: Variant) -> String:
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var settlement_id := str(snapshot.get_entity_state(
			str(person.get("id", "")), "settlement_id", ""
		))
		if settlement_id != "":
			return settlement_id
	return ""


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	var entity: Dictionary = snapshot.get_entity(entity_id)
	return str(entity.get("display_name", entity_id))


func _tick_value(tick_event: Dictionary) -> int:
	return int(tick_event.get("day", 0)) * 24 + int(
		tick_event.get("hour", 0)
	)


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")
