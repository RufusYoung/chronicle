extends RefCounted
class_name V5SettlementNetworkSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)

const EPSILON := 0.0001


func resolve_daily_consumption(
		snapshot: Variant,
		tick_event: Dictionary,
		config: Dictionary
) -> Dictionary:
	if config.is_empty() or int(tick_event.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var day := int(tick_event.get("day", 0))
	var populations := _population_by_settlement(snapshot)
	var goods_by_id := _goods_by_id(config.get("trade_goods", []))
	var result = TransactionResultModel.new()
	var events: Array = []
	for stock: Dictionary in snapshot.get_resource_stocks():
		if str(stock.get("source_kind", "")) != "trade_reserve":
			continue
		var good_id := _trade_good_id(stock, goods_by_id)
		if good_id == "" or not goods_by_id.has(good_id):
			continue
		var settlement_id := str(stock.get("settlement_id", ""))
		var fact_id := "fact.network_consumption.%s.%s.day%d" % [
			_safe_id(settlement_id), _safe_id(good_id), day
		]
		if _fact_exists(snapshot, fact_id):
			continue
		var good: Dictionary = goods_by_id[good_id]
		var amount := minf(
			float(stock.get("current", 0.0)),
			float(populations.get(settlement_id, 0)) * maxf(
				float(good.get("daily_use_per_resident", 0.0)), 0.0
			)
		)
		if amount <= EPSILON:
			continue
		result.add_resource_change({
			"operation": "consume",
			"stock_id": str(stock.get("stock_id", "")),
			"amount": amount,
			"tick": _tick_value(tick_event),
			"reason": "settlement_daily_consumption",
			"source_fact_ids": [fact_id],
		})
		result.add_fact({
			"fact_id": fact_id,
			"fact_type": "settlement_trade_reserve_consumed",
			"actor_id": settlement_id,
			"target_id": settlement_id,
			"stock_id": str(stock.get("stock_id", "")),
			"good_id": good_id,
			"amount": amount,
			"population": int(populations.get(settlement_id, 0)),
			"day": day,
			"summary": "居民日常消耗了 %.1f 份%s。" % [
				amount, str(good.get("reserve_label", "外来物资"))
			],
		})
		events.append({
			"event_type": "trade_reserve_consumed",
			"settlement_id": settlement_id,
			"good_id": good_id,
			"amount": amount,
			"fact_id": fact_id,
		})
	if result.is_empty():
		return {"results": [], "events": events}
	result.mark_resolved("settlement_network_consumption")
	return {"results": [result], "events": events}


func resolve_trade_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		config: Dictionary
) -> Dictionary:
	if config.is_empty() or int(tick_event.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var day := int(tick_event.get("day", 0))
	var goods := _dictionary_rows(config.get("trade_goods", []))
	var stocks: Array = snapshot.get_resource_stocks()
	var available := _available_amounts(stocks)
	var result = TransactionResultModel.new()
	var events: Array = []
	for link: Dictionary in _dictionary_rows(config.get("links", [])):
		var link_id := str(link.get("link_id", ""))
		var remaining_capacity := maxf(float(link.get(
			"capacity_per_day", 0.0
		)), 0.0)
		for good: Dictionary in goods:
			if remaining_capacity <= EPSILON:
				break
			var good_id := str(good.get("good_id", ""))
			var fact_id := "fact.network_trade.%s.%s.day%d" % [
				_safe_id(link_id), _safe_id(good_id), day
			]
			if _fact_exists(snapshot, fact_id):
				continue
			var candidate := _best_trade_direction(
				stocks, available, link, good
			)
			if candidate.is_empty():
				continue
			var source_stock: Dictionary = candidate["source_stock"]
			var destination_stock: Dictionary = candidate["destination_stock"]
			var traffic_stock: Dictionary = candidate["traffic_stock"]
			var source_id := str(candidate.get("source_settlement_id", ""))
			var destination_id := str(candidate.get(
				"destination_settlement_id", ""
			))
			var source_stock_id := str(source_stock.get("stock_id", ""))
			var destination_stock_id := str(destination_stock.get("stock_id", ""))
			var traffic_stock_id := str(traffic_stock.get("stock_id", ""))
			var amount := minf(
				minf(
					remaining_capacity,
					float(candidate.get("source_excess", 0.0))
				),
				minf(
					float(candidate.get("destination_free", 0.0)),
					maxf(float(good.get(
						"maximum_shipment", remaining_capacity
					)), 0.1)
				)
			)
			var traffic_cost := minf(
				float(available.get(traffic_stock_id, 0.0)),
				maxf(0.5, amount * 0.15)
			)
			if amount <= EPSILON or traffic_cost + EPSILON < maxf(
				0.5, amount * 0.15
			):
				continue
			var unit_price := float(good.get("base_unit_price", 1.0)) + float(
				link.get("risk", 0)
			) * 0.25 + (1.0 - float(candidate.get(
				"destination_ratio", 1.0
			))) * 2.0
			result.add_resource_change({
				"operation": "consume",
				"stock_id": source_stock_id,
				"amount": amount,
				"tick": _tick_value(tick_event),
				"reason": "network_trade_export",
				"source_fact_ids": [fact_id],
			})
			result.add_resource_change({
				"operation": "adjust",
				"stock_id": destination_stock_id,
				"amount": amount,
				"tick": _tick_value(tick_event),
				"reason": "network_trade_import",
				"source_fact_ids": [fact_id],
			})
			result.add_resource_change({
				"operation": "consume",
				"stock_id": traffic_stock_id,
				"amount": traffic_cost,
				"tick": _tick_value(tick_event),
				"reason": "network_trade_transport",
				"source_fact_ids": [fact_id],
			})
			available[source_stock_id] = float(
				available.get(source_stock_id, 0.0)
			) - amount
			available[destination_stock_id] = float(
				available.get(destination_stock_id, 0.0)
			) + amount
			available[traffic_stock_id] = float(
				available.get(traffic_stock_id, 0.0)
			) - traffic_cost
			remaining_capacity -= amount
			result.add_fact({
				"fact_id": fact_id,
				"fact_type": "settlement_trade_shipment",
				"actor_id": source_id,
				"target_id": destination_id,
				"source_settlement_id": source_id,
				"destination_settlement_id": destination_id,
				"link_id": link_id,
				"good_id": good_id,
				"amount": amount,
				"unit_price": _rounded(unit_price),
				"source_stock_id": source_stock_id,
				"destination_stock_id": destination_stock_id,
				"transport_stock_id": traffic_stock_id,
				"transport_cost": traffic_cost,
				"day": day,
				"summary": "%s沿道路向%s运送了 %.1f 份%s，成交价约为每份 %.1f 枚铜币。" % [
					_entity_name(snapshot, source_id),
					_entity_name(snapshot, destination_id),
					amount,
					str(good.get("reserve_label", good_id)),
					unit_price,
				],
			})
			result.add_pressure_change({
				"pressure_id": "pressure.network_trade.%s.%s.day%d" % [
					_safe_id(link_id), _safe_id(good_id), day
				],
				"domain": "settlement_network",
				"scope_id": destination_id,
				"pressure_type": "trade_relief",
				"value": -maxi(int(round(amount)), 1),
				"source_fact_ids": [fact_id],
			})
			events.append({
				"event_type": "settlement_trade_shipment",
				"source_settlement_id": source_id,
				"destination_settlement_id": destination_id,
				"good_id": good_id,
				"amount": amount,
				"unit_price": _rounded(unit_price),
				"fact_id": fact_id,
			})
	if result.is_empty():
		return {"results": [], "events": events}
	result.set_narrative_result({
		"title": "聚落间出现了真实货流",
		"summary": "%d 批物资沿区域道路从富余聚落流向短缺聚落，来源库存、目的库存和运力同时发生变化。" % events.size(),
		"tone": "regional_trade",
	})
	result.mark_resolved("settlement_network_trade")
	return {"results": [result], "events": events}


func resolve_migration_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		config: Dictionary
) -> Dictionary:
	if config.is_empty() or int(tick_event.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var day := int(tick_event.get("day", 0))
	var day_fact_id := "fact.network_migration_tick.day%d" % day
	if _fact_exists(snapshot, day_fact_id):
		return {"results": [], "events": []}
	var sites := _sites_by_settlement(config.get("sites", []))
	var populations := _population_by_settlement(snapshot)
	var households := _households_by_settlement(snapshot)
	var stocks_by_settlement := _stocks_by_settlement(
		snapshot.get_resource_stocks()
	)
	var pressure_by_settlement: Dictionary = {}
	var result = TransactionResultModel.new()
	for settlement_id: String in sites.keys():
		var pressure := _settlement_pressure(
			stocks_by_settlement.get(settlement_id, [])
		)
		pressure_by_settlement[settlement_id] = pressure
		var previous_days := int(snapshot.get_entity_state(
			settlement_id, "migration_pressure_days", 0
		))
		var next_days := previous_days + 1 if bool(pressure.get(
			"migration_high", false
		)) else 0
		if next_days != previous_days:
			result.add_state_change({
				"entity_id": settlement_id,
				"key": "migration_pressure_days",
				"to": next_days,
			})
		(pressure_by_settlement[settlement_id] as Dictionary)[
			"pressure_days"
		] = next_days

	var migration := _select_migration(
		snapshot,
		config,
		sites,
		populations,
		households,
		pressure_by_settlement
	)
	var events: Array = []
	if not migration.is_empty():
		_append_migration_changes(result, snapshot, migration, day)
		events.append({
			"event_type": "household_migrated",
			"household_id": str(migration.get("household_id", "")),
			"source_settlement_id": str(migration.get(
				"source_settlement_id", ""
			)),
			"destination_settlement_id": str(migration.get(
				"destination_settlement_id", ""
			)),
			"member_ids": (migration.get("member_ids", []) as Array).duplicate(),
		})
	result.add_fact({
		"fact_id": day_fact_id,
		"fact_type": "settlement_network_migration_evaluated",
		"actor_id": str((sites.keys() as Array)[0]) if not sites.is_empty() else "",
		"target_id": str((sites.keys() as Array)[0]) if not sites.is_empty() else "",
		"day": day,
		"migration_count": events.size(),
		"summary": (
			"持续压力促成了一个家庭的真实迁移。"
			if not events.is_empty()
			else "各聚落完成了当日迁移压力评估，没有家庭满足迁移条件。"
		),
	})
	if not events.is_empty():
		result.set_narrative_result({
			"title": "一个家庭离开了长期短缺的聚落",
			"summary": str(migration.get("summary", "居民迁往了条件更稳定的邻近聚落。")),
			"tone": "regional_migration",
		})
	result.mark_resolved("settlement_network_migration")
	return {"results": [result], "events": events}


func _best_trade_direction(
		stocks: Array,
		available: Dictionary,
		link: Dictionary,
		good: Dictionary
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for direction: Dictionary in [
		{
			"source": str(link.get("settlement_a_id", "")),
			"destination": str(link.get("settlement_b_id", "")),
		},
		{
			"source": str(link.get("settlement_b_id", "")),
			"destination": str(link.get("settlement_a_id", "")),
		},
	]:
		var source_id := str(direction.get("source", ""))
		var destination_id := str(direction.get("destination", ""))
		var source_stock := _best_export_stock(
			stocks, available, source_id, good
		)
		var destination_stock := _trade_reserve_stock(
			stocks, destination_id, str(good.get("good_id", ""))
		)
		var traffic_stock := _traffic_stock(
			stocks, available, source_id, str(link.get("mode", "road"))
		)
		if source_stock.is_empty() or destination_stock.is_empty() or traffic_stock.is_empty():
			continue
		var source_current := float(available.get(
			str(source_stock.get("stock_id", "")), 0.0
		))
		var source_capacity := float(source_stock.get("capacity", 0.0))
		var destination_current := float(available.get(
			str(destination_stock.get("stock_id", "")), 0.0
		))
		var destination_capacity := float(destination_stock.get("capacity", 0.0))
		var source_excess := source_current - source_capacity * 0.55
		var destination_ratio := _ratio(
			destination_current, destination_capacity
		)
		var destination_free := destination_capacity - destination_current
		if source_excess <= EPSILON or destination_ratio >= 0.55 or destination_free <= EPSILON:
			continue
		candidates.append({
			"source_settlement_id": source_id,
			"destination_settlement_id": destination_id,
			"source_stock": source_stock,
			"destination_stock": destination_stock,
			"traffic_stock": traffic_stock,
			"source_excess": source_excess,
			"destination_free": destination_free,
			"destination_ratio": destination_ratio,
			"score": (1.0 - destination_ratio) * 100.0 + source_excess,
		})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a.get("score", 0.0)) - float(b.get("score", 0.0))) > EPSILON:
			return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
		return str(a.get("source_settlement_id", "")) < str(
			b.get("source_settlement_id", "")
		)
	)
	return candidates[0]


