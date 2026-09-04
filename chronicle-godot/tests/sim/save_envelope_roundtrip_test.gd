extends SceneTree

const ControllerModel = preload(
	"res://scripts/sim/life_project/life_project_controller.gd"
)
const SaveEnvelopeServiceModel = preload(
	"res://scripts/sim/save/save_envelope_service.gd"
)

const FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_winter.json"
)
const SAVE_PATH := "user://tests/save_envelope_roundtrip.json"
const DECIMAL_SAVE_PATH := "user://tests/save_envelope_decimal_roundtrip.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original = ControllerModel.new()
	var start: Dictionary = original.start(FIXTURE, PROJECT)
	_check(bool(start.get("success", false)), "1. 第一冬可作为正式存档验收场景启动")
	if not bool(start.get("success", false)):
		_finish()
		return
	var duty: Dictionary = original.execute_duty("patrol_fog_line")
	_check(
		bool(duty.get("success", false)) and original.get_day() == 2,
		"2. 保存前已产生职责、NPC、世界时间和生活项目 runtime"
	)

	var before_store: Dictionary = original.session.get_save_store_data()
	var before_candidates := _canonical_candidates(original.get_duty_options())
	var before_time: Dictionary = original.session.get_time_summary()
	var before_history: Array = original.day_history.duplicate(true)
	var envelope: Dictionary = original.build_save_envelope({
		"save_id": "save.test.roundtrip",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-13T06:00:00Z",
		"saved_at_utc": "2026-08-13T06:10:00Z",
	})
	var decoded: Variant = JSON.parse_string(JSON.stringify(envelope))
	_check(
		decoded is Dictionary
		and str(envelope.get("payload_kind", "")) == "save_envelope"
		and str((envelope.get("integrity", {}) as Dictionary).get(
			"payload_hash", ""
		)) != ""
		and not (envelope.get("stores", {}) as Dictionary).has("inventory")
		and not (envelope.get("stores", {}) as Dictionary).has("market_stock"),
		"3. 正式 SaveEnvelope v1 包含完整性摘要且不保存派生投影"
	)

	var memory_restored = ControllerModel.new()
	var memory_report: Dictionary = memory_restored.load_from_save_envelope(decoded)
	_check(
		bool(memory_report.get("success", false))
		and memory_restored.get_day() == original.get_day()
		and _equivalent(
			memory_restored.session.get_save_store_data(), before_store
		)
		and _equivalent(
			memory_restored.session.get_time_summary(), before_time
		)
		and _equivalent(memory_restored.day_history, before_history)
		and _equivalent(
			_canonical_candidates(memory_restored.get_duty_options()),
			before_candidates
		),
		"4. 内存载入后 Store、时间、生活游标与行动候选完全一致"
	)

	var save_report: Dictionary = original.save_to_path(SAVE_PATH, {
		"save_id": "save.test.disk",
		"source_kind": "test_fixture",
		"created_at_utc": "2026-08-13T06:00:00Z",
		"saved_at_utc": "2026-08-13T06:20:00Z",
	})
	var disk_restored = ControllerModel.new()
	var disk_report: Dictionary = disk_restored.load_from_path(SAVE_PATH)
	_check(
		bool(save_report.get("ok", false))
		and bool(disk_report.get("success", false))
		and _equivalent(
			disk_restored.session.get_save_store_data(), before_store
		)
		and _equivalent(
			_canonical_candidates(disk_restored.get_duty_options()),
			before_candidates
		),
		"5. user 路径磁盘保存与载入恢复相同真值和候选"
	)

	var service = SaveEnvelopeServiceModel.new()
	var previous_pack := envelope.duplicate(true)
	previous_pack["definition_manifest"]["content_pack_version"] = 1
	previous_pack["definition_manifest"]["required_definition_ids"].erase("item:item.fiber_rope")
	previous_pack = service.finalize_envelope(previous_pack)
	var previous_pack_path := "user://tests/save_previous_content_pack.json"
	var previous_save: Dictionary = service.save_to_path(previous_pack_path, previous_pack)
	var previous_restored = ControllerModel.new()
	var previous_report: Dictionary = previous_restored.load_from_path(previous_pack_path)
	_check(
		bool(previous_save.get("ok", false))
		and bool(previous_report.get("success", false))
		and "base_v1_to_v2_fiber_rope" in previous_report.get("migrations", [])
		and "base_v2_to_v3_fiber_rope_durability" in previous_report.get(
			"migrations", []
		)
		and _equivalent(previous_restored.session.get_save_store_data(), before_store)
		and _equivalent(previous_restored.day_history, before_history)
		and int(previous_restored.build_save_envelope()["definition_manifest"]["content_pack_version"]) == 3,
		"5B. Previous 105-definition base pack migrates from disk without changing world history"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(previous_pack_path))
	var v2_pack := envelope.duplicate(true)
	v2_pack["definition_manifest"]["content_pack_version"] = 2
	var v2_stores: Dictionary = v2_pack.get("stores", {}).duplicate(true)
	var v2_items: Array = v2_stores.get("items", []).duplicate(true)
	var v2_facts: Array = v2_stores.get("facts", [])
	var source_fact_id := str((v2_facts[0] as Dictionary).get("fact_id", ""))
	v2_items.append({
		"item_instance_id": "item_instance.test.v2_fiber_rope",
		"item_def_id": "item.fiber_rope",
		"holder": {"kind": "entity", "id": "player"},
		"quantity": 1,
		"condition": {},
		"custom_tags": ["content_pack_v2_probe"],
		"provenance": {"created_by_fact_id": source_fact_id},
		"history": [],
		"created_tick": 0,
		"updated_tick": 0,
	})
	v2_stores["items"] = v2_items
	v2_pack["stores"] = v2_stores
	v2_pack = service.finalize_envelope(v2_pack)
	var v2_restored = ControllerModel.new()
	var v2_report: Dictionary = v2_restored.load_from_save_envelope(v2_pack)
	var migrated_rope: Dictionary = v2_restored.session.stores[
		"item_store"
	].get_item("item_instance.test.v2_fiber_rope")
	_check(
		bool(v2_report.get("success", false))
		and "base_v2_to_v3_fiber_rope_durability" in v2_report.get(
			"migrations", []
		)
		and int(migrated_rope.get("condition", {}).get("durability", 0)) == 4
		and int(migrated_rope.get("condition", {}).get(
			"maximum_durability", 0
		)) == 4,
		"5C. Content pack v2 rope receives explicit full durability during v3 migration"
	)
	for version: int in [1, 2, 3]:
		var broken_manifest := previous_pack.duplicate(true)
		broken_manifest["definition_manifest"]["content_pack_version"] = version
		if version == 1:
			broken_manifest["definition_manifest"]["required_definition_ids"].erase("item:item.travel_ration")
		broken_manifest = service.finalize_envelope(broken_manifest)
		var manifest_report: Dictionary = ControllerModel.new().load_from_save_envelope(broken_manifest)
		_check(
			str(manifest_report.get("error", "")) == "save_definition_manifest_mismatch",
			"5D. Missing definitions are still rejected outside the exact previous manifest: v%d" % version
		)
	var legacy := envelope.duplicate(true)
	legacy["schema_version"] = 0
	legacy["payload_kind"] = "save_envelope_v0"
	legacy.erase("integrity")
	var migrated = ControllerModel.new()
	var migration_report: Dictionary = migrated.load_from_save_envelope(legacy)
	_check(
		bool(migration_report.get("success", false))
		and "v0_to_v1" in (migration_report.get("migrations", []) as Array)
		and _equivalent(migrated.session.get_save_store_data(), before_store),
		"6. v0 迁移注册路径升级后恢复相同 Store 真值"
	)

	var tampered := envelope.duplicate(true)
	var tampered_stores: Dictionary = tampered.get("stores", {})
	(tampered_stores.get("states", {}) as Dictionary)["player"]["fatigue"] = 9
	tampered["stores"] = tampered_stores
	var tampered_report: Dictionary = ControllerModel.new().load_from_save_envelope(
		tampered
	)
	_check(
		not bool(tampered_report.get("success", false))
		and str(tampered_report.get("error", "")) == "save_payload_hash_mismatch",
		"7. 内容被篡改但摘要未更新的存档在完整性阶段被拒绝"
	)

	var broken_reference := envelope.duplicate(true)
	var broken_stores: Dictionary = broken_reference.get("stores", {})
	var relations: Dictionary = broken_stores.get("relationships", {})
	relations["missing_person"] = {"player": {"trust": 10}}
	broken_stores["relationships"] = relations
	broken_reference["stores"] = broken_stores
	broken_reference = service.finalize_envelope(broken_reference)
	var broken_report: Dictionary = ControllerModel.new().load_from_save_envelope(
		broken_reference
	)
	_check(
		not bool(broken_report.get("success", false))
		and str(broken_report.get("phase", "")) == "references",
		"8. 摘要有效但跨 Store 引用损坏的存档仍被拒绝"
	)

	var future := envelope.duplicate(true)
	future["schema_version"] = 99
	var future_report: Dictionary = ControllerModel.new().load_from_save_envelope(
		future
	)
	_check(
		not bool(future_report.get("success", false))
		and str(future_report.get("phase", "")) == "migration",
		"9. 高于运行时版本且无迁移路径的存档明确失败"
	)
	var malformed_v0 := legacy.duplicate(true)
	malformed_v0["session"] = "invalid"
	var malformed_report: Dictionary = ControllerModel.new().load_from_save_envelope(
		malformed_v0
	)
	_check(
		not bool(malformed_report.get("success", false))
		and str(malformed_report.get("phase", "")) == "migration"
		and str(malformed_report.get("error", "")) == (
			"save_v0_field_not_dictionary:session"
		),
		"10. 旧版容器类型损坏时返回迁移失败而不是触发脚本错误"
	)
	var decimal_envelope := envelope.duplicate(true)
	var decimal_session: Dictionary = decimal_envelope.get("session", {})
	decimal_session["decimal_roundtrip_probe"] = 0.03
	decimal_envelope["session"] = decimal_session
	decimal_envelope = service.finalize_envelope(decimal_envelope)
	var decimal_save: Dictionary = service.save_to_path(
		DECIMAL_SAVE_PATH, decimal_envelope
	)
	var decimal_load: Dictionary = service.load_from_path(DECIMAL_SAVE_PATH)
	var loaded_decimal := float((decimal_load.get(
		"envelope", {}
	) as Dictionary).get("session", {}).get(
		"decimal_roundtrip_probe", -1.0
	))
	var decimal_tampered := decimal_envelope.duplicate(true)
	(decimal_tampered.get("session", {}) as Dictionary)[
		"decimal_roundtrip_probe"
	] = 0.0301
	var decimal_tampered_report: Dictionary = service.validate_and_migrate(
		decimal_tampered
	)
	_check(
		bool(decimal_save.get("ok", false))
		and bool(decimal_load.get("ok", false))
		and is_equal_approx(loaded_decimal, 0.03)
		and str(decimal_tampered_report.get("error", ""))
		== "save_payload_hash_mismatch",
		"11. 常用小数跨磁盘解析不误报哈希错误，真实小数篡改仍被拒绝"
	)

	var original_next: Dictionary = original.execute_duty("patrol_fog_line")
	var restored_next: Dictionary = memory_restored.execute_duty("patrol_fog_line")
	_check(
		bool(original_next.get("success", false))
		and bool(restored_next.get("success", false))
		and _equivalent(original_next, restored_next)
		and _equivalent(
			original.session.get_save_store_data(),
			memory_restored.session.get_save_store_data()
		)
		and _equivalent(
			original.session.get_time_summary(),
			memory_restored.session.get_time_summary()
		),
		"12. 载入后继续承担同一职责会得到相同结果与后续世界状态"
	)
	_cleanup_save()
	_finish()


func _canonical_candidates(options: Array) -> Array:
	var rows: Array = options.duplicate(true)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("duty_id", "")) < str(b.get("duty_id", ""))
	)
	return rows


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
			if not _equivalent(
				(left as Array)[index], (right as Array)[index]
			):
				return false
		return true
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	return left == right


func _cleanup_save() -> void:
	for path: String in [SAVE_PATH, DECIMAL_SAVE_PATH]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(absolute)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SAVE ENVELOPE PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SAVE ENVELOPE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 SAVE ENVELOPE FAIL] " + failure)
	print("[V5 SAVE ENVELOPE RESULT] FAIL (%d)" % failures.size())
	quit(1)
