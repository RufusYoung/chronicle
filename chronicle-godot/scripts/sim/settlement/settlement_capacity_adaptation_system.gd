extends RefCounted
class_name V5SettlementCapacityAdaptationSystem

const Access = preload("res://scripts/sim/resource/resource_access.gd")

const IndustryCatalog = preload("res://scripts/sim/settlement/industry_runtime_catalog.gd")

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)

const CONSTRUCTION_TAGS := [
	"building", "timber", "stone", "reeds", "fiber",
]


func resolve_daily_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		network_config: Dictionary,
		profiles: Array,
		locations: Array
) -> Dictionary:
	profiles = IndustryCatalog.profiles(snapshot, profiles)
	var config: Dictionary = network_config.get("capacity_adaptation", {})
	var day := int(tick_event.get("day", 0))
	var interval := maxi(int(config.get("evaluation_interval_days", 1)), 1)
	if (
		not bool(config.get("enabled", false))
		or day <= 0
		or day % interval != 0
	):
		return {"results": [], "events": []}

	var result = TransactionResultModel.new()
	var events: Array = []
	var counts := {
		"housing_built": 0,
		"facilities_expanded": 0,
		"facilities_closed": 0,
		"facilities_reopened": 0,
		"residents_laid_off": 0,
	}
	var available_resources := _available_resource_amounts(snapshot)
	var built_plots := _built_plots(snapshot)
	var facility_delta_changes: Dictionary = {}
	for settlement_id: String in _settlement_ids(network_config):
		var organization_support := _organization_support(
			snapshot, settlement_id, config
		)
		_resolve_housing(
			result, snapshot, settlement_id, day, config, locations,
			available_resources, built_plots, organization_support,
			events, counts
		)
		_resolve_labor_capacity(
			result, snapshot, settlement_id, day, config, profiles,
			available_resources, facility_delta_changes,
			organization_support, events, counts
		)

	if result.is_empty():
		return {"results": [], "events": events}
	result.set_narrative_result({
		"title": "聚落按照人口与资源改变了自身",
		"summary": "新建住宅 %d 处，扩张设施 %d 次，关闭设施 %d 次，恢复设施 %d 次，%d 名居民失去岗位。" % [
			int(counts.get("housing_built", 0)),
			int(counts.get("facilities_expanded", 0)),
			int(counts.get("facilities_closed", 0)),
			int(counts.get("facilities_reopened", 0)),
			int(counts.get("residents_laid_off", 0)),
		],
		"tone": "ordinary_life",
	})
	result.mark_resolved("settlement_capacity_adaptation")
	return {"results": [result], "events": events}


