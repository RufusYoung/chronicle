extends RefCounted
class_name V5SettlementNetworkGenerator

const SettlementGeneratorModel = preload(
	"res://scripts/sim/generation/settlement_generator.gd"
)


func generate_fixture(
		source_fixture: Dictionary,
		config: Dictionary,
		definition: Dictionary
) -> Dictionary:
	if source_fixture.is_empty() or config.is_empty() or definition.is_empty():
		return _failure("generation_input_missing")
	if source_fixture.has("settlement_network_generation_result"):
		return {
			"ok": true,
			"fixture": source_fixture.duplicate(true),
			"report": (
				source_fixture.get(
					"settlement_network_generation_result", {}
				) as Dictionary
			).duplicate(true),
		}

	var sites := _dictionary_rows(config.get("sites", []))
	if sites.size() < 2:
		return _failure("network_requires_multiple_sites")
	var links := _dictionary_rows(config.get("links", []))
	if links.is_empty():
		return _failure("network_links_missing")
	var trade_goods := _dictionary_rows(config.get("trade_goods", []))
	if trade_goods.is_empty():
		return _failure("network_trade_goods_missing")

	var fixture := source_fixture.duplicate(true)
	var base_seed := int(config.get(
		"seed", fixture.get("challenge_seed", 1)
	))
	var resident_base: Dictionary = (
		fixture.get("resident_generation", {}) as Dictionary
	).duplicate(true)
	if resident_base.is_empty():
		return _failure("resident_generation_config_missing")

	var site_reports: Array = []
	var resident_configs: Array = []
	var sites_by_id: Dictionary = {}
	for site_index: int in range(sites.size()):
		var site := sites[site_index].duplicate(true)
		var site_id := str(site.get("site_id", ""))
		if site_id == "" or sites_by_id.has(site_id):
			return _failure("network_site_id_missing_or_duplicate:%s" % site_id)
		var site_seed := int(site.get(
			"seed", base_seed + int(site.get("seed_offset", site_index * 997))
		))
		site["seed"] = site_seed
		fixture.erase("settlement_generation_result")
		var resident_config := resident_base.duplicate(true)
		resident_config["seed"] = site_seed + 137
		resident_config["id_namespace"] = _safe_id(site_id)
		fixture["resident_generation"] = resident_config
		var generated: Dictionary = SettlementGeneratorModel.new().generate_fixture(
			fixture, site, definition
		)
		if not bool(generated.get("ok", false)):
			return _failure("network_site_generation_failed:%s:%s" % [
				site_id, str(generated.get("error", "unknown"))
			])
		fixture = (generated.get("fixture", fixture) as Dictionary).duplicate(true)
		var site_report: Dictionary = (
			generated.get("report", {}) as Dictionary
		).duplicate(true)
		resident_config = (
			fixture.get("resident_generation", resident_config) as Dictionary
		).duplicate(true)
		resident_config["seed"] = site_seed + 137
		resident_config["id_namespace"] = _safe_id(site_id)
		var initial_resident_count := clampi(
			int(site.get(
				"resident_count", resident_config.get("resident_count", 12)
			)),
			2,
			int(site_report.get("resident_capacity", 2))
		)
		resident_config["resident_count"] = initial_resident_count
		resident_config["minimum_households"] = maxi(
			2, initial_resident_count / 4
		)
		resident_config["maximum_households"] = maxi(
			int(resident_config["minimum_households"]),
			initial_resident_count / 3
		)
		resident_config["maximum_household_size"] = maxi(int(site.get(
			"dwelling_capacity", 6
		)), 2)
		resident_config["reserve_dwelling_count"] = maxi(int(site.get(
			"reserve_dwelling_count", 1
		)), 0)
		var capacity_adaptation: Dictionary = config.get(
			"capacity_adaptation", {}
		)
		resident_config["construction_plot_count"] = maxi(int(site.get(
			"construction_plot_count",
			capacity_adaptation.get(
				"construction_plot_count_per_settlement", 0
			)
		)), 0)
		resident_configs.append(resident_config)
		var site_row := {
			"site_id": site_id,
			"settlement_id": str(site_report.get("settlement_id", "")),
			"settlement_name": str(site_report.get("settlement_name", site_id)),
			"hub_location_id": str(site_report.get("hub_location_id", "")),
			"resident_capacity": int(site_report.get("resident_capacity", 0)),
			"population_target": int(site_report.get("population_target", 0)),
			"terrain_id": str(site_report.get("terrain_id", "")),
			"terrain_tags": (((site.get("terrain", {}) as Dictionary).get(
				"tags", []
			)) as Array).duplicate(),
			"dwelling_capacity": maxi(int(site.get(
				"dwelling_capacity", 6
			)), 0),
			"generation_seed": site_seed,
		}
		sites_by_id[site_id] = site_row
		site_reports.append(site_report)

	fixture.erase("settlement_generation_result")
	var network_fact_id := "fact.generated_settlement_network.%d" % base_seed
	var reserve_data := _append_trade_reserves(
		fixture, sites_by_id, trade_goods, network_fact_id, base_seed
	)
	fixture = reserve_data.get("fixture", fixture)
	var route_data := _append_network_routes(fixture, sites_by_id, links)
	if not bool(route_data.get("ok", false)):
		return _failure(str(route_data.get("error", "network_route_invalid")))
	if not _network_is_connected(
		route_data.get("runtime_links", []), sites_by_id
	):
		return _failure("network_sites_not_connected")
	fixture = route_data.get("fixture", fixture)

	var primary_site_id := str(config.get(
		"primary_site_id", str((sites[0] as Dictionary).get("site_id", ""))
	))
	if not sites_by_id.has(primary_site_id):
		return _failure("network_primary_site_unknown:%s" % primary_site_id)
	var primary: Dictionary = sites_by_id[primary_site_id]
	fixture["location_id"] = str(primary.get("hub_location_id", ""))
	fixture["resident_generations"] = resident_configs
	fixture["resident_generation"] = {}
	var runtime := {
		"generation_seed": base_seed,
		"sites": _sorted_dictionary_values(sites_by_id),
		"links": route_data.get("runtime_links", []).duplicate(true),
		"trade_goods": trade_goods.duplicate(true),
		"autonomous_pressure": (
			config.get("autonomous_pressure", {}) as Dictionary
		).duplicate(true),
		"population_lifecycle": (
			config.get("population_lifecycle", {}) as Dictionary
		).duplicate(true),
		"family_generation": (
			config.get("family_generation", {}) as Dictionary
		).duplicate(true),
		"labor_absorption": (
			config.get("labor_absorption", {}) as Dictionary
		).duplicate(true),
		"capacity_adaptation": (
			config.get("capacity_adaptation", {}) as Dictionary
		).duplicate(true),
		"industry_lifecycle": (
			config.get("industry_lifecycle", {}) as Dictionary
		).duplicate(true),
		"local_procurement": (
			config.get("local_procurement", {}) as Dictionary
		).duplicate(true),
		"operational_material_uses": (
			config.get("operational_material_uses", []) as Array
		).duplicate(true),
		"industry_archetypes": (
			definition.get("industry_archetypes", []) as Array
		).duplicate(true),
		"migration_delay_days": maxi(int(config.get(
			"migration_delay_days", 2
		)), 1),
		"absorption_delay_days": maxi(int(config.get(
			"absorption_delay_days", 1
		)), 1),
	}
	fixture["settlement_network_runtime"] = runtime

	var facts: Array = (fixture.get("known_facts", []) as Array).duplicate(true)
	facts.append({
		"fact_id": network_fact_id,
		"fact_type": "settlement_network_generated",
		"actor_id": str(primary.get("settlement_id", "")),
		"target_id": str(primary.get("settlement_id", "")),
		"site_count": sites.size(),
		"link_count": links.size(),
		"site_ids": _sorted_keys(sites_by_id),
		"generation_seed": base_seed,
		"summary": "多个资源条件互补的聚落与道路已经形成同一地区网络。",
	})
	fixture["known_facts"] = facts
	var chronicles: Array = (
		fixture.get("initial_chronicle_entries", []) as Array
	).duplicate(true)
	chronicles.append({
		"entry_id": "chronicle.generated_settlement_network.%d" % base_seed,
		"subject_id": str(primary.get("settlement_id", "")),
		"title": "北境聚落网络形成",
		"body": "%d 个聚落通过 %d 条区域道路彼此可达，资源差异开始具备形成贸易和迁移的条件。" % [
			sites.size(), links.size()
		],
		"source_fact_ids": [network_fact_id],
		"generation_seed": base_seed,
	})
	fixture["initial_chronicle_entries"] = chronicles

	var report := {
		"ok": true,
		"generation_seed": base_seed,
		"site_count": sites.size(),
		"link_count": links.size(),
		"primary_site_id": primary_site_id,
		"site_reports": site_reports,
		"sites": runtime["sites"].duplicate(true),
		"links": runtime["links"].duplicate(true),
		"trade_reserve_stock_ids": reserve_data.get(
			"stock_ids", []
		).duplicate(true),
		"signature": JSON.stringify({
			"sites": runtime["sites"],
			"links": runtime["links"],
			"reserves": reserve_data.get("stock_ids", []),
		}),
	}
	var integrity := _validate_fixture(fixture, report)
	report["integrity"] = integrity
	if not bool(integrity.get("ok", false)):
		return _failure("network_integrity_invalid:%s" % ",".join(
			integrity.get("errors", [])
		))
	fixture["settlement_network_generation_result"] = report.duplicate(true)
	return {"ok": true, "fixture": fixture, "report": report}


