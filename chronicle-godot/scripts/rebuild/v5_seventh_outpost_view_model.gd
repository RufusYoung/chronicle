extends RefCounted
class_name V5SeventhOutpostViewModel

const ControllerModel = preload(
	"res://scripts/sim/life_project/life_project_controller.gd"
)
const FIRST_WINTER_FIXTURE_PATH := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const FIRST_WINTER_PROJECT_PATH := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_winter.json"
)
const FIRST_QUARTER_FIXTURE_PATH := (
	"res://data/sim/fixtures/seventh_outpost_first_quarter_fixture.json"
)
const FIRST_QUARTER_PROJECT_PATH := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_quarter.json"
)
const FIRST_WINTER_PHASE_ID := "first_winter"
const FIRST_QUARTER_PHASE_ID := "first_quarter"
const FIRST_QUARTER_FIXTURE_ID := "seventh_outpost_first_quarter"
const MARKET_POLICY_ID := "market_policy.seventh_outpost_canteen"
const LifeStageTransitionServiceModel = preload(
	"res://scripts/sim/save/life_stage_transition_service.gd"
)

var controller: Variant = null
var latest_result: Dictionary = {}
var start_result: Dictionary = {}
var current_phase_id: String = FIRST_WINTER_PHASE_ID
var phase_start_transition: Dictionary = {}


func start(
		transition: Dictionary = {}, requested_phase_id: String = ""
) -> Dictionary:
	var next_phase_id := _resolve_phase_id(transition, requested_phase_id)
	var phase: Dictionary = _phase_config(next_phase_id)
	var next_controller = ControllerModel.new()
	var start_report: Dictionary = next_controller.start(
		str(phase.get("fixture_path", "")),
		str(phase.get("project_path", ""))
	)
	if not bool(start_report.get("success", false)):
		start_result = start_report.duplicate(true)
		return start_report
	if not transition.is_empty():
		var transition_report: Dictionary = (
			LifeStageTransitionServiceModel.new().apply_to_controller(
				next_controller, transition
			)
		)
		if not bool(transition_report.get("success", false)):
			start_result = transition_report.duplicate(true)
			return transition_report
		start_report["transition"] = transition_report
	controller = next_controller
	current_phase_id = next_phase_id
	phase_start_transition = transition.duplicate(true)
	latest_result = {}
	start_result = start_report.duplicate(true)
	return start_report


func restart_current_phase() -> Dictionary:
	return start(phase_start_transition, current_phase_id)


func enter_first_quarter() -> Dictionary:
	if not is_ready() or current_phase_id != FIRST_WINTER_PHASE_ID:
		return {
			"success": false,
			"error": "first_quarter_transition_not_available",
		}
	var transition: Dictionary = controller.build_life_stage_transition(
		FIRST_QUARTER_FIXTURE_ID
	)
	if transition.is_empty():
		return {
			"success": false,
			"error": "first_quarter_transition_not_ready",
		}
	return start(transition, FIRST_QUARTER_PHASE_ID)


func is_ready() -> bool:
	return controller != null and controller.is_ready()


func perform_duty(duty_id: String) -> Dictionary:
	if not is_ready():
		return {"success": false, "error": "project_not_ready"}
	latest_result = controller.execute_duty(duty_id)
	return latest_result.duplicate(true)


func purchase_market_offer(
		item_instance_id: String,
		quoted_unit_price: int,
		quantity: int = 1
) -> Dictionary:
	if not is_ready():
		return {"success": false, "error": "project_not_ready"}
	var trade: Dictionary = controller.session.execute_market_trade(
		MARKET_POLICY_ID,
		{
			"item_instance_id": item_instance_id,
			"quoted_unit_price": quoted_unit_price,
			"quantity": quantity,
		}
	)
	if bool(trade.get("success", false)):
		latest_result = {
			"success": true,
			"title": "从玛塔手里领到一份口粮",
			"summary": "你付出 %d 枚铜币。口粮进入随身物品，玛塔的库存和哨站粮食压力也已经改变。" % int(
				trade.get("total_price", 0)
			),
			"settlement_notes": ["交易事实与交换记录已经写入世界。"],
			"npc_narratives": [],
			"base_values": {},
			"modified_values": {},
			"modifier_explanations": [],
		}
	else:
		latest_result = {
			"success": false,
			"error": str(trade.get("error", "market_trade_failed")),
			"blocked_reason": _market_error_text(trade),
		}
	return trade


