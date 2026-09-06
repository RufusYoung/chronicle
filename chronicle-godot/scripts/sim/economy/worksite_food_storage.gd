extends RefCounted
class_name V5WorksiteFoodStorage

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const FOOD_IDS := ["item.fresh_fish_portion", "item.root_vegetable_portion"]
const PROFILE := {"version": 1, "personal_portions": 4, "maximum_stock": 24}


static func enabled(config: Dictionary) -> bool:
	return int(config.get("version", 0)) == 1


static func validate_config(config: Dictionary) -> String:
	if int(config.get("version", 0)) not in [0, 1]:
		return "unsupported_worksite_food_storage_version"
	if enabled(config):
		for key: String in ["personal_portions", "maximum_stock"]:
			var value: Variant = config.get(key)
			if not (value is int or value is float) or int(value) < 1 or float(value) != float(int(value)):
				return "invalid_worksite_food_storage_config"
	return ""


static func depot_id(owner: String) -> String:
	return "worksite_food_store." + owner


static func configure_fixture(fixture: Dictionary) -> void:
	if not enabled(fixture.get("resident_daily_life", {}).get("food_access", {}).get("worksite_storage", {})) \
			or fixture.has("worksite_food_storage_generated"):
		return
	var depots: Array = []
	for actor: Dictionary in fixture.get("entities", []):
		var states: Dictionary = actor.get("states", {})
		if "generated_resident" not in actor.get("tags", []):
			continue
		for profile: Dictionary in fixture.get("generated_livelihood_profiles", []):
			if profile.get("settlement_id") != states.get("settlement_id") \
					or profile.get("occupation_id") != states.get("occupation_id"):
				continue
			var food := false
			for product: Dictionary in profile.get("products", []):
				food = food or product.get("item_def_id") in FOOD_IDS
			if not food:
				continue
			depots.append({"id": depot_id(str(actor.id)), "type": "environment_detail", "role": "worksite_food_store",
				"display_name": str(actor.get("display_name", "居民")) + "的作业地存粮",
				"description": "这是有主人的现场存粮。取用和买卖要本人到场，货物不会跟着主人自动回家。",
				"tags": ["worksite_food_store"], "stock_custodian_id": str(actor.id),
				"stock_location_id": str(states.get("workplace_id", "")),
				"states": {"location_id": str(states.get("workplace_id", "")), "visible": true}})
	fixture.entities.append_array(depots)
	fixture["worksite_food_storage_generated"] = {"version": 1, "depot_ids": depots.map(func(row: Dictionary) -> String: return str(row.id))}


static func stock_holder(snapshot: Variant, actor: String) -> String:
	var depot: Dictionary = snapshot.get_entity(depot_id(actor))
	if depot.get("stock_custodian_id") != actor:
		return ""
	return str(depot.id)


static func quantity(items: Array, holder: String) -> int:
	var count := 0
	for item: Dictionary in items:
		if item.get("holder", {}) == {"kind": "entity", "id": holder} and item.get("item_def_id") in FOOD_IDS:
			count += int(item.quantity)
	return count


static func production_holder(snapshot: Variant, actor: String, item_def: String, config: Dictionary) -> String:
	if enabled(config) and item_def in FOOD_IDS:
		return stock_holder(snapshot, actor)
	return actor


static func has_capacity(snapshot: Variant, actor: String, profile: Dictionary, config: Dictionary) -> bool:
	if not enabled(config):
		return true
	var amount := 0
	for product: Dictionary in profile.get("products", []):
		if product.get("item_def_id") in FOOD_IDS:
			amount += int(product.get("quantity", 0))
	if amount == 0:
		return true
	var holder := stock_holder(snapshot, actor)
	if holder == "" or snapshot.get_entity_state(holder, "location_id", "") != snapshot.get_entity_state(actor, "workplace_id", ""):
		return false
	return quantity(snapshot.get_items_for_holder(holder), holder) + amount <= int(config.maximum_stock)