func _append_trade_reserves(
		fixture: Dictionary,
		sites_by_id: Dictionary,
		trade_goods: Array[Dictionary],
		network_fact_id: String,
		seed: int
) -> Dictionary:
	var updated := fixture.duplicate(true)
	var stocks: Array = (
		updated.get("initial_resource_stocks", []) as Array
	).duplicate(true)
	var facts: Array = (updated.get("known_facts", []) as Array).duplicate(true)
	var stock_ids: Array[String] = []
	for site_id: String in _sorted_keys(sites_by_id):
		var site: Dictionary = sites_by_id[site_id]
		for good: Dictionary in trade_goods:
			var good_id := _safe_id(str(good.get("good_id", "goods")))
			var stock_id := "resource_stock.%s.trade.%s" % [
				_safe_id(site_id), good_id
			]
			var capacity := maxf(float(good.get("reserve_capacity", 16.0)), 1.0)
			var current := clampf(
				float(good.get("initial_current", 0.0)), 0.0, capacity
			)
			var tags: Array = ["trade_reserve", "imported", good_id]
			for tag: Variant in good.get("tags", []):
				if tag not in tags:
					tags.append(tag)
			var fact_id := "fact.resource_stock.%s.trade.%s" % [
				_safe_id(site_id), good_id
			]
			stocks.append({
				"stock_id": stock_id,
				"source_id": "trade.%s" % good_id,
				"source_kind": "trade_reserve",
				"settlement_id": str(site.get("settlement_id", "")),
				"location_id": str(site.get("hub_location_id", "")),
				"label": str(good.get("reserve_label", "外来物资")),
				"tags": tags,
				"capacity": capacity,
				"current": current,
				"recovery_per_hour": 0.0,
				"operating_floor": 0.1,
				"status": "depleted" if current < 0.1 else "stable",
				"abundance": 0,
				"reliability": 0,
				"industry_ids": [],
				"facility_entity_ids": [],
				"source_fact_ids": [network_fact_id],
				"established_fact_id": fact_id,
				"generation_seed": seed,
				"change_count": 0,
				"last_tick": 0,
			})
			facts.append({
				"fact_id": fact_id,
				"fact_type": "settlement_trade_reserve_established",
				"actor_id": str(site.get("settlement_id", "")),
				"target_id": str(site.get("settlement_id", "")),
				"stock_id": stock_id,
				"good_id": str(good.get("good_id", "")),
				"source_fact_ids": [network_fact_id],
				"generation_seed": seed,
			})
			stock_ids.append(stock_id)
	updated["initial_resource_stocks"] = stocks
	updated["known_facts"] = facts
	return {"fixture": updated, "stock_ids": stock_ids}


