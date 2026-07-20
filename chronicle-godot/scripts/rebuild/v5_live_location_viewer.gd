extends Control
class_name V5LiveLocationViewer

const ViewModelModel = preload(
	"res://scripts/rebuild/v5_live_location_view_model.gd"
)

var view_model: Variant = null
var current_view_data: Dictionary = {}

@onready var location_title: Label = %LocationTitle
@onready var location_context: Label = %LocationContext
@onready var location_description: RichTextLabel = %LocationDescription
@onready var player_summary: RichTextLabel = %PlayerSummary
@onready var region_status: RichTextLabel = %RegionStatus
@onready var visible_people: RichTextLabel = %VisiblePeople
@onready var visible_observations: RichTextLabel = %VisibleObservations
@onready var knowledge_text: RichTextLabel = %KnowledgeText
@onready var travel_heading: Label = %TravelHeading
@onready var travel_buttons: VBoxContainer = %TravelButtons
@onready var feedback_title: Label = %FeedbackTitle
@onready var feedback_body: RichTextLabel = %FeedbackBody
@onready var history_text: RichTextLabel = %HistoryText
@onready var action_heading: Label = %ActionHeading
@onready var action_buttons: FlowContainer = %ActionButtons
@onready var time_label: Label = %TimeLabel
@onready var wait_button: Button = %WaitButton
@onready var restart_button: Button = %RestartButton


func _ready() -> void:
	view_model = ViewModelModel.new()
	wait_button.pressed.connect(advance_time)
	restart_button.pressed.connect(restart_session)
	restart_session()


func restart_session() -> void:
	view_model.start()
	refresh_view()


func perform_action(action_id: String) -> Dictionary:
	var result: Dictionary = view_model.perform_action(action_id)
	refresh_view()
	return result


func perform_travel(route_id: String) -> Dictionary:
	var result: Dictionary = view_model.perform_travel(route_id)
	refresh_view()
	return result


func advance_time() -> Dictionary:
	var result: Dictionary = view_model.advance_time(1)
	refresh_view()
	return result


func refresh_view() -> void:
	current_view_data = view_model.build_view_data()
	if not bool(current_view_data.get("ready", false)):
		_show_load_error(str(current_view_data.get("error_text", "局面暂时无法载入。")))
		return

	var location: Dictionary = current_view_data.get("location", {})
	location_title.text = str(location.get("title", "未知地点"))
	location_context.text = str(location.get("context", ""))
	location_description.text = str(location.get("description", ""))

	var player: Dictionary = current_view_data.get("player", {})
	player_summary.text = str(player.get("summary", ""))
	var time_data: Dictionary = current_view_data.get("time", {})
	time_label.text = "%s　%s" % [
		str(time_data.get("label", "")),
		str(time_data.get("period", "")),
	]
	region_status.text = _format_status_rows(
		current_view_data.get("region_status", []) as Array
	)
	visible_people.text = _format_entity_rows(
		current_view_data.get("visible_people", []) as Array,
		"这里没有值得留意的人。"
	)
	visible_observations.text = _format_entity_rows(
		current_view_data.get("visible_observations", []) as Array,
		"眼前没有明显的物件或痕迹。"
	)
	knowledge_text.text = _format_bullets(
		current_view_data.get("knowledge", []) as Array
	)
	_refresh_feedback(current_view_data.get("feedback", {}) as Dictionary)
	_refresh_history(current_view_data.get("history", []) as Array)
	_refresh_actions(current_view_data.get("actions", []) as Array)
	_refresh_travel_options(
		current_view_data.get("travel_options", []) as Array
	)


func get_current_view_data() -> Dictionary:
	return current_view_data.duplicate(true)


func _refresh_actions(actions: Array) -> void:
	_clear_children(action_buttons)
	action_heading.text = "此刻你能做什么　%d 项" % actions.size()
	for action_value: Variant in actions:
		var action := action_value as Dictionary
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 44)
		button.text = str(action.get("label", "采取行动"))
		button.tooltip_text = "%s：%s" % [
			str(action.get("kind", "行动")),
			str(action.get("hint", "")),
		]
		button.set_meta("action_id", str(action.get("action_id", "")))
		_apply_action_button_style(button, str(action.get("action_type", "normal")))
		button.pressed.connect(
			perform_action.bind(str(action.get("action_id", "")))
		)
		action_buttons.add_child(button)


