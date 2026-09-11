extends RefCounted
class_name V5ResidentWorkOpportunities

const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Market = preload("res://scripts/sim/economy/market_service.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Access = preload("res://scripts/sim/resource/resource_access.gd")


static func assigned_profile(actor: Dictionary, profiles: Array) -> Dictionary:
	for profile: Dictionary in profiles:
		if profile.get("occupation_id") == actor.states.get("occupation_id") and profile.get("settlement_id") == actor.states.get("settlement_id"):
			return profile
	return {}


static func need(snapshot: Variant, actor: Dictionary, profiles: Array) -> Dictionary:
	var profile := assigned_profile(actor, profiles)
	if not Recipe.enabled(profile):
		return {}
	var items: Array = snapshot.get_items_for_holder(str(actor.id))
	var depot: Dictionary = snapshot.get_entity(Storage.depot_id(str(actor.id)))
	if not depot.is_empty() and actor.states.get("location_id") == depot.get("stock_location_id") and actor.states.get("daily_route_id", "") == "":
		items.append_array(snapshot.get_items_for_holder(str(depot.id)))
	var reserved := {}
	for collection: String in ["item_inputs", "tools"]:
		for spec: Dictionary in profile.work_recipe.get(collection, []):
			var required := int(spec.get("quantity", 1))
			var sources: Array = []
			for item: Dictionary in items:
				if not Recipe.matches(item, spec.query):
					continue
				Recipe._add_item_sources(sources, item)
				if collection == "tools" and int(item.get("condition", {}).get("durability", 0)) < int(spec.wear):
					continue
				var count := mini(required, maxi(int(item.quantity) - int(reserved.get(item.item_instance_id, 0)), 0))
				reserved[item.item_instance_id] = int(reserved.get(item.item_instance_id, 0)) + count
				required -= count
			if required > 0:
				return {"query": spec.query, "quantity": required, "minimum_durability": int(spec.get("wear", 0)),
					"source_fact_ids": sources, "recipe_id": profile.work_recipe.recipe_id}
	return {}


static func repair_profiles(snapshot: Variant, actor: Dictionary, config: Dictionary, tick: Dictionary = {}) -> Array:
	var rows: Array = []
	for profile: Dictionary in config.get("maintenance_profiles", []):
		if profile.get("settlement_id") != actor.states.get("settlement_id"):
			continue
		var failed := false
		for fact: Dictionary in snapshot.get_facts_by_actor(str(actor.id)) if not tick.is_empty() else []:
			if fact.get("fact_type") == "npc_livelihood_blocked_resource" and fact.get("work_kind") == "maintenance" \
					and fact.get("location_id") == profile.workplace_id and _hour(tick) - _hour(fact) < 6:
				failed = true
		if failed:
			continue
		for item: Dictionary in snapshot.get_items_for_holder(str(actor.id)):
			if Recipe.repairable(item, profile.work_recipe.repairs[0], snapshot):
				rows.append(profile)
				break
	return rows


static func active_repair(snapshot: Variant, actor: Dictionary, config: Dictionary) -> Dictionary:
	if actor.states.get("daily_activity") != "working" or actor.states.get("daily_route_id", "") != "":
		return {}
	for profile: Dictionary in repair_profiles(snapshot, actor, config):
		if actor.states.get("daily_intent_id") == "repair:" + str(profile.work_recipe.recipe_id) \
				and profile.workplace_id == actor.states.get("location_id"):
			return profile
	return {}


static func supply_sites(snapshot: Variant, actor: Dictionary, profiles: Array, demand: Dictionary,
		network: Dictionary, registry: Variant, tick: Dictionary) -> Array:
	var settlements: Array = [str(actor.states.get("settlement_id", ""))]
	for edge: Dictionary in network.get("links", []):
		for ends: Array in [[edge.get("settlement_a_id", ""), edge.get("settlement_b_id", "")], [edge.get("settlement_b_id", ""), edge.get("settlement_a_id", "")]]:
			if ends[0] == actor.states.get("settlement_id") and ends[1] not in settlements:
				settlements.append(ends[1])
	var sites: Array = []
	for profile: Dictionary in profiles:
		if profile.get("settlement_id") not in settlements:
			continue
		for output: Dictionary in profile.get("products", []):
			if Recipe.matches(registry.get_definition("item", str(output.item_def_id)), demand.query):
				var site := str(profile.workplace_id)
				if site not in sites and not recently_failed(snapshot, str(actor.id), site, demand, tick):
					sites.append(site)
	return sites


static func recently_failed(snapshot: Variant, actor: String, site: String, demand: Dictionary, tick: Dictionary) -> bool:
	for fact: Dictionary in snapshot.get_facts_by_actor(actor):
		if fact.get("fact_type") == "work_supply_unmet" and fact.get("location_id") == site \
				and fact.get("query") == demand.query and _hour(tick) - int(fact.absolute_hour) < 6:
			return true
	return false


static func knows_work_blocked(snapshot: Variant, actor: Dictionary, profile: Dictionary, tick: Dictionary) -> bool:
	if not need(snapshot, actor, [profile]).is_empty():
		return true
	var site := str(profile.get("workplace_id", ""))
	if actor.states.get("location_id") == site and actor.states.get("daily_route_id", "") == "":
		for input: Dictionary in profile.get("resource_inputs", []):
			var stock: Dictionary = snapshot.get_resource_stock(str(input.stock_id))
			if float(stock.get("current", 0)) < float(input.amount_per_cycle) \
					or Access.denial(snapshot, stock, str(actor.id), "livelihood_production", float(input.amount_per_cycle), int(tick.get("day", 0))) != "":
				return true
	for fact: Dictionary in snapshot.get_facts_by_actor(str(actor.id)):
		if fact.get("fact_type") in ["npc_livelihood_blocked_resource", "npc_wage_work_declined"] \
				and fact.get("work_kind") == "occupation" and fact.get("location_id") == site and _hour(tick) - _hour(fact) < 6:
			return true
	return false


static func failure_sources(snapshot: Variant, actor: String, demand: Dictionary, tick: Dictionary) -> Array:
	var sources: Array = []
	for fact: Dictionary in snapshot.get_facts_by_actor(actor):
		if fact.get("fact_type") == "work_supply_unmet" and fact.get("query") == demand.query and _hour(tick) - _hour(fact) < 6:
			sources.append(str(fact.fact_id))
	return sources


static func reserved_for_work(snapshot: Variant, seller: Dictionary, profile: Dictionary, holder: String) -> Dictionary:
	var reserved := {}
	var items: Array = snapshot.get_items_for_holder(str(seller.id))
	items.append_array(snapshot.get_items_for_holder(holder))
	# Personal equipment is retained before reserving stock earmarked for sale.
	for collection: String in ["tools", "item_inputs"]:
		for spec: Dictionary in profile.get("work_recipe", {}).get(collection, []):
			var remaining := int(spec.get("quantity", 1))
			for item: Dictionary in items:
				if not Recipe.matches(item, spec.query) or (collection == "tools" and int(item.get("condition", {}).get("durability", 0)) < int(spec.wear)):
					continue
				var count := mini(remaining, maxi(int(item.quantity) - int(reserved.get(item.item_instance_id, 0)), 0))
				reserved[item.item_instance_id] = int(reserved.get(item.item_instance_id, 0)) + count
				remaining -= count
				if remaining == 0:
					break
	return reserved


static func stock_offers(snapshot: Variant, seller: Dictionary, buyer: String, profiles: Array, stores: Dictionary) -> Array:
	var holder := Storage.stock_holder(snapshot, str(seller.id))
	if holder == "":
		return []
	var reserved := reserved_for_work(snapshot, seller, assigned_profile(seller, profiles), holder)
	var policy := {"market_policy_id": "work_supply." + str(seller.id), "seller_entity_id": seller.id,
		"stock_entity_id": holder, "location_id": seller.states.location_id, "sellable_item_tags_any": [],
		"accepted_currency_item_def_ids": [Food.CURRENCY], "fact_type": "work_supply_purchased", "exchange_type": "work_supply_purchase"}
	var rows: Array = []
	for offer: Dictionary in Market.new().build_stock_view(policy, stores, buyer).get("offers", []):
		var item: Dictionary = stores.item_store.get_item(str(offer.item_instance_id))
		var retained := int(reserved.get(item.item_instance_id, 0))
		if int(offer.available_quantity) <= retained:
			continue
		offer["surplus"] = int(offer.available_quantity) - retained
		offer["policy"] = policy.duplicate(true)
		offer.policy["minimum_retained_quantity"] = retained
		offer["seller_name"] = seller.display_name
		offer["item"] = item
		rows.append(offer)
	return rows


static func plan_purchase(snapshot: Variant, actor: Dictionary, profiles: Array, stores: Dictionary, tick: Dictionary) -> Dictionary:
	if actor.states.get("daily_intent_id") != "work_supply" or actor.states.get("daily_route_id", "") != "" \
			or actor.states.get("daily_activity") != "seeking_work" or not actor.states.get("alive", true):
		return {}
	var demand := need(snapshot, actor, profiles)
	var buyer := str(actor.id)
	var location := str(actor.states.get("location_id", ""))
	if demand.is_empty() or recently_failed(snapshot, buyer, location, demand, tick):
		return {}
	var money := Food.balance(stores.item_store.list_items_for_owner(buyer), buyer)
	var offers: Array = []
	var people: Array = snapshot.get_entities_by_type("person")
	people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	for seller: Dictionary in people:
		if seller.id == buyer or seller.states.get("location_id") != location or seller.states.get("daily_route_id", "") != "" \
				or not seller.states.get("alive", true) or seller.states.get("life_status", "alive") != "alive":
			continue
		for offer: Dictionary in stock_offers(snapshot, seller, buyer, profiles, stores):
			var item: Dictionary = offer.item
			if not Recipe.matches(item, demand.query) or int(item.get("condition", {}).get("durability", 0)) < int(demand.minimum_durability):
				continue
			if int(offer.surplus) < int(demand.quantity):
				continue
			offers.append(offer)
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.unit_price) < int(b.unit_price) if a.unit_price != b.unit_price else str(a.item_instance_id) < str(b.item_instance_id))
	for offer: Dictionary in offers:
		if int(offer.unit_price) * int(demand.quantity) > money:
			continue
		var sources: Array = demand.source_fact_ids.duplicate()
		Recipe._add_item_sources(sources, offer.item)
		var summary := "%s为恢复作业，向在场的%s支付 %d 枚铜币买下%d件%s；工具已由本人携带，仍要走回作业地。" % [actor.display_name,
			offer.seller_name, int(offer.unit_price) * int(demand.quantity), demand.quantity, offer.display_name]
		var plan := Market.new().plan_trade(offer.policy, {"buyer_entity_id": buyer, "item_instance_id": offer.item_instance_id,
			"quantity": demand.quantity, "quoted_unit_price": offer.unit_price, "maximum_total_price": money,
			"exchange_id": "exchange.work_supply.%s.%d" % [buyer, _hour(tick)], "purpose_id": demand.recipe_id,
			"source_fact_ids": sources, "trace_payment_sources": true, "summary": summary}, stores, {"elapsed_hours": _hour(tick), "day": tick.day})
		if not plan.success:
			return {"error": plan.error}
		plan.transaction.facts_added[0].merge({"hour": tick.hour, "goods_source_item_instance_id": offer.item_instance_id,
			"stock_entity_id": offer.policy.stock_entity_id, "query": demand.query})
		return {"transaction": plan.transaction, "event": plan.transaction.facts_added[0]}
	var result := Result.new()
	var fact := {"fact_id": "fact.work_supply_unmet.%s.%d" % [buyer, _hour(tick)], "fact_type": "work_supply_unmet",
		"actor_id": buyer, "location_id": location, "query": demand.query, "day": tick.day, "hour": tick.hour,
		"absolute_hour": _hour(tick), "available_coins": money, "source_fact_ids": demand.source_fact_ids,
		"reason": "no_local_surplus" if offers.is_empty() else "unaffordable",
		"summary": "%s未能补到作业用品：%s。记住这次扑空，暂时改做别的事。" % [actor.display_name,
			"在场的人没有可出售的合用余货" if offers.is_empty() else "现货报价超过了手里的钱"]}
	result.add_fact(fact)
	result.mark_resolved("work_supply_unmet")
	return {"transaction": result, "event": fact}


static func _hour(tick: Dictionary) -> int:
	return int(tick.get("day", 0)) * 24 + int(tick.get("hour", 0))
