extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const CombatResolverModel = preload(
	"res://scripts/sim/combat/combat_encounter_resolver.gd"
)
const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const ENEMY_ID := "combat_contract_mist_hound"
const HAMMER_ID := "item_instance.seventh_outpost.player_repair_hammer"
const SPEAR_ID := "item_instance.combat_contract.boar_spear"

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
		and int(start.get("definition_count", 0)) == 106,
		"1. 装备战斗合同随正式定义和第七哨站世界启动"
	)
	if not bool(start.get("success", false)):
		_finish()
		return
	_check(_add_enemy(session), "2. 遭遇目标作为正式 Entity 接入世界")
	_check(_create_spear(session), "3. 猎豕矛通过事实和物品事务创建")

	var resolver = CombatResolverModel.new()
	resolver.configure(session.registry)
	var encounter := _encounter()
	var hammer_snapshot: Variant = session.get_snapshot()
	var hammer_preview: Dictionary = resolver.preview(
		encounter, hammer_snapshot, "fight_balanced"
	)
	_check(
		bool(hammer_preview.get("ok", false))
		and str((hammer_preview.get(
			"enemy_observation", {}
		) as Dictionary).get("danger_label", "")) == "高"
		and not ((hammer_preview.get(
			"enemy_observation", {}
		) as Dictionary).get("observable_features", []) as Array).is_empty()
		and int(hammer_preview.get("effective_score", 0)) == 13
		and int(hammer_preview.get("guard", 0)) == 16
		and int((hammer_preview.get(
			"possible_costs", {}
		) as Dictionary).get("health_loss", 0)) == 5,
		"4. 预览在行动前显示敌人、危险、工锤攻防和非死亡代价"
	)
	_check(
		_has_modifier(
			hammer_preview, "field_hammer_melee_attack", true
		)
		and _has_modifier(
			hammer_preview, "waxed_cloak_combat_guard", true
		)
		and _has_modifier(
			hammer_preview, "patrol_lantern_dim_retreat", false
		)
		and not _modifier_unmet(
			hammer_preview, "patrol_lantern_dim_retreat"
		).is_empty(),
		"5. 统一 Modifier 同时解释已触发装备和未触发被动"
	)
	_check(
		hammer_preview == resolver.preview(
			encounter, hammer_snapshot, "fight_balanced"
		),
		"6. 相同世界与处理方式得到完全一致的预览"
	)

	var hammer_failure = resolver.resolve_attempt(
		encounter,
		hammer_snapshot,
		"fight_balanced",
		2,
		201,
		{"day": 3, "hour": 19, "tick": 67}
	)
	_check(
		str(hammer_failure.contract_status) == "resolved"
		and str(hammer_failure.narrative_result.get("outcome", "")) == "failure"
		and int(hammer_failure.narrative_result.get("total", 0)) == 15
		and session.writer.apply_result(hammer_failure, session.stores),
		"7. 同骰点下工锤方案失败并以原子事务写入"
	)
	var hammer_after: Dictionary = session.stores["item_store"].get_item(HAMMER_ID)
	_check(
		int(session.stores["state_store"].get_state(
			"player", "health", 0
		)) == 95
		and int(session.stores["state_store"].get_state(
			"player", "fatigue", 0
		)) == 2
		and int((hammer_after.get("condition", {}) as Dictionary).get(
			"durability", 0
		)) == 64
		and _item_history_has_fact(
			hammer_after, "fact.combat_encounter.contract_mist_hound.201"
		)
		and _has_trait(session, "trait.combat_bruising"),
		"8. 失败写入健康、疲劳、伤势特质和工锤耐久履历"
	)
	var injured_preview: Dictionary = resolver.preview(
		encounter, session.get_snapshot(), "fight_balanced"
	)
	_check(
		int(injured_preview.get("guard", 0)) == 15
		and _has_modifier(
			injured_preview, "combat_bruising_guard_penalty", true
		),
		"9. 新伤势进入下一次检定并明确降低防守"
	)

	_check(
		_equip(session, SPEAR_ID, 202),
		"10. 玩家通过装备事务把主手从工锤换成猎豕矛"
	)
	var spear_snapshot: Variant = session.get_snapshot()
	var spear_preview: Dictionary = resolver.preview(
		encounter, spear_snapshot, "fight_balanced"
	)
	var calm_encounter := encounter.duplicate(true)
	(calm_encounter.get("enemy", {}) as Dictionary)["tags"] = ["beast"]
	(calm_encounter.get("enemy", {}) as Dictionary)["observable_tags"] = ["beast"]
	var calm_preview: Dictionary = resolver.preview(
		calm_encounter, spear_snapshot, "fight_balanced"
	)
	_check(
		int(spear_preview.get("effective_score", 0)) == 17
		and int(calm_preview.get("effective_score", 0)) == 15
		and _has_modifier(
			spear_preview, "boar_spear_brace_against_charge", true
		)
		and _has_modifier(
			calm_preview, "boar_spear_brace_against_charge", false
		)
		and "enemy_charging" in _modifier_unmet(
			calm_preview, "boar_spear_brace_against_charge"
		),
		"11. 猎豕矛冲锋被动会命中，也会说明未命中的目标条件"
	)
	var spear_success = resolver.resolve_attempt(
		encounter,
		spear_snapshot,
		"fight_balanced",
		2,
		203,
		{"day": 3, "hour": 20, "tick": 68}
	)
	_check(
		str(spear_success.contract_status) == "resolved"
		and str(spear_success.narrative_result.get("outcome", "")) == "success"
		and int(spear_success.narrative_result.get("total", 0)) == 19
		and session.writer.apply_result(spear_success, session.stores)
		and int(session.stores["state_store"].get_state(
			"player", "health", 0
		)) == 95
		and int((session.stores["item_store"].get_item(
			SPEAR_ID
		).get("condition", {}) as Dictionary).get("durability", 0)) == 89,
		"12. 同一骰点换成猎豕矛后成功，成功仍留下轻微装备磨损"
	)

	var retreat_preview: Dictionary = resolver.preview(
		encounter, session.get_snapshot(), "retreat"
	)
	var negotiate_preview: Dictionary = resolver.preview(
		encounter, session.get_snapshot(), "negotiate"
	)
	_check(
		bool(retreat_preview.get("ok", false))
		and int(retreat_preview.get("effective_score", 0)) == 15
		and _has_modifier(
			retreat_preview, "patrol_lantern_dim_retreat", true
		)
		and bool(negotiate_preview.get("ok", false))
		and int(negotiate_preview.get("effective_score", 0)) == 10
		and not ((retreat_preview.get(
			"possible_costs", {}
		) as Dictionary).get("descriptions", []) as Array).is_empty(),
		"13. 同一遭遇提供撤离与交涉分数，并在选择前展示代价"
	)
	var invalid_roll = resolver.resolve_attempt(
		encounter, session.get_snapshot(), "fight_balanced", 7, 204
	)
	_check(
		str(invalid_roll.contract_status) == "invalid_contract"
		and str(invalid_roll.error_reason) == "combat_roll_out_of_range",
		"14. 解析器拒绝合同外骰值，不在内部偷偷重抽"
	)

	var before_save: Dictionary = session.get_save_store_data()
	var envelope: Dictionary = session.build_save_envelope({
		"save_id": "save.test.combat_equipment",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-14T12:00:00Z",
		"saved_at_utc": "2026-08-14T12:30:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_save_envelope(
		JSON.parse_string(JSON.stringify(envelope))
	)
	var stores_equal := false
	var equipped_main_hand := ""
	var restored_injury := false
	var references_ok := false
	if bool(restore_report.get("success", false)):
		var restored_data: Dictionary = restored.get_save_store_data()
		stores_equal = _equivalent(restored_data, before_save)
		equipped_main_hand = str(restored.get_snapshot().get_equipped_item(
			"player", "main_hand"
		).get("item_instance_id", ""))
		restored_injury = _has_trait(restored, "trait.combat_bruising")
		references_ok = bool(restored.validate_persistent_references().get(
			"ok", false
		))
	_check(
		bool(restore_report.get("success", false))
		and stores_equal
		and equipped_main_hand == SPEAR_ID
		and restored_injury
		and references_ok,
		"15. 战斗事实、伤势、装备与耐久经过存档往返保持一致"
	)
	_finish()


func _encounter() -> Dictionary:
	return {
		"encounter_id": "contract_mist_hound",
		"context_tags": ["dim_light", "muddy_ground"],
		"enemy": {
			"entity_id": ENEMY_ID,
			"display_name": "雾沼猎犬",
			"danger_label": "高",
			"observable_features": [
				"肩背压低，正在准备直线扑击",
				"前腿沾满湿泥，转向不会太快",
			],
			"observable_tags": ["beast", "charging"],
			"tags": ["beast", "charging"],
			"attack": 18,
			"defense": 19,
			"pursuit": 17,
			"resolve": 16,
		},
		"approaches": [
			{
				"approach_id": "fight_balanced",
				"label": "稳住架势迎击",
				"score_target": "combat.attack",
				"difficulty_key": "defense",
				"action_tags": ["combat_melee", "balanced_stance"],
				"success": {
					"fatigue_gain": 1,
					"durability_loss": 1,
					"durability_slot": "main_hand",
					"narrative_title": "逼退猎犬",
					"narrative": "你借装备和地形稳住了扑击，猎犬退进雾里。",
				},
				"failure": {
					"base_health_loss": 3,
					"fatigue_gain": 1,
					"injury": "combat_bruising",
					"injury_label": "战斗挫伤",
					"durability_loss": 4,
					"durability_slot": "main_hand",
					"narrative_title": "被扑倒后脱身",
					"narrative": "你被撞倒又挣脱，伤势和受损装备替代了死亡结局。",
				},
			},
			{
				"approach_id": "retreat",
				"label": "借暗处撤离",
				"score_target": "combat.escape",
				"difficulty_key": "pursuit",
				"action_tags": ["combat_retreat"],
				"success": {
					"fatigue_gain": 1,
					"durability_loss": 1,
					"durability_slot": "utility",
				},
				"failure": {
					"base_health_loss": 1,
					"fatigue_gain": 2,
					"durability_loss": 2,
					"durability_slot": "utility",
				},
			},
			{
				"approach_id": "negotiate",
				"label": "放低武器安抚",
				"score_target": "combat.influence",
				"difficulty_key": "resolve",
				"action_tags": ["combat_negotiate"],
				"success": {"fatigue_gain": 0},
				"failure": {"fatigue_gain": 1},
			},
	],
	}


func _add_enemy(session: Variant) -> bool:
	var entity_store: Variant = session.stores["entity_store"]
	return entity_store.add_entity(ENEMY_ID, {
			"type": "object",
			"display_name": "雾沼猎犬",
			"description": "用于装备战斗合同验收的可追溯遭遇实体。",
			"tags": ["enemy", "beast"],
		})


func _create_spear(session: Variant) -> bool:
	var result = TransactionResultModel.new()
	var fact_id := "fact.combat_contract.spear_created"
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "item_created",
		"actor_id": "player",
		"target_id": "player",
		"item_instance_id": SPEAR_ID,
		"tick": 60,
	})
	result.add_item_change({
		"operation": "create",
		"item": {
			"item_instance_id": SPEAR_ID,
			"item_def_id": "item.outpost_boar_spear",
			"holder": {"kind": "entity", "id": "player"},
			"quantity": 1,
			"condition": {
				"durability": 90,
				"maximum_durability": 90,
				"quality": "serviceable",
			},
			"provenance": {"original_owner_entity_id": "seventh_outpost"},
			"created_tick": 60,
			"updated_tick": 60,
		},
		"source_fact_ids": [fact_id],
	})
	result.mark_resolved("combat_equipment_setup")
	return session.writer.apply_result(result, session.stores)


