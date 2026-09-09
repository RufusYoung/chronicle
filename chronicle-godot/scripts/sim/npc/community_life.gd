extends RefCounted
class_name V5CommunityLife

const Knowledge = preload("res://scripts/sim/npc/community_knowledge.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Choice = preload("res://scripts/sim/npc/resident_activity_choice.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Family = preload("res://scripts/sim/npc/household_provisioning.gd")
const Budget = preload("res://scripts/sim/economy/household_food_budget.gd")


static func social_need(snapshot: Variant, actor: Dictionary, tick: Dictionary) -> int:
	var last := 32
	for fact: Dictionary in snapshot.get_facts_by_actor(str(actor.id)):
		if fact.get("fact_type") == "community_conversation":
			last = maxi(last, Knowledge.hour(fact))
	var interval := 24 if actor.states.get("temperament") == "sociable" else 36
	return clampi(Knowledge.hour(tick) - last - interval, 0, 72)


static func proposals(snapshot: Variant, actor: Dictionary, tick: Dictionary, config: Dictionary, network: Dictionary) -> Array:
	var rows: Array = []
	if not Knowledge.enabled(config) or not bool(config.get("social_enabled", true)) \
			or int(actor.states.get("age_years", 0)) < 18 or int(tick.hour) < 9 or int(tick.hour) > 20:
		return rows
	var need := social_need(snapshot, actor, tick)
	var settlement := str(actor.states.settlement_id)
	var group := Knowledge.group_for(snapshot, str(actor.id))
	var representative: bool = group.get("representative_id") == actor.id
	var dispatch_sources: Array = []
	var return_sources: Array = []
	if representative and bool(config.get("messages_enabled", true)):
		for report: Dictionary in Knowledge.latest(snapshot, str(actor.id), Knowledge.hour(tick)).values():
			if report.subject_id == actor.id and (report.payload.get("needs_food", false) or report.payload.get("food_available", false)) \
					or report.subject_id == group.id and report.topic == "policy":
				dispatch_sources.append(str(report.source_fact_id))
			var subject: Dictionary = snapshot.get_entity(str(report.subject_id))
			if report.topic in ["supply", "need"] and subject.get("states", {}).get("settlement_id") != settlement:
				return_sources.append(str(report.source_fact_id))
	if need == 0 and dispatch_sources.is_empty() and return_sources.is_empty():
		return rows
	var neighbors: Array = [settlement]
	if representative or actor.states.get("temperament") in ["sociable", "bold"]:
		for link: Dictionary in network.get("links", []):
			if link.settlement_a_id == settlement:
				neighbors.append(str(link.settlement_b_id))
			elif link.settlement_b_id == settlement:
				neighbors.append(str(link.settlement_a_id))
	var destinations: Array = []
	for site: Dictionary in network.get("sites", []):
		if site.settlement_id not in neighbors:
			continue
		destinations.append({"settlement_id": site.settlement_id, "location_id": site.hub_location_id, "sources": []})
	for report: Dictionary in Knowledge.latest(snapshot, str(actor.id), Knowledge.hour(tick)).values():
		if report.topic != "need" or report.subject_id == actor.id or not report.payload.has("meeting_location_id"):
			continue
		var subject: Dictionary = snapshot.get_entity(str(report.subject_id))
		var target_settlement := str(subject.get("states", {}).get("settlement_id", ""))
		if target_settlement in neighbors:
			destinations.append({"settlement_id": target_settlement, "location_id": report.payload.meeting_location_id, "sources": [report.source_fact_id]})
	var offered := {}
	for site: Dictionary in destinations:
		var goal := str(site.location_id)
		if offered.has(goal):
			continue
		offered[goal] = true
		var recent := -100
		var foreign: bool = site.settlement_id != settlement
		var last_delivered := -100
		for fact: Dictionary in snapshot.get_facts_by_actor(str(actor.id)):
			if fact.get("fact_type") in ["community_conversation", "community_visit_unmet"] and fact.get("location_id") == goal:
				recent = maxi(recent, Knowledge.hour(fact))
			if fact.get("fact_type") == "community_conversation" and fact.get("target_settlement_id") == site.settlement_id:
				last_delivered = maxi(last_delivered, Knowledge.hour(fact))
		if Knowledge.hour(tick) - recent < int(config.visit_retry_hours):
			continue
		var news: Array = dispatch_sources if foreign else return_sources
		var dispatch := not news.is_empty() and Knowledge.hour(tick) - last_delivered >= 24
		if need == 0 and not dispatch:
			continue
		var reason := "许久没有与人好好说话，去集地或对方告知的住处走访"
		if dispatch:
			reason = "带着本地口粮和互助约定的消息去邻聚落当面联络" if foreign else "把亲自听到的邻聚落近况带回来，当面告诉本地人"
		Choice.propose(rows, "social", goal, "socializing", reason, (news if dispatch else []) + site.sources, "community_visit")
		rows.back()["social_need"] = need
		rows.back()["representative"] = representative
		rows.back()["dispatch"] = dispatch
	return rows


func observe(snapshot: Variant, tick: Dictionary, config: Dictionary, budget_config: Dictionary = {}) -> Dictionary:
	var result := Result.new()
	if not Knowledge.enabled(config):
		return {"results": [], "events": []}
	var now := Knowledge.hour(tick)
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		if not _present(person):
			continue
		var id := str(person.id)
		var known := Knowledge.latest(snapshot, id, now)
		var items: Array = snapshot.get_items_for_holder(id)
		var need := Food.needs_food(person, items)
		var family_sources: Array = []
		for memory: Dictionary in Family.latest_observations(snapshot, id).values():
			if memory.get("needs_food", false) and now - int(memory.observed_hour) < int(config.memory_hours):
				need = true
				family_sources.append(str(memory.source_fact_id))
		var payload := {"needs_food": need, "family_need": not family_sources.is_empty(), "meeting_location_id": person.states.home_location_id}
		var home_need := Budget.request(snapshot, person, tick, budget_config)
		if need and not home_need.is_empty():
			payload["delivery_request"] = {"pantry_id": home_need.pantry_id, "home_location_id": home_need.home_location_id,
				"quantity": mini(int(home_need.pantry_portions), int(config.aid_portions)),
				"recipient_ids": home_need.targets.map(func(t: Dictionary) -> String: return str(t.target_id)),
				"pantry_source_fact_id": home_need.source_fact_ids[0]}
			family_sources.append_array(home_need.source_fact_ids)
		var last_meal: Dictionary = {}
		for fact: Dictionary in snapshot.get_facts_by_actor(id):
			if fact.get("fact_type") in ["npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"] and fact.get("target_id", fact.get("actor_id")) == id \
					and (last_meal.is_empty() or Knowledge.hour(fact) > Knowledge.hour(last_meal)):
				last_meal = fact
		if not last_meal.is_empty() and now - Knowledge.hour(last_meal) < 12:
			family_sources.append(str(last_meal.fact_id))
		_observe(result, person, "need", payload, known, tick, config, family_sources)
		var stock := Storage.stock_holder(snapshot, id)
		if person.states.get("location_id") == person.states.get("workplace_id"):
			var quantity := Food.food_quantity(items, id)
			if stock != "" and snapshot.get_entity_state(stock, "location_id", "") == person.states.location_id:
				quantity += Food.food_quantity(snapshot.get_items_for_holder(stock), stock)
			if quantity > 2 or known.has("supply:" + id):
				_observe(result, person, "supply", {"food_available": quantity > 2, "portions_seen": quantity}, known, tick, config)
	return _resolved(result)


func converse(snapshot: Variant, tick: Dictionary, config: Dictionary) -> Dictionary:
	var result := Result.new()
	if not Knowledge.enabled(config) or not bool(config.get("social_enabled", true)):
		return _resolved(result)
	var now := Knowledge.hour(tick)
	var people: Array = snapshot.get_entities_by_type("person").filter(func(p: Dictionary) -> bool: return _present(p))
	people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	var used := {}
	for actor: Dictionary in people:
		var visiting: bool = actor.states.get("daily_activity") == "socializing"
		if used.has(actor.id) or (not visiting and actor.states.get("daily_activity") not in ["seeking_work", "seeking_food"]):
			continue
		var possible: Array = people.filter(func(p: Dictionary) -> bool:
			return p.id != actor.id and not used.has(p.id) and p.states.location_id == actor.states.location_id \
				and ((visiting and p.states.get("daily_activity") not in ["working", "foraging", "resting"]) or _worksite_contact(snapshot, actor, p)))
		possible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var last_a := _last_pair(snapshot, str(actor.id), str(a.id))
			var last_b := _last_pair(snapshot, str(actor.id), str(b.id))
			return last_a < last_b if last_a != last_b else str(a.id) < str(b.id))
		if possible.is_empty() or now - _last_pair(snapshot, str(actor.id), str(possible[0].id)) < int(config.conversation_retry_hours):
			if not visiting:
				continue
			var failed := _fact("community_visit_unmet", str(actor.id), tick)
			failed.merge({"location_id": actor.states.location_id, "summary": "%s花了一小时等人，但没有碰到方便交谈的人；只能改日再来。" % actor.display_name})
			result.add_fact(failed)
			continue
		var other: Dictionary = possible[0]
		used[actor.id] = true
		used[other.id] = true
		if other.states.get("daily_activity") == "working":
			result.add_state_change({"entity_id": other.id, "key": "daily_activity", "to": "socializing"})
			result.add_state_change({"entity_id": other.id, "key": "daily_activity_reason", "to": "暂停手边作业，与到场的人商谈差事和供给"})
		for pair: Array in [[actor, other], [other, actor]]:
			var receiver: Dictionary = pair[0]
			var speaker: Dictionary = pair[1]
			var conversation := _fact("community_conversation", str(receiver.id), tick)
			conversation.merge({"target_id": speaker.id, "location_id": actor.states.location_id,
				"actor_settlement_id": receiver.states.settlement_id, "target_settlement_id": speaker.states.settlement_id,
				"summary": "%s和%s当面聊了近况，暂时放下手边的事。" % [receiver.display_name, speaker.display_name],
				"source_fact_ids": _presence_sources(receiver, speaker)})
			result.add_fact(conversation)
			var trust := int(snapshot.get_relation(str(receiver.id), str(speaker.id), "trust", 0))
			if trust < 30:
				result.add_relationship_change({"source_id": receiver.id, "target_id": speaker.id, "axis": "trust", "delta": 1})
			if bool(config.get("messages_enabled", true)) and trust >= int(config.minimum_report_trust):
				_share(result, snapshot, receiver, speaker, conversation, tick, config)
	return _resolved(result)


