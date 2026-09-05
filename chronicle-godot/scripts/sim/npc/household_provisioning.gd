extends RefCounted
class_name V5HouseholdProvisioning

const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const PROFILE := {"version": 1, "social_presence_version": 1, "memory_hours": 48, "minimum_support": 50,
	"maximum_recipients": 4, "self_reserve": 1,
	"travel_hours": {"cautious": 2, "steady": 4, "bold": 6, "sociable": 4, "reserved": 4}}
const MEMORY_TYPE := "household_food_observation"


static func enabled(config: Dictionary) -> bool:
	return int(config.get("version", 0)) == 1


static func absolute_hour(tick: Dictionary) -> int:
	return int(tick.get("day", 1)) * 24 + int(tick.get("hour", 0))


static func latest_observations(snapshot: Variant, owner: String) -> Dictionary:
	var latest := {}
	for memory: Dictionary in snapshot.get_memories(owner):
		if memory.get("memory_type") == MEMORY_TYPE:
			var target := str(memory.get("target_id", ""))
			if not latest.has(target) or int(memory.get("observed_hour", -1)) >= int(latest[target].get("observed_hour", -1)):
				latest[target] = memory
	return latest


static func validate_memory(memory: Dictionary, stores: Dictionary, locations: Dictionary) -> String:
	if memory.get("memory_type") != MEMORY_TYPE:
		return ""
	var source := str(memory.get("source_fact_id", ""))
	var fact: Dictionary = stores.fact_store.get_fact(source)
	if not stores.entity_store.has_entity(str(memory.get("target_id", ""))) \
			or not stores.entity_store.has_entity(str(memory.get("household_id", ""))) \
			or not locations.has(str(memory.get("home_location_id", ""))) \
			or not locations.has(str(memory.get("location_id", ""))):
		return "save_household_memory_reference_invalid"
	if source == "" or source not in memory.get("source_fact_ids", []) \
			or fact.get("actor_id") != memory.get("owner_id") or fact.get("target_id") != memory.get("target_id") \
			or fact.get("fact_type") not in ["household_food_observed", "household_food_delivered"]:
		return "save_household_memory_evidence_invalid"
	var hour: Variant = memory.get("observed_hour")
	if not (hour is int or hour is float) or float(hour) != float(int(hour)) or int(hour) < 0 \
			or int(hour) != absolute_hour(fact) or not memory.get("needs_food") is bool:
		return "save_household_memory_time_invalid"
	return ""


static func request(snapshot: Variant, actor: Dictionary, tick: Dictionary, config: Dictionary) -> Dictionary:
	if not enabled(config) or not _adult(actor):
		return {}
	var states: Dictionary = actor.get("states", {})
	var home := str(states.get("home_location_id", ""))
	var targets: Array = []
	# Away from home, only the actor's dated observations are consulted.
	for memory: Dictionary in latest_observations(snapshot, str(actor.id)).values():
		if not bool(memory.get("needs_food", false)) or memory.get("home_location_id") != home \
				or memory.get("household_id") != states.get("household_id") \
				or absolute_hour(tick) - int(memory.get("observed_hour", -100)) >= int(config.get("memory_hours", 48)):
			continue
		var target := str(memory.target_id)
		var support := int(snapshot.get_relation(str(actor.id), target, "trust", 0)) \
			+ int(snapshot.get_relation(str(actor.id), target, "familiarity", 0)) \
			- int(snapshot.get_relation(str(actor.id), target, "resentment", 0))
		if support < int(config.get("minimum_support", 50)):
			continue
		var row := memory.duplicate(true)
		row["support"] = support
		targets.append(row)
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.hunger != b.hunger:
			return a.hunger == "extreme"
		return int(a.support) > int(b.support) if a.support != b.support else str(a.target_id) < str(b.target_id))
	targets = targets.slice(0, int(config.get("maximum_recipients", 4)))
	if targets.is_empty():
		return {}
	var sources: Array = []
	var names: Array[String] = []
	for target: Dictionary in targets:
		sources.append(str(target.source_fact_id))
		names.append(str(snapshot.get_entity(str(target.target_id)).get("display_name", target.target_id)))
	var budget := int(config.get("travel_hours", PROFILE.travel_hours).get(str(states.get("temperament", "steady")), 4))
	if targets[0].hunger == "extreme":
		budget += 2
	return {"targets": targets, "home_location_id": home, "source_fact_ids": sources,
		"target_portions": targets.size() + int(config.get("self_reserve", 1)),
		"travel_hours": budget, "names": "、".join(names)}


