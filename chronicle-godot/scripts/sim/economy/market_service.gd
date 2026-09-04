extends RefCounted
class_name V5MarketService

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


func build_stock_view(
		policy: Dictionary,
		stores: Dictionary,
		buyer_entity_id: String
) -> Dictionary:
	var seller_entity_id := str(policy.get("seller_entity_id", ""))
	var item_store: Variant = stores.get("item_store")
	var policy_error := _policy_error(policy)
	if item_store == null or policy_error != "":
		return {
			"market_policy_id": str(policy.get("market_policy_id", "")),
			"seller_entity_id": seller_entity_id,
			"buyer_entity_id": buyer_entity_id,
			"offers": [],
			"error": (
				"market_item_store_missing"
				if item_store == null
				else policy_error
			),
		}

	var offers: Array = []
	for item: Dictionary in item_store.list_items_for_owner(seller_entity_id):
		if not _is_sellable(item, policy):
			continue
		var quote := _quote(item, policy, stores, buyer_entity_id)
		var retained_quantity := _retained_quantity(item, policy)
		offers.append({
			"item_instance_id": str(item.get("item_instance_id", "")),
			"item_def_id": str(item.get("item_def_id", "")),
			"display_name": str(item.get("display_name", "")),
			"quantity": int(item.get("quantity", 0)),
			"available_quantity": int(item.get("quantity", 0)) - retained_quantity,
			"retained_quantity": retained_quantity,
			"unit_price": int(quote.get("unit_price", 0)),
			"currency_item_def_id": str(
				quote.get("currency_item_def_id", "")
			),
			"quote_status": "quoted",
			"quote_factors": (
				quote.get("quote_factors", []) as Array
			).duplicate(true),
			"quote_summary": str(quote.get("quote_summary", "")),
		})
	return {
		"market_policy_id": str(policy.get("market_policy_id", "")),
		"display_name": str(policy.get("display_name", "补给交易")),
		"seller_entity_id": seller_entity_id,
		"buyer_entity_id": buyer_entity_id,
		"offers": offers,
		"error": "",
	}


func execute_trade(
		policy: Dictionary,
		intent: Dictionary,
		stores: Dictionary,
		writer: Variant,
		world_time: Dictionary
) -> Dictionary:
	var plan := plan_trade(policy, intent, stores, world_time)
	if not bool(plan.get("success", false)):
		return plan
	var transaction: Variant = plan.get("transaction")
	if not writer.apply_result(transaction, stores):
		return _failure("trade_transaction_rejected", {
			"writer_report": writer.last_report.duplicate(true),
		})
	var result := plan.duplicate()
	result.erase("transaction")
	result["transaction_result"] = transaction.to_dict()
	return result