func _resolve_housing(
		result: Variant,
		snapshot: Variant,
		settlement_id: String,
		day: int,
		config: Dictionary,
		locations: Array,
		available_resources: Dictionary,
		built_plots: Dictionary,
		organization_support: Dictionary,
		events: Array,
		counts: Dictionary
) -> void:
	var population := _settlement_population(snapshot, settlement_id)
	var capacity := maxi(int(snapshot.get_entity_state(
		settlement_id, "resident_capacity", 0
	)), 1)
	var threshold := clampi(int(config.get(
		"housing_pressure_ratio_percent", 85
	)), 1, 100)
	var under_pressure := population * 100 >= capacity * threshold
	var previous_days := int(snapshot.get_entity_state(
		settlement_id, "housing_pressure_days", 0
	))
	var pressure_days := previous_days + 1 if under_pressure else 0
	if pressure_days != previous_days:
		result.add_state_change({
			"entity_id": settlement_id,
			"key": "housing_pressure_days",
			"to": pressure_days,
		})
	if not under_pressure:
		return
	var base_required_days := maxi(int(config.get(
		"housing_pressure_days_required", 30
	)), 1)
	var required_days := _required_pressure_days(
		base_required_days, organization_support
	)
	if pressure_days < required_days or not _cooldown_ready(
		snapshot, settlement_id, "settlement_dwelling_constructed", day,
		maxi(int(config.get("housing_construction_cooldown_days", 90)), 0)
	):
		return
	var plot := _next_construction_plot(
		locations, built_plots, settlement_id
	)
	if plot.is_empty():
		_append_unmet_capacity_fact(
			result, snapshot, settlement_id, "housing", "no_buildable_plot",
			population, capacity, day, config
		)
		return
	var cost := maxf(float(config.get("housing_construction_cost", 4.0)), 0.1)
	var stock := _select_construction_stock(
		snapshot, settlement_id, cost, available_resources, "settlement_dwelling_construction"
	)
	if stock.is_empty():
		_append_unmet_capacity_fact(
			result, snapshot, settlement_id, "housing", "materials_unavailable",
			population, capacity, day, config
		)
		return

	var plot_id := str(plot.get("id", ""))
	var capacity_delta := maxi(int(config.get(
		"housing_capacity_per_dwelling", 4
	)), 1)
	var fact_id := "fact.settlement_dwelling_constructed.%s.day%d" % [
		_safe_id(plot_id), day,
	]
	var source_fact_ids := _source_fact_ids(
		snapshot, settlement_id, plot_id, str(stock.get("stock_id", ""))
	)
	_append_organization_source(source_fact_ids, organization_support)
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "settlement_dwelling_constructed",
		"actor_id": settlement_id,
		"target_id": settlement_id,
		"settlement_id": settlement_id,
		"home_location_id": plot_id,
		"resource_stock_id": str(stock.get("stock_id", "")),
		"resource_cost": cost,
		"resident_capacity_before": capacity,
		"resident_capacity_delta": capacity_delta,
		"resident_capacity_after": capacity + capacity_delta,
		"pressure_days": pressure_days,
		"pressure_days_required": required_days,
		"pressure_days_without_organization": base_required_days,
		"coordinator_organization_id": str(organization_support.get(
			"organization_id", ""
		)),
		"coordinator_member_count": int(organization_support.get(
			"member_count", 0
		)),
		"coordination_days_reduced": int(organization_support.get(
			"pressure_day_reduction", 0
		)),
		"source_fact_ids": source_fact_ids,
		"day": day,
		"summary": _dwelling_summary(
			snapshot, settlement_id, organization_support
		),
	})
	var feature_id := "runtime_feature.dwelling.%s" % _safe_id(plot_id)
	result.add_entity_change({
		"operation": "create",
		"entity": {
			"id": feature_id,
			"type": "trace",
			"display_name": "%s新住屋" % _entity_name(snapshot, settlement_id),
			"description": "人口压力、可建地块和本地材料共同促成的普通住屋。",
			"tags": [
				"runtime_dwelling", "settlement_dwelling",
				"capacity_adaptation", "inspectable_site",
			],
		},
		"source_fact_ids": [fact_id],
		"day": day,
	})
	for change: Dictionary in [
		{"key": "location_id", "to": plot_id},
		{"key": "visible", "to": true},
		{"key": "inspectable", "to": true},
	]:
		result.add_state_change({
			"entity_id": feature_id,
			"key": str(change.get("key", "")),
			"to": change.get("to"),
		})
	result.add_state_change({
		"entity_id": settlement_id,
		"key": "resident_capacity",
		"to": capacity + capacity_delta,
	})
	result.add_state_change({
		"entity_id": settlement_id,
		"key": "housing_pressure_days",
		"to": 0,
	})
	result.add_resource_change({
		"stock_id": str(stock.get("stock_id", "")),
		"operation": "consume",
		"amount": cost,
		"source_fact_ids": [fact_id],
		"tick": day * 24,
		"reason": "settlement_dwelling_construction",
		"actor_id": settlement_id,
		"day": day,
	})
	result.add_chronicle_entry({
		"entry_id": "chronicle.settlement_dwelling_constructed.%s.day%d" % [
			_safe_id(plot_id), day,
		],
		"subject_id": settlement_id,
		"title": "%s增建住屋" % _entity_name(snapshot, settlement_id),
		"body": _dwelling_chronicle_body(
			pressure_days, str(stock.get("label", "本地材料")),
			organization_support
		),
		"source_fact_ids": [fact_id],
		"day": day,
	})
	available_resources[str(stock.get("stock_id", ""))] = (
		float(available_resources.get(str(stock.get("stock_id", "")), 0.0))
		- cost
	)
	built_plots[plot_id] = true
	events.append({
		"event_type": "settlement_dwelling_constructed",
		"settlement_id": settlement_id,
		"home_location_id": plot_id,
		"resident_capacity_delta": capacity_delta,
		"coordinator_organization_id": str(organization_support.get(
			"organization_id", ""
		)),
		"fact_id": fact_id,
		"day": day,
	})
	counts["housing_built"] = int(counts.get("housing_built", 0)) + 1


