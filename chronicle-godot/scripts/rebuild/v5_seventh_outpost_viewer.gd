extends Control
class_name V5SeventhOutpostViewer

const ViewModelModel = preload(
	"res://scripts/rebuild/v5_seventh_outpost_view_model.gd"
)
const SharedSurface = preload("res://scripts/rebuild/v5_shared_world_surface.gd")

var view_model: Variant = null
var current_view_data: Dictionary = {}
var completion_was_shown: bool = false
var pending_growth_candidate_id: String = ""
var surface: Dictionary = {}
var restart_dialog: ConfirmationDialog

@onready var subtitle: Label = %Subtitle
@onready var day_label: Label = %DayLabel
@onready var player_text: RichTextLabel = %PlayerText
@onready var feature_text: RichTextLabel = %FeatureText
@onready var objective_text: RichTextLabel = %ObjectiveText
@onready var market_text: RichTextLabel = %MarketText
@onready var market_buttons: VBoxContainer = %MarketButtons
@onready var ritual_title: Label = %RitualTitle
@onready var ritual_body: RichTextLabel = %RitualBody
@onready var people_text: RichTextLabel = %PeopleText
@onready var status_text: RichTextLabel = %StatusText
@onready var feedback_title: Label = %FeedbackTitle
@onready var feedback_body: RichTextLabel = %FeedbackBody
@onready var feedback_eyebrow: Label = $Margin/Root/Main/Center/Content/Feedback/Box/Eyebrow
@onready var history_text: RichTextLabel = %HistoryText
@onready var action_heading: Label = %ActionHeading
@onready var action_hint: Label = %ActionHint
@onready var action_buttons: FlowContainer = %ActionButtons
@onready var restart_button: Button = %RestartButton
@onready var intro_dialog: AcceptDialog = %IntroDialog
@onready var completion_dialog: AcceptDialog = %CompletionDialog
@onready var growth_confirmation_dialog: ConfirmationDialog = %GrowthConfirmationDialog


func _ready() -> void:
	view_model = ViewModelModel.new()
	surface = SharedSurface.install(self, $Margin/Root, $Margin/Root/Main,
		$Margin/Root/Dock, {
		"header": {
			"brand": [subtitle.get_parent().get_node("Title"), subtitle],
			"clock": [day_label], "commands": [restart_button],
		},
		"scene": [ritual_title, ritual_body],
		"feedback": [feedback_eyebrow, feedback_title, feedback_body],
		"people": [people_text.get_parent().get_node("PeopleHeading"), people_text],
		"decision": [status_text.get_parent().get_node("StatusHeading"), status_text],
		"supplies": [market_text.get_parent().get_node("MarketHeading"), market_text, market_buttons],
		"character": [
			[player_text.get_parent().get_node("PlayerHeading"), player_text,
			feature_text.get_parent().get_node("FeatureHeading"), feature_text],
		],
		"records": [objective_text, history_text.get_parent().get_node("HistoryHeading"), history_text],
	})
	var place := Label.new()
	place.name = "OutpostLocationTitle"
	place.text = "第七哨站"
	place.add_theme_font_size_override("font_size", SharedSurface.Style.FONT_TITLE)
	place.add_theme_color_override("font_color", SharedSurface.Style.COLOR_HEADING)
	ritual_title.get_parent().add_child(place)
	ritual_title.get_parent().move_child(place, 0)
	restart_dialog = ConfirmationDialog.new()
	restart_dialog.name = "RestartDialog"
	restart_dialog.title = "重新开始当前阶段？"
	restart_dialog.dialog_text = "本阶段的未保存行动和成长将被清空。\n已有磁盘存档不会被删除或覆盖。"
	restart_dialog.get_ok_button().text = "重新开始"
	restart_dialog.get_cancel_button().text = "取消"
	add_child(restart_dialog)
	restart_dialog.owner = self
	restart_dialog.unique_name_in_owner = true
	restart_dialog.confirmed.connect(_restart_current_phase)
	$Margin/Root/Dock.custom_minimum_size.y = 0
	$Margin/Root/Header.custom_minimum_size.y = 58
	feedback_body.bbcode_enabled = true
	action_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	restart_button.pressed.connect(_request_restart)
	growth_confirmation_dialog.confirmed.connect(_confirm_pending_growth)
	var transition: Dictionary = {}
	var relay: Node = get_node_or_null("/root/_LifeStageTransition")
	if relay != null:
		transition = relay.consume_transition()
	restart_project(transition)


