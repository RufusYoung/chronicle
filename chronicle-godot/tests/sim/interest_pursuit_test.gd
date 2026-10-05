extends "res://tests/sim/goal_pressure_test.gd"

const Interest = preload("res://scripts/sim/situation/interest_projection.gd")


func _run() -> void:
	var game := NewAgent.new()
	var response := _call(game, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v2"})
	_check(response.ok, "natural world starts")
	_check(response.observation.goal_pressure.interests.is_empty(), "no invented personal interests at start")
	for id: String in ["situation:ask:generated_resident.echo_landing.008:", "generated_route.network.echo_shore_road.a_to_b",
		"situation:ask:generated_resident.echo_terrace.006:", "generated_route.echo_terrace.commons_to_terrace_farming",
		"situation:follow:generated_resident.echo_terrace.008:generated_route.echo_terrace.terrace_farming_to_commons",
		"situation:ask:generated_resident.echo_terrace.008:"]:
		response = _act_offered(game, response, id)
	var interests: Array = response.observation.goal_pressure.interests
	_check(interests.size() == 1, "actual firsthand testimony offers one question")
	if interests.is_empty():
		_finish()
		return
	var question: Dictionary = interests[0]
	_check(question.why_care.contains("高岑") and question.uncertainty != "" and question.source != "", "why, unknown and provenance visible before departure")
	_check(question.resolution_type == "", "visit before learning this testimony does not resolve the later question")
	var signature := _signature(game.model.session)
	response = _call(game, "set_goal", {"goal_id": question.id})
	_check(signature == _signature(game.model.session), "selecting interest does not write world or knowledge")
	_call(game, "observe")
	_check(signature == _signature(game.model.session), "repeated protocol observation stays read-only")
	for id: String in ["situation:give:generated_resident.echo_terrace.008:item_instance.danger.worn_cloak",
		"generated_route.echo_terrace.commons_to_reed_craft", "generated_route.echo_terrace.reed_craft_to_commons",
		"generated_route.echo_terrace.commons_to_terrace_farming"]:
		response = _act_offered(game, response, id)
	var answer: Dictionary = response.observation.goal_pressure.interest
	_check(answer.resolution_type == "COLD_TRAIL", "natural evening arrival closes cold lead without spawning danger")
	_check(answer.new_information_count == 1 and answer.answer.contains("没有看见威胁"), "arrival explicitly answers what was previously unknown")
	_check(not answer.answer.contains("被击败") and answer.answer.contains("不必原地等"), "absence neither means defeated nor encourages repeated waiting")
	var scene := Presentation.build(response)
	_check(scene.body.contains(answer.answer) and scene.eyebrow == "这条线索已冷", "actual main scene gives resolution priority")
	_check(scene.choices.all(func(c: Dictionary) -> bool: return c.get("intent") != "wait"), "empty waiting is not promoted by a cold question")
	_check(Presentation.build(response, "all").choices.size() == response.choices.size(), "ordinary waiting remains legal in more actions")
	_check(game.model.session.validate_persistent_references().ok, "current-state reference check accepts dated observations without a restore time")
	var forged: Dictionary = game.model.session.build_save_envelope()
	for fact: Dictionary in forged.stores.facts:
		if fact.get("fact_type") == "situation_place_observed":
			fact.evidence.location_id = "test_injection.nonexistent"
			break
	_check(not Session.new().load_from_save_envelope(forged).get("ok", false), "test injection: forged observation location rejected by native restore")
	_check(_call(game, "save", {"slot": "interest_pursuit_contract", "overwrite": true}).ok, "native save with observed evidence")
	var restored := _call(game, "load", {"slot": "interest_pursuit_contract"})
	_check(restored.ok and JSON.parse_string(JSON.stringify(restored.observation)) == JSON.parse_string(JSON.stringify(response.observation)), "native restore preserves full projected answer")
	response = _act_offered(game, restored, "generated_route.echo_terrace.terrace_farming_to_commons")
	_check(response.observation.goal_pressure.interest.question_status == "resolved", "walking away does not reopen an answered question")
	_check(response.observation.goal_pressure.urgency == "none", "old checked danger does not manufacture equipment pressure elsewhere")
	var prior: Dictionary = response.observation.goal_pressure.interest.duplicate(true)
	game.model.session.stores.state_store.set_state("world_threat.field_boar", "visible", true)
	game.model.session.stores.state_store.set_state("world_threat.field_boar", "health", 1)
	_check(game.model.build_view_data().goal_pressure.interest == prior, "test injection: remote threat changes cannot rewrite dated local evidence")
	_resolution_counterexamples(question, game.model.session)
	_person_pursuit()
	_finish()


func _person_pursuit() -> void:
	var game := NewAgent.new()
	var response := _call(game, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81002, "economy_variant": "world_situation_v2"})
	for id: String in ["situation:ask:generated_resident.echo_landing.002:", "situation:ask:generated_resident.echo_landing.005:",
		"generated_route.echo_landing.commons_to_road_carting"]:
		response = _act_offered(game, response, id)
	for step: int in range(2):
		response = _act_offered(game, response, "situation:pursue:generated_resident.echo_landing.002:generated_location.echo_landing.landing")
	_check(response.observation.feedback.get("pursuit", {}).get("resolution_type") == "ACTIVE_SITUATION", "natural found person answers the destination question")
	_check(response.observation.feedback.body.contains("见到了杜冬"), "finding someone is explicit information, not an invented reward")
	_check(response.observation.goal_pressure.personal_stakes.is_empty() and response.observation.goal_pressure.stake_diagnostic == "NO_PERSONAL_STAKE", "81002 remains a genuine no-personal-stake counterexample")
	var cold: Dictionary = response.observation.feedback.pursuit.duplicate(true)
	Interest.resolve_place(cold, {"source_fact_id": "test_injection.absent", "observed_hour": 37, "people": [], "traces": []},
		game.model.session.stores.fact_store.get_fact(cold.source), true)
	_check(cold.resolution_type == "COLD_TRAIL", "test injection: absent person without newer trace closes a lead")
	response.observation.feedback.pursuit = cold
	var scene := Presentation.build(response)
	_check(scene.eyebrow == "这条线索已冷" and scene.body.contains("没有见到"), "test injection: direct pursuit answer on main page without a goal")
	_check(scene.choices.all(func(c: Dictionary) -> bool: return c.get("intent") != "wait"), "test injection: direct cold lead does not promote empty waiting")