func observe(snapshot: Variant, tick: Dictionary, config: Dictionary) -> Dictionary:
	if not enabled(config):
		return {"results": [], "events": []}
	var result := Result.new()
	var items: Array = snapshot.get_items()
	var people: Array = snapshot.get_entities_by_type("person")
	people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	for observer: Dictionary in people:
		if not _adult(observer) or not _present(observer):
			continue
		var states: Dictionary = observer.states
		var latest := latest_observations(snapshot, str(observer.id))
		for target: Dictionary in people:
			var other: Dictionary = target.get("states", {})
			if target.id == observer.id or states.get("household_id", "") == "" \
					or states.get("household_id") != other.get("household_id") \
					or states.get("location_id") != other.get("location_id") \
					or str(other.get("daily_route_id", "")) != "":
				continue
			# A co-present family member reports their own need and carried food.
			var hungry: bool = _present(target) and other.get("hunger", "none") in ["high", "extreme"] \
				and Food.food_quantity(items, str(target.id)) == 0
			var previous: Dictionary = latest.get(str(target.id), {})
			if previous.is_empty() and not hungry:
				continue
			if not previous.is_empty() and bool(previous.needs_food) == hungry \
					and (not hungry or (previous.hunger == other.get("hunger") \
					and absolute_hour(tick) - int(previous.observed_hour) < int(config.get("memory_hours", 48)))):
				continue
			var fact := _observation(result, observer, target, tick, hungry, "conversation")
			result.add_fact(fact)
	if result.is_empty():
		return {"results": [], "events": []}
	result.mark_resolved("household_food_observation")
	return {"results": [result], "events": []}


func plan_delivery(snapshot: Variant, actor: Dictionary, tick: Dictionary, config: Dictionary, stores: Dictionary) -> Dictionary:
	var intent := request(snapshot, actor, tick, config)
	if intent.is_empty() or not _present(actor):
		return {}
	var home := str(intent.home_location_id)
	if actor.states.get("location_id") != home:
		return {}
	var result := Result.new()
	var events: Array = []
	var items: Array = stores.item_store.list_items_for_owner(str(actor.id))
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.item_instance_id) < str(b.item_instance_id))
	var remaining := {}
	for item: Dictionary in items:
		remaining[str(item.item_instance_id)] = int(item.quantity)
	var reserve := 1 if actor.states.get("hunger", "none") in ["high", "extreme"] else 0
	var available := maxi(Food.food_quantity(items, str(actor.id)) - reserve, 0)
	for remembered: Dictionary in intent.targets:
		var target: Dictionary = snapshot.get_entity(str(remembered.target_id))
		if not _present(target) or target.states.get("location_id") != home \
				or target.states.get("household_id") != actor.states.get("household_id"):
			continue
		if target.states.get("hunger", "none") not in ["high", "extreme"] \
				or Food.food_quantity(stores.item_store.list_items_for_owner(str(target.id)), str(target.id)) > 0:
			continue
		if available <= 0:
			break
		for item: Dictionary in items:
			var item_id := str(item.item_instance_id)
			if not Food.is_food(item) or int(remaining[item_id]) <= 0:
				continue
			var fact_id := "fact.household_food_delivery.%s.%s.%d" % [actor.id, target.id, absolute_hour(tick)]
			var change := {"item_instance_id": item_id, "new_holder": {"kind": "entity", "id": str(target.id)},
				"updated_tick": absolute_hour(tick), "source_fact_ids": [fact_id]}
			var received := item_id
			if int(remaining[item_id]) == 1:
				change["operation"] = "transfer"
			else:
				received = "item_instance.household_food.%s.%s.%d" % [actor.id, target.id, absolute_hour(tick)]
				change.merge({"operation": "split_stack", "quantity": 1, "new_item_instance_id": received})
			var sources: Array = [str(remembered.source_fact_id)]
			var acquired := str(item.get("provenance", {}).get("created_by_fact_id", ""))
			for history: Dictionary in item.get("history", []):
				if history.get("event_type") in ["transferred", "split_from"]:
					acquired = str(history.get("fact_id", acquired))
			if acquired != "" and acquired not in sources:
				sources.append(acquired)
			var fact := {"fact_id": fact_id, "fact_type": "household_food_delivered", "actor_id": actor.id,
				"target_id": target.id, "location_id": home, "source_fact_ids": sources,
				"quantity": 1, "item_instance_id": received, "source_item_instance_id": item_id,
				"day": tick.get("day", 1), "hour": tick.get("hour", 0),
				"summary": "%s把带回的一份%s交给%s，自己手中的食物也少了一份。" % [
					actor.get("display_name", actor.id), item.get("display_name", "食物"), target.get("display_name", target.id)]}
			result.add_item_change(change)
			result.add_fact(fact)
			result.add_relationship_change({"source_id": target.id, "target_id": actor.id, "axis": "trust", "delta": 1})
			_observation(result, actor, target, tick, false, "delivery", fact_id)
			result.add_memory({"memory_id": "memory.received_family_food.%s" % fact_id,
				"owner_id": target.id, "target_id": actor.id, "memory_type": "received_family_food",
				"source_fact_id": fact_id, "source_fact_ids": [fact_id], "summary": fact.summary})
			events.append(fact)
			remaining[item_id] = int(remaining[item_id]) - 1
			available -= 1
			break
	if result.is_empty():
		return {}
	result.mark_resolved("household_food_delivery")
	return {"transaction": result, "events": events}


