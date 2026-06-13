extends SceneTree

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const PlayerActionsModel = preload("res://scripts/sim/player_world_actions.gd")
const SEED_PATH := "res://data/world_seed_mirror_lake.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulator := SimulatorModel.new()
	var player_actions := PlayerActionsModel.new()
	var initial := simulator.load_seed(SEED_PATH)
	var baseline := simulator.load_seed(SEED_PATH)
	var intervention := simulator.load_seed(SEED_PATH)
	if initial == null or baseline == null or intervention == null:
		push_error("[WORLD SIM RESULT] FAIL: seed could not be loaded")
		quit(1)
		return

	print("=== WORLD SIM A: 30 DAYS WITHOUT PLAYER INTERVENTION ===")
	var baseline_day_10: Dictionary = {}
	for _index: int in range(30):
		var before_news := baseline.world_news.size()
		var before_leads := baseline.lead_candidates.size()
		simulator.advance_one_day(baseline)
		if baseline.day == 10:
			baseline_day_10 = _comparison_snapshot(baseline)
		_print_daily_summary(baseline, before_news, before_leads)

	print("=== WORLD SIM B: PLAYER HELPS WARDENS ON DAY 3 ===")
	var intervention_day_10: Dictionary = {}
	for _index: int in range(30):
		var before_news := intervention.world_news.size()
		var before_leads := intervention.lead_candidates.size()
		simulator.advance_one_day(intervention)
		if intervention.day == 3:
			player_actions.help_faction(intervention, "wardens", "border_town")
			print("DAY 03 | PLAYER ACTION: helped wardens secure border_town supplies")
		if intervention.day == 10:
			intervention_day_10 = _comparison_snapshot(intervention)
		_print_daily_summary(intervention, before_news, before_leads)

	_print_final_state("A", baseline)
	_print_news("A", baseline)
	_print_leads("A", baseline)
	_print_final_state("B", intervention)
	_print_news("B", intervention)
	_print_leads("B", intervention)
	_print_comparison(baseline, intervention, baseline_day_10, intervention_day_10)
	_validate(initial, baseline, intervention, baseline_day_10, intervention_day_10)

	if failures.is_empty():
		print("[WORLD SIM RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[WORLD SIM FAIL] " + failure)
		print("[WORLD SIM RESULT] FAIL: %s" % failures)
		quit(1)


func _print_daily_summary(state: WorldSimState, previous_news: int, previous_leads: int) -> void:
	var actions: Array[String] = []
	for fact in state.world_facts:
		if fact.day == state.day and fact.faction_id != "" and fact.type in [
			"patrol",
			"suppress_smugglers",
			"seal_ruins",
			"escort_supplies",
			"raid_supplies",
			"bribe_guards",
			"spread_rumor",
			"move_contraband",
			"gather_relics",
			"harvest_herbs",
			"perform_ritual",
			"spread_visions",
		]:
			actions.append("%s:%s" % [fact.faction_id, fact.type])
	var town := state.get_region("border_town")
	var ruins := state.get_region("old_ruins")
	print(
		"DAY %02d | actions=%s | news+%d leads+%d | town scarcity=%.1f order=%.1f | ruins mystic=%.1f danger=%.1f"
		% [
			state.day,
			", ".join(actions),
			state.world_news.size() - previous_news,
			state.lead_candidates.size() - previous_leads,
			town.scarcity,
			town.order,
			ruins.mystic,
			ruins.danger,
		]
	)


func _print_final_state(label: String, state: WorldSimState) -> void:
	print("=== FINAL REGIONS %s ===" % label)
	var region_ids: Array = state.regions.keys()
	region_ids.sort()
	for region_id: String in region_ids:
		var region := state.get_region(region_id)
		print(
			"%s | danger=%.2f order=%.2f scarcity=%.2f mystic=%.2f food=%.2f herbs=%.2f relics=%.2f info=%.2f beasts=%.2f tags=%s"
			% [
				region.id,
				region.danger,
				region.order,
				region.scarcity,
				region.mystic,
				region.food,
				region.herbs,
				region.relics,
				region.information,
				region.beasts,
				", ".join(region.tags),
			]
		)
	print("=== FINAL FACTIONS %s ===" % label)
	var faction_ids: Array = state.factions.keys()
	faction_ids.sort()
	for faction_id: String in faction_ids:
		var faction := state.get_faction(faction_id)
		print(
			"%s | power=%.2f wealth=%.2f food_need=%.2f hostility=%.2f relations=%s"
			% [
				faction.id,
				faction.power,
				faction.wealth,
				faction.food_need,
				faction.hostility_to_player,
				JSON.stringify(faction.relations),
			]
		)
	_print_aggregate_summary(label, state)