func _append_network_routes(
		fixture: Dictionary,
		sites_by_id: Dictionary,
		links: Array[Dictionary]
) -> Dictionary:
	var updated := fixture.duplicate(true)
	var routes: Array = (updated.get("travel_routes", []) as Array).duplicate(true)
	var runtime_links: Array = []
	var seen_link_ids: Dictionary = {}
	var seen_route_ids: Dictionary = {}
	for existing_route: Dictionary in routes:
		seen_route_ids[str(existing_route.get("route_id", ""))] = true
	for link: Dictionary in links:
		var link_id := str(link.get("link_id", ""))
		var site_a_id := str(link.get("site_a_id", ""))
		var site_b_id := str(link.get("site_b_id", ""))
		if (
			link_id == ""
			or not sites_by_id.has(site_a_id)
			or not sites_by_id.has(site_b_id)
			or site_a_id == site_b_id
		):
			return {"ok": false, "error": "network_link_invalid:%s" % link_id}
		if seen_link_ids.has(link_id):
			return {"ok": false, "error": "network_link_duplicate:%s" % link_id}
		seen_link_ids[link_id] = true
		var site_a: Dictionary = sites_by_id[site_a_id]
		var site_b: Dictionary = sites_by_id[site_b_id]
		var hours := maxi(int(link.get("travel_hours", 4)), 1)
		var route_a_to_b := "generated_route.network.%s.a_to_b" % _safe_id(link_id)
		var route_b_to_a := "generated_route.network.%s.b_to_a" % _safe_id(link_id)
		if seen_route_ids.has(route_a_to_b) or seen_route_ids.has(route_b_to_a):
			return {"ok": false, "error": "network_route_duplicate:%s" % link_id}
		seen_route_ids[route_a_to_b] = true
		seen_route_ids[route_b_to_a] = true
		for row: Dictionary in [
			{
				"route_id": route_a_to_b,
				"from": site_a,
				"to": site_b,
			},
			{
				"route_id": route_b_to_a,
				"from": site_b,
				"to": site_a,
			},
		]:
			var from_site: Dictionary = row["from"]
			var to_site: Dictionary = row["to"]
			routes.append({
				"route_id": str(row.get("route_id", "")),
				"from_location_id": str(from_site.get("hub_location_id", "")),
				"to_location_id": str(to_site.get("hub_location_id", "")),
				"label": "沿区域道路前往%s" % str(to_site.get(
					"settlement_name", "邻近聚落"
				)),
				"hours": hours,
				"food_cost": 0,
				"narrative_title": "沿聚落间道路旅行",
				"narrative": "你跟随运货人与旧车辙，抵达%s。" % str(
					to_site.get("settlement_name", "邻近聚落")
				),
				"tags": ["generated_route", "inter_settlement", "trade_route"],
				"network_link_id": link_id,
			})
		runtime_links.append({
			"link_id": link_id,
			"site_a_id": site_a_id,
			"site_b_id": site_b_id,
			"settlement_a_id": str(site_a.get("settlement_id", "")),
			"settlement_b_id": str(site_b.get("settlement_id", "")),
			"hub_a_id": str(site_a.get("hub_location_id", "")),
			"hub_b_id": str(site_b.get("hub_location_id", "")),
			"route_a_to_b_id": route_a_to_b,
			"route_b_to_a_id": route_b_to_a,
			"mode": str(link.get("mode", "road")),
			"capacity_per_day": maxf(float(link.get(
				"capacity_per_day", 4.0
			)), 0.1),
			"risk": clampi(int(link.get("risk", 1)), 0, 5),
			"travel_hours": hours,
		})
	updated["travel_routes"] = routes
	return {
		"ok": true,
		"fixture": updated,
		"runtime_links": runtime_links,
	}