func _resolve_labor_capacity(
		result: Variant,
		snapshot: Variant,
		settlement_id: String,
		day: int,
		config: Dictionary,
		profiles: Array,
		available_resources: Dictionary,
		facility_delta_changes: Dictionary,
		organization_support: Dictionary,
		events: Array,
		counts: Dictionary
) -> void:
	var scoped_profiles := _profiles_for_settlement(profiles, settlement_id)
	if scoped_profiles.is_empty():
		return
	var had_closure := false
	var open_slots := 0
	for profile: Dictionary in scoped_profiles:
		var base_capacity := maxi(int(profile.get("maximum_slots", 0)), 0)
		var delta := _occupation_capacity_delta(
			snapshot, settlement_id, str(profile.get("occupation_id", ""))
		)
		var capacity := maxi(base_capacity + delta, 0)
		var resource := _profile_resource_condition(snapshot, profile, config)
		var latest_change := _latest_capacity_change(
			snapshot, settlement_id, str(profile.get("occupation_id", ""))
		)
		if bool(resource.get("depleted", false)) and capacity > 0:
			var capacity_fact_id := _append_work_capacity_change(
				result, snapshot, settlement_id, profile, -capacity,
				"resource_depleted", capacity, 0, day,
				resource.get("source_fact_ids", []), facility_delta_changes
			)
			_append_layoffs(
				result, snapshot, settlement_id, profile, 0,
				capacity_fact_id, day, events, counts
			)
			events.append({
				"event_type": "settlement_facility_closed",
				"settlement_id": settlement_id,
				"occupation_id": str(profile.get("occupation_id", "")),
				"workplace_id": str(profile.get("workplace_id", "")),
				"capacity_delta": -capacity,
				"fact_id": capacity_fact_id,
				"day": day,
			})
			counts["facilities_closed"] = int(counts.get(
				"facilities_closed", 0
			)) + 1
			had_closure = true
			capacity = 0
		elif (
			capacity <= 0
			and bool(resource.get("recovered", false))
			and str(latest_change.get("reason", "")) == "resource_depleted"
		):
			var restored_capacity := maxi(int(latest_change.get(
				"capacity_before", base_capacity
			)), 1)
			var capacity_fact_id := _append_work_capacity_change(
				result, snapshot, settlement_id, profile, restored_capacity,
				"resource_recovered", 0, restored_capacity, day,
				resource.get("source_fact_ids", []), facility_delta_changes
			)
			events.append({
				"event_type": "settlement_facility_reopened",
				"settlement_id": settlement_id,
				"occupation_id": str(profile.get("occupation_id", "")),
				"workplace_id": str(profile.get("workplace_id", "")),
				"capacity_delta": restored_capacity,
				"fact_id": capacity_fact_id,
				"day": day,
			})
			counts["facilities_reopened"] = int(counts.get(
				"facilities_reopened", 0
			)) + 1
			capacity = restored_capacity
		open_slots += maxi(
			capacity - _worker_count(snapshot, settlement_id, str(
				profile.get("occupation_id", "")
			)), 0
		)

	var unemployed := _unemployed_residents(snapshot, settlement_id)
	var minimum_unemployed := maxi(int(config.get(
		"minimum_unemployed_for_expansion", 1
	)), 1)
	var under_pressure := unemployed.size() >= minimum_unemployed and open_slots <= 0
	var previous_days := int(snapshot.get_entity_state(
		settlement_id, "labor_pressure_days", 0
	))
	var pressure_days := previous_days + 1 if under_pressure else 0
	if pressure_days != previous_days:
		result.add_state_change({
			"entity_id": settlement_id,
			"key": "labor_pressure_days",
			"to": pressure_days,
		})
	if not under_pressure or had_closure:
		return
	var base_required_days := maxi(int(config.get(
		"labor_pressure_days_required", 14
	)), 1)
	var required_days := _required_pressure_days(
		base_required_days, organization_support
	)
	if pressure_days < required_days or not _cooldown_ready(
		snapshot, settlement_id, "settlement_work_capacity_changed", day,
		maxi(int(config.get("facility_expansion_cooldown_days", 30)), 0),
		["labor_pressure_expansion"]
	):
		return
	var selected := _select_expansion_profile(
		snapshot, scoped_profiles, unemployed, settlement_id, config
	)
	if selected.is_empty():
		_append_unmet_capacity_fact(
			result, snapshot, settlement_id, "labor", "no_expandable_occupation",
			unemployed.size(), open_slots, day, config
		)
		return
	var cost := maxf(float(config.get("facility_expansion_cost", 3.0)), 0.1)
	var stock := _select_construction_stock(
		snapshot, settlement_id, cost, available_resources, "settlement_facility_expansion"
	)
	if stock.is_empty():
		_append_unmet_capacity_fact(
			result, snapshot, settlement_id, "labor", "materials_unavailable",
			unemployed.size(), open_slots, day, config
		)
		return
	var occupation_id := str(selected.get("occupation_id", ""))
	var base_capacity := maxi(int(selected.get("maximum_slots", 0)), 0)
	var current_delta := _occupation_capacity_delta(
		snapshot, settlement_id, occupation_id
	)
	var current_capacity := maxi(base_capacity + current_delta, 0)
	var maximum_extra := maxi(int(config.get(
		"maximum_extra_slots_per_occupation", 4
	)), 0)
	var slot_delta := mini(
		maxi(int(config.get("work_slots_per_expansion", 2)), 1),
		maxi(base_capacity + maximum_extra - current_capacity, 0)
	)
	if slot_delta <= 0:
		return
	var source_fact_ids: Array = selected.get("resource_source_fact_ids", [])
	for fact_id: String in _source_fact_ids(
		snapshot, settlement_id, "", str(stock.get("stock_id", ""))
	):
		if fact_id not in source_fact_ids:
			source_fact_ids.append(fact_id)
	_append_organization_source(source_fact_ids, organization_support)
	var capacity_fact_id := _append_work_capacity_change(
		result, snapshot, settlement_id, selected, slot_delta,
		"labor_pressure_expansion", current_capacity,
		current_capacity + slot_delta, day, source_fact_ids,
		facility_delta_changes, organization_support
	)
	result.add_resource_change({
		"stock_id": str(stock.get("stock_id", "")),
		"operation": "consume",
		"amount": cost,
		"source_fact_ids": [capacity_fact_id],
		"tick": day * 24,
		"reason": "settlement_facility_expansion",
		"actor_id": settlement_id,
		"day": day,
	})
	result.add_state_change({
		"entity_id": settlement_id,
		"key": "labor_pressure_days",
		"to": 0,
	})
	result.add_chronicle_entry({
		"entry_id": "chronicle.settlement_facility_expanded.%s.%s.day%d" % [
			_safe_id(settlement_id), _safe_id(occupation_id), day,
		],
		"subject_id": settlement_id,
		"title": "%s扩充%s岗位" % [
			_entity_name(snapshot, settlement_id),
			str(selected.get("label", occupation_id)),
		],
		"body": _facility_chronicle_body(
			pressure_days, str(stock.get("label", "本地材料")),
			slot_delta, organization_support
		),
		"source_fact_ids": [capacity_fact_id],
		"day": day,
	})
	available_resources[str(stock.get("stock_id", ""))] = (
		float(available_resources.get(str(stock.get("stock_id", "")), 0.0))
		- cost
	)
	events.append({
		"event_type": "settlement_facility_expanded",
		"settlement_id": settlement_id,
		"occupation_id": occupation_id,
		"workplace_id": str(selected.get("workplace_id", "")),
		"capacity_delta": slot_delta,
		"coordinator_organization_id": str(organization_support.get(
			"organization_id", ""
		)),
		"fact_id": capacity_fact_id,
		"day": day,
	})
	counts["facilities_expanded"] = int(counts.get(
		"facilities_expanded", 0
	)) + 1