func plan_trade(
		policy: Dictionary,
		intent: Dictionary,
		stores: Dictionary,
		world_time: Dictionary
) -> Dictionary:
	var buyer_entity_id := str(intent.get("buyer_entity_id", ""))
	var seller_entity_id := str(policy.get("seller_entity_id", ""))
	var item_instance_id := str(intent.get("item_instance_id", ""))
	var quantity := int(intent.get("quantity", 0))
	if (
		buyer_entity_id == ""
		or seller_entity_id == ""
		or buyer_entity_id == seller_entity_id
		or quantity < 1
	):
		return _failure("invalid_trade_intent")
	var party_error := _party_error(stores, buyer_entity_id, seller_entity_id)
	if party_error != "":
		return _failure(party_error)

	var stock_view := build_stock_view(policy, stores, buyer_entity_id)
	if str(stock_view.get("error", "")) != "":
		return _failure(str(stock_view.get("error", "market_not_configured")))
	var offer := _find_offer(stock_view, item_instance_id)
	if offer.is_empty():
		return _failure("offer_no_longer_available")
	if quantity > int(offer.get("available_quantity", 0)):
		return _failure("insufficient_stock")
	var unit_price := int(offer.get("unit_price", 0))
	if int(intent.get("quoted_unit_price", -1)) != unit_price:
		return _failure("quote_changed", {
			"current_offer": offer.duplicate(true),
		})
	var total_price := unit_price * quantity
	var maximum_total_price := int(intent.get("maximum_total_price", -1))
	if maximum_total_price >= 0 and total_price > maximum_total_price:
		return _failure("spending_limit_exceeded")
	var currency_item_def_id := str(offer.get("currency_item_def_id", ""))
	var payment_items := _find_payment_stacks(
		stores.get("item_store"),
		buyer_entity_id,
		currency_item_def_id,
		total_price,
		maxi(int(policy.get("buyer_currency_reserve", 0)), 0)
	)
	if payment_items.is_empty():
		return _failure("insufficient_payment")

	var exchange_id := str(intent.get("exchange_id", ""))
	if exchange_id == "":
		var sequence := _next_trade_sequence(stores)
		exchange_id = "exchange.market.%s.%d" % [
			_sanitize_id(str(policy.get("market_policy_id", "market"))),
			sequence,
		]
	var exchange_store: Variant = stores.get("exchange_store")
	if exchange_store != null and not exchange_store.find_exchange(exchange_id).is_empty():
		return _failure("trade_already_recorded")
	var fact_id := "fact.%s" % exchange_id
	var tick := int(world_time.get("elapsed_hours", 0))
	var source_value: Variant = intent.get("source_fact_ids", [])
	if not source_value is Array:
		return _failure("source_fact_ids_invalid")
	var source_fact_ids: Array = (source_value as Array).duplicate(true)
	var purpose_id := str(intent.get("purpose_id", ""))
	var purpose_target_id := str(intent.get("purpose_target_id", ""))
	var transaction = TransactionResultModel.new()
	transaction.add_fact({
		"fact_id": fact_id,
		"fact_type": str(policy.get("fact_type", "market_trade_completed")),
		"actor_id": buyer_entity_id,
		"target_id": seller_entity_id,
		"location_id": str(policy.get("location_id", "")),
		"tick": tick,
		"day": int(world_time.get("day", 0)),
		"purpose_id": purpose_id,
		"purpose_target_id": purpose_target_id,
		"source_fact_ids": source_fact_ids,
		"summary": str(intent.get("summary", "")),
		"fields": {
			"market_policy_id": str(policy.get("market_policy_id", "")),
			"item_def_id": str(offer.get("item_def_id", "")),
			"quantity": quantity,
			"unit_price": unit_price,
			"total_price": total_price,
			"currency_item_def_id": currency_item_def_id,
			"purpose_id": purpose_id,
			"purpose_target_id": purpose_target_id,
		},
	})
	_add_stack_transfer(
		transaction,
		offer,
		quantity,
		buyer_entity_id,
		"goods",
		exchange_id,
		fact_id,
		tick
	)
	transaction.item_changes.back()["expected_holder"] = {
		"kind": "entity", "id": seller_entity_id,
	}
	var remaining_payment := total_price
	for index: int in range(payment_items.size()):
		if remaining_payment <= 0:
			break
		var payment_item: Dictionary = payment_items[index]
		var payment_quantity := mini(
			remaining_payment, int(payment_item.get("quantity", 0))
		)
		_add_stack_transfer(
			transaction,
			payment_item,
			payment_quantity,
			seller_entity_id,
			"payment%d" % index,
			exchange_id,
			fact_id,
			tick
		)
		transaction.item_changes.back()["expected_holder"] = {
			"kind": "entity", "id": buyer_entity_id,
		}
		transaction.item_changes.back()["payment_fact_id"] = fact_id
		remaining_payment -= payment_quantity
	var pressure_change := _trade_pressure_change(policy, quantity, fact_id)
	if not pressure_change.is_empty():
		transaction.add_pressure_change(pressure_change)
	transaction.add_exchange({
		"exchange_id": exchange_id,
		"exchange_type": str(policy.get("exchange_type", "market_purchase")),
		"status": "settled",
		"party_a": buyer_entity_id,
		"party_b": seller_entity_id,
		"scope_type": "location",
		"scope_id": str(policy.get("location_id", "")),
		"created_tick": tick,
		"settled_tick": tick,
		"source_fact_ids": [fact_id] + source_fact_ids,
		"terms": {
			"item_def_id": str(offer.get("item_def_id", "")),
			"quantity": quantity,
			"unit_price": unit_price,
			"total_price": total_price,
			"currency_item_def_id": currency_item_def_id,
			"purpose_id": purpose_id,
			"purpose_target_id": purpose_target_id,
		},
	})
	transaction.mark_resolved("market_trade")
	return {
		"success": true,
		"error": "",
		"exchange_id": exchange_id,
		"fact_id": fact_id,
		"quantity": quantity,
		"unit_price": unit_price,
		"total_price": total_price,
		"offer": offer.duplicate(true),
		"transaction": transaction,
	}