func _network_is_connected(links: Array, sites_by_id: Dictionary) -> bool:
	var site_ids := _sorted_keys(sites_by_id)
	if site_ids.is_empty():
		return false
	var visited: Dictionary = {site_ids[0]: true}
	var pending: Array[String] = [site_ids[0]]
	while not pending.is_empty():
		var current: String = str(pending.pop_front())
		for link: Dictionary in links:
			var neighbor := ""
			if str(link.get("site_a_id", "")) == current:
				neighbor = str(link.get("site_b_id", ""))
			elif str(link.get("site_b_id", "")) == current:
				neighbor = str(link.get("site_a_id", ""))
			if neighbor != "" and not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	return visited.size() == site_ids.size()


func _validate_fixture(fixture: Dictionary, report: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var locations: Dictionary = fixture.get("locations", {})
	var entity_ids: Dictionary = {}
	for entity: Dictionary in fixture.get("entities", []):
		entity_ids[str(entity.get("id", ""))] = true
	for site: Dictionary in report.get("sites", []):
		if not entity_ids.has(str(site.get("settlement_id", ""))):
			errors.append("network_settlement_missing:%s" % str(
				site.get("site_id", "")
			))
		if not locations.has(str(site.get("hub_location_id", ""))):
			errors.append("network_hub_missing:%s" % str(site.get("site_id", "")))
	for route: Dictionary in fixture.get("travel_routes", []):
		if not locations.has(str(route.get("from_location_id", ""))):
			errors.append("network_route_from_missing:%s" % str(
				route.get("route_id", "")
			))
		if not locations.has(str(route.get("to_location_id", ""))):
			errors.append("network_route_to_missing:%s" % str(
				route.get("route_id", "")
			))
	var stock_ids: Dictionary = {}
	for stock: Dictionary in fixture.get("initial_resource_stocks", []):
		stock_ids[str(stock.get("stock_id", ""))] = true
		if not entity_ids.has(str(stock.get("settlement_id", ""))):
			errors.append("network_stock_settlement_missing:%s" % str(
				stock.get("stock_id", "")
			))
		if not locations.has(str(stock.get("location_id", ""))):
			errors.append("network_stock_location_missing:%s" % str(
				stock.get("stock_id", "")
			))
	for stock_id: Variant in report.get("trade_reserve_stock_ids", []):
		if not stock_ids.has(str(stock_id)):
			errors.append("network_trade_reserve_missing:%s" % stock_id)
	return {"ok": errors.is_empty(), "errors": errors}


func _dictionary_rows(value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if value is Array:
		for row: Variant in value:
			if row is Dictionary:
				rows.append((row as Dictionary).duplicate(true))
	return rows


func _sorted_dictionary_values(source: Dictionary) -> Array:
	var rows: Array = []
	for key: String in _sorted_keys(source):
		rows.append((source[key] as Dictionary).duplicate(true))
	return rows


func _sorted_keys(source: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for value: Variant in source.keys():
		keys.append(str(value))
	keys.sort()
	return keys


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "fixture": {}, "report": {}}
