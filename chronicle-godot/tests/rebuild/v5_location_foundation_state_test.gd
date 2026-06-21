extends SceneTree

const StateModel = preload(
	"res://scripts/rebuild/v5_location_foundation_state.gd"
)
const ViewModelModel = preload(
	"res://scripts/rebuild/v5_location_foundation_view_model.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := StateModel.new()
	var view_model := ViewModelModel.new()
	view_model.bind_state(state)
	_check(
		not state.get_character().is_empty()
		and state.get_character().get("name", "") == "阿尔维斯",
		"1. 初始状态存在角色状态"
	)
	_check(
		state.get_current_location_id() == "lake_town"
		and "湖湾镇" in view_model.get_location_scene().get("title", ""),
		"2. 初始状态存在湖湾镇地点"
	)
	_check(
		not state.get_region_statuses().is_empty()
		and JSON.stringify(view_model.get_region_status()).find("粮食") >= 0,
		"3. 初始状态存在地区状态"
	)

	state.apply_action("approach_chen_mi")
	_check(
		"陈米" in JSON.stringify(view_model.get_location_scene())
		and state.get_action_history().size() == 1,
		"4. 执行 approach_chen_mi 后出现陈米相关叙述"
	)

	state = StateModel.new()
	view_model = ViewModelModel.new()
	view_model.bind_state(state)
	state.apply_action("inspect_price_notice")
	_check(
		state.has_clue("price_rise_tomorrow"),
		"5. 执行 inspect_price_notice 后获得粮价线索"
	)
	_check(
		JSON.stringify(view_model.get_clues_by_location()).find("粮价明天再涨一次") >= 0,
		"6. 获得线索后线索列表能显示"
	)
	_check(
		_clue_card_is_complete(
			view_model.get_clue_action_card("price_rise_tomorrow")
		),
		"7. 点击线索能生成线索行动卡数据"
	)
	_check(
		_life_summary_has_direction(view_model.get_life_panel_summary(), "漂泊"),
		"8. 生涯面板 summary 至少返回可开始方向"
	)
	state.apply_action("ask_market_grain_price")
	_check(
		state.has_clue("north_caravan_late")
		and JSON.stringify(view_model.get_region_status()).find("北路商队迟了三天") >= 0,
		"9. 市场打听会更新粮食状态并新增北路商队线索"
	)
	state.apply_action("stay_one_month")
	_check(
		JSON.stringify(view_model.get_life_panel_summary()).find("在湖湾镇停留一月") >= 0,
		"10. 长期停留会写入已完成经历"
	)

	if failures.is_empty():
		print("[V5 LOCATION FOUNDATION RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 LOCATION FOUNDATION FAIL] " + failure)
		print("[V5 LOCATION FOUNDATION RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _clue_card_is_complete(card: Dictionary) -> bool:
	return (
		not card.is_empty()
		and "粮价明天再涨一次" in str(card.get("title", ""))
		and str(card.get("source", "")) != ""
		and str(card.get("credibility", "")) != ""
		and str(card.get("location", "")) != ""
		and not (card.get("actions", []) as Array).is_empty()
		and str(card.get("pursuit_text", "")) == "否"
	)


func _life_summary_has_direction(summary: Dictionary, direction: String) -> bool:
	return direction in (summary.get("available_directions", []) as Array)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 LOCATION FOUNDATION PASS] " + message)
	else:
		failures.append(message)
