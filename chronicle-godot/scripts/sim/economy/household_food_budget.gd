extends RefCounted
class_name V5HouseholdFoodBudget

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Family = preload("res://scripts/sim/npc/household_provisioning.gd")
const PROFILE := {"version": 1, "coverage_hours": 24, "maximum_load": 8, "capacity": 32,
	"personal_reserve": 2, "memory_hours": 24,
	"travel_hours": {"bold": 6, "cautious": 2, "reserved": 4, "sociable": 4, "steady": 4}}
const MEMORY := "household_pantry_observation"


static func enabled(config: Dictionary) -> bool:
	return int(config.get("version", 0)) == 1


static func validate_config(config: Dictionary) -> String:
	if int(config.get("version", 0)) not in [0, 1]:
		return "unsupported_household_food_budget_version"
	if enabled(config):
		for key: String in PROFILE:
			if key == "travel_hours":
				continue
			var value: Variant = config.get(key)
			if not (value is int or value is float) or float(value) != float(int(value)) or int(value) < 1:
				return "invalid_household_food_budget_config"
		if config.has("travel_hours"):
			if not config.travel_hours is Dictionary:
				return "invalid_household_budget_travel"
			for temperament: String in PROFILE.travel_hours:
				var value: Variant = config.travel_hours.get(temperament)
				if not (value is int or value is float) or float(value) != float(int(value)) or int(value) < 1:
					return "invalid_household_budget_travel"
	return ""


static func pantry_id(household: String) -> String:
	return "household_food_store." + household


static func configure_fixture(fixture: Dictionary) -> void:
	var config: Dictionary = fixture.get("resident_daily_life", {}).get("food_access", {}).get("household_budget", {})
	if not enabled(config) or fixture.has("household_food_storage_generated"):
		return
	var pantries: Array = []
	for household: Dictionary in fixture.entities:
		if household.get("type") != "household" or "generated_household" not in household.get("tags", []):
			continue
		var homes: Array = []
		for person: Dictionary in fixture.entities:
			if person.get("states", {}).get("household_id") == household.id:
				var home := str(person.states.get("home_location_id", ""))
				if home != "" and home not in homes:
					homes.append(home)
		if homes.size() != 1:
			continue
		pantries.append({"id": pantry_id(str(household.id)), "type": "environment_detail",
			"role": "household_food_store", "display_name": str(household.display_name) + "的共有粮柜",
			"description": "成员自愿存入的食物归家庭共有。只有在家中的家庭成员能取用，外人只能按托付送入。铜币与私人物品不共享。",
			"tags": ["household_food_store"], "household_id": household.id, "stock_location_id": homes[0],
			"states": {"location_id": homes[0], "visible": true}})
	fixture.entities.append_array(pantries)
	fixture["household_food_storage_generated"] = {"version": 1, "pantry_ids": pantries.map(func(row: Dictionary) -> String: return str(row.id))}


static func pantry(snapshot: Variant, actor: Dictionary) -> Dictionary:
	var id := pantry_id(str(actor.get("states", {}).get("household_id", "")))
	return snapshot.get_entity(id)


static func request(snapshot: Variant, actor: Dictionary, tick: Dictionary, config: Dictionary) -> Dictionary:
	if not enabled(config) or int(actor.get("states", {}).get("age_years", 0)) < 18:
		return {}
	var latest: Dictionary = {}
	for memory: Dictionary in snapshot.get_memories(str(actor.id)):
		if memory.get("memory_type") == MEMORY and (latest.is_empty() or int(memory.observed_hour) > int(latest.observed_hour)):
			latest = memory
	if latest.is_empty() or Family.absolute_hour(tick) - int(latest.observed_hour) >= int(config.memory_hours) \
			or latest.household_id != actor.states.get("household_id") or int(latest.missing_portions) <= 0:
		return {}
	var promised := 0
	for order: Dictionary in snapshot.exchanges:
		# The payer knows what was promised and its deadline, not a remote recipient's current stock.
		if order.get("party_a") == actor.id and order.get("pantry_id") == latest.pantry_id \
				and Family.absolute_hour(tick) < int(order.get("deadline_tick", 0)):
			promised += int(order.quantity)
	var need := maxi(int(latest.missing_portions) - promised, 0)
	if need == 0:
		return {}
	var targets: Array = []
	for recipient: String in latest.recipient_ids:
		targets.append({"target_id": recipient, "source_fact_id": latest.source_fact_id, "need_kind": "forecast"})
	return {"pantry_id": latest.pantry_id, "targets": targets, "home_location_id": latest.home_location_id,
		"source_fact_ids": [str(latest.source_fact_id)], "target_portions": mini(need, int(config.maximum_load)) + int(config.personal_reserve),
		"pantry_portions": mini(need, int(config.maximum_load)),
		"travel_hours": int(config.get("travel_hours", {}).get(str(actor.states.get("temperament", "steady")), 6)),
		"names": "家中接下来一天的口粮"}


