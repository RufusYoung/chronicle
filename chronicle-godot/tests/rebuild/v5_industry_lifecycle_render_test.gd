extends SceneTree

const Industry = preload("res://scripts/sim/settlement/industry_lifecycle_system.gd")
const Writer = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const RULES := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json"
]
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
	_check(
		bool(
			(
				session
				. start_from_fixture_path(
					"res://data/sim/fixtures/generated_settlement_network_fixture.json", RULES
				)
				. get("success", false)
			)
		),
		"normal generated world starts"
	)
	_check(
		bool(
			(
				session
				. advance_time(24 * 7, "industry_render", {"scope_type": "global", "scope_id": ""})
				. get("success", false)
			)
		),
		"world advances naturally before rendering"
	)
	var facts: Array = session.stores["fact_store"].list_facts().filter(
		func(fact: Dictionary) -> bool:
			return str(fact.get("fact_type", "")) == "settlement_industry_founded"
	)
	_check(not facts.is_empty(), "an industry is present without adding a scripted foundation")
	if facts.is_empty():
		_finish()
		return
	var fact: Dictionary = facts[0]
	var facility := str(fact.get("facility_entity_id", ""))
	var knowledge_started := Time.get_ticks_msec()
	var knowledge: Array = viewer.view_model._knowledge_rows(session.get_snapshot())
	var knowledge_seconds := float(Time.get_ticks_msec() - knowledge_started) / 1000.0
	_check(not knowledge.is_empty() and knowledge_seconds < 5.0,
		"seven-day knowledge list renders within five seconds without rebuilding a snapshot per fact")
	print("[INDUSTRY UI TIMING] knowledge_seconds=", knowledge_seconds)
	viewer.refresh_view()
	await _settle()
	_check(
		"产业变化" in str(viewer.get_node("%RegionStatus").text),
		"existing record surface reports industry change"
	)
	_check(
		"产业变化" in str(viewer.get_node("%DecisionSituation").text),
		"recent industry change is visible on the decision surface without opening records"
	)
	await _capture("industry_hub")
	await _travel(facility + ".visit")
	_check(
		str(session.context.location_id) == str(fact.get("workplace_id", "")),
		"visible route button enters the real new workplace"
	)
	_check(
		"制绳棚" in str(viewer.get_node("%LocationTitle").text),
		"site title names the actual facility, not an empty reserved plot"
	)
	_check(
		"某个对象" not in str(viewer.get_node("%GoalTitle").text),
		"workplace goal resolves the known settlement name"
	)
	await _capture("industry_active")
	var inspection: Button = null
	var inspection_id := ""
	for child: Node in viewer.get_node("%ActionButtons").get_children():
		var action := str(child.get_meta("action_id", ""))
		if child is Button and facility in action and "inspect_visible_trace" in action:
			inspection = child
			inspection_id = action
	_check(
		inspection != null and inspection.is_visible_in_tree() and not inspection.disabled,
		"new facility offers a visible inspection action"
	)
	if inspection != null and inspection.is_visible_in_tree() and not inspection.disabled:
		var started := Time.get_ticks_msec()
		inspection.pressed.emit()
		print("[INDUSTRY UI TIMING] inspection_seconds=", float(Time.get_ticks_msec() - started) / 1000.0)
	await _settle()
	_check(
		"劳动经验" in str(viewer.get_node("%FeedbackBody").text),
		"inspection feedback displays the actual founding account"
	)
	var repeated := false
	for child: Node in viewer.get_node("%ActionButtons").get_children():
		if str(child.get_meta("action_id", "")) == inspection_id:
			repeated = true
	_check(not repeated, "completed one-time inspection no longer occupies an action slot")
	await _capture("industry_inspected")
	var runtime: Dictionary = session.get_settlement_network_summary()
	runtime["industry_lifecycle"]["exit_days_required"] = 1
	runtime["industry_lifecycle"]["conditions"] = {
		"cordage":
		{"demand_kind": "route_risk", "entry_demand_at_least": 999, "exit_demand_below": 999}
	}
	var snapshot: Variant = session.snapshot_builder.build_snapshot(
		session.context, session.stores, true
	)
	var day := int(session.get_time_summary().get("day", 0)) + 1
	var data: Dictionary = Industry.new().resolve_daily_tick(
		snapshot,
		{"day": day},
		runtime,
		session.npc_livelihood_profiles,
		session.context.get_locations()
	)
	_check(
		Writer.new().apply_results(data.get("results", []), session.stores),
		"test intervention retires the same facility through its transaction"
	)
	viewer.refresh_view()
	await _settle()
	_check(
		"旧址" in str(viewer.get_node("%LocationTitle").text),
		"retirement changes the current site to a ruin"
	)
	_check(
		"需求" in str(viewer.get_node("%LocationDescription").text),
		"site description explains why this facility retired"
	)
	await _capture("industry_retired")
	await _travel(facility + ".return")
	_check(
		str(session.context.location_id) == str(fact.get("hub_location_id", "")),
		"retired site retains a working return route"
	)
	var return_visit: Button = null
	for child: Node in viewer.get_node("%TravelButtons").get_children():
		if child is Button and str(child.get_meta("route_id", "")) == facility + ".visit":
			return_visit = child
	_check(
		return_visit != null and "旧址" in return_visit.text,
		"hub route also identifies the retired workplace without a local entity snapshot"
	)
	_finish()


func _settle() -> void:
	for frame: int in 4:
		await process_frame


func _travel(id: String) -> void:
	var found: Button = null
	for child: Node in viewer.get_node("%TravelButtons").get_children():
		if child is Button and str(child.get_meta("route_id", "")) == id:
			found = child
	var before: Dictionary = viewer.view_model.session.get_time_summary()
	var previous := viewer.get_node("%PreviousTravel") as Button
	var next := viewer.get_node("%NextTravel") as Button
	while not previous.disabled:
		previous.pressed.emit()
	while found != null and not found.is_visible_in_tree() and not next.disabled:
		next.pressed.emit()
	await _settle()
	_check(
		before == viewer.view_model.session.get_time_summary(),
		"browsing destinations does not advance world time"
	)
	_check(
		found != null and found.is_visible_in_tree() and not found.disabled,
		"route is visible and enabled: " + id
	)
	if found != null and found.is_visible_in_tree() and not found.disabled:
		var started := Time.get_ticks_msec()
		found.pressed.emit()
		print("[INDUSTRY UI TIMING] travel_seconds=", float(Time.get_ticks_msec() - started) / 1000.0)
	await _settle()


func _capture(name: String) -> void:
	var errors: Array[String] = []
	_audit(viewer, errors)
	_check(errors.is_empty(), "visible text and buttons fit at 720p: " + str(errors))
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	_check(
		root.get_texture().get_image().save_png("user://tests/" + name + ".png") == OK,
		"render saved: " + name
	)


func _audit(node: Node, errors: Array[String]) -> void:
	if node is Control and not node.is_visible_in_tree():
		return
	if (
		node is RichTextLabel
		and (node.scroll_active or node.get_content_height() > node.size.y + 2)
	):
		errors.append("clipped_text:" + str(node.name))
	if node is RichTextLabel or node is Button:
		if not Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(1).encloses(
			node.get_global_rect()
		):
			errors.append("outside:" + str(node.name))
	for child: Node in node.get_children():
		_audit(child, errors)


func _check(condition: bool, label: String) -> void:
	print("[INDUSTRY RENDER %s] %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)


func _finish() -> void:
	viewer.queue_free()
	print("[INDUSTRY RENDER RESULT] ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
