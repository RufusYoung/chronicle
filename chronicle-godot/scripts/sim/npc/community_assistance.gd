extends RefCounted
class_name V5CommunityAssistance

const Knowledge = preload("res://scripts/sim/npc/community_knowledge.gd")
const Budget = preload("res://scripts/sim/economy/household_food_budget.gd")
const Choice = preload("res://scripts/sim/npc/resident_activity_choice.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")


static func requests(snapshot: Variant, owner: Dictionary, tick: Dictionary, config: Dictionary, budget_config: Dictionary) -> Array:
	var rows: Array = []
	if not Knowledge.enabled(config) or not bool(config.get("aid_enabled", true)):
		return rows
	var now := Knowledge.hour(tick)
	var policy := Knowledge.known_policy(snapshot, str(owner.id), now)
	var own := Budget.request(snapshot, owner, tick, budget_config)
	var retained := maxi(int(config.aid_retained_portions), int(own.get("pantry_portions", 0)) + int(budget_config.get("personal_reserve", 2)))
	for report: Dictionary in Knowledge.latest(snapshot, str(owner.id), now).values():
		if report.topic != "need" or not report.payload.get("needs_food", false) or not report.payload.has("delivery_request"):
			continue
		var subject: Dictionary = snapshot.get_entity(str(report.subject_id))
		if subject.get("states", {}).get("settlement_id") == owner.states.get("settlement_id") or snapshot.get_relation(str(owner.id), str(subject.id), "trust", 0) < 0:
			continue
		var request: Dictionary = report.payload.delivery_request
		var recently_sent := false
		for order: Dictionary in snapshot.exchanges:
			if order.get("party_a") == owner.id and order.get("pantry_id") == request.pantry_id \
					and now - int(order.get("created_tick", 0)) < int(config.aid_retry_hours):
				recently_sent = true
		if recently_sent:
			continue
		var declined := false
		for fact: Dictionary in snapshot.get_facts_by_actor(str(owner.id)):
			if fact.get("fact_type") == "community_aid_withheld" and fact.get("requester_id") == report.subject_id \
					and fact.get("community_policy_id") == policy.get("source_fact_id", ""):
				declined = true
		if declined:
			continue
		var targets: Array = request.recipient_ids.map(func(id: String) -> Dictionary: return {"target_id": id})
		var sources: Array = [report.source_fact_id]
		if not policy.is_empty():
			sources.append(policy.source_fact_id)
		rows.append({"pantry_id": request.pantry_id, "home_location_id": request.home_location_id,
			"targets": targets, "pantry_portions": mini(int(request.quantity), int(config.aid_portions)),
			"source_fact_ids": sources, "community_request_id": report.source_fact_id,
			"request_root_fact_id": report.root_fact_id, "requester_id": report.subject_id,
			"community_policy_id": str(policy.get("source_fact_id", "")), "community_withheld": policy.get("payload", {}).get("policy") == "reserve",
			"retained_portions": retained, "maximum_hours": int(config.aid_travel_hours),
			"trust": int(snapshot.get_relation(str(owner.id), str(subject.id), "trust", 0)), "observed_hour": report.observed_hour})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.trust != b.trust:
			return a.trust > b.trust
		return a.observed_hour < b.observed_hour if a.observed_hour != b.observed_hour else a.requester_id < b.requester_id)
	return rows


static func proposals(snapshot: Variant, actor: Dictionary, tick: Dictionary, config: Dictionary, budget_config: Dictionary) -> Array:
	var rows: Array = []
	if not Knowledge.enabled(config) or int(actor.states.get("age_years", 0)) < 18 \
			or int(tick.hour) < 8 or int(tick.hour) > 18 or Food.needs_food(actor, snapshot.get_items_for_holder(str(actor.id))):
		return rows
	for request: Dictionary in requests(snapshot, actor, tick, config, budget_config):
		for supply: Dictionary in Knowledge.supply_reports(snapshot, str(actor.id), Knowledge.hour(tick)):
			if supply.subject_id != actor.id or supply.location_id != actor.states.get("workplace_id") \
					or int(supply.payload.portions_seen) < int(request.pantry_portions) + int(request.retained_portions):
				continue
			Choice.propose(rows, "aid", str(supply.location_id), "seeking_work", "听到了邻聚落的送粮请求，回作业地核对自有余粮，考虑亲自送去", request.source_fact_ids + [supply.source_fact_id], "community_delivery:" + str(request.request_root_fact_id))
			rows.back()["aid_trust"] = request.trust
			break
	return rows
