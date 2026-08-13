extends Control
class_name V5SeventhOutpostViewer

const ViewModelModel = preload(
	"res://scripts/rebuild/v5_seventh_outpost_view_model.gd"
)

var view_model: Variant = null
var current_view_data: Dictionary = {}
var completion_was_shown: bool = false
var pending_growth_candidate_id: String = ""

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
	restart_button.pressed.connect(restart_project)
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


func perform_duty(duty_id: String) -> Dictionary:
	var result: Dictionary = view_model.perform_duty(duty_id)
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


func refresh_view() -> void:
	current_view_data = view_model.build_view_data()
	if not bool(current_view_data.get("ready", false)):
		return
	subtitle.text = str(current_view_data.get("subtitle", ""))
	var day := int(current_view_data.get("day", 1))
	var duration := int(current_view_data.get("duration_days", 7))
	day_label.text = (
		"第一轮值勤已结束"
		if bool(current_view_data.get("complete", false))
		else "第 %d / %d 天　06:00　清晨点名" % [day, duration]
	)
	var player: Dictionary = current_view_data.get("player", {})
	player_text.text = str(player.get("summary", ""))
	feature_text.text = str(player.get("features", ""))
	objective_text.text = (
		"[b]第一冬目标[/b]\n完成七个值勤日。每天只选一项职责；口粮、疲劳、军纪与身边人的行动都会继续结算。"
	)
	var ritual: Dictionary = current_view_data.get("ritual", {})
	ritual_title.text = str(ritual.get("title", "清晨点名"))
	ritual_body.text = str(ritual.get("body", ""))
	people_text.text = _format_people(current_view_data.get("people", []))
	status_text.text = _format_status(
		current_view_data.get("status", {}) as Dictionary
	)
	_refresh_market(current_view_data.get("market", {}) as Dictionary)
	_refresh_feedback(current_view_data.get("feedback", {}) as Dictionary)
	_refresh_history(current_view_data.get("history", []))
	if bool(current_view_data.get("complete", false)):
		_refresh_growth_actions(
			(current_view_data.get("completion", {}) as Dictionary).get(
				"growth_candidates", []
			)
		)
	else:
		_refresh_actions(current_view_data.get("actions", []))
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
		child.queue_free()
	var executable := 0
	var blocked := 0
	for action: Dictionary in actions:
		if bool(action.get("can_execute", true)):
			executable += 1
		else:
			blocked += 1
	action_heading.text = "今日职责　可承担 %d 项" % executable
	if blocked > 0:
		action_heading.text += "　·　受限 %d 项" % blocked
	action_hint.text = (
		"每项职责已直接列出条件、消耗与影响；选择后推进到次日点名。"
		if not actions.is_empty()
		else "第一轮值勤已经结束，查看右侧小结。"
	)
	for action: Dictionary in actions:
		var button := Button.new()
		button.custom_minimum_size = Vector2(300, 88)
		button.text = "%s\n%s" % [
			str(action.get("label", "承担值勤")),
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


func _refresh_growth_actions(candidates: Array) -> void:
	for child: Node in action_buttons.get_children():
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
		action_hint.text = "这项成长已经写入角色、事实与纪事，不能重复领取。"
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
	button.tooltip_text = str(offer.get("quote_summary", ""))
	button.pressed.connect(purchase_market_offer.bind(
		str(offer.get("item_instance_id", "")),
		int(offer.get("unit_price", 0))
	))
	market_buttons.add_child(button)


func _refresh_feedback(feedback: Dictionary) -> void:
	feedback_title.text = str(feedback.get("title", "值勤结果"))
	var lines: Array[String] = [str(feedback.get("body", ""))]
	for detail: Variant in feedback.get("details", []):
		lines.append("\n• %s" % str(detail))
	feedback_body.text = "".join(lines)


func _refresh_history(history: Array) -> void:
	if history.is_empty():
		history_text.text = "还没有完成值勤。"
		return
	var rows: Array[String] = []
	var first := maxi(history.size() - 4, 0)
	for entry: Dictionary in history.slice(first):
		rows.append("[b]第 %d 天　%s[/b]\n[color=#9aa29d]%s[/color]" % [
			int(entry.get("day", 0)),
			str(entry.get("label", "值勤")),
			str(entry.get("summary", "")),
		])
	history_text.text = "\n\n".join(rows)
	call_deferred("_scroll_history_to_latest")


func _format_people(people: Array) -> String:
	var rows: Array[String] = []
	for person: Dictionary in people:
		var relation := ""
		if int(person.get("relation_value", 0)) > 0:
			relation = "　[color=#cbb06a]%s %d[/color]" % [
				str(person.get("relation_label", "关系")),
				int(person.get("relation_value", 0)),
			]
		rows.append("[b]%s[/b]%s\n%s" % [
			str(person.get("name", "")),
			relation,
			str(person.get("description", "")),
		])
	return "\n\n".join(rows)


func _format_status(status: Dictionary) -> String:
	var rows: Array[String] = []
	for row: Dictionary in status.get("rows", []):
		var color := "#d0b468" if bool(row.get("warning", false)) else "#b8c0b8"
		rows.append("[color=%s][b]%s　%d / 12[/b][/color]" % [
			color,
			str(row.get("label", "状态")),
			int(row.get("value", 0)),
		])
	return "\n".join(rows)


func _show_intro() -> void:
	intro_dialog.popup_centered_clamped(Vector2i(760, 300), 0.9)


func _show_completion() -> void:
	var completion: Dictionary = current_view_data.get("completion", {})
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
	completion_dialog.dialog_text = "\n".join(lines)
	completion_dialog.popup_centered_clamped(Vector2i(820, 520), 0.9)


func _scroll_history_to_latest() -> void:
	history_text.scroll_to_line(maxi(history_text.get_line_count() - 1, 0))
