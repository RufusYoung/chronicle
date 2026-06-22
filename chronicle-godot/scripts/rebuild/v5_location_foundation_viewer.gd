extends Control
class_name V5LocationFoundationViewer

const StateModel = preload(
	"res://scripts/rebuild/v5_location_foundation_state.gd"
)
const ViewModelModel = preload(
	"res://scripts/rebuild/v5_location_foundation_view_model.gd"
)

var state: Variant
var view_model: Variant

@onready var inventory_button: Button = %InventoryButton
@onready var character_button: Button = %CharacterButton
@onready var world_button: Button = %WorldButton
@onready var life_button: Button = %LifeButton
@onready var settings_button: Button = %SettingsButton
@onready var character_summary: RichTextLabel = %CharacterSummary
@onready var scene_title: Label = %SceneTitle
@onready var scene_text: RichTextLabel = %SceneText
@onready var visible_people: Label = %VisiblePeople
@onready var visible_traces: Label = %VisibleTraces
@onready var child_location_buttons: FlowContainer = %ChildLocationButtons
@onready var region_status: RichTextLabel = %RegionStatus
@onready var clue_buttons: VBoxContainer = %ClueButtons
@onready var location_buttons: FlowContainer = %LocationButtons
@onready var action_buttons: FlowContainer = %ActionButtons
@onready var history_text: Label = %HistoryText


func _ready() -> void:
	state = StateModel.new()
	view_model = ViewModelModel.new()
	view_model.bind_state(state)
	_connect_top_buttons()
	refresh_view()


func refresh_view() -> void:
	_refresh_character()
	_refresh_location_scene()
	_refresh_region_status()
	_refresh_clues()
	_refresh_locations()
	_refresh_actions()
	_refresh_history()


func perform_action(action_id: String) -> void:
	state.apply_action(action_id)
	refresh_view()


func open_location(location_id: String) -> void:
	state.set_current_location(location_id)
	refresh_view()


func open_clue_card(clue_id: String) -> void:
	var card: Dictionary = view_model.get_clue_action_card(clue_id)
	if card.is_empty():
		return
	scene_title.text = str(card.get("title", "线索"))
	var lines: Array[String] = [
		"[b]%s[/b]" % str(card.get("title", "")),
		"",
		"[b]来源：[/b]",
		str(card.get("source", "")),
		"",
		"[b]可信度：[/b]",
		str(card.get("credibility", "")),
		"",
		"[b]关联地点：[/b]",
		str(card.get("location", "")),
		"",
		"[b]可行动：[/b]",
		_bullet_lines(card.get("actions", []) as Array),
		"",
		"[b]是否可加入追寻：[/b]",
		str(card.get("pursuit_text", "否")),
	]
	scene_text.text = "\n".join(lines)
	visible_people.text = "可见人物：无"
	visible_traces.text = "可见痕迹：线索行动卡"


func open_life_panel() -> void:
	var summary: Dictionary = view_model.get_life_panel_summary()
	scene_title.text = "生涯"
	scene_text.text = "\n".join([
		"[b]生涯[/b]",
		"",
		"[b]可开始的人生方向：[/b]",
		_bullet_lines(summary.get("available_directions", []) as Array),
		"",
		"[b]听说过但尚未开启：[/b]",
		_bullet_lines(summary.get("heard_but_locked", []) as Array),
		"",
		"[b]已完成经历：[/b]",
		_bullet_lines(summary.get("completed_experiences", []) as Array),
		"",
		"[b]纪事：[/b]",
		_bullet_lines(summary.get("chronicle", []) as Array),
	])
	visible_people.text = "可见人物：无"
	visible_traces.text = "可见痕迹：生涯面板占位"


func open_character_panel() -> void:
	var summary: Dictionary = view_model.get_character_summary()
	scene_title.text = "角色详情"
	scene_text.text = str(summary.get("summary_text", ""))
	visible_people.text = "可见人物：阿尔维斯"
	visible_traces.text = "可见痕迹：角色状态摘要"