func confirm_growth_candidate(candidate_id: String) -> Dictionary:
	if not is_ready():
		return {"success": false, "error": "project_not_ready"}
	latest_result = controller.confirm_growth_candidate(candidate_id)
	if not bool(latest_result.get("success", false)):
		latest_result["blocked_reason"] = _growth_error_text(latest_result)
	return latest_result.duplicate(true)


func save_to_path(path: String, options: Dictionary = {}) -> Dictionary:
	if not is_ready():
		return {"success": false, "ok": false, "error": "project_not_ready"}
	return controller.save_to_path(path, options)


func load_from_path(path: String) -> Dictionary:
	controller = ControllerModel.new()
	latest_result = {}
	var result: Dictionary = controller.load_from_path(path)
	if (
		bool(result.get("success", false))
		and str(result.get("source_kind", "")) != "player_save"
	):
		controller.reset()
		return {
			"success": false,
			"ok": false,
			"error": "save_source_kind_not_player_save",
			"phase": "ui_load",
		}
	if bool(result.get("success", false)):
		current_phase_id = _phase_id_for_project(controller.project_id)
		phase_start_transition = controller.get_entry_transition()
		latest_result = controller.latest_result.duplicate(true)
	return result


func build_view_data() -> Dictionary:
	if not is_ready():
		return {"ready": false, "error_text": "第七哨站暂时无法载入。"}
	var snapshot: Variant = controller.session.get_snapshot()
	var phase: Dictionary = _phase_config(current_phase_id)
	return {
		"ready": true,
		"title": "第七哨站",
		"subtitle": str(phase.get("subtitle", "边境服役")),
		"phase_id": current_phase_id,
		"day": controller.get_day(),
		"duration_days": controller.get_duration_days(),
		"calendar_days_per_step": controller.get_calendar_days_per_step(),
		"progress_unit_label": controller.get_progress_unit_label(),
		"world_day": int(controller.session.current_day),
		"complete": controller.is_complete(),
		"can_advance_phase": _can_enter_first_quarter(),
		"objective": str(phase.get("objective", "")),
		"ritual": controller.get_ritual(),
		"player": _player_view(snapshot),
		"status": controller.get_status(),
		"market": _market_view(snapshot),
		"people": _people_view(snapshot),
		"actions": _action_rows(),
		"feedback": _feedback_view(),
		"history": controller.day_history.duplicate(true),
		"completion": controller.get_completion_summary(),
	}


