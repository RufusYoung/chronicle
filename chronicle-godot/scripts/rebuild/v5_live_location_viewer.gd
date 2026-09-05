extends Control
class_name V5LiveLocationViewer

const ViewModelModel = preload(
	"res://scripts/rebuild/v5_live_location_view_model.gd"
)
const SharedInterfaceStyle = preload(
	"res://scripts/rebuild/v5_shared_interface_style.gd"
)
const SharedSurface = preload("res://scripts/rebuild/v5_shared_world_surface.gd")

var view_model: Variant = null
var current_view_data: Dictionary = {}
var _playtest_end_state := ""
var surface: Dictionary = {}

@onready var location_title: Label = %LocationTitle
@onready var location_context: Label = %LocationContext
@onready var location_description: RichTextLabel = %LocationDescription
@onready var player_summary: RichTextLabel = %PlayerSummary
@onready var goal_progress: Label = %GoalProgress
@onready var goal_title: Label = %GoalTitle
@onready var goal_summary: RichTextLabel = %GoalSummary
@onready var region_status: RichTextLabel = %RegionStatus
@onready var visible_people: RichTextLabel = %VisiblePeople
@onready var visible_observations: RichTextLabel = %VisibleObservations
@onready var knowledge_heading: Label = %KnowledgeHeading
@onready var knowledge_text: RichTextLabel = %KnowledgeText
@onready var chronicle_heading: Label = %ChronicleHeading
@onready var chronicle_text: RichTextLabel = %ChronicleText
@onready var risk_heading: Label = %RiskHeading
@onready var risk_text: RichTextLabel = %RiskText
@onready var travel_heading: Label = %TravelHeading
@onready var travel_scroll: ScrollContainer = %TravelScroll
@onready var travel_buttons: VBoxContainer = %TravelButtons
@onready var feedback_title: Label = %FeedbackTitle
@onready var feedback_eyebrow: Label = %FeedbackEyebrow
@onready var feedback_body: RichTextLabel = %FeedbackBody
@onready var history_text: RichTextLabel = %HistoryText
@onready var action_heading: Label = %ActionHeading
@onready var action_hint: Label = %ActionHint
@onready var investigation_bar: RichTextLabel = %InvestigationBar
@onready var action_buttons: FlowContainer = %ActionButtons
@onready var action_dock: PanelContainer = %ActionDock
@onready var time_label: Label = %TimeLabel
@onready var session_label: Label = %SessionLabel
@onready var brand_subtitle: Label = %BrandSubtitle
@onready var wait_button: Button = %WaitButton
@onready var restart_button: Button = %RestartButton
@onready var intro_dialog: AcceptDialog = %IntroDialog
@onready var completion_dialog: AcceptDialog = %CompletionDialog
@onready var failure_dialog: AcceptDialog = %FailureDialog
@onready var restart_dialog: ConfirmationDialog = %RestartDialog


func _ready() -> void:
	view_model = ViewModelModel.new()
	surface = SharedSurface.install(self, $Margin/RootLayout,
		$Margin/RootLayout/MainArea, action_dock, {
		"header": {
			"brand": [brand_subtitle.get_parent().get_node("BrandTitle"), brand_subtitle],
			"clock": [time_label, session_label], "commands": [wait_button, restart_button],
		},
		"scene": [location_title, location_context, location_description],
		"feedback": [feedback_eyebrow, feedback_title, feedback_body],
		"people": [visible_people.get_parent().get_node("PeopleHeading"), visible_people],
		"observations": [visible_observations.get_parent().get_node("ObservationHeading"), visible_observations],
		"decision": [goal_title, risk_heading, risk_text, travel_heading, travel_scroll],
		"character": [[player_summary.get_parent().get_node("PlayerHeading"), player_summary]],
		"records": [goal_progress, goal_summary, region_status.get_parent().get_node("RegionHeading"), region_status,
			knowledge_heading, knowledge_text, chronicle_heading, chronicle_text,
			history_text.get_parent().get_node("HistoryHeading"), history_text],
	})
	location_title.add_theme_font_size_override("font_size", SharedInterfaceStyle.FONT_TITLE)
	wait_button.pressed.connect(advance_time)
	restart_button.pressed.connect(_request_restart)
	restart_dialog.confirmed.connect(restart_session)
	completion_dialog.confirmed.connect(_enter_seventh_outpost)
	restart_session()


