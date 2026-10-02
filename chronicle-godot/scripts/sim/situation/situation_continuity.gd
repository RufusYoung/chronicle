extends RefCounted
## Knowledge travels with witnesses. Projections never refresh a distant person's position.

const Intents = preload("res://scripts/sim/situation/equipment_intents.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const FOLLOWUP_TYPES := ["resident_equipped", "work_supply_purchased", "npc_work_maintained",
	"npc_livelihood_produced", "world_danger_round", "actor_rested_with_injury", "resident_food_purchased",
	"household_pantry_stored", "household_food_delivered", "npc_self_meal", "npc_household_shared_food"]


static func enabled(session: Variant) -> bool:
	return session.fixture_source_data.get("situation_rules", {}).get("version") == 2


static func sightings(snapshot: Variant, observer: String) -> Dictionary:
	var found := {}
	for memory: Dictionary in snapshot.get_memories(observer):
		if memory.get("memory_type") != "situation_sighting":
			continue
		var subject := str(memory.subject_id)
		if not found.has(subject) or int(memory.observed_hour) > int(found[subject].observed_hour):
			found[subject] = memory
	return found


static func observe(snapshot: Variant, tick: Dictionary, locations: Dictionary) -> Variant:
	var result := Result.new()
	var people: Array = snapshot.get_entities_by_type("person").duplicate()
	if not people.any(func(p: Dictionary) -> bool: return p.id == snapshot.player.id):
		people.append({"id": snapshot.player.id, "display_name": snapshot.player.get("display_name", "旅人"), "states": snapshot.player})
	for observer: Dictionary in people:
		var location := str(observer.states.get("location_id", ""))
		if not Intents.present(observer, location):
			continue
		var known := sightings(snapshot, str(observer.id))
		for subject: Dictionary in people:
			if subject.id == observer.id or not Intents.present(subject, location) or not subject.states.get("visible", true):
				continue
			var equipped: Array = []
			for item_id: Variant in snapshot.get_equipment_loadout(str(subject.id)).get("slots", {}).values():
				var item: Dictionary = snapshot.get_item(str(item_id))
				if item.get("holder", {}).get("id") == subject.id:
					equipped.append({"id": item_id, "name": item.display_name, "durability": item.condition.durability})
			var prior: Dictionary = known.get(str(subject.id), {})
			var injured: bool = int(subject.states.get("health", 100)) < 85
			if prior.get("location_id") == location and equipment_signature(prior.get("equipment", [])) == equipment_signature(equipped) and prior.get("injured") == injured \
				and Intents.now(tick) - int(prior.observed_hour) < 6:
				continue
			var id := "fact.sighting.%s.%s.%d" % [observer.id, subject.id, Intents.now(tick)]
			var fact := {"fact_id": id, "fact_type": "situation_sighting", "actor_id": observer.id,
				"subject_id": subject.id, "location_id": location, "day": tick.day, "hour": tick.hour,
				"equipment": equipped, "injured": injured, "source_fact_ids": [],
				"summary": "%s在%s见到%s%s。" % [observer.display_name, locations.get(location, {}).get("display_name", location), subject.display_name, "，身上带伤" if injured else ""]}
			result.add_fact(fact)
			result.add_memory({"memory_id": "memory." + id, "memory_type": "situation_sighting", "owner_id": observer.id,
				"subject_id": subject.id, "location_id": location, "observed_hour": Intents.now(tick), "equipment": equipped,
				"injured": injured, "source_fact_id": id, "summary": fact.summary})
	result.mark_resolved("situation_observations")
	return result


static func equipment_signature(items: Array) -> String:
	var parts: Array[String] = []
	for item: Dictionary in items:
		parts.append("%s:%d" % [item.id, int(item.durability)])
	parts.sort()
	return "|".join(parts)


static func contribution(snapshot: Variant, sources: Array, player: String, witness: String = "") -> String:
	var pending := sources.duplicate()
	var visited := {}
	for index: int in range(128):
		if pending.is_empty():
			break
		var id := str(pending.pop_front())
		if visited.has(id):
			continue
		visited[id] = true
		var fact: Dictionary = snapshot.get_fact(id)
		var defended: bool = fact.get("fact_type") == "world_danger_round" and int(fact.get("enemy_health_after", 0)) < int(fact.get("enemy_health_before", 0))
		if fact.get("contributor_id") == player or (fact.get("fact_type") == "equipment_purchased" and fact.get("target_id") == player) \
			or (fact.get("actor_id") == player and (fact.get("fact_type") in ["situation_fund", "equipment_given", "situation_advice", "npc_work_maintained", "npc_livelihood_produced"] \
			or defended)):
			if witness == "" or known_contribution(snapshot, fact, witness):
				return id
		pending.append_array(fact.get("source_fact_ids", []))
	return ""


