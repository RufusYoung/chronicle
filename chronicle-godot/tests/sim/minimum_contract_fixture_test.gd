extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const ItemConsumptionPlannerModel = preload(
	"res://scripts/sim/item/item_consumption_planner.gd"
)

const FIXTURE_PATH := (
	"res://data/sim/fixtures/core_system_contract_fixture.json"
)
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
		FIXTURE_PATH,
		RULE_PATHS
	)
	_check(
		bool(start.get("success", false))
		and str(start.get("fixture_id", "")) == "core_system_contract"
		and int(start.get("definition_count", 0)) == 64,
		"1. 最小合同 fixture 通过全部 Definition 与 Store 启动校验"
	)
	if not bool(start.get("success", false)):
		_finish()
		return

	var snapshot: Variant = session.get_snapshot()
	var player_cloak: Dictionary = snapshot.get_item(
		"item_instance.contract.player_winter_cloak"
	)
	var veteran_cloak: Dictionary = snapshot.get_item(
		"item_instance.contract.veteran_winter_cloak"
	)
	_check(
		str(player_cloak.get("item_def_id", "")) == "item.waxed_winter_cloak"
		and str(veteran_cloak.get("item_def_id", "")) == "item.waxed_winter_cloak"
		and int((player_cloak.get("condition", {}) as Dictionary).get(
			"durability",
			0
		)) == 76
		and int((veteran_cloak.get("condition", {}) as Dictionary).get(
			"durability",
			0
		)) == 43
		and player_cloak.get("history", []) != veteran_cloak.get("history", []),
		"2. 两名角色拥有同定义但耐久、来源和历史不同的冬衣实例"
	)
	_check(
		str(snapshot.get_equipped_item("player", "body_outer").get(
			"item_instance_id",
			""
		)) == "item_instance.contract.player_winter_cloak"
		and str(snapshot.get_equipped_item(
			"outpost_veteran",
			"body_outer"
		).get("item_instance_id", ""))
			== "item_instance.contract.veteran_winter_cloak",
		"3. 两件冬衣分别由持有人装备且没有复制物品状态"
	)
	_check(
		int(snapshot.get_player_value("food_count", -1)) == 6
		and not session.stores["state_store"].list_states("player").has(
			"food_count"
		)
		and int(snapshot.get_item(
			"item_instance.contract.player_rations"
		).get("quantity", 0)) == 6,
		"4. food_count 只由玩家实际口粮堆叠聚合"
	)
	var merchant_stock: Dictionary = snapshot.get_market_stock_view(
		"merchant_sela"
	)
	var offers: Array = merchant_stock.get("offers", [])
	_check(
		offers.size() == 1
		and str((offers[0] as Dictionary).get("item_instance_id", ""))
			== "item_instance.contract.merchant_rations"
		and int((offers[0] as Dictionary).get("available_quantity", 0)) == 12
		and str((offers[0] as Dictionary).get("quote_status", "")) == "unquoted",
		"5. 商店候选来自商人真实商品堆叠且不伪造报价"
	)
	var feature_store: Variant = session.stores["character_feature_store"]
	_check(
		feature_store.list_trait_instances("player").size() == 1
		and feature_store.list_mark_instances("player").size() == 1
		and feature_store.list_mark_instances("outpost_veteran").size() == 1
		and feature_store.list_skill_progress("player").size() == 1,
		"6. 可恢复伤势、两个雾盐印记样本与侦察技艺进入独立 Store"
	)

	var split_result = TransactionResultModel.new()
	split_result.add_fact({
		"fact_id": "fact.contract.player_rations_split",
		"fact_type": "item_stack_split",
		"actor_id": "player",
		"target_id": "item_instance.contract.player_rations",
		"tick": 8,
	})
	split_result.add_item_change({
		"operation": "split_stack",
		"item_instance_id": "item_instance.contract.player_rations",
		"new_item_instance_id": "item_instance.contract.player_rations_split",
		"quantity": 2,
		"new_holder": {"kind": "entity", "id": "player"},
		"source_fact_ids": ["fact.contract.player_rations_split"],
	})
	split_result.mark_resolved("minimum_contract_fixture_test")
	_check(
		session.writer.apply_result(split_result, session.stores)
		and int(session.stores["item_store"].get_item(
			"item_instance.contract.player_rations"
		).get("quantity", 0)) == 4
		and int(session.stores["item_store"].get_item(
			"item_instance.contract.player_rations_split"
		).get("quantity", 0)) == 2
		and int(session.get_snapshot().get_player_value("food_count", -1)) == 6,
		"7. 口粮堆叠可拆分且总量投影保持一致"
	)

	var consume_result = TransactionResultModel.new()
	consume_result.add_fact({
		"fact_id": "fact.contract.player_rations_consumed",
		"fact_type": "actor_consumed_rations",
		"actor_id": "player",
		"target_id": "player",
		"tick": 9,
	})
	var plan: Dictionary = ItemConsumptionPlannerModel.new(
	).plan_owned_definition_consumption(
		session.get_snapshot(),
		"player",
		"item.travel_ration",
		5,
		["fact.contract.player_rations_consumed"]
	)
	for change: Dictionary in plan.get("changes", []):
		consume_result.add_item_change(change)
	consume_result.mark_resolved("minimum_contract_fixture_test")
	_check(
		bool(plan.get("ok", false))
		and (plan.get("changes", []) as Array).size() == 2
		and session.writer.apply_result(consume_result, session.stores)
		and int(session.get_snapshot().get_player_value("food_count", -1)) == 1,
		"8. 多个真实口粮堆叠按稳定实例顺序共同承担一次消费"
	)
	_check(
		str((session.stores["item_store"].get_item(
			"item_instance.contract.player_rations"
		).get("holder", {}) as Dictionary).get("kind", "")) == "destroyed"
		and int(session.stores["item_store"].get_item(
			"item_instance.contract.player_rations_split"
		).get("quantity", 0)) == 1,
		"9. 耗尽的堆叠进入 destroyed holder，剩余实例仍可追溯"
	)

	var envelope: Dictionary = session.build_save_envelope_seed()
	var encoded := JSON.stringify(envelope)
	var decoded: Variant = JSON.parse_string(encoded)
	_check(
		decoded is Dictionary
		and _json_equivalent(decoded, envelope)
		and JSON.stringify(session.build_save_envelope_seed()) == encoded
		and int(envelope.get("schema_version", 0)) == 1
		and str(envelope.get("payload_kind", "")) == "save_envelope_seed"
		and str(envelope.get("location_id", "")) == "contract_market",
		"10. SaveEnvelope seed 可无损通过 JSON 编码与解码"
	)
	var manifest: Array = (envelope.get(
		"definition_manifest",
		{}
	) as Dictionary).get("required_definition_ids", [])
	_check(
		manifest.size() == 64
		and manifest == _sorted_copy(manifest)
		and "item:item.travel_ration" in manifest
		and "item:item.field_repair_hammer" in manifest
		and "talent:talent.steady_hands" in manifest
		and "trait:trait.winter_work_callus" in manifest
		and "trait:trait.fire_circle_belonging" in manifest
		and "equipment_slot:slot.body_outer" in manifest,
		"11. Definition manifest 完整且顺序稳定"
	)
	_check(
		_save_references_are_valid(envelope),
		"12. JSON 往返后的装备、物品历史与角色特征引用仍全部存在"
	)
	_check(
		(envelope.get("stores", {}) as Dictionary).has("items")
		and not (envelope.get("stores", {}) as Dictionary).has("inventory")
		and not (envelope.get("stores", {}) as Dictionary).has("market_stock")
		and _saved_items_are_canonical(envelope),
		"13. 保存种子只含规范 Store 真值，不保存兼容别名或派生投影"
	)

	_finish()


