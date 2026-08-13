extends RefCounted
class_name V5SeventhOutpostViewModel

const ControllerModel = preload(
	"res://scripts/sim/life_project/life_project_controller.gd"
)
const FIXTURE_PATH := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const PROJECT_PATH := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_winter.json"
)

var controller: Variant = null
var latest_result: Dictionary = {}


func start() -> Dictionary:
	controller = ControllerModel.new()
	latest_result = {}
	return controller.start(FIXTURE_PATH, PROJECT_PATH)


func is_ready() -> bool:
	return controller != null and controller.is_ready()


func perform_duty(duty_id: String) -> Dictionary:
	if not is_ready():
		return {"success": false, "error": "project_not_ready"}
	latest_result = controller.execute_duty(duty_id)
	return latest_result.duplicate(true)


func build_view_data() -> Dictionary:
	if not is_ready():
		return {"ready": false, "error_text": "第七哨站暂时无法载入。"}
	var snapshot: Variant = controller.session.get_snapshot()
	return {
		"ready": true,
		"title": "第七哨站",
		"subtitle": "边境服役 · 第一年 · 新兵之冬",
		"day": controller.get_day(),
		"duration_days": controller.get_duration_days(),
		"complete": controller.is_complete(),
		"ritual": controller.get_ritual(),
		"player": _player_view(snapshot),
		"status": controller.get_status(),
		"people": _people_view(snapshot),
		"actions": _action_rows(),
		"feedback": _feedback_view(),
		"history": controller.day_history.duplicate(true),
		"completion": controller.get_completion_summary(),
	}


func _player_view(snapshot: Variant) -> Dictionary:
	return {
		"summary": "\n".join([
			"身份　第七哨站新兵",
			"力量 %d　敏捷 %d　智慧 %d" % [
				int(snapshot.get_player_value("strength", 0)),
				int(snapshot.get_player_value("dexterity", 0)),
				int(snapshot.get_player_value("wisdom", 0)),
			],
			"魅力 %d　体质 %d　感知 %d" % [
				int(snapshot.get_player_value("charisma", 0)),
				int(snapshot.get_player_value("constitution", 0)),
				int(snapshot.get_player_value("perception", 0)),
			],
			"疲劳 %d / 10　训练 %d" % [
				int(snapshot.get_player_value("fatigue", 0)),
				int(snapshot.get_player_value("training", 0)),
			],
		]),
		"fatigue": int(snapshot.get_player_value("fatigue", 0)),
		"training": int(snapshot.get_player_value("training", 0)),
	}


func _people_view(snapshot: Variant) -> Array:
	var rows: Array[Dictionary] = []
	var relationship_axes := {
		"captain_ron": ["discipline_respect", "军纪认可"],
		"recruit_elai": ["trust", "信任"],
		"cook_marta": ["trust", "信任"],
		"medic_saira": ["familiarity", "熟悉"],
		"veteran_hoke": ["trust", "信任"],
	}
	for person_id: String in relationship_axes.keys():
		var person: Dictionary = snapshot.get_entity(person_id)
		var axis_data: Array = relationship_axes[person_id]
		rows.append({
			"id": person_id,
			"name": str(person.get("display_name", person_id)),
			"description": str(person.get("description", "")),
			"relation_label": str(axis_data[1]),
			"relation_value": int(snapshot.get_relation(
				person_id, "player", str(axis_data[0]), 0
			)),
		})
	return rows


func _action_rows() -> Array:
	var rows: Array[Dictionary] = []
	for option: Dictionary in controller.get_duty_options():
		var can_execute := bool(option.get("can_execute", true))
		var label := str(option.get("label", "承担值勤"))
		if not can_execute:
			var unmet_summary := _unmet_requirement_summary(
				option.get("requirements", [])
			)
			label += "　[%s]" % (
				unmet_summary if unmet_summary != "" else "条件不足"
			)
		var hint := (
			str(option.get("blocked_reason", ""))
			if not can_execute
			else str(option.get("hint", ""))
		)
		var risk_text := _risk_text(option)
		if risk_text != "":
			hint += "\n%s" % risk_text
		rows.append({
			"duty_id": str(option.get("duty_id", "")),
			"label": label,
			"kind": str(option.get("kind", "值勤")),
			"hint": hint,
			"can_execute": can_execute,
			"requirements": option.get("requirements", []),
			"modifier_explanations": option.get("modifier_explanations", []),
			"base_values": option.get("base_values", {}),
			"modified_values": option.get("modified_values", {}),
		})
	return rows


func _feedback_view() -> Dictionary:
	if latest_result.is_empty():
		return {
			"title": "第一次点名",
			"body": "罗恩念到你的名字时没有抬头。今天做什么，会在明早的点名以前改变哨站。",
			"details": [],
		}
	if not bool(latest_result.get("success", false)):
		return {
			"title": "今天的职责没有开始",
			"body": str(latest_result.get(
				"blocked_reason", "当前状态不允许承担这项职责。"
			)),
			"details": [],
		}
	var details: Array[String] = []
	for note: Variant in latest_result.get("settlement_notes", []):
		details.append(str(note))
	for narrative: Variant in latest_result.get("npc_narratives", []):
		details.append(str(narrative))
	var risk_text := _risk_text(latest_result)
	if risk_text != "":
		details.push_front(risk_text)
	for modifier: Dictionary in latest_result.get("modifier_explanations", []):
		details.append(_modifier_text(modifier))
	return {
		"title": str(latest_result.get("title", "一天过去")),
		"body": str(latest_result.get("summary", "")),
		"details": details,
	}


func _risk_text(source: Dictionary) -> String:
	var base_values: Dictionary = source.get("base_values", {})
	var modified_values: Dictionary = source.get("modified_values", {})
	if not base_values.has("action.risk"):
		return ""
	return "风险 %s → %s" % [
		_number_text(float(base_values.get("action.risk", 0.0))),
		_number_text(float(modified_values.get(
			"action.risk", base_values.get("action.risk", 0.0)
		))),
	]


func _modifier_text(modifier: Dictionary) -> String:
	var amount := float(modifier.get("value", 0.0))
	var sign := "+" if amount > 0.0 else ""
	var reason := str(modifier.get("reason", ""))
	return "%s %s%s 风险%s%s" % [
		str(modifier.get("source_label", "修正")),
		sign,
		_number_text(amount),
		"：" if reason != "" else "",
		reason,
	]


func _number_text(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(value))
	return str(value)


func _unmet_requirement_summary(requirements: Array) -> String:
	for requirement: Dictionary in requirements:
		if bool(requirement.get("met", false)):
			continue
		for condition: Dictionary in requirement.get("conditions", []):
			if bool(condition.get("met", false)):
				continue
			var current: Variant = condition.get("current")
			var required: Variant = condition.get("required")
			if current is int or current is float:
				return "%s %s/%s" % [
					str(condition.get("label", "条件")),
					_number_text(float(current)),
					_number_text(float(required)),
				]
	return ""
