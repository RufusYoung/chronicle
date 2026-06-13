extends RefCounted
class_name WorldToLeadsProjector

const StateModel = preload("res://scripts/sim/world_sim_state.gd")


func generate_leads_from_world(state: WorldSimState) -> Array:
	var generated: Array = []
	var forest := state.get_region("mirror_lake_forest")
	var town := state.get_region("border_town")
	var ruins := state.get_region("old_ruins")
	var wardens := state.get_faction("wardens")
	var smugglers := state.get_faction("smugglers")
	var cult := state.get_faction("echo_cult")

	if town != null and smugglers != null:
		if town.scarcity > 65.0 and smugglers.power > 40.0:
			_add_if_fresh(
				state,
				generated,
				_make_lead(
					state,
					"caravan",
					town.id,
					"smugglers",
					"scarcity_high_and_smuggler_raid",
					clampf(town.scarcity / 100.0, 0.55, 1.0),
					clampf((town.danger + town.scarcity) / 200.0, 0.35, 1.0),
					["investigate", "protect", "rob", "ignore"],
					{"protect": "scarcity_down", "rob": "scarcity_up", "ignore": "smugglers_wealth_up"},
					_latest_fact_id(state, town.id, ["raid_supplies", "region_daily_shift"])
				)
			)

	if ruins != null and cult != null:
		if ruins.mystic > 70.0 and cult.power > 35.0:
			_add_if_fresh(
				state,
				generated,
				_make_lead(
					state,
					"apparition",
					ruins.id,
					"echo_cult",
					"cult_ritual_and_mystic_pressure",
					clampf(ruins.mystic / 100.0, 0.6, 1.0),
					clampf((ruins.danger + ruins.mystic) / 200.0, 0.5, 1.0),
					["observe", "interrupt", "follow", "report"],
					{"interrupt": "mystic_down", "follow": "information_up", "ignore": "danger_up"},
					_latest_fact_id(state, ruins.id, ["perform_ritual", "spread_visions", "region_daily_shift"])
				)
			)

	if forest != null:
		if forest.order < 35.0 and forest.danger > 55.0:
			_add_if_fresh(
				state,
				generated,
				_make_lead(
					state,
					"smoke",
					forest.id,
					"",
					"order_collapse_and_forest_conflict",
					clampf((100.0 - forest.order) / 100.0, 0.5, 1.0),
					clampf(forest.danger / 100.0, 0.45, 1.0),
					["approach", "scout", "avoid", "inform_wardens"],
					{"scout": "information_up", "inform_wardens": "order_up", "avoid": "danger_persists"},
					_latest_fact_id(state, forest.id)
				)
			)

		if forest.beasts > 70.0:
			_add_if_fresh(
				state,
				generated,
				_make_lead(
					state,
					"tracks",
					forest.id,
					"",
					"beast_migration",
					clampf(forest.beasts / 100.0, 0.5, 1.0),
					clampf((forest.beasts + forest.danger) / 200.0, 0.4, 1.0),
					["hunt", "follow", "set_trap", "warn_travelers"],
					{"hunt": "beasts_down", "follow": "information_up", "warn_travelers": "danger_down"},
					_latest_fact_id(state, forest.id, ["region_daily_shift", "harvest_herbs"])
				)
			)

		if forest.mystic > 57.0 and (forest.herbs < 70.0 or forest.scarcity > 50.0):
			_add_if_fresh(
				state,
				generated,
				_make_lead(
					state,
					"river",
					forest.id,
					"echo_cult",
					"resource_pressure_along_lake_routes",
					clampf((forest.mystic + forest.scarcity) / 200.0, 0.4, 1.0),
					clampf((100.0 - forest.herbs + forest.danger) / 200.0, 0.25, 1.0),
					["sample_water", "trace_upstream", "warn_villagers", "ignore"],
					{"trace_upstream": "cult_activity_exposed", "warn_villagers": "danger_down", "ignore": "scarcity_up"},
					_latest_fact_id(state, forest.id, ["harvest_herbs", "region_daily_shift"])
				)
			)

	if town != null and wardens != null:
		if town.order > 58.0 and _has_recent_faction_fact(state, "wardens", 2):
			_add_if_fresh(
				state,
				generated,
				_make_lead(
					state,
					"checkpoint",
					town.id,
					"wardens",
					"warden_security_response",
					clampf(town.order / 100.0, 0.35, 0.9),
					clampf((100.0 - town.order + wardens.hostility_to_player) / 100.0, 0.15, 0.8),
					["cooperate", "question", "bypass", "report_smuggling"],
					{"cooperate": "warden_relation_up", "bypass": "danger_up", "report_smuggling": "smuggler_power_down"},
					_latest_fact_id(state, town.id, ["patrol", "suppress_smugglers", "escort_supplies"])
				)
			)

	if town != null and smugglers != null:
		if town.information > 70.0 and smugglers.wealth > 42.0:
			_add_if_fresh(
				state,
				generated,
				_make_lead(
					state,
					"rumor",
					town.id,
					"smugglers",
					"smuggler_information_market",
					clampf(town.information / 100.0, 0.4, 0.95),
					clampf(smugglers.power / 100.0, 0.25, 0.85),
					["verify", "buy_information", "spread", "report"],
					{"verify": "truth_known", "spread": "order_down", "report": "smuggler_hostility_up"},
					_latest_fact_id(state, town.id, ["spread_rumor", "bribe_guards", "region_daily_shift"])
				)
			)

	return generated


func _make_lead(
		state: WorldSimState,
		type_name: String,
		region_id: String,
		source_faction_id: String,
		world_cause: String,
		urgency: float,
		risk: float,
		possible_actions: Array[String],
		projected_consequences: Dictionary,
		related_fact_id: String
	):
	var lead := StateModel.LeadCandidate.new()
	lead.id = "lead_d%02d_%s_%s" % [state.day, type_name, region_id]
	lead.day = state.day
	lead.type = type_name
	lead.region_id = region_id
	lead.source_faction_id = source_faction_id
	lead.world_cause = world_cause
	lead.urgency = clampf(urgency, 0.0, 1.0)
	lead.freshness = 1.0
	lead.risk = clampf(risk, 0.0, 1.0)
	lead.possible_actions = possible_actions.duplicate()
	lead.projected_consequences = projected_consequences.duplicate(true)
	lead.related_fact_id = related_fact_id
	return lead


func _add_if_fresh(state: WorldSimState, output: Array, lead) -> void:
	for existing in state.lead_candidates:
		if existing.type == lead.type and existing.region_id == lead.region_id:
			if state.day - existing.day < 4:
				return
	if lead.world_cause == "" or lead.related_fact_id == "":
		push_error("[WorldToLeadsProjector] Lead lacks a world cause or related fact: %s" % lead.id)
		return
	state.lead_candidates.append(lead)
	output.append(lead)


func _latest_fact_id(
		state: WorldSimState,
		region_id: String,
		preferred_types: Array[String] = []
	) -> String:
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact = state.world_facts[index]
		if fact.region_id != region_id:
			continue
		if preferred_types.is_empty() or fact.type in preferred_types:
			return fact.id
	return ""


func _has_recent_faction_fact(state: WorldSimState, faction_id: String, days: int) -> bool:
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact = state.world_facts[index]
		if state.day - fact.day > days:
			return false
		if fact.faction_id == faction_id and fact.type in [
			"patrol",
			"suppress_smugglers",
			"seal_ruins",
			"escort_supplies",
		]:
			return true
	return false