func _save_references_are_valid(envelope: Dictionary) -> bool:
	var stores: Dictionary = envelope.get("stores", {})
	var fact_ids: Dictionary = {}
	for fact: Dictionary in stores.get("facts", []):
		fact_ids[str(fact.get("fact_id", ""))] = true
	var items: Dictionary = {}
	for item: Dictionary in stores.get("items", []):
		var item_id := str(item.get("item_instance_id", ""))
		items[item_id] = item
		for history: Dictionary in item.get("history", []):
			if not fact_ids.has(str(history.get("fact_id", ""))):
				return false
	for entity_id: String in (stores.get("equipment_loadouts", {}) as Dictionary).keys():
		var loadout: Dictionary = stores["equipment_loadouts"][entity_id]
		for item_value: Variant in (loadout.get("slots", {}) as Dictionary).values():
			if item_value == null:
				continue
			var item_id := str(item_value)
			if not items.has(item_id):
				return false
			var holder: Dictionary = (items[item_id] as Dictionary).get("holder", {})
			if str(holder.get("kind", "")) != "entity" or str(
				holder.get("id", "")
			) != entity_id:
				return false
	for key: String in ["mark_instances", "skill_progress"]:
		for instance: Dictionary in stores.get(key, []):
			for fact_id: Variant in instance.get("source_fact_ids", []):
				if not fact_ids.has(str(fact_id)):
					return false
	return true


func _saved_items_are_canonical(envelope: Dictionary) -> bool:
	var stores: Dictionary = envelope.get("stores", {})
	for item: Dictionary in stores.get("items", []):
		for derived_key: String in [
			"id",
			"item_id",
			"owner_id",
			"item_type",
			"equip_slots",
			"capabilities",
			"base_mass",
			"base_value",
			"modifiers",
			"tags",
		]:
			if item.has(derived_key):
				return false
	return true


func _sorted_copy(values: Array) -> Array:
	var copy := values.duplicate(true)
	copy.sort()
	return copy


func _json_equivalent(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		if (left as Dictionary).size() != (right as Dictionary).size():
			return false
		for key: Variant in (left as Dictionary).keys():
			if not (right as Dictionary).has(key) or not _json_equivalent(
				(left as Dictionary)[key],
				(right as Dictionary)[key]
			):
				return false
		return true
	if left is Array and right is Array:
		if (left as Array).size() != (right as Array).size():
			return false
		for index: int in range((left as Array).size()):
			if not _json_equivalent(
				(left as Array)[index],
				(right as Array)[index]
			):
				return false
		return true
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	return left == right


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 MINIMUM CONTRACT FIXTURE PASS] " + message)
	else:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 MINIMUM CONTRACT FIXTURE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 MINIMUM CONTRACT FIXTURE FAIL] " + failure)
	print(
		"[V5 MINIMUM CONTRACT FIXTURE RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)