func _print_news(label: String, state: WorldSimState) -> void:
	print("=== WORLD NEWS %s (%d) ===" % [label, state.world_news.size()])
	for news in state.world_news:
		print(
			"%s | day=%d region=%s source=%s truth=%.2f fact=%s | %s"
			% [
				news.id,
				news.day,
				news.region_id,
				news.source,
				news.truth_level,
				news.related_fact_id,
				news.summary,
			]
		)


func _print_leads(label: String, state: WorldSimState) -> void:
	print("=== LEAD CANDIDATES %s (%d) ===" % [label, state.lead_candidates.size()])
	for lead in state.lead_candidates:
		print(
			"%s | day=%d type=%s region=%s cause=%s fact=%s urgency=%.2f risk=%.2f actions=%s"
			% [
				lead.id,
				lead.day,
				lead.type,
				lead.region_id,
				lead.world_cause,
				lead.related_fact_id,
				lead.urgency,
				lead.risk,
				", ".join(lead.possible_actions),
			]
		)


func _print_comparison(
		baseline: WorldSimState,
		intervention: WorldSimState,
		baseline_day_10: Dictionary,
		intervention_day_10: Dictionary
	) -> void:
	print("=== COMPARISON ===")
	print(
		"day_10 regions differ=%s factions differ=%s news differ=%s leads differ=%s"
		% [
			baseline_day_10.get("regions", {}) != intervention_day_10.get("regions", {}),
			baseline_day_10.get("factions", {}) != intervention_day_10.get("factions", {}),
			baseline_day_10.get("news_signatures", []) != intervention_day_10.get("news_signatures", []),
			baseline_day_10.get("lead_signatures", []) != intervention_day_10.get("lead_signatures", []),
		]
	)
	for region_id: String in baseline.regions:
		var left := baseline.get_region(region_id)
		var right := intervention.get_region(region_id)
		print(
			"region %s | danger_delta=%.2f order_delta=%.2f scarcity_delta=%.2f mystic_delta=%.2f"
			% [
				region_id,
				right.danger - left.danger,
				right.order - left.order,
				right.scarcity - left.scarcity,
				right.mystic - left.mystic,
			]
		)
	for faction_id: String in baseline.factions:
		var left := baseline.get_faction(faction_id)
		var right := intervention.get_faction(faction_id)
		print(
			"faction %s | power_delta=%.2f wealth_delta=%.2f hostility_delta=%.2f"
			% [
				faction_id,
				right.power - left.power,
				right.wealth - left.wealth,
				right.hostility_to_player - left.hostility_to_player,
			]
		)
	print(
		"news signatures differ=%s | lead signatures differ=%s"
		% [
			_news_signatures(baseline) != _news_signatures(intervention),
			_lead_signatures(baseline) != _lead_signatures(intervention),
		]
	)


