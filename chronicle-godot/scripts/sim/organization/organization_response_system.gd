extends RefCounted
class_name V5OrganizationResponseSystem

const Access = preload("res://scripts/sim/resource/resource_access.gd")

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const RoutePressureQueryModel = preload(
	"res://scripts/sim/resource/route_pressure_query.gd"
)

const EPSILON := 0.0001
const PRESSURE_RANK := {"low": 0, "medium": 1, "high": 2}


func resolve_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		_config: Dictionary,
		network_config: Dictionary
) -> Dictionary:
	var day := int(tick_event.get("day", 0))
	if day <= 0 or network_config.is_empty():
		return {"results": [], "events": []}
	var results: Array = []
	var events: Array = []
	var available := _available_amounts(snapshot.get_resource_stocks())
	for organization: Dictionary in _organizations(snapshot):
		var response: Dictionary = organization.get("runtime_response", {})
		var action_kind := str(response.get("action_kind", ""))
		if (
			action_kind == ""
			or _staffed_position_count(snapshot, organization)
			< maxi(int(response.get("minimum_staffed_positions", 1)), 1)
		):
			continue
		var fact_id := "fact.organization_action.%s.%s.day%d" % [
			_safe_id(str(organization.get("id", ""))),
			_safe_id(action_kind),
			day,
		]
		if _fact_exists(snapshot, fact_id) or _fact_exists(snapshot, fact_id + ".denied"):
			continue
		var planned_available := available.duplicate()
		var resolution: Dictionary = {}
		match action_kind:
			"local_provisioning":
				resolution = _resolve_local_provisioning(
					snapshot, organization, response, tick_event, fact_id, planned_available
				)
			"trade_coordination":
				resolution = _resolve_trade_coordination(
					snapshot,
					organization,
					response,
					tick_event,
					fact_id,
					planned_available,
					network_config
				)
			"route_patrol":
				resolution = _resolve_route_patrol(
					snapshot,
					organization,
					response,
					tick_event,
					fact_id,
					planned_available,
					network_config
				)
		if resolution.is_empty():
			continue
		var result: Variant = resolution.get("result")
		var denied := ""
		for change: Dictionary in result.resource_changes:
			change["actor_id"] = str(organization["id"])
			change["day"] = day
			denied = Access.denial(snapshot, snapshot.get_resource_stock(str(change.get("stock_id", ""))),
				str(organization["id"]), str(change.get("reason", "")), float(change.get("amount", 0)), day)
			if denied != "":
				break
		if denied != "":
			var blocked = TransactionResultModel.new()
			blocked.add_fact({"fact_id": fact_id + ".denied", "fact_type": "organization_resource_access_blocked",
				"actor_id": str(organization["id"]), "target_id": str(organization.get("settlement_id", "")),
				"day": day, "reason": denied, "summary": "%s未能执行计划：资源使用许可或当天额度不足。" % organization.get("display_name", "组织")})
			blocked.mark_resolved("organization_resource_access_blocked")
			results.append(blocked)
			continue
		available = planned_available
		var summary := str(resolution.get("summary", "地方组织完成了例行响应。"))
		for change: Dictionary in [
			{"key": "last_response_day", "to": day},
			{"key": "last_response_kind", "to": action_kind},
			{"key": "last_response_summary", "to": summary},
			{"key": "last_response_fact_id", "to": fact_id},
		]:
			result.add_state_change({
				"entity_id": str(organization.get("id", "")),
				"key": str(change.get("key", "")),
				"to": change.get("to"),
			})
		result.mark_resolved("organization_pressure_response")
		results.append(result)
		events.append((resolution.get("event", {}) as Dictionary).duplicate(true))
	return {"results": results, "events": events}