func restart_project(transition: Dictionary = {}) -> void:
	completion_was_shown = false
	pending_growth_candidate_id = ""
	completion_dialog.hide()
	growth_confirmation_dialog.hide()
	view_model.start(transition)
	refresh_view()


func _restart_current_phase() -> void:
	restart_dialog.hide()
	completion_was_shown = false
	pending_growth_candidate_id = ""
	completion_dialog.hide()
	growth_confirmation_dialog.hide()
	view_model.restart_current_phase()
	refresh_view()


func _request_restart() -> void:
	restart_dialog.popup_centered_clamped(Vector2i(640, 210), 0.9)
	restart_dialog.get_cancel_button().grab_focus()


func enter_first_quarter() -> Dictionary:
	completion_was_shown = false
	pending_growth_candidate_id = ""
	completion_dialog.hide()
	growth_confirmation_dialog.hide()
	var result: Dictionary = view_model.enter_first_quarter()
	refresh_view()
	return result


func enter_first_year_close() -> Dictionary:
	completion_was_shown = false
	completion_dialog.hide()
	var result: Dictionary = view_model.enter_first_year_close()
	refresh_view()
	return result


func enter_second_year_reception() -> Dictionary:
	completion_was_shown = false
	completion_dialog.hide()
	var result: Dictionary = view_model.enter_second_year_reception()
	refresh_view()
	return result


