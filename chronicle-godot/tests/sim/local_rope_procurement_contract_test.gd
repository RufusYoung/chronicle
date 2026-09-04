extends SceneTree

const Session = preload("res://scripts/sim/core/sim_session.gd")
const Market = preload("res://scripts/sim/economy/market_service.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")
const Transaction = preload("res://scripts/sim/transaction/transaction_result.gd")
const FIXTURE := "res://data/sim/fixtures/generated_settlement_network_fixture.json"
const BOUNDARY_FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const RULES := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_natural_procurement()
	if not failures.is_empty():
		_finish()
		return
	_test_trade_boundaries()
	_test_stale_resources()
	_finish()


func _test_natural_procurement() -> void:
	var session: Variant = _start(true)
	var initial_currency := _currency(session)
	var purchase: Dictionary = {}
	var procurement_events: Array = []
	for _day: int in range(10):
		var advanced: Dictionary = session.advance_time(24, "local_procurement_natural")
		_check(advanced.get("success", false), "natural world advances a full day")
		for event: Dictionary in advanced.get("network_events", []):
			if str(event.get("event_type", "")) in [
				"local_rope_procured", "local_procurement_blocked",
			]:
				procurement_events.append(event.duplicate(true))
		var purchases := _facts(session, "local_rope_procured")
		if not purchases.is_empty():
			purchase = purchases[0]
			break
	_check(not purchase.is_empty(), "recent autonomous freight naturally causes one local rope purchase")
	if purchase.is_empty():
		print("[LOCAL PROCUREMENT DIAGNOSTIC] ", JSON.stringify({
			"procurement_events": procurement_events,
			"shipment_count": _facts(session, "settlement_trade_shipment").size(),
			"rope_holders": _item_holders(session, "item.fiber_rope"),
			"active_buyers": _active_procurement_buyers(session),
		}))
		return
	var source_ids: Array = purchase.get("source_fact_ids", [])
	var source: Dictionary = (
		{}
		if source_ids.is_empty()
		else session.stores["fact_store"].get_fact(str(source_ids[0]))
	)
	var buyer_id := str(purchase.get("actor_id", ""))
	var seller_id := str(purchase.get("target_id", ""))
	var obligation_id := str(purchase.get("purpose_obligation_id", ""))
	var exchange_id := str(purchase.get("fact_id", "")).trim_prefix("fact.")
	var exchange: Dictionary = session.stores["exchange_store"].find_exchange(exchange_id)
	var demand: Dictionary = session.stores["obligation_store"].find_obligation(
		obligation_id
	)
	_check(
		str(source.get("fact_type", "")) == "settlement_trade_shipment"
		and str(purchase.get("purpose_id", "")) != ""
		and str(purchase.get("purpose_target_id", "")) == str(source.get("link_id", "")),
		"purchase cites the actual freight fact, route, and organization-specific purpose"
	)
	_check(
		obligation_id != ""
		and str(demand.get("obligation_type", ""))
			== "operational_material_demand"
		and str(demand.get("material_status", "")) == "acquired"
		and str(demand.get("procurement_fact_id", ""))
			== str(purchase.get("fact_id", "")),
		"purchase fulfills the acquisition stage of a real route-work demand"
	)
	_check(
		str(exchange.get("status", "")) == "settled"
		and str(exchange.get("exchange_type", "")) == "local_spot_procurement"
		and str(exchange.get("party_a", "")) == buyer_id
		and str(exchange.get("party_b", "")) == seller_id
		and int(exchange.get("terms", {}).get("total_price", 0)) == 5,
		"settled Exchange names both parties and the real five-coin price"
	)
	_check(
		_item_quantity(session, seller_id, "item.fiber_rope") >= 1,
		"seller retains at least one rope after the local sale"
	)
	_check(
		_item_history_has_fact(session, "item.fiber_rope", str(purchase.get("fact_id", ""))),
		"purchased rope records the procurement fact in item provenance"
	)
	_check(
		_currency(session) == initial_currency,
		"local payment conserves the world's copper-coin quantity"
	)
	var receipt: Dictionary = session.stores["state_store"].get_state(
		buyer_id, "last_local_procurement", {}
	)
	_check(
		str(receipt.get("fact_id", "")) == str(purchase.get("fact_id", ""))
		and int(receipt.get("quantity", 0)) == 1
		and int(receipt.get("total_price", 0)) == 5,
		"buyer state retains a compact procurement receipt"
	)
	_check(session.validate_persistent_references().get("ok", false), "natural purchase keeps all persistent references valid")
	var first_use: Dictionary = {}
	var worn_out: Dictionary = {}
	var lifecycle_events: Array = []
	for _day: int in range(12):
		var advanced: Dictionary = session.advance_time(
			24, "local_procurement_material_lifecycle"
		)
		_check(advanced.get("success", false), "natural material lifecycle advances a full day")
		lifecycle_events.append_array(advanced.get("network_events", []))
		var uses := _facts(session, "operational_material_used")
		if first_use.is_empty() and not uses.is_empty():
			first_use = uses[0]
		var retired := _facts(session, "operational_material_worn_out")
		if not retired.is_empty():
			worn_out = retired[0]
			break
	_check(not first_use.is_empty(), "a later real shipment uses the purchased rope")
	if not first_use.is_empty():
		var work_fact: Dictionary = session.stores["fact_store"].get_fact(
			str(first_use.get("work_fact_id", ""))
		)
		var fulfilled_demand: Dictionary = session.stores[
			"obligation_store"
		].find_obligation(str(first_use.get("demand_obligation_id", "")))
		_check(
			str(work_fact.get("fact_type", "")) == "settlement_trade_shipment"
			and str(first_use.get("procurement_fact_id", ""))
				== str(purchase.get("fact_id", ""))
			and float(first_use.get("transport_cost_reduction", 0.0)) > 0.0
			and is_equal_approx(
				float(work_fact.get("transport_cost_without_material", 0.0))
					- float(work_fact.get("transport_cost", 0.0)),
				float(first_use.get("transport_cost_reduction", 0.0))
			),
			"rope use cites the procurement, demand, actual shipment, and applied effect"
		)
		_check(
			int(first_use.get("durability_before", 0)) == 4
			and int(first_use.get("durability_after", 0)) == 3
			and str(fulfilled_demand.get("status", "")) == "fulfilled"
			and str(fulfilled_demand.get("fulfilled_by_fact_id", ""))
				== str(first_use.get("fact_id", "")),
			"one coarse work cycle wears one durability and fulfills one demand"
		)
	_check(not worn_out.is_empty(), "four supported work cycles naturally wear out the rope")
	if not worn_out.is_empty():
		var retired_item: Dictionary = session.stores["item_store"].get_item(
			str(worn_out.get("item_instance_id", ""))
		)
		_check(
			int(retired_item.get("quantity", -1)) == 0
			and str(retired_item.get("holder", {}).get("kind", "")) == "destroyed"
			and int(retired_item.get("condition", {}).get("durability", -1)) == 0,
			"a fully worn rope exits usable inventory instead of blocking replacement"
		)
		_check(
			_has_open_material_demand(
				session,
				str(worn_out.get("scope_id", "")),
				"item.fiber_rope"
			),
			"continued route work opens replacement demand after the rope is retired"
		)
	var replacement: Dictionary = {}
	var replacement_demand: Dictionary = {}
	for candidate: Dictionary in _facts(session, "local_rope_procured"):
		if (
			str(candidate.get("fact_id", "")) != str(purchase.get("fact_id", ""))
			and str(candidate.get("purpose_target_id", ""))
				== str(purchase.get("purpose_target_id", ""))
			and int(candidate.get("day", 0)) >= int(worn_out.get("day", 0))
		):
			replacement = candidate
			replacement_demand = session.stores[
				"obligation_store"
			].find_obligation(str(candidate.get(
				"purpose_obligation_id", ""
			)))
			break
	_check(
		not replacement.is_empty()
		and str(replacement.get("purpose_obligation_id", ""))
			!= obligation_id
		and str(replacement_demand.get("owner_id", ""))
			== str(worn_out.get("target_id", ""))
		and _currency(session) == initial_currency,
		"worn stock causes a newly demanded and fully funded replacement purchase"
	)
	_check(
		session.validate_persistent_references().get("ok", false),
		"demand, use, wear, and retirement keep persistent references valid"
	)
	print("[LOCAL PROCUREMENT SAMPLE] ", JSON.stringify({
		"day": purchase.get("day", 0),
		"buyer": buyer_id,
		"seller": seller_id,
		"purpose": purchase.get("purpose_id", ""),
		"route": purchase.get("purpose_target_id", ""),
		"price": purchase.get("fields", {}).get("total_price", 0),
		"uses": _facts(session, "operational_material_used").size(),
		"worn_out": not worn_out.is_empty(),
		"purchase_count": _facts(session, "local_rope_procured").size(),
		"lifecycle_event_count": lifecycle_events.size(),
	}))