func _equip(session: Variant, item_id: String, event_id: int) -> bool:
	var result = TransactionResultModel.new()
	var fact_id := "fact.combat_contract.equipment_changed.%d" % event_id
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "equipment_changed",
		"actor_id": "player",
		"target_id": "player",
		"item_instance_id": item_id,
		"slot_id": "main_hand",
		"tick": event_id,
	})
	result.add_equipment_change({
		"operation": "equipment_set",
		"entity_id": "player",
		"slot_id": "main_hand",
		"item_instance_id": item_id,
		"source_fact_ids": [fact_id],
		"updated_tick": event_id,
	})
	result.mark_resolved("combat_equipment_setup")
	return session.writer.apply_result(result, session.stores)


func _has_modifier(
		preview_data: Dictionary, modifier_id: String, applied: bool
) -> bool:
	for row: Dictionary in preview_data.get("modifier_evaluations", []):
		if (
			str(row.get("modifier_id", "")) == modifier_id
			and bool(row.get("applied", false)) == applied
		):
			return true
	return false


func _modifier_unmet(
		preview_data: Dictionary, modifier_id: String
) -> String:
	for row: Dictionary in preview_data.get("modifier_evaluations", []):
		if str(row.get("modifier_id", "")) != modifier_id:
			continue
		return "；".join(row.get("unmet_conditions", []))
	return ""


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


func _item_history_has_fact(item: Dictionary, fact_id: String) -> bool:
	for history: Dictionary in item.get("history", []):
		if str(history.get("fact_id", "")) == fact_id:
			return true
	return false


func _equivalent(left: Variant, right: Variant) -> bool:
	return JSON.stringify(_normalize_json_numbers(left)) == JSON.stringify(
		_normalize_json_numbers(right)
	)


func _normalize_json_numbers(value: Variant) -> Variant:
	if value is float and is_equal_approx(float(value), round(float(value))):
		return int(value)
	if value is Array:
		var rows: Array = []
		for child: Variant in value:
			rows.append(_normalize_json_numbers(child))
		return rows
	if value is Dictionary:
		var row: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			row[key] = _normalize_json_numbers((value as Dictionary).get(key))
		return row
	return value


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 COMBAT EQUIPMENT PASS] " + message)
		return
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 COMBAT EQUIPMENT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 COMBAT EQUIPMENT FAIL] " + failure)
	print("[V5 COMBAT EQUIPMENT RESULT] FAIL: %s" % JSON.stringify(failures))
	quit(1)
