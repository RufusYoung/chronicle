extends SceneTree

const ViewModelModel = preload(
	"res://scripts/dev/lake_town_world_view_model.gd"
)
const BuilderModel = preload(
	"res://scripts/dev/lake_town_living_surface_builder.gd"
)
const TemplatesModel = preload(
	"res://scripts/dev/lake_town_living_surface_templates.gd"
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
	var builder := BuilderModel.new()
	var templates := TemplatesModel.new()
	var data := view_model.build_view_data(
		LegacyRunnerModel.DEFAULT_SEEDS,
		30
	)
	var runs := data.get("seeds", []) as Array
	_check(
		_key_days_generate_cards(view_model, runs),
		"1. build_living_surface_cards generates cards for key dates in 20 seeds"
	)
	_check(
		_all_cards_have_required_fields(view_model, runs),
		"2. every LivingSurfaceCard has card_id/day/title/scene_summary"
	)
	_check(
		_all_cards_have_sources(view_model, runs),
		"3. every LivingSurfaceCard has source_fact_ids or trace_ids"
	)
	_check(
		_fact_card_contains(
			view_model,
			runs,
			"chen_mi_took_spoiled_grain",
			["陈米", "发霉"]
		),
		"4. grain-taking day mentions Chen Mi and spoiled grain"
	)
	_check(
		_fact_card_contains(
			view_model,
			runs,
			"guard_locked_abandoned_granary",
			["粮仓", "封条"]
		),
		"5. guard-lock path produces a granary seal card"
	)
	_check(
		_any_fact_card_contains(
			view_model,
			runs,
			[
				"chen_mi_collapsed_from_hunger",
				"old_chen_took_chen_mi_to_seek_help",
			],
			["倒", "求助"]
		),
		"6. extreme hunger path produces collapse or help card"
	)
	_check(
		_fact_card_contains(
			view_model,
			runs,
			"chen_mi_returned_empty_handed",
			["空手"]
		),
		"7. empty granary path produces empty-handed card"
	)
	_check(
		_any_fact_card_contains(
			view_model,
			runs,
			[
				"chen_mi_endured_hunger",
				"chen_mi_weakened_from_enduring_hunger",
			],
			["虚弱", "沉默", "忍"]
		),
		"8. endured hunger path produces weakness or silent-child card"
	)
	_check(
		builder.build_living_surface_cards(_unsupported_state_run(), 1).is_empty(),
		"9. unsupported blank day does not create a major scene"
	)
	var first_run := runs[0] as Dictionary
	var first_day := _first_fact_day(first_run)
	var people_cards := view_model.build_people_cards(first_run, first_day)
	_check(
		_cards_include_ids(people_cards, "npc_id", ["old_chen", "chen_mi"]),
		"10. People cards include old_chen and chen_mi"
	)
	var location_cards := view_model.build_location_cards(
		first_run,
		first_day
	)
	_check(
		_cards_include_ids(
			location_cards,
			"location_id",
			["old_chen_shop", "abandoned_granary"]
		),
		"11. Location cards include shop and granary"
	)
	_check(
		templates.value_level(0) == "低"
		and templates.value_level(31) == "中"
		and templates.value_level(61) == "高"
		and templates.value_level(86) == "极高",
		"12. numeric level conversion is correct"
	)
	_check(
		_unknown_fact_card_is_generic(builder),
		"13. unknown fact type does not error and uses generic text"
	)
	var detail := view_model.build_day_detail(first_run, first_day)
	_check(
		_detail_keeps_old_and_new_fields(detail),
		"14. build_day_detail keeps old fields and adds living-surface fields"
	)
	_check(
		_viewer_scene_parses_and_is_read_only(),
		"15. UI scene script parses headlessly"
	)
	_check(
		_viewer_source_has_no("add_fact("),
		"16. UI does not create WorldFact"
	)
	_check(
		_viewer_source_has_no("WorldSimState")
		and _viewer_source_has_no("create_state_for_seed(")
		and _viewer_source_has_no("tick_once("),
		"17. UI does not modify state"
	)
	var totals := data.get("quality_totals", {}) as Dictionary
	_check(
		int(totals.get("unresolved_extreme_hunger", -1)) == 0,
		"18. unresolved_extreme_hunger remains zero"
	)
	_check(
		int(totals.get("impossible_shop_state", -1)) == 0,
		"19. impossible_shop_state remains zero"
	)
	_check(
		int(totals.get("dangling_major_fact", -1)) == 0,
		"20. dangling_major_fact remains zero"
	)
	_check(
		_git_path_unchanged(PROTECTED_STORY_PLAYER),
		"21. story_player.gd is unchanged"
	)
	_check(
		_git_path_unchanged(PROTECTED_WORLD_GENERATION),
		"22. world_generation_v03.gd is unchanged"
	)

	if failures.is_empty():
		print("[LAKE TOWN LIVING SURFACE RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[LAKE TOWN LIVING SURFACE FAIL] " + failure)
		print(
			"[LAKE TOWN LIVING SURFACE RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _key_days_generate_cards(view_model: Variant, runs: Array) -> bool:
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		var found_card := false
		for fact_value: Variant in run.get("fact_rows", []):
			var fact := fact_value as Dictionary
			if str(fact.get("type", "")) not in BuilderModel.KEY_FACT_TYPES:
				continue
			if not view_model.build_living_surface_cards(
					run,
					int(fact.get("day", 0))
				).is_empty():
				found_card = true
				break
		if not found_card:
			return false
	return not runs.is_empty()


func _all_cards_have_required_fields(
		view_model: Variant,
		runs: Array
	) -> bool:
	for card in _all_cards(view_model, runs):
		var data := card as Dictionary
		for key: String in ["card_id", "day", "title", "scene_summary"]:
			if not data.has(key) or str(data.get(key, "")) == "":
				return false
	return true


func _all_cards_have_sources(view_model: Variant, runs: Array) -> bool:
	for card in _all_cards(view_model, runs):
		var data := card as Dictionary
		if (
			(data.get("source_fact_ids", []) as Array).is_empty()
			and (data.get("trace_ids", []) as Array).is_empty()
		):
			return false
	return true


func _fact_card_contains(
		view_model: Variant,
		runs: Array,
		fact_type: String,
		tokens: Array[String]
	) -> bool:
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		for fact_value: Variant in run.get("fact_rows", []):
			var fact := fact_value as Dictionary
			if str(fact.get("type", "")) != fact_type:
				continue
			var text := JSON.stringify(
				view_model.build_living_surface_cards(
					run,
					int(fact.get("day", 0))
				)
			)
			var ok := true
			for token: String in tokens:
				if token not in text:
					ok = false
			if ok:
				return true
	return false


func _any_fact_card_contains(
		view_model: Variant,
		runs: Array,
		fact_types: Array[String],
		any_tokens: Array[String]
	) -> bool:
	for fact_type: String in fact_types:
		for token: String in any_tokens:
			if _fact_card_contains(view_model, runs, fact_type, [token]):
				return true
	return false


func _cards_include_ids(
		cards: Array,
		id_key: String,
		expected: Array[String]
	) -> bool:
	var found: Array[String] = []
	for card_value: Variant in cards:
		var id_value := str((card_value as Dictionary).get(id_key, ""))
		if id_value not in found:
			found.append(id_value)
	for id_value: String in expected:
		if id_value not in found:
			return false
	return true


func _unknown_fact_card_is_generic(builder: Variant) -> bool:
	var cards: Array = builder.build_living_surface_cards(
		_unknown_fact_run(),
		1
	)
	var text := JSON.stringify(cards)
	return (
		not cards.is_empty()
		and "尚未命名" in text
		and "unknown_lake_town_fact" in text
	)


func _detail_keeps_old_and_new_fields(detail: Dictionary) -> bool:
	var old_keys: Array[String] = [
		"facts",
		"traces",
		"memories",
		"narratable_states",
		"npc_snapshot",
		"location_snapshot",
		"quality_flags",
	]
	var new_keys: Array[String] = [
		"living_surface_cards",
		"primary_surface_card",
		"people_cards",
		"location_cards",
	]
	for key: String in old_keys + new_keys:
		if not detail.has(key):
			return false
	return true


func _viewer_scene_parses_and_is_read_only() -> bool:
	var packed := load(VIEWER_SCENE) as PackedScene
	if packed == null:
		return false
	var viewer := packed.instantiate()
	var valid := viewer.get_script() != null
	viewer.free()
	return valid


func _viewer_source_has_no(token: String) -> bool:
	var source := FileAccess.get_file_as_string(VIEWER_SCRIPT)
	return token not in source


func _all_cards(view_model: Variant, runs: Array) -> Array:
	var output: Array = []
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		for day: int in range(1, int(run.get("days", 30)) + 1):
			output.append_array(
				view_model.build_living_surface_cards(run, day)
			)
	return output


func _first_fact_day(run: Dictionary) -> int:
	for fact_value: Variant in run.get("fact_rows", []):
		return int((fact_value as Dictionary).get("day", 1))
	return 1


func _unsupported_state_run() -> Dictionary:
	return {
		"seed": 1,
		"days": 1,
		"fact_rows": [],
		"trace_rows": [],
		"memory_rows": [],
		"narratable_rows": [],
		"npc_snapshots": {
			"1": {
				"old_chen": {"id": "old_chen", "stress": 100},
				"chen_mi": {"id": "chen_mi", "hunger": 100},
			},
		},
		"location_snapshots": {"1": {}},
		"quality_summary": {"quality_flags": []},
	}


func _unknown_fact_run() -> Dictionary:
	var base := _unsupported_state_run()
	base["fact_rows"] = [{
		"id": "fact_unknown",
		"fact_id": "fact_unknown",
		"day": 1,
		"type": "unknown_lake_town_fact",
		"summary": "",
		"actors": [],
		"location_id": "old_chen_shop",
		"region_id": "lake_town",
		"cause_fact_ids": [],
		"tags": [],
	}]
	base["trace_rows"] = [{
		"id": "trace_unknown",
		"trace_id": "trace_unknown",
		"day": 1,
		"type": "unknown_trace",
		"location_id": "old_chen_shop",
		"source_fact_id": "fact_unknown",
		"description_tags": ["unknown"],
	}]
	base["location_snapshots"] = {
		"1": {
			"old_chen_shop": {
				"id": "old_chen_shop",
				"is_open": true,
				"status_tags": [],
			},
			"abandoned_granary": {
				"id": "abandoned_granary",
				"status_tags": [],
			},
		},
	}
	return base


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
		print("[LAKE TOWN LIVING SURFACE PASS] " + message)
	else:
		failures.append(message)