func _test_trade_boundaries() -> void:
	var prepared := _prepared_trade()
	var session: Variant = prepared.get("session")
	if session == null:
		return
	var policy: Dictionary = prepared["policy"]
	var intent: Dictionary = prepared["intent"]
	var offer: Dictionary = prepared["offer"]
	_check(
		int(offer.get("retained_quantity", 0)) == 1
		and int(offer.get("available_quantity", 0))
			== int(prepared.get("seller_quantity", 0)) - 1,
		"stock view exposes only rope above the producer's self-retained unit"
	)
	var before: Dictionary = session.get_save_store_data()
	var wrong_target_intent := intent.duplicate(true)
	wrong_target_intent["purpose_target_id"] = "route.test.wrong"
	var wrong_target := Market.new().plan_trade(
		policy, wrong_target_intent, session.stores, session.get_time_summary()
	)
	_check(
		str(wrong_target.get("error", ""))
			== "purpose_obligation_target_mismatch"
		and before == session.get_save_store_data(),
		"a work-material purchase cannot bind an unrelated route demand"
	)
	var wrong_purpose_intent := intent.duplicate(true)
	wrong_purpose_intent["purpose_id"] = "personal_resale"
	var wrong_purpose := Market.new().plan_trade(
		policy, wrong_purpose_intent, session.stores, session.get_time_summary()
	)
	_check(
		str(wrong_purpose.get("error", ""))
			== "purpose_obligation_purpose_mismatch"
		and before == session.get_save_store_data(),
		"a work-material purchase cannot relabel the demand as another purpose"
	)
	var over_budget_intent := intent.duplicate(true)
	over_budget_intent["maximum_total_price"] = 4
	var over_budget := Market.new().plan_trade(
		policy, over_budget_intent, session.stores, session.get_time_summary()
	)
	_check(
		str(over_budget.get("error", "")) == "spending_limit_exceeded"
		and before == session.get_save_store_data(),
		"declared spending limit rejects the quote without mutating stores"
	)
	var seller_id := str(policy.get("seller_entity_id", ""))
	session.stores["state_store"].apply_state_change({
		"entity_id": seller_id, "key": "life_status", "to": "dead",
	})
	var dead_seller := Market.new().plan_trade(
		policy, intent, session.stores, session.get_time_summary()
	)
	_check(str(dead_seller.get("error", "")) == "seller_unavailable", "a dead seller cannot settle a quoted sale")
	session.stores["state_store"].apply_state_change({
		"entity_id": seller_id, "key": "life_status", "to": "alive",
	})
	var plan := Market.new().plan_trade(policy, intent, session.stores, session.get_time_summary())
	_check(plan.get("success", false), "a valid local spot purchase produces an unapplied transaction plan")
	if not bool(plan.get("success", false)):
		return
	var transaction: Variant = plan.get("transaction")
	_check(session.writer.apply_result(transaction, session.stores), "valid purchase commits goods, payment, fact, and Exchange atomically")
	var after: Dictionary = session.get_save_store_data()
	_check(
		not session.writer.apply_result(transaction, session.stores)
		and after == session.get_save_store_data()
		and "payment_already_recorded" in str(session.writer.last_report),
		"replaying the same purchase is rejected without a second delivery or payment"
	)
	var duplicate := Market.new().plan_trade(
		policy, intent, session.stores, session.get_time_summary()
	)
	_check(str(duplicate.get("error", "")) == "trade_already_recorded", "settled Exchange identity cannot be planned again")
	var buyer_id := str(intent.get("buyer_entity_id", ""))
	session.stores["entity_store"].entities[buyer_id]["lifecycle_status"] = "retired"
	var retired_intent := intent.duplicate(true)
	retired_intent["exchange_id"] = str(intent.get("exchange_id", "")) + ".retired"
	var retired := Market.new().plan_trade(
		policy, retired_intent, session.stores, session.get_time_summary()
	)
	_check(str(retired.get("error", "")) == "buyer_unavailable", "a retired buying organization cannot place another order")


