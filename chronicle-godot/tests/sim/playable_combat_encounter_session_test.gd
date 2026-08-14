extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
)
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const FIGHT := "combat:mist_salt_well_claimant:fight_balanced"
const RETREAT := "combat:mist_salt_well_claimant:retreat"
const NEGOTIATE := "combat:mist_salt_well_claimant:negotiate"
const HAMMER_ID := "item_instance.lake_town.player_field_hammer"
const LANTERN_ID := "item_instance.lake_town.player_patrol_lantern"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS
	)
	_check(
		bool(start.get("success", false))
		and int(start.get("combat_encounter_definition_count", 0)) == 2
		and int(start.get("combat_encounter_seed", 0)) == 516
		and str(session.get_snapshot().get_equipped_item(
			"player", "main_hand"
		).get("item_instance_id", "")) == HAMMER_ID
		and str(session.get_snapshot().get_equipped_item(
			"player", "utility"
		).get("item_instance_id", "")) == LANTERN_ID,
		"1. 湖湾镇启动时加载正式遭遇定义和旅人野外装备"
	)
	if not bool(start.get("success", false)):
		_finish()
		return
	_check(_reach_well(session), "2. 正常调查流程抵达雾盐旧井")

	var options: Array = session.get_combat_encounter_options()
	var fight := _find_option(options, FIGHT)
	var retreat := _find_option(options, RETREAT)
	var negotiate := _find_option(options, NEGOTIATE)
	var fight_preview: Dictionary = fight.get("preview", {})
	var retreat_preview: Dictionary = retreat.get("preview", {})
	var negotiate_preview: Dictionary = negotiate.get("preview", {})
	_check(
		options.size() == 3
		and not fight.is_empty()
		and not retreat.is_empty()
		and not negotiate.is_empty()
		and int(fight_preview.get("effective_score", 0)) == 13
		and int(fight_preview.get("required_roll", 0)) == 4
		and int(retreat_preview.get("effective_score", 0)) == 15
		and int(retreat_preview.get("required_roll", 0)) == 2
		and int(negotiate_preview.get("effective_score", 0)) == 10
		and int(negotiate_preview.get("required_roll", 0)) == 4,
		"3. 三种处理方式显示装备计入后的独立数值与最低骰点"
	)
	_check(
		int((fight_preview.get("possible_costs", {}) as Dictionary).get(
			"health_loss", 0
		)) == 5
		and not ((fight_preview.get(
			"possible_costs", {}
		) as Dictionary).get("descriptions", []) as Array).is_empty()
		and _modifier_applied(
			fight_preview, "field_hammer_melee_attack"
		)
		and _modifier_applied(
			retreat_preview, "patrol_lantern_dim_retreat"
		),
		"4. 选择前可见非致死代价，并能解释工锤与巡灯为何生效"
	)

	var time_before := session.get_time_summary().duplicate(true)
	var log_count_before := session.get_world_log_entries().size()
	var result: Dictionary = session.execute_combat_encounter_option(
		FIGHT,
		{"source": "test_injection", "roll_override": 1}
	)
	var hammer: Dictionary = session.stores["item_store"].get_item(HAMMER_ID)
	_check(
		bool(result.get("success", false))
		and str(result.get("outcome", "")) == "failure"
		and int(result.get("roll", 0)) == 1
		and int(session.get_time_summary().get("elapsed_hours", 0))
			== int(time_before.get("elapsed_hours", 0)) + 1
		and int(session.stores["state_store"].get_state(
			"player", "health", 0
		)) == 95
		and int(session.stores["state_store"].get_state(
			"player", "fatigue", 0
		)) == 2
		and int((hammer.get("condition", {}) as Dictionary).get(
			"durability", 0
		)) == 64
		and _has_trait(session, "trait.combat_bruising"),
		"5. 失败写回一小时、健康、疲劳、战斗挫伤和工锤耐久"
	)
	var log_count_after := session.get_world_log_entries().size()
	_check(
		session.get_combat_encounter_options().is_empty()
		and not _visible_entity(session, "mist_salt_well_claimant")
		and _has_fact(session, "actor_resolved_combat_encounter")
		and _has_fact(session, "mist_salt_claimant_won_brief_clash")
		and log_count_after > log_count_before
		and _combat_log_count(session, "mist_salt_well_claimant") == 1,
		"6. 任一结果都让对手离场、消费全部方案并形成可追溯事实"
	)

	var time_after := session.get_time_summary().duplicate(true)
	var stale: Dictionary = session.execute_combat_encounter_option(FIGHT)
	_check(
		not bool(stale.get("success", true))
		and str(stale.get("error", ""))
			== "combat_encounter_option_not_found"
		and session.get_time_summary() == time_after
		and session.get_world_log_entries().size() == log_count_after
		and _combat_log_count(session, "mist_salt_well_claimant") == 1,
		"7. 旧选项不能重复推进时间、磨损装备或污染世界日志"
	)

	var envelope: Dictionary = session.build_save_envelope({
		"save_id": "save.test.playable_combat_encounter",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-14T13:00:00Z",
		"saved_at_utc": "2026-08-14T13:01:00Z",
	})
	var restored = SimSessionModel.new()
	var restore: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(envelope))
	)
	_check(
		bool(restore.get("success", false))
		and restored.combat_encounter_count == 1
		and restored.get_combat_encounter_options().is_empty()
		and int((restored.stores["item_store"].get_item(
			HAMMER_ID
		).get("condition", {}) as Dictionary).get("durability", 0)) == 64
		and _has_trait(restored, "trait.combat_bruising")
		and bool(restored.validate_persistent_references().get("ok", false)),
		"8. 已消费遭遇、伤势和装备磨损经过存档往返保持一致"
	)
	_finish()