func _best_export_stock(
		stocks: Array,
		available: Dictionary,
		settlement_id: String,
		good: Dictionary
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var tags: Array = good.get("tags", [])
	for stock: Dictionary in stocks:
		if (
			str(stock.get("settlement_id", "")) != settlement_id
			or str(stock.get("source_kind", "")) != "natural_resource"
			or not _has_any_tag(stock.get("tags", []), tags)
		):
			continue
		var capacity := float(stock.get("capacity", 0.0))
		var current := float(available.get(str(stock.get("stock_id", "")), 0.0))
		var excess := current - capacity * 0.55
		if excess > EPSILON:
			var row := stock.duplicate(true)
			row["export_excess"] = excess
			candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a.get("export_excess", 0.0)) - float(b.get("export_excess", 0.0))) > EPSILON:
			return float(a.get("export_excess", 0.0)) > float(b.get("export_excess", 0.0))
		return str(a.get("stock_id", "")) < str(b.get("stock_id", ""))
	)
	return candidates[0]


func _trade_reserve_stock(
		stocks: Array,
		settlement_id: String,
		good_id: String
) -> Dictionary:
	for stock: Dictionary in stocks:
		if (
			str(stock.get("settlement_id", "")) == settlement_id
			and str(stock.get("source_kind", "")) == "trade_reserve"
			and good_id in (stock.get("tags", []) as Array)
		):
			return stock.duplicate(true)
	return {}