func _append_work_capacity_change(
		result: Variant,
		snapshot: Variant,
		settlement_id: String,
		profile: Dictionary,
		delta: int,
		reason: String,
		capacity_before: int,
		capacity_after: int,
		day: int,
		source_values: Variant,
		facility_delta_changes: Dictionary,
		organization_support: Dictionary = {}
) -> String:
	var occupation_id := str(profile.get("occupation_id", ""))
	var workplace_id := str(profile.get("workplace_id", ""))
	var fact_id := "fact.settlement_work_capacity_changed.%s.%s.day%d.%s" % [
		_safe_id(settlement_id), _safe_id(occupation_id), day, _safe_id(reason),
	]
	var source_fact_ids: Array[String] = []
	if source_values is Array:
		for value: Variant in source_values:
			var source_fact_id := str(value)
			if source_fact_id != "" and source_fact_id not in source_fact_ids:
				source_fact_ids.append(source_fact_id)
	var settlement_fact := _settlement_generation_fact(snapshot, settlement_id)
	if settlement_fact != "" and settlement_fact not in source_fact_ids:
		source_fact_ids.append(settlement_fact)
	var fact := {
		"fact_id": fact_id,
		"fact_type": "settlement_work_capacity_changed",
		"actor_id": settlement_id,
		"target_id": settlement_id,
		"settlement_id": settlement_id,
		"occupation_id": occupation_id,
		"occupation_label": str(profile.get("label", occupation_id)),
		"workplace_id": workplace_id,
		"capacity_delta": delta,
		"capacity_before": capacity_before,
		"capacity_after": capacity_after,
		"reason": reason,
		"source_fact_ids": source_fact_ids,
		"day": day,
		"summary": _capacity_change_summary(
			snapshot, profile, reason, delta, capacity_after
		),
	}
	if not organization_support.is_empty():
		fact["coordinator_organization_id"] = str(
			organization_support.get("organization_id", "")
		)
		fact["coordinator_member_count"] = int(
			organization_support.get("member_count", 0)
		)
		fact["coordination_days_reduced"] = int(
			organization_support.get("pressure_day_reduction", 0)
		)
	result.add_fact(fact)
	var facility_id := str(profile.get("facility_entity_id", _facility_entity_id(snapshot, workplace_id)))
	if facility_id != "":
		var local_delta := int(facility_delta_changes.get(facility_id, 0)) + delta
		facility_delta_changes[facility_id] = local_delta
		result.add_state_change({
			"entity_id": facility_id,
			"key": "job_capacity_delta",
			"to": int(snapshot.get_entity_state(
				facility_id, "job_capacity_delta", 0
			)) + local_delta,
		})
		result.add_state_change({
			"entity_id": facility_id,
			"key": "facility_operational",
			"to": capacity_after > 0,
		})
	return fact_id


func _append_layoffs(
		result: Variant,
		snapshot: Variant,
		settlement_id: String,
		profile: Dictionary,
		capacity_after: int,
		capacity_fact_id: String,
		day: int,
		events: Array,
		counts: Dictionary,
		reason: String = "resource_depleted"
) -> void:
	var occupation_id := str(profile.get("occupation_id", ""))
	var workers := _workers(snapshot, settlement_id, occupation_id)
	if workers.size() <= capacity_after:
		return
	workers.sort_custom(func(a: String, b: String) -> bool:
		var blocked_a := int(snapshot.get_entity_state(
			a, "livelihood_blocked_count", 0
		))
		var blocked_b := int(snapshot.get_entity_state(
			b, "livelihood_blocked_count", 0
		))
		return blocked_a < blocked_b if blocked_a != blocked_b else a < b
	)
	for index: int in range(capacity_after, workers.size()):
		var resident_id := workers[index]
		var fact_id := "fact.resident_laid_off.%s.day%d" % [
			_safe_id(resident_id), day,
		]
		result.add_fact({
			"fact_id": fact_id,
			"fact_type": "resident_laid_off",
			"actor_id": settlement_id,
			"target_id": resident_id,
			"resident_id": resident_id,
			"settlement_id": settlement_id,
			"occupation_id": occupation_id,
			"occupation_label": str(profile.get("label", occupation_id)),
			"former_workplace_id": str(profile.get("workplace_id", "")),
			"reason": reason,
			"source_fact_ids": [capacity_fact_id],
			"day": day,
			"summary": "%s因设施停止经营而失去%s岗位。" % [
				_entity_name(snapshot, resident_id),
				str(profile.get("label", occupation_id)),
			],
		})
		for change: Dictionary in [
			{"key": "occupation_id", "to": "unemployed"},
			{"key": "livelihood_status", "to": "unemployed"},
			{"key": "workplace_id", "to": str(snapshot.get_entity_state(
				resident_id, "home_location_id", ""
			))},
			{"key": "livelihood_elapsed_hours", "to": 0},
		]:
			result.add_state_change({
				"entity_id": resident_id,
				"key": str(change.get("key", "")),
				"to": change.get("to"),
			})
		var entity: Dictionary = snapshot.get_entity(resident_id)
		var tags: Array = []
		for value: Variant in entity.get("tags", []):
			var tag := str(value)
			if not tag.begins_with("occupation_") and tag != "unemployed_resident":
				tags.append(tag)
		tags.append("unemployed_resident")
		result.add_entity_change({
			"operation": "update",
			"entity_id": resident_id,
			"fields": {
				"tags": tags,
				"description": "%d 岁的生成居民，原设施停止经营，正在重新寻找生计。" % int(
					snapshot.get_entity_state(resident_id, "age_years", 18)
				),
			},
			"source_fact_ids": [fact_id],
			"day": day,
		})
		result.add_chronicle_entry({
			"entry_id": "chronicle.resident_laid_off.%s.day%d" % [
				_safe_id(resident_id), day,
			],
			"subject_id": resident_id,
			"title": "%s失去%s岗位" % [
				_entity_name(snapshot, resident_id),
				str(profile.get("label", occupation_id)),
			],
			"body": "设施停止经营，岗位被真实关闭，居民转为求职状态。具体原因保留在来源事实中。",
			"source_fact_ids": [fact_id],
			"day": day,
		})
		events.append({
			"event_type": "resident_laid_off",
			"resident_id": resident_id,
			"settlement_id": settlement_id,
			"occupation_id": occupation_id,
			"fact_id": fact_id,
			"day": day,
		})
		counts["residents_laid_off"] = int(counts.get(
			"residents_laid_off", 0
		)) + 1