static func known_contribution(snapshot: Variant, fact: Dictionary, witness: String) -> bool:
	for key: String in ["actor_id", "subject_id", "target_id", "recipient_id", "employer_id"]:
		if fact.get(key) == witness:
			return true
	for memory: Dictionary in snapshot.get_memories(witness):
		var observed: Dictionary = snapshot.get_fact(str(memory.get("source_fact_id", "")))
		if observed.get("fact_id") == fact.fact_id:
			return true
		if observed.get("actor_id") == witness and observed.get("fact_type") == "world_danger_cleared" \
			and fact.fact_id in observed.get("source_fact_ids", []):
			return true
	return false


static func followup(snapshot: Variant, person: String, player: String) -> Dictionary:
	var heard := {}
	var latest_heard := {}
	for fact: Dictionary in snapshot.get_facts_by_actor(player):
		if fact.get("fact_type") == "situation_heard_update":
			heard[str(fact.get("update_key", fact.get("update_id", "")))] = true
			if fact.get("update_kind", "consequence") == "consequence":
				latest_heard[str(fact.contribution_id)] = maxi(int(latest_heard.get(str(fact.contribution_id), -1)), int(fact.get("update_hour", -1)))
	var facts: Array = snapshot.get_facts_by_actor(person)
	for i: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[i]
		if fact.get("actor_id") != person or fact.get("fact_type") not in FOLLOWUP_TYPES or heard.has(fact.fact_id):
			continue
		var origin := contribution(snapshot, fact.get("source_fact_ids", []), player, person)
		var key := update_key(fact, origin)
		if origin != "" and not heard.has(key) and Intents.now(fact) > int(latest_heard.get(origin, -1)):
			return {"update_id": fact.fact_id, "contribution_id": origin, "summary": fact.summary,
				"day": fact.day, "hour": fact.get("hour", 0), "location_id": fact.get("location_id", ""), "kind": "consequence", "key": key,
				"connection": connection(snapshot.get_fact(origin), fact)}
	# Unresolved help is also a first-person answer, not a fabricated successful use.
	var contributions: Array = snapshot.get_facts_by_actor(player)
	for i: int in range(contributions.size() - 1, -1, -1):
		var gift: Dictionary = contributions[i]
		if gift.get("fact_type") != "situation_fund" or gift.get("subject_id") != person \
			or Intents.now(snapshot.world_time) <= Intents.now(gift) or latest_heard.has(str(gift.fact_id)):
			continue
		var need := Intents.Gear.need(snapshot, snapshot.get_entity(person))
		if need.is_empty():
			continue
		# A later weapon need must not reopen an earlier request for protection.
		var funded_query := {}
		for source_id: String in gift.get("source_fact_ids", []):
			var source_fact: Dictionary = snapshot.get_fact(source_id)
			if source_fact.has("query") and (source_fact.get("subject_id") == person or source_fact.get("actor_id") == person):
				funded_query = source_fact.query
				break
		if funded_query.is_empty() or funded_query != need.query:
			continue
		var status := "还没拿到能用的装备，这件事还没有办成"
		var source := str(gift.fact_id)
		for j: int in range(facts.size() - 1, -1, -1):
			var attempt: Dictionary = facts[j]
			if attempt.get("actor_id") == person and attempt.get("fact_type") == "work_supply_unmet" \
				and attempt.get("query") == need.query and Intents.now(attempt) > Intents.now(gift):
				status = "上次打听是在第%d天%02d时：%s" % [attempt.day, attempt.hour, attempt.summary]
				source = str(attempt.fact_id)
				break
		var attempt_fact: Dictionary = snapshot.get_fact(source)
		var key := str(gift.fact_id) + ":pending:" + str(attempt_fact.get("reason", "unresolved"))
		if heard.has(key):
			continue
		return {"update_id": source, "contribution_id": gift.fact_id, "summary": status,
			"day": snapshot.world_time.day, "hour": snapshot.world_time.hour,
			"location_id": snapshot.get_entity(person).states.location_id, "kind": "pending", "key": key}
	return {}


static func update_key(fact: Dictionary, origin: String) -> String:
	# Another identical work cycle is not another development in the relationship.
	return "%s:%s:%s:%s" % [origin, fact.fact_type, fact.get("approach_id", fact.get("recipe_id", "")), fact.get("outcome", "")]


static func connection(origin: Dictionary, outcome: Dictionary) -> String:
	if outcome.fact_type == "resident_equipped":
		return "你先前交出的装备已经派上用场；对方接下来去哪，仍由本人决定。"
	if origin.fact_type == "situation_fund" and outcome.fact_type in ["work_supply_purchased", "resident_food_purchased"]:
		return "收下资助后，对方买了这些东西；并没有承诺只买装备。"
	if origin.fact_type == "situation_advice":
		return "对方做决定时考虑了你的劝告，但还同时考虑了自己的需要；不能据此认定结果全因你而起。"
	return "这是对方后来的实际经历，与你交出的钱物有关；身体、装备和其他人的行动也在起作用。"


