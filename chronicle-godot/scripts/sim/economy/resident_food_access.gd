extends RefCounted
class_name V5ResidentFoodAccess

const Market = preload("res://scripts/sim/economy/market_service.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const PROFILE := {"version": 1, "shopping_start_hour": 12, "shopping_end_hour": 17,
	"target_portions": 2, "seller_retained_portions": 2, "retry_hours": 6,
	"adjacent_supply_known": true,
	"minimum_independent_shopping_age": 18,
	"production_batch": {"version": 1, "work_hours": 4, "portions": 12}}
const CURRENCY := "item.copper_coin"
const HARVEST_FOOD_IDS := ["item.fresh_fish_portion", "item.root_vegetable_portion"]


static func enabled(config: Dictionary) -> bool:
	return int(config.get("version", 0)) == 1


static func configure_fixture(fixture: Dictionary) -> void:
	var config: Dictionary = fixture.get("resident_daily_life", {}).get("food_access", {})
	var batch: Dictionary = config.get("production_batch", {})
	if not enabled(config) or not enabled(batch) or fixture.has("food_production_generation_result"):
		return
	var configured: Array = []
	for profile: Dictionary in fixture.get("generated_livelihood_profiles", []):
		if not is_food_producer(profile):
			continue
		profile["work_interval_hours"] = maxi(int(batch.get("work_hours", 4)), 1)
		for product: Dictionary in profile.get("products", []):
			if str(product.get("item_def_id", "")) in HARVEST_FOOD_IDS:
				product["quantity"] = maxi(int(batch.get("portions", 12)), 1)
		configured.append(str(profile.get("settlement_id", "")) + ":" + str(profile.occupation_id))
	fixture["food_production_generation_result"] = {"version": 1, "profiles": configured,
		"work_hours": batch.get("work_hours"), "portions": batch.get("portions"),
		"scope": "One existing resource harvest batch becomes edible meal portions after actual on-site labor; no initial food or money added."}


static func food_quantity(items: Array, owner: String) -> int:
	var quantity := 0
	for item: Dictionary in items:
		if item.get("holder", {}) == {"kind": "entity", "id": owner} and is_food(item):
			quantity += int(item.get("quantity", 0))
	return quantity


static func is_food(item: Dictionary) -> bool:
	return "food" in item.get("tags", []) and "consume" in item.get("capabilities", [])


static func balance(items: Array, owner: String) -> int:
	var value := 0
	for item: Dictionary in items:
		if item.get("holder", {}) == {"kind": "entity", "id": owner} and item.get("item_def_id") == CURRENCY:
			value += int(item.get("quantity", 0))
	return value


static func needs_food(actor: Dictionary, items: Array) -> bool:
	var states: Dictionary = actor.get("states", {})
	return "generated_resident" in actor.get("tags", []) and bool(states.get("alive", true)) \
		and str(states.get("life_status", "alive")) == "alive" \
		and str(states.get("hunger", "none")) in ["high", "extreme"] \
		and food_quantity(items, str(actor.id)) == 0


static func known_supply_locations(snapshot: Variant, actor: Dictionary, profiles: Array, network: Dictionary = {}, config: Dictionary = {}) -> Array:
	# A resident knows local occupations, not remote inventories or live offers.
	var sites: Array = []
	var neighboring_sites: Array = []
	var settlement := str(actor.get("states", {}).get("settlement_id", ""))
	var neighbors: Array = []
	if bool(config.get("adjacent_supply_known", false)):
		for link: Dictionary in network.get("links", []):
			var a := str(link.get("settlement_a_id", ""))
			var b := str(link.get("settlement_b_id", ""))
			if a == settlement:
				neighbors.append(b)
			elif b == settlement:
				neighbors.append(a)
	for profile: Dictionary in profiles:
		var owner := str(profile.get("settlement_id", ""))
		if owner != settlement and owner not in neighbors:
			continue
		if not is_food_producer(profile):
			continue
		var workplace := str(profile.get("workplace_id", ""))
		var occupation := str(profile.get("occupation_id", ""))
		for person: Dictionary in snapshot.get_entities_by_type("person"):
			var states: Dictionary = person.get("states", {})
			if str(states.get("workplace_id", "")) == workplace and str(states.get("occupation_id", "")) == occupation \
					and bool(states.get("alive", true)):
				var collection := sites if owner == settlement else neighboring_sites
				if workplace not in collection:
					collection.append(workplace)
	sites.sort()
	neighboring_sites.sort()
	sites.append_array(neighboring_sites)
	return sites


