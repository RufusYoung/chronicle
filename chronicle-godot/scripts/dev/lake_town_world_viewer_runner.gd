extends SceneTree

const VIEWER_SCENE := (
	"res://scenes/dev/lake_town_world_viewer.tscn"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	if packed == null:
		push_error("[LAKE TOWN WORLD VIEWER RUNNER] scene load failed")
		quit(1)
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await viewer.view_data_ready
	var seed_list := viewer.get_node("%SeedList") as ItemList
	var timeline_list := viewer.get_node("%TimelineList") as ItemList
	var day_detail := viewer.get_node("%DayDetail") as RichTextLabel
	var data_tabs := viewer.get_node("%DataTabs") as TabContainer
	var passed := (
		seed_list.item_count == 20
		and timeline_list.item_count > 0
		and "今日局面卡" in day_detail.text
		and "人物状态卡" in day_detail.text
		and "地点状态卡" in day_detail.text
		and data_tabs.get_tab_count() == 7
	)
	if passed:
		print("[LAKE TOWN WORLD VIEWER RUNNER RESULT] PASS")
		viewer.queue_free()
		quit(0)
	else:
		push_error(
			"[LAKE TOWN WORLD VIEWER RUNNER RESULT] FAIL "
			+ "seeds=%d timeline=%d detail=%d tabs=%d"
			% [
				seed_list.item_count,
				timeline_list.item_count,
				day_detail.text.length(),
				data_tabs.get_tab_count(),
			]
		)
		viewer.queue_free()
		quit(1)
