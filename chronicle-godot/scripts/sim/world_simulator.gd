extends RefCounted
class_name WorldSimulator

const StateModel = preload("res://scripts/sim/world_sim_state.gd")
const ProjectorModel = preload("res://scripts/sim/world_to_leads_projector.gd")
const NewsDigestModel = preload("res://scripts/sim/world_news_digest.gd")
const LakeTownFoodChainModel = preload("res://scripts/sim/lake_town_food_chain.gd")
const LakeTownReactionSystemModel = preload(
	"res://scripts/sim/lake_town_reaction_system.gd"
)
const LakeTownRecoverySystemModel = preload(
	"res://scripts/sim/lake_town_recovery_system.gd"
)

const DYNAMIC_TAGS: Array[String] = [
	"danger_high",
	"order_low",
	"scarcity_high",
	"mystic_surge",
	"beast_migration",
	"stable",
	"resource_strained",
]

var projector := ProjectorModel.new()
var news_digest := NewsDigestModel.new()
var lake_town_food_chain := LakeTownFoodChainModel.new()
var lake_town_reaction_system := LakeTownReactionSystemModel.new()
var lake_town_recovery_system := LakeTownRecoverySystemModel.new()


func load_seed(path: String) -> WorldSimState:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("[WorldSimulator] Empty or missing seed: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("[WorldSimulator] Seed root must be a Dictionary: %s" % path)
		return null

	var data := parsed as Dictionary
	var state := StateModel.new()
	state.day = int(data.get("day", 0))
	state.seed = int(data.get("seed", 1))
	for region_data: Variant in data.get("regions", []):
		if region_data is Dictionary:
			var region := StateModel.RegionState.from_dictionary(region_data as Dictionary)
			state.regions[region.id] = region
	for faction_data: Variant in data.get("factions", []):
		if faction_data is Dictionary:
			var faction := StateModel.FactionState.from_dictionary(faction_data as Dictionary)
			state.factions[faction.id] = faction
	lake_town_food_chain.initialize_from_seed(
		state,
		data.get("micro_world", {}) as Dictionary
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = state.seed
	state.rng_state = rng.state
	return state


func advance_days(state: WorldSimState, days: int) -> WorldSimState:
	for _day: int in range(maxi(days, 0)):
		advance_one_day(state)
	return state


func advance_one_day(state: WorldSimState) -> void:
	state.day += 1
	_age_leads(state)

	var rng := RandomNumberGenerator.new()
	rng.state = state.rng_state
	_apply_natural_region_changes(state, rng)
	_apply_region_pressure(state)
	_calculate_faction_needs(state)

	for faction_id: String in ["wardens", "smugglers", "echo_cult"]:
		var action := _choose_faction_action(state, faction_id)
		_apply_faction_action(state, faction_id, action)

	_update_region_tags(state)
	lake_town_food_chain.advance_one_day(state)
	lake_town_reaction_system.tick_reactions(state)
	lake_town_recovery_system.tick_recovery(state)
	projector.generate_leads_from_world(state)
	state.rng_state = rng.state


func _age_leads(state: WorldSimState) -> void:
	for lead in state.lead_candidates:
		lead.freshness = maxf(0.0, lead.freshness - 0.08)


func _apply_natural_region_changes(state: WorldSimState, rng: RandomNumberGenerator) -> void:
	var region_ids: Array = state.regions.keys()
	region_ids.sort()
	for region_id: String in region_ids:
		var region := state.get_region(region_id)
		var before := _region_metrics(region)

		var food_regen := 0.8 if region.id == "mirror_lake_forest" else 0.25
		region.food += food_regen + rng.randf_range(-1.2, 1.2) - region.population * 0.012
		region.herbs += (1.0 if region.id == "mirror_lake_forest" else 0.2) + rng.randf_range(-0.8, 0.8)
		region.relics += rng.randf_range(-0.25, 0.05)
		region.information += rng.randf_range(-0.6, 1.0)
		region.beasts += rng.randf_range(-0.6, 1.2)
		if region.id == "old_ruins":
			region.mystic += 0.55 + rng.randf_range(-0.25, 0.65)
		else:
			region.mystic += rng.randf_range(-0.35, 0.4)
		_clamp_region(region)

		var after := _region_metrics(region)
		region.recent_changes.append({
			"day": state.day,
			"type": "natural_change",
			"before": before,
			"after": after,
		})
		if region.recent_changes.size() > 10:
			region.recent_changes.pop_front()
		state.add_fact(
			"region_daily_shift",
			region.id,
			region.owner_faction_id,
			{"before": before, "after": after}
		)


func _apply_region_pressure(state: WorldSimState) -> void:
	for region_id: String in state.regions:
		var region := state.get_region(region_id)
		var food_pressure := (50.0 - region.food) * 0.045
		var population_pressure := region.population * 0.006
		region.scarcity += food_pressure + population_pressure - 0.25
		region.danger += (
			(region.beasts - 50.0) * 0.018
			+ (region.mystic - 55.0) * 0.015
			- (region.order - 50.0) * 0.012
		)
		var owner_bonus := 0.35 if region.owner_faction_id == "wardens" else -0.15
		region.order += owner_bonus - region.scarcity * 0.008 - region.danger * 0.006
		_clamp_region(region)


func _calculate_faction_needs(state: WorldSimState) -> void:
	for faction_id: String in state.factions:
		var faction := state.get_faction(faction_id)
		var region := state.get_region(faction.active_region_id)
		if region == null:
			continue
		faction.food_need = clampf(
			region.scarcity * 0.55 + (100.0 - region.food) * 0.25,
			0.0,
			100.0
		)


func _choose_faction_action(state: WorldSimState, faction_id: String) -> String:
	var town := state.get_region("border_town")
	var ruins := state.get_region("old_ruins")
	var smugglers := state.get_faction("smugglers")
	var wardens := state.get_faction("wardens")

	match faction_id:
		"wardens":
			if smugglers.power > 43.0:
				return "suppress_smugglers"
			if town.scarcity > 58.0:
				return "escort_supplies"
			if ruins.mystic > 74.0:
				return "seal_ruins"
			return "patrol"
		"smugglers":
			if town.scarcity > 55.0:
				return "raid_supplies"
			if state.day % 3 == 0:
				return "spread_rumor"
			if wardens.power > 64.0:
				return "bribe_guards"
			return "move_contraband"
		"echo_cult":
			if state.day % 4 == 0:
				return "perform_ritual"
			if state.day % 3 == 1 and ruins.relics > 55.0:
				return "gather_relics"
			var forest := state.get_region("mirror_lake_forest")
			if state.day % 3 == 2 and forest.herbs > 45.0:
				return "harvest_herbs"
			return "spread_visions"
	return ""


func _apply_faction_action(state: WorldSimState, faction_id: String, action: String) -> void:
	match action:
		"patrol":
			_wardens_patrol(state)
		"suppress_smugglers":
			_wardens_suppress_smugglers(state)
		"seal_ruins":
			_wardens_seal_ruins(state)
		"escort_supplies":
			_wardens_escort_supplies(state)
		"raid_supplies":
			_smugglers_raid_supplies(state)
		"bribe_guards":
			_smugglers_bribe_guards(state)
		"spread_rumor":
			_smugglers_spread_rumor(state)
		"move_contraband":
			_smugglers_move_contraband(state)
		"gather_relics":
			_cult_gather_relics(state)
		"harvest_herbs":
			_cult_harvest_herbs(state)
		"perform_ritual":
			_cult_perform_ritual(state)
		"spread_visions":
			_cult_spread_visions(state)


func _wardens_patrol(state: WorldSimState) -> void:
	var region := state.get_region("mirror_lake_forest")
	var wardens := state.get_faction("wardens")
	region.order += 3.0
	region.danger -= 2.5
	wardens.power += 0.4
	wardens.wealth -= 0.5
	_record_action(state, "patrol", region, wardens, "守望者加强了森林道路巡逻。")


func _wardens_suppress_smugglers(state: WorldSimState) -> void:
	var region := state.get_region("border_town")
	var wardens := state.get_faction("wardens")
	var smugglers := state.get_faction("smugglers")
	region.order += 2.5
	region.danger += 0.8
	wardens.power += 0.7
	wardens.wealth -= 1.0
	smugglers.power -= 2.2
	smugglers.wealth -= 1.0
	_change_relation(wardens, "smugglers", -2.0)
	_change_relation(smugglers, "wardens", -2.0)
	_record_action(state, "suppress_smugglers", region, wardens, "守望者突袭了边境镇的走私据点。")


func _wardens_seal_ruins(state: WorldSimState) -> void:
	var region := state.get_region("old_ruins")
	var wardens := state.get_faction("wardens")
	var cult := state.get_faction("echo_cult")
	region.order += 2.5
	region.mystic -= 4.0
	region.danger -= 1.5
	wardens.power += 0.4
	wardens.wealth -= 1.2
	cult.power -= 1.2
	_change_relation(wardens, "echo_cult", -2.0)
	_change_relation(cult, "wardens", -2.0)
	_record_action(state, "seal_ruins", region, wardens, "守望者封锁了旧日遗迹的一处入口。")


func _wardens_escort_supplies(state: WorldSimState) -> void:
	var region := state.get_region("border_town")
	var wardens := state.get_faction("wardens")
	var smugglers := state.get_faction("smugglers")
	region.food += 8.0
	region.scarcity -= 7.0
	region.order += 1.0
	wardens.power += 0.5
	wardens.wealth -= 2.0
	smugglers.wealth -= 1.2
	_record_action(state, "escort_supplies", region, wardens, "守望者护送粮车进入边境镇。")


func _smugglers_raid_supplies(state: WorldSimState) -> void:
	var region := state.get_region("border_town")
	var smugglers := state.get_faction("smugglers")
	var wardens := state.get_faction("wardens")
	region.food -= 6.0
	region.scarcity += 5.0
	region.order -= 3.0
	region.danger += 1.5
	smugglers.wealth += 4.0
	smugglers.power += 0.7
	_change_relation(smugglers, "wardens", -1.5)
	_change_relation(wardens, "smugglers", -1.5)
	_record_action(state, "raid_supplies", region, smugglers, "一批补给在边境镇外被截走。")


func _smugglers_bribe_guards(state: WorldSimState) -> void:
	var region := state.get_region("border_town")
	var smugglers := state.get_faction("smugglers")
	var wardens := state.get_faction("wardens")
	region.order -= 4.0
	region.information += 3.0
	smugglers.wealth += 2.0
	smugglers.power += 0.5
	wardens.wealth -= 1.0
	_record_action(state, "bribe_guards", region, smugglers, "边境镇的关卡出现了可疑放行记录。")


func _smugglers_spread_rumor(state: WorldSimState) -> void:
	var region := state.get_region("border_town")
	var smugglers := state.get_faction("smugglers")
	region.information += 5.0
	region.order -= 1.5
	smugglers.wealth += 1.0
	smugglers.power += 0.3
	_record_action(state, "spread_rumor", region, smugglers, "关于粮价与守望者失职的说法开始流传。")


func _smugglers_move_contraband(state: WorldSimState) -> void:
	var region_id := "mirror_lake_forest" if state.day % 2 == 0 else "old_ruins"
	var region := state.get_region(region_id)
	var smugglers := state.get_faction("smugglers")
	region.information += 3.0
	region.order -= 2.0
	region.danger += 1.0
	if region.id == "old_ruins":
		region.relics -= 2.0
	else:
		region.herbs -= 2.0
	smugglers.wealth += 3.0
	smugglers.power += 0.4
	_record_action(state, "move_contraband", region, smugglers, "走私货物沿隐蔽路线穿过地区。")


func _cult_gather_relics(state: WorldSimState) -> void:
	var region := state.get_region("old_ruins")
	var cult := state.get_faction("echo_cult")
	region.relics -= 4.0
	region.mystic += 2.0
	region.danger += 1.0
	cult.wealth += 1.0
	cult.power += 1.0
	_record_action(state, "gather_relics", region, cult, "回声教团从遗迹深处带出了遗物。")


func _cult_harvest_herbs(state: WorldSimState) -> void:
	var region := state.get_region("mirror_lake_forest")
	var cult := state.get_faction("echo_cult")
	region.herbs -= 6.0
	region.scarcity += 2.0
	region.mystic += 1.5
	cult.wealth += 1.2
	cult.power += 0.5
	_record_action(state, "harvest_herbs", region, cult, "森林中的稀有草药被成批采走。")


func _cult_perform_ritual(state: WorldSimState) -> void:
	var region := state.get_region("old_ruins")
	var cult := state.get_faction("echo_cult")
	var wardens := state.get_faction("wardens")
	region.mystic += 6.0
	region.danger += 3.0
	region.order -= 1.5
	cult.power += 1.5
	cult.wealth -= 0.5
	_change_relation(cult, "wardens", -1.0)
	_change_relation(wardens, "echo_cult", -1.0)
	_record_action(state, "perform_ritual", region, cult, "旧日遗迹上空出现了不自然的回声。")


func _cult_spread_visions(state: WorldSimState) -> void:
	var region := state.get_region("border_town")
	var cult := state.get_faction("echo_cult")
	region.information += 4.0
	region.mystic += 2.0
	region.order -= 2.0
	cult.power += 0.6
	_record_action(state, "spread_visions", region, cult, "镇民开始梦见同一片倒悬的湖面。")


func _record_action(
		state: WorldSimState,
		action: String,
		region,
		faction,
		summary: String
	) -> void:
	_clamp_region(region)
	_clamp_faction(faction)
	var fact := state.add_fact(
		action,
		region.id,
		faction.id,
		{
			"action": action,
			"region": _region_metrics(region),
			"faction_power": faction.power,
			"faction_wealth": faction.wealth,
		}
	)
	news_digest.record_action(state, fact, faction.name, summary)


func _update_region_tags(state: WorldSimState) -> void:
	for region_id: String in state.regions:
		var region := state.get_region(region_id)
		var previous: Array[String] = region.tags.duplicate()
		for dynamic_tag: String in DYNAMIC_TAGS:
			region.tags.erase(dynamic_tag)
		if region.danger >= 65.0:
			region.tags.append("danger_high")
		if region.order <= 35.0:
			region.tags.append("order_low")
		if region.scarcity >= 65.0:
			region.tags.append("scarcity_high")
		if region.mystic >= 70.0:
			region.tags.append("mystic_surge")
		if region.beasts >= 70.0:
			region.tags.append("beast_migration")
		if region.order >= 70.0 and region.danger <= 40.0:
			region.tags.append("stable")
		if minf(region.food, region.herbs) <= 35.0:
			region.tags.append("resource_strained")
		region.tags.sort()
		previous.sort()
		if previous != region.tags:
			var fact := state.add_fact(
				"region_tags_changed",
				region.id,
				region.owner_faction_id,
				{"before": previous, "after": region.tags.duplicate()}
			)
			if "mystic_surge" in region.tags or "scarcity_high" in region.tags:
				news_digest.record_immediate(
					state,
					fact,
					"地区观察",
					"%s 的状态标签发生变化：%s" % [
						region.name,
						", ".join(region.tags),
					],
					"region_tags_changed",
					",".join(region.tags)
				)


func _change_relation(faction, target_id: String, delta: float) -> void:
	faction.relations[target_id] = clampf(
		float(faction.relations.get(target_id, 0.0)) + delta,
		-100.0,
		100.0
	)


func _region_metrics(region) -> Dictionary:
	return {
		"danger": snappedf(region.danger, 0.01),
		"order": snappedf(region.order, 0.01),
		"scarcity": snappedf(region.scarcity, 0.01),
		"mystic": snappedf(region.mystic, 0.01),
		"food": snappedf(region.food, 0.01),
		"herbs": snappedf(region.herbs, 0.01),
		"relics": snappedf(region.relics, 0.01),
		"information": snappedf(region.information, 0.01),
		"beasts": snappedf(region.beasts, 0.01),
	}


func _clamp_region(region) -> void:
	region.danger = clampf(region.danger, 0.0, 100.0)
	region.order = clampf(region.order, 0.0, 100.0)
	region.scarcity = clampf(region.scarcity, 0.0, 100.0)
	region.mystic = clampf(region.mystic, 0.0, 100.0)
	region.food = clampf(region.food, 0.0, 100.0)
	region.herbs = clampf(region.herbs, 0.0, 100.0)
	region.relics = clampf(region.relics, 0.0, 100.0)
	region.information = clampf(region.information, 0.0, 100.0)
	region.beasts = clampf(region.beasts, 0.0, 100.0)
	region.population = clampf(region.population, 0.0, 100.0)


func _clamp_faction(faction) -> void:
	faction.power = clampf(faction.power, 0.0, 100.0)
	faction.wealth = clampf(faction.wealth, 0.0, 100.0)
	faction.food_need = clampf(faction.food_need, 0.0, 100.0)
	faction.hostility_to_player = clampf(faction.hostility_to_player, -100.0, 100.0)
