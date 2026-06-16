extends Control
class_name LakeTownWorldViewer

signal view_data_ready(data: Dictionary)

const ViewModelModel = preload(
	"res://scripts/dev/lake_town_world_view_model.gd"
)
const LegacyRunnerModel = preload(
	"res://scripts/dev/lake_town_history_variation_runner.gd"
)

var view_model := ViewModelModel.new()
var view_data: Dictionary = {}
var selected_seed_index := -1
var selected_day := 1

@onready var status_label: Label = %StatusLabel
@onready var seed_list: ItemList = %SeedList
@onready var timeline_list: ItemList = %TimelineList
@onready var day_title: Label = %DayTitle
@onready var day_detail: RichTextLabel = %DayDetail
@onready var data_tabs: TabContainer = %DataTabs
@onready var fact_text: TextEdit = %WorldFact
@onready var trace_text: TextEdit = %Trace
@onready var memory_text: TextEdit = %Memory
@onready var narratable_text: TextEdit = %NarratableState
@onready var quality_text: TextEdit = %QualityAudit
@onready var profile_text: TextEdit = %Profile
@onready var signature_text: TextEdit = %RawSignature


func _ready() -> void:
	seed_list.item_selected.connect(_on_seed_selected)
	timeline_list.item_selected.connect(_on_timeline_selected)
	data_tabs.set_tab_title(6, "Raw Signature")
	status_label.text = "正在运行湖湾镇 20 seed / 30 天本地模拟..."
	call_deferred("_load_view_data")


func _load_view_data() -> void:
	view_data = view_model.build_view_data(
		LegacyRunnerModel.DEFAULT_SEEDS,
		30
	)
	_fill_seed_list()
	if not (view_data.get("seeds", []) as Array).is_empty():
		seed_list.select(0)
		_select_seed(0)
	var totals := view_data.get("quality_totals", {}) as Dictionary
	status_label.text = (
		"完成：%d seeds；极端饥饿未闭合 %d；店铺状态矛盾 %d；重大事实悬空 %d"
		% [
			int(view_data.get("seed_count", 0)),
			int(totals.get("unresolved_extreme_hunger", 0)),
			int(totals.get("impossible_shop_state", 0)),
			int(totals.get("dangling_major_fact", 0)),
		]
	)
	view_data_ready.emit(view_data.duplicate(true))


func _fill_seed_list() -> void:
	seed_list.clear()
	for run_value: Variant in view_data.get("seeds", []):
		var run := run_value as Dictionary
		var summary := view_model.build_seed_summary(run)
		var flags := summary.get("quality_flags", []) as Array
		var quality_label := "OK" if flags.is_empty() else ", ".join(flags)
		var markers: Array[String] = []
		markers.append(
			"坏饥饿:%s"
			% _yes_no(bool(summary.get("bad_hunger_outcome", false)))
		)
		markers.append(
			"取粮:%s"
			% _yes_no(bool(summary.get("has_grain_taking", false)))
		)
		markers.append(
			"封仓:%s"
			% _yes_no(bool(summary.get("has_guard_lock", false)))
		)
		markers.append(
			"空仓:%s"
			% _yes_no(bool(summary.get("has_empty_granary", false)))
		)
		seed_list.add_item(
			"%d | %s | quality_flags:%d (%s)\n%s"
			% [
				int(summary.get("seed", 0)),
				String(summary.get("outcome_class", "")),
				int(summary.get("quality_flag_count", flags.size())),
				quality_label,
				"  ".join(markers),
			]
		)


func _on_seed_selected(index: int) -> void:
	_select_seed(index)


func _select_seed(index: int) -> void:
	var runs := view_data.get("seeds", []) as Array
	if index < 0 or index >= runs.size():
		return
	selected_seed_index = index
	var run := runs[index] as Dictionary
	var timeline := view_model.build_timeline(run)
	timeline_list.clear()
	for row_value: Variant in timeline:
		var row := row_value as Dictionary
		timeline_list.add_item(String(row.get("label", "")))
	if timeline.is_empty():
		selected_day = 1
	else:
		selected_day = int(
			(timeline[0] as Dictionary).get("day", 1)
		)
		timeline_list.select(0)
	_refresh_day_detail(run, selected_day)
	_refresh_tabs(run)


func _on_timeline_selected(index: int) -> void:
	var run := _selected_run()
	var timeline := view_model.build_timeline(run)
	if index < 0 or index >= timeline.size():
		return
	selected_day = int(
		(timeline[index] as Dictionary).get("day", 1)
	)
	_refresh_day_detail(run, selected_day)