func _test_stale_resources() -> void:
	var prepared := _prepared_trade()
	var session: Variant = prepared.get("session")
	if session == null:
		return
	var policy: Dictionary = prepared["policy"]
	var intent: Dictionary = prepared["intent"]
	var buyer_id := str(intent.get("buyer_entity_id", ""))
	var seller_id := str(policy.get("seller_entity_id", ""))
	var funds_sink_id := _other_person(session, buyer_id)
	var balance := Treasury.new(session.get_snapshot()).balance(buyer_id)
	var reserve := int(policy.get("buyer_currency_reserve", 0))
	var drain: Variant = _transaction("funds_reserved")
	_check(
		Treasury.new(session.get_snapshot()).append_payment(
			drain, buyer_id, funds_sink_id, balance - reserve,
			str(drain.facts_added[0]["fact_id"]),
			int(session.get_time_summary().get("elapsed_hours", 0))
		)
		and session.writer.apply_result(drain, session.stores),
		"test injection transfers the buyer's spendable money elsewhere"
	)
	var unfunded := Market.new().plan_trade(
		policy, intent, session.stores, session.get_time_summary()
	)
	_check(str(unfunded.get("error", "")) == "insufficient_payment", "funds used by another commitment invalidate the old quote")
	var transfer: Variant = _transaction("seller_lost_goods")
	var other_id := _other_person(session, seller_id)
	transfer.add_item_change({
		"operation": "transfer",
		"item_instance_id": str(intent.get("item_instance_id", "")),
		"new_holder": {"kind": "entity", "id": other_id},
		"expected_holder": {"kind": "entity", "id": seller_id},
		"source_fact_ids": [str(transfer.facts_added[0]["fact_id"])],
	})
	_check(session.writer.apply_result(transfer, session.stores), "test injection transfers the quoted rope away from the seller")
	var stale_goods := Market.new().plan_trade(
		policy, intent, session.stores, session.get_time_summary()
	)
	_check(str(stale_goods.get("error", "")) == "offer_no_longer_available", "goods moved after quotation cannot be sold by the former holder")