func observe(snapshot: Variant, tick: Dictionary, config: Dictionary) -> Dictionary:
	if not enabled(config):
		return {"results": []}
	var result := Result.new()
	var items: Array = snapshot.get_items()
	for actor: Dictionary in snapshot.get_entities_by_type("person"):
		if not _member_at_home(snapshot, actor) or int(actor.states.get("age_years", 0)) < 18:
			continue
		var store := pantry(snapshot, actor)
		var required := 0
		var recipients: Array = []
		for other: Dictionary in snapshot.get_entities_by_type("person"):
			if not _member_at_home(snapshot, other) or other.states.get("household_id") != actor.states.get("household_id"):
				continue
			if other.id != actor.id:
				var support := int(snapshot.get_relation(str(actor.id), str(other.id), "trust", 0)) \
					+ int(snapshot.get_relation(str(actor.id), str(other.id), "familiarity", 0)) - int(snapshot.get_relation(str(actor.id), str(other.id), "resentment", 0))
				if support < 50:
					continue
			var meals := ceili(float(config.coverage_hours) / (2.0 * maxf(float(other.states.get("hunger_interval_hours", 6)), 1.0)))
			required += maxi(meals - Food.food_quantity(items, str(other.id)), 0)
			recipients.append(str(other.id))
		var stock := Food.food_quantity(items, str(store.id))
		var missing := maxi(required - stock, 0)
		var latest: Dictionary = {}
		for memory: Dictionary in snapshot.get_memories(str(actor.id)):
			if memory.get("memory_type") == MEMORY and (latest.is_empty() or int(memory.observed_hour) > int(latest.observed_hour)):
				latest = memory
		if not latest.is_empty() and latest.get("missing_portions") == missing and latest.get("recipient_ids") == recipients \
				and Family.absolute_hour(tick) - int(latest.observed_hour) < 6:
			continue
		var id := "fact.pantry_observed.%s.%d" % [actor.id, Family.absolute_hour(tick)]
		var summary := "%s在家查看共有粮柜并与在场家人核对口粮：柜中 %d 份，未来 %d 小时还缺 %d 份。" % [actor.display_name, stock, int(config.coverage_hours), missing]
		result.add_fact({"fact_id": id, "fact_type": "household_pantry_observed", "actor_id": actor.id,
			"location_id": store.stock_location_id, "pantry_id": store.id, "stock_portions": stock, "missing_portions": missing,
			"recipient_ids": recipients, "day": tick.day, "hour": tick.hour, "summary": summary})
		result.add_memory({"memory_id": "memory." + id, "memory_type": MEMORY, "owner_id": actor.id,
			"source_fact_id": id, "source_fact_ids": [id], "observed_hour": Family.absolute_hour(tick),
			"household_id": actor.states.household_id, "home_location_id": store.stock_location_id, "pantry_id": store.id,
			"missing_portions": missing, "recipient_ids": recipients, "summary": summary})
	if result.is_empty():
		return {"results": []}
	result.mark_resolved("household_pantry_observation")
	return {"results": [result]}