func _quote(
		item: Dictionary,
		policy: Dictionary,
		stores: Dictionary,
		buyer_entity_id: String
) -> Dictionary:
	var base_value := maxf(float(item.get("base_value", 0.0)), 0.0)
	var markup := maxf(float(policy.get("base_markup", 0.0)), -0.95)
	var price := base_value * (1.0 + markup)
	var factors: Array = [{
		"factor_id": "base_value",
		"label": "基础价值",
		"value": base_value,
		"multiplier": 1.0,
	}]
	var pressure_store: Variant = stores.get("pressure_store")
	for binding: Dictionary in policy.get("pressure_bindings", []):
		var scope_id := str(binding.get("scope_id", ""))
		var pressure_type := str(binding.get("pressure_type", ""))
		var value := 0
		if pressure_store != null:
			value = pressure_store.get_pressure_value(scope_id, pressure_type)
		var multiplier := maxf(
			1.0 + float(binding.get("price_factor_per_point", 0.0)) * value,
			0.05
		)
		price *= multiplier
		factors.append({
			"factor_id": "pressure:%s" % pressure_type,
			"label": str(binding.get("label", pressure_type)),
			"value": value,
			"multiplier": multiplier,
		})
	var discount: Dictionary = policy.get("relationship_discount", {})
	if not discount.is_empty():
		var relation_store: Variant = stores.get("relationship_store")
		var axis := str(discount.get("axis", "trust"))
		var relation_value := 0
		if relation_store != null:
			relation_value = int(relation_store.get_relation(
				str(policy.get("seller_entity_id", "")),
				buyer_entity_id,
				axis,
				0
			))
		var discount_rate := minf(
			maxf(relation_value, 0) * float(
				discount.get("discount_per_point", 0.0)
			),
			float(discount.get("maximum_discount", 0.0))
		)
		var relation_multiplier := maxf(1.0 - discount_rate, 0.05)
		price *= relation_multiplier
		factors.append({
			"factor_id": "relationship:%s" % axis,
			"label": str(discount.get("label", axis)),
			"value": relation_value,
			"multiplier": relation_multiplier,
		})
	var unit_price := maxi(ceili(price), 1)
	var currency_ids: Array = policy.get("accepted_currency_item_def_ids", [])
	return {
		"unit_price": unit_price,
		"currency_item_def_id": "" if currency_ids.is_empty() else str(
			currency_ids[0]
		),
		"quote_factors": factors,
		"quote_summary": _quote_summary(unit_price, factors),
	}


func _is_sellable(item: Dictionary, policy: Dictionary) -> bool:
	if int(item.get("quantity", 0)) <= _retained_quantity(item, policy):
		return false
	if "trade" not in (item.get("capabilities", []) as Array):
		return false
	var allowed_defs: Array = policy.get("sellable_item_def_ids", [])
	var allowed_tags: Array = policy.get("sellable_item_tags_any", [])
	if allowed_defs.is_empty() and allowed_tags.is_empty():
		return true
	if str(item.get("item_def_id", "")) in allowed_defs:
		return true
	for tag: Variant in item.get("tags", []):
		if tag in allowed_tags:
			return true
	return false


func _retained_quantity(item: Dictionary, policy: Dictionary) -> int:
	var by_definition: Dictionary = policy.get("minimum_retained_by_item_def", {})
	return maxi(int(by_definition.get(
		str(item.get("item_def_id", "")),
		policy.get("minimum_retained_quantity", 0)
	)), 0)


func _find_offer(stock_view: Dictionary, item_instance_id: String) -> Dictionary:
	for offer: Dictionary in stock_view.get("offers", []):
		if str(offer.get("item_instance_id", "")) == item_instance_id:
			return offer.duplicate(true)
	return {}


