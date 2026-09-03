extends RefCounted
class_name V5TreasuryTransferPlanner

const Market = preload("res://scripts/sim/economy/market_service.gd")
const CURRENCY := "item.copper_coin"

var items: Array = []


func _init(snapshot: Variant = null) -> void:
	if snapshot != null:
		items = snapshot.get_items().duplicate(true)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("item_instance_id", "")) < str(b.get("item_instance_id", "")))


func balance(holder: String) -> int:
	var total := 0
	for item: Dictionary in items:
		if str(item.get("item_def_id", "")) == CURRENCY and item.get("holder", {}) == {"kind": "entity", "id": holder}:
			total += int(item.get("quantity", 0))
	return total


func append_payment(result: Variant, payer: String, recipient: String, amount: int, fact_id: String, tick: int, reserve: int = 0) -> bool:
	if amount <= 0 or payer == recipient or balance(payer) - reserve < amount:
		return false
	var remaining := amount
	var created: Array = []
	for item: Dictionary in items:
		if remaining <= 0:
			break
		if str(item.get("item_def_id", "")) != CURRENCY or item.get("holder", {}) != {"kind": "entity", "id": payer}:
			continue
		var quantity := mini(remaining, int(item.get("quantity", 0)))
		if quantity <= 0:
			continue
		Market.new()._add_stack_transfer(result, item, quantity, recipient,
			"payment%d" % result.item_changes.size(), fact_id, fact_id, tick)
		var change: Dictionary = result.item_changes.back()
		change["expected_holder"] = {"kind": "entity", "id": payer}
		change["payment_fact_id"] = fact_id
		if quantity == int(item.get("quantity", 0)):
			item["holder"] = {"kind": "entity", "id": recipient}
		else:
			var split := item.duplicate(true)
			split["item_instance_id"] = change["new_item_instance_id"]
			split["quantity"] = quantity
			split["holder"] = {"kind": "entity", "id": recipient}
			created.append(split)
			item["quantity"] = int(item["quantity"]) - quantity
		remaining -= quantity
	items.append_array(created)
	return remaining == 0


func append_funding(result: Variant, snapshot: Variant, manager: String, organization: String, source: String, day: int) -> void:
	if int(snapshot.get_entity_state(manager, "economic_contract_version", 0)) != 1:
		return
	var amount := int(snapshot.get_entity_state(manager, "organization_seed_grant", 12))
	var fact_id := "fact.treasury_funding." + organization
	var paid := append_payment(result, manager, organization, amount, fact_id, day * 24,
		int(snapshot.get_entity_state(manager, "treasury_reserve", 12)))
	result.add_fact({"fact_id": fact_id, "fact_type": "organization_treasury_funded" if paid else "organization_funding_unavailable",
		"actor_id": manager, "target_id": organization, "amount": amount if paid else 0,
		"source_fact_ids": [source], "day": day,
		"summary": "聚落实际拨付 %d 枚铜币给新组织。" % amount if paid else "聚落金库不足，新组织没有获得启动拨款。"})


static func append_retirement(result: Variant, snapshot: Variant, manager: String, organization: String, source: String, day: int) -> void:
	if int(snapshot.get_entity_state(manager, "economic_contract_version", 0)) != 1:
		return
	var count := 0
	for item: Dictionary in snapshot.get_items():
		if item.get("holder", {}) != {"kind": "entity", "id": organization}:
			continue
		result.add_item_change({"operation": "transfer", "item_instance_id": item["item_instance_id"],
			"new_holder": {"kind": "entity", "id": manager}, "expected_holder": {"kind": "entity", "id": organization},
			"source_fact_ids": [source], "updated_tick": day * 24})
		count += 1
	for exchange: Dictionary in snapshot.get_open_exchanges():
		if organization in [str(exchange.get("party_a", "")), str(exchange.get("party_b", ""))]:
			result.add_exchange_update({"exchange_id": exchange["exchange_id"], "status": "failed",
				"reason": "organization_retired", "source_fact_ids": [source]})
	result.add_fact({"fact_id": "fact.treasury_reclaimed." + organization, "fact_type": "organization_assets_reclaimed",
		"actor_id": organization, "target_id": manager, "item_stack_count": count,
		"source_fact_ids": [source], "day": day, "summary": "组织退场，%d 组实际持有物归还聚落，未结承诺终止。" % count})
