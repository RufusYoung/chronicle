extends RefCounted
class_name V5SettlementResourceSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)

const STATUS_RANK := {
	"abundant": 0,
	"stable": 1,
	"strained": 2,
	"depleted": 3,
}


func resolve_recovery_tick(
		snapshot: Variant,
		tick_event: Dictionary
) -> Dictionary:
	if int(tick_event.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var result = TransactionResultModel.new()
	for stock: Dictionary in snapshot.get_resource_stocks():
		var current := float(stock.get("current", 0.0))
		var capacity := float(stock.get("capacity", 0.0))
		var recovery := float(stock.get("recovery_per_hour", 0.0))
		if recovery <= 0.0 or current >= capacity - 0.0001:
			continue
		result.add_resource_change({
			"operation": "recover",
			"stock_id": str(stock.get("stock_id", "")),
			"amount": minf(recovery, capacity - current),
			"tick": _tick_value(tick_event),
			"reason": "natural_recovery",
		})
	if result.is_empty():
		return {"results": [], "events": []}
	result.mark_resolved("settlement_resource_recovery")
	return {"results": [result], "events": []}


func resolve_status_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		region_entity_id: String
) -> Dictionary:
	var stocks: Array = snapshot.get_resource_stocks()
	if stocks.is_empty():
		return {"results": [], "events": []}
	var result = TransactionResultModel.new()
	var events: Array = []
	var facility_rows := _facility_status_rows(stocks)
	for feature_id: String in facility_rows.keys():
		var row: Dictionary = facility_rows[feature_id]
		var status := str(row.get("status", "abundant"))
		var previous := str(snapshot.get_entity_state(
			feature_id, "resource_status", "abundant"
		))
		var operational := status != "depleted"
		if previous == status and bool(snapshot.get_entity_state(
			feature_id, "facility_operational", true
		)) == operational:
			continue
		result.add_state_change({
			"entity_id": feature_id,
			"key": "resource_status",
			"to": status,
		})
		result.add_state_change({
			"entity_id": feature_id,
			"key": "facility_operational",
			"to": operational,
		})
		var stock: Dictionary = row.get("stock", {})
		var fact_id := "fact.resource_status.%s.%s" % [
			_safe_id(str(stock.get("stock_id", feature_id))),
			_safe_id(str(tick_event.get("tick_event_id", "tick"))),
		]
		var summary := _status_summary(stock, previous, status)
		result.add_fact({
			"fact_id": fact_id,
			"fact_type": "settlement_resource_status_changed",
			"actor_id": str(stock.get("settlement_id", "")),
			"target_id": feature_id,
			"location_id": str(stock.get("location_id", "")),
			"stock_id": str(stock.get("stock_id", "")),
			"resource_label": str(stock.get("label", "资源")),
			"status_before": previous,
			"status_after": status,
			"current": float(stock.get("current", 0.0)),
			"capacity": float(stock.get("capacity", 0.0)),
			"source_fact_ids": (
				stock.get("source_fact_ids", []) as Array
			).duplicate(true),
			"day": int(tick_event.get("day", 0)),
			"tick_event_id": str(tick_event.get("tick_event_id", "")),
			"summary": summary,
		})
		result.add_pressure_change({
			"pressure_id": "pressure.resource.%s.%s" % [
				_safe_id(str(stock.get("stock_id", feature_id))),
				_safe_id(str(tick_event.get("tick_event_id", "tick"))),
			],
			"domain": "settlement_resource",
			"scope_id": str(stock.get("settlement_id", "")),
			"pressure_type": (
				"resource_recovery"
				if STATUS_RANK.get(status, 0) < STATUS_RANK.get(previous, 0)
				else "resource_depletion"
			),
			"value": 8 if status == "depleted" else 3,
			"source_fact_ids": [fact_id],
		})
		if status == "depleted" or previous == "depleted":
			result.add_chronicle_entry({
				"entry_id": "chronicle.resource.%s.%s" % [
					_safe_id(str(stock.get("stock_id", feature_id))),
					_safe_id(str(tick_event.get("tick_event_id", "tick"))),
				],
				"subject_id": str(stock.get("settlement_id", "")),
				"title": "%s%s" % [
					str(stock.get("label", "资源")),
					"恢复生产" if previous == "depleted" else "迫使设施停工",
				],
				"body": summary,
				"source_fact_ids": [fact_id],
				"day": int(tick_event.get("day", 0)),
			})
		events.append({
			"event_type": "resource_status_changed",
			"stock_id": str(stock.get("stock_id", "")),
			"feature_id": feature_id,
			"status_before": previous,
			"status_after": status,
			"fact_id": fact_id,
		})

	var pressure_state := _pressure_state(stocks)
	var pressure_changed := false
	if region_entity_id != "":
		for key: String in [
			"food_pressure", "resource_strain", "migration_tendency"
		]:
			var next_value := str(pressure_state.get(key, "low"))
			if str(snapshot.get_region_state_value(key, "")) == next_value:
				continue
			result.add_state_change({
				"entity_id": region_entity_id,
				"key": key,
				"to": next_value,
			})
			pressure_changed = true
	if pressure_changed:
		var settlement_id := str((stocks[0] as Dictionary).get(
			"settlement_id", ""
		))
		var fact_id := "fact.resource_pressure.%s.%s" % [
			_safe_id(settlement_id),
			_safe_id(str(tick_event.get("tick_event_id", "tick"))),
		]
		result.add_fact({
			"fact_id": fact_id,
			"fact_type": "settlement_resource_pressure_changed",
			"actor_id": settlement_id,
			"target_id": settlement_id,
			"food_pressure": str(pressure_state.get("food_pressure", "low")),
			"resource_strain": str(pressure_state.get("resource_strain", "low")),
			"migration_tendency": str(pressure_state.get(
				"migration_tendency", "low"
			)),
			"food_ratio": float(pressure_state.get("food_ratio", 1.0)),
			"resource_ratio": float(pressure_state.get("resource_ratio", 1.0)),
			"day": int(tick_event.get("day", 0)),
			"tick_event_id": str(tick_event.get("tick_event_id", "")),
			"summary": "本地资源水位改变了粮食压力、资源负担与迁移倾向。",
		})
		events.append({
			"event_type": "resource_pressure_changed",
			"settlement_id": settlement_id,
			"fact_id": fact_id,
		})

	if result.is_empty():
		return {"results": [], "events": events}
	if not events.is_empty():
		result.set_narrative_result({
			"title": "聚落资源水位发生变化",
			"summary": _event_summary(events, stocks),
			"tone": "systemic_change",
		})
	result.mark_resolved("settlement_resource_status")
	return {"results": [result], "events": events}