func _refresh_day_detail(run: Dictionary, day: int) -> void:
	var detail := view_model.build_day_detail(run, day)
	day_title.text = "湖湾镇 · Day %d" % day
	var sections: Array[String] = [
		"[b]今日局面卡[/b]\n%s"
		% _format_surface_card(
			detail.get("primary_surface_card", {}) as Dictionary
		),
		"[b]人物状态卡[/b]\n%s"
		% _format_cards(detail.get("people_cards", []) as Array),
		"[b]地点状态卡[/b]\n%s"
		% _format_cards(detail.get("location_cards", []) as Array),
		"[b]可见痕迹[/b]\n%s"
		% _format_primary_list(
			detail.get("primary_surface_card", {}) as Dictionary,
			"trace_lines"
		),
		"[b]因果来源[/b]\n%s"
		% _format_primary_list(
			detail.get("primary_surface_card", {}) as Dictionary,
			"cause_lines"
		),
		"[b]当日新增 WorldFact[/b]\n%s"
		% _format_rows(detail.get("facts", []) as Array),
		"[b]当日新增 Trace[/b]\n%s"
		% _format_rows(detail.get("traces", []) as Array),
		"[b]当日新增 Memory[/b]\n%s"
		% _format_rows(detail.get("memories", []) as Array),
		"[b]当日新增 NarratableState[/b]\n%s"
		% _format_rows(
			detail.get("narratable_states", []) as Array
		),
		"[b]NPC 状态[/b]\n%s"
		% _format_snapshot(
			detail.get("npc_snapshot", {}) as Dictionary
		),
		"[b]地点状态[/b]\n%s"
		% _format_snapshot(
			detail.get("location_snapshot", {}) as Dictionary
		),
		"[b]质量标记[/b]\n%s"
		% _pretty(detail.get("quality_flags", [])),
	]
	day_detail.text = "\n\n".join(sections)


func _refresh_tabs(run: Dictionary) -> void:
	fact_text.text = _pretty(view_model.build_fact_rows(run))
	trace_text.text = _pretty(view_model.build_trace_rows(run))
	memory_text.text = _pretty(view_model.build_memory_rows(run))
	narratable_text.text = _pretty(
		view_model.build_narratable_rows(run)
	)
	quality_text.text = _pretty(
		view_model.build_quality_summary(run)
	)
	profile_text.text = _pretty(run.get("profile", {}))
	signature_text.text = _pretty(run.get("raw_signature", {}))


func _selected_run() -> Dictionary:
	var runs := view_data.get("seeds", []) as Array
	if selected_seed_index < 0 or selected_seed_index >= runs.size():
		return {}
	return runs[selected_seed_index] as Dictionary


func _format_rows(rows: Array) -> String:
	if rows.is_empty():
		return "无"
	var output: Array[String] = []
	for row_value: Variant in rows:
		output.append(_pretty(row_value))
	return "\n".join(output)


func _format_surface_card(card: Dictionary) -> String:
	if card.is_empty():
		return "今天没有足够来源生成局面卡。"
	var lines: Array[String] = [
		"[b]%s[/b]" % String(card.get("title", "")),
		"%s | %s | %s"
		% [
			String(card.get("subtitle", "")),
			String(card.get("location_name", "")),
			String(card.get("severity", "")),
		],
		String(card.get("scene_summary", "")),
	]
	lines.append(
		"可见细节：\n%s"
		% _bullet_lines(card.get("visible_details", []) as Array)
	)
	lines.append(
		"相关人物：\n%s"
		% _bullet_lines(card.get("people_present", []) as Array)
	)
	lines.append(
		"相关地点状态：\n%s"
		% _bullet_lines(
			card.get("location_state_lines", []) as Array
		)
	)
	lines.append(
		"质量标记：\n%s"
		% _bullet_lines(card.get("quality_lines", []) as Array)
	)
	lines.append(
		"来源：facts=%s traces=%s narratable=%s"
		% [
			", ".join(card.get("source_fact_ids", []) as Array),
			", ".join(card.get("trace_ids", []) as Array),
			", ".join(
				card.get("narratable_state_ids", []) as Array
			),
		]
	)
	return "\n".join(lines)


func _format_cards(cards: Array) -> String:
	if cards.is_empty():
		return "无"
	var output: Array[String] = []
	for card_value: Variant in cards:
		var card := card_value as Dictionary
		output.append(
			"[b]%s[/b]\n%s"
			% [
				String(card.get("title", "")),
				String(card.get("summary", "")),
			]
		)
	return "\n\n".join(output)


func _format_primary_list(card: Dictionary, key: String) -> String:
	if card.is_empty():
		return "无"
	return _bullet_lines(card.get(key, []) as Array)


func _bullet_lines(rows: Array) -> String:
	if rows.is_empty():
		return "- 无"
	var output: Array[String] = []
	for row_value: Variant in rows:
		output.append("- %s" % String(row_value))
	return "\n".join(output)


func _format_snapshot(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return "无"
	var output: Array[String] = []
	for id_value: Variant in snapshot:
		output.append(
			"%s: %s"
			% [String(id_value), _pretty(snapshot[id_value])]
		)
	return "\n".join(output)


func _pretty(value: Variant) -> String:
	return JSON.stringify(value, "\t", false)


func _yes_no(value: bool) -> String:
	return "是" if value else "否"