static func _worksite_contact(snapshot: Variant, actor: Dictionary, other: Dictionary) -> bool:
	return actor.states.get("daily_activity") in ["seeking_work", "seeking_food"] \
		and other.states.get("daily_activity") in ["working", "arrived", "home", "socializing"] \
		and other.states.get("location_id") == other.states.get("workplace_id") \
		and Storage.stock_holder(snapshot, str(other.id)) != ""


func _share(result: Variant, snapshot: Variant, receiver: Dictionary, speaker: Dictionary, conversation: Dictionary, tick: Dictionary, config: Dictionary) -> void:
	var now := Knowledge.hour(tick)
	var heard := Knowledge.latest(snapshot, str(receiver.id), now)
	var sent := 0
	var reports := Knowledge.latest(snapshot, str(speaker.id), now)
	var keys: Array = reports.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var pa := _report_priority(reports[a], receiver, now)
		var pb := _report_priority(reports[b], receiver, now)
		return pa > pb if pa != pb else a < b)
	for key: String in keys:
		var report: Dictionary = reports[key]
		if int(report.hops) >= int(config.maximum_hops) or (heard.has(key) and int(heard[key].observed_hour) >= int(report.observed_hour)):
			continue
		var fact := _fact("community_message_heard", str(receiver.id), tick, "." + str(sent))
		fact.merge({"target_id": speaker.id, "location_id": receiver.states.location_id, "topic": report.topic,
			"subject_id": report.subject_id, "root_fact_id": report.root_fact_id, "hops": int(report.hops) + 1,
			"source_fact_ids": [conversation.fact_id, report.source_fact_id],
			"summary": "%s从%s那里听说：%s。这是此前的见闻，到了现场仍需重新确认。" % [receiver.display_name, speaker.display_name, _message(report, snapshot)]})
		result.add_fact(fact)
		var memory := report.duplicate(true)
		memory.merge({"memory_id": "memory." + str(fact.fact_id), "owner_id": receiver.id, "reporter_id": speaker.id,
			"source_fact_id": fact.fact_id, "source_fact_ids": [fact.fact_id], "hops": int(report.hops) + 1, "learned_hour": now}, true)
		result.add_memory(memory)
		sent += 1
		if sent >= int(config.maximum_reports):
			break