func plan_home_transfer(snapshot: Variant, actor: Dictionary, tick: Dictionary, config: Dictionary, stores: Dictionary) -> Dictionary:
	if not enabled(config) or not _member_at_home(snapshot, actor):
		return {}
	var store := pantry(snapshot, actor)
	var carried := Food.food_quantity(stores.item_store.list_items_for_owner(str(actor.id)), str(actor.id))
	var stock := Food.food_quantity(stores.item_store.list_items_for_owner(str(store.id)), str(store.id))
	var hungry: bool = actor.states.get("hunger") in ["high", "extreme"]
	var result := Result.new()
	var id := "fact.pantry_transfer.%s.%d" % [actor.id, Family.absolute_hour(tick)]
	var count := 0
	var urgent_family := false
	var first_in_need := true
	for other: Dictionary in snapshot.get_entities_by_type("person"):
		if other.id == actor.id or not _member_at_home(snapshot, other) or other.states.get("household_id") != actor.states.get("household_id") \
				or Food.food_quantity(stores.item_store.list_items_for_owner(str(other.id)), str(other.id)) > 0:
			continue
		if other.states.get("hunger") in ["high", "extreme"]:
			urgent_family = true
			if _meal_priority(snapshot, other) > _meal_priority(snapshot, actor):
				first_in_need = false
	var reserve := (1 if hungry else 0) if urgent_family else int(config.personal_reserve)
	var taking := carried < (1 if hungry else reserve)
	if taking:
		if first_in_need:
			count = mini((1 if hungry else reserve) - carried, stock)
	else:
		var willing := not request(snapshot, actor, tick, config).is_empty()
		if willing:
			count = mini(maxi(carried - reserve, 0), int(config.capacity) - stock)
	if count <= 0:
		return {}
	var from := str(store.id) if taking else str(actor.id)
	var to := str(actor.id) if taking else str(store.id)
	var sources := _append_food_transfer(result, stores.item_store.list_items_for_owner(from), count, to, id, Family.absolute_hour(tick))
	var fact := {"fact_id": id, "fact_type": "household_pantry_taken" if taking else "household_pantry_stored", "actor_id": actor.id,
		"location_id": store.stock_location_id, "pantry_id": store.id, "quantity": count, "day": tick.day, "hour": tick.hour, "source_fact_ids": sources,
		"summary": "%s%s %d 份口粮。共有粮食只在家中取用，个人铜币不共享。" % [actor.display_name, "从家中粮柜取出" if taking else "自愿向家中粮柜存入", count]}
	result.add_fact(fact)
	if taking and int(config.get("community_aid_feedback_version", 0)) == 1:
		for source: String in sources:
			var receipt: Dictionary = stores.fact_store.get_fact(source)
			if receipt.get("fact_type") != "food_hauling_stocked" or not receipt.has("community_request_id"):
				continue
			var remembered: Array = snapshot.get_memories(str(actor.id))
			if remembered.any(func(m: Dictionary) -> bool: return m.get("memory_type") == "community_aid_received" and m.get("delivery_fact_id") == source):
				continue
			var donor := str(receipt.payer_id)
			result.add_memory({"memory_id": "memory.aid.%s.%s" % [actor.id, source], "memory_type": "community_aid_received",
				"owner_id": actor.id, "target_id": donor, "delivery_fact_id": source,
				"source_fact_id": id, "source_fact_ids": [id, source], "summary": "%s取到了%s托人送来的口粮，记住了这次实际帮助。" % [actor.display_name, snapshot.get_entity(donor).display_name]})
			result.add_relationship_change({"source_id": actor.id, "target_id": donor, "axis": "trust", "delta": 4})
	result.mark_resolved("household_pantry_transfer")
	return {"transaction": result, "events": [fact]}