func restart_session() -> void:
	_playtest_end_state = ""
	completion_dialog.hide()
	failure_dialog.hide()
	restart_dialog.hide()
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


func perform_challenge(option_id: String) -> Dictionary:
	var result: Dictionary = view_model.perform_challenge(option_id)
	refresh_view()
	return result


func perform_combat_encounter(
		option_id: String,
		metadata: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = view_model.perform_combat_encounter(
		option_id, metadata
	)
	refresh_view()
	return result


func perform_return_echo(option_id: String) -> Dictionary:
	var result: Dictionary = view_model.perform_return_echo(option_id)
	refresh_view()
	return result


func perform_investigation(option_id: String) -> Dictionary:
	var result: Dictionary = view_model.perform_investigation(option_id)
	refresh_view()
	return result


func advance_time() -> Dictionary:
	var result: Dictionary = view_model.advance_time(1)
	refresh_view()
	return result


func wait_until_north_quay_ferry() -> Dictionary:
	var result: Dictionary = view_model.wait_until_north_quay_ferry()
	refresh_view()
	return result


func refresh_view(projected: Dictionary = {}) -> void:
	current_view_data = projected if not projected.is_empty() else view_model.build_view_data()
	if not bool(current_view_data.get("ready", false)):
		_show_load_error(str(current_view_data.get("error_text", "局面暂时无法载入。")))
		return

	var location: Dictionary = current_view_data.get("location", {})
	location_title.text = str(location.get("title", "未知地点"))
	location_context.text = str(location.get("context", ""))
	location_context.hide()
	location_description.text = str(location.get("description", ""))
	var playtest: Dictionary = current_view_data.get("playtest", {})
	match str(playtest.get("mode", "")):
		"generated_settlement_network":
			brand_subtitle.text = "生成区域现场 / INTERNAL PLAYTEST"
		"generated_settlement":
			brand_subtitle.text = "生成聚落现场 / INTERNAL PLAYTEST"
		_:
			brand_subtitle.text = "湖湾镇垂直切片 / INTERNAL PLAYTEST"
	_refresh_playtest(playtest)

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
		"这里没有值得留意的人。", true
	)
	visible_observations.text = _format_entity_rows(
		current_view_data.get("visible_observations", []) as Array,
		"眼前没有明显的物件或痕迹。", true
	)
	(surface["scene_record"] as RichTextLabel).text = "%s\n%s\n\n[b]在场的人[/b]\n%s\n\n[b]进入视线的东西[/b]\n%s" % [
		location_title.text + " · " + location_context.text, location_description.text,
		_format_entity_rows(current_view_data.get("visible_people", []), "此处无人"),
		_format_entity_rows(current_view_data.get("visible_observations", []), "没有明显痕迹"),
	]
	knowledge_heading.text = "已经确认的事"
	knowledge_text.text = _format_bullets(current_view_data.get("knowledge", []))
	(surface["situation"] as RichTextLabel).text = "[b]随身[/b] 食物 %d · 健康 %d · 疲劳 %d/10\n%s" % [
		player.get("food_count", 0), player.get("health", 100), player.get("fatigue", 0),
		_format_decision_context(
		current_view_data.get("decision", {}) as Dictionary,
		current_view_data.get("agency", {}) as Dictionary
	)]
	_refresh_chronicle(
		current_view_data.get("chronicle", {}) as Dictionary
	)
	_refresh_investigation(
		current_view_data.get("investigation", {}) as Dictionary
	)
	_refresh_risk(current_view_data.get("risk", {}) as Dictionary)
	_refresh_feedback(current_view_data.get("feedback", {}) as Dictionary)
	_refresh_history(current_view_data.get("history", []) as Array)
	_refresh_actions(
		current_view_data.get("actions", []) as Array,
		current_view_data.get("decision", {}) as Dictionary
	)
	_refresh_travel_options(
		current_view_data.get("travel_options", []) as Array
	)