func _traffic_stock(
		stocks: Array,
		available: Dictionary,
		settlement_id: String,
		mode: String
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for stock: Dictionary in stocks:
		if (
			str(stock.get("settlement_id", "")) == settlement_id
			and str(stock.get("source_kind", "")) == "traffic_capacity"
			and mode in (stock.get("tags", []) as Array)
			and float(available.get(str(stock.get("stock_id", "")), 0.0)) >= 0.5
		):
			candidates.append(stock.duplicate(true))
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(available.get(str(a.get("stock_id", "")), 0.0)) > float(
			available.get(str(b.get("stock_id", "")), 0.0)
		)
	)
	return candidates[0]


func _select_migration(
		snapshot: Variant,
		config: Dictionary,
		sites: Dictionary,
		populations: Dictionary,
		households: Dictionary,
		pressures: Dictionary
) -> Dictionary:
	var delay_days := maxi(int(config.get("migration_delay_days", 2)), 1)
	var origins: Array[String] = []
	for settlement_id: String in sites.keys():
		var pressure: Dictionary = pressures.get(settlement_id, {})
		if (
			bool(pressure.get("migration_high", false))
			and int(pressure.get("pressure_days", 0)) >= delay_days
			and int(populations.get(settlement_id, 0)) > 2
		):
			origins.append(settlement_id)
	origins.sort()
	for origin_id: String in origins:
		var destination := _best_migration_destination(
			origin_id, config, sites, populations, pressures, snapshot
		)
		if destination.is_empty():
			continue
		var settlement_households: Dictionary = households.get(origin_id, {})
		var household_ids: Array[String] = []
		for value: Variant in settlement_households.keys():
			household_ids.append(str(value))
		household_ids.sort()
		for household_id: String in household_ids:
			var members: Array = settlement_households[household_id]
			if (
				members.is_empty()
				or int(populations.get(origin_id, 0)) - members.size() < 2
				or members.size() > int(destination.get("free_capacity", 0))
			):
				continue
			var origin: Dictionary = sites[origin_id]
			return {
				"household_id": household_id,
				"member_ids": members.duplicate(),
				"source_settlement_id": origin_id,
				"source_settlement_name": _entity_name(snapshot, origin_id),
				"destination_settlement_id": str(destination.get(
					"settlement_id", ""
				)),
				"destination_settlement_name": _entity_name(
					snapshot, str(destination.get("settlement_id", ""))
				),
				"destination_hub_id": str(destination.get("hub_location_id", "")),
				"link_id": str(destination.get("link_id", "")),
				"pressure_days": int((pressures[origin_id] as Dictionary).get(
					"pressure_days", 0
				)),
				"summary": "%s的一户居民在连续 %d 天资源压力后，沿%s迁往%s。原有劳动者失去旧岗位，抵达后需要重新寻找生计。" % [
					_entity_name(snapshot, origin_id),
					int((pressures[origin_id] as Dictionary).get(
						"pressure_days", 0
					)),
					str(destination.get("link_id", "区域道路")),
					_entity_name(snapshot, str(destination.get(
						"settlement_id", ""
					))),
				],
			}
	return {}