func _resolve_local_provisioning(
		snapshot: Variant,
		organization: Dictionary,
		response: Dictionary,
		tick_event: Dictionary,
		fact_id: String,
		available: Dictionary
) -> Dictionary:
	var settlement_id := str(organization.get("settlement_id", ""))
	var food_pressure := str(snapshot.get_entity_state(
		settlement_id, "food_pressure", "low"
	))
	if food_pressure not in (response.get(
		"trigger_food_pressure", ["medium", "high"]
	) as Array):
		return {}
	var linked_stock_ids: Array = organization.get("resource_stock_ids", [])
	var source_stock := _best_local_food_source(
		snapshot.get_resource_stocks(), settlement_id, linked_stock_ids, available
	)
	var reserve_stock := _best_local_food_reserve(
		snapshot.get_resource_stocks(), settlement_id, linked_stock_ids, available
	)
	if source_stock.is_empty() or reserve_stock.is_empty():
		return {}
	var source_stock_id := str(source_stock.get("stock_id", ""))
	var reserve_stock_id := str(reserve_stock.get("stock_id", ""))
	var transferable := maxf(
		float(available.get(source_stock_id, 0.0))
		- float(source_stock.get("operating_floor", 1.0)),
		0.0
	)
	var reserve_free := maxf(
		float(reserve_stock.get("capacity", 0.0))
		- float(available.get(reserve_stock_id, 0.0)),
		0.0
	)
	var amount := minf(
		maxf(float(response.get("amount_per_action", 1.0)), 0.1),
		minf(transferable, reserve_free)
	)
	if amount <= EPSILON:
		return {}
	available[source_stock_id] = float(available.get(
		source_stock_id, 0.0
	)) - amount
	available[reserve_stock_id] = float(available.get(
		reserve_stock_id, 0.0
	)) + amount
	var source_fact_ids := _source_fact_ids(
		snapshot, organization, settlement_id, [source_stock, reserve_stock]
	)
	var result = TransactionResultModel.new()
	result.add_resource_change({
		"operation": "consume",
		"stock_id": source_stock_id,
		"amount": amount,
		"tick": _tick_value(tick_event),
		"reason": "organization_local_provisioning_source",
		"source_fact_ids": [fact_id],
	})
	result.add_resource_change({
		"operation": "adjust",
		"stock_id": reserve_stock_id,
		"amount": amount,
		"tick": _tick_value(tick_event),
		"reason": "organization_local_provisioning_reserve",
		"source_fact_ids": [fact_id],
	})
	var summary := "%s把 %.1f 份%s转入%s，没有凭空增加食物。" % [
		_entity_name(snapshot, str(organization.get("id", ""))),
		amount,
		str(source_stock.get("label", "本地食物")),
		str(reserve_stock.get("label", "口粮储备")),
	]
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "organization_local_provisions_transferred",
		"actor_id": str(organization.get("id", "")),
		"target_id": settlement_id,
		"organization_id": str(organization.get("id", "")),
		"settlement_id": settlement_id,
		"source_stock_id": source_stock_id,
		"destination_stock_id": reserve_stock_id,
		"amount": amount,
		"food_pressure": food_pressure,
		"source_fact_ids": source_fact_ids,
		"day": int(tick_event.get("day", 0)),
		"summary": summary,
	})
	result.add_pressure_change({
		"pressure_id": "pressure.organization_provisioning.%s.day%d" % [
			_safe_id(str(organization.get("id", ""))),
			int(tick_event.get("day", 0)),
		],
		"domain": "organization",
		"scope_id": settlement_id,
		"pressure_type": "food_coordination_relief",
		"value": -maxi(int(round(amount)), 1),
		"source_fact_ids": [fact_id],
	})
	result.set_narrative_result({
		"title": "%s调入本地口粮" % _entity_name(
			snapshot, str(organization.get("id", ""))
		),
		"summary": summary,
		"tone": "organization_provisioning",
	})
	return {
		"result": result,
		"summary": summary,
		"event": {
			"event_type": "organization_response_executed",
			"action_kind": "local_provisioning",
			"organization_id": str(organization.get("id", "")),
			"settlement_id": settlement_id,
			"amount": amount,
			"fact_id": fact_id,
		},
	}


