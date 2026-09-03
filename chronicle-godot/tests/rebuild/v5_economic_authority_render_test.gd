extends SceneTree

const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")
const Transaction = preload("res://scripts/sim/transaction/transaction_result.gd")
const Work = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const RULES := ["res://data/sim/raw/action_rules/basic_action_rules.json", "res://data/sim/raw/action_rules/domain_action_rules.json"]
var failures: Array[String] = []
var viewer: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	viewer = load("res://scenes/rebuild/v5_live_location_viewer.tscn").instantiate()
	root.add_child(viewer)
	await process_frame
	var session: Variant = viewer.view_model.session
	_check(session.start_from_fixture_path("res://data/sim/fixtures/generated_settlement_network_fixture.json", RULES).get("success", false), "generated economic world starts")
	_check(session.advance_time(24, "economic_render_autonomous").get("success", false), "one autonomous day pays wages")
	viewer.refresh_view()
	await _settle()
	var records := viewer.get_node("%RegionStatus") as RichTextLabel
	_check("公共金库" in records.text and "可支出" in records.text and "已实际支付" in records.text and "未结算货币的调拨" in records.text, "existing records show real funds, payment and unpaid cargo boundary")
	var time_before: Dictionary = session.get_time_summary()
	var tabs := viewer.get_node("%WorldSurfacePages") as TabContainer
	tabs.current_tab = 2
	await _settle()
	var scroll := tabs.get_child(2) as ScrollContainer
	scroll.scroll_vertical += int(records.global_position.y - scroll.global_position.y)
	await _settle()
	await _capture("economic_funded_records")
	tabs.current_tab = 0
	await _settle()
	_check(time_before == session.get_time_summary(), "viewing balances and returning does not advance world time")
	var snapshot: Variant = session.snapshot_builder.build_snapshot(session.context, session.stores, true)
	var manager := "generated_settlement.reed_bay"
	var sink := str(snapshot.get_entities().filter(func(row: Dictionary) -> bool: return str(row.get("type", "")) == "person")[0]["id"])
	var treasury = Treasury.new(snapshot)
	var result = Transaction.new()
	result.add_fact({"fact_id": "fact.test.economic_render.drain", "fact_type": "test_injection", "summary": "测试注入：转出公共金库余款"})
	_check(treasury.append_payment(result, manager, sink, treasury.balance(manager), result.facts_added[0]["fact_id"], 48), "test injection transfers remaining funds to an actual person")
	result.mark_resolved("test_injection")
	_check(session.writer.apply_result(result, session.stores), "money drain applies without deleting currency")
	for person: Dictionary in snapshot.get_entities():
		if str(person.get("type", "")) == "person":
			session.stores["state_store"].apply_state_change({"entity_id": person["id"], "key": "livelihood_elapsed_hours", "to": 100})
	snapshot = session.snapshot_builder.build_snapshot(session.context, session.stores, true)
	var profiles: Array = session.npc_livelihood_profiles.filter(func(row: Dictionary) -> bool: return int(row.get("wage_amount", 0)) > 0 and str(row.get("settlement_id", "")) == manager)
	var work: Dictionary = Work.new().resolve_work_tick(snapshot, profiles, {"tick_event_id": "test.economic_render.unfunded", "elapsed_hours": 1, "day": session.current_day, "hour": 8})
	_check(session.writer.apply_results(work.get("results", []), session.stores), "real work planner declines unfunded shifts")
	viewer.refresh_view()
	await _settle()
	_check("0 枚铜币 · 可支出 0" in records.text and "薪酬不足，本轮未开工" in records.text, "zero balance is explicit, not missing or negative")
	var decision := viewer.get_node("%DecisionSituation") as RichTextLabel
	_check("薪酬不足，本轮未开工" in decision.text and not decision.scroll_active, "current unfunded work is visible on decision surface without an inner scrollbar")
	_check(decision.get_global_rect().end.y <= root.content_scale_size.y and decision.get_content_height() <= decision.size.y + 2, "key consequence fits at 1280 by 720")
	await _capture("economic_unfunded_scene")
	session.stores["fact_store"].add_fact({"fact_id": "fact.test.economic_render.denial", "fact_type": "organization_resource_access_blocked",
		"actor_id": "generated_organization.reed_bay.provision_circle", "target_id": manager, "day": session.current_day,
		"reason": "organization_daily_limit", "summary": "测试注入展示样本：共食会当天资源额度已用完，不能继续调拨。"})
	viewer.refresh_view()
	await _settle()
	_check("当日额度不足，计划未执行" in decision.text and "测试注入展示样本" in records.text, "quota refusal has an explicit decision-surface reason and full record")
	viewer.queue_free()
	await process_frame
	print("[ECONOMIC UI RESULT] ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _settle() -> void:
	await process_frame
	await process_frame


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://tests/" + name + ".png"
	_check(root.get_texture().get_image().save_png(path) == OK, "screenshot written: " + name)
	print("[ECONOMIC UI IMAGE] ", ProjectSettings.globalize_path(path))


func _check(ok: bool, message: String) -> void:
	print("[ECONOMIC UI %s] %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures.append(message)