func _best_migration_destination(
		origin_id: String,
		config: Dictionary,
		sites: Dictionary,
		populations: Dictionary,
		pressures: Dictionary,
		snapshot: Variant
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for link: Dictionary in _dictionary_rows(config.get("links", [])):
		var destination_id := ""
		if str(link.get("settlement_a_id", "")) == origin_id:
			destination_id = str(link.get("settlement_b_id", ""))
		elif str(link.get("settlement_b_id", "")) == origin_id:
			destination_id = str(link.get("settlement_a_id", ""))
		if destination_id == "" or not sites.has(destination_id):
			continue
		var destination_pressure: Dictionary = pressures.get(destination_id, {})
		if bool(destination_pressure.get("migration_high", true)):
			continue
		var capacity := int(snapshot.get_entity_state(
			destination_id, "resident_capacity", 0
		))
		var free_capacity := capacity - int(populations.get(destination_id, 0))
		if free_capacity <= 0:
			continue
		var row: Dictionary = (sites[destination_id] as Dictionary).duplicate(true)
		row["settlement_id"] = destination_id
		row["link_id"] = str(link.get("link_id", ""))
		row["free_capacity"] = free_capacity
		candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("free_capacity", 0)) != int(b.get("free_capacity", 0)):
			return int(a.get("free_capacity", 0)) > int(b.get("free_capacity", 0))
		return str(a.get("settlement_id", "")) < str(b.get("settlement_id", ""))
	)
	return candidates[0]