func _player_view(snapshot: Variant) -> Dictionary:
	var identity := (
		"第七哨站新兵"
		if current_phase_id == FIRST_WINTER_PHASE_ID
		else "第七哨站戍卒 · 第一季度"
	)
	return {
		"summary": "\n".join([
			"身份　%s" % identity,
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
		"features": _feature_lines(snapshot),
		"fatigue": int(snapshot.get_player_value("fatigue", 0)),
		"training": int(snapshot.get_player_value("training", 0)),
	}


func _feature_lines(snapshot: Variant) -> String:
	var talent_names: Array[String] = []
	for assignment: Dictionary in snapshot.get_talent_assignments("player"):
		var definition: Dictionary = controller.session.registry.get_definition(
			"talent", str(assignment.get("talent_def_id", ""))
		)
		talent_names.append(str(definition.get(
			"display_name", assignment.get("talent_def_id", "")
		)))
	var mark_names: Array[String] = []
	for mark: Dictionary in snapshot.get_mark_instances("player"):
		var definition: Dictionary = controller.session.registry.get_definition(
			"mark", str(mark.get("mark_def_id", ""))
		)
		mark_names.append("%s %s（%d）" % [
			str(definition.get("display_name", mark.get("mark_def_id", ""))),
			str(mark.get("stage_id", "")),
			int(mark.get("progress", 0)),
		])
	var trait_names: Array[String] = []
	for trait_instance: Dictionary in snapshot.get_trait_instances("player"):
		if str(trait_instance.get("status", "active")) != "active":
			continue
		var definition: Dictionary = controller.session.registry.get_definition(
			"trait", str(trait_instance.get("trait_def_id", ""))
		)
		trait_names.append(str(definition.get(
			"display_name", trait_instance.get("trait_def_id", "")
		)))
	var skill_names: Array[String] = []
	var progress_by_id: Dictionary = {}
	for skill: Dictionary in snapshot.get_skill_progress("player"):
		progress_by_id[str(skill.get("skill_def_id", ""))] = skill
	for skill_id: String in [
		"skill.scouting", "skill.maintenance", "skill.archery"
	]:
		var definition: Dictionary = controller.session.registry.get_definition(
			"skill", skill_id
		)
		var progress: Dictionary = progress_by_id.get(skill_id, {})
		skill_names.append("%s %d级·%d经验" % [
			str(definition.get("display_name", skill_id)),
			int(progress.get("rank", 0)),
			int(progress.get("practice_xp", 0)),
		])
	var equipment_names: Array[String] = []
	for slot: String in ["body_outer", "main_hand", "utility"]:
		var item: Dictionary = snapshot.get_equipped_item("player", slot)
		if item.is_empty():
			continue
		var condition: Dictionary = item.get("condition", {})
		var durability := ""
		if condition.has("durability"):
			durability = " %d/%d" % [
				int(condition.get("durability", 0)),
				int(condition.get("maximum_durability", 0)),
			]
		var history_count := (item.get("history", []) as Array).size()
		var history_text := (
			" · %d 条履历" % history_count if history_count > 0 else ""
		)
		equipment_names.append("%s%s%s" % [
			str(item.get("display_name", item.get("item_def_id", ""))),
			durability,
			history_text,
		])
	return "\n".join([
		"天赋　%s" % "、".join(talent_names),
		"特质　%s" % (
			"尚未形成" if trait_names.is_empty() else "、".join(trait_names)
		),
		"印记　%s" % (
			"尚未形成" if mark_names.is_empty() else "、".join(mark_names)
		),
		"技能　%s" % "　".join(skill_names),
		"装备　%s" % "　".join(equipment_names),
	])


func _market_view(snapshot: Variant) -> Dictionary:
	var stock: Dictionary = controller.session.get_market_stock_view(
		MARKET_POLICY_ID
	)
	var coin_count := _owned_item_quantity(
		snapshot, "player", "item.copper_coin"
	)
	var ration_count := _owned_item_quantity(
		snapshot, "player", "item.travel_ration"
	)
	var offers: Array[Dictionary] = []
	for offer: Dictionary in stock.get("offers", []):
		var unit_price := int(offer.get("unit_price", 0))
		offers.append({
			"item_instance_id": str(offer.get("item_instance_id", "")),
			"display_name": str(offer.get("display_name", "口粮")),
			"available_quantity": int(offer.get("available_quantity", 0)),
			"unit_price": unit_price,
			"quote_summary": str(offer.get("quote_summary", "")),
			"can_purchase": coin_count >= unit_price,
		})
	return {
		"display_name": str(stock.get("display_name", "哨站配给处")),
		"coin_count": coin_count,
		"ration_count": ration_count,
		"offers": offers,
		"error": str(stock.get("error", "")),
	}


func _owned_item_quantity(
		snapshot: Variant,
		owner_id: String,
		item_def_id: String
) -> int:
	var quantity := 0
	for item: Dictionary in snapshot.get_items():
		var holder: Dictionary = item.get("holder", {})
		if (
			str(holder.get("kind", "")) == "entity"
			and str(holder.get("id", "")) == owner_id
			and str(item.get("item_def_id", "")) == item_def_id
		):
			quantity += int(item.get("quantity", 0))
	return quantity


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
			"state_summary": _person_state_summary(snapshot, person_id),
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
		if current_phase_id == FIRST_QUARTER_PHASE_ID:
			return {
				"title": "第一冬已经翻页",
				"body": "北坡开始融雪。接下来每次选择代表两周值勤，第一冬留下的成长、关系、物资和哨站压力都会继续参与结算。",
				"details": ["当前世界第 %d 天。" % int(
					controller.session.current_day
				)],
			}
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
	var risk_outcome: Dictionary = latest_result.get("risk_outcome", {})
	if not risk_outcome.is_empty():
		details.append("%s：掷骰 %d，对抗风险 %d" % [
			str(risk_outcome.get("title", "风险结算")),
			int(risk_outcome.get("roll", 0)),
			int(risk_outcome.get("risk", 0)),
		])
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


func _market_error_text(result: Dictionary) -> String:
	match str(result.get("error", "")):
		"quote_changed":
			return "粮食压力改变了报价，请查看当前价格后再买。"
		"insufficient_payment":
			return "你的铜币不够。物品和库存都没有改变。"
		"insufficient_stock", "offer_no_longer_available":
			return "玛塔手里已经没有这份库存。"
	return "这笔交易没有完成，物品与铜币均未改变。"


func _growth_error_text(result: Dictionary) -> String:
	match str(result.get("error", "")):
		"project_not_complete":
			return "这一阶段尚未结束，当前经历还不能结算。"
		"growth_candidate_not_available":
			return "这项成长不符合你实际留下的经历。"
		"growth_already_confirmed":
			return "本阶段的成长已经确认，不能重复领取。"
		"growth_transaction_rejected":
			return "成长写入未通过完整性检查，角色状态没有改变。"
	return "这项成长没有确认，角色状态没有改变。"


func _can_enter_first_quarter() -> bool:
	return (
		current_phase_id == FIRST_WINTER_PHASE_ID
		and controller.is_complete()
		and not controller.build_life_stage_transition(
			FIRST_QUARTER_FIXTURE_ID
		).is_empty()
	)


func _resolve_phase_id(
		transition: Dictionary, requested_phase_id: String
) -> String:
	if requested_phase_id in [FIRST_WINTER_PHASE_ID, FIRST_QUARTER_PHASE_ID]:
		return requested_phase_id
	if str(transition.get("target_fixture_id", "")) == FIRST_QUARTER_FIXTURE_ID:
		return FIRST_QUARTER_PHASE_ID
	return FIRST_WINTER_PHASE_ID


func _phase_id_for_project(source_project_id: String) -> String:
	return (
		FIRST_QUARTER_PHASE_ID
		if source_project_id == "seventh_outpost_first_quarter"
		else FIRST_WINTER_PHASE_ID
	)


func _phase_config(phase_id: String) -> Dictionary:
	if phase_id == FIRST_QUARTER_PHASE_ID:
		return {
			"fixture_path": FIRST_QUARTER_FIXTURE_PATH,
			"project_path": FIRST_QUARTER_PROJECT_PATH,
			"subtitle": "边境服役 · 第一年 · 融雪期 · 第一季度",
			"objective": "[b]第一季度目标[/b]\n完成六个双周值勤节点，共推进 84 天。冬季形成的成长会解锁不同职责；人物、物资和哨站压力会继续变化。",
		}
	return {
		"fixture_path": FIRST_WINTER_FIXTURE_PATH,
		"project_path": FIRST_WINTER_PROJECT_PATH,
		"subtitle": "边境服役 · 第一年 · 新兵之冬",
		"objective": "[b]第一冬目标[/b]\n完成七个值勤日。每天只选一项职责；口粮、疲劳、军纪与身边人的行动都会继续结算。",
	}


func _person_state_summary(snapshot: Variant, person_id: String) -> String:
	var rows: Array[String] = []
	var fatigue: Variant = snapshot.get_entity_state(
		person_id, "fatigue", null
	)
	if fatigue != null:
		rows.append("疲劳 %d/10" % int(fatigue))
	var fear := str(snapshot.get_entity_state(person_id, "fear", ""))
	if fear != "":
		rows.append("紧张 %s" % {
			"low": "低", "medium": "中", "high": "高"
		}.get(fear, fear))
	return "　".join(rows)
