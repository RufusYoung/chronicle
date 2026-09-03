extends RefCounted
class_name V5IndustryLifecycleSystem

const Transaction = preload("res://scripts/sim/transaction/transaction_result.gd")
const Catalog = preload("res://scripts/sim/settlement/industry_runtime_catalog.gd")
const Capacity = preload("res://scripts/sim/settlement/settlement_capacity_adaptation_system.gd")
const Labor = preload("res://scripts/sim/population/labor_absorption_system.gd")
const RoutePressure = preload("res://scripts/sim/resource/route_pressure_query.gd")


func resolve_daily_tick(
	snapshot: Variant,
	tick: Dictionary,
	network: Dictionary,
	initial_profiles: Array,
	locations: Array
) -> Dictionary:
	var config: Dictionary = network.get("industry_lifecycle", {})
	var day := int(tick.get("day", 0))
	if not bool(config.get("enabled", false)) or day <= 0:
		return {"results": [], "events": []}
	var result = Transaction.new()
	var events: Array = []
	var capacity = Capacity.new()
	var profiles := Catalog.profiles(snapshot, initial_profiles)
	var plots := capacity._built_plots(snapshot)
	var available := capacity._available_resource_amounts(snapshot)
	for site: Dictionary in network.get("sites", []):
		var settlement := str(site.get("settlement_id", ""))
		var previous_day := int(snapshot.get_entity_state(settlement, "industry_evaluation_day", 0))
		if day <= previous_day:
			continue
		_state(result, settlement, "industry_evaluation_day", day)
		var signals: Dictionary = (
			(snapshot.get_entity_state(settlement, "industry_signals", {}) as Dictionary)
			. duplicate(true)
		)
		var support: Dictionary = capacity._organization_support(snapshot, settlement, config)
		var candidates: Array[Dictionary] = []
		for prototype: Dictionary in network.get("industry_archetypes", []):
			var industry := str(prototype.get("industry_id", ""))
			var rules: Dictionary = (config.get("conditions", {}) as Dictionary).get(industry, {})
			if rules.is_empty():
				continue
			var demand := demand_for(snapshot, network, settlement, rules, day)
			var profile := _industry_profile(profiles, settlement, prototype)
			var active := not profile.is_empty()
			var prior: Dictionary = signals.get(industry, {})
			# An unobserved gap is not evidence of continuously sustained conditions.
			if previous_day != day - 1:
				prior = {}
			if active:
				var resource: Dictionary = capacity._profile_resource_condition(
					snapshot, profile, config
				)
				var workers: Array = capacity._workers(
					snapshot, settlement, str(profile.get("occupation_id", ""))
				)
				var reason := ""
				if bool(resource.get("depleted", false)):
					reason = "resource_exhausted"
				elif workers.is_empty():
					reason = "workforce_absent"
				elif float(demand.get("value", 0)) < float(rules.get("exit_demand_below", 1)):
					reason = "demand_disappeared"
				var bad_days := (
					0
					if reason == ""
					else (
						int(prior.get("bad_days", 0)) + 1
						if str(prior.get("reason", "")) == reason
						else 1
					)
				)
				signals[industry] = {"bad_days": bad_days, "reason": reason}
				if bad_days >= maxi(int(config.get("exit_days_required", 30)), 1):
					_retire(
						result,
						snapshot,
						settlement,
						prototype,
						profile,
						reason,
						bad_days,
						day,
						events
					)
					signals[industry] = {"retired_day": day}
				continue
			var good_days := (
				int(prior.get("good_days", 0)) + 1
				if float(demand.get("value", 0)) >= float(rules.get("entry_demand_at_least", 4))
				else 0
			)
			var retired_day := int(
				prior.get("retired_day", _last_retirement(snapshot, settlement, industry))
			)
			signals[industry] = {"good_days": good_days, "retired_day": retired_day}
			var required := capacity._required_pressure_days(
				maxi(int(config.get("entry_days_required", 6)), 1), support
			)
			if (
				good_days < required
				or (
					retired_day > 0
					and day - retired_day < maxi(int(config.get("reentry_cooldown_days", 30)), 1)
				)
			):
				continue
			var candidate := _candidate(
				snapshot, network, site, prototype, rules, config, demand, available
			)
			if not candidate.is_empty():
				candidate["good_days"] = good_days
				candidate["required_days"] = required
				candidates.append(candidate)
		candidates.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				if not is_equal_approx(float(a.get("score", 0)), float(b.get("score", 0))):
					return float(a.get("score", 0)) > float(b.get("score", 0))
				return str(a.get("industry_id", "")) < str(b.get("industry_id", ""))
		)
		var plot: Dictionary = capacity._next_construction_plot(locations, plots, settlement)
		if not candidates.is_empty() and not plot.is_empty():
			var selected: Dictionary = candidates[0]
			_found(result, snapshot, selected, plot, support, day, events)
			plots[str(plot.get("id", ""))] = true
			var stock_id := str(selected.get("construction_stock_id", ""))
			available[stock_id] = (
				float(available.get(stock_id, 0)) - float(selected.get("construction_cost", 0))
			)
			signals[str(selected.get("industry_id", ""))] = {}
		_state(result, settlement, "industry_signals", signals)
	if result.is_empty():
		return {"results": [], "events": events}
	if not events.is_empty():
		result.set_narrative_result(
			{"title": "聚落产业发生变化", "summary": str(events[0].get("summary", ""))}
		)
	result.mark_resolved("settlement_industry_lifecycle")
	return {"results": [result], "events": events}