func get_current_view_data() -> Dictionary:
	return current_view_data.duplicate(true)


func _refresh_playtest(playtest: Dictionary) -> void:
	var stage := int(playtest.get("stage", 1))
	var stage_count := int(playtest.get("stage_count", 5))
	var completed := bool(playtest.get("completed", false))
	var failed := bool(playtest.get("failed", false))
	var accent_color := Color("#d1b76f")
	var title_color := Color("#ead9ad")
	var end_state := ""
	if completed:
		goal_progress.text = "内部试玩　已完成"
		session_label.text = "● 试玩完成"
		accent_color = Color("#8db08e")
		title_color = Color("#b9d2b5")
		end_state = "completed"
	elif failed:
		goal_progress.text = "内部试玩　本次受挫"
		session_label.text = "● 试玩受挫"
		accent_color = Color("#c78a6b")
		title_color = Color("#e1b29b")
		end_state = "failed"
	else:
		goal_progress.text = "内部试玩　目标 %d / %d" % [
			stage,
			stage_count,
		]
		session_label.text = "● 试玩进行中"
	goal_title.text = str(playtest.get("title", "当前目标"))
	goal_summary.text = str(playtest.get("summary", ""))
	goal_progress.add_theme_color_override(
		"font_color",
		accent_color
	)
	goal_title.add_theme_color_override(
		"font_color",
		title_color
	)
	if end_state != "" and end_state != _playtest_end_state:
		call_deferred("_show_playtest_end", end_state)
	_playtest_end_state = end_state


func _request_restart() -> void:
	restart_dialog.popup_centered_clamped(Vector2i(640, 210), 0.9)
	restart_dialog.get_cancel_button().grab_focus()


func _show_playtest_end(end_state: String) -> void:
	if end_state != _playtest_end_state:
		return
	if end_state == "completed":
		completion_dialog.popup_centered_clamped(Vector2i(760, 230), 0.9)
	elif end_state == "failed":
		failure_dialog.popup_centered_clamped(Vector2i(760, 230), 0.9)


func _enter_seventh_outpost() -> void:
	var transition: Dictionary = view_model.build_life_stage_transition()
	if transition.is_empty():
		return
	var relay: Node = get_node_or_null("/root/_LifeStageTransition")
	if relay == null:
		return
	relay.store_transition(transition)
	get_tree().change_scene_to_file(
		"res://scenes/rebuild/v5_seventh_outpost_viewer.tscn"
	)


