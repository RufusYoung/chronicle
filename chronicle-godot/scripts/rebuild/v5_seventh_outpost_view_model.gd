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
			for requirement: Dictionary in option.get("requirements", []):
				if bool(requirement.get("met", false)):
					continue
				label += "　[%s %d/%d]" % [
					str(requirement.get("label", "条件")),
					int(requirement.get("current", 0)),
					int(requirement.get("required", 0)),
				]
				break
		rows.append({
			"duty_id": str(option.get("duty_id", "")),
			"label": label,
			"kind": str(option.get("kind", "值勤")),
			"hint": (
				str(option.get("blocked_reason", ""))
				if not can_execute
				else str(option.get("hint", ""))
			),
			"can_execute": can_execute,
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
	return {
		"title": str(latest_result.get("title", "一天过去")),
		"body": str(latest_result.get("summary", "")),
		"details": details,
	}
