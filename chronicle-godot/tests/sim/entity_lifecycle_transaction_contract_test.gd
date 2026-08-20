extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const ViewModelModel = preload(
	"res://scripts/rebuild/v5_live_location_view_model.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SAVE_PATH := "user://tests/entity_lifecycle_transaction.save.json"
const ORGANIZATION_ID := "runtime_organization.reed_bay.relief_council"
const FAILED_ENTITY_ID := "runtime_organization.reed_bay.failed_preview"
const SETTLEMENT_ID := "generated_settlement.reed_bay"
const MEMBER_ID := "generated_resident.reed_bay.001"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": 81001}
	)
	_check(
		bool(start.get("success", false)),
		"1. G4-C1 实体生命周期合同通过正式 SimSession 启动"
	)
	if not bool(start.get("success", false)):
		_finish()
		return

	var create_result: Variant = _create_result()
	var created: bool = session.writer.apply_result(create_result, session.stores)
	var created_entity: Dictionary = session.stores[
		"entity_store"
	].get_entity(ORGANIZATION_ID)
	_check(
		created
		and str(created_entity.get("type", "")) == "institution"
		and str(session.stores["state_store"].get_state(
			ORGANIZATION_ID, "location_id", ""
		)) == "generated_location.reed_bay.commons"
		and int(session.stores["relationship_store"].get_relation(
			ORGANIZATION_ID, MEMBER_ID, "familiarity", 0
		)) == 12,
		"2. 同一事务创建实体、初始状态和真实成员关系"
	)
	_check(
		str(session.stores["fact_store"].get_fact(
			"fact.runtime_organization_created.reed_bay.relief_council"
		).get("target_id", "")) == ORGANIZATION_ID
		and int(create_result.to_dict().get("entity_changes", []).size()) == 1,
		"3. 创建操作由同事务事实追溯，并进入序列化事务结果"
	)

	var view_model = ViewModelModel.new(session)
	var before_update_view := JSON.stringify(view_model.build_view_data())
	_check(
		"苇岸临时粮议会" in before_update_view,
		"4. 新建组织无需重启会话即可进入正式地点投影"
	)

	var update_result: Variant = _update_goal_result()
	var updated: bool = session.writer.apply_result(update_result, session.stores)
	var updated_entity: Dictionary = session.stores[
		"entity_store"
	].get_entity(ORGANIZATION_ID)
	_check(
		updated
		and str(updated_entity.get("goal", ""))
		== "优先照料断粮家庭，并公开记录每次调拨。"
		and "优先照料断粮家庭" in JSON.stringify(
			view_model.build_view_data()
		),
		"5. 目标变更通过实体事务提交并立即改变正式界面投影"
	)

	var forbidden_result: Variant = _forbidden_update_result()
	var forbidden_fact_id := "fact.runtime_organization_forbidden_update"
	_check(
		not session.writer.apply_result(forbidden_result, session.stores)
		and str(session.stores["entity_store"].get_entity(
			ORGANIZATION_ID
		).get("type", "")) == "institution"
		and session.stores["fact_store"].get_fact(forbidden_fact_id).is_empty(),
		"6. 修改不可变 type 会在预演中拒绝，事实与实体均不受污染"
	)

	var missing_source_result: Variant = _missing_source_create_result()
	_check(
		not session.writer.apply_result(missing_source_result, session.stores)
		and not session.stores["entity_store"].has_entity(
			"runtime_organization.reed_bay.missing_source"
		),
		"7. 未知来源事实不能创建运行期实体"
	)

	var rollback_result: Variant = _rollback_result(session)
	var rollback_fact_id := "fact.runtime_organization_failed_preview"
	_check(
		not session.writer.apply_result(rollback_result, session.stores)
		and not session.stores["entity_store"].has_entity(FAILED_ENTITY_ID)
		and session.stores["fact_store"].get_fact(rollback_fact_id).is_empty(),
		"8. 后续资源透支会让已预演的实体与事实整体回滚"
	)

	var duplicate_result: Variant = _duplicate_create_result()
	_check(
		not session.writer.apply_result(duplicate_result, session.stores)
		and session.stores["fact_store"].get_fact(
			"fact.runtime_organization_duplicate"
		).is_empty(),
		"9. 重复实体 ID 在预演中拒绝，不提交配套事实"
	)

	var protected_result: Variant = _protected_retire_result()
	var protected_tag_result: Variant = _protected_tag_update_result()
	_check(
		not session.writer.apply_result(protected_result, session.stores)
		and not session.writer.apply_result(protected_tag_result, session.stores)
		and session.stores["entity_store"].is_entity_active("player")
		and session.stores["fact_store"].get_fact(
			"fact.runtime_player_retire"
		).is_empty()
		and session.stores["fact_store"].get_fact(
			"fact.runtime_player_tags_removed"
		).is_empty(),
		"10. 玩家身份标签不可移除，实体也不能被通用退役操作撤销"
	)

	var retire_result: Variant = _retire_result()
	var retired: bool = session.writer.apply_result(retire_result, session.stores)
	var retired_entity: Dictionary = session.stores[
		"entity_store"
	].get_entity(ORGANIZATION_ID)
	_check(
		retired
		and not session.stores["entity_store"].is_entity_active(ORGANIZATION_ID)
		and str(retired_entity.get("retired_fact_id", ""))
		== "fact.runtime_organization_retired.reed_bay.relief_council"
		and int(session.stores["relationship_store"].get_relation(
			ORGANIZATION_ID, MEMBER_ID, "familiarity", 0
		)) == 12
		and "苇岸临时粮议会" not in JSON.stringify(
			view_model.build_view_data()
		),
		"11. 软退役保留实体和历史关系，但运行界面不再把它当作当前组织"
	)

	var save_before: Dictionary = session.get_save_store_data()
	var save_report: Dictionary = session.save_to_path(SAVE_PATH, {
		"save_id": "save.test.entity_lifecycle_transaction",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-20T10:00:00Z",
		"saved_at_utc": "2026-08-20T10:30:00Z",
	})
	var restored = SimSessionModel.new()
	var restore_report: Dictionary = restored.load_from_path(SAVE_PATH)
	_check(
		bool(save_report.get("ok", false))
		and bool(restore_report.get("success", false))
		and _equivalent(save_before, restored.get_save_store_data())
		and not restored.stores["entity_store"].is_entity_active(ORGANIZATION_ID)
		and bool(restored.validate_persistent_references().get("ok", false)),
		"12. 磁盘存档精确保留创建、目标历史、软退役和跨 Store 引用"
	)

	print("[V5 ENTITY LIFECYCLE SAMPLE] %s" % JSON.stringify({
		"created": created_entity,
		"updated_goal": updated_entity.get("goal", ""),
		"retired": retired_entity,
		"writer_report": session.writer.last_report,
	}))
	_finish()