static func _append_food_transfer(result: Variant, items: Array, amount: int, to: String, fact: String, hour: int) -> Array:
	var moved := 0
	var sources: Array = []
	for item: Dictionary in items:
		if not Food.is_food(item) or moved >= amount:
			continue
		var count := mini(amount - moved, int(item.quantity))
		preload("res://scripts/sim/item/item_causal_sources.gd").append_to(sources, item)
		var source := str(item.get("provenance", {}).get("created_by_fact_id", ""))
		for history: Dictionary in item.get("history", []):
			if history.get("event_type") in ["transferred", "split_from"]:
				source = str(history.get("fact_id", source))
		if source != "" and source not in sources:
			sources.append(source)
		var change := {"item_instance_id": item.item_instance_id, "expected_holder": item.holder,
			"new_holder": {"kind": "entity", "id": to}, "source_fact_ids": [fact], "updated_tick": hour}
		if count == int(item.quantity):
			change["operation"] = "transfer"
		else:
			change.merge({"operation": "split_stack", "quantity": count, "new_item_instance_id": "%s.%d" % [fact, moved]})
		result.add_item_change(change)
		moved += count
	return sources


static func _member_at_home(snapshot: Variant, actor: Dictionary) -> bool:
	var state: Dictionary = actor.get("states", {})
	var store := pantry(snapshot, actor)
	return not store.is_empty() and bool(state.get("alive", true)) and state.get("life_status", "alive") == "alive" \
		and state.get("daily_route_id", "") == "" and state.get("location_id") == store.get("stock_location_id") \
		and state.get("home_location_id") == store.get("stock_location_id")


static func _meal_priority(snapshot: Variant, actor: Dictionary) -> int:
	var level := int({"extreme": 3, "high": 2}.get(str(actor.states.get("hunger", "none")), 0))
	var last_meal := 0
	for kind: String in ["npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"]:
		for fact: Dictionary in snapshot.get_facts_by_type(kind):
			if fact.get("target_id") == actor.id:
				last_meal = maxi(last_meal, Family.absolute_hour(fact))
	return level * 1000000 - last_meal


static func validate_references(stores: Dictionary, locations: Dictionary) -> String:
	for entity: Dictionary in stores.entity_store.entities.values():
		if "household_food_store" not in entity.get("tags", []):
			continue
		var household := str(entity.get("household_id", ""))
		var home := str(entity.get("stock_location_id", ""))
		if str(entity.id) != pantry_id(household) or not stores.entity_store.has_entity(household) \
				or stores.entity_store.get_entity(household).get("type") != "household" \
				or not locations.has(home) or "home" not in locations.get(home, {}).get("tags", []) \
				or stores.state_store.get_state(str(entity.id), "location_id", "") != home:
			return "invalid_household_pantry"
	for memory: Dictionary in stores.memory_store.memories:
		if memory.get("memory_type") != MEMORY:
			continue
		for key: String in ["missing_portions", "observed_hour"]:
			var value: Variant = memory.get(key)
			if not (value is int or value is float) or float(value) != float(int(value)) or int(value) < 0:
				return "invalid_household_budget_memory"
		var cabinet: Dictionary = stores.entity_store.get_entity(str(memory.get("pantry_id", "")))
		if cabinet.get("household_id", "") != memory.get("household_id") or cabinet.get("stock_location_id", "") != memory.get("home_location_id") \
				or not memory.get("recipient_ids") is Array or memory.recipient_ids.is_empty() \
				or memory.get("source_fact_ids") != [memory.get("source_fact_id")]:
			return "invalid_household_budget_memory"
		var seen := []
		for recipient: Variant in memory.recipient_ids:
			if not recipient is String or recipient in seen or stores.entity_store.get_entity(str(recipient)).get("type") != "person":
				return "invalid_household_budget_memory"
			seen.append(recipient)
		var fact: Dictionary = stores.fact_store.get_fact(str(memory.get("source_fact_id", "")))
		if fact.get("fact_type") != "household_pantry_observed" or fact.get("actor_id") != memory.get("owner_id") \
				or fact.get("missing_portions") != memory.get("missing_portions") or fact.get("pantry_id") != memory.get("pantry_id") \
				or fact.get("recipient_ids") != memory.get("recipient_ids") or Family.absolute_hour(fact) != int(memory.get("observed_hour", -1)):
			return "invalid_household_budget_memory"
	return ""