func _append_migration_changes(
		result: Variant,
		snapshot: Variant,
		migration: Dictionary,
		day: int
) -> void:
	var household_id := str(migration.get("household_id", ""))
	var source_id := str(migration.get("source_settlement_id", ""))
	var destination_id := str(migration.get("destination_settlement_id", ""))
	var destination_hub_id := str(migration.get("destination_hub_id", ""))
	var fact_id := "fact.household_migrated.%s.day%d" % [
		_safe_id(household_id), day
	]
	result.add_state_change({
		"entity_id": household_id,
		"key": "location_id",
		"to": destination_hub_id,
	})
	for member_value: Variant in migration.get("member_ids", []):
		var member_id := str(member_value)
		for change: Dictionary in [
			{"key": "settlement_id", "to": destination_id},
			{"key": "location_id", "to": destination_hub_id},
			{"key": "home_location_id", "to": destination_hub_id},
			{"key": "workplace_id", "to": destination_hub_id},
			{"key": "livelihood_elapsed_hours", "to": 0},
		]:
			result.add_state_change({
				"entity_id": member_id,
				"key": str(change.get("key", "")),
				"to": change.get("to"),
			})
		var livelihood_status := str(snapshot.get_entity_state(
			member_id, "livelihood_status", "dependent"
		))
		if livelihood_status in ["employed", "self_employed", "unemployed"]:
			result.add_state_change({
				"entity_id": member_id,
				"key": "occupation_id",
				"to": "unemployed",
			})
			result.add_state_change({
				"entity_id": member_id,
				"key": "livelihood_status",
				"to": "unemployed",
			})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "household_migrated",
		"actor_id": household_id,
		"target_id": destination_id,
		"household_id": household_id,
		"member_ids": (migration.get("member_ids", []) as Array).duplicate(),
		"source_settlement_id": source_id,
		"destination_settlement_id": destination_id,
		"destination_location_id": destination_hub_id,
		"link_id": str(migration.get("link_id", "")),
		"pressure_days": int(migration.get("pressure_days", 0)),
		"day": day,
		"summary": str(migration.get("summary", "居民迁往了邻近聚落。")),
	})
	result.add_pressure_change({
		"pressure_id": "pressure.migration.%s.day%d" % [
			_safe_id(household_id), day
		],
		"domain": "settlement_network",
		"scope_id": source_id,
		"pressure_type": "out_migration",
		"value": (migration.get("member_ids", []) as Array).size(),
		"source_fact_ids": [fact_id],
	})
	result.add_chronicle_entry({
		"entry_id": "chronicle.household_migrated.%s.day%d" % [
			_safe_id(household_id), day
		],
		"subject_id": household_id,
		"title": "一户居民沿区域道路迁居",
		"body": str(migration.get("summary", "居民迁往了邻近聚落。")),
		"source_fact_ids": [fact_id],
		"day": day,
	})


