extends RefCounted
class_name V5LocalProcurementSystem

const Market = preload("res://scripts/sim/economy/market_service.gd")
const OperationalMaterialServiceModel = preload(
	"res://scripts/sim/economy/operational_material_service.gd"
)


func resolve_daily_tick(
		snapshot: Variant,
		tick: Dictionary,
		network: Dictionary,
		stores: Dictionary
) -> Dictionary:
	var config: Dictionary = network.get("local_procurement", {})
	var day := int(tick.get("day", 0))
	if not bool(config.get("enabled", false)) or day <= 0:
		return {"results": [], "events": []}

	var results: Array = []
	var events: Array = []
	var material_service = OperationalMaterialServiceModel.new()
	material_service.configure(
		snapshot,
		network.get("operational_material_uses", []),
		day,
		int(tick.get("elapsed_hours", 0))
	)
	var sites: Array = network.get("sites", []).duplicate(true)
	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("settlement_id", "")) < str(b.get("settlement_id", "")))
	for site: Dictionary in sites:
		var settlement_id := str(site.get("settlement_id", ""))
		if (
			settlement_id == ""
			or int(snapshot.get_entity_state(
				settlement_id, "economic_contract_version", 0
			)) != 1
		):
			continue
		var need := _oldest_material_need(snapshot, settlement_id, material_service)
		if need.is_empty():
			continue
		var item_def_id := str(need.get("item_def_id", ""))
		var material_rule := material_service.rule_for_item(
			item_def_id, str(need.get("use_id", ""))
		)
		if material_rule.is_empty():
			events.append(_blocked_event(
				settlement_id, day, "material_rule_missing", need
			))
			continue
		var accepted_purposes: Array = material_rule.get(
			"accepted_purpose_ids", []
		)
		var buyer := _select_buyer(
			snapshot, settlement_id, config, accepted_purposes
		)
		if buyer.is_empty():
			events.append(_blocked_event(settlement_id, day, "buyer_unavailable", need))
			continue
		var buyer_id := str(buyer.get("id", ""))
		var target_quantity := maxi(int(need.get(
			"quantity_required", config.get("target_quantity", 1)
		)), 1)
		var shortage := target_quantity - material_service.usable_quantity(
			material_rule,
			str(need.get("scope_id", "")),
			settlement_id
		)
		if shortage <= 0:
			continue
		var seller := _select_seller(
			snapshot, settlement_id, config, material_rule, item_def_id
		)
		if seller.is_empty():
			events.append(_blocked_event(settlement_id, day, "seller_unavailable", need, buyer_id))
			continue
		var seller_id := str(seller.get("seller_id", ""))
		var policy := {
			"market_policy_id": "market_policy.local_procurement.%s" % settlement_id,
			"display_name": "本地维护物资采购",
			"seller_entity_id": seller_id,
			"location_id": str(site.get("hub_location_id", "")),
			"sellable_item_def_ids": [item_def_id],
			"accepted_currency_item_def_ids": [str(config.get(
				"currency_item_def_id", "item.copper_coin"
			))],
			"minimum_retained_quantity": maxi(int(material_rule.get(
				"seller_retained_quantity",
				config.get("seller_retained_quantity", 1)
			)), 0),
			"buyer_currency_reserve": maxi(int(snapshot.get_entity_state(
				buyer_id, "procurement_treasury_reserve", 0
			)), 0),
			"fact_type": str(material_rule.get(
				"procurement_fact_type",
				config.get("procurement_fact_type", "local_material_procured")
			)),
			"exchange_type": str(material_rule.get(
				"procurement_exchange_type", "local_spot_procurement"
			)),
		}
		var stock := Market.new().build_stock_view(policy, stores, buyer_id)
		var offer := _first_offer(stock, str(seller.get("item_instance_id", "")))
		if offer.is_empty():
			events.append(_blocked_event(settlement_id, day, "offer_no_longer_available", need, buyer_id, seller_id))
			continue
		var quantity := mini(shortage, mini(
			maxi(int(config.get("maximum_quantity_per_purchase", 1)), 1),
			int(offer.get("available_quantity", 0))
		))
		var spending_limit := maxi(int(snapshot.get_entity_state(
			buyer_id, "procurement_spending_limit", 0
		)), 0)
		var purpose_id := _purpose_for(buyer, config)
		var buyer_name := str(buyer.get("display_name", buyer_id))
		var seller_entity: Dictionary = snapshot.get_entity(seller_id)
		var seller_name := str(seller_entity.get("display_name", seller_id))
		var item_name := str(material_rule.get(
			"item_display_name", item_def_id
		))
		var quantity_label := str(material_rule.get("quantity_label", "份"))
		var summary := "%s为履行路线 %s 的%s需求，向%s支付 %d 枚铜币，购入 %d %s%s。" % [
			buyer_name,
			str(need.get("scope_id", "")),
			str(material_rule.get("work_label", "作业材料")),
			seller_name,
			int(offer.get("unit_price", 0)) * quantity,
			quantity,
			quantity_label,
			item_name,
		]
		var exchange_id := "exchange.local_procurement.%s.%s.day%d" % [
			_safe_id(buyer_id), _safe_id(str(need.get("scope_id", ""))), day,
		]
		var source_fact_ids: Array = need.get("source_fact_ids", []).duplicate(true)
		var plan := Market.new().plan_trade(policy, {
			"buyer_entity_id": buyer_id,
			"item_instance_id": str(offer.get("item_instance_id", "")),
			"quantity": quantity,
			"quoted_unit_price": int(offer.get("unit_price", 0)),
			"maximum_total_price": spending_limit,
			"exchange_id": exchange_id,
			"purpose_id": purpose_id,
			"purpose_target_id": str(need.get("scope_id", "")),
			"purpose_obligation_id": str(need.get("obligation_id", "")),
			"source_fact_ids": source_fact_ids,
			"summary": summary,
		}, stores, tick)
		if not bool(plan.get("success", false)):
			events.append(_blocked_event(
				settlement_id, day, str(plan.get("error", "trade_rejected")),
				need, buyer_id, seller_id
			))
			continue
		var transaction: Variant = plan.get("transaction")
		transaction.add_obligation_update({
			"obligation_id": str(need.get("obligation_id", "")),
			"material_status": "acquired",
			"procurement_fact_id": str(plan.get("fact_id", "")),
			"procurement_exchange_id": str(plan.get("exchange_id", "")),
			"procured_item_def_id": item_def_id,
			"procured_quantity": quantity,
			"procured_day": day,
		})
		transaction.add_state_change({
			"entity_id": buyer_id,
			"key": "last_local_procurement",
			"to": {
				"day": day,
				"fact_id": str(plan.get("fact_id", "")),
				"obligation_id": str(need.get("obligation_id", "")),
				"purpose_id": purpose_id,
				"purpose_target_id": str(need.get("scope_id", "")),
				"quantity": quantity,
				"total_price": int(plan.get("total_price", 0)),
			},
		})
		transaction.set_narrative_result({
			"title": "本地物资完成现货采购",
			"summary": summary,
			"tone": "local_procurement",
		})
		transaction.mark_resolved("local_material_procurement")
		results.append(transaction)
		events.append({
			"event_type": str(policy.get(
				"fact_type", "local_material_procured"
			)),
			"status": "settled",
			"settlement_id": settlement_id,
			"buyer_entity_id": buyer_id,
			"seller_entity_id": seller_id,
			"obligation_id": str(need.get("obligation_id", "")),
			"purpose_id": purpose_id,
			"purpose_target_id": str(need.get("scope_id", "")),
			"source_fact_id": str(need.get("opened_by_fact_id", "")),
			"fact_id": str(plan.get("fact_id", "")),
			"quantity": quantity,
			"total_price": int(plan.get("total_price", 0)),
			"day": day,
		})
	return {"results": results, "events": events}