func _resolve_trade_coordination(
		snapshot: Variant,
		organization: Dictionary,
		response: Dictionary,
		tick_event: Dictionary,
		fact_id: String,
		available: Dictionary,
		network_config: Dictionary
) -> Dictionary:
	var settlement_id := str(organization.get("settlement_id", ""))
	var target := _best_stressed_neighbor(
		snapshot,
		settlement_id,
		network_config.get("links", []),
		response.get("trigger_neighbor_food_pressure", ["medium", "high"])
	)
	if target.is_empty():
		return {}
	var traffic_cost := maxf(float(response.get("traffic_cost", 1.0)), 0.1)
	var traffic_stock := _best_road_stock(
		snapshot.get_resource_stocks(),
		settlement_id,
		organization.get("resource_stock_ids", []),
		available,
		traffic_cost
	)
	if traffic_stock.is_empty():
		return {}
	var stock_id := str(traffic_stock.get("stock_id", ""))
	available[stock_id] = float(available.get(stock_id, 0.0)) - traffic_cost
	var duration_days := maxi(int(response.get("duration_days", 1)), 1)
	var capacity_bonus := maxf(float(response.get("capacity_bonus", 1.0)), 0.1)
	var until_day := int(tick_event.get("day", 0)) + duration_days
	var source_fact_ids := _source_fact_ids(
		snapshot, organization, str(target.get("neighbor_id", "")), [traffic_stock]
	)
	var result = TransactionResultModel.new()
	result.add_resource_change({
		"operation": "consume",
		"stock_id": stock_id,
		"amount": traffic_cost,
		"tick": _tick_value(tick_event),
		"reason": "organization_trade_coordination",
		"source_fact_ids": [fact_id],
	})
	result.add_state_change({
		"entity_id": settlement_id,
		"key": "organization_trade_coordination",
		"to": {
			"organization_id": str(organization.get("id", "")),
			"link_id": str(target.get("link_id", "")),
			"target_settlement_id": str(target.get("neighbor_id", "")),
			"capacity_bonus": capacity_bonus,
			"until_day": until_day,
			"source_fact_id": fact_id,
		},
	})
	var summary := "%s消耗 %.1f 份%s，为通往%s的道路协调次日 %.1f 份额外运力。" % [
		_entity_name(snapshot, str(organization.get("id", ""))),
		traffic_cost,
		str(traffic_stock.get("label", "道路运力")),
		_entity_name(snapshot, str(target.get("neighbor_id", ""))),
		capacity_bonus,
	]
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "organization_trade_coordinated",
		"actor_id": str(organization.get("id", "")),
		"target_id": str(target.get("neighbor_id", "")),
		"organization_id": str(organization.get("id", "")),
		"settlement_id": settlement_id,
		"target_settlement_id": str(target.get("neighbor_id", "")),
		"link_id": str(target.get("link_id", "")),
		"traffic_stock_id": stock_id,
		"traffic_cost": traffic_cost,
		"capacity_bonus": capacity_bonus,
		"effective_until_day": until_day,
		"source_fact_ids": source_fact_ids,
		"day": int(tick_event.get("day", 0)),
		"summary": summary,
	})
	result.add_pressure_change({
		"pressure_id": "pressure.organization_trade.%s.day%d" % [
			_safe_id(str(organization.get("id", ""))),
			int(tick_event.get("day", 0)),
		],
		"domain": "organization",
		"scope_id": str(target.get("neighbor_id", "")),
		"pressure_type": "trade_coordination_relief",
		"value": -maxi(int(round(capacity_bonus)), 1),
		"source_fact_ids": [fact_id],
	})
	result.set_narrative_result({
		"title": "%s协调了紧急货路" % _entity_name(
			snapshot, str(organization.get("id", ""))
		),
		"summary": summary,
		"tone": "organization_trade_coordination",
	})
	return {
		"result": result,
		"summary": summary,
		"event": {
			"event_type": "organization_response_executed",
			"action_kind": "trade_coordination",
			"organization_id": str(organization.get("id", "")),
			"settlement_id": settlement_id,
			"target_settlement_id": str(target.get("neighbor_id", "")),
			"link_id": str(target.get("link_id", "")),
			"fact_id": fact_id,
		},
	}