func _create_result() -> Variant:
	var fact_id := "fact.runtime_organization_created.reed_bay.relief_council"
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "create",
		"entity": {
			"id": ORGANIZATION_ID,
			"type": "institution",
			"display_name": "苇岸临时粮议会",
			"description": "由持续粮压促成的临时地方组织。",
			"tags": [
				"institution", "organization", "generated_organization",
				"runtime_organization",
			],
			"settlement_id": SETTLEMENT_ID,
			"goal": "协调本地口粮。",
			"positions": [],
			"resource_stock_ids": [],
			"runtime_response": {},
		},
		"source_fact_ids": [fact_id],
	})
	result.add_state_change({
		"entity_id": ORGANIZATION_ID,
		"key": "location_id",
		"to": "generated_location.reed_bay.commons",
	})
	result.add_relationship_change({
		"source_id": ORGANIZATION_ID,
		"target_id": MEMBER_ID,
		"axis": "familiarity",
		"delta": 12,
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "runtime_entity_created",
		"actor_id": SETTLEMENT_ID,
		"target_id": ORGANIZATION_ID,
		"entity_id": ORGANIZATION_ID,
		"summary": "持续粮压促成了一个临时地方组织。",
	})
	result.mark_resolved("entity_lifecycle_create")
	return result


func _update_goal_result() -> Variant:
	var fact_id := "fact.runtime_organization_goal_changed.reed_bay.relief_council"
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "update",
		"entity_id": ORGANIZATION_ID,
		"fields": {
			"goal": "优先照料断粮家庭，并公开记录每次调拨。",
		},
		"source_fact_ids": [fact_id],
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "runtime_entity_goal_changed",
		"actor_id": ORGANIZATION_ID,
		"target_id": ORGANIZATION_ID,
		"entity_id": ORGANIZATION_ID,
		"summary": "临时粮议会把目标改为优先照料断粮家庭。",
	})
	result.mark_resolved("entity_lifecycle_update")
	return result