func _refresh_actions(actions: Array, decision: Dictionary = {}) -> void:
	_clear_children(action_buttons)
	var executable_count := 0
	for action_value: Variant in actions:
		var action := action_value as Dictionary
		if bool(action.get("can_execute", true)):
			executable_count += 1
	var blocked_count := actions.size() - executable_count
	var combat_active := (
		not actions.is_empty()
		and str((actions[0] as Dictionary).get("event_type", ""))
			== "combat_encounter"
	)
	wait_button.disabled = combat_active
	wait_button.tooltip_text = (
		"先处理眼前的遭遇，不能用等待跳过。"
		if combat_active
		else "让世界时间推进一小时。"
	)
	action_heading.text = str(decision.get(
		"question",
		"眼前的遭遇，选一种处理方式。"
		if combat_active
		else "你愿意先把时间用在哪里？"
	))
	action_heading.text += "　%d 项可选" % executable_count
	if blocked_count > 0:
		action_heading.text += "　·　受限 %d 项" % blocked_count
	action_hint.text = str(decision.get(
		"rule",
		"只结算一个选择；行动期间，其他人物和局势不会暂停。"
	)) if not actions.is_empty() else (
		"这里暂时没有可执行的现场行动。比较当前局势和可前往地点。"
	)
	action_dock.custom_minimum_size.y = 0
	for action_value: Variant in actions:
		var action := action_value as Dictionary
		var button := Button.new()
		button.custom_minimum_size = Vector2(SharedSurface.action_width(self, actions.size()), 86)
		var kind := str(action.get("kind", "行动"))
		var hint := str(action.get("hint", ""))
		var cost := str(action.get("cost", "花费 1 小时"))
		var known_effect := str(action.get(
			"known_effect", "让当前人物与局面产生一次结算"
		))
		var tradeoff := str(action.get(
			"tradeoff", "这段时间里，世界仍会继续运行"
		))
		var caption := str(action.get("label", "采取行动"))
		if str(action.get("event_type", "")) == "challenge":
			caption = caption.trim_suffix("%d小时" % int(action.get("hours", 1))).strip_edges()
		button.text = "%s　[%s]\n%s\n取舍：%s" % [
			caption,
			cost,
			known_effect,
			tradeoff,
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", SharedInterfaceStyle.FONT_ACTION)
		button.tooltip_text = "%s：%s\n花费：%s\n取舍：%s" % [
			kind,
			hint,
			cost,
			tradeoff,
		]
		button.mouse_entered.connect(_show_action_hint.bind(kind, hint))
		button.focus_entered.connect(_show_action_hint.bind(kind, hint))
		button.mouse_exited.connect(_restore_action_hint)
		button.disabled = not bool(action.get("can_execute", true))
		button.set_meta("action_id", str(action.get("action_id", "")))
		_apply_action_button_style(button, str(action.get("action_type", "normal")))
		match str(action.get("event_type", "player_action")):
			"ferry_wait":
				button.pressed.connect(wait_until_north_quay_ferry)
			"challenge":
				button.set_meta(
					"challenge_option_id",
					str(action.get("challenge_option_id", ""))
				)
				button.pressed.connect(
					perform_challenge.bind(
						str(action.get("challenge_option_id", ""))
					)
				)
			"combat_encounter":
				button.set_meta(
					"combat_option_id",
					str(action.get("combat_option_id", ""))
				)
				button.pressed.connect(
					perform_combat_encounter.bind(
						str(action.get("combat_option_id", ""))
					)
				)
			"return_echo":
				button.set_meta(
					"return_echo_option_id",
					str(action.get("return_echo_option_id", ""))
				)
				button.pressed.connect(
					perform_return_echo.bind(
						str(action.get("return_echo_option_id", ""))
					)
				)
			"investigation":
				button.set_meta(
					"investigation_option_id",
					str(action.get("investigation_option_id", ""))
				)
				button.pressed.connect(
					perform_investigation.bind(
						str(action.get("investigation_option_id", ""))
					)
				)
			_:
				button.pressed.connect(
					perform_action.bind(
						str(action.get("action_id", ""))
					)
				)
		action_buttons.add_child(button)
	SharedSurface.paginate_actions(surface, self, action_buttons)


func _show_action_hint(kind: String, hint: String) -> void:
	action_hint.text = "%s　%s" % [kind, hint]


func _restore_action_hint() -> void:
	var decision: Dictionary = current_view_data.get("decision", {})
	action_hint.text = str(decision.get(
		"rule", "行动期间，其他人物和世界局势不会暂停。"
	))


func _refresh_investigation(investigation: Dictionary) -> void:
	var active := bool(investigation.get("active", false))
	action_hint.visible = true
	investigation_bar.visible = false
	if not active:
		investigation_bar.text = ""
		return
	goal_title.text = "可追查：%s" % str(investigation.get("title", ""))
	goal_summary.text = "%s\n%s" % [
		str(investigation.get("status", "")), str(investigation.get("summary", ""))]
	investigation_bar.text = "[color=#d6b66e][b]调查方向　%s[/b][/color]　%s\n[color=#8f9c98]%s[/color]" % [
		str(investigation.get("title", "")),
		str(investigation.get("status", "")),
		str(investigation.get("summary", "")),
	]


func _refresh_chronicle(chronicle: Dictionary) -> void:
	var active := bool(chronicle.get("active", false))
	chronicle_heading.visible = active
	chronicle_text.visible = active
	if not active:
		chronicle_text.text = ""
		return
	chronicle_heading.text = "个人纪事　%s" % str(
		chronicle.get("title", "")
	)
	chronicle_text.text = "%s\n\n[color=#8f9c98]依据 %d 条事实、%d 件物品[/color]" % [
		str(chronicle.get("body", "")),
		int(chronicle.get("source_fact_count", 0)),
		int(chronicle.get("source_item_count", 0)),
	]


func _refresh_risk(risk: Dictionary) -> void:
	var active := bool(risk.get("active", false))
	goal_progress.visible = not active
	goal_title.visible = not active
	goal_summary.visible = not active
	risk_heading.visible = active
	risk_text.visible = active
	_refresh_right_panel_density()
	if not active:
		risk_text.text = ""
		return
	risk_heading.text = str(risk.get("title", "眼前的风险"))
	risk_text.text = "[color=#d1b76f]%s[/color]\n%s\n[color=#b8a8a0]%s[/color]" % [
		str(risk.get("check_text", "")), str(risk.get("preparation_text", "")),
		str(risk.get("failure_hint", "")),
	]
	var evidence := str(risk.get("decision_evidence", ""))
	if evidence != "":
		risk_text.text = evidence + "\n" + risk_text.text
	(surface["scene_record"] as RichTextLabel).text += "\n\n[b]风险依据[/b]\n%s\n%s" % [
		str(risk.get("description", "")), risk_text.text,
	]


func _refresh_right_panel_density() -> void:
	chronicle_text.custom_minimum_size.y = 0
	risk_text.custom_minimum_size.y = 0
	history_text.custom_minimum_size.y = 0


func _refresh_travel_options(options: Array) -> void:
	_clear_children(travel_buttons)
	travel_heading.text = "可以前往　%d 处" % options.size()
	travel_scroll.custom_minimum_size.y = 0
	travel_heading.visible = not options.is_empty()
	travel_scroll.visible = not options.is_empty()
	for option_value: Variant in options:
		var option := option_value as Dictionary
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 44)
		button.text = str(option.get("label", "前往新的地点"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = "%s\n取舍：%s" % [
			str(option.get("hint", "")),
			str(option.get("tradeoff", "路上世界照常变化")),
		]
		button.disabled = not bool(option.get("can_travel", false))
		button.set_meta("route_id", str(option.get("route_id", "")))
		_apply_action_button_style(button, "travel")
		button.pressed.connect(
			perform_travel.bind(str(option.get("route_id", "")))
		)
		travel_buttons.add_child(button)
	SharedSurface.paginate_travel(surface, self, travel_buttons)


func _refresh_feedback(feedback: Dictionary) -> void:
	feedback_eyebrow.text = str(feedback.get("eyebrow", "当前局势"))
	feedback_title.text = str(feedback.get("title", "局面"))
	SharedSurface.update_receipt(surface, feedback)
	feedback_body.text = SharedSurface.compact_feedback(feedback, 2)


func _refresh_history(history: Array) -> void:
	if history.is_empty():
		history_text.custom_minimum_size.y = 48
		history_text.text = "还没有发生行动。"
		return
	var rows: Array[String] = []
	var first_index := 0
	for item_value: Variant in history.slice(first_index):
		var item := item_value as Dictionary
		var narrative := str(item.get("narrative", ""))
		if narrative == "":
			narrative = "局面已经更新。"
		var cause_label := (
			"你的选择"
			if str(item.get("cause_kind", "player")) == "player"
			else "世界自行发生"
		)
		rows.append("[color=#718b84]%s[/color]　[b]%02d　%s[/b]\n[color=#8f9c98]%s[/color]" % [
			cause_label,
			int(item.get("index", 0)),
			str(item.get("label", "行动")),
			narrative,
		])
		var impact: Dictionary = item.get("impact", {})
		if not impact.is_empty():
			rows.append("行动结算：%s" % "；".join(impact.get("details", [])))
			if str(impact.get("world_summary", "")) != "":
				rows.append("同期世界变化：%s" % impact.get("world_summary", ""))
	history_text.text = "\n\n".join(rows)


func _format_status_rows(rows: Array) -> String:
	var output: Array[String] = []
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		output.append("[b]%s　%s[/b]　[color=#9aa6a3]%s[/color]" % [
			str(row.get("label", "状态")),
			str(row.get("value", "")),
			str(row.get("detail", "")).replace("\n", " "),
		])
	return "\n".join(output)


func _format_entity_rows(rows: Array, empty_text: String, compact: bool = false) -> String:
	if rows.is_empty():
		return empty_text
	var output: Array[String] = []
	var display_rows: Array = []
	if compact:
		for priority: int in 3:
			for row: Dictionary in rows:
				if int(row.get("surface_priority", 0)) == priority:
					display_rows.append(row)
		display_rows = display_rows.slice(0, 4)
	else:
		display_rows = rows
	for row_value: Variant in display_rows:
		var row := row_value as Dictionary
		var text := "[b]%s[/b]" % str(row.get("name", "未命名"))
		var state_text := str(row.get("state_text", ""))
		if state_text != "":
			text += "　[color=#d7b86e]%s[/color]" % state_text
		var description := str(row.get("description", ""))
		if description != "" and not compact:
			text += "　[color=#aeb6b3]%s[/color]" % description
		output.append(text)
	if compact and rows.size() > 4:
		output.append("[color=#8f9c98]另有 %d 项现场信息，完整内容见「记录」。[/color]" % (rows.size() - 4))
	return "\n".join(output)


func _format_bullets(rows: Array) -> String:
	var output: Array[String] = []
	for row: Variant in rows:
		output.append("• %s" % str(row))
	return "\n".join(output)


func _format_decision_context(
		decision: Dictionary,
		agency: Dictionary
) -> String:
	var rows: Array[String] = []
	var stakes: Array = decision.get("stakes", [])
	if not stakes.is_empty():
		rows.append("[color=#d1b76f][b]眼前要紧[/b][/color]　%s" % (
			"；".join(stakes)
		))
	var world_summary := str(agency.get("world_summary", ""))
	if world_summary != "":
		var first_event := world_summary.split(" | ")[0]
		rows.append("[b]%s[/b] %s" % [
			"世界自行发生" if str(agency.get("world_kind", "")) == "independent" else "行动期间",
			first_event,
		])
	return "\n".join(rows)


func _apply_action_button_style(button: Button, action_type: String) -> void:
	SharedInterfaceStyle.apply_decision_button(button, action_type)


func _show_load_error(message: String) -> void:
	location_title.text = "局面未能载入"
	location_context.text = ""
	location_description.text = message
	player_summary.text = ""
	goal_progress.text = "内部试玩　载入失败"
	goal_title.text = "当前无法开始"
	goal_summary.text = message
	session_label.text = "● 需要检查"
	region_status.text = ""
	visible_people.text = ""
	visible_observations.text = ""
	knowledge_text.text = ""
	chronicle_heading.visible = false
	chronicle_text.visible = false
	investigation_bar.visible = false
	risk_heading.visible = false
	risk_text.visible = false
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