func _append_unmet_capacity_fact(
		result: Variant,
		snapshot: Variant,
		settlement_id: String,
		pressure_kind: String,
		reason: String,
		demand: int,
		capacity: int,
		day: int,
		config: Dictionary
) -> void:
	var interval := maxi(int(config.get(
		"unmet_pressure_fact_interval_days", 30
	)), 1)
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "settlement_capacity_pressure_unmet"
			and str(fact.get("settlement_id", "")) == settlement_id
			and str(fact.get("pressure_kind", "")) == pressure_kind
			and day - int(fact.get("day", 0)) < interval
		):
			return
	var fact_id := "fact.settlement_capacity_pressure_unmet.%s.%s.day%d" % [
		_safe_id(settlement_id), pressure_kind, day,
	]
	var source_fact_ids: Array[String] = []
	var settlement_fact_id := _settlement_generation_fact(
		snapshot, settlement_id
	)
	if settlement_fact_id != "":
		source_fact_ids.append(settlement_fact_id)
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "settlement_capacity_pressure_unmet",
		"actor_id": settlement_id,
		"target_id": settlement_id,
		"settlement_id": settlement_id,
		"pressure_kind": pressure_kind,
		"reason": reason,
		"demand": demand,
		"capacity": capacity,
		"source_fact_ids": source_fact_ids,
		"day": day,
		"summary": "%s已经出现%s压力，但当前条件不足以完成扩建。" % [
			_entity_name(snapshot, settlement_id),
			"住房" if pressure_kind == "housing" else "就业",
		],
	})


func _select_expansion_profile(
		snapshot: Variant,
		profiles: Array[Dictionary],
		unemployed: Array[String],
		settlement_id: String,
		config: Dictionary
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var maximum_extra := maxi(int(config.get(
		"maximum_extra_slots_per_occupation", 4
	)), 0)
	for profile: Dictionary in profiles:
		var condition := _profile_resource_condition(snapshot, profile, config)
		if not bool(condition.get("recovered", false)):
			continue
		var occupation_id := str(profile.get("occupation_id", ""))
		var base_capacity := maxi(int(profile.get("maximum_slots", 0)), 0)
		var current_capacity := maxi(
			base_capacity + _occupation_capacity_delta(
				snapshot, settlement_id, occupation_id
			), 0
		)
		if current_capacity >= base_capacity + maximum_extra:
			continue
		var score := int(round(float(condition.get("ratio", 1.0)) * 100.0))
		var bias: Dictionary = profile.get("attribute_bias", {})
		for resident_id: String in unemployed:
			var resident_score := 0
			for attribute: String in bias.keys():
				resident_score += int(snapshot.get_entity_state(
					resident_id, attribute, 0
				)) * int(bias.get(attribute, 0))
			score += resident_score
		var row := profile.duplicate(true)
		row["expansion_score"] = score
		row["resource_source_fact_ids"] = condition.get(
			"source_fact_ids", []
		)
		candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("expansion_score", 0)) != int(b.get("expansion_score", 0)):
			return int(a.get("expansion_score", 0)) > int(b.get("expansion_score", 0))
		return str(a.get("occupation_id", "")) < str(b.get("occupation_id", ""))
	)
	return candidates[0]


