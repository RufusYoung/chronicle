extends SceneTree

const Snapshot = preload("res://scripts/sim/core/sim_snapshot.gd")
const MaterialService = preload("res://scripts/sim/economy/operational_material_service.gd")
const Procurement = preload("res://scripts/sim/economy/local_procurement_system.gd")
const Transaction = preload("res://scripts/sim/transaction/transaction_result.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Market = preload("res://scripts/sim/economy/market_service.gd")
const OUTPUT := "user://tests/2026-09-05_material_review_probes.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reports: Array = []
	reports.append(_probe_same_item_two_uses())
	reports.append(_probe_partial_consumption())
	reports.append(_probe_first_demand_blocks_later())
	reports.append(_probe_market_authority())
	var completed := true
	for report: Dictionary in reports:
		completed = completed and bool(report.get("probe_completed", false))
		print("[REVIEW PROBE] ", JSON.stringify(report))
	var output := {
		"baseline_commit": "52de618",
		"date": "2026-09-05",
		"evidence_kind": "test_injection",
		"purpose": "Reproduce review findings; reproduced defects are not passing gameplay contracts.",
		"probes_completed": completed,
		"reports": reports,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write review evidence")
		quit(1)
		return
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("[REVIEW PROBES COMPLETED] ", completed)
	quit(0 if completed else 1)


func _rule(use_id: String) -> Dictionary:
	return {
		"use_id": use_id,
		"trigger_fact_type": "settlement_trade_shipment",
		"item_def_id": "item.fiber_rope",
		"quantity_required": 1,
		"durability_loss_per_cycle": 1,
		"transport_cost_reduction": 0.25,
		"require_acquisition_purpose": false,
	}


func _demand(use_id: String, scope_id: String, opened_day: int = 1) -> Dictionary:
	return {
		"obligation_id": "obligation.review." + use_id + "." + scope_id,
		"obligation_type": "operational_material_demand",
		"status": "open", "material_status": "needed",
		"owner_id": "town", "target_id": "town",
		"scope_type": "route", "scope_id": scope_id,
		"use_id": use_id, "item_def_id": "item.fiber_rope",
		"quantity_required": 1, "opened_day": opened_day,
		"needed_from_day": opened_day + 1,
		"source_fact_ids": [],
	}


func _snapshot(demands: Array, item: Dictionary) -> Variant:
	return Snapshot.new({
		"entities": [{"id": "town", "type": "settlement"}],
		"states": {"town": {"economic_contract_version": 1}},
		"obligations": demands,
		"items": [item],
	})


func _item() -> Dictionary:
	return {
		"item_instance_id": "item.review.rope", "item_def_id": "item.fiber_rope",
		"holder": {"kind": "entity", "id": "town"}, "quantity": 1,
		"condition": {"maximum_durability": 4, "durability": 4},
	}


func _probe_same_item_two_uses() -> Dictionary:
	var snapshot = _snapshot([_demand("a", "road"), _demand("b", "road")], _item())
	var service = MaterialService.new()
	service.configure(snapshot, [_rule("a"), _rule("b")], 3, 72)
	var plans: Array[Dictionary] = service.plan_uses("settlement_trade_shipment", "road", "town")
	var result = Transaction.new()
	service.append_uses(result, plans, "fact.review.work", 0.5)
	var assigned_items: Array = []
	for plan: Dictionary in plans:
		assigned_items.append(plan["item"]["item_instance_id"])
	return {
		"id": "shared_item_double_assignment", "probe_completed": true,
		"reproduced": assigned_items.size() == 2 and assigned_items[0] == assigned_items[1],
		"assigned_items": assigned_items, "use_fact_count": result.facts_added.size(),
		"durability_changes": result.item_changes,
		"expected": "Reserve each item while planning, or explicitly compose multiple uses and cumulative wear.",
	}


func _probe_partial_consumption() -> Dictionary:
	var item := _item()
	item["condition"] = {}
	var rule := _rule("consume")
	rule["consume_quantity_per_cycle"] = 2
	var service = MaterialService.new()
	service.configure(_snapshot([_demand("consume", "road")], item), [rule], 3, 72)
	var plans: Array[Dictionary] = service.plan_uses("settlement_trade_shipment", "road", "town")
	var result = Transaction.new()
	service.append_uses(result, plans, "fact.review.work", 0.25)
	var claimed := int(result.facts_added[0].get("consumed_quantity", 0)) if not result.facts_added.is_empty() else 0
	var consumed := int(result.item_changes[0].get("quantity", 0)) if not result.item_changes.is_empty() else 0
	return {
		"id": "partial_consumption_full_effect", "probe_completed": true,
		"reproduced": claimed == 2 and consumed == 1,
		"available_quantity": 1, "required_consumption": 2,
		"fact_consumed_quantity": claimed, "actual_consumption_change": consumed,
		"expected": "Reject inconsistent material rules or require enough stock before granting the full effect.",
	}


func _probe_first_demand_blocks_later() -> Dictionary:
	var first := _demand("lashing", "first_road")
	first["material_status"] = "acquired"
	var second := _demand("lashing", "second_road", 2)
	var item := _item()
	item["provenance"] = {"created_by_fact_id": "fact.review.purchase"}
	var snapshot = _snapshot([first, second], item)
	snapshot.facts = [{
		"fact_id": "fact.review.purchase", "fact_type": "local_material_procured",
		"purpose_target_id": "first_road", "day": 1,
	}]
	var rule := _rule("lashing")
	rule["require_acquisition_purpose"] = true
	rule["purchase_fact_types"] = ["local_material_procured"]
	var service = MaterialService.new()
	service.configure(snapshot, [rule], 3, 72)
	var network := {
		"local_procurement": {"enabled": true},
		"operational_material_uses": [rule],
		"sites": [{"settlement_id": "town"}],
	}
	var procurement = Procurement.new()
	var chosen: Dictionary = procurement._oldest_material_need(snapshot, "town", service)
	var all_data: Dictionary = procurement.resolve_daily_tick(snapshot, {"day": 3}, network, {})
	snapshot.obligations = [second]
	var second_data: Dictionary = procurement.resolve_daily_tick(snapshot, {"day": 3}, network, {})
	return {
		"id": "old_demand_hides_later_demand", "probe_completed": true,
		"reproduced": chosen.get("scope_id") == "first_road",
		"selected_scope": chosen.get("scope_id"),
		"first_road_usable_quantity": service.usable_quantity(rule, "first_road", "town"),
		"second_road_usable_quantity": service.usable_quantity(rule, "second_road", "town"),
		"with_both_demands_events": all_data.get("events", []),
		"with_only_second_demand_events": second_data.get("events", []),
		"boundary": "This probe demonstrates candidate starvation before buyer availability; it does not claim a funded natural purchase failed.",
	}


func _probe_market_authority() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
	))
	data["initial_obligations"] = [{
		"obligation_id": "obligation.review.foreign", "owner_id": "cook_marta",
		"target_id": "cook_marta", "obligation_type": "operational_material_demand",
		"status": "open", "material_status": "needed", "scope_id": "road",
		"item_def_id": "item.fiber_rope", "accepted_purpose_ids": ["lashing"],
	}]
	data["initial_items"].append({
		"item_instance_id": "item.review.seller_rope", "item_def_id": "item.fiber_rope",
		"holder": {"kind": "entity", "id": "cook_marta"}, "quantity": 3,
	})
	data["initial_items"].append({
		"item_instance_id": "item.review.buyer_money", "item_def_id": "item.copper_coin",
		"holder": {"kind": "entity", "id": "seventh_outpost"}, "quantity": 30,
	})
	var session = Session.new()
	var start: Dictionary = session.start_from_fixture_data(data, [])
	if not bool(start.get("success", false)):
		return {"id": "foreign_obligation_purchase", "probe_completed": false, "start": start}
	var policy := {
		"market_policy_id": "market.review", "seller_entity_id": "cook_marta",
		"location_id": "outpost_courtyard", "sellable_item_def_ids": ["item.fiber_rope"],
		"accepted_currency_item_def_ids": ["item.copper_coin"],
	}
	var market = Market.new()
	var stock: Dictionary = market.build_stock_view(policy, session.stores, "seventh_outpost")
	var offer: Dictionary = {}
	for candidate: Dictionary in stock.get("offers", []):
		if candidate.get("item_instance_id") == "item.review.seller_rope":
			offer = candidate
	var intent := {
		"buyer_entity_id": "seventh_outpost", "item_instance_id": "item.review.seller_rope",
		"quantity": 1, "quoted_unit_price": offer.get("unit_price", -1),
		"exchange_id": "exchange.review", "purpose_id": "lashing",
		"purpose_target_id": "road", "purpose_obligation_id": "obligation.review.foreign",
	}
	var plan: Dictionary = market.plan_trade(policy, intent, session.stores, session.get_time_summary())
	var acquired = Transaction.new()
	acquired.add_obligation_update({"obligation_id": "obligation.review.foreign", "material_status": "acquired"})
	var updated: bool = session.writer.apply_result(acquired, session.stores)
	var replacement: Dictionary = market.plan_trade(policy, intent, session.stores, session.get_time_summary())
	return {
		"id": "foreign_obligation_purchase", "probe_completed": updated,
		"reproduced": bool(plan.get("success", false)),
		"buyer": "seventh_outpost", "obligation_owner": "cook_marta",
		"unrelated_owner_plan_accepted": plan.get("success", false),
		"unrelated_owner_plan_error": plan.get("error", ""),
		"acquired_without_usable_item_error": replacement.get("error", ""),
		"boundary": "Direct market boundary with injected obligation status; no natural theft or loss is claimed.",
	}
