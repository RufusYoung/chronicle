extends RefCounted
class_name V5SettlementEnvironmentSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const RoutePressureQueryModel = preload(
	"res://scripts/sim/resource/route_pressure_query.gd"
)


func resolve_daily_pressure(
		snapshot: Variant,
		tick_event: Dictionary,
		network_config: Dictionary
) -> Dictionary:
	var config: Dictionary = network_config.get("autonomous_pressure", {})
	var day := int(tick_event.get("day", 0))
	if day <= 0 or not bool(config.get("enabled", false)):
		return {"results": [], "events": []}
	var marker_id := "fact.autonomous_route_pressure_tick.day%d" % day
	if _fact_exists(snapshot, marker_id):
		return {"results": [], "events": []}

	var source_fact_id := _network_source_fact_id(snapshot)
	if source_fact_id == "":
		return {"results": [], "events": []}
	var seed := int(network_config.get("generation_seed", 1))
	var result = TransactionResultModel.new()
	var events: Array[Dictionary] = []
	result.add_fact({
		"fact_id": marker_id,
		"fact_type": "autonomous_route_pressure_tick",
		"actor_id": str(snapshot.player.get("id", "player")),
		"target_id": str(snapshot.player.get("id", "player")),
		"day": day,
		"source_fact_ids": [source_fact_id],
	})
	for link_value: Variant in network_config.get("links", []):
		if not link_value is Dictionary:
			continue
		var link: Dictionary = link_value
		if not _should_start(snapshot, link, config, seed, day):
			continue
		var event := _pressure_event(
			snapshot, link, network_config, config, seed, day, source_fact_id
		)
		result.add_fact(event.get("fact", {}))
		result.add_pressure_change(event.get("pressure", {}))
		result.add_chronicle_entry(event.get("chronicle", {}))
		events.append(event.get("event", {}))
	if not events.is_empty():
		var first_event: Dictionary = events[0]
		result.set_narrative_result({
			"title": str(first_event.get("title", "一条道路通行受阻")),
			"summary": str(first_event.get(
				"summary", "附近道路受到环境影响，货流与出行都会变慢。"
			)),
		})
	result.mark_resolved("autonomous_route_pressure")
	return {"results": [result], "events": events}


func _should_start(
		snapshot: Variant,
		link: Dictionary,
		config: Dictionary,
		seed: int,
		day: int
) -> bool:
	var link_id := str(link.get("link_id", ""))
	if link_id == "" or not RoutePressureQueryModel.new().active_pressure(
		snapshot, link_id, day
	).get("source_fact_ids", []).is_empty():
		return false
	var latest_day := RoutePressureQueryModel.new().latest_start_day(
		snapshot, link_id, day
	)
	var quiet_days := day - latest_day
	var minimum_quiet := maxi(int(config.get("minimum_quiet_days", 4)), 1)
	var maximum_quiet := maxi(
		int(config.get("maximum_quiet_days", 9)), minimum_quiet
	)
	if quiet_days < minimum_quiet:
		return false
	if quiet_days >= maximum_quiet:
		return true
	var chance := clampi(int(config.get(
		"daily_start_chance_percent", 20
	)), 0, 100)
	return _stable_noise("%d:%s:day%d:start" % [seed, link_id, day]) % 100 < chance


