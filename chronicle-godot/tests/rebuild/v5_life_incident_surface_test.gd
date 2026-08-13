extends SceneTree

const VIEWER_SCENE := (
	"res://scenes/rebuild/v5_seventh_outpost_viewer.tscn"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame
	for unused: int in range(7):
		viewer.perform_duty("patrol_fog_line")
		await process_frame
	viewer.confirm_growth_candidate("growth.first_winter.fog_reader")
	await process_frame
	viewer.enter_first_quarter()
	await process_frame
	var duty_result: Dictionary = viewer.perform_duty(
		"survey_thaw_routes",
		{
			"incident_roll_override": 1,
			"incident_id_override": "marta_thin_stew",
		}
	)
	await process_frame
	await process_frame
	var heading := viewer.get_node("%ActionHeading") as Label
	var hint := viewer.get_node("%ActionHint") as Label
	var buttons := viewer.get_node("%ActionButtons") as FlowContainer
	var day_label := viewer.get_node("%DayLabel") as Label
	_check(
		bool(duty_result.get("incident_pending", false))
		and "途中插曲" in heading.text
		and "空锅" in heading.text
		and "锅底" in hint.text
		and "补给已经降到 5" in hint.text,
		"1a. Incident surface explains what happened and which state caused it"
	)
	_check(
		buttons.get_child_count() == 2
		and _find_duty_button(buttons) == null,
		"1b. Incident replaces every duty with exactly two responses"
	)
	_check(
		"结算后" in day_label.text,
		"1c. Header explains that time already advanced before the response"
	)
	var response := _find_response_button(buttons, "scrape_the_pot")
	_check(
		response != null
		and "疲劳 +1" in response.text
		and "玛塔信任 +1" in response.text,
		"2. Response previews its concrete state and relationship changes"
	)
	response.pressed.emit()
	await process_frame
	await process_frame
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	_check(
		feedback_title.text == "锅底最后一层麦粒没有浪费"
		and "没有新任务出现" in feedback_body.text
		and "疲劳 +1" in feedback_body.text
		and "玛塔信任 +1" in feedback_body.text
		and _find_response_button(buttons, "scrape_the_pot") == null
		and _find_duty_button(buttons) != null,
		"3. Response disappears once, result is explicit, and duties return"
	)
	viewer.queue_free()
	await process_frame
	_finish()


func _find_response_button(container: Node, response_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta(
			"incident_response_id", ""
		)) == response_id:
			return child as Button
	return null


func _find_duty_button(container: Node) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta("duty_id", "")) != "":
			return child as Button
	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 LIFE INCIDENT SURFACE PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LIFE INCIDENT SURFACE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 LIFE INCIDENT SURFACE FAIL] " + failure)
	print("[V5 LIFE INCIDENT SURFACE RESULT] FAIL (%d)" % failures.size())
	quit(1)
