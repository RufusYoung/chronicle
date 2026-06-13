extends SceneTree

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const PlayerActionsModel = preload("res://scripts/sim/player_world_actions.gd")
const AdapterModel = preload("res://scripts/sim/world_sim_lead_adapter.gd")
const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const ALLOWED_TYPES: Array[String] = ["足迹", "烟柱", "河流", "传闻"]
const REQUIRED_FIELDS: Array[String] = [
	"id",
	"type",
	"target",
	"direction",
	"stage",
	"freshness",
	"risk",
	"source",
	"title",
	"description",
	"possible_actions",
	"world_cause",
	"related_fact_id",
	"source_region_id",
	"source_faction_id",
	"origin",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulator := SimulatorModel.new()
	var adapter := AdapterModel.new()
	var baseline := simulator.load_seed(SEED_PATH)
	var repeat := simulator.load_seed(SEED_PATH)
	var intervention := simulator.load_seed(SEED_PATH)
	if baseline == null or repeat == null or intervention == null:
		push_error("[WORLD SIM LEAD ADAPTER RESULT] FAIL: seed loading failed")
		quit(1)
		return

	simulator.advance_days(baseline, 30)
	simulator.advance_days(repeat, 30)
	for _day: int in range(30):
		simulator.advance_one_day(intervention)
		if intervention.day == 3:
			PlayerActionsModel.new().help_faction(
				intervention,
				"wardens",
				"border_town"
			)

	var baseline_candidates := _candidate_dictionaries(baseline.lead_candidates)
	var repeat_candidates := _candidate_dictionaries(repeat.lead_candidates)
	var intervention_candidates := _candidate_dictionaries(intervention.lead_candidates)
	var baseline_fact_count := baseline.world_facts.size()
	var baseline_lead_count := baseline.lead_candidates.size()

	var adapted := adapter.adapt_lead_candidates(baseline_candidates)
	var adapted_repeat := adapter.adapt_lead_candidates(repeat_candidates)
	var adapted_intervention := adapter.adapt_lead_candidates(intervention_candidates)

	_check(baseline_candidates.size() > 0, "world_sim produced LeadCandidate values")
	_check(adapted.size() > 0, "adapter produced v0.3 clue dictionaries")
	_check(adapted.size() == baseline_candidates.size(), "adapter preserved candidate count")
	_check(_all_required_fields_present(adapted), "all required v0.3 fields are present")
	_check(_all_types_allowed(adapted), "all types belong to the four v0.3 clue types")
	_check(_all_ratios_valid(adapted), "freshness and risk stay within 0.0 to 1.0")
	_check(_all_actions_present(adapted), "every adapted clue has an action hint")
	_check(_all_causes_present(adapted), "every adapted clue has world_cause")
	_check(_all_fact_ids_present(adapted), "every adapted clue has related_fact_id")
	_check(_all_origins_valid(adapted), "every adapted clue has world_sim origin")
	_check(
		_signatures(adapted) == _signatures(adapted_repeat),
		"same seed produces reproducible adapted clues"
	)
	_check(
		_signatures(adapted) != _signatures(adapted_intervention),
		"day 3 test injection changes adapted clue signatures"
	)
	_check(
		baseline.world_facts.size() == baseline_fact_count,
		"adapter does not create world facts"
	)
	_check(
		baseline.lead_candidates.size() == baseline_lead_count,
		"adapter does not create LeadCandidate values"
	)

	print(
		"[ADAPTER SUMMARY] candidates=%d adapted=%d types=%s"
		% [baseline_candidates.size(), adapted.size(), JSON.stringify(_type_counts(adapted))]
	)
	print(
		"[ADAPTER A/B] baseline=%d intervention=%d signatures_differ=%s"
		% [
			adapted.size(),
			adapted_intervention.size(),
			_signatures(adapted) != _signatures(adapted_intervention),
		]
	)
	for index: int in range(mini(5, adapted.size())):
		var clue: Dictionary = adapted[index]
		print(
			"[ADAPTER SAMPLE] %s | %s | %s | cause=%s | fact=%s | actions=%s"
			% [
				clue.get("type", ""),
				clue.get("title", ""),
				clue.get("direction", ""),
				clue.get("world_cause", ""),
				clue.get("related_fact_id", ""),
				", ".join(clue.get("possible_actions", [])),
			]
		)

	if failures.is_empty():
		print("[WORLD SIM LEAD ADAPTER RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[WORLD SIM LEAD ADAPTER FAIL] " + failure)
		print("[WORLD SIM LEAD ADAPTER RESULT] FAIL: %s" % failures)
		quit(1)


func _candidate_dictionaries(candidates: Array) -> Array:
	var output: Array[Dictionary] = []
	for candidate in candidates:
		output.append({
			"id": candidate.id,
			"day": candidate.day,
			"type": candidate.type,
			"region_id": candidate.region_id,
			"source_faction_id": candidate.source_faction_id,
			"world_cause": candidate.world_cause,
			"urgency": candidate.urgency,
			"freshness": candidate.freshness,
			"risk": candidate.risk,
			"possible_actions": candidate.possible_actions.duplicate(),
			"projected_consequences": candidate.projected_consequences.duplicate(true),
			"related_fact_id": candidate.related_fact_id,
		})
	return output


func _all_required_fields_present(clues: Array) -> bool:
	for clue_value: Variant in clues:
		var clue := clue_value as Dictionary
		for field: String in REQUIRED_FIELDS:
			if not clue.has(field):
				return false
	return true


func _all_types_allowed(clues: Array) -> bool:
	for clue_value: Variant in clues:
		var clue := clue_value as Dictionary
		if not String(clue.get("type", "")) in ALLOWED_TYPES:
			return false
	return true


func _all_ratios_valid(clues: Array) -> bool:
	for clue_value: Variant in clues:
		var clue := clue_value as Dictionary
		var freshness := float(clue.get("freshness", -1.0))
		var risk := float(clue.get("risk", -1.0))
		if freshness < 0.0 or freshness > 1.0 or risk < 0.0 or risk > 1.0:
			return false
	return true


func _all_actions_present(clues: Array) -> bool:
	for clue_value: Variant in clues:
		var clue := clue_value as Dictionary
		var actions := clue.get("possible_actions", []) as Array
		if actions.is_empty():
			return false
	return true


func _all_causes_present(clues: Array) -> bool:
	for clue_value: Variant in clues:
		var clue := clue_value as Dictionary
		if String(clue.get("world_cause", "")) == "":
			return false
	return true


func _all_fact_ids_present(clues: Array) -> bool:
	for clue_value: Variant in clues:
		var clue := clue_value as Dictionary
		if String(clue.get("related_fact_id", "")) == "":
			return false
	return true


func _all_origins_valid(clues: Array) -> bool:
	for clue_value: Variant in clues:
		var clue := clue_value as Dictionary
		if String(clue.get("origin", "")) != "world_sim":
			return false
	return true


func _signatures(clues: Array) -> Array[String]:
	var output: Array[String] = []
	for clue_value: Variant in clues:
		var clue := clue_value as Dictionary
		output.append(
			"%s|%s|%s|%s|%s|%d"
			% [
				clue.get("id", ""),
				clue.get("type", ""),
				clue.get("direction", ""),
				clue.get("world_cause", ""),
				clue.get("related_fact_id", ""),
				int(clue.get("freshness_percent", 0)),
			]
		)
	return output


func _type_counts(clues: Array) -> Dictionary:
	var counts: Dictionary = {}
	for clue_value: Variant in clues:
		var clue := clue_value as Dictionary
		var type_name := String(clue.get("type", ""))
		counts[type_name] = int(counts.get(type_name, 0)) + 1
	return counts


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[WORLD SIM LEAD ADAPTER PASS] " + message)
	else:
		failures.append(message)