func _find_payment_stacks(
		item_store: Variant,
		owner_id: String,
		item_def_id: String,
		quantity: int,
		reserve: int = 0
) -> Array:
	if item_store == null:
		return []
	var rows: Array = []
	var balance := 0
	for item: Dictionary in item_store.list_items_for_owner(owner_id):
		if str(item.get("item_def_id", "")) != item_def_id:
			continue
		rows.append(item.duplicate(true))
		balance += int(item.get("quantity", 0))
	return rows if balance - reserve >= quantity else []


func _party_error(
		stores: Dictionary,
		buyer_entity_id: String,
		seller_entity_id: String
) -> String:
	var entity_store: Variant = stores.get("entity_store")
	var state_store: Variant = stores.get("state_store")
	for party: Dictionary in [
		{"id": buyer_entity_id, "label": "buyer"},
		{"id": seller_entity_id, "label": "seller"},
	]:
		var entity_id := str(party.get("id", ""))
		var label := str(party.get("label", "party"))
		if entity_store == null or not entity_store.is_entity_active(entity_id):
			return label + "_unavailable"
		var entity: Dictionary = entity_store.get_entity(entity_id)
		if (
			str(entity.get("type", "")) == "person"
			and state_store != null
			and str(state_store.get_state(entity_id, "life_status", "alive")) != "alive"
		):
			return label + "_unavailable"
	return ""


func _add_stack_transfer(
		transaction: Variant,
		item: Dictionary,
		quantity: int,
		new_owner_id: String,
		role: String,
		exchange_id: String,
		fact_id: String,
		tick: int
) -> void:
	var item_instance_id := str(item.get("item_instance_id", ""))
	var change := {
		"item_instance_id": item_instance_id,
		"new_holder": {"kind": "entity", "id": new_owner_id},
		"source_fact_ids": [fact_id],
		"updated_tick": tick,
	}
	if quantity == int(item.get("quantity", item.get("available_quantity", 0))):
		change["operation"] = "transfer"
	else:
		change["operation"] = "split_stack"
		change["quantity"] = quantity
		change["new_item_instance_id"] = "item_instance.%s.%s" % [
			_sanitize_id(exchange_id),
			role,
		]
	transaction.add_item_change(change)


func _trade_pressure_change(
		policy: Dictionary,
		quantity: int,
		fact_id: String
) -> Dictionary:
	var config: Dictionary = policy.get("trade_pressure_change", {})
	if config.is_empty():
		return {}
	return {
		"domain": str(config.get("domain", "economy")),
		"scope_id": str(config.get("scope_id", policy.get("location_id", ""))),
		"pressure_type": str(config.get("pressure_type", "market_pressure")),
		"value": int(config.get("value_per_unit", 0)) * quantity,
		"reason": "market_purchase",
		"source_fact_ids": [fact_id],
	}


func _quote_summary(unit_price: int, factors: Array) -> String:
	var parts: Array[String] = []
	for factor: Dictionary in factors:
		if str(factor.get("factor_id", "")) == "base_value":
			continue
		parts.append("%s %s" % [
			str(factor.get("label", "因素")),
			str(factor.get("value", 0)),
		])
	return "单价 %d 铜币（%s）" % [unit_price, "，".join(parts)]


func _next_trade_sequence(stores: Dictionary) -> int:
	var exchange_store: Variant = stores.get("exchange_store")
	return 1 if exchange_store == null else exchange_store.list_exchanges().size() + 1


func _policy_error(policy: Dictionary) -> String:
	if str(policy.get("market_policy_id", "")) == "":
		return "market_policy_id_missing"
	if str(policy.get("seller_entity_id", "")) == "":
		return "market_seller_not_configured"
	var currency_value: Variant = policy.get("accepted_currency_item_def_ids", [])
	if not currency_value is Array or (currency_value as Array).is_empty():
		return "market_currency_not_configured"
	if str((currency_value as Array)[0]) == "":
		return "market_currency_not_configured"
	return ""


func _sanitize_id(value: String) -> String:
	return value.replace(".", "_").replace(":", "_").replace("/", "_")


func _failure(error: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "error": error}
	result.merge(extra, true)
	return result
