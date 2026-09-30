extends RefCounted
## World behavior. Requests and assistance exist without a player or a story node.

const Gear = preload("res://scripts/sim/equipment/resident_equipment.gd")
const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Market = preload("res://scripts/sim/economy/market_service.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")
const RULES := {"version": 1, "request_interval_hours": 6, "request_lifetime_hours": 24,
	"friend_trust": 30, "help_reserve_coins": 6, "help_coins": 4, "initial_history_hours": 2}


static func rules(version: int) -> Dictionary:
	var config := RULES.duplicate(true)
	config.version = version
	return config


static func present(person: Dictionary, location: String) -> bool:
	var states: Dictionary = person.get("states", {})
	return states.get("alive", true) and states.get("life_status", "alive") == "alive" \
		and states.get("daily_route_id", "") == "" and states.get("location_id") == location


static func now(tick: Dictionary) -> int:
	return int(tick.get("day", 0)) * 24 + int(tick.get("hour", 0))


static func latest_request(snapshot: Variant, actor: String) -> Dictionary:
	var rows: Array = snapshot.get_facts_by_actor(actor)
	for i: int in range(rows.size() - 1, -1, -1):
		if rows[i].get("fact_type") == "equipment_request":
			return rows[i]
	return {}


static func declaration(snapshot: Variant, person: Dictionary, tick: Dictionary, locations: Dictionary, force: bool = false) -> Dictionary:
	if not Gear.enabled(person) or not present(person, str(person.states.location_id)) \
		or person.states.get("danger_opponent_id", "") != "":
		return {}
	var demand := Gear.need(snapshot, person)
	if demand.is_empty():
		return {}
	var previous := latest_request(snapshot, str(person.id))
	if not force and not previous.is_empty() and previous.get("query") == demand.query \
		and now(tick) - int(previous.absolute_hour) < RULES.request_interval_hours:
		return {}
	var source: Dictionary = snapshot.get_fact(str(demand.source_fact_ids[0]))
	var danger_place := str(source.get("location_id", ""))
	var place_name := str(locations.get(danger_place, {}).get("display_name", "先前经过的地方"))
	var need_name := "护具" if "armor_outer" in demand.query.get("tags_all", []) else "武器"
	var listeners: Array = snapshot.get_entities_by_type("person").filter(func(p: Dictionary) -> bool:
		return p.id != person.id and present(p, str(person.states.location_id))).map(func(p: Dictionary) -> String: return str(p.id))
	if snapshot.player.get("id", "") != person.id and snapshot.player.get("location_id") == person.states.location_id \
		and snapshot.player.get("daily_route_id", "") == "" and snapshot.player.id not in listeners:
		listeners.append(snapshot.player.id)
	return {"fact_id": "fact.equipment_request.%s.%d" % [person.id, now(tick)], "fact_type": "equipment_request",
		"actor_id": person.id, "location_id": person.states.location_id, "day": tick.day, "hour": tick.hour,
		"absolute_hour": now(tick), "expires_hour": now(tick) + RULES.request_lifetime_hours,
		"query": demand.query, "minimum_durability": demand.minimum_durability, "need_name": need_name,
		"goal": "找一件能用的" + need_name, "danger_location_id": danger_place, "heard_by_ids": listeners,
		"source_fact_ids": demand.source_fact_ids,
		"summary": "%s说：我之前在%s遇过危险，想找一件能用的%s，再考虑接下来的去向。" % [person.display_name, place_name, need_name]}


static func append_trace(result: Variant, fact: Dictionary, text: String, lifetime: int = 24) -> void:
	result.add_trace({"trace_id": "trace." + str(fact.fact_id), "trace_type": "equipment_activity",
		"actor_id": fact.actor_id, "location_id": fact.location_id, "visible": true, "inspectable": true,
		"source_fact_id": fact.fact_id, "source_fact_type": fact.fact_type, "source_fact_ids": [fact.fact_id],
		"created_hour": now(fact), "expires_hour": now(fact) + lifetime, "display_name": "在此留下的消息",
		"description": text, "summary": text, "tags": ["equipment", "public_notice"]})


