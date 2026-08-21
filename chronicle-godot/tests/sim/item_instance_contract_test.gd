extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const EntityStoreModel = preload("res://scripts/sim/entity/entity_store.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const ItemStoreModel = preload("res://scripts/sim/item/item_store.gd")

const STATE_DEFS_PATH := "res://data/sim/raw/state_defs/basic_state_defs.json"
const OBJECT_DEFS_PATH := "res://data/sim/raw/object_defs/basic_object_defs.json"
const FEATURE_DEFS_PATH := (
	"res://data/sim/raw/character_feature_defs/basic_character_feature_defs.json"
)
const ITEM_DEFS_PATH := "res://data/sim/raw/item_defs/basic_item_defs.json"
const EQUIPMENT_SLOT_DEFS_PATH := (
	"res://data/sim/raw/equipment_slot_defs/basic_equipment_slot_defs.json"
)
const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = SimRegistryModel.new()
	var report: Dictionary = registry.load_raw_definition_files([
		STATE_DEFS_PATH,
		OBJECT_DEFS_PATH,
		FEATURE_DEFS_PATH,
		ITEM_DEFS_PATH,
		EQUIPMENT_SLOT_DEFS_PATH,
	])
	_check(
		bool(report.get("ok", false))
		and int(report.get("total_definition_count", 0)) == 101
		and registry.has_definition("item", "item.travel_ration")
		and registry.has_definition("item", "item.waxed_winter_cloak")
		and registry.has_definition("item", "item.copper_coin")
		and registry.has_definition("item", "item.field_repair_hammer"),
		"1. ItemDef 以稳定 ID 进入严格 Registry"
	)
	var invalid_registry = SimRegistryModel.new()
	_check(
			not invalid_registry.register_definition("item", "item.invalid", {
			"definition_version": 1,
			"display_name_key": "item.invalid.name",
			"item_kind": "equipment",
			"tags": [],
			"stackable": false,
			"max_stack": 4,
			"base_mass": -1,
			"equip_slots": [],
			"capabilities": [],
			"durability": {"maximum": 0},
			"modifiers": [],
				"base_value": 0,
			})
		and not invalid_registry.register_definition(
			"item",
			"item.invalid_fractional_durability",
			{
				"definition_version": 1,
				"display_name_key": "item.invalid_fractional_durability.name",
				"item_kind": "equipment",
				"tags": [],
				"stackable": false,
				"max_stack": 1,
				"base_mass": 1,
				"equip_slots": [],
				"capabilities": [],
				"durability": {"maximum": 1.5},
				"modifiers": [],
				"base_value": 0,
			}
		),
		"2. Registry 拒绝非堆叠多数量、负质量和非法耐久 ItemDef"
	)

	var entity_store = EntityStoreModel.new()
	entity_store.configure_definitions(registry.list_definitions("object"), true)
	entity_store.add_entity("player", {"type": "person", "role": "traveler"})
	entity_store.add_entity("merchant", {"type": "person", "role": "merchant"})
	var fact_store = FactStoreModel.new()
	var store = ItemStoreModel.new()
	store.configure(
		registry.list_definitions("item"),
		entity_store,
		{"camp": {"id": "camp"}},
		fact_store
	)
	_check(
		not store.create_item({
			"item_instance_id": "item_instance.unknown",
			"item_def_id": "item.unknown",
			"holder": {"kind": "entity", "id": "player"},
			"quantity": 1,
			"source_kind": "test_fixture",
		})
		and not store.create_item({
			"item_instance_id": "item_instance.bad_holder",
			"item_def_id": "item.waxed_winter_cloak",
			"holder": {"kind": "entity", "id": "missing"},
			"quantity": 1,
			"source_kind": "test_fixture",
		}),
		"3. ItemStore 拒绝未知 Definition 与悬空 holder"
	)
	_check(
		not store.create_item({
			"item_instance_id": "item_instance.two_cloaks",
			"item_def_id": "item.waxed_winter_cloak",
			"holder": {"kind": "entity", "id": "player"},
			"quantity": 2,
			"source_kind": "test_fixture",
		})
		and not store.create_item({
			"item_instance_id": "item_instance.spoofed_fixture",
			"item_def_id": "item.waxed_winter_cloak",
			"holder": {"kind": "entity", "id": "player"},
			"quantity": 1,
			"source_kind": "test_fixture",
		})
		and not store.items.has("item_instance.spoofed_fixture"),
		"4. 非堆叠数量受限且运行时创建不能伪造 fixture 来源"
	)

	var creation_fact := _fact(
		"fact.item.cloak.created",
		"item_created",
		"player",
		10
	)
	var ration_fact := _fact(
		"fact.item.rations.created",
		"item_created",
		"player",
		11
	)
	fact_store.add_fact(creation_fact)
	fact_store.add_fact(ration_fact)
	_check(
		not store.create_item({
			"item_instance_id": "item_instance.fractional_stack",
			"item_def_id": "item.travel_ration",
			"holder": {"kind": "entity", "id": "player"},
			"quantity": 1.5,
		}, ["fact.item.rations.created"])
		and not store.create_item({
			"item_instance_id": "item_instance.prefilled_history",
			"item_def_id": "item.waxed_winter_cloak",
			"holder": {"kind": "entity", "id": "player"},
			"quantity": 1,
			"history": [{"fact_id": "fact.item.cloak.created"}],
		}, ["fact.item.cloak.created"])
		and store.create_item({
			"item_instance_id": "item_instance.cloak.1",
			"item_def_id": "item.waxed_winter_cloak",
			"holder": {"kind": "entity", "id": "player"},
			"quantity": 1,
			"condition": {
				"durability": 83,
				"maximum_durability": 100,
				"quality": "serviceable",
			},
			"provenance": {"created_by_fact_id": "fact.spoofed"},
			"created_tick": 10,
		}, ["fact.item.cloak.created"])
		and store.create_item({
			"item_instance_id": "item_instance.rations.1",
			"item_def_id": "item.travel_ration",
			"holder": {"kind": "entity", "id": "player"},
			"quantity": 5,
			"created_tick": 11,
		}, ["fact.item.rations.created"]),
		"5. 运行时创建拒绝小数数量和预制历史，合法实例可创建"
	)
	var stored_cloak: Dictionary = store.items["item_instance.cloak.1"]
	var projected_cloak: Dictionary = store.get_item("item_instance.cloak.1")
	_check(
		not stored_cloak.has("owner_id")
		and not stored_cloak.has("item_id")
		and str(stored_cloak.get("item_instance_id", ""))
			== "item_instance.cloak.1"
		and str(projected_cloak.get("owner_id", "")) == "player"
		and str(projected_cloak.get("item_id", ""))
			== "item_instance.cloak.1"
		and str((stored_cloak.get("provenance", {}) as Dictionary).get(
			"created_by_fact_id",
			""
		)) == "fact.item.cloak.created",
		"6. Store 只保存 holder 与 item_instance_id，旧别名仅在读取时派生"
	)

	var transfer_fact := _fact(
		"fact.item.cloak.transferred",
		"item_transferred",
		"player",
		20
	)
	fact_store.add_fact(transfer_fact)
	_check(
		store.apply_item_change({
			"operation": "transfer",
			"item_instance_id": "item_instance.cloak.1",
			"new_holder": {"kind": "entity", "id": "merchant"},
			"source_fact_ids": ["fact.item.cloak.transferred"],
		})
		and store.list_items_for_owner("player").size() == 1
		and store.list_items_for_owner("merchant").size() == 1
		and str((store.get_item("item_instance.cloak.1").get(
			"history",
			[]
		) as Array)[0].get("fact_id", ""))
			== "fact.item.cloak.transferred",
		"7. transfer 原子改变 holder 并写入事实历史"
	)
	var snapshot_before_invalid_transfer := store.get_item(
		"item_instance.cloak.1"
	)
	_check(
		not store.apply_item_change({
			"operation": "transfer",
			"item_instance_id": "item_instance.cloak.1",
			"new_holder": {"kind": "entity", "id": "player"},
			"source_fact_ids": ["fact.missing"],
		})
		and store.get_item("item_instance.cloak.1")
			== snapshot_before_invalid_transfer,
		"8. 缺失事实的 transfer 被原子拒绝"
	)

	var durability_fact := _fact(
		"fact.item.cloak.damaged",
		"item_durability_changed",
		"merchant",
		21
	)
	fact_store.add_fact(durability_fact)
	_check(
		store.apply_item_change({
			"operation": "adjust_durability",
			"item_instance_id": "item_instance.cloak.1",
			"delta": -13,
			"source_fact_ids": ["fact.item.cloak.damaged"],
		})
		and int((store.get_item("item_instance.cloak.1").get(
			"condition",
			{}
		) as Dictionary).get("durability", -1)) == 70
		and not store.apply_item_change({
			"operation": "adjust_durability",
			"item_instance_id": "item_instance.cloak.1",
			"delta": -100,
			"source_fact_ids": ["fact.item.cloak.damaged"],
		}),
		"9. 耐久变化受 Definition 上限约束且越界写入被拒绝"
	)

	var split_fact := _fact(
		"fact.item.rations.split",
		"item_stack_split",
		"player",
		22
	)
	fact_store.add_fact(split_fact)
	_check(
		store.apply_item_change({
			"operation": "split_stack",
			"item_instance_id": "item_instance.rations.1",
			"quantity": 2,
			"new_item_instance_id": "item_instance.rations.2",
			"new_holder": {"kind": "location", "id": "camp"},
			"source_fact_ids": ["fact.item.rations.split"],
		})
		and int(store.get_item("item_instance.rations.1").get("quantity", 0)) == 3
		and int(store.get_item("item_instance.rations.2").get("quantity", 0)) == 2
		and (store.get_item("item_instance.rations.2").get(
			"provenance",
			{}
		) as Dictionary).get("parent_item_instance_ids", [])
			== ["item_instance.rations.1"]
		and str((store.get_item("item_instance.rations.2").get(
			"holder",
			{}
		) as Dictionary).get("kind", "")) == "location",
		"10. split_stack 保留总量并允许新堆叠进入合法 holder"
	)
	var increase_fact := _fact(
		"fact.item.rations.increased",
		"item_quantity_increased",
		"player",
		23
	)
	fact_store.add_fact(increase_fact)
	_check(
		store.apply_item_change({
			"operation": "increase_quantity",
			"item_instance_id": "item_instance.rations.2",
			"quantity": 2,
			"source_fact_ids": ["fact.item.rations.increased"],
		})
		and int(store.get_item(
			"item_instance.rations.2"
		).get("quantity", 0)) == 4
		and str((store.get_item("item_instance.rations.2").get(
			"history", []
		) as Array).back().get("fact_id", "")) == (
			"fact.item.rations.increased"
		)
		and not store.apply_item_change({
			"operation": "increase_quantity",
			"item_instance_id": "item_instance.rations.2",
			"quantity": 30,
			"source_fact_ids": ["fact.item.rations.increased"],
		}),
		"11. increase_quantity 合并合法堆叠、写入来源历史并拒绝越过上限"
	)

	var consume_fact := _fact(
		"fact.item.rations.consumed",
		"item_consumed",
		"player",
		23
	)
	fact_store.add_fact(consume_fact)
	_check(
		store.apply_item_change({
			"operation": "consume",
			"item_instance_id": "item_instance.rations.1",
			"quantity": 3,
			"source_fact_ids": ["fact.item.rations.consumed"],
		})
		and int(store.get_item("item_instance.rations.1").get("quantity", -1)) == 0
		and str((store.get_item("item_instance.rations.1").get(
			"holder",
			{}
		) as Dictionary).get("kind", "")) == "destroyed"
		and not store.apply_item_change({
			"operation": "transfer",
			"item_instance_id": "item_instance.rations.1",
			"new_holder": {"kind": "entity", "id": "player"},
			"source_fact_ids": ["fact.item.rations.consumed"],
		}),
		"12. 完全消耗将 holder 变为 destroyed 且不能重新转移"
	)
	_check(
		not store.apply_item_change({
			"operation": "transfer",
			"item_instance_id": "item_instance.cloak.1",
			"new_holder": {
				"kind": "container",
				"id": "item_instance.cloak.1",
			},
			"source_fact_ids": ["fact.item.cloak.transferred"],
		}),
		"13. container holder 拒绝直接自包含循环"
	)

	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH,
		RULE_PATHS
	)
	if not bool(start.get("success", false)):
		_check(false, "14. Session 启动失败：%s" % JSON.stringify(start))
		_finish()
		return
	_check(
		int(start.get("definition_count", 0)) == 101
		and bool((start.get("item_contract_report", {}) as Dictionary).get(
			"ok",
			false
		))
		and not session.stores["state_store"].list_states("player").has(
			"inventory_item_ids"
		),
		"14. Session 接入 ItemDef 与 ItemStore 合同且 StateStore 不保存库存数组"
	)
	session.travel("old_chen_shop_to_abandoned_granary")
	session.execute_challenge_option("prepare_granary_entry")
	session.execute_challenge_option(
		"enter_abandoned_granary",
		{"source": "test_injection", "roll_override": 3}
	)
	var snapshot: Variant = session.get_snapshot()
	var token: Dictionary = snapshot.get_item("lake_town_granary_measure_token")
	var internal_token: Dictionary = session.stores["item_store"].items[
		"lake_town_granary_measure_token"
	]
	_check(
		str(token.get("item_def_id", ""))
			== "item.lake_town_granary_measure_token"
		and str((token.get("holder", {}) as Dictionary).get("id", ""))
			== "player"
		and not internal_token.has("owner_id")
		and not internal_token.has("item_id")
		and "lake_town_granary_measure_token" in (
			snapshot.get_player_value("inventory_item_ids", []) as Array
		)
		and "item_instance.lake_town.player_travel_rations" in (
			snapshot.get_player_value("inventory_item_ids", []) as Array
		)
		and not session.stores["state_store"].list_states("player").has(
			"inventory_item_ids"
		),
		"15. 真实发现物只以 holder 存储，旧库存数组由 Snapshot 当场派生"
	)
	_check(
		not session.stores["state_store"].set_state(
			"player",
			"inventory_item_ids",
			["forged"]
		)
		and session.stores["state_store"].last_error.ends_with(
			"external_projection_owned_key"
		),
		"16. StateStore 拒绝伪造 inventory_item_ids 第二真值"
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


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 ITEM INSTANCE CONTRACT PASS] " + message)
	else:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 ITEM INSTANCE CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 ITEM INSTANCE CONTRACT FAIL] " + failure)
	print("[V5 ITEM INSTANCE CONTRACT RESULT] FAIL: %s" % JSON.stringify(failures))
	quit(1)
