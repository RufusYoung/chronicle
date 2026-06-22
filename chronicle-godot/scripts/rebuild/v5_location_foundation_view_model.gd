extends RefCounted
class_name V5LocationFoundationViewModel

const StateModel = preload(
	"res://scripts/rebuild/v5_location_foundation_state.gd"
)

var state: Variant


func _init() -> void:
	state = StateModel.new()


func bind_state(source_state: Variant) -> void:
	state = source_state


func get_character_summary() -> Dictionary:
	var character: Dictionary = state.get_character()
	var stats: Dictionary = character.get("stats", {}) as Dictionary
	return {
		"name": str(character.get("name", "")),
		"age": int(character.get("age", 0)),
		"identity": str(character.get("identity", "")),
		"current_location": str(character.get("current_location_name", "")),
		"vitals": [
			_stat_line("生命", stats.get("life", {}) as Dictionary),
			_stat_line("精力", stats.get("energy", {}) as Dictionary),
			_stat_line(
				"健康",
				stats.get("health", {}) as Dictionary,
				_inline_terms(character.get("injuries", []) as Array)
			),
			_stat_line(
				"理智",
				stats.get("sanity", {}) as Dictionary,
				_inline_terms(character.get("mental_terms", []) as Array)
			),
			_stat_line("饥饿", stats.get("hunger", {}) as Dictionary),
		],
		"injuries": (character.get("injuries", []) as Array).duplicate(),
		"mental_terms": (character.get("mental_terms", []) as Array).duplicate(),
		"attributes": (character.get("attributes", {}) as Dictionary).duplicate(true),
		"traits": (character.get("traits", []) as Array).duplicate(),
		"summary_text": _build_character_text(character),
	}


func get_location_scene() -> Dictionary:
	var scene: Dictionary = state.get_current_scene()
	var child_nodes: Array[Dictionary] = []
	for location_id: Variant in scene.get("child_location_ids", []):
		var location: Dictionary = state.get_location(str(location_id))
		if not location.is_empty():
			child_nodes.append({
				"id": str(location.get("id", "")),
				"name": str(location.get("name", "")),
			})
	scene["child_nodes"] = child_nodes
	return scene


func get_region_status() -> Array:
	var output: Array[Dictionary] = []
	for status_value: Variant in state.get_region_statuses():
		var status := status_value as Dictionary
		output.append({
			"id": str(status.get("id", "")),
			"label": str(status.get("label", "")),
			"state": str(status.get("state", "")),
			"detail": str(status.get("detail", "")),
			"display": "%s：%s。%s" % [
				str(status.get("label", "")),
				str(status.get("state", "")),
				str(status.get("detail", "")),
			],
		})
	return output


func get_clues_by_location() -> Array:
	var groups: Dictionary = {}
	for clue_value: Variant in state.get_discovered_clues():
		var clue := clue_value as Dictionary
		var location := str(clue.get("location", "湖湾镇"))
		if not groups.has(location):
			groups[location] = []
		(groups[location] as Array).append(_clue_row(clue))
	var output: Array[Dictionary] = []
	for location: Variant in groups:
		output.append({
			"location": str(location),
			"clues": (groups[location] as Array).duplicate(true),
		})
	return output


func get_location_nodes() -> Array:
	var output: Array[Dictionary] = []
	var current: String = state.get_current_location_id()
	for location_value: Variant in state.get_locations():
		var location := location_value as Dictionary
		output.append({
			"id": str(location.get("id", "")),
			"name": str(location.get("name", "")),
			"parent_id": str(location.get("parent_id", "")),
			"is_current": str(location.get("id", "")) == current,
		})
	return output


func get_action_options() -> Array:
	var output: Array[Dictionary] = []
	for action_value: Variant in state.get_available_actions():
		var action := action_value as Dictionary
		var prefix := str(action.get("prefix", "普通"))
		var label := str(action.get("label", ""))
		var time_cost := str(action.get("time_cost", ""))
		var button_text := "[%s] %s" % [prefix, label]
		if time_cost != "":
			button_text += " " + time_cost
		var row := action.duplicate(true)
		row["button_text"] = button_text
		output.append(row)
	return output