func _forbidden_update_result() -> Variant:
	var fact_id := "fact.runtime_organization_forbidden_update"
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "update",
		"entity_id": ORGANIZATION_ID,
		"fields": {"type": "person"},
		"source_fact_ids": [fact_id],
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "runtime_entity_goal_changed",
		"actor_id": ORGANIZATION_ID,
		"target_id": ORGANIZATION_ID,
	})
	result.mark_resolved("entity_lifecycle_forbidden_update")
	return result


func _missing_source_create_result() -> Variant:
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "create",
		"entity": {
			"id": "runtime_organization.reed_bay.missing_source",
			"type": "institution",
			"display_name": "无来源组织",
		},
		"source_fact_ids": ["fact.does_not_exist"],
	})
	result.mark_resolved("entity_lifecycle_missing_source")
	return result


func _rollback_result(session: Variant) -> Variant:
	var fact_id := "fact.runtime_organization_failed_preview"
	var stock: Dictionary = session.stores[
		"resource_stock_store"
	].list_stocks()[0]
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "create",
		"entity": {
			"id": FAILED_ENTITY_ID,
			"type": "institution",
			"display_name": "不应提交的组织",
		},
		"source_fact_ids": [fact_id],
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "runtime_entity_created",
		"actor_id": SETTLEMENT_ID,
		"target_id": FAILED_ENTITY_ID,
	})
	result.add_resource_change({
		"operation": "consume",
		"stock_id": str(stock.get("stock_id", "")),
		"amount": float(stock.get("current", 0.0)) + 999.0,
		"source_fact_ids": [fact_id],
	})
	result.mark_resolved("entity_lifecycle_rollback")
	return result


func _duplicate_create_result() -> Variant:
	var fact_id := "fact.runtime_organization_duplicate"
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "create",
		"entity": {
			"id": ORGANIZATION_ID,
			"type": "institution",
			"display_name": "重复组织",
		},
		"source_fact_ids": [fact_id],
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "runtime_entity_created",
		"actor_id": SETTLEMENT_ID,
		"target_id": ORGANIZATION_ID,
	})
	result.mark_resolved("entity_lifecycle_duplicate")
	return result


func _protected_retire_result() -> Variant:
	var fact_id := "fact.runtime_player_retire"
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "retire",
		"entity_id": "player",
		"retired_fact_id": fact_id,
		"day": 1,
		"reason": "test_injection",
		"source_fact_ids": [fact_id],
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "runtime_entity_retired",
		"actor_id": "player",
		"target_id": "player",
	})
	result.mark_resolved("entity_lifecycle_protected_retire")
	return result


func _protected_tag_update_result() -> Variant:
	var fact_id := "fact.runtime_player_tags_removed"
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "update",
		"entity_id": "player",
		"fields": {"tags": ["actor"]},
		"source_fact_ids": [fact_id],
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "runtime_entity_updated",
		"actor_id": "player",
		"target_id": "player",
	})
	result.mark_resolved("entity_lifecycle_protected_tags")
	return result


func _retire_result() -> Variant:
	var fact_id := "fact.runtime_organization_retired.reed_bay.relief_council"
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "retire",
		"entity_id": ORGANIZATION_ID,
		"retired_fact_id": fact_id,
		"day": 4,
		"reason": "粮压缓解后临时职责结束",
		"source_fact_ids": [fact_id],
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "runtime_entity_retired",
		"actor_id": ORGANIZATION_ID,
		"target_id": ORGANIZATION_ID,
		"entity_id": ORGANIZATION_ID,
		"summary": "粮压缓解后，苇岸临时粮议会结束职责并保留历史记录。",
	})
	result.mark_resolved("entity_lifecycle_retire")
	return result


func _equivalent(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		if (left as Dictionary).size() != (right as Dictionary).size():
			return false
		for key: Variant in (left as Dictionary).keys():
			if (
				not (right as Dictionary).has(key)
				or not _equivalent(
					(left as Dictionary).get(key),
					(right as Dictionary).get(key)
				)
			):
				return false
		return true
	if left is Array and right is Array:
		if (left as Array).size() != (right as Array).size():
			return false
		for index: int in range((left as Array).size()):
			if not _equivalent((left as Array)[index], (right as Array)[index]):
				return false
		return true
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	return left == right


func _finish() -> void:
	if failures.is_empty():
		print("[V5 ENTITY LIFECYCLE CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 ENTITY LIFECYCLE CONTRACT RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 ENTITY LIFECYCLE CONTRACT PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 ENTITY LIFECYCLE CONTRACT FAIL] %s" % label)