func _profile_resource_condition(
		snapshot: Variant, profile: Dictionary, config: Dictionary
) -> Dictionary:
	var inputs: Array = profile.get("resource_inputs", [])
	if inputs.is_empty():
		return {
			"depleted": false,
			"recovered": true,
			"ratio": 1.0,
			"source_fact_ids": [],
		}
	var depleted := false
	var recovered := true
	var minimum_ratio := 1.0
	var source_fact_ids: Array[String] = []
	var recovery_ratio := float(clampi(int(config.get(
		"resource_recovery_ratio_percent", 35
	)), 1, 100)) / 100.0
	for input_value: Variant in inputs:
		if not input_value is Dictionary:
			continue
		var input: Dictionary = input_value
		var stock: Dictionary = snapshot.get_resource_stock(str(
			input.get("stock_id", "")
		))
		if stock.is_empty():
			depleted = true
			recovered = false
			continue
		var current := float(stock.get("current", 0.0))
		var capacity := maxf(float(stock.get("capacity", 0.0)), 0.001)
		var required := maxf(
			float(input.get("amount_per_cycle", 0.0)),
			float(stock.get("operating_floor", 0.0))
		)
		var ratio := current / capacity
		minimum_ratio = minf(minimum_ratio, ratio)
		if current + 0.0001 < required:
			depleted = true
		if current + 0.0001 < required or ratio < recovery_ratio:
			recovered = false
		var established_fact_id := str(stock.get("established_fact_id", ""))
		if established_fact_id != "" and established_fact_id not in source_fact_ids:
			source_fact_ids.append(established_fact_id)
	return {
		"depleted": depleted,
		"recovered": recovered,
		"ratio": minimum_ratio,
		"source_fact_ids": source_fact_ids,
	}


func _select_construction_stock(
		snapshot: Variant,
		settlement_id: String,
		cost: float,
		available_resources: Dictionary,
		purpose: String = "industry_construction"
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for stock: Dictionary in snapshot.get_resource_stocks():
		var stock_id := str(stock.get("stock_id", ""))
		if (
			str(stock.get("settlement_id", "")) != settlement_id
			or str(stock.get("source_kind", "")) != "natural_resource"
			or float(available_resources.get(stock_id, 0.0)) + 0.0001 < cost
			or not _has_any_tag(stock.get("tags", []), CONSTRUCTION_TAGS)
			or not Access.manager_allows(stock, settlement_id, purpose)
		):
			continue
		var row := stock.duplicate(true)
		row["available"] = float(available_resources.get(stock_id, 0.0))
		candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ratio_a := float(a.get("available", 0.0)) / maxf(
			float(a.get("capacity", 0.0)), 0.001
		)
		var ratio_b := float(b.get("available", 0.0)) / maxf(
			float(b.get("capacity", 0.0)), 0.001
		)
		if not is_equal_approx(ratio_a, ratio_b):
			return ratio_a > ratio_b
		return str(a.get("stock_id", "")) < str(b.get("stock_id", ""))
	)
	return candidates[0]


func _next_construction_plot(
		locations: Array, built_plots: Dictionary, settlement_id: String
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for value: Variant in locations:
		if not value is Dictionary:
			continue
		var location: Dictionary = value
		var plot_id := str(location.get("id", ""))
		if (
			str(location.get("settlement_id", "")) == settlement_id
			and "settlement_construction_plot" in (
				location.get("tags", []) as Array
			)
			and not built_plots.has(plot_id)
		):
			candidates.append(location)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return {} if candidates.is_empty() else candidates[0]


func _built_plots(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) == "settlement_dwelling_constructed":
			rows[str(fact.get("home_location_id", ""))] = true
		elif str(fact.get("fact_type", "")) == "settlement_industry_founded":
			rows[str(fact.get("workplace_id", ""))] = true
	rows.erase("")
	return rows


func _occupation_capacity_delta(
		snapshot: Variant, settlement_id: String, occupation_id: String
) -> int:
	var delta := 0
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "settlement_work_capacity_changed"
			and str(fact.get("settlement_id", "")) == settlement_id
			and str(fact.get("occupation_id", "")) == occupation_id
		):
			delta += int(fact.get("capacity_delta", 0))
	return delta


func _latest_capacity_change(
		snapshot: Variant, settlement_id: String, occupation_id: String
) -> Dictionary:
	var latest: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) != "settlement_work_capacity_changed"
			or str(fact.get("settlement_id", "")) != settlement_id
			or str(fact.get("occupation_id", "")) != occupation_id
		):
			continue
		if (
			latest.is_empty()
			or int(fact.get("day", 0)) > int(latest.get("day", 0))
			or (
				int(fact.get("day", 0)) == int(latest.get("day", 0))
				and str(fact.get("fact_id", "")) > str(latest.get("fact_id", ""))
			)
		):
			latest = fact
	return latest


func _profiles_for_settlement(
		profiles: Array, settlement_id: String
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for value: Variant in profiles:
		if value is Dictionary and str((value as Dictionary).get(
			"settlement_id", ""
		)) == settlement_id:
			rows.append((value as Dictionary).duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("occupation_id", "")) < str(b.get("occupation_id", ""))
	)
	return rows


func _unemployed_residents(
		snapshot: Variant, settlement_id: String
) -> Array[String]:
	var rows: Array[String] = []
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			person_id != "player"
			and str(snapshot.get_entity_state(
				person_id, "settlement_id", ""
			)) == settlement_id
			and str(snapshot.get_entity_state(
				person_id, "life_status", "alive"
			)) == "alive"
			and int(snapshot.get_entity_state(person_id, "age_years", 0)) >= 18
			and str(snapshot.get_entity_state(
				person_id, "livelihood_status", ""
			)) == "unemployed"
		):
			rows.append(person_id)
	rows.sort()
	return rows


