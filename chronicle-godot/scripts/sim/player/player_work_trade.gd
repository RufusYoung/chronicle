extends RefCounted

const Market = preload("res://scripts/sim/economy/market_service.gd")
const Work = preload("res://scripts/sim/economy/resident_work_opportunities.gd")
const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")


static func options(session: Variant, view: Variant, actor: Dictionary) -> Array:
	if not session.PlayerLife.Equipment.enabled(session):
		return []
	var rows: Array = []
	var worn: Array = view.get_equipment_loadout(str(actor.id)).get("slots", {}).values()
	for buyer: Dictionary in session.PlayerLife.Local.present(view, actor):
		if int(buyer.states.get("age_years", 0)) < 18:
			continue
		var demand := Work.need(view, buyer, session.npc_livelihood_profiles)
		if demand.is_empty():
			continue
		var policy := {"market_policy_id": "player_work_goods", "seller_entity_id": actor.id,
			"stock_entity_id": actor.id, "location_id": actor.states.location_id, "sellable_item_tags_any": [],
			"accepted_currency_item_def_ids": [Food.CURRENCY], "fact_type": "player_work_goods_sold", "exchange_type": "work_supply_purchase"}
		for offer: Dictionary in Market.new().build_stock_view(policy, session.stores, str(buyer.id)).get("offers", []):
			var item: Dictionary = session.stores.item_store.get_item(str(offer.item_instance_id))
			if item.item_instance_id in worn or not Recipe.matches(item, demand.query) \
					or int(item.get("condition", {}).get("durability", 0)) < int(demand.minimum_durability) \
					or int(item.quantity) < int(demand.quantity):
				continue
			var cost := int(offer.unit_price) * int(demand.quantity)
			var ready := Food.balance(view.get_items_for_holder(str(buyer.id)), str(buyer.id)) >= cost
			var reason := "对方有需求，但手里的铜币不足" if not ready else ""
			var summary := "%s需要%s，用%d铜币买%d件。你交出实物，不是领取系统奖金。" % [buyer.display_name, "防身装备" if str(demand.recipe_id).begins_with("equipment:") else "作业用品", cost, demand.quantity]
			var row: Dictionary = session.PlayerLife.row("sell_work:%s:%s" % [buyer.id, item.item_instance_id],
				"售%s给%s · %d铜币" % [item.display_name, buyer.display_name, cost], summary, reason)
			row.merge({"life_group": "trade", "recipient_id": buyer.id, "item_id": item.item_instance_id,
				"quantity": demand.quantity, "unit_price": offer.unit_price, "policy": policy, "demand": demand})
			rows.append(row)
	return rows


static func execute(session: Variant, selected: Dictionary) -> Dictionary:
	var sources: Array = selected.demand.source_fact_ids.duplicate()
	var summary := "你交出%d件%s，实际收到%d枚铜币。对方之后是否穿戴或用来开工，取决于其身体和处境。" % [
		selected.quantity, session.stores.item_store.get_item(str(selected.item_id)).display_name,
		int(selected.quantity) * int(selected.unit_price)]
	var plan := Market.new().plan_trade(selected.policy, {"buyer_entity_id": selected.recipient_id,
		"item_instance_id": selected.item_id, "quantity": selected.quantity, "quoted_unit_price": selected.unit_price,
		"exchange_id": "exchange.player_work_goods.%d" % session.elapsed_hours_since_start,
		"purpose_id": selected.demand.recipe_id, "source_fact_ids": sources, "trace_goods_sources": true,
		"trace_payment_sources": true, "summary": summary}, session.stores, session.get_time_summary())
	if not plan.get("success", false):
		return plan
	plan.transaction.facts_added[0]["contributor_id"] = session.context.actor_id
	if not session.writer.apply_result(plan.transaction, session.stores):
		return {"success": false, "error": plan.transaction.error_reason}
	return session.PlayerLife.feedback(session.advance_time(1, "player_work_goods_sale"), summary)