func _reach_well(session: Variant) -> bool:
	var results: Array[Dictionary] = [
		session.travel("old_chen_shop_to_abandoned_granary"),
		session.execute_challenge_option("prepare_granary_entry"),
		session.execute_challenge_option(
			"enter_abandoned_granary",
			{"source": "test_injection", "roll_override": 3}
		),
		session.travel("abandoned_granary_to_old_chen_shop"),
		session.execute_return_echo_option(
			"show_granary_measure_token_to_chen_mi"
		),
		session.execute_investigation_option(
			"investigate_public_granary_seal_records"
		),
		session.execute_action(
			"read_visible_readable_object:old_chen_public_granary_tax_deed"
		),
		session.advance_time(6, "wait_for_north_quay_ferry"),
		session.travel("old_chen_shop_to_north_quay_record_house"),
		session.execute_challenge_option("prepare_flooded_archive_search"),
		session.execute_challenge_option(
			"search_flooded_archive_stack",
			{"source": "test_injection", "roll_override": 1}
		),
		session.execute_challenge_option(
			"prepare_mist_salt_well_expedition"
		),
		session.travel("north_quay_record_house_to_mist_salt_well"),
	]
	for result: Dictionary in results:
		if not bool(result.get("success", false)):
			return false
	return str(session.context.location_id) == "mist_salt_well"


func _find_option(options: Array, option_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("option_id", "")) == option_id:
			return option
	return {}


func _modifier_applied(preview: Dictionary, modifier_id: String) -> bool:
	for modifier: Dictionary in preview.get("modifier_evaluations", []):
		if (
			str(modifier.get("modifier_id", "")) == modifier_id
			and bool(modifier.get("applied", false))
		):
			return true
	return false


func _has_fact(session: Variant, fact_type: String) -> bool:
	return not session.stores["fact_store"].find_facts_by_type(
		fact_type
	).is_empty()


func _has_trait(session: Variant, trait_def_id: String) -> bool:
	for instance: Dictionary in session.stores[
		"character_feature_store"
	].list_trait_instances("player"):
		if (
			str(instance.get("trait_def_id", "")) == trait_def_id
			and str(instance.get("status", "active")) == "active"
		):
			return true
	return false


func _visible_entity(session: Variant, entity_id: String) -> bool:
	for entity: Dictionary in session.get_snapshot().get_visible_entities():
		if str(entity.get("id", "")) == entity_id:
			return true
	return false


func _combat_log_count(session: Variant, encounter_id: String) -> int:
	var count := 0
	for entry: Dictionary in session.get_world_log_entries():
		if (
			str(entry.get("entry_type", "")) == "combat_encounter"
			and str(entry.get("encounter_id", "")) == encounter_id
		):
			count += 1
	return count


func _finish() -> void:
	if failures.is_empty():
		print("[V5 PLAYABLE COMBAT ENCOUNTER SESSION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 PLAYABLE COMBAT ENCOUNTER SESSION FAIL] " + failure)
	print(
		"[V5 PLAYABLE COMBAT ENCOUNTER SESSION RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 PLAYABLE COMBAT ENCOUNTER SESSION PASS] " + message)
	else:
		failures.append(message)