func _validate(
		initial: WorldSimState,
		baseline: WorldSimState,
		intervention: WorldSimState,
		baseline_day_10: Dictionary,
		intervention_day_10: Dictionary
	) -> void:
	_check(baseline.world_news.size() >= 3, "baseline produced at least 3 world_news")
	_check(baseline.lead_candidates.size() >= 5, "baseline produced at least 5 lead_candidates")
	_check(_count_facts(baseline, "region_tags_changed") >= 1, "at least one region tag changed")
	_check(_faction_changed(initial, baseline), "at least one faction state changed")
	_check(_significantly_changed_regions(initial, baseline) >= 2, "at least two regions changed significantly")
	_check(_all_leads_traceable(baseline), "all baseline leads have world_cause and related_fact_id")
	_check(_all_leads_traceable(intervention), "all intervention leads have world_cause and related_fact_id")
	_check(_regions_differ(baseline, intervention), "player intervention changed at least one region")
	_check(_factions_differ(baseline, intervention), "player intervention changed at least one faction")
	_check(
		_news_signatures(baseline) != _news_signatures(intervention),
		"player intervention changed world_news"
	)
	_check(
		_lead_signatures(baseline) != _lead_signatures(intervention),
		"player intervention changed lead_candidates"
	)
	_check(
		baseline_day_10.get("regions", {}) != intervention_day_10.get("regions", {}),
		"player intervention changed region state by day 10"
	)
	_check(
		baseline_day_10.get("factions", {}) != intervention_day_10.get("factions", {}),
		"player intervention changed faction state by day 10"
	)
	_check(
		baseline_day_10.get("news_signatures", []) != intervention_day_10.get("news_signatures", []),
		"player intervention changed world_news by day 10"
	)
	_check(
		baseline_day_10.get("lead_signatures", []) != intervention_day_10.get("lead_signatures", []),
		"player intervention changed lead_candidates by day 10"
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[WORLD SIM PASS] " + message)
	else:
		failures.append(message)


func _count_facts(state: WorldSimState, type_name: String) -> int:
	var count := 0
	for fact in state.world_facts:
		if fact.type == type_name:
			count += 1
	return count


func _faction_changed(initial: WorldSimState, result: WorldSimState) -> bool:
	return _factions_differ(initial, result)


func _significantly_changed_regions(initial: WorldSimState, result: WorldSimState) -> int:
	var changed := 0
	for region_id: String in initial.regions:
		var before := initial.get_region(region_id)
		var after := result.get_region(region_id)
		var largest := maxf(
			absf(after.danger - before.danger),
			maxf(
				absf(after.order - before.order),
				maxf(absf(after.scarcity - before.scarcity), absf(after.mystic - before.mystic))
			)
		)
		if largest >= 5.0:
			changed += 1
	return changed


func _all_leads_traceable(state: WorldSimState) -> bool:
	for lead in state.lead_candidates:
		if lead.world_cause == "" or lead.related_fact_id == "":
			return false
	return true


func _regions_differ(left: WorldSimState, right: WorldSimState) -> bool:
	for region_id: String in left.regions:
		var a := left.get_region(region_id)
		var b := right.get_region(region_id)
		if (
			not is_equal_approx(a.danger, b.danger)
			or not is_equal_approx(a.order, b.order)
			or not is_equal_approx(a.scarcity, b.scarcity)
			or not is_equal_approx(a.mystic, b.mystic)
			or not is_equal_approx(a.food, b.food)
		):
			return true
	return false


func _factions_differ(left: WorldSimState, right: WorldSimState) -> bool:
	for faction_id: String in left.factions:
		var a := left.get_faction(faction_id)
		var b := right.get_faction(faction_id)
		if (
			not is_equal_approx(a.power, b.power)
			or not is_equal_approx(a.wealth, b.wealth)
			or not is_equal_approx(a.hostility_to_player, b.hostility_to_player)
			or a.relations != b.relations
		):
			return true
	return false


func _news_signatures(state: WorldSimState) -> Array[String]:
	var signatures: Array[String] = []
	for news in state.world_news:
		signatures.append("%d:%s:%s" % [news.day, news.region_id, news.summary])
	return signatures


func _lead_signatures(state: WorldSimState) -> Array[String]:
	var signatures: Array[String] = []
	for lead in state.lead_candidates:
		signatures.append("%d:%s:%s:%s" % [lead.day, lead.type, lead.region_id, lead.world_cause])
	return signatures


func _comparison_snapshot(state: WorldSimState) -> Dictionary:
	var result := state.snapshot()
	result["news_signatures"] = _news_signatures(state)
	result["lead_signatures"] = _lead_signatures(state)
	return result


func _print_aggregate_summary(label: String, state: WorldSimState) -> void:
	var news_by_fact_type: Dictionary = {}
	for news in state.world_news:
		var fact_type := _fact_type_for_id(state, news.related_fact_id)
		news_by_fact_type[fact_type] = int(news_by_fact_type.get(fact_type, 0)) + 1
	var leads_by_type: Dictionary = {}
	for lead in state.lead_candidates:
		leads_by_type[lead.type] = int(leads_by_type.get(lead.type, 0)) + 1
	print(
		"SUMMARY %s | facts=%d news=%d leads=%d tag_changes=%d | news_by_fact=%s | leads_by_type=%s"
		% [
			label,
			state.world_facts.size(),
			state.world_news.size(),
			state.lead_candidates.size(),
			_count_facts(state, "region_tags_changed"),
			JSON.stringify(news_by_fact_type),
			JSON.stringify(leads_by_type),
		]
	)


func _fact_type_for_id(state: WorldSimState, fact_id: String) -> String:
	for fact in state.world_facts:
		if fact.id == fact_id:
			return fact.type
	return "unknown"