func _connect_top_buttons() -> void:
	inventory_button.pressed.connect(_show_placeholder.bind("背包系统尚未接入。"))
	character_button.pressed.connect(open_character_panel)
	world_button.pressed.connect(_show_placeholder.bind("世界地图尚未接入。"))
	life_button.pressed.connect(open_life_panel)
	settings_button.pressed.connect(_show_placeholder.bind("设置尚未接入。"))


func _show_placeholder(message: String) -> void:
	scene_title.text = "尚未接入"
	scene_text.text = message
	visible_people.text = "可见人物：无"
	visible_traces.text = "可见痕迹：入口占位"


func _refresh_character() -> void:
	var summary: Dictionary = view_model.get_character_summary()
	character_summary.text = str(summary.get("summary_text", ""))


func _refresh_location_scene() -> void:
	var scene: Dictionary = view_model.get_location_scene()
	scene_title.text = str(scene.get("title", ""))
	scene_text.text = str(scene.get("text", ""))
	visible_people.text = "可见人物：%s" % _inline_list(
		scene.get("visible_people", []) as Array
	)
	visible_traces.text = "可见痕迹：%s" % _inline_list(
		scene.get("visible_traces", []) as Array
	)
	_clear_children(child_location_buttons)
	for node_value: Variant in scene.get("child_nodes", []):
		var node := node_value as Dictionary
		var button := Button.new()
		button.text = str(node.get("name", ""))
		button.pressed.connect(open_location.bind(str(node.get("id", ""))))
		child_location_buttons.add_child(button)


func _refresh_region_status() -> void:
	var lines: Array[String] = []
	for status_value: Variant in view_model.get_region_status():
		var status := status_value as Dictionary
		lines.append("[b]%s：%s。[/b]\n%s" % [
			str(status.get("label", "")),
			str(status.get("state", "")),
			str(status.get("detail", "")),
		])
	region_status.text = "\n\n".join(lines)


func _refresh_clues() -> void:
	_clear_children(clue_buttons)
	var groups: Array = view_model.get_clues_by_location()
	if groups.is_empty():
		var empty := Label.new()
		empty.text = "暂无已获得线索"
		clue_buttons.add_child(empty)
		return
	for group_value: Variant in groups:
		var group := group_value as Dictionary
		var heading := Label.new()
		heading.text = str(group.get("location", "湖湾镇"))
		clue_buttons.add_child(heading)
		for clue_value: Variant in group.get("clues", []):
			var clue := clue_value as Dictionary
			var button := Button.new()
			button.text = str(clue.get("label", ""))
			button.pressed.connect(open_clue_card.bind(str(clue.get("id", ""))))
			clue_buttons.add_child(button)


func _refresh_locations() -> void:
	_clear_children(location_buttons)
	for node_value: Variant in view_model.get_location_nodes():
		var node := node_value as Dictionary
		var button := Button.new()
		button.text = str(node.get("name", ""))
		if bool(node.get("is_current", false)):
			button.text = "• " + button.text
		button.pressed.connect(open_location.bind(str(node.get("id", ""))))
		location_buttons.add_child(button)


func _refresh_actions() -> void:
	_clear_children(action_buttons)
	for action_value: Variant in view_model.get_action_options():
		var action := action_value as Dictionary
		var button := Button.new()
		button.text = str(action.get("button_text", ""))
		button.pressed.connect(perform_action.bind(str(action.get("id", ""))))
		action_buttons.add_child(button)


func _refresh_history() -> void:
	var history: Array = state.get_action_history()
	if history.is_empty():
		history_text.text = "行动历史：暂无"
		return
	var labels: Array[String] = []
	for item_value: Variant in history.slice(maxi(history.size() - 4, 0)):
		var item := item_value as Dictionary
		labels.append(
			"#%d %s"
			% [
				int(item.get("index", 0)),
				str(item.get("action_label", "")),
			]
		)
	history_text.text = "行动历史：" + " / ".join(labels)


func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _inline_list(values: Array) -> String:
	if values.is_empty():
		return "无"
	var output: Array[String] = []
	for value: Variant in values:
		output.append(str(value))
	return "、".join(output)


func _bullet_lines(values: Array) -> String:
	if values.is_empty():
		return "- 暂无"
	var output: Array[String] = []
	for value: Variant in values:
		output.append("- %s" % str(value))
	return "\n".join(output)