func _refresh_travel_options(options: Array) -> void:
	_clear_children(travel_buttons)
	travel_heading.text = "可以前往　%d 处" % options.size()
	for option_value: Variant in options:
		var option := option_value as Dictionary
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 42)
		button.text = str(option.get("label", "前往新的地点"))
		button.tooltip_text = str(option.get("hint", ""))
		button.disabled = not bool(option.get("can_travel", false))
		button.set_meta("route_id", str(option.get("route_id", "")))
		_apply_action_button_style(button, "travel")
		button.pressed.connect(
			perform_travel.bind(str(option.get("route_id", "")))
		)
		travel_buttons.add_child(button)


func _refresh_feedback(feedback: Dictionary) -> void:
	feedback_title.text = str(feedback.get("title", "局面"))
	var lines: Array[String] = [str(feedback.get("body", ""))]
	var details: Array = feedback.get("details", [])
	if not details.is_empty():
		lines.append("")
		for detail: Variant in details:
			lines.append("• %s" % str(detail))
	feedback_body.text = "\n".join(lines)


func _refresh_history(history: Array) -> void:
	if history.is_empty():
		history_text.text = "还没有发生行动。"
		return
	var rows: Array[String] = []
	var first_index := maxi(history.size() - 5, 0)
	for item_value: Variant in history.slice(first_index):
		var item := item_value as Dictionary
		rows.append("%02d　%s" % [
			int(item.get("index", 0)),
			str(item.get("label", "行动")),
		])
	history_text.text = "\n".join(rows)


func _format_status_rows(rows: Array) -> String:
	var output: Array[String] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		output.append("[b]%s　%s[/b]\n[color=#9aa6a3]%s[/color]" % [
			str(row.get("label", "状态")),
			str(row.get("value", "")),
			str(row.get("detail", "")),
		])
	return "\n\n".join(output)


func _format_entity_rows(rows: Array, empty_text: String) -> String:
	if rows.is_empty():
		return empty_text
	var output: Array[String] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		var text := "[b]%s[/b]" % str(row.get("name", "未命名"))
		var state_text := str(row.get("state_text", ""))
		if state_text != "":
			text += "　[color=#d7b86e]%s[/color]" % state_text
		var description := str(row.get("description", ""))
		if description != "":
			text += "\n[color=#aeb6b3]%s[/color]" % description
		output.append(text)
	return "\n\n".join(output)


func _format_bullets(rows: Array) -> String:
	var output: Array[String] = []
	for row: Variant in rows:
		output.append("• %s" % str(row))
	return "\n\n".join(output)


func _apply_action_button_style(button: Button, action_type: String) -> void:
	var accent := Color("#a98452")
	if action_type == "dialogue":
		accent = Color("#668c91")
	elif action_type == "clue":
		accent = Color("#8a7450")
	elif action_type == "relationship":
		accent = Color("#8c6477")
	elif action_type == "travel":
		accent = Color("#6f8264")
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#222a2b")
	normal.border_color = accent
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 12.0
	var hover := normal.duplicate()
	hover.bg_color = Color("#303a3a")
	hover.border_color = accent.lightened(0.2)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("#171d1e")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color("#e9e3d5"))


func _show_load_error(message: String) -> void:
	location_title.text = "局面未能载入"
	location_context.text = ""
	location_description.text = message
	player_summary.text = ""
	region_status.text = ""
	visible_people.text = ""
	visible_observations.text = ""
	knowledge_text.text = ""
	_clear_children(travel_buttons)
	travel_heading.text = "当前没有可用路线"
	feedback_title.text = "无法开始"
	feedback_body.text = message
	history_text.text = ""
	_clear_children(action_buttons)
	action_heading.text = "此刻没有可用行动"
	time_label.text = ""


func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