func demand_for(
	snapshot: Variant, network: Dictionary, settlement: String, rules: Dictionary, day: int
) -> Dictionary:
	var kind := str(rules.get("demand_kind", "resource_shortage"))
	var sources: Array = []
	var value := 0.0
	if kind == "route_risk":
		for link: Dictionary in network.get("links", []):
			if (
				settlement
				not in [str(link.get("settlement_a_id", "")), str(link.get("settlement_b_id", ""))]
			):
				continue
			var pressure: Dictionary = RoutePressure.new().active_pressure(
				snapshot, str(link.get("link_id", "")), day
			)
			value = maxf(
				value, float(link.get("risk", 0)) + float(pressure.get("risk_increase", 0))
			)
			sources.append_array(pressure.get("source_fact_ids", []))
	elif kind == "transport":
		for fact: Dictionary in snapshot.get_facts():
			if (
				str(fact.get("fact_type", "")) == "settlement_trade_shipment"
				and day - int(fact.get("day", 0)) in range(0, 8)
				and settlement in [str(fact.get("actor_id", "")), str(fact.get("target_id", ""))]
			):
				value += 1.0
				sources.append(str(fact.get("fact_id", "")))
	else:
		var current := 0.0
		var total := 0.0
		for stock: Dictionary in snapshot.get_resource_stocks():
			if (
				str(stock.get("settlement_id", "")) == settlement
				and Capacity.new()._has_any_tag(stock.get("tags", []), rules.get("demand_tags", []))
			):
				current += float(stock.get("current", 0))
				total += float(stock.get("capacity", 0))
				sources.append_array(stock.get("source_fact_ids", []))
		value = 10.0 if total <= 0 else 10.0 * (1.0 - clampf(current / total, 0, 1))
	return {"kind": kind, "value": value, "source_fact_ids": sources}


func _candidate(
	snapshot: Variant,
	network: Dictionary,
	site: Dictionary,
	prototype: Dictionary,
	rules: Dictionary,
	config: Dictionary,
	demand: Dictionary,
	available: Dictionary
) -> Dictionary:
	var settlement := str(site.get("settlement_id", ""))
	var template := _industry_profile(
		network.get("industry_occupation_templates", []), "", prototype
	)
	if template.is_empty():
		return {}
	var founder := _experienced_founder(snapshot, settlement, rules, config)
	if founder.is_empty():
		return {}
	var capacity = Capacity.new()
	var cost := maxf(float(config.get("construction_cost", 4)), 0.1)
	var construction: Dictionary = capacity._select_construction_stock(
		snapshot, settlement, cost, available
	)
	if construction.is_empty():
		return {}
	var input_rule: Dictionary = prototype.get("stock_input", {})
	var inputs: Array = []
	if not input_rule.is_empty():
		var stocks: Array = snapshot.get_resource_stocks()
		stocks.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return str(a.get("stock_id", "")) < str(b.get("stock_id", ""))
		)
		for stock: Dictionary in stocks:
			var amount := float(available.get(str(stock.get("stock_id", "")), 0))
			if str(stock.get("stock_id", "")) == str(construction.get("stock_id", "")):
				amount -= cost
			var required := maxf(
				float(input_rule.get("amount_per_cycle", 1)), float(stock.get("operating_floor", 0))
			)
			if (
				str(stock.get("settlement_id", "")) != settlement
				or str(stock.get("source_kind", "")) != str(input_rule.get("source_kind", ""))
				or not capacity._has_any_tag(stock.get("tags", []), input_rule.get("tags_any", []))
				or amount < required * 2
			):
				continue
			inputs.append(
				{
					"stock_id": str(stock.get("stock_id", "")),
					"amount_per_cycle": float(input_rule.get("amount_per_cycle", 1)),
					"label": str(stock.get("label", "生产资源"))
				}
			)
			break
		if inputs.is_empty():
			return {}
	var row := prototype.duplicate(true)
	row.merge(
		{
			"settlement_id": settlement,
			"hub_id": str(site.get("hub_location_id", "")),
			"profile": template,
			"founder": founder,
			"demand": demand,
			"resource_inputs": inputs,
			"construction_stock_id": str(construction.get("stock_id", "")),
			"construction_cost": cost,
			"initial_slots": maxi(int(config.get("initial_slots", 2)), 1),
			"score": float(demand.get("value", 0)) * 100 + int(founder.get("cycles", 0))
		},
		true
	)
	return row


