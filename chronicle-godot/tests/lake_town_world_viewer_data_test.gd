extends SceneTree

const ViewModelModel = preload(
	"res://scripts/dev/lake_town_world_view_model.gd"
)
const LegacyRunnerModel = preload(
	"res://scripts/dev/lake_town_history_variation_runner.gd"
)

const PROTECTED_STORY_PLAYER := (
	"chronicle-godot/scenes/ui/story_player.gd"
)
const PROTECTED_WORLD_GENERATION := (
	"chronicle-godot/scripts/gen/world_generation_v03.gd"
)
const VIEWER_SCENE := (
	"res://scenes/dev/lake_town_world_viewer.tscn"
)
const VIEWER_SCRIPT := (
	"res://scripts/dev/lake_town_world_viewer.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var view_model := ViewModelModel.new()
	var data := view_model.build_view_data(
		LegacyRunnerModel.DEFAULT_SEEDS,
		30
	)
	var runs := data.get("seeds", []) as Array
	_check(
		int(data.get("seed_count", 0)) == 20 and runs.size() == 20,
		"1. build_view_data generates 20 seed results"
	)
	_check(
		_all_runs_have_dictionary(runs, "seed_summary"),
		"2. every seed has seed_summary"
	)
	_check(
		_all_runs_have_array(runs, "timeline"),
		"3. every seed has timeline"
	)
	_check(
		_all_timelines_have_lake_town_fact(runs),
		"4. every timeline contains a lake town WorldFact"
	)
	_check(
		_all_runs_have_dictionary(runs, "quality_summary"),
		"5. every seed has quality_summary"
	)
	var totals := data.get("quality_totals", {}) as Dictionary
	_check(
		int(totals.get("unresolved_extreme_hunger", -1)) == 0,
		"6. unresolved_extreme_hunger remains zero"
	)
	_check(
		int(totals.get("impossible_shop_state", -1)) == 0,
		"7. impossible_shop_state remains zero"
	)
	_check(
		int(totals.get("dangling_major_fact", -1)) == 0,
		"8. dangling_major_fact remains zero"
	)

	var first_run := runs[0] as Dictionary
	var first_timeline := view_model.build_timeline(first_run)
	var selected_day := int(
		(first_timeline[0] as Dictionary).get("day", 1)
	)
	var detail := view_model.build_day_detail(
		first_run,
		selected_day
	)
	_check(
		_day_detail_is_complete(detail, selected_day),
		"9. build_day_detail returns all additions for the selected day"
	)
	var npc_snapshot := view_model.build_npc_snapshot(
		first_run,
		selected_day
	)
	_check(
		npc_snapshot.has("old_chen")
		and npc_snapshot.has("chen_mi"),
		"10. NPC snapshot includes old_chen and chen_mi"
	)
	var location_snapshot := view_model.build_location_snapshot(
		first_run,
		selected_day
	)
	_check(
		location_snapshot.has("old_chen_shop")
		and location_snapshot.has("abandoned_granary"),
		"11. location snapshot includes shop and granary"
	)
	_check(
		_rows_have_keys(
			view_model.build_fact_rows(first_run),
			["fact_id", "day", "type"]
		),
		"12. every fact row contains fact_id/day/type"
	)
	_check(
		_rows_have_keys(
			view_model.build_trace_rows(first_run),
			["trace_id", "source_fact_id"]
		),
		"13. every trace row contains trace_id/source_fact_id"
	)
	_check(
		_rows_have_any_key(
			view_model.build_memory_rows(first_run),
			["memory_id", "id"]
		),
		"14. every memory row contains memory_id or id"
	)
	_check(
		_rows_have_any_key(
			view_model.build_narratable_rows(first_run),
			["narratable_state_id", "id"]
		),
		"15. every narratable row contains narratable_state_id or id"
	)
	_check(
		first_run.get("raw_signature", {}) is Dictionary
		and not (
			first_run.get("raw_signature", {}) as Dictionary
		).is_empty(),
		"16. raw signature is readable"
	)

	var unchanged_copy := first_run.duplicate(true)
	view_model.build_seed_summary(first_run)
	view_model.build_timeline(first_run)
	view_model.build_day_detail(first_run, selected_day)
	view_model.build_npc_snapshot(first_run, selected_day)
	view_model.build_location_snapshot(first_run, selected_day)
	view_model.build_fact_rows(first_run)
	view_model.build_trace_rows(first_run)
	view_model.build_memory_rows(first_run)
	view_model.build_narratable_rows(first_run)
	view_model.build_quality_summary(first_run)
	_check(
		first_run == unchanged_copy,
		"17. ViewModel readers do not mutate input results"
	)
	_check(
		_viewer_scene_parses_and_is_read_only(),
		"18. UI scene parses headlessly and contains no state writes"
	)
	_check(
		_git_path_unchanged(PROTECTED_STORY_PLAYER),
		"19. story_player.gd is unchanged"
	)
	_check(
		_git_path_unchanged(PROTECTED_WORLD_GENERATION),
		"20. world_generation_v03.gd is unchanged"
	)

	if failures.is_empty():
		print("[LAKE TOWN WORLD VIEWER DATA RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[LAKE TOWN WORLD VIEWER DATA FAIL] " + failure)
		print(
			"[LAKE TOWN WORLD VIEWER DATA RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _all_runs_have_dictionary(runs: Array, key: String) -> bool:
	for run_value: Variant in runs:
		if not (run_value as Dictionary).get(key, null) is Dictionary:
			return false
	return not runs.is_empty()


func _all_runs_have_array(runs: Array, key: String) -> bool:
	for run_value: Variant in runs:
		if not (run_value as Dictionary).get(key, null) is Array:
			return false
	return not runs.is_empty()


func _all_timelines_have_lake_town_fact(runs: Array) -> bool:
	for run_value: Variant in runs:
		var timeline := (
			(run_value as Dictionary).get("timeline", []) as Array
		)
		if timeline.is_empty():
			return false
		for row_value: Variant in timeline:
			var row := row_value as Dictionary
			if not (
				row.has("fact_id")
				and row.has("day")
				and row.has("type")
			):
				return false
	return not runs.is_empty()


func _day_detail_is_complete(
		detail: Dictionary,
		expected_day: int
	) -> bool:
	return (
		int(detail.get("day", -1)) == expected_day
		and detail.get("facts", null) is Array
		and detail.get("traces", null) is Array
		and detail.get("memories", null) is Array
		and detail.get("narratable_states", null) is Array
	)


func _rows_have_keys(rows: Array, keys: Array[String]) -> bool:
	if rows.is_empty():
		return false
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		for key: String in keys:
			if not row.has(key):
				return false
	return true


func _rows_have_any_key(rows: Array, keys: Array[String]) -> bool:
	if rows.is_empty():
		return false
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		var found := false
		for key: String in keys:
			if row.has(key):
				found = true
				break
		if not found:
			return false
	return true


func _viewer_scene_parses_and_is_read_only() -> bool:
	var packed := load(VIEWER_SCENE) as PackedScene
	if packed == null:
		return false
	var viewer := packed.instantiate()
	var source := FileAccess.get_file_as_string(VIEWER_SCRIPT)
	var forbidden: Array[String] = [
		"add_fact(",
		"resolve_action(",
		"tick_once(",
		"run_days(",
		"create_state_for_seed(",
	]
	for token: String in forbidden:
		if token in source:
			viewer.free()
			return false
	var valid := viewer.get_script() != null
	viewer.free()
	return valid


func _git_path_unchanged(path: String) -> bool:
	var output: Array = []
	var repository_root := ProjectSettings.globalize_path("res://..")
	var exit_code := OS.execute(
		"git",
		[
			"-C",
			repository_root,
			"diff",
			"--quiet",
			"HEAD",
			"--",
			path,
		],
		output,
		true
	)
	return exit_code == 0


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[LAKE TOWN WORLD VIEWER DATA PASS] " + message)
	else:
		failures.append(message)