func plan_withdrawal(snapshot: Variant, actor: Dictionary, tick: Dictionary, config: Dictionary, stores: Dictionary, daily_config: Dictionary = {}, household_need: Dictionary = {}) -> Dictionary:
	if not enabled(config) or not bool(actor.get("states", {}).get("alive", true)) \
			or actor.get("states", {}).get("life_status", "alive") != "alive":
		return {}
	var owner := str(actor.id)
	var depot: Dictionary = snapshot.get_entity(depot_id(owner))
	if depot.is_empty() or depot.get("stock_custodian_id") != owner \
			or snapshot.get_entity_state(owner, "daily_route_id", "") != "" \
			or snapshot.get_entity_state(owner, "location_id", "") != depot.get("stock_location_id"):
		return {}
	for item: Dictionary in stores.item_store.list_items_for_owner(str(depot.id)):
		if int(daily_config.get("food_access", {}).get("hauling", {}).get("version", 0)) != 1:
			break
		if item.get("item_def_id") != "item.copper_coin":
			continue
		var returned := Result.new()
		var receipt := "fact.worksite_cash_reclaimed.%s.%d" % [owner, int(tick.day) * 24 + int(tick.hour)]
		var sources: Array = []
		for history: Dictionary in item.get("history", []):
			var source := str(history.get("fact_id", ""))
			if source != "" and source not in sources:
				sources.append(source)
		returned.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id,
			"expected_holder": item.holder, "new_holder": {"kind": "entity", "id": owner}, "source_fact_ids": [receipt]})
		var cash_fact := {"fact_id": receipt, "fact_type": "worksite_cash_reclaimed", "actor_id": owner,
			"stock_entity_id": depot.id, "location_id": depot.stock_location_id, "day": tick.day, "hour": tick.hour,
			"amount": item.quantity, "source_fact_ids": sources, "summary": "%s到场取回作业地保管的 %d 枚铜币。" % [actor.display_name, int(item.quantity)]}
		returned.add_fact(cash_fact)
		returned.mark_resolved("worksite_cash_reclaimed")
		return {"transaction": returned, "event": cash_fact}
	var on_shift := int(tick.hour) > int(daily_config.get("work_start_hour", 6)) and int(tick.hour) <= int(daily_config.get("work_end_hour", 18))
	var leaving := not on_shift or int(actor.states.get("fatigue", 0)) >= int(daily_config.get("rest_fatigue", 7)) \
		or int(actor.states.get("health", 100)) < int(daily_config.get("minimum_work_health", 30))
	# During work, take a meal as needed. Load the household bundle before leaving, not on every arrival.
	var target := int(config.personal_portions) if leaving else (1 if actor.states.get("hunger") in ["high", "extreme"] else 0)
	if int(daily_config.get("food_access", {}).get("household_budget", {}).get("version", 0)) == 1:
		# A forecast for the coming day is supplied after a real work block, not an emergency trip on every arrival.
		var finished_block := false
		for fact: Dictionary in snapshot.get_facts_by_actor(owner):
			if fact.get("fact_type") == "npc_livelihood_produced" and fact.get("actor_id") == owner and int(fact.get("day", 0)) == int(tick.day):
				finished_block = true
		if leaving or finished_block:
			target = maxi(target, int(household_need.get("target_portions", 0)))
	var needed := maxi(target - quantity(stores.item_store.list_items_for_owner(owner), owner), 0)
	if needed == 0:
		return {}
	var result := Result.new()
	var count := 0
	var fact_id := "fact.worksite_food_withdrawn.%s.%d" % [owner, int(tick.day) * 24 + int(tick.hour)]
	var sources: Array = []
	for item: Dictionary in stores.item_store.list_items_for_owner(str(depot.id)):
		if item.item_def_id not in FOOD_IDS or needed == 0:
			continue
		var take := mini(needed, int(item.quantity))
		var change := {"item_instance_id": str(item.item_instance_id), "new_holder": {"kind": "entity", "id": owner},
			"expected_holder": {"kind": "entity", "id": str(depot.id)}, "source_fact_ids": [fact_id],
			"updated_tick": int(tick.day) * 24 + int(tick.hour)}
		if take == int(item.quantity):
			change["operation"] = "transfer"
		else:
			change.merge({"operation": "split_stack", "quantity": take, "new_item_instance_id": "%s.%d" % [fact_id, count]})
		result.add_item_change(change)
		var source := str(item.get("provenance", {}).get("created_by_fact_id", ""))
		if source != "" and source not in sources:
			sources.append(source)
		needed -= take
		count += take
	if count == 0:
		return {}
	var fact := {"fact_id": fact_id, "fact_type": "worksite_food_withdrawn", "actor_id": owner,
		"location_id": depot.stock_location_id, "stock_entity_id": str(depot.id), "quantity": count,
		"day": int(tick.day), "hour": int(tick.hour), "source_fact_ids": sources,
		"summary": "%s从自己的作业地存粮中取出 %d 份随身口粮，其余仍留在原处。" % [actor.get("display_name", owner), count]}
	result.add_fact(fact)
	result.mark_resolved("worksite_food_withdrawal")
	return {"transaction": result, "event": fact}


static func validate_depot(depot: Dictionary, stores: Dictionary, locations: Dictionary) -> String:
	if "worksite_food_store" not in depot.get("tags", []):
		return ""
	var owner := str(depot.get("stock_custodian_id", ""))
	var location := str(depot.get("stock_location_id", ""))
	if not stores.entity_store.has_entity(owner) or stores.entity_store.get_entity(owner).get("type") != "person" \
			or str(depot.id) != depot_id(owner) or not locations.has(location) \
			or stores.state_store.get_state(str(depot.id), "location_id", "") != location:
		return "invalid_worksite_food_depot"
	return ""