func _experienced_founder(
	snapshot: Variant, settlement: String, rules: Dictionary, config: Dictionary
) -> Dictionary:
	var evidence: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) != "npc_livelihood_produced"
			or (
				str(fact.get("occupation_id", ""))
				not in (rules.get("experience_occupations", []) as Array)
			)
		):
			continue
		var id := str(fact.get("actor_id", ""))
		var row: Dictionary = evidence.get(id, {"cycles": 0, "work_days": [], "source_fact_id": ""})
		row["cycles"] = int(row.get("cycles", 0)) + 1
		var work_day := int(fact.get("day", 0))
		if work_day not in row["work_days"]:
			row["work_days"].append(work_day)
		row["source_fact_id"] = str(fact.get("fact_id", ""))
		evidence[id] = row
	var candidates: Array[Dictionary] = []
	var pending: Dictionary = Labor.new()._pending_migrant_households(snapshot)
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var id := str(person.get("id", ""))
		var row: Dictionary = evidence.get(id, {})
		if (
			id == "player"
			or str(snapshot.get_entity_state(id, "settlement_id", "")) != settlement
			or str(snapshot.get_entity_state(id, "life_status", "alive")) != "alive"
			or (
				str(snapshot.get_entity_state(id, "livelihood_status", ""))
				not in ["employed", "self_employed", "unemployed"]
			)
			or pending.has(str(snapshot.get_entity_state(id, "household_id", "")))
			or int(row.get("cycles", 0)) < maxi(int(config.get("minimum_experience_cycles", 6)), 1)
		):
			continue
		row = row.duplicate(true)
		row["resident_id"] = id
		var weights: Dictionary = rules.get(
			"founder_attribute_weights", {"dexterity": 2, "wisdom": 1}
		)
		var contributions: Dictionary = {}
		# Shorter production cycles must not count as more days of experience.
		var initiative := mini((row.get("work_days", []) as Array).size(), 20)
		for attribute: String in weights.keys():
			var contribution := (
				int(snapshot.get_entity_state(id, attribute, 0)) * int(weights[attribute])
			)
			contributions[attribute] = contribution
			initiative += contribution
		if str(snapshot.get_entity_state(id, "livelihood_status", "")) == "unemployed":
			initiative += 8
		row["initiative_score"] = initiative
		row["attribute_contributions"] = contributions
		candidates.append(row)
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				int(a.get("initiative_score", 0)) > int(b.get("initiative_score", 0))
				if int(a.get("initiative_score", 0)) != int(b.get("initiative_score", 0))
				else str(a.get("resident_id", "")) < str(b.get("resident_id", ""))
			)
	)
	return {} if candidates.is_empty() else candidates[0]


