extends SceneTree
## Regressions discovered during stepwise, public-information self-play.

const Agent = preload("res://scripts/agent/agent_game_session.gd")
const Surface = preload("res://scripts/rebuild/roaming_presentation.gd")
var game := Agent.new()
var serial := 0
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func request(command: String, fields: Dictionary = {}) -> Dictionary:
	serial += 1
	var payload := {"protocol": 1, "command": command, "request_id": "selfplay." + str(serial),
		"session_id": game.session_id, "expected_revision": game.revision}
	payload.merge(fields)
	var response := game.handle(payload)
	check(response.ok, command + " accepted: " + str(response.get("error", "")))
	return response


func act(id: String) -> Dictionary:
	return request("act", {"choice_id": id, "confirm": true})


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func run() -> void:
	var r := request("start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v2"})
	var features_before: Dictionary = game.model.session.stores.character_feature_store.to_save_data().duplicate(true)
	check(game.model.session.PlayerLife.Equipment.combat_growth_warning(game.model.session, "guard").contains("进攻-1"), "first defense discloses its permanent attack penalty before execution")
	check(game.model.session.PlayerLife.Equipment.combat_growth_warning(game.model.session, "withdraw") == "", "withdrawal is not given a fictional negative trait")
	check(features_before == game.model.session.stores.character_feature_store.to_save_data(), "growth preview does not grant a trait")
	var preview_session: Variant = game.model.session
	var stock: Dictionary = preview_session.registry.get_definition("item", "item.light_reed_mantle").duplicate(true)
	check(not stock.is_empty(), "purchase preview uses a registered equipment definition")
	var equipment_before: Dictionary = preview_session.stores.equipment_store.to_save_data().duplicate(true)
	var purchase: String = preview_session.PlayerLife.Equipment.purchase_description(preview_session, stock)
	check(purchase.contains("脱离+2") and purchase.contains("防守+1"), "purchase preview exposes actual equipment effects before payment")
	check(purchase.contains("上蜡冬衣") and purchase.contains("防守+2"), "purchase preview compares the player's actual worn equipment")
	check(purchase.contains("不会自动替换") and equipment_before == preview_session.stores.equipment_store.to_save_data(), "purchase preview neither equips nor implies automatic replacement")
	r = act("player_life/situation:ask:generated_resident.echo_landing.008:")
	check(r.choices.filter(func(c: Dictionary) -> bool: return c.get("intent") == "pursue" and c.get("subject_id") == "generated_resident.echo_landing.008").is_empty(), "do not send player away to find the visible person")
	r = act("player_life/ask_local:generated_resident.echo_landing.001")
	var text := str(r.observation.feedback.body)
	check(not text.contains("废灯台") and not text.contains("水洞"), "disabled authored routes are not advertised by local testimony")
	r = act("travel/generated_route.echo_landing.commons_to_watch_service")
	var person_leads: Array = r.choices.filter(func(c: Dictionary) -> bool: return c.get("intent") == "pursue" and c.get("subject_id") == "generated_resident.echo_landing.008")
	check(person_leads.size() == 1, "sighting and stated intention yield one actionable lead per person")
	if person_leads.size() == 1:
		check(person_leads[0].get("lead_kind") == "intention", "destination stated during the same sighting takes priority")
		check(str(person_leads[0].id).ends_with("generated_location.echo_landing.road_yard"), "known intention is retained without tracking current remote position")
	# Reproduce the actual hand-played trip, with no forced location or dice.
	r = act("travel/generated_route.echo_landing.watch_service_to_commons")
	r = act("travel/generated_route.network.echo_shore_road.a_to_b")
	r = act("player_life/situation:ask:generated_resident.echo_terrace.008:")
	r = act("player_life/situation:fund:generated_resident.echo_terrace.008:")
	r = act("player_life/eat:item_instance.journey.traveler.provisions")
	r = act("player_life/situation:pursue:generated_resident.echo_terrace.008:generated_location.echo_terrace.terraces")
	check(r.observation.feedback.pursuit.resolution_type == "COLD_TRAIL" and str(r.observation.feedback.body).contains("眼下没有看见威胁"), "actual empty danger destination acknowledges the mismatch without declaring permanent safety")
	check(str(r.observation.feedback.compact_body).begins_with(str(r.observation.feedback.pursuit.answer)), "arrival result is first in the bounded inline UI, not hidden behind generic travel prose")
	var scene := Surface.build(r)
	check(scene.choices.all(func(c: Dictionary) -> bool: return c.get("intent") != "whereabouts"), "main scene does not fill with every other acquaintance")
	check(Surface.build(r, "talk").choices.any(func(c: Dictionary) -> bool: return c.get("intent") == "whereabouts"), "deliberate search questions remain available under conversation")
	# Test injection: only move the test clock, not a natural-play result.
	var session: Variant = game.model.session
	session.current_day += 1
	session.current_hour = 1
	var timed: Array = session.PlayerLife.Situations.options(session).filter(func(c: Dictionary) -> bool: return c.label == "原地等到06:00")
	check(timed.size() == 1 and int(timed[0].minutes) <= 300, "after midnight the next wait target is dawn, not 17:00")
	check(game.model._state_change_text({"entity_id": "player", "key": "danger_grace_until", "to": 99}) == "", "combat grace implementation key is not player-facing prose")
	# Preserve authored-route advice in the actual authored mode.
	r = request("start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_roaming_v1"})
	# The authored opening can temporarily own the choices; test its underlying guide directly.
	session = game.model.session
	check(session.advance_time(2, "test_legacy_morning").success, "legacy residents establish themselves under their own rules")
	var snapshot: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	var speaker: Dictionary = snapshot.get_entity("generated_resident.echo_landing.001")
	var info: Dictionary = session.PlayerLife.Local.local_statement(session, snapshot, snapshot.get_entity(str(session.context.actor_id)), speaker)
	check(session.PlayerLife.Local.statement_brief(session, speaker, info).contains("废灯台"), "authored adventure guidance is preserved in its own mode")
	print("SELFPLAY_REGRESSION %d/%d %s" % [checks - failures.size(), checks, str(failures)])
	quit(0 if failures.is_empty() else 1)