static func requests(snapshot: Variant, tick: Dictionary, locations: Dictionary) -> Variant:
	var result := Result.new()
	if int(tick.hour) < 7 or int(tick.hour) >= 21:
		return result
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var fact := declaration(snapshot, person, tick, locations)
		if fact.is_empty():
			continue
		result.add_fact(fact)
		append_trace(result, fact, "第%d天 %02d时，%s在这里留下口信：想找一件能用的%s。本人可能已经离开。" % [tick.day, tick.hour, person.display_name, fact.need_name])
	result.mark_resolved("equipment_requests")
	return result


static func spare_items(snapshot: Variant, donor: Dictionary, query: Dictionary) -> Array:
	var equipped: Array = snapshot.get_equipment_loadout(str(donor.id)).get("slots", {}).values()
	return snapshot.get_items_for_holder(str(donor.id)).filter(func(item: Dictionary) -> bool:
		return Recipe.matches(item, query) and item.item_instance_id not in equipped \
			and int(item.get("condition", {}).get("durability", 0)) >= 4 and int(item.quantity) > 0)


static func gift(snapshot: Variant, donor: String, recipient: String, item: Dictionary, fact_id: String, tick: Dictionary, sources: Array) -> Variant:
	var result := Result.new()
	var target: Dictionary = snapshot.get_entity(recipient)
	var giver: Dictionary = snapshot.get_entity(donor)
	var fact := {"fact_id": fact_id, "fact_type": "equipment_given", "actor_id": donor, "target_id": recipient,
		"location_id": target.states.location_id, "day": tick.day, "hour": tick.hour,
		"item_instance_id": item.item_instance_id, "quantity": 1, "source_fact_ids": sources,
		"summary": "%s把一件%s交给%s；物品已经换了主人，如何使用由对方决定。" % [giver.get("display_name", "旅人"), item.display_name, target.display_name]}
	Recipe._add_item_sources(fact.source_fact_ids, item)
	result.add_fact(fact)
	Market.new()._add_stack_transfer(result, item, 1, recipient, "equipment", fact_id, fact_id, now(tick))
	result.item_changes.back()["expected_holder"] = item.holder
	result.add_relationship_change({"source_id": recipient, "target_id": donor, "axis": "trust", "delta": 2})
	result.add_memory({"memory_id": "memory." + fact_id, "owner_id": recipient, "memory_type": "equipment_help",
		"source_fact_id": fact_id, "source_fact_ids": [fact_id], "actor_id": donor, "summary": fact.summary})
	append_trace(result, fact, fact.summary)
	result.mark_resolved("equipment_given")
	return result