static func known_unaffordable(snapshot: Variant, actor: String, location: String, money: int, tick: Dictionary, config: Dictionary) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if fact.get("fact_type") == "resident_food_purchase_unmet" and fact.get("reason") == "unaffordable" \
				and fact.get("actor_id") == actor and fact.get("location_id") == location \
				and _hour(tick) - int(fact.get("absolute_hour", -100)) < int(config.get("retry_hours", 6)) \
				and money < int(fact.get("unit_price", 0)):
			return true
	return false


static func is_food_producer(profile: Dictionary) -> bool:
	for product: Dictionary in profile.get("products", []):
		if str(product.get("item_def_id", "")) in HARVEST_FOOD_IDS:
			return true
	return false


static func recently_failed(snapshot: Variant, actor: String, location: String, tick: Dictionary, config: Dictionary) -> bool:
	var now := _hour(tick)
	for fact: Dictionary in snapshot.get_facts():
		if fact.get("fact_type") == "resident_food_purchase_unmet" and fact.get("actor_id") == actor and fact.get("location_id") == location \
				and now - int(fact.get("absolute_hour", -100)) < int(config.get("retry_hours", 6)):
			return true
	return false


func plan_purchase(snapshot: Variant, actor: Dictionary, tick: Dictionary,
		config: Dictionary, locations: Dictionary, stores: Dictionary) -> Dictionary:
	if not enabled(config):
		return {}
	var buyer := str(actor.id)
	var states: Dictionary = actor.get("states", {})
	var location := str(states.get("location_id", ""))
	if "generated_resident" not in actor.get("tags", []) or str(states.get("hunger", "none")) not in ["high", "extreme"] \
			or str(states.get("daily_route_id", "")) != "" \
			or not locations.has(location) or "home" in locations[location].get("tags", []):
		return {}
	var items: Array = stores.item_store.list_items_for_owner(buyer)
	if not needs_food(actor, items):
		return {}
	var money := balance(items, buyer)
	var offers: Array = []
	for seller: Dictionary in snapshot.get_entities_by_type("person"):
		var id := str(seller.id)
		var seller_states: Dictionary = seller.get("states", {})
		if id == buyer or not snapshot.is_entity_active(id) or not bool(seller_states.get("alive", true)) \
				or seller_states.get("life_status", "alive") != "alive" \
				or str(seller_states.get("location_id", "")) != location \
				or str(seller_states.get("daily_route_id", "")) != "":
			continue
		var total_food := food_quantity(stores.item_store.list_items_for_owner(id), id)
		var retained := maxi(int(config.get("seller_retained_portions", 2)), 0)
		if total_food <= retained:
			continue
		var policy := {"market_policy_id": "resident_food." + id, "seller_entity_id": id,
			"location_id": location, "sellable_item_tags_any": ["food"],
			"accepted_currency_item_def_ids": [CURRENCY], "fact_type": "resident_food_purchased",
			"exchange_type": "resident_food_purchase"}
		for offer: Dictionary in Market.new().build_stock_view(policy, stores, buyer).get("offers", []):
			var item: Dictionary = stores.item_store.get_item(str(offer.get("item_instance_id", "")))
			if not is_food(item):
				continue
			offer["surplus"] = mini(int(offer.available_quantity), total_food - retained)
			offer["policy"] = policy
			offer["seller_name"] = str(seller.get("display_name", id))
			offers.append(offer)
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.unit_price) < int(b.unit_price) if int(a.unit_price) != int(b.unit_price) \
			else str(a.item_instance_id) < str(b.item_instance_id))
	if offers.is_empty():
		if str(states.get("daily_activity", "")) != "seeking_food" \
				or recently_failed(snapshot, buyer, location, tick, config):
			return {}
		return _unmet(actor, location, "no_local_surplus", tick)
	var offer: Dictionary = offers[0]
	var price := int(offer.unit_price)
	if money < price:
		if recently_failed(snapshot, buyer, location, tick, config):
			return {}
		return _unmet(actor, location, "unaffordable", tick, {"available_coins": money, "unit_price": price})
	var quantity := mini(int(config.get("target_portions", 2)), mini(int(offer.surplus), int(money / price)))
	var source_ids: Array = []
	for id: String in [str(states.get("daily_presence_fact_id", "")),
		str(snapshot.get_entity_state(str(offer.policy.seller_entity_id), "daily_presence_fact_id", ""))]:
		if id != "" and id not in source_ids:
			source_ids.append(id)
	var summary := "%s在%s向%s支付 %d 枚铜币，买下 %d 份%s；食物已实际交到手中。" % [
		actor.get("display_name", buyer), locations[location].get("display_name", location),
		offer.seller_name, price * quantity, quantity, offer.get("display_name", "食物")]
	var plan := Market.new().plan_trade(offer.policy, {"buyer_entity_id": buyer,
		"item_instance_id": offer.item_instance_id, "quantity": quantity, "quoted_unit_price": price,
		"maximum_total_price": money, "exchange_id": "exchange.resident_food.%s.%d" % [buyer, _hour(tick)],
		"purpose_id": "household_food", "purpose_target_id": buyer,
		"source_fact_ids": source_ids, "summary": summary}, stores,
		{"elapsed_hours": _hour(tick), "day": int(tick.get("day", 0))})
	if not bool(plan.get("success", false)):
		return {"error": str(plan.get("error", "food_trade_rejected"))}
	plan.transaction.facts_added.back()["hour"] = int(tick.get("hour", 0))
	plan.transaction.facts_added.back()["tick_basis"] = "calendar_day_times_24_plus_hour"
	plan.transaction.facts_added.back()["buyer_settlement_id"] = str(states.get("settlement_id", ""))
	plan.transaction.facts_added.back()["seller_settlement_id"] = str(snapshot.get_entity_state(str(offer.policy.seller_entity_id), "settlement_id", ""))
	plan.transaction.facts_added.back()["goods_source_item_instance_id"] = str(offer.item_instance_id)
	plan.transaction.facts_added.back()["received_item_instance_id"] = str(plan.transaction.item_changes[0].get("new_item_instance_id", offer.item_instance_id))
	plan.transaction.set_narrative_result({"title": "居民买到了食物", "summary": summary, "tone": "ordinary_life"})
	return {"transaction": plan.transaction, "event": {"event_type": "resident_food_purchased", "actor_id": buyer,
		"location_id": location, "quantity": quantity, "total_price": price * quantity, "fact_id": plan.fact_id}}


func _unmet(actor: Dictionary, location: String, reason: String, tick: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var result := Result.new()
	var fact := {"fact_id": "fact.resident_food_unmet.%s.%d" % [actor.id, _hour(tick)],
		"fact_type": "resident_food_purchase_unmet", "actor_id": actor.id, "location_id": location,
		"reason": reason, "day": int(tick.get("day", 0)), "hour": int(tick.get("hour", 0)), "absolute_hour": _hour(tick),
		"summary": "%s没买到食物：%s。" % [actor.get("display_name", actor.id),
			"在场的人没有可出售的余粮" if reason == "no_local_surplus" else "有货，但手里的铜币不够"]}
	fact.merge(extra, true)
	result.add_fact(fact)
	result.mark_resolved("resident_food_purchase_unmet")
	return {"transaction": result, "event": fact}


static func _hour(tick: Dictionary) -> int:
	# Match existing NPC livelihood item timestamps, not session elapsed duration.
	return int(tick.get("day", 1)) * 24 + int(tick.get("hour", 0))