func _oldest_material_need(
		snapshot: Variant,
		settlement_id: String,
		material_service: Variant
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for obligation: Dictionary in snapshot.get_open_obligations():
		if (
			str(obligation.get("obligation_type", ""))
				!= "operational_material_demand"
			or str(obligation.get("owner_id", "")) != settlement_id
			or material_service.rule_for_item(
				str(obligation.get("item_def_id", "")),
				str(obligation.get("use_id", ""))
			).is_empty()
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


func _select_buyer(
		snapshot: Variant,
		settlement_id: String,
		config: Dictionary,
		accepted_purpose_ids: Array
) -> Dictionary:
	var purposes: Dictionary = config.get("buyer_purposes", {})
	var priority: Array = config.get("buyer_priority", purposes.keys())
	var candidates: Array[Dictionary] = []
	for entity: Dictionary in snapshot.get_entities_by_type("institution"):
		var prototype_id := str(entity.get("prototype_id", ""))
		var purpose_id := str(purposes.get(prototype_id, ""))
		if (
			str(entity.get("settlement_id", "")) != settlement_id
			or not purposes.has(prototype_id)
			or (
				not accepted_purpose_ids.is_empty()
				and purpose_id not in accepted_purpose_ids
			)
			or not _is_staffed(snapshot, entity)
			or int(snapshot.get_entity_state(
				str(entity.get("id", "")), "economic_contract_version", 0
			)) != 1
		):
			continue
		var row := entity.duplicate(true)
		row["procurement_priority"] = priority.find(prototype_id)
		candidates.append(row)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a.get("procurement_priority", 999))
		var right := int(b.get("procurement_priority", 999))
		return left < right if left != right else str(a.get("id", "")) < str(b.get("id", "")))
	return {} if candidates.is_empty() else candidates[0]