func _observe(result: Variant, person: Dictionary, topic: String, payload: Dictionary, known: Dictionary, tick: Dictionary, config: Dictionary, sources: Array = []) -> void:
	var old: Dictionary = known.get(topic + ":" + str(person.id), {})
	if not old.is_empty() and _same_payload(old.payload, payload) and Knowledge.hour(tick) - int(old.observed_hour) < int(config.observation_hours):
		return
	var fact := _fact("community_observation", str(person.id), tick, "." + topic)
	var summary := "%s知道自己%s。" % [person.display_name, "仍没有可吃的口粮" if payload.get("needs_food", false) else "暂不缺随身口粮"]
	if payload.get("family_need", false):
		summary = "%s记得亲自见过的家人仍缺粮，准备向别人说明家里的需要。" % person.display_name
	if topic == "supply":
		summary = "%s在作业地检查了自己实际持有的食物，共 %d 份。" % [person.display_name, int(payload.portions_seen)]
	fact.merge({"topic": topic, "subject_id": person.id, "location_id": person.states.location_id,
		"payload": payload, "summary": summary, "source_fact_ids": sources})
	result.add_fact(fact)
	result.add_memory(direct_memory(fact, int(config.memory_hours)))


static func _same_payload(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: String in b:
		if not a.has(key):
			return false
		# Native JSON restores integral numbers as floats; observation equality is semantic.
		if b[key] is int or b[key] is float:
			if float(a[key]) != float(b[key]):
				return false
		elif a[key] != b[key]:
			if not (a[key] is Dictionary and b[key] is Dictionary and _same_payload(a[key], b[key])):
				return false
	return true


static func direct_memory(fact: Dictionary, duration: int) -> Dictionary:
	return {"memory_id": "memory." + str(fact.fact_id), "memory_type": Knowledge.MEMORY_TYPE,
		"owner_id": fact.actor_id, "reporter_id": fact.actor_id, "subject_id": fact.subject_id,
		"topic": fact.topic, "payload": fact.payload, "location_id": fact.location_id,
		"source_fact_id": fact.fact_id, "source_fact_ids": [fact.fact_id], "root_fact_id": fact.fact_id,
		"observed_hour": Knowledge.hour(fact), "learned_hour": Knowledge.hour(fact),
		"expires_hour": Knowledge.hour(fact) + duration, "hops": 0}


static func _report_priority(report: Dictionary, receiver: Dictionary, now: int) -> int:
	var priority := 100 if report.topic == "supply" and report.payload.get("food_available", false) else 0
	if report.topic == "policy":
		priority = 80
	elif report.topic == "need" and report.payload.get("needs_food", false):
		priority = 60
	return priority - (now - int(report.observed_hour)) - int(report.hops) * 8 + (4 if report.subject_id == receiver.id else 0)


static func _message(report: Dictionary, snapshot: Variant) -> String:
	var subject: Dictionary = snapshot.get_entity(str(report.subject_id))
	var name := str(subject.get("display_name", report.subject_id))
	var time := "第 %d 天 %02d:00" % [int(report.observed_hour) / 24, int(report.observed_hour) % 24]
	match str(report.topic):
		"need":
			var description := "%s在%s说%s" % [name, time, "家人仍缺粮" if report.payload.get("family_need", false) else ("自己缺粮" if report.payload.get("needs_food", false) else "自己的口粮暂有着落")]
			if report.payload.has("delivery_request"):
				description += "，请有余粮的人帮家中送来 %d 份，已告知住处与共有粮柜" % int(report.payload.delivery_request.quantity)
			return description
		"supply": return "%s在%s检查作业地的自有食物，共 %d 份，%s" % [name, time, int(report.payload.portions_seen), "可能有余粮出售" if report.payload.food_available else "当时没有余粮"]
		"policy": return "%s在%s提出：%s" % [name, time, str(report.payload.get("description", "调整售粮约定"))]
	return "一条未确认的近况"


static func _fact(kind: String, actor: String, tick: Dictionary, suffix: String = "") -> Dictionary:
	return {"fact_id": "fact.%s.%s.%d%s" % [kind, actor, Knowledge.hour(tick), suffix],
		"fact_type": kind, "actor_id": actor, "day": tick.day, "hour": tick.hour}


static func _last_pair(snapshot: Variant, actor: String, target: String) -> int:
	var latest := -100
	for fact: Dictionary in snapshot.get_facts_by_actor(actor):
		if fact.get("fact_type") == "community_conversation" and fact.get("target_id") == target:
			latest = maxi(latest, Knowledge.hour(fact))
	return latest


static func _present(actor: Dictionary) -> bool:
	var states: Dictionary = actor.get("states", {})
	return "generated_resident" in actor.get("tags", []) and bool(states.get("alive", true)) \
		and states.get("life_status", "alive") == "alive" and states.get("daily_route_id", "") == ""


static func _presence_sources(a: Dictionary, b: Dictionary) -> Array:
	var sources: Array = []
	for person: Dictionary in [a, b]:
		var source := str(person.states.get("daily_presence_fact_id", ""))
		if source != "" and source not in sources:
			sources.append(source)
	return sources


static func _resolved(result: Variant) -> Dictionary:
	if result.is_empty():
		return {"results": [], "events": []}
	result.mark_resolved("community_life")
	return {"results": [result], "events": result.facts_added.filter(func(f: Dictionary) -> bool: return f.fact_type != "community_observation")}