func get_life_panel_summary() -> Dictionary:
	var panel: Dictionary = state.get_life_panel()
	var completed: Array = panel.get("completed_experiences", []) as Array
	var chronicle: Array = panel.get("chronicle", []) as Array
	return {
		"title": "生涯",
		"available_directions": (
			panel.get("available_directions", []) as Array
		).duplicate(),
		"heard_but_locked": (
			panel.get("heard_but_locked", []) as Array
		).duplicate(),
		"completed_experiences": (
			["暂无"] if completed.is_empty() else completed.duplicate()
		),
		"chronicle": ["暂无"] if chronicle.is_empty() else chronicle.duplicate(),
	}


func get_clue_action_card(clue_id: String) -> Dictionary:
	var clue: Dictionary = state.get_clue(clue_id)
	if clue.is_empty() or not state.has_clue(clue_id):
		return {}
	var action_rows: Array[String] = []
	for action_id: Variant in clue.get("action_ids", []):
		var action := _action_by_id(str(action_id))
		if action.is_empty():
			continue
		action_rows.append(_action_display(action))
	return {
		"clue_id": clue_id,
		"title": "线索：%s" % str(clue.get("title", "")),
		"source": str(clue.get("source", "")),
		"credibility": str(clue.get("credibility", "")),
		"location": str(clue.get("location", "")),
		"actions": action_rows,
		"can_add_to_pursuit": bool(clue.get("can_add_to_pursuit", false)),
		"pursuit_text": (
			"是" if bool(clue.get("can_add_to_pursuit", false)) else "否"
		),
	}


func _build_character_text(character: Dictionary) -> String:
	var lines: Array[String] = [
		"%s" % str(character.get("name", "")),
		"%d 岁｜%s｜%s" % [
			int(character.get("age", 0)),
			str(character.get("identity", "")),
			str(character.get("current_location_name", "")),
		],
	]
	var stats := character.get("stats", {}) as Dictionary
	for item in [
		["生命", "life"],
		["精力", "energy"],
		["健康", "health", _inline_terms(character.get("injuries", []) as Array)],
		["理智", "sanity", _inline_terms(character.get("mental_terms", []) as Array)],
		["饥饿", "hunger"],
	]:
		var suffix := ""
		if item.size() > 2:
			suffix = str(item[2])
		lines.append(
			_stat_line(
				str(item[0]),
				stats.get(str(item[1]), {}) as Dictionary,
				suffix
			)
		)
	lines.append("")
	lines.append("核心特质：%s" % "、".join(character.get("traits", []) as Array))
	lines.append("")
	for key: Variant in (character.get("attributes", {}) as Dictionary):
		lines.append("%s %d" % [str(key), int(character["attributes"][key])])
	return "\n".join(lines)


func _stat_line(label: String, stat: Dictionary, suffix: String = "") -> String:
	var line := "%s：%d / %d" % [
		label,
		int(stat.get("current", 0)),
		int(stat.get("max", 0)),
	]
	if suffix != "":
		line += "　" + suffix
	return line


func _inline_terms(values: Array) -> String:
	if values.is_empty():
		return ""
	return "、".join(values)


func _clue_row(clue: Dictionary) -> Dictionary:
	return {
		"id": str(clue.get("id", "")),
		"label": "[%s] %s" % [
			str(clue.get("tag", "线索")),
			str(clue.get("title", "")),
		],
		"title": str(clue.get("title", "")),
		"location": str(clue.get("location", "")),
	}


func _action_by_id(action_id: String) -> Dictionary:
	for action_value: Variant in state.actions.values():
		var action := action_value as Dictionary
		if str(action.get("id", "")) == action_id:
			return action.duplicate(true)
	return {}


func _action_display(action: Dictionary) -> String:
	var text := str(action.get("label", ""))
	var time_cost := str(action.get("time_cost", ""))
	if time_cost != "":
		text += " " + time_cost
	return text
