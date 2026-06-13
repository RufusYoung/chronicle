extends RefCounted
class_name PlayerWorldActions


func help_faction(state: WorldSimState, faction_id: String, region_id: String) -> void:
	var faction := state.get_faction(faction_id)
	var region := state.get_region(region_id)
	if faction == null or region == null:
		push_error("[PlayerWorldActions] Unknown faction or region")
		return

	region.order = clampf(region.order + 6.0, 0.0, 100.0)
	region.scarcity = clampf(region.scarcity - 8.0, 0.0, 100.0)
	region.food = clampf(region.food + 5.0, 0.0, 100.0)
	faction.power = clampf(faction.power + 4.0, 0.0, 100.0)
	faction.wealth = clampf(faction.wealth - 2.0, 0.0, 100.0)
	faction.hostility_to_player = clampf(faction.hostility_to_player - 6.0, -100.0, 100.0)

	if faction_id == "wardens":
		var smugglers := state.get_faction("smugglers")
		smugglers.wealth = clampf(smugglers.wealth - 3.0, 0.0, 100.0)
		smugglers.power = clampf(smugglers.power - 6.0, 0.0, 100.0)
		smugglers.hostility_to_player = clampf(
			smugglers.hostility_to_player + 8.0,
			-100.0,
			100.0
		)
		smugglers.relations["wardens"] = clampf(
			float(smugglers.relations.get("wardens", 0.0)) - 4.0,
			-100.0,
			100.0
		)

	var fact := state.add_fact(
		"player_helped_faction",
		region_id,
		faction_id,
		{
			"faction_id": faction_id,
			"food_delta": 5.0,
			"scarcity_delta": -8.0,
			"order_delta": 6.0,
			"smuggler_power_delta": -6.0,
		}
	)
	state.add_news(
		region_id,
		"目击者",
		"一名旅者协助%s稳定了%s的补给。" % [faction.name, region.name],
		1.0,
		fact.id
	)


func steal_resource(state: WorldSimState, region_id: String, resource_id: String) -> void:
	var region := state.get_region(region_id)
	if region == null or not resource_id in ["food", "herbs", "relics", "information"]:
		push_error("[PlayerWorldActions] Unknown region or resource")
		return
	var previous := region.resource_value(resource_id)
	region.set_resource_value(resource_id, previous - 8.0)
	region.scarcity = clampf(region.scarcity + 4.0, 0.0, 100.0)
	region.danger = clampf(region.danger + 2.0, 0.0, 100.0)
	var owner := state.get_faction(region.owner_faction_id)
	if owner != null:
		owner.power = clampf(owner.power - 0.5, 0.0, 100.0)
		owner.hostility_to_player = clampf(owner.hostility_to_player + 6.0, -100.0, 100.0)
	state.add_fact(
		"player_stole_resource",
		region_id,
		region.owner_faction_id,
		{"resource_id": resource_id, "amount": minf(previous, 8.0)}
	)


func expose_secret(state: WorldSimState, faction_id: String) -> void:
	var faction := state.get_faction(faction_id)
	if faction == null:
		push_error("[PlayerWorldActions] Unknown faction: %s" % faction_id)
		return
	faction.power = clampf(faction.power - 5.0, 0.0, 100.0)
	faction.wealth = clampf(faction.wealth - 3.0, 0.0, 100.0)
	faction.hostility_to_player = clampf(faction.hostility_to_player + 10.0, -100.0, 100.0)
	var region := state.get_region(faction.active_region_id)
	if region != null:
		region.information = clampf(region.information + 8.0, 0.0, 100.0)
		region.order = clampf(region.order + 2.0, 0.0, 100.0)
	var fact := state.add_fact(
		"player_exposed_secret",
		faction.active_region_id,
		faction_id,
		{"power_delta": -5.0, "wealth_delta": -3.0, "information_delta": 8.0}
	)
	state.add_news(
		faction.active_region_id,
		"公开告示",
		"%s的一项秘密活动被公开。" % faction.name,
		1.0,
		fact.id
	)


func ignore_crisis(state: WorldSimState, region_id: String) -> void:
	var region := state.get_region(region_id)
	if region == null:
		push_error("[PlayerWorldActions] Unknown region: %s" % region_id)
		return
	region.danger = clampf(region.danger + 6.0, 0.0, 100.0)
	region.scarcity = clampf(region.scarcity + 4.0, 0.0, 100.0)
	region.order = clampf(region.order - 5.0, 0.0, 100.0)
	var owner := state.get_faction(region.owner_faction_id)
	if owner != null:
		owner.power = clampf(owner.power - 2.0, 0.0, 100.0)
	state.add_fact(
		"player_ignored_crisis",
		region_id,
		region.owner_faction_id,
		{"danger_delta": 6.0, "scarcity_delta": 4.0, "order_delta": -5.0}
	)


func resolve_lead(state: WorldSimState, lead_id: String, outcome: String) -> void:
	var lead = state.find_lead(lead_id)
	if lead == null:
		push_error("[PlayerWorldActions] Unknown lead: %s" % lead_id)
		return
	var region := state.get_region(lead.region_id)
	if region == null:
		return

	match outcome:
		"protect", "warn_travelers", "inform_wardens", "report":
			region.order = clampf(region.order + 5.0, 0.0, 100.0)
			region.danger = clampf(region.danger - 4.0, 0.0, 100.0)
			var wardens := state.get_faction("wardens")
			wardens.power = clampf(wardens.power + 2.0, 0.0, 100.0)
		"interrupt":
			region.mystic = clampf(region.mystic - 7.0, 0.0, 100.0)
			region.danger = clampf(region.danger - 2.0, 0.0, 100.0)
			var cult := state.get_faction("echo_cult")
			cult.power = clampf(cult.power - 3.0, 0.0, 100.0)
			cult.hostility_to_player = clampf(cult.hostility_to_player + 8.0, -100.0, 100.0)
		"rob":
			region.food = clampf(region.food - 5.0, 0.0, 100.0)
			region.scarcity = clampf(region.scarcity + 5.0, 0.0, 100.0)
			var smugglers := state.get_faction("smugglers")
			smugglers.wealth = clampf(smugglers.wealth - 2.0, 0.0, 100.0)
		"ignore", "avoid":
			region.danger = clampf(region.danger + 3.0, 0.0, 100.0)
			region.order = clampf(region.order - 2.0, 0.0, 100.0)
		_:
			region.information = clampf(region.information + 4.0, 0.0, 100.0)
			region.danger = clampf(region.danger - 1.0, 0.0, 100.0)

	lead.freshness = 0.0
	state.add_fact(
		"player_resolved_lead",
		lead.region_id,
		lead.source_faction_id,
		{"lead_id": lead.id, "lead_type": lead.type, "outcome": outcome}
	)
