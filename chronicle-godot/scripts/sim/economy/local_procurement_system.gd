extends RefCounted
class_name V5LocalProcurementSystem

const Market = preload("res://scripts/sim/economy/market_service.gd")


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
		var need := _latest_shipment_need(snapshot, settlement_id, day, config)
		if need.is_empty():
			continue
		var buyer := _select_buyer(snapshot, settlement_id, config)
		if buyer.is_empty():
			events.append(_blocked_event(settlement_id, day, "buyer_unavailable", need))
			continue
		var buyer_id := str(buyer.get("id", ""))
		var item_def_id := str(config.get("item_def_id", "item.fiber_rope"))
		var target_quantity := maxi(int(config.get("target_quantity", 1)), 1)
		var shortage := target_quantity - _item_quantity(snapshot, buyer_id, item_def_id)
		if shortage <= 0:
			continue
		var seller := _select_seller(snapshot, settlement_id, config)
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
			"minimum_retained_quantity": maxi(int(config.get(
				"seller_retained_quantity", 1
			)), 0),
			"buyer_currency_reserve": maxi(int(snapshot.get_entity_state(
				buyer_id, "procurement_treasury_reserve", 0
			)), 0),
			"fact_type": "local_rope_procured",
			"exchange_type": "local_spot_procurement",
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
		var summary := "%s因近期货运需要备料，向%s支付 %d 枚铜币，购入 %d 捆纤维绳索。" % [
			buyer_name,
			seller_name,
			int(offer.get("unit_price", 0)) * quantity,
			quantity,
		]
		var exchange_id := "exchange.local_procurement.%s.day%d" % [
			_safe_id(buyer_id), day,
		]
		var plan := Market.new().plan_trade(policy, {
			"buyer_entity_id": buyer_id,
			"item_instance_id": str(offer.get("item_instance_id", "")),
			"quantity": quantity,
			"quoted_unit_price": int(offer.get("unit_price", 0)),
			"maximum_total_price": spending_limit,
			"exchange_id": exchange_id,
			"purpose_id": purpose_id,
			"purpose_target_id": str(need.get("link_id", "")),
			"source_fact_ids": [str(need.get("fact_id", ""))],
			"summary": summary,
		}, stores, tick)
		if not bool(plan.get("success", false)):
			events.append(_blocked_event(
				settlement_id, day, str(plan.get("error", "trade_rejected")),
				need, buyer_id, seller_id
			))
			continue
		var transaction: Variant = plan.get("transaction")
		transaction.add_state_change({
			"entity_id": buyer_id,
			"key": "last_local_procurement",
			"to": {
				"day": day,
				"fact_id": str(plan.get("fact_id", "")),
				"purpose_id": purpose_id,
				"purpose_target_id": str(need.get("link_id", "")),
				"quantity": quantity,
				"total_price": int(plan.get("total_price", 0)),
			},
		})
		transaction.set_narrative_result({
			"title": "本地物资完成现货采购",
			"summary": summary,
			"tone": "local_procurement",
		})
		transaction.mark_resolved("local_rope_procurement")
		results.append(transaction)
		events.append({
			"event_type": "local_rope_procured",
			"status": "settled",
			"settlement_id": settlement_id,
			"buyer_entity_id": buyer_id,
			"seller_entity_id": seller_id,
			"purpose_id": purpose_id,
			"purpose_target_id": str(need.get("link_id", "")),
			"source_fact_id": str(need.get("fact_id", "")),
			"fact_id": str(plan.get("fact_id", "")),
			"quantity": quantity,
			"total_price": int(plan.get("total_price", 0)),
			"day": day,
		})
	return {"results": results, "events": events}


func _latest_shipment_need(
		snapshot: Variant,
		settlement_id: String,
		day: int,
		config: Dictionary
) -> Dictionary:
	var latest: Dictionary = {}
	var lookback := maxi(int(config.get("recent_shipment_days", 7)), 1)
	for fact: Dictionary in snapshot.get_facts():
		var fact_day := int(fact.get("day", 0))
		if (
			str(fact.get("fact_type", "")) != "settlement_trade_shipment"
			or day - fact_day < 0
			or day - fact_day >= lookback
			or settlement_id not in [
				str(fact.get("source_settlement_id", "")),
				str(fact.get("destination_settlement_id", "")),
			]
		):
			continue
		if (
			latest.is_empty()
			or fact_day > int(latest.get("day", 0))
			or (
				fact_day == int(latest.get("day", 0))
				and str(fact.get("fact_id", "")) > str(latest.get("fact_id", ""))
			)
		):
			latest = fact.duplicate(true)
	return latest


func _select_buyer(
		snapshot: Variant,
		settlement_id: String,
		config: Dictionary
) -> Dictionary:
	var purposes: Dictionary = config.get("buyer_purposes", {})
	var priority: Array = config.get("buyer_priority", purposes.keys())
	var candidates: Array[Dictionary] = []
	for entity: Dictionary in snapshot.get_entities_by_type("institution"):
		var prototype_id := str(entity.get("prototype_id", ""))
		if (
			str(entity.get("settlement_id", "")) != settlement_id
			or not purposes.has(prototype_id)
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
		config: Dictionary
) -> Dictionary:
	var occupations: Array = config.get("seller_occupation_ids", [])
	var item_def_id := str(config.get("item_def_id", "item.fiber_rope"))
	var retained := maxi(int(config.get("seller_retained_quantity", 1)), 0)
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


func _item_quantity(snapshot: Variant, holder_id: String, item_def_id: String) -> int:
	var quantity := 0
	for item: Dictionary in snapshot.get_items():
		if (
			item.get("holder", {}) == {"kind": "entity", "id": holder_id}
			and str(item.get("item_def_id", "")) == item_def_id
		):
			quantity += int(item.get("quantity", 0))
	return quantity


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
		"purpose_target_id": str(need.get("link_id", "")),
		"source_fact_id": str(need.get("fact_id", "")),
		"day": day,
	}


func _safe_id(value: String) -> String:
	return value.replace(".", "_").replace(":", "_").replace("/", "_")