func perform_duty(
		duty_id: String, options: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = view_model.perform_duty(duty_id, options)
	refresh_view()
	return result


func resolve_life_incident(response_id: String) -> Dictionary:
	var result: Dictionary = view_model.resolve_life_incident(response_id)
	refresh_view()
	return result


func purchase_market_offer(
		item_instance_id: String,
		quoted_unit_price: int
) -> Dictionary:
	var result: Dictionary = view_model.purchase_market_offer(
		item_instance_id, quoted_unit_price
	)
	refresh_view()
	return result


func confirm_growth_candidate(candidate_id: String) -> Dictionary:
	var result: Dictionary = view_model.confirm_growth_candidate(candidate_id)
	refresh_view()
	return result


func resolve_milestone() -> Dictionary:
	var result: Dictionary = view_model.resolve_milestone()
	refresh_view()
	return result


func refresh_view() -> void:
	current_view_data = view_model.build_view_data()
	if not bool(current_view_data.get("ready", false)):
		return
	subtitle.text = str(current_view_data.get("subtitle", ""))
	var day := int(current_view_data.get("day", 1))
	var duration := int(current_view_data.get("duration_days", 7))
	var unit_label := str(current_view_data.get("progress_unit_label", "天"))
	var calendar_days := int(current_view_data.get("calendar_days_per_step", 1))
	var phase_id := str(current_view_data.get("phase_id", "first_winter"))
	var incident: Dictionary = current_view_data.get("incident", {})
	if bool(incident.get("active", false)):
		day_label.text = "第 %d %s结算后 · 世界第 %d 天" % [
			int(incident.get("trigger_day", day)),
			unit_label,
			int(current_view_data.get("world_day", 1)),
		]
	elif bool(current_view_data.get("complete", false)):
		if phase_id == "second_year_reception":
			day_label.text = "第二年接收已完成 · 世界第 %d 天" % int(
				current_view_data.get("world_day", 1)
			)
		elif phase_id == "first_year_close":
			day_label.text = "第一年已结束 · 世界第 %d 天" % int(
				current_view_data.get("world_day", 1)
			)
		elif phase_id == "first_quarter":
			day_label.text = "第一季度已结束 · 世界第 %d 天" % int(
				current_view_data.get("world_day", 1)
			)
		else:
			day_label.text = "第一轮值勤已结束"
	elif phase_id == "first_quarter":
		day_label.text = "第 %d / %d %s · 每轮 %d 天 · 世界第 %d 天" % [
			day,
			duration,
			unit_label,
			calendar_days,
			int(current_view_data.get("world_day", 1)),
		]
	elif phase_id == "first_year_close":
		day_label.text = "第 %d / %d 月 · 本月 %d 天 · 世界第 %d 天" % [
			day,
			duration,
			calendar_days,
			int(current_view_data.get("world_day", 1)),
		]
	elif phase_id == "second_year_reception":
		day_label.text = "第 %d / %d 周 · 本周 %d 天 · 世界第 %d 天" % [
			day,
			duration,
			calendar_days,
			int(current_view_data.get("world_day", 1)),
		]
	else:
		day_label.text = "第 %d / %d 天　06:00　清晨点名" % [day, duration]
	var player: Dictionary = current_view_data.get("player", {})
	player_text.text = str(player.get("summary", ""))
	feature_text.text = str(player.get("features", ""))
	objective_text.text = str(current_view_data.get("objective", ""))
	var decision: Dictionary = current_view_data.get("decision", {})
	var market: Dictionary = current_view_data.get("market", {})
	(surface["situation"] as RichTextLabel).text = "[b]随身[/b] 口粮 %d · 铜币 %d · 疲劳 %d/10\n%s" % [
		market.get("ration_count", 0), market.get("coin_count", 0), player.get("fatigue", 0),
		"；".join(decision.get("stakes", [])),
	]
	match phase_id:
		"first_quarter":
			restart_button.text = "重来第一季度"
		"first_year_close":
			restart_button.text = "重来年度轮转"
		"second_year_reception":
			restart_button.text = "重来第二年接收"
		_:
			restart_button.text = "重新开始服役"
	var ritual: Dictionary = current_view_data.get("ritual", {})
	ritual_title.text = str(ritual.get("title", "清晨点名"))
	ritual_body.text = str(ritual.get("body", ""))
	people_text.text = _format_people(current_view_data.get("people", []))
	var person_records: Array[String] = [ritual_body.text]
	for person: Dictionary in current_view_data.get("people", []):
		person_records.append("[b]%s[/b] %s\n%s" % [
			person.get("name", ""), person.get("description", ""), person.get("state_summary", ""),
		])
	(surface["scene_record"] as RichTextLabel).text = "\n\n".join(person_records)
	status_text.text = _format_status(
		current_view_data.get("status", {}) as Dictionary
	)
	_refresh_market(current_view_data.get("market", {}) as Dictionary)
	_refresh_feedback(current_view_data.get("feedback", {}) as Dictionary)
	_refresh_history(current_view_data.get("history", []))
	if bool(incident.get("active", false)):
		_refresh_life_incident(incident)
	elif bool(current_view_data.get("complete", false)):
		var growth_candidates: Array = (
			current_view_data.get("completion", {}) as Dictionary
		).get("growth_candidates", [])
		if phase_id == "first_quarter":
			_refresh_quarter_completion_actions()
		elif phase_id == "first_year_close":
			_refresh_milestone_actions((
				current_view_data.get("completion", {}) as Dictionary
			).get("milestone", {}))
		elif phase_id == "second_year_reception":
			_refresh_second_year_completion_actions()
		else:
			_refresh_growth_actions(growth_candidates)
	else:
		_refresh_actions(current_view_data.get("actions", []))
	var live_buttons: Array[Node] = []
	for child: Node in action_buttons.get_children():
		if child is Button and not child.is_queued_for_deletion():
			live_buttons.append(child)
	for button: Button in live_buttons:
		button.custom_minimum_size = Vector2(SharedSurface.action_width(self, live_buttons.size()), 82)
		SharedSurface.style_action(button, "life")
	SharedSurface.paginate_actions(surface, self, action_buttons)
	if (
		bool(current_view_data.get("complete", false))
		and not completion_was_shown
	):
		completion_was_shown = true
		call_deferred("_show_completion")


func get_current_view_data() -> Dictionary:
	return current_view_data.duplicate(true)


func _refresh_actions(actions: Array) -> void:
	for child: Node in action_buttons.get_children():
		action_buttons.remove_child(child)
		child.queue_free()
	var executable := 0
	var blocked := 0
	for action: Dictionary in actions:
		if bool(action.get("can_execute", true)):
			executable += 1
		else:
			blocked += 1
	var decision: Dictionary = current_view_data.get("decision", {})
	action_heading.text = str(decision.get("question", "今日职责"))
	if blocked > 0:
		action_heading.text += "　·　受限 %d 项" % blocked
	action_hint.text = (
		str(decision.get("rule", "每项职责直接列出条件、消耗与影响。"))
		if not actions.is_empty()
		else "第一轮值勤已经结束，查看右侧小结。"
	)
	for action: Dictionary in actions:
		var button := Button.new()
		button.custom_minimum_size = Vector2(
			270 if actions.size() <= 4 else 300,
			88
		)
		button.text = "%s　[%s]\n%s" % [
			str(action.get("label", "承担值勤")),
			str(action.get("cost", "推进 1 天")),
			str(action.get("hint", "")),
		]
		button.disabled = not bool(action.get("can_execute", true))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = "%s：%s" % [
			str(action.get("kind", "值勤")),
			str(action.get("hint", "")),
		]
		button.set_meta("duty_id", str(action.get("duty_id", "")))
		button.pressed.connect(perform_duty.bind(
			str(action.get("duty_id", ""))
		))
		action_buttons.add_child(button)


func _refresh_life_incident(incident: Dictionary) -> void:
	for child: Node in action_buttons.get_children():
		action_buttons.remove_child(child)
		child.queue_free()
	action_heading.text = "途中插曲 · %s" % str(
		incident.get("title", "一件小事")
	)
	action_hint.text = "%s\n%s" % [
		str(incident.get("body", "")),
		str(incident.get(
			"trigger_reason", "它来自刚刚结算后的地点与人物状态。"
		)),
	]
	for response: Dictionary in incident.get("responses", []):
		var button := Button.new()
		button.custom_minimum_size = Vector2(300, 76)
		var hint := str(response.get("hint", ""))
		if not bool(response.get("can_execute", true)):
			hint = str(response.get("blocked_reason", "当前不能这样回应"))
		button.text = "%s\n%s" % [
			str(response.get("label", "回应")), hint
		]
		button.disabled = not bool(response.get("can_execute", true))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.set_meta("incident_response_id", str(
			response.get("response_id", "")
		))
		button.pressed.connect(resolve_life_incident.bind(str(
			response.get("response_id", "")
		)))
		action_buttons.add_child(button)


func _refresh_growth_actions(candidates: Array) -> void:
	for child: Node in action_buttons.get_children():
		action_buttons.remove_child(child)
		child.queue_free()
	var confirmed: Dictionary = {}
	for candidate: Dictionary in candidates:
		if bool(candidate.get("confirmed", false)):
			confirmed = candidate
			break
	if not confirmed.is_empty():
		action_heading.text = "阶段成长已确认　%s" % str(
			confirmed.get("title", "阶段成长")
		)
		action_hint.text = "这项成长已经写入角色、事实与纪事。现在可以让它进入下一段生活。"
		if bool(current_view_data.get("can_advance_phase", false)):
			var next_button := Button.new()
			next_button.custom_minimum_size = Vector2(300, 72)
			next_button.text = "进入第一季度\n六个双周节点 · 推进 84 天"
			next_button.set_meta("phase_transition_id", "first_quarter")
			next_button.pressed.connect(enter_first_quarter)
			action_buttons.add_child(next_button)
		return
	action_heading.text = "从实际经历中确认一项成长　%d 项可选" % candidates.size()
	action_hint.text = "成长会永久写入本次存档。点击选项查看依据和奖励，再进行确认。"
	for candidate: Dictionary in candidates:
		var preview: Dictionary = candidate.get("reward_preview", {})
		var button := Button.new()
		button.custom_minimum_size = Vector2(300, 88)
		button.text = "%s\n%s　·　%s %d 次" % [
			str(candidate.get("title", "阶段成长")),
			str(preview.get("summary", "查看成长奖励")),
			str(candidate.get("evidence_label", "经历")),
			int(candidate.get("evidence_count", 0)),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.set_meta("candidate_id", str(candidate.get("candidate_id", "")))
		button.pressed.connect(_request_growth_confirmation.bind(candidate))
		action_buttons.add_child(button)


func _refresh_quarter_completion_actions() -> void:
	for child: Node in action_buttons.get_children():
		action_buttons.remove_child(child)
		child.queue_free()
	action_heading.text = "第一季度已经结束"
	action_hint.text = "八十四天的状态、人物变化、物品履历与纪事已经写入。现在可以进入第一年余下九个月。"
	if bool(current_view_data.get("can_advance_phase", false)):
		var next_button := Button.new()
		next_button.custom_minimum_size = Vector2(320, 72)
		next_button.text = "进入年度轮转\n九个月度节点 · 推进 273 天"
		next_button.set_meta("phase_transition_id", "first_year_close")
		next_button.pressed.connect(enter_first_year_close)
		action_buttons.add_child(next_button)


func _refresh_milestone_actions(milestone: Dictionary) -> void:
	for child: Node in action_buttons.get_children():
		action_buttons.remove_child(child)
		child.queue_free()
	var outcomes: Array = milestone.get("outcomes", [])
	if bool(milestone.get("resolved", false)):
		action_heading.text = str(milestone.get(
			"resolved_title", "第一年的变化已经写入世界"
		))
		action_hint.text = "年末变化已写入人物状态、关系、事实与个人纪事；第二年会读取这些结果，而不是重新选择一条剧情。"
		if bool(current_view_data.get("can_advance_phase", false)):
			var next_button := Button.new()
			next_button.custom_minimum_size = Vector2(340, 76)
			next_button.text = "进入第二年接收\n三个周节点 · 检验跨年因果"
			next_button.set_meta(
				"phase_transition_id", "second_year_reception"
			)
			next_button.pressed.connect(enter_second_year_reception)
			action_buttons.add_child(next_button)
		return
	action_heading.text = "年末点名 · %d 项变化满足条件" % outcomes.size()
	var lines: Array[String] = [str(milestone.get("intro", ""))]
	for outcome: Dictionary in outcomes:
		lines.append("%s：%s %d / %d" % [
			str(outcome.get("title", "年度变化")),
			str(outcome.get("evidence_label", "经历")),
			int(outcome.get("evidence_count", 0)),
			int(outcome.get("minimum_fact_count", 1)),
		])
	action_hint.text = "\n".join(lines)
	if outcomes.is_empty():
		return
	var button := Button.new()
	button.custom_minimum_size = Vector2(320, 72)
	button.text = "%s\n把满足阈值的变化写入第一年纪事" % str(
		milestone.get("action_label", "完成年末点名")
	)
	button.set_meta("milestone_action", "resolve")
	button.pressed.connect(resolve_milestone)
	action_buttons.add_child(button)


func _refresh_second_year_completion_actions() -> void:
	for child: Node in action_buttons.get_children():
		action_buttons.remove_child(child)
		child.queue_free()
	action_heading.text = "第二年接收已经完成"
	action_hint.text = "跨年职责、仪式和 NPC 自主行为已经由第一年事实改写。年度手写扩展到此停止，下一开发阶段转入人物生成合同。"


func _request_growth_confirmation(candidate: Dictionary) -> void:
	pending_growth_candidate_id = str(candidate.get("candidate_id", ""))
	var preview: Dictionary = candidate.get("reward_preview", {})
	growth_confirmation_dialog.title = "确认阶段成长 · %s" % str(
		candidate.get("title", "阶段成长")
	)
	growth_confirmation_dialog.dialog_text = "%s\n\n经历依据：%s，共 %d 次\n奖励：%s\n\n确认后不能在本阶段改选。" % [
		str(candidate.get("description", "")),
		str(candidate.get("evidence_label", "经历事实")),
		int(candidate.get("evidence_count", 0)),
		str(preview.get("summary", "成长奖励")),
	]
	growth_confirmation_dialog.popup_centered_clamped(Vector2i(660, 320), 0.9)
	call_deferred("_focus_growth_cancel")


func _focus_growth_cancel() -> void:
	if growth_confirmation_dialog.visible:
		growth_confirmation_dialog.get_cancel_button().grab_focus()


func _confirm_pending_growth() -> void:
	if pending_growth_candidate_id == "":
		return
	var candidate_id := pending_growth_candidate_id
	pending_growth_candidate_id = ""
	confirm_growth_candidate(candidate_id)


func _refresh_market(market: Dictionary) -> void:
	for child: Node in market_buttons.get_children():
		market_buttons.remove_child(child)
		child.queue_free()
	var offers: Array = market.get("offers", [])
	var lines := [
		"[b]随身[/b]　口粮 %d　铜币 %d" % [
			int(market.get("ration_count", 0)),
			int(market.get("coin_count", 0)),
		]
	]
	if offers.is_empty():
		lines.append("玛塔今天没有可出售的口粮。")
		market_text.text = "\n".join(lines)
		return
	var offer: Dictionary = offers[0]
	lines.append("[b]%s[/b]　库存 %d" % [
		str(offer.get("display_name", "口粮")),
		int(offer.get("available_quantity", 0)),
	])
	lines.append(str(offer.get("quote_summary", "")))
	market_text.text = "\n".join(lines)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 38)
	button.text = "购买 1 份 · %d 铜币" % int(offer.get("unit_price", 0))
	button.disabled = not bool(offer.get("can_purchase", false))
	button.tooltip_text = str(offer.get(
		"blocked_reason", offer.get("quote_summary", "")
	))
	button.pressed.connect(purchase_market_offer.bind(
		str(offer.get("item_instance_id", "")),
		int(offer.get("unit_price", 0))
	))
	SharedSurface.Style.apply_command_button(button)
	market_buttons.add_child(button)


func _refresh_feedback(feedback: Dictionary) -> void:
	feedback_eyebrow.text = str(feedback.get("eyebrow", "当前局势"))
	feedback_title.text = str(feedback.get("title", "值勤结果"))
	SharedSurface.update_receipt(surface, feedback)
	feedback_body.text = SharedSurface.compact_feedback(feedback, 1)


func _refresh_history(history: Array) -> void:
	if history.is_empty():
		history_text.text = "还没有完成值勤。"
		return
	var rows: Array[String] = []
	var first := 0
	for entry: Dictionary in history.slice(first):
		var unit_label := str(entry.get("progress_unit_label", "天"))
		var calendar_text := ""
		if int(entry.get("calendar_day_end", 0)) > 0:
			calendar_text = "\n[color=#7f918c]世界日 %d–%d[/color]" % [
				int(entry.get("calendar_day_start", 0)),
				int(entry.get("calendar_day_end", 0)),
			]
		rows.append("[color=#8db08e]你的职责[/color]　[b]第 %d %s　%s[/b]%s\n[color=#9aa29d]%s[/color]" % [
			int(entry.get("day", 0)),
			unit_label,
			str(entry.get("label", "值勤")),
			calendar_text,
			str(entry.get("summary", "")),
		])
		for narrative: Variant in entry.get("npc_narratives", []):
			rows.append("同袍随后：%s" % str(narrative))
		for note: Variant in entry.get("settlement_notes", []):
			rows.append("日常结算：%s" % str(note))
	history_text.text = "\n\n".join(rows)


func _format_people(people: Array) -> String:
	var rows: Array[String] = []
	for person: Dictionary in people:
		var relation := ""
		if int(person.get("relation_value", 0)) > 0:
			relation = "　[color=#cbb06a]%s %d[/color]" % [
				str(person.get("relation_label", "关系")),
				int(person.get("relation_value", 0)),
			]
		rows.append("[b]%s[/b]%s　[color=#8fa09b]%s[/color]" % [
			str(person.get("name", "")),
			relation,
			str(person.get("state_summary", "")),
		])
	var lines: Array[String] = []
	for index: int in range(0, rows.size(), 2):
		lines.append("　　".join(rows.slice(index, index + 2)))
	return "\n".join(lines)


func _format_status(status: Dictionary) -> String:
	var rows: Array[String] = []
	for row: Dictionary in status.get("rows", []):
		var color := "#d0b468" if bool(row.get("warning", false)) else "#b8c0b8"
		rows.append("[color=%s][b]%s　%d / 12[/b][/color]" % [
			color,
			str(row.get("label", "状态")),
			int(row.get("value", 0)),
		])
	var lines: Array[String] = []
	for index: int in range(0, rows.size(), 2):
		lines.append("　".join(rows.slice(index, index + 2)))
	return "\n".join(lines)


func _show_intro() -> void:
	intro_dialog.popup_centered_clamped(Vector2i(760, 300), 0.9)


func _show_completion() -> void:
	var completion: Dictionary = current_view_data.get("completion", {})
	completion_dialog.title = str(completion.get("title", "阶段小结"))
	var lines: Array[String] = [str(completion.get("intro", ""))]
	for line: Variant in completion.get("lines", []):
		lines.append("• %s" % str(line))
	var candidates: Array = completion.get("growth_candidates", [])
	if not candidates.is_empty():
		lines.append("\n阶段成长候选（关闭小结后在底部确认一项）")
	for candidate: Dictionary in candidates:
		var preview: Dictionary = candidate.get("reward_preview", {})
		lines.append("• %s（%s %d 次）\n  %s\n  奖励：%s" % [
			str(candidate.get("title", "阶段成长")),
			str(candidate.get("evidence_label", "经历")),
			int(candidate.get("evidence_count", 0)),
			str(candidate.get("description", "")),
			str(preview.get("summary", "成长奖励")),
		])
	var milestone: Dictionary = completion.get("milestone", {})
	if bool(milestone.get("active", false)):
		lines.append("\n年末长期变化（关闭小结后在底部结算）")
		for outcome: Dictionary in milestone.get("outcomes", []):
			lines.append("• %s（%s %d / %d）\n  %s" % [
				str(outcome.get("title", "年度变化")),
				str(outcome.get("evidence_label", "经历")),
				int(outcome.get("evidence_count", 0)),
				int(outcome.get("minimum_fact_count", 1)),
				str(outcome.get("text", "")),
			])
	completion_dialog.dialog_text = "\n".join(lines)
	completion_dialog.popup_centered_clamped(Vector2i(820, 520), 0.9)
