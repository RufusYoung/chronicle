extends RefCounted
## Read-only projection. No Store writes, RNG draws, event choices or outcomes.

const Intents = preload("res://scripts/sim/situation/equipment_intents.gd")
const Gear = preload("res://scripts/sim/equipment/resident_equipment.gd")
const Affordance = preload("res://scripts/sim/action/action_affordance_system.gd")


static func enabled(session: Variant) -> bool:
	return session.fixture_source_data.get("situation_rules", {}).get("version") == 1


static func build(session: Variant) -> Array:
	if not enabled(session):
		return []
	var snapshot: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	var player := str(session.context.actor_id)
	var location := str(session.context.location_id)
	if snapshot.get_entity_state(player, "daily_route_id", "") != "":
		return []
	var rows: Array = []
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		if person.id == player or not Intents.present(person, location) or not person.states.get("visible", false):
			continue
		var visible_items: Array = []
		for id: Variant in snapshot.get_equipment_loadout(str(person.id)).get("slots", {}).values():
			var item: Dictionary = snapshot.get_item(str(id))
			if not item.is_empty() and item.get("holder", {}).get("id") == person.id:
				visible_items.append({"id": id, "name": item.display_name, "damaged": int(item.condition.durability) < int(item.condition.maximum_durability)})
		var knowledge: Dictionary = {}
		for fact: Dictionary in snapshot.get_facts_by_actor(player):
			if fact.get("fact_type") == "situation_inquiry" and fact.get("subject_id") == person.id:
				knowledge = fact
		var request := Intents.latest_request(snapshot, str(person.id))
		var heard: bool = not request.is_empty() and player in request.heard_by_ids and Intents.now(snapshot.world_time) < int(request.expires_hour)
		var known: bool = not knowledge.is_empty() and Intents.now(snapshot.world_time) - int(knowledge.absolute_hour) < 6
		var row := {"subject_id": person.id, "subjects": [person.id], "title": str(person.display_name),
			"location_id": location, "goals": [], "blockers": [], "related_items": visible_items,
			"visible_traces": [], "player_known_facts": [], "provenance": [], "urgency": "unknown",
			"stakes": "去向与准备由本人决定", "body": "%s在这里。" % person.display_name, "score": 10}
		if visible_items.any(func(item: Dictionary) -> bool: return item.damaged):
			row.body += " 身上的装备已有磨损。"
			row.visible_traces.append({"kind": "worn_equipment", "source": "visible_equipment"})
			row.score += 10
		if int(person.states.get("health", 100)) < 85:
			row.body += " 看上去还带着伤。"
			row.visible_traces.append({"kind": "injury", "source": "visible_body"})
			row.score += 10
		if heard or known:
			var source: Dictionary = request if heard and (not known or int(request.absolute_hour) > int(knowledge.absolute_hour)) else knowledge
			row.player_known_facts.append(source.fact_id)
			row.provenance.append({"kind": "heard_in_person", "fact_id": source.fact_id})
			row.body += "\n你在第%d天%02d时听到：%s" % [source.day, source.hour, str(source.get("statement", source.get("summary", "")))]
			row.goals = [source.get("goal", "本人没有提出装备需求")]
			if source.has("query"):
				row["known_query"] = source.query
				row.score += 50
				row.blockers.append("先前提出的装备需求；是否仍缺须当面确认")
		else:
			row.body += " 可以问问近况；你还不知道此人的打算。"
		row.provenance.append({"kind": "present_entity", "entity_id": person.id, "location_id": location})
		row["affordances"] = Affordance.new().situation_candidates(session, snapshot, row)
		row.score += mini(row.affordances.size(), 5)
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score if a.score != b.score else str(a.subject_id) < str(b.subject_id))
	return rows


static func notices(session: Variant) -> Array:
	var rows: Array = []
	if not enabled(session):
		return rows
	var hour := Intents.now(session.get_time_summary())
	var latest := {}
	for trace: Dictionary in session.stores.trace_store.list_traces_by_location(str(session.context.location_id)):
		if trace.get("trace_type") == "equipment_activity" and trace.get("visible", false) and hour < int(trace.get("expires_hour", 0)):
			var key := str(trace.get("actor_id", "")) + ":" + str(trace.get("source_fact_type", ""))
			latest[key] = {"text": trace.description, "source_fact_id": trace.source_fact_id, "trace_id": trace.trace_id,
				"created_hour": trace.created_hour, "actor_id": trace.get("actor_id", ""), "departure_to": trace.get("departure_to", ""), "witness_id": trace.get("witness_id", "")}
	rows.assign(latest.values())
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.created_hour < b.created_hour if a.created_hour != b.created_hour else str(a.trace_id) < str(b.trace_id))
	return rows