func _select_seller(
		snapshot: Variant,
		settlement_id: String,
		config: Dictionary,
		material_rule: Dictionary,
		item_def_id: String
) -> Dictionary:
	var occupations: Array = material_rule.get(
		"seller_occupation_ids", config.get("seller_occupation_ids", [])
	)
	var retained := maxi(int(material_rule.get(
		"seller_retained_quantity", config.get("seller_retained_quantity", 1)
	)), 0)
	var candidates: Array[Dictionary] = []
	for item: Dictionary in snapshot.get_items():
		var holder: Dictionary = item.get("holder", {})
		var seller_id := str(holder.get("id", ""))
		if (
			str(holder.get("kind", "")) != "entity"
			or str(item.get("item_def_id", "")) != item_def_id
			or int(item.get("quantity", 0)) <= retained
			or str(snapshot.get_entity_state(seller_id, "settlement_id", "")) != settlement_id
			or str(snapshot.get_entity_state(seller_id, "life_status", "alive")) != "alive"
			or str(snapshot.get_entity_state(seller_id, "occupation_id", "")) not in occupations
			or not snapshot.is_entity_active(seller_id)
		):
			continue
		candidates.append({
			"seller_id": seller_id,
			"item_instance_id": str(item.get("item_instance_id", "")),
			"available_quantity": int(item.get("quantity", 0)) - retained,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a.get("available_quantity", 0))
		var right := int(b.get("available_quantity", 0))
		return left > right if left != right else str(a.get("seller_id", "")) < str(b.get("seller_id", "")))
	return {} if candidates.is_empty() else candidates[0]


func _is_staffed(snapshot: Variant, organization: Dictionary) -> bool:
	var prefix := str(organization.get("id", "")) + "::"
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			str(snapshot.get_entity_state(person_id, "life_status", "alive")) == "alive"
			and str(snapshot.get_entity_state(person_id, "institution_role", "")).begins_with(prefix)
		):
			return true
	return false


func _purpose_for(buyer: Dictionary, config: Dictionary) -> String:
	return str((config.get("buyer_purposes", {}) as Dictionary).get(
		str(buyer.get("prototype_id", "")), "local_transport_reserve"
	))


func _first_offer(stock: Dictionary, item_instance_id: String) -> Dictionary:
	for offer: Dictionary in stock.get("offers", []):
		if str(offer.get("item_instance_id", "")) == item_instance_id:
			return offer.duplicate(true)
	return {}


func _blocked_event(
		settlement_id: String,
		day: int,
		reason: String,
		need: Dictionary,
		buyer_id: String = "",
		seller_id: String = ""
) -> Dictionary:
	return {
		"event_type": "local_procurement_blocked",
		"status": "blocked",
		"reason": reason,
		"settlement_id": settlement_id,
		"buyer_entity_id": buyer_id,
		"seller_entity_id": seller_id,
		"obligation_id": str(need.get("obligation_id", "")),
		"purpose_target_id": str(need.get("scope_id", "")),
		"source_fact_id": str(need.get("opened_by_fact_id", "")),
		"day": day,
	}


func _safe_id(value: String) -> String:
	return value.replace(".", "_").replace(":", "_").replace("/", "_")