func _resolve_route_patrol(
		snapshot: Variant,
		organization: Dictionary,
		response: Dictionary,
		tick_event: Dictionary,
		fact_id: String,
		available: Dictionary,
		network_config: Dictionary
) -> Dictionary:
	var settlement_id := str(organization.get("settlement_id", ""))
	var link := _highest_risk_link(
		snapshot,
		settlement_id,
		network_config.get("links", []),
		maxi(int(response.get("minimum_route_risk", 1)), 0),
		int(tick_event.get("day", 0))
	)
	if link.is_empty():
		return {}
	var traffic_cost := maxf(float(response.get("traffic_cost", 1.0)), 0.1)
	var traffic_stock := _best_road_stock(
		snapshot.get_resource_stocks(),
		settlement_id,
		organization.get("resource_stock_ids", []),
		available,
		traffic_cost
	)
	if traffic_stock.is_empty():
		return {}
	var stock_id := str(traffic_stock.get("stock_id", ""))
	available[stock_id] = float(available.get(stock_id, 0.0)) - traffic_cost
	var duration_days := maxi(int(response.get("duration_days", 1)), 1)
	var until_day := int(tick_event.get("day", 0)) + duration_days
	var risk_reduction := maxi(int(response.get("risk_reduction", 1)), 1)
	var cost_reduction := maxf(float(response.get(
		"transport_cost_reduction", 0.1
	)), 0.0)
	var source_fact_ids := _source_fact_ids(
		snapshot, organization, settlement_id, [traffic_stock]
	)
	for source_value: Variant in link.get("pressure_source_fact_ids", []):
		_append_unique(source_fact_ids, str(source_value))
	var link_label := _link_label(snapshot, link)
	var result = TransactionResultModel.new()
	result.add_resource_change({
		"operation": "consume",
		"stock_id": stock_id,
		"amount": traffic_cost,
		"tick": _tick_value(tick_event),
		"reason": "organization_route_patrol",
		"source_fact_ids": [fact_id],
	})
	result.add_state_change({
		"entity_id": settlement_id,
		"key": "organization_route_watch",
		"to": {
			"organization_id": str(organization.get("id", "")),
			"link_id": str(link.get("link_id", "")),
			"risk_reduction": risk_reduction,
			"transport_cost_reduction": cost_reduction,
			"until_day": until_day,
			"source_fact_id": fact_id,
		},
	})
	var summary := "%s投入 %.1f 份%s，巡守%s，使次日道路风险降低 %d 级。" % [
		_entity_name(snapshot, str(organization.get("id", ""))),
		traffic_cost,
		str(traffic_stock.get("label", "道路运力")),
		link_label,
		risk_reduction,
	]
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "organization_route_patrolled",
		"actor_id": str(organization.get("id", "")),
		"target_id": settlement_id,
		"organization_id": str(organization.get("id", "")),
		"settlement_id": settlement_id,
		"link_id": str(link.get("link_id", "")),
		"link_label": link_label,
		"base_risk": int(link.get("risk", 0)),
		"environment_risk_increase": int(link.get(
			"environment_risk_increase", 0
		)),
		"effective_risk_before_patrol": int(link.get(
			"effective_risk", link.get("risk", 0)
		)),
		"traffic_stock_id": stock_id,
		"traffic_cost": traffic_cost,
		"risk_reduction": risk_reduction,
		"transport_cost_reduction": cost_reduction,
		"effective_until_day": until_day,
		"source_fact_ids": source_fact_ids,
		"day": int(tick_event.get("day", 0)),
		"summary": summary,
	})
	result.add_pressure_change({
		"pressure_id": "pressure.organization_watch.%s.day%d" % [
			_safe_id(str(organization.get("id", ""))),
			int(tick_event.get("day", 0)),
		],
		"domain": "organization",
		"scope_id": settlement_id,
		"pressure_type": "route_security_relief",
		"value": -risk_reduction,
		"source_fact_ids": [fact_id],
	})
	result.set_narrative_result({
		"title": "%s派出了道路巡守" % _entity_name(
			snapshot, str(organization.get("id", ""))
		),
		"summary": summary,
		"tone": "organization_route_patrol",
	})
	return {
		"result": result,
		"summary": summary,
		"event": {
			"event_type": "organization_response_executed",
			"action_kind": "route_patrol",
			"organization_id": str(organization.get("id", "")),
			"settlement_id": settlement_id,
			"link_id": str(link.get("link_id", "")),
			"fact_id": fact_id,
		},
	}