func _prepared_trade() -> Dictionary:
	var data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(BOUNDARY_FIXTURE)
	)
	for entity: Dictionary in data.get("entities", []):
		if str(entity.get("id", "")) != "seventh_outpost":
			continue
		var states: Dictionary = entity.get("states", {})
		states.merge({
			"economic_contract_version": 1,
			"procurement_spending_limit": 5,
			"procurement_treasury_reserve": 2,
		}, true)
		entity["states"] = states
	data["known_facts"] = [
		{
			"fact_id": "fact.test.local_procurement.rope_batch",
			"fact_type": "livelihood_item_produced",
			"actor_id": "cook_marta",
			"target_id": "seventh_outpost",
			"day": 1,
			"summary": "测试注入：玛塔完成了一批绳索。",
		},
		{
			"fact_id": "fact.test.local_procurement.shipment",
			"fact_type": "settlement_trade_shipment",
			"actor_id": "seventh_outpost",
			"target_id": "seventh_outpost",
			"source_settlement_id": "seventh_outpost",
			"destination_settlement_id": "seventh_outpost",
			"link_id": "route.test.outpost_supply",
			"day": 1,
			"summary": "测试注入：一批货物抵达哨站。",
		},
	]
	data["initial_obligations"] = [{
		"obligation_id": "obligation.test.local_procurement.route_material",
		"owner_id": "seventh_outpost",
		"target_id": "seventh_outpost",
		"obligation_type": "operational_material_demand",
		"status": "open",
		"material_status": "needed",
		"scope_type": "route",
		"scope_id": "route.test.outpost_supply",
		"use_id": "shipment_lashing",
		"item_def_id": "item.fiber_rope",
		"quantity_required": 1,
		"accepted_purpose_ids": ["route_maintenance_reserve"],
		"opened_day": 1,
		"needed_from_day": 2,
		"opened_by_fact_id": "fact.test.local_procurement.shipment",
		"source_fact_ids": ["fact.test.local_procurement.shipment"],
	}]
	var items: Array = data.get("initial_items", [])
	items.append({
		"item_instance_id": "item_instance.test.local_procurement.rope",
		"item_def_id": "item.fiber_rope",
		"holder": {"kind": "entity", "id": "cook_marta"},
		"quantity": 3,
		"condition": {},
		"custom_tags": ["test_injection"],
		"provenance": {
			"created_by_fact_id": "fact.test.local_procurement.rope_batch",
		},
		"history": [],
		"created_tick": 0,
		"updated_tick": 0,
	})
	items.append({
		"item_instance_id": "item_instance.test.local_procurement.treasury",
		"item_def_id": Treasury.CURRENCY,
		"holder": {"kind": "entity", "id": "seventh_outpost"},
		"quantity": 12,
		"condition": {},
		"custom_tags": ["test_injection"],
		"provenance": {"source": "local_procurement_contract_test"},
		"history": [],
		"created_tick": 0,
		"updated_tick": 0,
	})
	data["initial_items"] = items
	var session: Variant = Session.new()
	var started: Dictionary = session.start_from_fixture_data(data, [])
	_check(bool(started.get("success", false)), "test-injected procurement boundary fixture starts")
	if not bool(started.get("success", false)):
		return {}
	var snapshot: Variant = session.get_snapshot()
	var buyer_id := "seventh_outpost"
	var seller_id := "cook_marta"
	var policy := {
		"market_policy_id": "market_policy.test.local_procurement",
		"seller_entity_id": seller_id,
		"location_id": "outpost_courtyard",
		"sellable_item_def_ids": ["item.fiber_rope"],
		"accepted_currency_item_def_ids": [Treasury.CURRENCY],
		"minimum_retained_quantity": 1,
		"buyer_currency_reserve": int(snapshot.get_entity_state(
			buyer_id, "procurement_treasury_reserve", 0
		)),
		"fact_type": "local_rope_procured",
		"exchange_type": "local_spot_procurement",
	}
	var stock := Market.new().build_stock_view(policy, session.stores, buyer_id)
	var offer: Dictionary = {}
	for candidate: Dictionary in stock.get("offers", []):
		if str(candidate.get("item_instance_id", "")) == "item_instance.test.local_procurement.rope":
			offer = candidate
			break
	var intent := {
		"buyer_entity_id": buyer_id,
		"item_instance_id": str(offer.get("item_instance_id", "")),
		"quantity": 1,
		"quoted_unit_price": int(offer.get("unit_price", 0)),
		"maximum_total_price": int(snapshot.get_entity_state(
			buyer_id, "procurement_spending_limit", 0
		)),
		"exchange_id": "exchange.test.local_procurement",
		"purpose_id": "route_maintenance_reserve",
		"purpose_target_id": "route.test.outpost_supply",
		"purpose_obligation_id": (
			"obligation.test.local_procurement.route_material"
		),
		"source_fact_ids": ["fact.test.local_procurement.shipment"],
		"summary": "测试注入：本地组织采购实际绳索。",
	}
	return {
		"session": session,
		"policy": policy,
		"intent": intent,
		"offer": offer,
		"seller_quantity": _item_quantity(session, seller_id, "item.fiber_rope"),
	}


