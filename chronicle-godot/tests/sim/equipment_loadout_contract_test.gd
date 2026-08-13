extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const EntityStoreModel = preload("res://scripts/sim/entity/entity_store.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const ItemStoreModel = preload("res://scripts/sim/item/item_store.gd")
const EquipmentStoreModel = preload(
	"res://scripts/sim/equipment/equipment_loadout_store.gd"
)
const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const TransactionWorldWriterModel = preload(
	"res://scripts/sim/transaction/transaction_world_writer.gd"
)

const STATE_DEFS_PATH := "res://data/sim/raw/state_defs/basic_state_defs.json"
const OBJECT_DEFS_PATH := "res://data/sim/raw/object_defs/basic_object_defs.json"
const FEATURE_DEFS_PATH := (
	"res://data/sim/raw/character_feature_defs/basic_character_feature_defs.json"
)
const ITEM_DEFS_PATH := "res://data/sim/raw/item_defs/basic_item_defs.json"
const SLOT_DEFS_PATH := (
	"res://data/sim/raw/equipment_slot_defs/basic_equipment_slot_defs.json"
)
const OUTPOST_FIXTURE_PATH := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = SimRegistryModel.new()
	var definition_report: Dictionary = registry.load_raw_definition_files([
		STATE_DEFS_PATH,
		OBJECT_DEFS_PATH,
		FEATURE_DEFS_PATH,
		ITEM_DEFS_PATH,
		SLOT_DEFS_PATH,
	])
	_check(
		bool(definition_report.get("ok", false))
		and int(definition_report.get("total_definition_count", 0)) == 59
		and registry.has_definition("equipment_slot", "slot.body_outer")
		and registry.has_definition("equipment_slot", "slot.main_hand")
		and registry.has_definition("equipment_slot", "slot.utility"),
		"1. 三个 EquipmentSlotDef 以稳定 ID 进入严格 Registry"
	)
	var invalid_registry = SimRegistryModel.new()
	_check(
		not invalid_registry.register_definition(
			"equipment_slot",
			"slot.invalid",
			{
				"definition_version": 1,
				"display_name_key": "slot.invalid.name",
				"accepts_item_tags_any": [],
				"exclusive_group": "",
			}
		),
		"2. Registry 拒绝没有可接受标签和互斥组的装备位"
	)
	_check(
		not registry.register_definition("item", "item.invalid_slot", {
			"definition_version": 1,
			"display_name_key": "item.invalid_slot.name",
			"item_kind": "equipment",
			"tags": ["clothing"],
			"stackable": false,
			"max_stack": 1,
			"base_mass": 1,
			"equip_slots": ["unknown_slot"],
			"capabilities": ["equip"],
			"durability": {},
			"modifiers": [],
			"base_value": 1,
		}),
		"2B. Registry 在槽位可用时拒绝 ItemDef 的未知装备位"
	)

	var entity_store = EntityStoreModel.new()
	entity_store.configure_definitions(registry.list_definitions("object"), true)
	entity_store.add_entity("player", {"type": "person", "role": "traveler"})
	entity_store.add_entity("merchant", {"type": "person", "role": "merchant"})
	var fact_store = FactStoreModel.new()
	for fact: Dictionary in [
		_fact("fact.cloak.player.created", "item_created", "player", 1),
		_fact("fact.cloak.merchant.created", "item_created", "merchant", 2),
	]:
		fact_store.add_fact(fact)
	var item_store = ItemStoreModel.new()
	item_store.configure(
		registry.list_definitions("item"),
		entity_store,
		{"camp": {"id": "camp"}},
		fact_store
	)
	_check(
		item_store.create_item({
			"item_instance_id": "item.cloak.player",
			"item_def_id": "item.waxed_winter_cloak",
			"holder": {"kind": "entity", "id": "player"},
			"quantity": 1,
			"condition": {
				"durability": 83,
				"maximum_durability": 100,
				"quality": "serviceable",
			},
			"provenance": {"original_owner_entity_id": "seventh_outpost"},
		}, ["fact.cloak.player.created"])
		and item_store.create_item({
			"item_instance_id": "item.cloak.merchant",
			"item_def_id": "item.waxed_winter_cloak",
			"holder": {"kind": "entity", "id": "merchant"},
			"quantity": 1,
			"condition": {
				"durability": 41,
				"maximum_durability": 100,
				"quality": "worn",
			},
			"provenance": {"original_owner_entity_id": "merchant"},
		}, ["fact.cloak.merchant.created"]),
		"3. 同一 ItemDef 可创建不同持有人、耐久与来源的装备实例"
	)
	var equipment_store = EquipmentStoreModel.new()
	equipment_store.configure(
		registry.list_definitions("equipment_slot"),
		entity_store,
		item_store,
		fact_store
	)
	equipment_store.ensure_loadout("player")
	equipment_store.ensure_loadout("merchant")
	_check(
		not equipment_store.apply_equipment_change({
			"operation": "equipment_set",
			"entity_id": "player",
			"slot_id": "body_outer",
			"item_instance_id": "item.cloak.player",
			"source_fact_ids": [],
		})
		and equipment_store.get_equipped_item_id("player", "body_outer") == "",
		"4. 没有来源 Fact 的装备写入被拒绝"
	)
	var equip_fact := _fact(
		"fact.cloak.player.equipped",
		"equipment_changed",
		"player",
		3
	)
	fact_store.add_fact(equip_fact)
	_check(
		equipment_store.apply_equipment_change({
			"operation": "equipment_set",
			"entity_id": "player",
			"slot_id": "body_outer",
			"item_instance_id": "item.cloak.player",
			"source_fact_ids": ["fact.cloak.player.equipped"],
		})
		and equipment_store.get_equipped_item_id("player", "slot.body_outer")
			== "item.cloak.player"
		and _item_history_has(
			item_store.get_item("item.cloak.player"),
			"equipped",
			"fact.cloak.player.equipped"
		),
		"5. 合法装备写入 Loadout 并在 ItemInstance 历史保留事实"
	)
	var wrong_slot_fact := _fact(
		"fact.cloak.player.wrong_slot",
		"equipment_changed",
		"player",
		4
	)
	fact_store.add_fact(wrong_slot_fact)
	_check(
		not equipment_store.apply_equipment_change({
			"operation": "equipment_set",
			"entity_id": "player",
			"slot_id": "utility",
			"item_instance_id": "item.cloak.player",
			"source_fact_ids": ["fact.cloak.player.wrong_slot"],
		})
		and equipment_store.get_equipped_item_id("player", "utility") == "",
		"6. ItemDef 不允许的装备位不会产生引用"
	)

	var writer = TransactionWorldWriterModel.new()
	var stores := {
		"entity_store": entity_store,
		"fact_store": fact_store,
		"item_store": item_store,
		"equipment_store": equipment_store,
	}
	var rejected_transfer = TransactionResultModel.new()
	rejected_transfer.mark_resolved("equipment_contract_test")
	rejected_transfer.add_fact(_fact(
		"fact.cloak.player.transfer.rejected",
		"item_transferred",
		"player",
		5
	))
	rejected_transfer.add_item_change({
		"operation": "transfer",
		"item_instance_id": "item.cloak.player",
		"new_holder": {"kind": "entity", "id": "merchant"},
		"source_fact_ids": ["fact.cloak.player.transfer.rejected"],
	})
	_check(
		not writer.apply_result(rejected_transfer, stores)
		and fact_store.get_fact("fact.cloak.player.transfer.rejected").is_empty()
		and item_store.is_held_by("item.cloak.player", "player")
		and equipment_store.get_equipped_item_id("player", "body_outer")
			== "item.cloak.player"
		and str(rejected_transfer.contract_status) == "invalid_contract",
		"7. 转移已装备物但不卸装时整笔事务拒绝且 Fact 不落地"
	)

	var accepted_transfer = TransactionResultModel.new()
	accepted_transfer.mark_resolved("equipment_contract_test")
	accepted_transfer.add_fact(_fact(
		"fact.cloak.player.transfer.accepted",
		"item_transferred",
		"player",
		6
	))
	accepted_transfer.add_item_change({
		"operation": "transfer",
		"item_instance_id": "item.cloak.player",
		"new_holder": {"kind": "entity", "id": "merchant"},
		"source_fact_ids": ["fact.cloak.player.transfer.accepted"],
	})
	accepted_transfer.add_equipment_change({
		"operation": "equipment_clear",
		"entity_id": "player",
		"slot_id": "body_outer",
		"source_fact_ids": ["fact.cloak.player.transfer.accepted"],
	})
	_check(
		writer.apply_result(accepted_transfer, stores)
		and not fact_store.get_fact(
			"fact.cloak.player.transfer.accepted"
		).is_empty()
		and item_store.is_held_by("item.cloak.player", "merchant")
		and equipment_store.get_equipped_item_id("player", "body_outer") == ""
		and _item_history_has(
			item_store.get_item("item.cloak.player"),
			"unequipped",
			"fact.cloak.player.transfer.accepted"
		),
		"8. 同笔 clear 与 transfer 通过预检并同步写入"
	)

	var merchant_equip_fact := _fact(
		"fact.cloak.player.merchant_equipped",
		"equipment_changed",
		"merchant",
		7
	)
	fact_store.add_fact(merchant_equip_fact)
	equipment_store.apply_equipment_change({
		"operation": "equipment_set",
		"entity_id": "merchant",
		"slot_id": "body_outer",
		"item_instance_id": "item.cloak.player",
		"source_fact_ids": ["fact.cloak.player.merchant_equipped"],
	})
	var rejected_break = TransactionResultModel.new()
	rejected_break.mark_resolved("equipment_contract_test")
	rejected_break.add_fact(_fact(
		"fact.cloak.player.break.rejected",
		"item_durability_changed",
		"merchant",
		8
	))
	rejected_break.add_item_change({
		"operation": "adjust_durability",
		"item_instance_id": "item.cloak.player",
		"to": 0,
		"source_fact_ids": ["fact.cloak.player.break.rejected"],
	})
	_check(
		not writer.apply_result(rejected_break, stores)
		and fact_store.get_fact("fact.cloak.player.break.rejected").is_empty()
		and int((item_store.get_item("item.cloak.player").get(
			"condition",
			{}
		) as Dictionary).get("durability", 0)) == 83
		and equipment_store.get_equipped_item_id("merchant", "body_outer")
			== "item.cloak.player",
		"9. 完全损坏已装备物但不卸装时整笔事务拒绝"
	)
	var accepted_break = TransactionResultModel.new()
	accepted_break.mark_resolved("equipment_contract_test")
	accepted_break.add_fact(_fact(
		"fact.cloak.player.break.accepted",
		"item_durability_changed",
		"merchant",
		9
	))
	accepted_break.add_item_change({
		"operation": "adjust_durability",
		"item_instance_id": "item.cloak.player",
		"to": 0,
		"source_fact_ids": ["fact.cloak.player.break.accepted"],
	})
	accepted_break.add_equipment_change({
		"operation": "equipment_clear",
		"entity_id": "merchant",
		"slot_id": "body_outer",
		"source_fact_ids": ["fact.cloak.player.break.accepted"],
	})
	_check(
		writer.apply_result(accepted_break, stores)
		and int((item_store.get_item("item.cloak.player").get(
			"condition",
			{}
		) as Dictionary).get("durability", -1)) == 0
		and equipment_store.get_equipped_item_id("merchant", "body_outer") == "",
		"10. 同笔 clear 与完全损坏可安全落地"
	)

	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		OUTPOST_FIXTURE_PATH,
		RULE_PATHS
	)
	_check(
		bool(start.get("success", false))
		and int(start.get("definition_count", 0)) == 59
		and bool((start.get(
			"equipment_contract_report",
			{}
		) as Dictionary).get("ok", false)),
		"11. Session 启动时接入装备位与 Loadout 合同"
	)
	if not bool(start.get("success", false)):
		_finish()
		return
	var snapshot: Variant = session.get_snapshot()
	var equipped_cloak: Dictionary = snapshot.get_equipped_item(
		"player",
		"body_outer"
	)
	var inventory_view: Dictionary = snapshot.get_inventory_view("player")
	_check(
		str(equipped_cloak.get("item_instance_id", ""))
			== "item_instance.seventh_outpost.player_winter_cloak"
		and str(equipped_cloak.get("item_def_id", ""))
			== "item.waxed_winter_cloak"
		and int((equipped_cloak.get("condition", {}) as Dictionary).get(
			"durability",
			0
		)) == 76
		and (inventory_view.get("item_instance_ids", []) as Array).size() == 5
		and "item_instance.seventh_outpost.player_winter_cloak" in (
			inventory_view.get("item_instance_ids", []) as Array
		)
		and "item_instance.seventh_outpost.player_repair_hammer" in (
			inventory_view.get("item_instance_ids", []) as Array
		)
		and "item_instance.seventh_outpost.player_patrol_lantern" in (
			inventory_view.get("item_instance_ids", []) as Array
		)
		and is_equal_approx(float(inventory_view.get("total_mass", 0.0)), 6.54),
		"12. 第七哨站三件装备与随身物同时进入 InventoryView 投影"
	)
	var outpost_market: Dictionary = snapshot.get_market_stock_view("seventh_outpost")
	var player_market: Dictionary = snapshot.get_market_stock_view("player")
	_check(
		(outpost_market.get("offers", []) as Array).size() == 2
		and (player_market.get("offers", []) as Array).size() == 5
		and str(((player_market.get("offers", []) as Array)[0] as Dictionary).get(
			"quote_status",
			""
		)) == "unquoted",
		"13. MarketStockView 只从实际 holder 派生且不伪造价格"
	)
	_check(
		session.get_store_snapshots().has("equipment_loadouts")
		and int(session.get_store_summary().get("equipment_loadouts", 0)) == 1
		and not session.context.player.has("equipment_loadout"),
		"14. EquipmentLoadout 只存在 Store，Snapshot 与摘要均为读取面"
	)

	_finish()


func _fact(
		fact_id: String,
		fact_type: String,
		actor_id: String,
		tick: int
) -> Dictionary:
	return {
		"fact_id": fact_id,
		"fact_type": fact_type,
		"actor_id": actor_id,
		"tick": tick,
	}


func _item_history_has(
		item: Dictionary,
		event_type: String,
		fact_id: String
) -> bool:
	for entry: Dictionary in item.get("history", []):
		if (
			str(entry.get("event_type", "")) == event_type
			and str(entry.get("fact_id", "")) == fact_id
		):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 EQUIPMENT CONTRACT PASS] " + message)
	else:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 EQUIPMENT CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 EQUIPMENT CONTRACT FAIL] " + failure)
	print("[V5 EQUIPMENT CONTRACT RESULT] FAIL: %s" % JSON.stringify(failures))
	quit(1)