func _organizations(snapshot: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entity: Dictionary in snapshot.get_entities():
		if (
			"generated_organization" in (entity.get("tags", []) as Array)
			and str(entity.get("lifecycle_status", "active")) != "retired"
		):
			rows.append(entity)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return rows


func _staffed_position_count(snapshot: Variant, organization: Dictionary) -> int:
	var expected_roles: Dictionary = {}
	var organization_id := str(organization.get("id", ""))
	for position_value: Variant in organization.get("positions", []):
		if position_value is Dictionary:
			expected_roles["%s::%s" % [
				organization_id,
				str((position_value as Dictionary).get("position_id", "")),
			]] = true
	var count := 0
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		if expected_roles.has(str(snapshot.get_entity_state(
			str(person.get("id", "")), "institution_role", ""
		))):
			count += 1
	return count


func _best_local_food_source(
		stocks: Array,
		settlement_id: String,
		linked_stock_ids: Array,
		available: Dictionary
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for stock: Dictionary in stocks:
		var stock_id := str(stock.get("stock_id", ""))
		var transferable := float(available.get(stock_id, 0.0)) - float(
			stock.get("operating_floor", 1.0)
		)
		if (
			str(stock.get("settlement_id", "")) == settlement_id
			and str(stock.get("source_kind", "")) == "natural_resource"
			and "food" in (stock.get("tags", []) as Array)
			and stock_id in linked_stock_ids
			and transferable > EPSILON
		):
			var row := stock.duplicate(true)
			row["transferable"] = transferable
			candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(
			float(a.get("transferable", 0.0)),
			float(b.get("transferable", 0.0))
		):
			return float(a.get("transferable", 0.0)) > float(b.get("transferable", 0.0))
		return str(a.get("stock_id", "")) < str(b.get("stock_id", ""))
	)
	return candidates[0]


func _best_local_food_reserve(
		stocks: Array,
		settlement_id: String,
		linked_stock_ids: Array,
		available: Dictionary
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for stock: Dictionary in stocks:
		var stock_id := str(stock.get("stock_id", ""))
		var free := float(stock.get("capacity", 0.0)) - float(
			available.get(stock_id, 0.0)
		)
		if (
			str(stock.get("settlement_id", "")) == settlement_id
			and str(stock.get("source_kind", "")) == "trade_reserve"
			and "food" in (stock.get("tags", []) as Array)
			and stock_id in linked_stock_ids
			and free > EPSILON
		):
			var row := stock.duplicate(true)
			row["free"] = free
			candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.get("free", 0.0)), float(b.get("free", 0.0))):
			return float(a.get("free", 0.0)) > float(b.get("free", 0.0))
		return str(a.get("stock_id", "")) < str(b.get("stock_id", ""))
	)
	return candidates[0]


func _best_road_stock(
		stocks: Array,
		settlement_id: String,
		linked_stock_ids: Array,
		available: Dictionary,
		minimum: float
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for stock: Dictionary in stocks:
		if (
			str(stock.get("settlement_id", "")) == settlement_id
			and str(stock.get("source_kind", "")) == "traffic_capacity"
			and "road" in (stock.get("tags", []) as Array)
			and str(stock.get("stock_id", "")) in linked_stock_ids
			and float(available.get(str(stock.get("stock_id", "")), 0.0))
			>= minimum
		):
			candidates.append(stock.duplicate(true))
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := float(available.get(str(a.get("stock_id", "")), 0.0))
		var right := float(available.get(str(b.get("stock_id", "")), 0.0))
		return left > right if not is_equal_approx(left, right) else str(
			a.get("stock_id", "")
		) < str(b.get("stock_id", ""))
	)
	return candidates[0]


func _best_stressed_neighbor(
		snapshot: Variant,
		settlement_id: String,
		link_values: Variant,
		trigger_value: Variant
) -> Dictionary:
	var trigger_states: Array = trigger_value if trigger_value is Array else []
	var candidates: Array[Dictionary] = []
	for link: Dictionary in _dictionary_rows(link_values):
		if float(link.get("capacity_per_day", 0.0)) <= EPSILON:
			continue
		var neighbor_id := _neighbor_id(link, settlement_id)
		if neighbor_id == "":
			continue
		var pressure := str(snapshot.get_entity_state(
			neighbor_id, "food_pressure", "low"
		))
		if pressure not in trigger_states:
			continue
		var row := link.duplicate(true)
		row["neighbor_id"] = neighbor_id
		row["food_pressure"] = pressure
		candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left_rank := int(PRESSURE_RANK.get(str(a.get("food_pressure", "low")), 0))
		var right_rank := int(PRESSURE_RANK.get(str(b.get("food_pressure", "low")), 0))
		if left_rank != right_rank:
			return left_rank > right_rank
		if int(a.get("risk", 0)) != int(b.get("risk", 0)):
			return int(a.get("risk", 0)) > int(b.get("risk", 0))
		return str(a.get("link_id", "")) < str(b.get("link_id", ""))
	)
	return candidates[0]