func _found(
	result: Variant,
	snapshot: Variant,
	row: Dictionary,
	plot: Dictionary,
	support: Dictionary,
	day: int,
	events: Array
) -> void:
	var settlement := str(row.get("settlement_id", ""))
	var industry := str(row.get("industry_id", ""))
	var token := "%s.%s.day%d" % [settlement, industry, day]
	var fact_id := "fact.industry_founded." + token
	var facility_id := "runtime_industry." + token
	var workplace := str(plot.get("id", ""))
	var founder: Dictionary = row.get("founder", {})
	var resident := str(founder.get("resident_id", ""))
	var profile: Dictionary = (row.get("profile", {}) as Dictionary).duplicate(true)
	var occupation := str(profile.get("occupation_id", ""))
	var capacity = Capacity.new()
	var slots := int(row.get("initial_slots", 2))
	profile.merge(
		{
			"settlement_id": settlement,
			"workplace_id": workplace,
			"maximum_slots": 0,
			"resource_inputs": row.get("resource_inputs", []),
			"industry_source_fact_id": fact_id,
			"facility_entity_id": facility_id
		},
		true
	)
	var sources: Array = capacity._source_fact_ids(
		snapshot, settlement, workplace, str(row.get("construction_stock_id", ""))
	)
	sources.append(str(founder.get("source_fact_id", "")))
	sources.append_array((row.get("demand", {}) as Dictionary).get("source_fact_ids", []))
	for input: Dictionary in profile.get("resource_inputs", []):
		sources.append_array(
			snapshot.get_resource_stock(str(input.get("stock_id", ""))).get("source_fact_ids", [])
		)
	if str(support.get("source_fact_id", "")) != "":
		sources.append(str(support.get("source_fact_id", "")))
	var name := (
		"%s%s"
		% [
			capacity._entity_name(snapshot, settlement),
			(row.get("facility", {}) as Dictionary).get("name_suffix", "作业棚")
		]
	)
	var summary := (
		"%s利用已有劳动经验，在%s办起%s，先投入 %d 个岗位。"
		% [
			capacity._entity_name(snapshot, resident),
			capacity._entity_name(snapshot, settlement),
			row.get("label", industry),
			slots
		]
	)
	var description := (
		"%s\n%s" % [(row.get("facility", {}) as Dictionary).get("observation", ""), summary]
	)
	result.add_fact(
		{
			"fact_id": fact_id,
			"fact_type": "settlement_industry_founded",
			"actor_id": resident,
			"target_id": settlement,
			"settlement_id": settlement,
			"industry_id": industry,
			"industry_label": row.get("label", industry),
			"facility_entity_id": facility_id,
			"workplace_id": workplace,
			"occupation_id": occupation,
			"hub_location_id": row.get("hub_id", ""),
			"facility_name": name,
			"facility_description": description,
			"former_occupation_id": snapshot.get_entity_state(resident, "occupation_id", ""),
			"experience_cycles": founder.get("cycles", 0),
			"experience_days": (founder.get("work_days", []) as Array).size(),
			"demand": row.get("demand", {}),
			"founder_initiative_score": founder.get("initiative_score", 0),
			"founder_attribute_contributions": founder.get("attribute_contributions", {}),
			"qualifying_days": row.get("good_days", 0),
			"required_days": row.get("required_days", 0),
			"coordinator_organization_id": support.get("organization_id", ""),
			"resource_stock_id": row.get("construction_stock_id", ""),
			"resource_cost": row.get("construction_cost", 0),
			"resource_inputs": profile.get("resource_inputs", []),
			"source_fact_ids": sources,
			"day": day,
			"summary": summary
		}
	)
	result.add_entity_change(
		{
			"operation": "create",
			"entity":
			{
				"id": facility_id,
				"type": "trace",
				"display_name": name,
				"description": description,
				"tags":
				[
					"generated_facility",
					"runtime_industry",
					"inspectable_site",
					"industry_" + industry
				],
				"industry_profile": profile,
				"industry_founded_day": day,
				"industry_hub_id": row.get("hub_id", "")
			},
			"source_fact_ids": [fact_id],
			"day": day
		}
	)
	for key: String in ["visible", "inspectable", "facility_operational"]:
		_state(result, facility_id, key, true)
	_state(result, facility_id, "location_id", workplace)
	_state(result, facility_id, "industry_status", "active")
	var old_delta := capacity._occupation_capacity_delta(snapshot, settlement, occupation)
	capacity._append_work_capacity_change(
		result,
		snapshot,
		settlement,
		profile,
		slots - old_delta,
		"industry_founded",
		0,
		slots,
		day,
		[fact_id],
		{},
		support
	)
	_state(result, facility_id, "job_capacity_delta", slots)
	result.add_resource_change(
		{
			"stock_id": row.get("construction_stock_id", ""),
			"operation": "consume",
			"amount": row.get("construction_cost", 0),
			"source_fact_ids": [fact_id],
			"tick": day * 24,
			"reason": "industry_construction"
		}
	)
	var employment_sources: Array[String] = [fact_id, str(founder.get("source_fact_id", ""))]
	Labor.new()._append_employment(
		result, snapshot, resident, settlement, profile, employment_sources, day, []
	)
	result.add_chronicle_entry(
		{
			"entry_id": "chronicle.industry_founded." + token,
			"subject_id": settlement,
			"title": "新办" + str(row.get("label", industry)),
			"body": summary,
			"source_fact_ids": [fact_id],
			"day": day
		}
	)
	events.append(
		{
			"event_type": "settlement_industry_founded",
			"settlement_id": settlement,
			"industry_id": industry,
			"fact_id": fact_id,
			"summary": summary,
			"day": day
		}
	)