func _settlement_pressure(stocks: Array) -> Dictionary:
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
	var food_ratio := 0.0 if food_capacity <= 0.0 else _ratio(
		food_current, food_capacity
	)
	var resource_ratio := _ratio(total_current, total_capacity)
	return {
		"food_ratio": food_ratio,
		"resource_ratio": resource_ratio,
		"migration_high": food_ratio < 0.20 or resource_ratio < 0.20,
	}


func _population_by_settlement(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var settlement_id := str(snapshot.get_entity_state(
			str(person.get("id", "")), "settlement_id", ""
		))
		if settlement_id != "":
			rows[settlement_id] = int(rows.get(settlement_id, 0)) + 1
	return rows


func _households_by_settlement(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		var settlement_id := str(snapshot.get_entity_state(
			person_id, "settlement_id", ""
		))
		var household_id := str(snapshot.get_entity_state(
			person_id, "household_id", ""
		))
		if settlement_id == "" or household_id == "":
			continue
		if not rows.has(settlement_id):
			rows[settlement_id] = {}
		var settlement_rows: Dictionary = rows[settlement_id]
		if not settlement_rows.has(household_id):
			settlement_rows[household_id] = []
		(settlement_rows[household_id] as Array).append(person_id)
	return rows


func _stocks_by_settlement(stocks: Array) -> Dictionary:
	var rows: Dictionary = {}
	for stock: Dictionary in stocks:
		var settlement_id := str(stock.get("settlement_id", ""))
		if settlement_id == "":
			continue
		if not rows.has(settlement_id):
			rows[settlement_id] = []
		(rows[settlement_id] as Array).append(stock.duplicate(true))
	return rows


func _sites_by_settlement(value: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for site: Dictionary in _dictionary_rows(value):
		var settlement_id := str(site.get("settlement_id", ""))
		if settlement_id != "":
			rows[settlement_id] = site.duplicate(true)
	return rows


func _goods_by_id(value: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for good: Dictionary in _dictionary_rows(value):
		var good_id := str(good.get("good_id", ""))
		if good_id != "":
			rows[good_id] = good.duplicate(true)
	return rows


func _trade_good_id(stock: Dictionary, goods_by_id: Dictionary) -> String:
	for good_id: String in goods_by_id.keys():
		if good_id in (stock.get("tags", []) as Array):
			return good_id
	return ""


func _available_amounts(stocks: Array) -> Dictionary:
	var rows: Dictionary = {}
	for stock: Dictionary in stocks:
		rows[str(stock.get("stock_id", ""))] = float(stock.get("current", 0.0))
	return rows


func _has_any_tag(source_value: Variant, expected: Array) -> bool:
	if not source_value is Array:
		return false
	for tag: Variant in source_value:
		if tag in expected:
			return true
	return false


func _fact_exists(snapshot: Variant, fact_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	var entity: Dictionary = snapshot.get_entity(entity_id)
	return str(entity.get("display_name", entity_id))


func _dictionary_rows(value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if value is Array:
		for row: Variant in value:
			if row is Dictionary:
				rows.append((row as Dictionary).duplicate(true))
	return rows


func _ratio(current: float, capacity: float) -> float:
	return 1.0 if capacity <= 0.0 else clampf(current / capacity, 0.0, 1.0)


func _rounded(value: float) -> float:
	return round(value * 100.0) / 100.0


func _tick_value(tick_event: Dictionary) -> int:
	return int(tick_event.get("day", 0)) * 24 + int(tick_event.get("hour", 0))


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")