static func assistance(snapshot: Variant, donor: Dictionary, tick: Dictionary) -> Variant:
	var empty := Result.new()
	if not Gear.enabled(donor) or donor.states.get("daily_activity") not in ["home", "socializing", "seeking_work"] \
		or donor.states.get("hunger") in ["high", "extreme"] or donor.states.get("danger_opponent_id", "") != "" \
		or not present(donor, str(donor.states.location_id)):
		return empty
	for fact: Dictionary in snapshot.get_facts_by_actor(str(donor.id)):
		if fact.get("fact_type") in ["equipment_given", "equipment_funded"] and now(tick) - now(fact) < 6:
			return empty
	for recipient: Dictionary in snapshot.get_entities_by_type("person"):
		if recipient.id == donor.id or not present(recipient, str(donor.states.location_id)) \
			or snapshot.get_relation(str(donor.id), str(recipient.id), "trust", 0) < RULES.friend_trust:
			continue
		var request := latest_request(snapshot, str(recipient.id))
		if request.is_empty() or donor.id not in request.heard_by_ids or now(tick) >= int(request.expires_hour):
			continue
		var need := Gear.need(snapshot, recipient)
		if need.is_empty() or need.query != request.query:
			continue
		var spares := spare_items(snapshot, donor, need.query)
		if not spares.is_empty():
			return gift(snapshot, str(donor.id), str(recipient.id), spares[0],
				"fact.equipment_aid.%s.%d" % [donor.id, now(tick)], tick, [request.fact_id])
		# Money help follows an actual failed quote, not omniscient inspection of a friend's purse.
		for failure: Dictionary in snapshot.get_facts_by_actor(str(recipient.id)):
			if failure.get("fact_type") != "work_supply_unmet" or failure.get("reason") != "unaffordable" \
				or failure.get("query") != need.query \
				or donor.id not in failure.get("heard_by_ids", []) or now(tick) - now(failure) >= 6:
				continue
			var id := "fact.equipment_funded.%s.%d" % [donor.id, now(tick)]
			var support := Result.new()
			if not Treasury.new(snapshot).append_payment(support, str(donor.id), str(recipient.id), RULES.help_coins, id, now(tick), RULES.help_reserve_coins):
				continue
			var funding := {"fact_id": id, "fact_type": "equipment_funded", "actor_id": donor.id, "target_id": recipient.id,
				"location_id": donor.states.location_id, "day": tick.day, "hour": tick.hour, "amount": RULES.help_coins,
				"source_fact_ids": [request.fact_id, failure.fact_id], "summary": "%s拿出%d枚自己的铜币资助%s；不是借款，也没有约定用途。" % [donor.display_name, RULES.help_coins, recipient.display_name]}
			support.add_fact(funding)
			support.add_relationship_change({"source_id": recipient.id, "target_id": donor.id, "axis": "trust", "delta": 1})
			append_trace(support, funding, funding.summary)
			support.mark_resolved("equipment_funded")
			return support
	return empty


static func witnessed_changes(snapshot: Variant, facts: Array, tick: Dictionary, locations: Dictionary) -> Variant:
	var result := Result.new()
	var seen := {}
	for fact: Dictionary in facts:
		var kind := str(fact.get("fact_type", ""))
		if now(fact) != now(tick) or seen.has(fact.fact_id):
			continue
		seen[fact.fact_id] = true
		var actor: Dictionary = snapshot.get_entity(str(fact.get("actor_id", "")))
		if actor.is_empty() or not actor.states.get("equipment_autonomy_version", 0) == 1:
			continue
		var text := ""
		if kind == "resident_equipped":
			text = "%s在这里换上了%s。" % [actor.display_name, snapshot.get_item(str(fact.item_instance_id)).get("display_name", "装备")]
		elif kind == "npc_work_maintained":
			text = "%s在这里完成了一次实物修补。" % actor.display_name
		elif kind == "work_supply_unmet" and fact.get("query", {}).get("tags_all", []).any(func(tag: String) -> bool: return tag in ["armor_outer", "melee_weapon"]):
			text = "%s在这里问过装备，%s。" % [actor.display_name, "价钱超出了当时能付的范围" if fact.get("reason") == "unaffordable" else "没找到在场且有余货的卖方"]
		elif kind == "resident_activity_changed" and fact.get("activity") == "traveling" and fact.has("to_location_id") and not latest_request(snapshot, str(actor.id)).is_empty():
			# A departure is visible at its origin. Its private final goal and scoring are never exposed.
			if snapshot.player.get("location_id") != fact.location_id or snapshot.player.get("daily_route_id", "") != "":
				continue
			text = "你看见%s沿路往%s去了。" % [actor.display_name, locations.get(str(fact.get("to_location_id", "")), {}).get("display_name", "前方")]
		if text == "":
			continue
		append_trace(result, fact, "第%d天 %02d时，%s" % [tick.day, tick.hour, text])
		if kind == "resident_activity_changed":
			result.traces_added.back().merge({"departure_to": fact.to_location_id, "witness_id": snapshot.player.id})
	result.mark_resolved("situation_traces")
	return result