func _workers(
		snapshot: Variant, settlement_id: String, occupation_id: String
) -> Array[String]:
	var rows: Array[String] = []
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			str(snapshot.get_entity_state(
				person_id, "settlement_id", ""
			)) == settlement_id
			and str(snapshot.get_entity_state(
				person_id, "occupation_id", ""
			)) == occupation_id
			and str(snapshot.get_entity_state(
				person_id, "livelihood_status", ""
			)) in ["employed", "self_employed"]
			and str(snapshot.get_entity_state(
				person_id, "life_status", "alive"
			)) == "alive"
		):
			rows.append(person_id)
	rows.sort()
	return rows


func _worker_count(
		snapshot: Variant, settlement_id: String, occupation_id: String
) -> int:
	return _workers(snapshot, settlement_id, occupation_id).size()


func _settlement_population(snapshot: Variant, settlement_id: String) -> int:
	var count := 0
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			person_id != "player"
			and str(snapshot.get_entity_state(
				person_id, "settlement_id", ""
			)) == settlement_id
			and str(snapshot.get_entity_state(
				person_id, "life_status", "alive"
			)) == "alive"
		):
			count += 1
	return count


func _settlement_ids(network_config: Dictionary) -> Array[String]:
	var rows: Array[String] = []
	for value: Variant in network_config.get("sites", []):
		if value is Dictionary:
			var settlement_id := str((value as Dictionary).get(
				"settlement_id", ""
			))
			if settlement_id != "" and settlement_id not in rows:
				rows.append(settlement_id)
	rows.sort()
	return rows


func _organization_support(
		snapshot: Variant, settlement_id: String, config: Dictionary
) -> Dictionary:
	var minimum_members := maxi(int(config.get(
		"minimum_organization_members_for_coordination", 1
	)), 1)
	var candidates: Array[Dictionary] = []
	for entity: Dictionary in snapshot.get_entities():
		var tags: Array = entity.get("tags", [])
		var organization_id := str(entity.get("id", ""))
		if (
			"generated_organization" not in tags
			or str(entity.get("settlement_id", "")) != settlement_id
			or organization_id == ""
		):
			continue
		var member_count := _active_organization_member_count(
			snapshot, settlement_id, organization_id
		)
		if member_count < minimum_members:
			continue
		candidates.append({
			"organization_id": organization_id,
			"display_name": str(entity.get("display_name", organization_id)),
			"member_count": member_count,
			"source_fact_id": _organization_source_fact_id(
				snapshot, organization_id
			),
		})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_count := int(a.get("member_count", 0))
		var b_count := int(b.get("member_count", 0))
		if a_count == b_count:
			return str(a.get("organization_id", "")) < str(b.get(
				"organization_id", ""
			))
		return a_count > b_count
	)
	var selected := candidates[0].duplicate(true)
	var days_per_member := maxi(int(config.get(
		"organization_coordination_days_per_member", 2
	)), 0)
	var maximum_reduction := maxi(int(config.get(
		"organization_coordination_max_reduction_days", 8
	)), 0)
	selected["pressure_day_reduction"] = mini(
		int(selected.get("member_count", 0)) * days_per_member,
		maximum_reduction
	)
	return selected


func _active_organization_member_count(
		snapshot: Variant, settlement_id: String, organization_id: String
) -> int:
	var role_prefix := "%s::" % organization_id
	var count := 0
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			str(snapshot.get_entity_state(
				person_id, "settlement_id", ""
			)) == settlement_id
			and str(snapshot.get_entity_state(
				person_id, "life_status", "alive"
			)) == "alive"
			and str(snapshot.get_entity_state(
				person_id, "institution_role", ""
			)).begins_with(role_prefix)
		):
			count += 1
	return count


func _organization_source_fact_id(
		snapshot: Variant, organization_id: String
) -> String:
	var matches: Array[Dictionary] = []
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) in [
				"organization_generated", "organization_runtime_formed",
			]
			and (
				str(fact.get("target_id", "")) == organization_id
				or str(fact.get("organization_id", "")) == organization_id
			)
		):
			matches.append(fact)
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_day := int(a.get("day", 0))
		var b_day := int(b.get("day", 0))
		if a_day == b_day:
			return str(a.get("fact_id", "")) < str(b.get("fact_id", ""))
		return a_day > b_day
	)
	return "" if matches.is_empty() else str(matches[0].get("fact_id", ""))


func _required_pressure_days(
		base_required_days: int, organization_support: Dictionary
) -> int:
	var base_days := maxi(base_required_days, 1)
	var reduction := clampi(int(organization_support.get(
		"pressure_day_reduction", 0
	)), 0, base_days - 1)
	return base_days - reduction


func _append_organization_source(
		source_fact_ids: Array, organization_support: Dictionary
) -> void:
	var organization_fact_id := str(organization_support.get(
		"source_fact_id", ""
	))
	if (
		organization_fact_id != ""
		and organization_fact_id not in source_fact_ids
	):
		source_fact_ids.append(organization_fact_id)


