extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"

const EXPECTED_ATTRIBUTES := {
	"strength": 7,
	"dexterity": 8,
	"wisdom": 9,
	"charisma": 6,
	"constitution": 8,
	"perception": 10,
}

const EXPECTED_CHALLENGE_STATS := {
	"granary_rotten_floor_entry": "dexterity",
	"north_quay_flooded_stack_search": "strength",
	"mist_salt_well_second_ring_descent": "constitution",
}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. Player attribute surface loads")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var player_summary := viewer.get_node("%PlayerSummary") as RichTextLabel
	var player_view: Dictionary = viewer.get_current_view_data().get("player", {})
	var snapshot: Variant = viewer.view_model.session.get_snapshot()
	var runtime_attributes_match := true
	for key: String in EXPECTED_ATTRIBUTES:
		var expected := int(EXPECTED_ATTRIBUTES[key])
		runtime_attributes_match = (
			runtime_attributes_match
			and int(player_view.get(key, -1)) == expected
			and int(snapshot.get_player_value(key, -1)) == expected
		)
	_check(
		runtime_attributes_match,
		"2. All six attributes come from the runtime player snapshot"
	)

	_check(
		"力量 7　敏捷 8　智慧 9" in player_summary.text
		and "魅力 6　体质 8　感知 10" in player_summary.text
		and "食物　3 份　健康　100　伤势　无" in player_summary.text,
		"3. Left summary exposes all attributes and survival state"
	)
	_check(
		player_summary.custom_minimum_size.y >= 126.0,
		"4. Attribute summary reserves enough vertical reading space"
	)

	var challenge_stats := {}
	for challenge: Dictionary in viewer.view_model.session.challenge_definitions:
		challenge_stats[str(challenge.get("challenge_id", ""))] = str(
			challenge.get("stat_key", "")
		)
	var challenge_stats_match := true
	for challenge_id: String in EXPECTED_CHALLENGE_STATS:
		challenge_stats_match = (
			challenge_stats_match
			and str(challenge_stats.get(challenge_id, ""))
				== str(EXPECTED_CHALLENGE_STATS[challenge_id])
		)
	_check(
		challenge_stats_match,
		"5. Physical risks use dexterity, strength, and constitution checks"
	)

	viewer.restart_session()
	await process_frame
	_check(
		"力量 7　敏捷 8　智慧 9" in player_summary.text
		and "魅力 6　体质 8　感知 10" in player_summary.text,
		"6. Restart restores the complete attribute sheet"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 PLAYER ATTRIBUTE PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 PLAYER ATTRIBUTE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 PLAYER ATTRIBUTE FAIL] " + failure)
	print("[V5 PLAYER ATTRIBUTE RESULT] FAIL (%d)" % failures.size())
	quit(1)