func _start(procurement_enabled: bool) -> Variant:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	data["settlement_network_generation"]["local_procurement"]["enabled"] = procurement_enabled
	var session = Session.new()
	var started: Dictionary = session.start_from_fixture_data(data, RULES)
	_check(started.get("success", false), "generated economic fixture starts")
	return session


func _transaction(suffix: String) -> Variant:
	var result = Transaction.new()
	result.add_fact({
		"fact_id": "fact.test.local_procurement." + suffix,
		"fact_type": "test_injection",
		"summary": "本地采购边界测试注入",
	})
	result.mark_resolved("test_injection")
	return result


func _other_person(session: Variant, excluded_id: String) -> String:
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		if str(entity.get("type", "")) == "person" and str(entity.get("id", "")) != excluded_id:
			return str(entity.get("id", ""))
	return "player"


func _facts(session: Variant, fact_type: String) -> Array:
	return session.stores["fact_store"].list_facts().filter(func(fact: Dictionary) -> bool:
		return str(fact.get("fact_type", "")) == fact_type)


func _item_quantity(session: Variant, holder_id: String, item_def_id: String) -> int:
	var quantity := 0
	for item: Dictionary in session.stores["item_store"].list_items_for_owner(holder_id):
		if str(item.get("item_def_id", "")) == item_def_id:
			quantity += int(item.get("quantity", 0))
	return quantity


