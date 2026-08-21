extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const CharacterFeatureStoreModel = preload(
	"res://scripts/sim/character_feature/character_feature_store.gd"
)
const EntityStoreModel = preload("res://scripts/sim/entity/entity_store.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")

const FEATURE_DEFS_PATH := (
	"res://data/sim/raw/character_feature_defs/basic_character_feature_defs.json"
)
const STATE_DEFS_PATH := "res://data/sim/raw/state_defs/basic_state_defs.json"
const OBJECT_DEFS_PATH := "res://data/sim/raw/object_defs/basic_object_defs.json"
const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = SimRegistryModel.new()
	var definition_report: Dictionary = registry.load_raw_definition_files([
		STATE_DEFS_PATH,
		OBJECT_DEFS_PATH,
		FEATURE_DEFS_PATH,
	])
	_check(
		bool(definition_report.get("ok", false))
		and int(definition_report.get("total_definition_count", 0)) == 85
		and registry.has_definition("talent", "talent.night_adapted_eyes")
		and registry.has_definition("talent", "talent.steady_hands")
		and registry.has_definition("trait", "trait.twisted_ankle")
		and registry.has_definition("trait", "trait.combat_bruising")
		and registry.has_definition("trait", "trait.winter_work_callus")
		and registry.has_definition("trait", "trait.fire_circle_belonging")
		and registry.has_definition("mark", "mark.mist_salt_echo")
		and registry.has_definition("mark", "mark.winter_wall_callus")
		and registry.has_definition("skill", "skill.scouting")
		and registry.has_definition("skill", "skill.maintenance")
		and registry.has_definition("skill", "skill.archery"),
		"1. 四类角色特征 Definition 以稳定 ID 通过严格注册"
	)

	var invalid_registry = SimRegistryModel.new()
	_check(
		not invalid_registry.register_definition("mark", "mark.invalid", {
			"definition_version": 1,
			"display_name_key": "mark.invalid.name",
			"tags": [],
			"modifiers": [],
			"granted_affordance_tags": [],
			"accepted_fact_types": [],
			"stages": [
				{"stage_id": "late", "threshold": 4},
				{"stage_id": "early", "threshold": 1},
			],
		})
		and not bool(invalid_registry.get_definition_report().get("ok", true)),
		"2. Registry 拒绝缺少事实来源或阶段阈值倒序的 MarkDef"
	)
	var invalid_progress_registry = SimRegistryModel.new()
	_check(
		not invalid_progress_registry.register_definition(
			"mark",
			"mark.invalid_progress_rule",
			{
				"definition_version": 1,
				"display_name_key": "mark.invalid_progress_rule.name",
				"tags": [],
				"modifiers": [],
				"granted_affordance_tags": [],
				"accepted_fact_types": ["test_mark_progress"],
				"progress_by_fact_type": {"test_mark_progress": 1},
				"progress_rules": [
					{"fact_type": "unaccepted_fact", "delta": 1},
				],
				"stages": [{"stage_id": "noticed", "threshold": 1}],
			}
		)
		and not bool(invalid_progress_registry.get_definition_report().get(
			"ok", true
		)),
		"2B. Registry rejects a Mark progress rule for an unaccepted fact"
	)
	var malformed_registry = SimRegistryModel.new()
	_check(
		not malformed_registry.register_definition("skill", "skill.malformed", {
			"definition_version": 1,
			"display_name_key": "skill.malformed.name",
			"tags": [],
			"modifiers": [],
			"rank_thresholds": [0, "bad"],
			"accepted_practice_fact_types": ["test_practice"],
			"practice_rules": ["bad"],
		})
		and not bool(malformed_registry.get_definition_report().get("ok", true)),
		"3. Registry 将畸形 FeatureDef 安全返回为合同错误而不触发崩溃"
	)

	var entity_store = EntityStoreModel.new()
	entity_store.configure_definitions(registry.list_definitions("object"), true)
	_check(
		entity_store.add_entity("player", {"type": "person", "role": "traveler"}),
		"4. 角色特征测试拥有已注册的角色实体"
	)
	var fact_store = FactStoreModel.new()
	var feature_store = CharacterFeatureStoreModel.new()
	feature_store.configure({
		"talent": registry.list_definitions("talent"),
		"trait": registry.list_definitions("trait"),
		"mark": registry.list_definitions("mark"),
		"skill": registry.list_definitions("skill"),
	}, entity_store, fact_store)
	_check(
		feature_store.assign_talent({
			"talent_assignment_id": "talent_assignment.test.player.night_eyes",
			"talent_def_id": "talent.night_adapted_eyes",
			"owner_entity_id": "player",
			"status": "active",
			"source_kind": "test_fixture",
			"source_fact_ids": [],
			"assigned_tick": 0,
		})
		and not feature_store.assign_talent({
			"talent_assignment_id": "talent_assignment.test.player.duplicate",
			"talent_def_id": "talent.night_adapted_eyes",
			"owner_entity_id": "player",
			"status": "active",
			"source_kind": "test_fixture",
			"source_fact_ids": [],
			"assigned_tick": 0,
		}),
		"5. TalentAssignment 接受受控来源并拒绝同角色重复天赋"
	)
	_check(
		not feature_store.load_trait_instance({
			"trait_instance_id": "trait_instance.test.no_fact",
			"trait_def_id": "trait.twisted_ankle",
			"owner_entity_id": "player",
			"stage_id": "fresh",
			"severity": 2,
			"status": "active",
			"source_fact_ids": [],
		}),
		"6. 运行时 TraitInstance 没有来源事实时被拒绝"
	)

	var injury_fact := {
		"fact_id": "fact.test.injury.1",
		"fact_type": "actor_injured_during_challenge",
		"source_id": "player",
		"injury": "twisted_ankle",
		"tick": 12,
	}
	fact_store.add_fact(injury_fact)
	var injury_apply: Dictionary = feature_store.apply_facts([injury_fact])
	_check(
		int(injury_apply.get("trait_instances_created", 0)) == 1
		and feature_store.list_trait_instances("player").size() == 1
		and str((feature_store.list_trait_instances("player")[0] as Dictionary).get(
			"trait_def_id",
			""
		)) == "trait.twisted_ankle",
		"7. 已写入 FactStore 的挑战伤势事实创建可追溯 TraitInstance"
	)
	feature_store.apply_facts([injury_fact])
	_check(
		feature_store.list_trait_instances("player").size() == 1,
		"8. 同一伤势事实不会重复创建 TraitInstance"
	)
	feature_store.apply_facts([{
		"fact_id": "fact.test.injury.1",
		"fact_type": "actor_acquired_mist_salt_echo",
		"source_id": "player",
	}])
	_check(
		feature_store.list_mark_instances("player").is_empty(),
		"9. 同 ID 的伪造 payload 不能绕过 FactStore 规范事实触发 Mark"
	)
	_check(
		not feature_store.load_mark_instance({
			"mark_instance_id": "mark_instance.test.invalid_source",
			"mark_def_id": "mark.mist_salt_echo",
			"owner_entity_id": "player",
			"progress": 1,
			"status": "active",
			"source_fact_ids": ["fact.test.injury.1"],
			"progress_events": [
				{"fact_id": "fact.test.injury.1", "delta": 1},
			],
		}),
		"10. MarkInstance 拒绝 Definition 未接受的来源事实类型"
	)
	_check(
		not feature_store.load_skill_progress({
			"skill_progress_id": "skill_progress.test.forged",
			"skill_def_id": "skill.scouting",
			"owner_entity_id": "player",
			"practice_xp": 99,
			"source_fact_ids": ["fact.test.injury.1"],
			"practice_events": [
				{"fact_id": "fact.test.injury.1", "xp": 99},
			],
		}),
		"11. SkillProgress 拒绝非练习事实及伪造的 XP"
	)

	var echo_fact := {
		"fact_id": "fact.test.echo.1",
		"fact_type": "actor_acquired_mist_salt_echo",
		"source_id": "player",
		"tick": 20,
	}
	fact_store.add_fact(echo_fact)
	feature_store.apply_facts([echo_fact, echo_fact])
	var mark: Dictionary = feature_store.list_mark_instances("player")[0]
	_check(
		int(mark.get("progress", 0)) == 1
		and str(mark.get("stage_id", "")) == "faint"
		and (mark.get("progress_events", []) as Array).size() == 1,
		"12. Mark 阶段由事实进度推导且同一事实只贡献一次"
	)

	var patrol_fact := {
		"fact_id": "fact.test.patrol.1",
		"fact_type": "life_project_duty_completed",
		"actor_id": "player",
		"duty_id": "patrol_fog_line",
		"tick": 30,
	}
	fact_store.add_fact(patrol_fact)
	feature_store.apply_facts([patrol_fact, patrol_fact])
	var skill: Dictionary = feature_store.list_skill_progress("player")[0]
	_check(
		int(skill.get("practice_xp", 0)) == 8
		and int(skill.get("rank", -1)) == 0
		and (skill.get("practice_events", []) as Array).size() == 1,
		"13. Skill XP 来自匹配职责事实，rank 由阈值推导且事实去重"
	)

	var unrelated_fact := {
		"fact_id": "fact.test.unrelated.1",
		"fact_type": "life_project_duty_completed",
		"actor_id": "player",
		"duty_id": "share_hard_bread",
	}
	fact_store.add_fact(unrelated_fact)
	feature_store.apply_facts([unrelated_fact])
	_check(
		int((feature_store.list_skill_progress("player")[0] as Dictionary).get(
			"practice_xp",
			0
		)) == 8,
		"14. 不匹配侦察规则的职责事实不会伪造技艺成长"
	)

	var singleton_registered := registry.register_definition(
		"trait",
		"trait.test_singleton",
		{
			"definition_version": 1,
			"display_name_key": "trait.test_singleton.name",
			"tags": ["test"],
			"stage_order": ["active", "resolved"],
			"terminal_stages": ["resolved"],
			"allow_multiple_instances": false,
			"source_fact_rules": [
				{
					"fact_type": "test_singleton_trait_granted",
					"stage_id": "active",
					"severity": 1,
				},
			],
			"modifiers": [],
		}
	)
	var singleton_store = CharacterFeatureStoreModel.new()
	singleton_store.configure({
		"talent": registry.list_definitions("talent"),
		"trait": registry.list_definitions("trait"),
		"mark": registry.list_definitions("mark"),
		"skill": registry.list_definitions("skill"),
	}, entity_store, fact_store)
	for index: int in range(2):
		var singleton_fact := {
			"fact_id": "fact.test.singleton.%d" % index,
			"fact_type": "test_singleton_trait_granted",
			"source_id": "player",
			"tick": 40 + index,
		}
		fact_store.add_fact(singleton_fact)
		singleton_store.apply_facts([singleton_fact])
	var second_singleton_fact: Dictionary = fact_store.get_fact(
		"fact.test.singleton.1"
	)
	_check(
		singleton_registered
		and singleton_store.list_trait_instances("player").size() == 1
		and singleton_store.get_contract_report().get("ok", false)
		and not singleton_store.load_trait_instance({
			"trait_instance_id": "trait_instance.test.singleton.second",
			"trait_def_id": "trait.test_singleton",
			"owner_entity_id": "player",
			"stage_id": "active",
			"severity": 1,
			"status": "active",
			"source_fact_ids": [second_singleton_fact.get("fact_id", "")],
			"created_tick": 41,
			"updated_tick": 41,
		}),
		"15. 单实例 Trait 对事实幂等且拒绝显式载入第二个活动实例"
	)

	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH,
		[BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	)
	if not bool(start.get("success", false)):
		_check(false, "16. Session 启动失败：%s" % JSON.stringify(start))
		_finish()
		return
	var snapshot: Variant = session.get_snapshot()
	var progress: Dictionary = snapshot.get_character_progress()
	_check(
		int(start.get("definition_count", 0)) == 105
		and session.stores.has("character_feature_store")
		and int((progress.get("attributes", {}) as Dictionary).get(
			"perception",
			0
		)) == 10
		and not session.stores["state_store"].list_states("player").has("injury")
		and not session.stores["state_store"].list_states("player").has(
			"mist_salt_echo"
		),
		"16. Session 接入特征 Store，CharacterProgress 从 StateStore 聚合属性"
	)
	_check(
		str(snapshot.get_player_value("injury", "")) == "none"
		and str(snapshot.get_player_value("mist_salt_echo", "")) == "none"
		and snapshot.get_trait_instances("player").is_empty()
		and snapshot.get_mark_instances("player").is_empty(),
		"17. 旧字段仅由空特征集合投影为兼容 none，不形成状态真值"
	)
	_check(
		not session.stores["state_store"].set_state(
			"player",
			"injury",
			"twisted_ankle"
		)
		and session.stores["state_store"].last_error.ends_with(
			"external_projection_owned_key"
		),
		"18. StateStore 拒绝直接写入由外部 Store 派生的旧投影字段"
	)

	session.travel("old_chen_shop_to_abandoned_granary")
	var failed: Dictionary = session.execute_challenge_option(
		"enter_abandoned_granary",
		{"source": "test_injection", "roll_override": 3}
	)
	var failure_snapshot: Variant = session.get_snapshot()
	_check(
		bool(failed.get("success", false))
		and str(failure_snapshot.get_player_value("injury", "")) == "twisted_ankle"
		and not session.stores["state_store"].list_states("player").has("injury")
		and failure_snapshot.get_trait_instances("player").size() == 1
		and (failure_snapshot.get_character_progress().get(
			"trait_instance_ids",
			[]
		) as Array).size() == 1,
		"19. 真实挑战失败由伤势事实创建 Trait，旧 injury 只作 Snapshot 投影"
	)
	_check(
		str((failure_snapshot.get_trait_instances("player")[0] as Dictionary).get(
			"source_fact_ids",
			[]
		)[0]) == "actor_injured_during_challenge:1",
		"20. 真实伤势实例保留产生它的世界事实 ID"
	)

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("[V5 CHARACTER FEATURE CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 CHARACTER FEATURE CONTRACT FAIL] " + failure)
	print(
		"[V5 CHARACTER FEATURE CONTRACT RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 CHARACTER FEATURE CONTRACT PASS] " + message)
	else:
		failures.append(message)