static func knowledge(session: Variant, snapshot: Variant) -> Array:
	var player := str(session.context.actor_id)
	var rows := {}
	for seen: Dictionary in sightings(snapshot, player).values():
		rows[str(seen.subject_id)] = {"subject_id": seen.subject_id, "location_id": seen.location_id,
			"observed_hour": seen.observed_hour, "source_fact_id": seen.source_fact_id, "kind": "seen",
			"text": seen.summary, "equipment": seen.equipment}
	for fact: Dictionary in snapshot.get_facts_by_actor(player):
		if fact.get("fact_type") == "situation_whereabouts":
			var subject := str(fact.subject_id)
			if not rows.has(subject) or int(fact.observed_hour) > int(rows[subject].observed_hour):
				rows[subject] = {"subject_id": subject, "location_id": fact.known_location_id,
					"observed_hour": fact.observed_hour, "source_fact_id": fact.fact_id, "kind": "heard", "text": fact.summary}
		elif fact.get("fact_type") in ["situation_inquiry", "situation_notice_read"]:
			# A stated intention is a lead, not confirmation that a journey happened.
			var observed := int(fact.get("observed_hour", Intents.now(fact)))
			var destination := str(fact.get("stated_destination_id", ""))
			var intention := "intention:" + str(fact.subject_id)
			if fact.fact_type == "situation_inquiry" and int(rows.get(intention, {}).get("observed_hour", -1)) <= observed:
				rows.erase(intention)
			if not rows.has(str(fact.subject_id)) or int(rows[str(fact.subject_id)].observed_hour) <= observed:
				rows[str(fact.subject_id)] = {"subject_id": fact.subject_id, "location_id": fact.location_id,
					"observed_hour": observed, "source_fact_id": fact.fact_id,
					"kind": "heard" if fact.fact_type == "situation_notice_read" else "seen", "text": fact.summary}
			if destination != "" and int(rows.get(intention, {}).get("observed_hour", -1)) <= observed:
				rows[intention] = {"subject_id": fact.subject_id, "location_id": destination,
					"observed_hour": observed, "source_fact_id": fact.fact_id, "kind": "intention", "text": fact.summary}
			var danger := str(fact.get("danger_location_id", ""))
			if danger != "" and int(rows.get("danger:" + danger, {}).get("observed_hour", -1)) <= observed:
				rows["danger:" + danger] = {"subject_id": fact.subject_id, "location_id": danger,
					"observed_hour": observed, "source_fact_id": fact.fact_id, "kind": "danger", "text": fact.summary}
	var list: Array = rows.values()
	for row: Dictionary in list:
		row["name"] = snapshot.get_entity(str(row.subject_id)).get("display_name", "认识的人")
		row["place"] = session.context.locations.get(str(row.location_id), {}).get("display_name", "曾见地点")
		row["age_hours"] = maxi(Intents.now(snapshot.world_time) - int(row.observed_hour), 0)
		row["stale"] = row.age_hours >= 6
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.observed_hour > b.observed_hour if a.observed_hour != b.observed_hour else str(a.source_fact_id) < str(b.source_fact_id))
	return list


static func direction(session: Variant, destination: String) -> Dictionary:
	var here := str(session.context.location_id)
	if destination == here:
		return {}
	var routes: Array = session._current_travel_routes(session.get_snapshot())
	var edge: Dictionary = session.PlayerLife.Daily.new()._next_edge(routes, here, destination)
	if not edge.is_empty():
		for route: Dictionary in session.get_travel_options():
			if route.route_id == edge.route_id and route.get("can_travel", false):
				return {"route": route, "total_hours": edge.total_hours}
	return {}


static func leads(session: Variant, snapshot: Variant) -> Array:
	var rows: Array = []
	var seen := {}
	var known_rows := knowledge(session, snapshot)
	# A stated destination supersedes the sighting made during that conversation.
	# A later sighting supersedes that old intention; neither tracks remote truth.
	known_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.observed_hour) != int(b.observed_hour):
			return int(a.observed_hour) > int(b.observed_hour)
		if (a.kind == "intention") != (b.kind == "intention"):
			return a.kind == "intention"
		return str(a.source_fact_id) < str(b.source_fact_id))
	for known: Dictionary in known_rows:
		var destination := str(known.location_id)
		var is_danger: bool = known.kind == "danger"
		var key := "danger:" + destination if is_danger else "person:" + str(known.subject_id)
		if seen.has(key):
			continue
		seen[key] = true
		var person: Dictionary = snapshot.get_entity(str(known.subject_id))
		if not is_danger and Intents.present(person, str(session.context.location_id)) and person.get("states", {}).get("visible", false):
			continue
		var path := direction(session, destination)
		if path.is_empty():
			continue
		var row := known.duplicate(true)
		row.merge({"route_id": path.route.route_id, "hours": path.route.hours, "total_hours": path.total_hours,
			"next_place": path.route.get("destination_name", session.context.locations.get(str(path.route.to_location_id), {}).get("display_name", "下一站"))})
		rows.append(row)
	return rows