func _item_holders(session: Variant, item_def_id: String) -> Array:
	var rows: Array = []
	for item: Dictionary in session.stores["item_store"].list_items():
		if str(item.get("item_def_id", "")) != item_def_id:
			continue
		var holder_id := str(item.get("holder", {}).get("id", ""))
		rows.append({
			"holder_id": holder_id,
			"quantity": int(item.get("quantity", 0)),
			"settlement_id": session.stores["state_store"].get_state(
				holder_id, "settlement_id", ""
			),
			"occupation_id": session.stores["state_store"].get_state(
				holder_id, "occupation_id", ""
			),
		})
	return rows


func _active_procurement_buyers(session: Variant) -> Array:
	var rows: Array = []
	var purposes: Dictionary = session.get_settlement_network_summary().get(
		"local_procurement", {}
	).get("buyer_purposes", {})
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		if (
			str(entity.get("type", "")) == "institution"
			and purposes.has(str(entity.get("prototype_id", "")))
			and session.stores["entity_store"].is_entity_active(str(entity.get("id", "")))
		):
			rows.append({
				"id": entity.get("id", ""),
				"prototype_id": entity.get("prototype_id", ""),
				"settlement_id": entity.get("settlement_id", ""),
			})
	return rows


func _item_history_has_fact(session: Variant, item_def_id: String, fact_id: String) -> bool:
	for item: Dictionary in session.stores["item_store"].list_items():
		if str(item.get("item_def_id", "")) != item_def_id:
			continue
		if str(item.get("provenance", {}).get("created_by_fact_id", "")) == fact_id:
			return true
		for entry: Dictionary in item.get("history", []):
			if str(entry.get("fact_id", "")) == fact_id:
				return true
	return false


func _has_open_material_demand(
		session: Variant,
		scope_id: String,
		item_def_id: String
) -> bool:
	for obligation: Dictionary in session.stores[
		"obligation_store"
	].find_open_obligations():
		if (
			str(obligation.get("obligation_type", ""))
				== "operational_material_demand"
			and str(obligation.get("scope_id", "")) == scope_id
			and str(obligation.get("item_def_id", "")) == item_def_id
		):
			return true
	return false


func _currency(session: Variant) -> int:
	var total := 0
	for item: Dictionary in session.stores["item_store"].list_items():
		if str(item.get("item_def_id", "")) == Treasury.CURRENCY:
			total += int(item.get("quantity", 0))
	return total


func _check(value: bool, message: String) -> void:
	print("[LOCAL PROCUREMENT %s] %s" % ["PASS" if value else "FAIL", message])
	if not value:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	print("[LOCAL PROCUREMENT RESULT] ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
