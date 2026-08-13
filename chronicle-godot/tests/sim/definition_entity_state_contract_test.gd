extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const EntityStoreModel = preload("res://scripts/sim/entity/entity_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const STATE_DEFS_PATH := "res://data/sim/raw/state_defs/basic_state_defs.json"
const OBJECT_DEFS_PATH := "res://data/sim/raw/object_defs/basic_object_defs.json"
const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = SimRegistryModel.new()
	var definition_report: Dictionary = registry.load_raw_definition_files([
		STATE_DEFS_PATH,
		OBJECT_DEFS_PATH,
	])
	_check(
		bool(definition_report.get("ok", false))
		and int(definition_report.get("registered_count", 0)) >= 30
		and registry.has_definition("state", "state.character.perception")
		and registry.has_definition("object", "object.person"),
		"1. Raw Definition 文件以稳定 ID 和版本通过严格注册"
	)
	_check(
		str(registry.get_definition(
			"state",
			"state.character.perception"
		).get("value_type", "")) == "int"
		and str(registry.get_definition(
			"object",
			"object.person"
		).get("owner_kind", "")) == "character",
		"2. Registry 可按 kind 与稳定 ID 返回不可变定义"
	)
	_check(
		not registry.register_definition(
			"state",
			"state.character.perception",
			registry.get_definition("state", "state.character.perception")
		)
		and not registry.register_definition(
			"state",
			"state.character.perception_alias",
			{
				"definition_version": 1,
				"key": "perception",
				"value_type": "int",
				"owner_kinds": ["character"],
				"allowed_operations": ["set", "add"],
				"persistence": "save",
				"ui_visibility": "summary",
			}
		)
		and not registry.register_definition(
			"object",
			"object.person_alias",
			{
				"definition_version": 1,
				"type": "person",
				"owner_kind": "character",
				"default_tags": [],
			}
		)
		and not registry.register_definition(
			"state",
			"state.character.mismatched_id",
			{
				"state_def_id": "state.character.other_id",
				"definition_version": 1,
				"key": "mismatched_id",
				"value_type": "int",
				"owner_kinds": ["character"],
				"allowed_operations": ["set"],
				"persistence": "save",
				"ui_visibility": "hidden",
			}
		)
		and str(registry.get_definition(
			"state",
			"state.character.perception"
		).get("key", "")) == "perception",
		"3. Registry 拒绝 ID 不一致、重复 key/type 且不覆盖定义"
	)

	var invalid_registry = SimRegistryModel.new()
	_check(
		not invalid_registry.register_definition("state", "state.invalid", {
			"definition_version": 0,
			"key": "invalid",
			"value_type": "number",
			"owner_kinds": [],
			"allowed_operations": [],
		})
		and not bool(invalid_registry.get_definition_report().get("ok", true)),
		"4. Registry 拒绝缺少版本、类型和所有者合同的 StateDef"
	)

	var strict_context = SimContextModel.new({
		"fixture_id": "strict_contract_fixture",
		"actor_id": "player",
		"location_id": "test_room",
		"locations": {
			"test_room": {"id": "test_room", "tags": ["interior"]},
		},
		"entities": [
			{
				"id": "observer",
				"type": "person",
				"location_id": "test_room",
				"states": {"visible": true, "perception": 7},
			},
		],
		"player": {
			"id": "player",
			"type": "person",
			"role": "traveler",
			"perception": 10,
			"health": 100,
		},
	})
	var entity_store = EntityStoreModel.new()
	entity_store.configure_definitions(
		registry.list_definitions("object"),
		true
	)
	var entity_report: Dictionary = entity_store.load_from_context(strict_context)
	_check(
		bool(entity_report.get("ok", false))
		and entity_store.has_entity("player")
		and entity_store.has_entity("observer")
		and not entity_store.get_entity("player").has("perception")
		and str(entity_store.get_entity("player").get("role", ""))
			== "traveler",
		"5. EntityStore 只保存身份和静态元数据，不吞入可变状态"
	)
	_check(
		not entity_store.add_entity("invalid_entity", {"type": "unknown_type"})
		and not entity_store.has_entity("invalid_entity"),
		"6. 严格 EntityStore 拒绝未注册实体类型"
	)

	var state_store = StateStoreModel.new()
	state_store.configure_definitions(
		registry.list_definitions("state"),
		entity_store,
		true
	)
	var state_report: Dictionary = state_store.load_from_context(strict_context)
	_check(
		bool(state_report.get("ok", false))
		and int(state_store.get_state("player", "perception", 0)) == 10
		and not state_store.list_states("player").has("id")
		and not state_store.list_states("player").has("role"),
		"7. StateStore 只保存可变状态，玩家身份字段不会形成第二真值"
	)
	_check(
		state_store.apply_state_change({
			"entity_id": "player",
			"key": "perception",
			"delta": 1,
		})
		and int(state_store.get_state("player", "perception", 0)) == 11,
		"8. 已注册 StateDef 允许合法类型、范围与 add 操作"
	)
	var perception_before_invalid := int(
		state_store.get_state("player", "perception", 0)
	)
	_check(
		not state_store.apply_state_change({
			"entity_id": "player",
			"key": "perception",
			"to": "sharp",
		})
		and int(state_store.get_state("player", "perception", 0))
			== perception_before_invalid
		and "value_type_mismatch" in state_store.last_error,
		"9. 严格 StateStore 拒绝类型错误且不发生部分写入"
	)
	_check(
		not state_store.apply_state_change({
			"entity_id": "player",
			"key": "perception",
			"degrade": 1,
		})
		and "operation_not_allowed" in state_store.last_error,
		"10. 严格 StateStore 拒绝 StateDef 未允许的操作"
	)
	_check(
		not state_store.set_state("player", "unregistered_value", 1)
		and not state_store.list_states("player").has("unregistered_value"),
		"11. 严格 StateStore 拒绝未注册状态字段"
	)

	var session = SimSessionModel.new()
	var start_result: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH,
		[BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	)
	if not bool(start_result.get("success", false)):
		_check(
			false,
			"12. SimSession 启动失败：%s" % JSON.stringify(start_result)
		)
		_finish()
		return
	var initial_snapshot: Variant = session.get_snapshot()
	_check(
		bool(start_result.get("success", false))
		and session.stores.has("entity_store")
		and int(start_result.get("definition_count", 0)) >= 30
		and str(initial_snapshot.get_entity("chen_mi").get(
			"display_name",
			""
		)) == "陈米",
		"12. SimSession 启动时加载 Definition 并由 EntityStore 构建 Snapshot"
	)
	_check(
		session.context.player.is_empty()
		and session.context.entities.is_empty()
		and session.context.region_state.is_empty()
		and session.context.institution.is_empty()
		and session.context.known_facts.is_empty(),
		"13. 初始化后 Context 释放玩家、实体、地区、制度和事实副本"
	)

	session.context.player = {"id": "player", "food_count": 99}
	session.context.entities = [
		{
			"id": "chen_mi",
			"type": "person",
			"location_id": "old_chen_shop",
			"display_name": "伪造副本",
			"states": {"hunger": "low", "visible": false},
		},
	]
	var context_tampered_snapshot: Variant = session.get_snapshot()
	_check(
		int(context_tampered_snapshot.get_player_value("food_count", 0)) == 3
		and str(context_tampered_snapshot.get_entity("chen_mi").get(
			"display_name",
			""
		)) == "陈米"
		and str(context_tampered_snapshot.get_entity_state(
			"chen_mi",
			"hunger",
			""
		)) == "high",
		"14. 篡改 Context 运行副本不会改变 Store 真值或 Snapshot"
	)

	session.stores["fact_store"].add_fact({
		"fact_id": "fact.test.consume_all_rations",
		"fact_type": "test_consumed_rations",
		"actor_id": "player",
		"tick": 1,
	})
	session.stores["item_store"].apply_item_change({
		"operation": "consume",
		"item_instance_id": "item_instance.lake_town.player_travel_rations",
		"quantity": 3,
		"source_fact_ids": ["fact.test.consume_all_rations"],
	})
	var changed_snapshot: Variant = session.get_snapshot()
	var changed_options: Array = session.get_action_options()
	var food_action := _find_action(
		changed_options,
		"give_food_to_hungry_person:chen_mi"
	)
	_check(
		int(changed_snapshot.get_player_value("food_count", -1)) == 0
		and not food_action.is_empty()
		and not bool(food_action.get("can_execute", true))
		and int(((food_action.get("player_requirements", []) as Array)[0]
			as Dictionary).get("current", -1)) == 0,
		"15. ItemStore 口粮变化会立即重建 Snapshot 与候选阻塞解释"
	)
	_check(
		str(changed_snapshot.get_player_value("role", "")) == "traveler"
		and not session.stores["state_store"].list_states("player").has("role")
		and str(session.stores["entity_store"].get_entity("player").get(
			"role",
			""
		)) == "traveler",
		"16. Snapshot 合并静态身份与可变状态而不产生重复所有权"
	)
	_check_runtime_registered_state_rejection(session)

	_finish()


func _find_action(options: Array, action_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("action_id", "")) == action_id:
			return option.duplicate(true)
	return {}


func _check_runtime_registered_state_rejection(session: Variant) -> void:
	var state_store: Variant = session.stores["state_store"]
	_check(
		not state_store.set_state("player", "food_count", 0)
		and not state_store.list_states("player").has("food_count")
		and "external_projection_owned_key" in state_store.last_error,
		"17. StateStore 拒绝写入由 ItemStore 聚合的 food_count 投影"
	)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 DEFINITION ENTITY STATE CONTRACT RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 DEFINITION ENTITY STATE CONTRACT FAIL] " + failure)
		print(
			"[V5 DEFINITION ENTITY STATE CONTRACT RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 DEFINITION ENTITY STATE CONTRACT PASS] " + message)
	else:
		failures.append(message)