static func reservations(snapshot: Variant, tick: Dictionary, config: Dictionary) -> Dictionary:
	var amounts := {}
	if not enabled(config):
		return amounts
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var intent := request(snapshot, person, tick, config)
		if not intent.is_empty():
			amounts[str(person.id)] = int(intent.target_portions)
	return amounts


func _observation(result: Variant, observer: Dictionary, target: Dictionary, tick: Dictionary,
		needs: bool, method: String, source: String = "") -> Dictionary:
	var fact_id := source if source != "" else "fact.household_food_observed.%s.%s.%d" % [observer.id, target.id, absolute_hour(tick)]
	var summary := "%s当面得知%s%s。" % [observer.get("display_name", observer.id),
		target.get("display_name", target.id), "缺粮，记下带一份食物回家" if needs else "暂时不缺口粮，取消这次补给需求"]
	result.add_memory({"memory_id": "memory.household_food.%s.%s" % [fact_id, method],
		"owner_id": observer.id, "target_id": target.id, "memory_type": MEMORY_TYPE,
		"source_fact_id": fact_id, "source_fact_ids": [fact_id], "observed_hour": absolute_hour(tick), "needs_food": needs,
		"hunger": target.states.get("hunger", "none"), "location_id": observer.states.get("location_id", ""),
		"household_id": observer.states.get("household_id", ""),
		"home_location_id": observer.states.get("home_location_id", ""), "method": method, "summary": summary})
	return {"fact_id": fact_id, "fact_type": "household_food_observed", "actor_id": observer.id,
		"target_id": target.id, "location_id": observer.states.get("location_id", ""),
		"needs_food": needs, "day": tick.get("day", 1), "hour": tick.get("hour", 0), "summary": summary}


static func _present(actor: Dictionary) -> bool:
	var states: Dictionary = actor.get("states", {})
	return not actor.is_empty() and bool(states.get("alive", true)) and states.get("life_status", "alive") == "alive" \
		and str(states.get("daily_route_id", "")) == ""


static func _adult(actor: Dictionary) -> bool:
	var states: Dictionary = actor.get("states", {})
	return "generated_resident" in actor.get("tags", []) and bool(states.get("alive", true)) \
		and states.get("life_status", "alive") == "alive" and int(states.get("age_years", 0)) >= 18