func _retire(
	result: Variant,
	snapshot: Variant,
	settlement: String,
	prototype: Dictionary,
	profile: Dictionary,
	reason: String,
	bad_days: int,
	day: int,
	events: Array
) -> void:
	var capacity = Capacity.new()
	var industry := str(prototype.get("industry_id", ""))
	var workplace := str(profile.get("workplace_id", ""))
	var facility := str(
		profile.get("facility_entity_id", capacity._facility_entity_id(snapshot, workplace))
	)
	if facility == "":
		return
	var fact_id := "fact.industry_retired.%s.%s.day%d" % [settlement, industry, day]
	var occupation := str(profile.get("occupation_id", ""))
	var slots := maxi(
		(
			int(profile.get("maximum_slots", 0))
			+ capacity._occupation_capacity_delta(snapshot, settlement, occupation)
		),
		0
	)
	var reason_label: String = (
		{
			"resource_exhausted": "资源长期不足",
			"workforce_absent": "长期无人承接工作",
			"demand_disappeared": "原有需求长期消退"
		}
		. get(reason, "条件无法维持")
	)
	var summary := (
		"%s因%s持续 %d 天退出本地产业，旧设施保留，岗位不再招人。"
		% [prototype.get("label", industry), reason_label, bad_days]
	)
	var sources: Array = capacity._source_fact_ids(snapshot, settlement, workplace, "")
	var founding := str(profile.get("industry_source_fact_id", ""))
	if founding != "":
		sources.append(founding)
	result.add_fact(
		{
			"fact_id": fact_id,
			"fact_type": "settlement_industry_retired",
			"actor_id": settlement,
			"target_id": facility,
			"settlement_id": settlement,
			"industry_id": industry,
			"industry_label": prototype.get("label", industry),
			"occupation_id": occupation,
			"workplace_id": workplace,
			"reason": reason,
			"unsustainable_days": bad_days,
			"source_fact_ids": sources,
			"day": day,
			"summary": summary
		}
	)
	capacity._append_work_capacity_change(
		result,
		snapshot,
		settlement,
		profile,
		-slots,
		"industry_retired",
		slots,
		0,
		day,
		[fact_id],
		{}
	)
	capacity._append_layoffs(
		result, snapshot, settlement, profile, 0, fact_id, day, events, {}, "industry_retired"
	)
	_state(result, facility, "industry_status", "retired")
	_state(result, facility, "facility_operational", false)
	result.add_entity_change(
		{
			"operation": "update",
			"entity_id": facility,
			"fields": {"description": summary},
			"source_fact_ids": [fact_id],
			"day": day
		}
	)
	result.add_chronicle_entry(
		{
			"entry_id": "chronicle." + fact_id,
			"subject_id": settlement,
			"title": str(prototype.get("label", industry)) + "退场",
			"body": summary,
			"source_fact_ids": [fact_id],
			"day": day
		}
	)
	events.append(
		{
			"event_type": "settlement_industry_retired",
			"settlement_id": settlement,
			"industry_id": industry,
			"fact_id": fact_id,
			"summary": summary,
			"day": day
		}
	)


func _industry_profile(profiles: Array, settlement: String, prototype: Dictionary) -> Dictionary:
	for profile: Dictionary in profiles:
		if (
			str(profile.get("settlement_id", "")) == settlement
			and (
				str(profile.get("occupation_id", ""))
				in (prototype.get("occupation_ids", []) as Array)
			)
		):
			return profile.duplicate(true)
	return {}


func _last_retirement(snapshot: Variant, settlement: String, industry: String) -> int:
	var latest := 0
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "settlement_industry_retired"
			and str(fact.get("settlement_id", "")) == settlement
			and str(fact.get("industry_id", "")) == industry
		):
			latest = maxi(latest, int(fact.get("day", 0)))
	return latest


func _state(result: Variant, entity: String, key: String, value: Variant) -> void:
	result.add_state_change({"entity_id": entity, "key": key, "to": value})
