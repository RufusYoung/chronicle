extends "res://scripts/sim/local_story_module.gd"
class_name LakeTownFoodCrisisModule

const SimulatorModel = preload(
	"res://scripts/sim/world_simulator.gd"
)
const RegionSimProfileModel = preload(
	"res://scripts/sim/region_sim_profile.gd"
)
const MicroActionResolverModel = preload(
	"res://scripts/sim/micro_action_resolver.gd"
)
const HistoryVariationRunnerModel = preload(
	"res://scripts/dev/lake_town_history_variation_runner.gd"
)
const QualityAuditorModel = preload(
	"res://scripts/dev/lake_town_history_quality_auditor.gd"
)

const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const MODULE_ID := "lake_town_food_crisis"
const MODULE_VERSION := "0.1.0"
const REGION_ID := "border_town"
const LOCATION_IDS: Array[String] = [
	"lake_town_market",
	"old_chen_shop",
	"abandoned_granary",
	"ma_shen_home_temp",
]
const CORE_NPCS: Array[String] = [
	"old_chen",
	"chen_mi",
	"ma_shen",
	"liu_zhangfang",
]
const WRAPPED_SYSTEMS: Array[String] = [
	"lake_town_food_chain",
	"lake_town_reaction_system",
	"lake_town_recovery_system",
	"lake_town_branch_closure_system",
	"lake_town_hunger_closure_system",
	"micro_action_resolver",
	"lake_town_history_quality_auditor",
	"lake_town_history_variation_runner",
]

var simulator := SimulatorModel.new()
var region_profile := RegionSimProfileModel.new()
var action_resolver := MicroActionResolverModel.new()
var history_runner := HistoryVariationRunnerModel.new()
var quality_auditor := QualityAuditorModel.new()


func get_module_id() -> String:
	return MODULE_ID


func get_module_version() -> String:
	return MODULE_VERSION


func get_region_id() -> String:
	return REGION_ID


func get_location_ids() -> Array:
	return LOCATION_IDS.duplicate()


func get_required_state_keys() -> Array:
	return [
		"regions",
		"factions",
		"world_facts",
		"micro_state",
		"npcs",
		"locations",
		"items",
		"traces",
		"memories",
		"narratable_states",
	]


func create_state_for_seed(_seed_value: int) -> Variant:
	return simulator.load_seed(SEED_PATH)


func build_profile_for_seed(seed_value: int) -> Dictionary:
	return region_profile.build_lake_town_region_profile(seed_value)


func initialize_module_state(
		state: Variant,
		profile: Dictionary = {}
	) -> void:
	if not state is WorldSimState or profile.is_empty():
		return
	var legacy_profile := (
		profile.get("legacy_profile", {}) as Dictionary
	)
	if legacy_profile.is_empty() and profile.has("old_chen"):
		legacy_profile = profile
	if legacy_profile.is_empty():
		legacy_profile = (
			region_profile.lake_town_seed_profile.build_profile(
				int(profile.get("seed", state.seed))
			)
		)
	region_profile.lake_town_seed_profile.apply_profile_to_state(
		state,
		legacy_profile
	)
	state.micro_state["region_sim_profile"] = profile.duplicate(true)


func tick_module(state: Variant) -> Array:
	if not state is WorldSimState:
		return []
	var start_index: int = state.world_facts.size()
	simulator.advance_one_day(state)
	var created: Array = []
	for index: int in range(start_index, state.world_facts.size()):
		created.append(state.world_facts[index])
	return created


func build_narratable_states(state: Variant) -> Array:
	if not state is WorldSimState:
		return []
	return state.narratable_states.duplicate(true)


func build_action_candidates(
		state: Variant,
		actor_state: Dictionary,
		narratable_state_id: String
	) -> Array:
	return action_resolver.build_action_candidates(
		state,
		actor_state,
		narratable_state_id
	)


func resolve_action(
		state: Variant,
		actor_state: Dictionary,
		action_id: String,
		narratable_state_id: String
	) -> Dictionary:
	return action_resolver.resolve_micro_action(
		state,
		actor_state,
		action_id,
		narratable_state_id
	)


func build_history_signature(state: Variant) -> Dictionary:
	return history_runner.build_history_signature(state)


func build_history_hash(signature: Dictionary) -> String:
	return history_runner.build_history_hash(signature)


func audit_quality(
		state: Variant,
		signature: Dictionary = {}
	) -> Dictionary:
	if not signature.is_empty():
		var state_audit := quality_auditor.audit_state(state)
		var signature_audit := (
			quality_auditor.audit_history_signature(signature)
		)
		if bool(
			signature_audit.get(
				"unclassified_without_reason",
				false
			)
		):
			state_audit["unclassified_without_reason"] = true
			var flags := (
				state_audit.get("quality_flags", []) as Array
			)
			if not "unclassified_without_reason" in flags:
				flags.append("unclassified_without_reason")
			state_audit["quality_flags"] = flags
		return state_audit
	return quality_auditor.audit_state(state)


func describe_module() -> Dictionary:
	return {
		"module_id": MODULE_ID,
		"module_version": MODULE_VERSION,
		"module_name": "湖湾镇粮食危机",
		"region_id": REGION_ID,
		"locations": LOCATION_IDS.duplicate(),
		"core_npcs": CORE_NPCS.duplicate(),
		"pressure_fields": [
			"food",
			"scarcity",
			"debt",
			"hunger",
			"guard_pressure",
			"neighbor_help",
		],
		"supported_outputs": [
			"WorldFact",
			"Trace",
			"Memory",
			"NarratableState",
			"ActionCandidate",
			"HistorySignature",
			"QualityAudit",
		],
		"wrapped_systems": WRAPPED_SYSTEMS.duplicate(),
		"daily_tick_owner": "WorldSimulator.advance_one_day",
		"ui_dependency": false,
		"module_stage": "prototype",
	}