static func validate(session: Variant, restored_hour: int = -1) -> String:
	if not enabled(session):
		return ""
	var stores: Dictionary = session.stores
	var now := restored_hour if restored_hour >= 0 else Intents.now(session.get_time_summary())
	for memory: Dictionary in stores.memory_store.snapshot_memories():
		if memory.get("memory_type") != "situation_sighting":
			continue
		var fact: Dictionary = stores.fact_store.get_fact(str(memory.get("source_fact_id", "")))
		if fact.get("fact_type") != "situation_sighting" or fact.get("actor_id") != memory.get("owner_id") \
			or fact.get("subject_id") != memory.get("subject_id") or fact.get("location_id") != memory.get("location_id") \
			or int(memory.get("observed_hour", -1)) != Intents.now(fact) or Intents.now(fact) > now \
			or not session.context.locations.has(str(memory.get("location_id", ""))) \
			or not stores.entity_store.has_entity(str(memory.get("subject_id", ""))) \
			or JSON.parse_string(JSON.stringify(memory.get("equipment"))) != JSON.parse_string(JSON.stringify(fact.get("equipment"))) \
			or memory.get("injured") != fact.get("injured"):
			return "situation_sighting_reference_mismatch"
	for fact: Dictionary in stores.fact_store.list_facts():
		if fact.get("fact_type") not in ["situation_whereabouts", "situation_heard_update", "situation_notice_read"]:
			continue
		if not session.context.locations.has(str(fact.get("location_id", ""))) or Intents.now(fact) > now:
			return "situation_information_reference_mismatch"
		for source: Variant in fact.get("source_fact_ids", []):
			if stores.fact_store.get_fact(str(source)).is_empty():
				return "situation_information_missing_source"
		if fact.fact_type == "situation_whereabouts":
			var sources: Array = fact.get("source_fact_ids", [])
			var sighting: Dictionary = stores.fact_store.get_fact(str(sources[0])) if sources.size() == 1 else {}
			if sighting.get("fact_type") != "situation_sighting" or sighting.get("actor_id") != fact.get("speaker_id") \
				or sighting.get("subject_id") != fact.get("subject_id") or sighting.get("location_id") != fact.get("known_location_id") \
				or Intents.now(sighting) != int(fact.get("observed_hour", -1)) or Intents.now(sighting) > Intents.now(fact):
				return "situation_testimony_reference_mismatch"
		if fact.fact_type == "situation_heard_update":
			var origin: Dictionary = stores.fact_store.get_fact(str(fact.get("contribution_id", "")))
			var update: Dictionary = stores.fact_store.get_fact(str(fact.get("update_id", "")))
			if origin.is_empty() or update.is_empty() or str(origin.fact_id) not in fact.get("source_fact_ids", []) \
				or str(update.fact_id) not in fact.get("source_fact_ids", []) or int(fact.get("update_hour", -1)) > Intents.now(fact):
				return "situation_update_reference_mismatch"
			if fact.get("update_kind") == "consequence":
				var snapshot: Variant = session.PlayerLife.snapshot(session.context, stores, {"day": now / 24, "hour": now % 24})
				if update.get("actor_id") != fact.get("subject_id") or update.get("fact_type") not in FOLLOWUP_TYPES \
					or contribution(snapshot, update.get("source_fact_ids", []), str(fact.actor_id), str(fact.subject_id)) != str(origin.fact_id) \
					or Intents.now(update) != int(fact.update_hour):
					return "situation_update_reference_mismatch"
		if fact.fact_type == "situation_notice_read":
			var sources: Array = fact.get("source_fact_ids", [])
			var source: Dictionary = stores.fact_store.get_fact(str(sources[0])) if sources.size() == 1 else {}
			if source.get("fact_type") != "equipment_request" or source.get("actor_id") != fact.get("subject_id") \
				or source.get("location_id") != fact.get("location_id") or source.get("query") != fact.get("query") \
				or source.get("danger_location_id") != fact.get("danger_location_id") or source.get("goal") != fact.get("goal") \
				or Intents.now(source) != int(fact.get("observed_hour", -1)) or Intents.now(source) > Intents.now(fact):
				return "situation_notice_reference_mismatch"
	return ""
