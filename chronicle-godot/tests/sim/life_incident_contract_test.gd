extends SceneTree

const ControllerModel = preload(
	"res://scripts/sim/life_project/life_project_controller.gd"
)
const FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_quarter_fixture.json"
)
const PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_quarter.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller = ControllerModel.new()
	var start: Dictionary = controller.start(FIXTURE, PROJECT)
	_check(
		bool(start.get("success", false))
		and not controller.has_pending_incident(),
		"1. Quarter starts without a preselected incident"
	)
	var first: Dictionary = controller.execute_duty(
		"survey_thaw_routes",
		{
			"incident_roll_override": 1,
			"incident_id_override": "marta_thin_stew",
		}
	)
	var pending: Dictionary = controller.get_pending_incident()
	_check(
		bool(first.get("success", false))
		and bool(first.get("incident_pending", false))
		and bool(pending.get("active", false))
		and str(pending.get("incident_id", "")) == "marta_thin_stew"
		and "补给已经降到 5" in str(pending.get("trigger_reason", "")),
		"2. A forced test injection only selects an incident whose state cause is true"
	)
	var blocked_duty: Dictionary = controller.execute_duty(
		"survey_thaw_routes", {"incident_roll_override": 100}
	)
	_check(
		controller.get_duty_options().is_empty()
		and str(blocked_duty.get("error", "")) == "life_incident_pending"
		and controller.get_day() == 2,
		"3. Pending incident replaces duties and cannot advance time twice"
	)
	var envelope: Dictionary = controller.build_save_envelope({
		"save_id": "save.test.life_incident_pending",
		"source_kind": "player_save",
	})
	var restored = ControllerModel.new()
	var restore: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(envelope))
	)
	_check(
		bool(restore.get("success", false))
		and restored.has_pending_incident()
		and str(restored.get_pending_incident().get(
			"incident_id", ""
		)) == "marta_thin_stew",
		"4. Save restore preserves the unresolved incident and its responses"
	)
	var trust_before: int = int(restored.session.stores[
		"relationship_store"
	].get_relation("cook_marta", "player", "trust", 0))
	var chronicles_before: int = int(restored.session.stores[
		"chronicle_store"
	].list_entries().size())
	var result: Dictionary = restored.resolve_life_incident("scrape_the_pot")
	var incident_facts: Array = restored.session.stores[
		"fact_store"
	].find_facts_by_type("life_incident_resolved")
	_check(
		bool(result.get("success", false))
		and bool(result.get("incident_resolved", false))
		and not restored.has_pending_incident()
		and int(restored.session.stores["relationship_store"].get_relation(
			"cook_marta", "player", "trust", 0
		)) == trust_before + 1
		and incident_facts.size() == 1,
		"5. One response applies one bounded transaction and clears the incident"
	)
	var incident_fact: Dictionary = incident_facts[0]
	_check(
		str(incident_fact.get("story_role", "")) == "incidental"
		and not bool(incident_fact.get("opens_storyline", true))
		and restored.session.stores["chronicle_store"].list_entries().size()
			== chronicles_before
		and restored.incident_history.size() == 1,
		"6. Incidental response records evidence without opening a Chronicle storyline"
	)
	var repeated: Dictionary = restored.resolve_life_incident("scrape_the_pot")
	_check(
		str(repeated.get("error", "")) == "life_incident_not_pending"
		and restored.session.stores["fact_store"].find_facts_by_type(
			"life_incident_resolved"
		).size() == 1,
		"7. The same response cannot be settled repeatedly"
	)
	var cooldown: Dictionary = restored.execute_duty(
		"survey_thaw_routes",
		{
			"incident_roll_override": 1,
			"incident_id_override": "loose_wall_wedge",
		}
	)
	_check(
		bool(cooldown.get("success", false))
		and not restored.has_pending_incident(),
		"8. Minimum step gap prevents back-to-back incident cards"
	)
	restored.session.stores["state_store"].set_state(
		"seventh_outpost", "wall_integrity", 12
	)
	var state_filtered: Dictionary = restored.execute_duty(
		"survey_thaw_routes",
		{
			"incident_roll_override": 1,
			"incident_id_override": "loose_wall_wedge",
		}
	)
	_check(
		bool(state_filtered.get("success", false))
		and not restored.has_pending_incident(),
		"9. Test injection cannot bypass a false world-state condition"
	)
	var replay_a = ControllerModel.new()
	var replay_b = ControllerModel.new()
	replay_a.start(FIXTURE, PROJECT)
	replay_b.start(FIXTURE, PROJECT)
	var sequence_a := _run_random_sequence(replay_a)
	var sequence_b := _run_random_sequence(replay_b)
	_check(
		not sequence_a.is_empty() and sequence_a == sequence_b,
		"10. The same seed and duty choices replay the same incident sequence"
	)
	var varied_incident_ids: Dictionary = {}
	for seed_value: int in range(1, 13):
		var incident_id := _first_incident_for_seed(seed_value)
		if incident_id != "":
			varied_incident_ids[incident_id] = true
	_check(
		varied_incident_ids.size() >= 3,
		"11. Different run seeds produce at least three state-valid incidents"
	)
	_finish()


func _run_random_sequence(controller: Variant) -> Array[String]:
	var sequence: Array[String] = []
	for unused: int in range(6):
		var result: Dictionary = controller.execute_duty("survey_thaw_routes")
		if not bool(result.get("success", false)):
			break
		var incident: Dictionary = controller.get_pending_incident()
		if not bool(incident.get("active", false)):
			continue
		sequence.append(str(incident.get("incident_id", "")))
		var responses: Array = incident.get("responses", [])
		for response: Dictionary in responses:
			if bool(response.get("can_execute", false)):
				controller.resolve_life_incident(str(
					response.get("response_id", "")
				))
				break
	return sequence


func _first_incident_for_seed(seed_value: int) -> String:
	var controller = ControllerModel.new()
	controller.start(FIXTURE, PROJECT)
	controller.session.stores["state_store"].set_state(
		"player", "fatigue", 5
	)
	controller.session.stores["state_store"].set_state(
		"seventh_outpost", "border_pressure", 8
	)
	controller.session.challenge_rng.seed = seed_value
	controller.execute_duty("survey_thaw_routes")
	return str(controller.get_pending_incident().get("incident_id", ""))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 LIFE INCIDENT PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LIFE INCIDENT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 LIFE INCIDENT FAIL] " + failure)
	print("[V5 LIFE INCIDENT RESULT] FAIL (%d)" % failures.size())
	quit(1)