func _highest_risk_link(
		snapshot: Variant,
		settlement_id: String,
		link_values: Variant,
		minimum_risk: int,
		day: int
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for link: Dictionary in _dictionary_rows(link_values):
		var pressure := RoutePressureQueryModel.new().active_pressure(
			snapshot, str(link.get("link_id", "")), day
		)
		var effective_risk := int(link.get("risk", 0)) + int(
			pressure.get("risk_increase", 0)
		)
		if (
			float(link.get("capacity_per_day", 0.0)) > EPSILON
			and _neighbor_id(link, settlement_id) != ""
			and effective_risk >= minimum_risk
		):
			var row := link.duplicate(true)
			row["effective_risk"] = effective_risk
			row["environment_risk_increase"] = int(pressure.get(
				"risk_increase", 0
			))
			row["pressure_source_fact_ids"] = (
				pressure.get("source_fact_ids", []) as Array
			).duplicate()
			candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("effective_risk", 0)) != int(b.get("effective_risk", 0)):
			return int(a.get("effective_risk", 0)) > int(b.get("effective_risk", 0))
		return str(a.get("link_id", "")) < str(b.get("link_id", ""))
	)
	return candidates[0]


func _neighbor_id(link: Dictionary, settlement_id: String) -> String:
	if str(link.get("settlement_a_id", "")) == settlement_id:
		return str(link.get("settlement_b_id", ""))
	if str(link.get("settlement_b_id", "")) == settlement_id:
		return str(link.get("settlement_a_id", ""))
	return ""


func _link_label(snapshot: Variant, link: Dictionary) -> String:
	var settlement_a := _entity_name(
		snapshot, str(link.get("settlement_a_id", ""))
	)
	var settlement_b := _entity_name(
		snapshot, str(link.get("settlement_b_id", ""))
	)
	if settlement_a == "" or settlement_b == "":
		return "区域道路"
	return "%s至%s道路" % [settlement_a, settlement_b]


func _source_fact_ids(
		snapshot: Variant,
		organization: Dictionary,
		pressure_settlement_id: String,
		stocks: Array
) -> Array[String]:
	var rows: Array[String] = []
	for value: Variant in organization.get("source_fact_ids", []):
		_append_unique(rows, str(value))
	for stock_value: Variant in stocks:
		if not stock_value is Dictionary:
			continue
		var stock: Dictionary = stock_value
		_append_unique(rows, str(stock.get("established_fact_id", "")))
		for value: Variant in stock.get("source_fact_ids", []):
			_append_unique(rows, str(value))
	var pressure_fact_id := _latest_pressure_fact_id(
		snapshot, pressure_settlement_id
	)
	_append_unique(rows, pressure_fact_id)
	return rows


func _latest_pressure_fact_id(snapshot: Variant, settlement_id: String) -> String:
	var latest: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", ""))
			== "settlement_resource_pressure_changed"
			and str(fact.get("actor_id", "")) == settlement_id
			and (
				latest.is_empty()
				or int(fact.get("day", 0)) >= int(latest.get("day", 0))
			)
		):
			latest = fact
	return str(latest.get("fact_id", ""))


func _append_unique(rows: Array[String], value: String) -> void:
	if value != "" and value not in rows:
		rows.append(value)


func _available_amounts(stocks: Array) -> Dictionary:
	var rows: Dictionary = {}
	for stock: Dictionary in stocks:
		rows[str(stock.get("stock_id", ""))] = float(stock.get("current", 0.0))
	return rows


func _fact_exists(snapshot: Variant, fact_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	for entity: Dictionary in snapshot.get_entities():
		if str(entity.get("id", "")) == entity_id:
			return str(entity.get("display_name", entity_id))
	return entity_id


func _dictionary_rows(value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if value is Array:
		for row: Variant in value:
			if row is Dictionary:
				rows.append((row as Dictionary).duplicate(true))
	return rows


func _tick_value(tick_event: Dictionary) -> int:
	return int(tick_event.get("day", 0)) * 24 + int(tick_event.get("hour", 0))


func _safe_id(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace(":", "_")