func _dwelling_summary(
		snapshot: Variant,
		settlement_id: String,
		organization_support: Dictionary
) -> String:
	var coordinator := _coordination_label(organization_support)
	return "%s因人口持续逼近承载上限，由%s把一处预留地块建成了住屋。" % [
		_entity_name(snapshot, settlement_id), coordinator,
	]


func _dwelling_chronicle_body(
		pressure_days: int,
		material_label: String,
		organization_support: Dictionary
) -> String:
	return "连续 %d 天的人口压力促使%s使用%s，在预留地块建成可被家庭实际占用的住屋。" % [
		pressure_days, _coordination_label(organization_support), material_label,
	]


func _facility_chronicle_body(
		pressure_days: int,
		material_label: String,
		slot_delta: int,
		organization_support: Dictionary
) -> String:
	return "连续 %d 天没有空缺岗位后，%s使用%s扩建设施，新增 %d 个真实岗位。" % [
		pressure_days, _coordination_label(organization_support),
		material_label, slot_delta,
	]


func _coordination_label(organization_support: Dictionary) -> String:
	if organization_support.is_empty():
		return "当地居民自行协调"
	return "%s的 %d 名在岗成员协调居民" % [
		str(organization_support.get("display_name", "当地组织")),
		int(organization_support.get("member_count", 0)),
	]


func _available_resource_amounts(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for stock: Dictionary in snapshot.get_resource_stocks():
		rows[str(stock.get("stock_id", ""))] = float(stock.get("current", 0.0))
	return rows


func _source_fact_ids(
		snapshot: Variant,
		settlement_id: String,
		plot_id: String,
		stock_id: String
) -> Array[String]:
	var rows: Array[String] = []
	var settlement_fact := _settlement_generation_fact(snapshot, settlement_id)
	if settlement_fact != "":
		rows.append(settlement_fact)
	for fact: Dictionary in snapshot.get_facts():
		if (
			plot_id != ""
			and str(fact.get("fact_type", "")) == "settlement_construction_plot_generated"
			and str(fact.get("plot_location_id", "")) == plot_id
		):
			rows.append(str(fact.get("fact_id", "")))
	for stock: Dictionary in snapshot.get_resource_stocks():
		if (
			str(stock.get("stock_id", "")) == stock_id
			and str(stock.get("established_fact_id", "")) != ""
		):
			var fact_id := str(stock.get("established_fact_id", ""))
			if fact_id not in rows:
				rows.append(fact_id)
	var cleaned: Array[String] = []
	for fact_id: String in rows:
		if fact_id != "" and fact_id not in cleaned:
			cleaned.append(fact_id)
	return cleaned


func _settlement_generation_fact(
		snapshot: Variant, settlement_id: String
) -> String:
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "settlement_generated"
			and str(fact.get("target_id", "")) == settlement_id
		):
			return str(fact.get("fact_id", ""))
	return ""


func _facility_entity_id(snapshot: Variant, workplace_id: String) -> String:
	var candidates: Array[String] = []
	for entity: Dictionary in snapshot.get_entities():
		var entity_id := str(entity.get("id", ""))
		if (
			str(snapshot.get_entity_state(entity_id, "location_id", ""))
			== workplace_id
			and "generated_facility" in (entity.get("tags", []) as Array)
		):
			candidates.append(entity_id)
	candidates.sort()
	return "" if candidates.is_empty() else candidates[0]


func _cooldown_ready(
		snapshot: Variant,
		settlement_id: String,
		fact_type: String,
		day: int,
		cooldown_days: int,
		reasons: Array = []
) -> bool:
	var latest_day := -1000000
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) != fact_type
			or str(fact.get("settlement_id", fact.get("target_id", "")))
			!= settlement_id
			or (
				not reasons.is_empty()
				and str(fact.get("reason", "")) not in reasons
			)
		):
			continue
		latest_day = maxi(latest_day, int(fact.get("day", 0)))
	return day - latest_day >= cooldown_days


func _capacity_change_summary(
		snapshot: Variant,
		profile: Dictionary,
		reason: String,
		delta: int,
		capacity_after: int
) -> String:
	var settlement_name := _entity_name(
		snapshot, str(profile.get("settlement_id", ""))
	)
	var occupation_label := str(profile.get(
		"label", profile.get("occupation_id", "岗位")
	))
	match reason:
		"industry_founded":
			return "%s因新产业开办而新设 %d 个%s岗位。" % [
				settlement_name, capacity_after, occupation_label,
			]
		"industry_retired":
			return "%s的%s设施停止经营，该产业岗位关闭至 %d 个。" % [
				settlement_name, occupation_label, capacity_after,
			]
		"resource_depleted":
			return "%s的生产资源跌破开工水位，%s岗位关闭至 %d 个。" % [
				settlement_name, occupation_label, capacity_after,
			]
		"resource_recovered":
			return "%s的生产资源恢复，%s重新开放 %d 个岗位。" % [
				settlement_name, occupation_label, delta,
			]
	return "%s因持续就业压力扩建设施，新增 %d 个%s岗位。" % [
		settlement_name, delta, occupation_label,
	]


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	var entity: Dictionary = snapshot.get_entity(entity_id)
	return str(entity.get("display_name", entity_id)) if not entity.is_empty() else entity_id


func _has_any_tag(source_values: Variant, expected: Array) -> bool:
	if not source_values is Array:
		return false
	for value: Variant in source_values:
		if str(value) in expected:
			return true
	return false


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")