func _act_offered(game: Variant, response: Dictionary, id: String) -> Dictionary:
	var offered: Array = response.choices.filter(func(c: Dictionary) -> bool: return c.id == id and c.enabled)
	_check(not offered.is_empty(), "legal action offered " + id)
	if offered.is_empty():
		return response
	var next := _call(game, "act", {"choice_id": offered[0].choice_id, "confirm": true})
	_check(next.ok, "legal action executes " + id)
	return next


func _resolution_counterexamples(question: Dictionary, session: Variant) -> void:
	var source: Dictionary = session.stores.fact_store.get_fact(question.source)
	var evidence := {"source_fact_id": "test_injection.local_observation", "observed_hour": 50,
		"threats": [{"id": "world_threat.field_boar", "name": "测试中在场的威胁"}], "traces": []}
	var active: Dictionary = question.duplicate(true)
	Interest.resolve_place(active, evidence, source, true)
	_check(active.resolution_type == "ACTIVE_SITUATION" and active.answer.contains("确实看见"), "test injection: visible ongoing danger is active, not cold")
	evidence.threats.clear()
	evidence.traces.append({"subject": question.subject, "when": 45, "source": "test_injection.public_notice", "text": "测试注入：此人在这里留下过公开求助口信"})
	var aftermath: Dictionary = question.duplicate(true)
	Interest.resolve_place(aftermath, evidence, source, true)
	_check(aftermath.resolution_type == "AFTERMATH" and aftermath.new_information_count == 2, "test injection: genuinely newer public evidence gives limited aftermath")
	_check(aftermath.answer.contains("不能证明危险被击退"), "a person's notice does not identify a danger's fate")
	evidence.traces[0].when = 30
	var old: Dictionary = question.duplicate(true)
	Interest.resolve_place(old, evidence, source, true)
	_check(old.resolution_type == "COLD_TRAIL", "already old departure cannot be advertised as new information")
	var snapshot: Variant = _snapshot(session)
	var observation := Interest.local_evidence(session, snapshot)
	_check(observation.traces.all(func(t: Dictionary) -> bool: return t.where == session.context.location_id), "evidence is restricted to local traces")