func _pressure_event(
		snapshot: Variant,
		link: Dictionary,
		network_config: Dictionary,
		config: Dictionary,
		seed: int,
		day: int,
		source_fact_id: String
) -> Dictionary:
	var link_id := str(link.get("link_id", ""))
	var key := "%d:%s:day%d" % [seed, link_id, day]
	var duration := _range_value(
		config, "minimum_duration_days", "maximum_duration_days", 3, 4,
		key + ":duration"
	)
	var risk_increase := _range_value(
		config, "minimum_risk_increase", "maximum_risk_increase", 1, 2,
		key + ":risk"
	)
	var capacity_penalty := _range_float(
		config,
		"minimum_capacity_penalty",
		"maximum_capacity_penalty",
		1.0,
		2.0,
		key + ":capacity"
	)
	var until_day := day + duration - 1
	var cause := _cause_for(link, network_config, key)
	var fact_id := "fact.regional_route_pressure.%s.day%d" % [
		_safe_id(link_id), day
	]
	var endpoint_a := str(link.get("settlement_a_id", ""))
	var endpoint_b := str(link.get("settlement_b_id", ""))
	var route_name := "%s至%s道路" % [
		_entity_name(snapshot, endpoint_a),
		_entity_name(snapshot, endpoint_b),
	]
	var summary := "%s遭遇%s，预计持续 %d 天。道路风险上升 %d，日运力减少 %.1f。" % [
		route_name,
		str(cause.get("label", "恶劣路况")),
		duration,
		risk_increase,
		capacity_penalty,
	]
	return {
		"fact": {
			"fact_id": fact_id,
			"fact_type": "regional_route_pressure_started",
			"actor_id": endpoint_a,
			"target_id": endpoint_b,
			"link_id": link_id,
			"cause_id": str(cause.get("cause_id", "route_disruption")),
			"risk_increase": risk_increase,
			"capacity_penalty": capacity_penalty,
			"start_day": day,
			"until_day": until_day,
			"generation_seed": seed,
			"source_fact_ids": [source_fact_id],
			"summary": summary,
		},
		"pressure": {
			"pressure_id": "pressure.regional_route.%s.day%d" % [
				_safe_id(link_id), day
			],
			"domain": "settlement_environment",
			"scope_id": link_id,
			"pressure_type": "route_disruption",
			"value": risk_increase,
			"source_fact_ids": [fact_id],
		},
		"chronicle": {
			"entry_id": "chronicle.regional_route_pressure.%s.day%d" % [
				_safe_id(link_id), day
			],
			"subject_id": endpoint_a,
			"title": "%s通行受阻" % route_name,
			"body": summary,
			"source_fact_ids": [fact_id],
			"day": day,
		},
		"event": {
			"event_type": "regional_route_pressure_started",
			"fact_id": fact_id,
			"link_id": link_id,
			"title": "%s通行受阻" % route_name,
			"summary": summary,
			"cause_id": str(cause.get("cause_id", "")),
			"risk_increase": risk_increase,
			"capacity_penalty": capacity_penalty,
			"start_day": day,
			"until_day": until_day,
		},
	}


func _cause_for(
		link: Dictionary, network_config: Dictionary, key: String
) -> Dictionary:
	var tags: Array[String] = []
	for site_value: Variant in network_config.get("sites", []):
		if not site_value is Dictionary:
			continue
		var site: Dictionary = site_value
		if str(site.get("settlement_id", "")) not in [
			str(link.get("settlement_a_id", "")),
			str(link.get("settlement_b_id", "")),
		]:
			continue
		for tag_value: Variant in site.get("terrain_tags", []):
			var tag := str(tag_value)
			if tag != "" and tag not in tags:
				tags.append(tag)
	var candidates: Array[Dictionary] = []
	if "upland" in tags or "slope" in tags:
		candidates.append({"cause_id": "slope_fall", "label": "坡石坠落"})
	if "marsh" in tags or "waterside" in tags or "riverside" in tags:
		candidates.append({"cause_id": "road_washout", "label": "积水冲毁路基"})
	if "windy" in tags:
		candidates.append({"cause_id": "crosswind", "label": "持续横风"})
	if candidates.is_empty():
		candidates.append({"cause_id": "dense_fog", "label": "浓雾滞留"})
	return candidates[_stable_noise(key + ":cause") % candidates.size()]


func _range_value(
		config: Dictionary,
		minimum_key: String,
		maximum_key: String,
		default_minimum: int,
		default_maximum: int,
		key: String
) -> int:
	var minimum := int(config.get(minimum_key, default_minimum))
	var maximum := maxi(int(config.get(maximum_key, default_maximum)), minimum)
	return minimum + _stable_noise(key) % (maximum - minimum + 1)


func _range_float(
		config: Dictionary,
		minimum_key: String,
		maximum_key: String,
		default_minimum: float,
		default_maximum: float,
		key: String
) -> float:
	var minimum := float(config.get(minimum_key, default_minimum))
	var maximum := maxf(float(config.get(maximum_key, default_maximum)), minimum)
	if is_equal_approx(minimum, maximum):
		return minimum
	var ratio := float(_stable_noise(key) % 1001) / 1000.0
	return snappedf(lerpf(minimum, maximum, ratio), 0.1)


func _network_source_fact_id(snapshot: Variant) -> String:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) == "settlement_network_generated":
			return str(fact.get("fact_id", ""))
	return ""


func _fact_exists(snapshot: Variant, fact_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	return str(snapshot.get_entity(entity_id).get("display_name", entity_id))


func _stable_noise(key: String) -> int:
	return int(("0x" + key.sha256_text().substr(0, 8)).hex_to_int() % 1000000)


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")
