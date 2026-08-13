extends SceneTree

const ControllerModel = preload(
	"res://scripts/sim/life_project/life_project_controller.gd"
)
const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const EffectProtocolResolverModel = preload(
	"res://scripts/sim/transaction/effect_protocol_resolver.gd"
)

const FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const PROJECT := (
	"res://data/sim/raw/life_projects/seventh_outpost_first_winter.json"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller = ControllerModel.new()
	var start: Dictionary = controller.start(FIXTURE, PROJECT)
	_check(bool(start.get("success", false)), "1. 冬季生活项目可加载统一行动合同")
	if not bool(start.get("success", false)):
		_finish()
		return

	var initial := _find_duty(controller.get_duty_options(), "patrol_fog_line")
	_check(
		int((initial.get("base_values", {}) as Dictionary).get(
			"action.risk", -1
		)) == 6
		and int((initial.get("modified_values", {}) as Dictionary).get(
			"action.risk", -1
		)) == 4
		and _has_modifier_source(initial, "equipment", "上蜡冬衣"),
		"2. 已装备冬衣把严寒巡查风险从 6 降至 4，并提供来源说明"
	)

	var feature_result = TransactionResultModel.new()
	feature_result.add_fact({
		"fact_id": "fact.contract.patrol.twisted_ankle",
		"fact_type": "actor_injured_during_challenge",
		"actor_id": "player",
		"target_id": "player",
		"injury": "twisted_ankle",
		"tick": 1,
	})
	feature_result.add_fact({
		"fact_id": "fact.contract.patrol.mist_salt_echo",
		"fact_type": "actor_acquired_mist_salt_echo",
		"actor_id": "player",
		"target_id": "mist_salt_line",
		"tick": 2,
	})
	for index: int in range(3):
		feature_result.add_fact({
			"fact_id": "fact.contract.patrol.practice.%d" % index,
			"fact_type": "life_project_duty_completed",
			"actor_id": "player",
			"target_id": "seventh_outpost",
			"duty_id": "patrol_fog_line",
			"tick": 3 + index,
		})
	feature_result.mark_resolved("unified_action_contract_test")
	_check(
		controller.session.writer.apply_result(
			feature_result, controller.session.stores
		),
		"3. 特征事实通过统一 TransactionResult 写入"
	)

	controller.session.stores["state_store"].set_state(
		"player", "perception", 7
	)
	var trained := _find_duty(
		controller.get_duty_options(), "patrol_fog_line"
	)
	_check(
		bool(trained.get("can_execute", false))
		and _requirement_mode(trained) == "any"
		and int((trained.get("modified_values", {}) as Dictionary).get(
			"action.risk", -1
		)) == 6,
		"4. 感知不足时 1 级侦察满足任一条件，四类修正共同得出风险 6"
	)
	_check(
		_has_modifier_source(trained, "equipment", "上蜡冬衣")
		and _has_modifier_source(trained, "trait", "扭伤的脚踝")
		and _has_modifier_source(trained, "mark", "雾盐回响")
		and _has_modifier_source(trained, "skill", "侦察"),
		"5. 装备、伤势、印记和技能均给出可读且可追踪的风险修正"
	)

	var fact_store: Variant = controller.session.stores["fact_store"]
	var state_store: Variant = controller.session.stores["state_store"]
	var fatigue_before := int(state_store.get_state("player", "fatigue", 0))
	var rejected = TransactionResultModel.new()
	rejected.add_fact({
		"fact_id": "fact.contract.atomicity.must_not_exist",
		"fact_type": "atomicity_probe",
		"actor_id": "player",
		"tick": 9,
	})
	rejected.add_state_change({
		"entity_id": "player",
		"key": "fatigue",
		"delta": 2,
	})
	rejected.add_obligation_update({
		"obligation_id": "missing.obligation",
		"status": "fulfilled",
	})
	rejected.mark_resolved("unified_action_contract_test")
	_check(
		not controller.session.writer.apply_result(
			rejected, controller.session.stores
		)
		and fact_store.get_fact(
			"fact.contract.atomicity.must_not_exist"
		).is_empty()
		and int(state_store.get_state("player", "fatigue", 0)) == fatigue_before
		and str(rejected.contract_status) == "invalid_contract",
		"6. 后置 Store 失败会拒绝整笔事务，前置 Fact 与状态均不落地"
	)

	var execution: Dictionary = controller.execute_duty("patrol_fog_line")
	_check(
		bool(execution.get("success", false))
		and int((execution.get("modified_values", {}) as Dictionary).get(
			"action.risk", -1
		)) == 6
		and controller.get_day() == 2,
		"7. 显式 Effect operations 经统一结果和 Writer 成功推进真实值勤"
	)

	var invalid = TransactionResultModel.new()
	invalid.add_state_change({
		"entity_id": "player",
		"key": "fatigue",
		"delta": 99,
	})
	invalid.mark_invalid_contract("test", "unsupported_effect_operation:test")
	var fatigue_after_duty := int(
		state_store.get_state("player", "fatigue", 0)
	)
	_check(
		not controller.session.writer.apply_result(
			invalid, controller.session.stores
		)
		and int(state_store.get_state("player", "fatigue", 0))
		== fatigue_after_duty,
		"8. 无效 Effect 协议在 Store 预检前被拒绝且不写入状态"
	)

	var investigation = TransactionResultModel.new()
	var effect_report: Dictionary = EffectProtocolResolverModel.new().append_effects(
		investigation,
		{
			"operations": [{
				"operation": "investigation_change",
				"change": {
					"operation": "create",
					"lead": {
						"lead_id": "lead.contract.protocol",
						"location_id": "seventh_outpost",
					},
				},
			}],
		}
	)
	investigation.mark_resolved("unified_action_contract_test")
	_check(
		bool(effect_report.get("ok", false))
		and controller.session.writer.apply_result(
			investigation, controller.session.stores
		)
		and not controller.session.stores["investigation_store"].get_lead(
			"lead.contract.protocol"
		).is_empty(),
		"9. 调查 Effect 保留内部 create 操作并经统一 Writer 落地"
	)
	_finish()


func _find_duty(options: Array, duty_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("duty_id", "")) == duty_id:
			return option
	return {}


func _has_modifier_source(
		option: Dictionary, source_kind: String, source_label: String
) -> bool:
	for modifier: Dictionary in option.get("modifier_explanations", []):
		if (
			str(modifier.get("source_kind", "")) == source_kind
			and str(modifier.get("source_label", "")) == source_label
			and str(modifier.get("reason", "")) != ""
		):
			return true
	return false


func _requirement_mode(option: Dictionary) -> String:
	var requirements: Array = option.get("requirements", [])
	if requirements.is_empty():
		return ""
	return str((requirements[0] as Dictionary).get("mode", ""))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 UNIFIED ACTION CONTRACT PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 UNIFIED ACTION CONTRACT RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 UNIFIED ACTION CONTRACT FAIL] " + failure)
	print(
		"[V5 UNIFIED ACTION CONTRACT RESULT] FAIL (%d)" % failures.size()
	)
	quit(1)