func _facility_status_rows(stocks: Array) -> Dictionary:
	var rows := {}
	for stock: Dictionary in stocks:
		for feature_value: Variant in stock.get("facility_entity_ids", []):
			var feature_id := str(feature_value)
			if feature_id == "":
				continue
			var status := str(stock.get("status", "abundant"))
			if (
				not rows.has(feature_id)
				or STATUS_RANK.get(status, 0) > STATUS_RANK.get(
					str((rows[feature_id] as Dictionary).get("status", "abundant")), 0
				)
			):
				rows[feature_id] = {
					"status": status,
					"stock": stock.duplicate(true),
				}
	return rows


func _pressure_state(stocks: Array) -> Dictionary:
	var total_current := 0.0
	var total_capacity := 0.0
	var food_current := 0.0
	var food_capacity := 0.0
	for stock: Dictionary in stocks:
		var current := float(stock.get("current", 0.0))
		var capacity := float(stock.get("capacity", 0.0))
		total_current += current
		total_capacity += capacity
		if "food" in (stock.get("tags", []) as Array):
			food_current += current
			food_capacity += capacity
	var resource_ratio := _ratio(total_current, total_capacity)
	var food_ratio := _ratio(food_current, food_capacity)
	var food_pressure := _inverse_pressure(food_ratio)
	var resource_strain := _inverse_pressure(resource_ratio)
	var migration := "low"
	if food_pressure == "high" or resource_strain == "high":
		migration = "high"
	elif food_pressure == "medium" or resource_strain == "medium":
		migration = "medium"
	return {
		"food_pressure": food_pressure,
		"resource_strain": resource_strain,
		"migration_tendency": migration,
		"food_ratio": food_ratio,
		"resource_ratio": resource_ratio,
	}


func _inverse_pressure(ratio: float) -> String:
	if ratio < 0.20:
		return "high"
	if ratio < 0.55:
		return "medium"
	return "low"


func _ratio(current: float, capacity: float) -> float:
	return 1.0 if capacity <= 0.0 else clampf(current / capacity, 0.0, 1.0)


func _status_summary(stock: Dictionary, previous: String, status: String) -> String:
	var label := str(stock.get("label", "资源"))
	var current := float(stock.get("current", 0.0))
	var capacity := float(stock.get("capacity", 0.0))
	if status == "depleted":
		return "%s只剩 %.1f / %.1f，已经不足以维持下一轮生产。" % [
			label, current, capacity
		]
	if previous == "depleted":
		return "%s恢复到 %.1f / %.1f，相关设施可以重新开工。" % [
			label, current, capacity
		]
	return "%s库存由%s转为%s，当前为 %.1f / %.1f。" % [
		label, _status_label(previous), _status_label(status), current, capacity
	]


func _event_summary(events: Array, stocks: Array) -> String:
	for event: Dictionary in events:
		if str(event.get("event_type", "")) != "resource_status_changed":
			continue
		var stock_id := str(event.get("stock_id", ""))
		for stock: Dictionary in stocks:
			if str(stock.get("stock_id", "")) == stock_id:
				return _status_summary(
					stock,
					str(event.get("status_before", "abundant")),
					str(event.get("status_after", "abundant"))
				)
	return "生产与自然恢复改变了本地资源水位，聚落压力随之调整。"


func _status_label(status: String) -> String:
	return {
		"abundant": "充足",
		"stable": "尚稳",
		"strained": "吃紧",
		"depleted": "停产线以下",
	}.get(status, status)


func _tick_value(tick_event: Dictionary) -> int:
	return int(tick_event.get("day", 0)) * 24 + int(tick_event.get("hour", 0))


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")
