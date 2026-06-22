extends SceneTree

const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const EntityStoreModel = preload("res://scripts/sim/entity/entity_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const ActionCandidateModel = preload("res://scripts/sim/action/action_candidate.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var context = SimContextModel.new({
		"world_id": "fixture_world",
		"actor_id": "player",
		"location_id": "lake_town",
		"visible_entity_ids": ["player", "chen_mi"],
		"region_state": {"food_pressure": "high"},
		"known_fact_ids": ["fact_old_chen_shop_closed"],
	})
	_check(
		context.world_id == "fixture_world"
		and context.to_dict().get("location_id", "") == "lake_town",
		"1. SimContext 可实例化并导出上下文"
	)

	var registry = SimRegistryModel.new()
	registry.register_definition("entity", "chen_mi", {"type": "person", "tags": ["hungry_child"]})
	_check(
		registry.get_definition("entity", "chen_mi").get("type", "") == "person",
		"2. SimRegistry 可登记和读取定义"
	)

	var entity_store = EntityStoreModel.new()
	entity_store.add_entity("player", {"type": "person"})
	entity_store.add_entity("chen_mi", {"type": "person"})
	_check(
		entity_store.has_entity("player")
		and entity_store.get_entity("chen_mi").get("type", "") == "person",
		"3. EntityStore 可保存最小实体"
	)

	var state_store = StateStoreModel.new()
	state_store.set_state("chen_mi", "hunger", "high")
	_check(
		state_store.get_state("chen_mi", "hunger") == "high"
		and state_store.list_states("chen_mi").has("hunger"),
		"4. StateStore 可写入和读取状态"
	)

	var candidate = ActionCandidateModel.new({
		"action_id": "inspect_trace",
		"label": "检查痕迹",
		"action_type": "inspect",
		"source_rule_id": "skeleton_rule",
		"target_id": "trace_powder",
		"priority": 10,
	})
	_check(
		candidate.to_dict().get("action_id", "") == "inspect_trace"
		and candidate.priority == 10,
		"5. ActionCandidate 可创建行动候选对象"
	)

	var affordance_system = ActionAffordanceModel.new()
	_check(
		affordance_system.build_candidates(context).is_empty(),
		"6. ActionAffordanceSystem 当前为空骨架"
	)

	var transaction_result = TransactionResultModel.new()
	_check(
		transaction_result.is_empty()
		and transaction_result.to_dict().has("facts"),
		"7. TransactionResult 可表示空事务结果"
	)

	var fact_store = FactStoreModel.new()
	fact_store.add_fact({"fact_id": "fact_test", "type": "skeleton"})
	_check(
		fact_store.list_facts().size() == 1,
		"8. FactStore 可保存结构化事实"
	)

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SIM ARCHITECTURE SKELETON RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 SIM ARCHITECTURE SKELETON FAIL] " + failure)
		print("[V5 SIM ARCHITECTURE SKELETON RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 SIM ARCHITECTURE SKELETON PASS] " + message)
	else:
		failures.append(message)
