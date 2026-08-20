extends RefCounted
class_name V5LiveLocationViewModel

const LifeStageTransitionServiceModel = preload(
	"res://scripts/sim/save/life_stage_transition_service.gd"
)

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const SURFACE_FACT_REQUIREMENTS := {
	"old_chen_shop_to_abandoned_granary": [
		{"fact_type": "actor_read_object", "target_id": "old_chen_shop_price_notice"},
		{"fact_type": "actor_inspected_trace", "target_id": "gray_grain_powder"},
	],
	"granary_rotten_floor_entry": [
		{"fact_type": "actor_inspected_trace", "target_id": "abandoned_granary_mold_trace"},
	],
	"north_quay_flooded_stack_search": [
		{"fact_type": "actor_read_object", "target_id": "north_quay_visiting_rules"},
		{"fact_type": "actor_inspected_trace", "target_id": "north_quay_tide_marks"},
	],
	"mist_salt_well_second_ring_descent": [
		{"fact_type": "actor_read_object", "target_id": "mist_salt_well_warning_stone"},
		{"fact_type": "actor_inspected_trace", "target_id": "mist_salt_well_mouth_crust"},
	],
	"mist_salt_well_to_north_quay_record_house": [
		{"fact_type": "actor_inspected_trace", "target_id": "mist_salt_well_mouth_crust"},
	],
}

var session: Variant = null
var start_result: Dictionary = {}
var latest_result: Dictionary = {}
var action_history: Array[Dictionary] = []
var latest_event_type: String = ""


func _init(source_session: Variant = null) -> void:
	session = source_session


func start(options: Dictionary = {}) -> Dictionary:
	if session == null:
		session = SimSessionModel.new()
	action_history.clear()
	latest_result = {}
	latest_event_type = ""
	var start_options := options.duplicate(true)
	if (
		not start_options.has("challenge_seed_override")
		and not "--script" in OS.get_cmdline_args()
	):
		var runtime_rng := RandomNumberGenerator.new()
		runtime_rng.randomize()
		start_options["challenge_seed_override"] = int(runtime_rng.randi())
	start_result = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, start_options
	)
	return start_result.duplicate(true)


func is_ready() -> bool:
	return session != null and session.is_ready()


func build_life_stage_transition() -> Dictionary:
	if not is_ready():
		return {}
	var playtest: Dictionary = _playtest_view(session.get_snapshot())
	if not bool(playtest.get("completed", false)):
		return {}
	return LifeStageTransitionServiceModel.new().build_player_transition(
		session
	)


func perform_action(action_id: String) -> Dictionary:
	latest_event_type = "player_action"
	if not is_ready():
		latest_result = {
			"success": false,
			"error": "session_not_initialized",
			"action_id": action_id,
		}
		return latest_result.duplicate(true)

	var option := _find_action_option(action_id)
	latest_result = session.execute_action(action_id, {
		"source": "v5_live_location_surface",
	})
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"action_id": action_id,
			"label": str(option.get("label", "采取行动")),
			"contract_status": str(latest_result.get("contract_status", "")),
			"narrative": _result_narrative(latest_result),
		})
	return latest_result.duplicate(true)


func advance_time(hours: int = 1) -> Dictionary:
	latest_event_type = "world_tick"
	if not is_ready():
		latest_result = {
			"success": false,
			"error_reason": "session_not_initialized",
		}
		return latest_result.duplicate(true)

	latest_result = session.advance_time(hours, "after_short_wait", {
		"label": "在老陈铺子等待一小时",
		"source": "v5_live_location_surface",
	})
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"event_type": "world_tick",
			"label": "等待一小时",
			"triggered_count": _world_change_count(latest_result),
			"narrative": _tick_narrative(latest_result),
		})
	return latest_result.duplicate(true)


func wait_until_north_quay_ferry() -> Dictionary:
	latest_event_type = "ferry_wait"
	if not is_ready():
		latest_result = {
			"success": false,
			"error_reason": "session_not_initialized",
		}
		return latest_result.duplicate(true)

	if not _should_offer_north_quay_ferry_wait(session.get_snapshot()):
		latest_result = {
			"success": false,
			"error_reason": "ferry_wait_not_available",
		}
		return latest_result.duplicate(true)

	var hours := _hours_until_north_quay_ferry()
	latest_result = session.advance_time(hours, "wait_for_north_quay_ferry", {
		"label": "在铺里歇到北埠早船",
		"source": "v5_live_location_surface",
	})
	latest_result["waited_hours"] = hours
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"event_type": "ferry_wait",
			"label": "在铺里歇到北埠早船",
			"triggered_count": _world_change_count(latest_result),
			"narrative": _ferry_wait_narrative(),
		})
	return latest_result.duplicate(true)


func perform_travel(route_id: String) -> Dictionary:
	latest_event_type = "travel"
	if not is_ready():
		latest_result = {
			"success": false,
			"error": "session_not_initialized",
			"route_id": route_id,
		}
		return latest_result.duplicate(true)

	var option := _find_travel_option(route_id)
	latest_result = session.travel(route_id, {
		"tick_metadata": {
			"source": "v5_live_location_surface",
		},
	})
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"event_type": "travel",
			"route_id": route_id,
			"label": str(option.get("label", "前往新的地点")),
			"narrative": _result_narrative(latest_result),
		})
	return latest_result.duplicate(true)


func perform_challenge(
		option_id: String,
		metadata: Dictionary = {}
) -> Dictionary:
	latest_event_type = "challenge"
	if not is_ready():
		latest_result = {
			"success": false,
			"error": "session_not_initialized",
			"option_id": option_id,
		}
		return latest_result.duplicate(true)

	var option := _find_challenge_option(option_id)
	var execution_metadata := {
		"source": "v5_live_location_surface",
	}
	execution_metadata.merge(metadata, true)
	latest_result = session.execute_challenge_option(
		option_id,
		execution_metadata
	)
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"event_type": "challenge",
			"option_id": option_id,
			"label": str(option.get("label", "面对眼前的危险")),
			"outcome": str(latest_result.get("outcome", "")),
			"narrative": _result_narrative(latest_result),
		})
	return latest_result.duplicate(true)


func perform_combat_encounter(
		option_id: String,
		metadata: Dictionary = {}
) -> Dictionary:
	latest_event_type = "combat_encounter"
	if not is_ready():
		latest_result = {
			"success": false,
			"error": "session_not_initialized",
			"option_id": option_id,
		}
		return latest_result.duplicate(true)

	var option := _find_combat_encounter_option(option_id)
	var execution_metadata := {
		"source": "v5_live_location_surface",
	}
	execution_metadata.merge(metadata, true)
	latest_result = session.execute_combat_encounter_option(
		option_id, execution_metadata
	)
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"event_type": "combat_encounter",
			"option_id": option_id,
			"label": str(option.get("label", "处理眼前的遭遇")),
			"outcome": str(latest_result.get("outcome", "")),
			"narrative": _result_narrative(latest_result),
		})
	return latest_result.duplicate(true)


func perform_return_echo(option_id: String) -> Dictionary:
	latest_event_type = "return_echo"
	if not is_ready():
		latest_result = {
			"success": false,
			"error": "session_not_initialized",
			"option_id": option_id,
		}
		return latest_result.duplicate(true)

	var option := _find_return_echo_option(option_id)
	latest_result = session.execute_return_echo_option(option_id, {
		"source": "v5_live_location_surface",
	})
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"event_type": "return_echo",
			"option_id": option_id,
			"label": str(option.get("label", "请人辨认旧物")),
			"narrative": _result_narrative(latest_result),
		})
	return latest_result.duplicate(true)


func perform_investigation(option_id: String) -> Dictionary:
	latest_event_type = "investigation"
	if not is_ready():
		latest_result = {
			"success": false,
			"error": "session_not_initialized",
			"option_id": option_id,
		}
		return latest_result.duplicate(true)

	var option := _find_investigation_option(option_id)
	latest_result = session.execute_investigation_option(option_id, {
		"source": "v5_live_location_surface",
	})
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"event_type": "investigation",
			"option_id": option_id,
			"option_type": str(
				latest_result.get("option_type", "")
			),
			"label": str(option.get("label", "处理调查方向")),
			"narrative": _result_narrative(latest_result),
		})
	return latest_result.duplicate(true)


func build_view_data() -> Dictionary:
	if not is_ready():
		return {
			"ready": false,
			"error_text": "局面暂时无法载入。",
			"actions": [],
		}

	var snapshot: Variant = session.get_snapshot()
	var location: Dictionary = snapshot.location
	var visible_people: Array[Dictionary] = []
	var visible_observations: Array[Dictionary] = []
	var visible_entity_ids: Array[String] = []
	for entity: Dictionary in snapshot.get_visible_entities():
		var row := _entity_row(entity, snapshot)
		visible_entity_ids.append(str(entity.get("id", "")))
		if str(entity.get("type", "")) == "person":
			visible_people.append(row)
		else:
			visible_observations.append(row)
	var encounter_options: Array = session.get_combat_encounter_options()
	if not encounter_options.is_empty():
		var preview: Dictionary = (
			(encounter_options[0] as Dictionary).get("preview", {})
		)
		var enemy_id := str((preview.get(
			"enemy_observation", {}
		) as Dictionary).get("entity_id", ""))
		var enemy_entity: Dictionary = snapshot.get_entity(enemy_id)
		if enemy_id != "" and enemy_id not in visible_entity_ids:
			var enemy_row := _entity_row(enemy_entity, snapshot)
			if str(enemy_entity.get("type", "")) == "person":
				visible_people.append(enemy_row)
			else:
				visible_observations.append(enemy_row)
	var observation_ids: Array[String] = []
	for observation: Dictionary in visible_observations:
		observation_ids.append(str(observation.get("id", "")))
	for trace: Dictionary in snapshot.get_visible_traces():
		var trace_id := str(trace.get("trace_id", ""))
		if trace_id == "" or trace_id in observation_ids:
			continue
		visible_observations.append(_trace_row(trace))
		observation_ids.append(trace_id)
	for rumor: Dictionary in snapshot.get_visible_rumors():
		var rumor_id := str(rumor.get("rumor_id", ""))
		if rumor_id == "" or rumor_id in observation_ids:
			continue
		visible_observations.append(_rumor_row(rumor))
		observation_ids.append(rumor_id)

	return {
		"ready": true,
		"location": {
			"id": str(location.get("id", "")),
			"title": str(location.get("display_name", "未知地点")),
			"description": str(
				location.get("description", "你停下来观察眼前的地方。")
			),
			"context": _location_context(location, snapshot),
		},
		"playtest": _playtest_view(snapshot),
		"player": _player_view(snapshot),
		"time": _time_view(),
		"region_status": _region_status_rows(snapshot),
		"visible_people": visible_people,
		"visible_observations": visible_observations,
		"actions": _action_rows(),
		"risk": _risk_view(),
		"travel_options": _travel_rows(),
		"knowledge": _knowledge_rows(snapshot),
		"investigation": _investigation_view(snapshot),
		"chronicle": _chronicle_view(snapshot),
		"feedback": _feedback_view(),
		"history": action_history.duplicate(true),
		"world_log_count": session.get_world_log_entries().size(),
	}


func _playtest_view(snapshot: Variant) -> Dictionary:
	var location_id := str(snapshot.location.get("id", ""))
	if _has_fact(snapshot, "settlement_network_generated"):
		var current_settlement_id := _current_settlement_id(snapshot)
		var current_name := _entity_name(current_settlement_id)
		var trade_seen := _has_fact(snapshot, "settlement_trade_shipment")
		var absorption_seen := _has_fact(snapshot, "migrant_absorption_evaluated")
		return {
			"mode": "generated_settlement_network",
			"stage": 3 if absorption_seen else (2 if trade_seen else 1),
			"stage_count": 3,
			"completed": false,
			"failed": false,
			"title": "观察%s如何依赖邻近聚落" % current_name,
			"summary": (
				"迁徙家庭正在面对真实住房容量与职业空缺。查看区域状态，可以确认他们已经入住就业，还是仍需临时安置。"
				if absorption_seen
				else (
					"道路已经产生真实货流。查看本地储备与最近运输，也可以沿区域道路前往另一个聚落比较资源和人口压力。"
					if trade_seen
					else "三个聚落拥有不同资源和承载力。等待会让居民生产、消耗储备，并让富余物资沿道路流向短缺地点。"
				)
			),
			"hint": "连续短缺不会触发预写剧情，而会提高迁离压力并最终促成家庭搬迁。",
		}
	if _has_fact(snapshot, "settlement_generated"):
		var at_hub: bool = (
			"public_space" in (snapshot.location.get("tags", []) as Array)
		)
		return {
			"mode": "generated_settlement",
			"stage": 1 if at_hub else 2,
			"stage_count": 3,
			"completed": false,
			"failed": false,
			"title": (
				"认识这座生成聚落"
				if at_hub
				else "查看产业如何占据地点"
			),
			"summary": (
				"聚落的规模、产业和道路来自地形、资源与交通；资源水位会随生产与恢复继续变化。选择一处实际形成的设施前往。"
				if at_hub
				else "这里的设施会消耗真实资源库存；水位过低会停工并改变聚落压力。沿内部道路可以返回集地。"
			),
			"hint": "等待会让居民生产、消耗资源，也让可靠资源逐步恢复。",
		}
	if _has_fact(
			snapshot,
			"actor_traveled_route",
			"route_id",
			"mist_salt_well_to_north_quay_record_house"
	):
		return {
			"stage": 5,
			"stage_count": 5,
			"completed": true,
			"failed": false,
			"title": "试玩目标完成",
			"summary": "你从湖湾镇的粮仓旧事追到了雾盐旧井，并带着这段亲历返回北埠。",
			"hint": "可继续观察，也可重新开始。",
		}
	if location_id == "mist_salt_well":
		var inspected_well_mouth := _has_fact(
			snapshot,
			"actor_inspected_trace",
			"target_id",
			"mist_salt_well_mouth_crust"
		)
		var read_warning := _has_fact(
			snapshot,
			"actor_read_object",
			"target_id",
			"mist_salt_well_warning_stone"
		)
		return {
			"stage": 5,
			"stage_count": 5,
			"completed": false,
			"title": "从旧井带回一次亲历",
			"summary": (
				"先试探盐壳白丝对水的反应，确认怎样安全封存水囊。"
				if not inspected_well_mouth
				else (
					"返程已经开放。读过旧警石后，你也可以承担不可逆后果，深入第二环。"
					if not read_warning
					else "带着现有发现返回北埠，或承担不可逆后果深入第二环。"
				)
			),
			"hint": "返回不会抹掉发现；深入可能留下长期雾盐回响。",
		}
	if _has_challenge_outcome(
			snapshot,
			"north_quay_flooded_stack_search",
			"failure"
	):
		return {
			"stage": 3,
			"stage_count": 5,
			"completed": false,
			"failed": true,
			"title": "水浸档案没能取出",
			"summary": "这次追查停在北埠封存层。可以继续观察后果，或重新开始试玩。",
			"hint": "下次先借罩灯和油布。",
		}
	if _has_challenge_outcome(
			snapshot,
			"granary_rotten_floor_entry",
			"failure"
	):
		return {
			"stage": 1,
			"stage_count": 5,
			"completed": false,
			"failed": true,
			"title": "粮仓里的线索断了",
			"summary": "这次探索留下了伤势，却没带出铜牌。可以返回老陈铺观察后果。",
			"hint": "下次先检查朽木地板。",
		}
	if _has_fact(
			snapshot,
			"lu_huai_recorded_departure_for_mist_salt_well"
	):
		return {
			"stage": 4,
			"stage_count": 5,
			"completed": false,
			"title": "准备前往雾盐旧井",
			"summary": (
				"带上防盐面罩与往返口粮，沿北岸前往雾盐旧井。"
				if _has_fact(
					snapshot,
					"actor_prepared_mist_salt_expedition"
				)
				else "在北埠帮闻简晒卷，换取防盐面罩与往返口粮。"
			),
			"hint": "远行会推进世界时间。",
		}
	if (
		location_id == "north_quay_record_house"
		or _has_fact(
			snapshot,
			"actor_found_public_granary_archive_reference"
		)
	):
		var read_archive_rules := _has_fact(
			snapshot,
			"actor_read_object",
			"target_id",
			"north_quay_visiting_rules"
		)
		var inspected_tide_marks := _has_fact(
			snapshot,
			"actor_inspected_trace",
			"target_id",
			"north_quay_tide_marks"
		)
		return {
			"stage": 3,
			"stage_count": 5,
			"completed": false,
			"title": "追查陆槐最后的记录",
			"summary": (
				(
					"先读查档规条，再检查廊柱潮线；两条信息都确认后，封存层入口才会开放。"
					if not read_archive_rules and not inspected_tide_marks
					else (
						"再检查廊柱上的旧潮线，确认水位和落脚处。"
						if not inspected_tide_marks
						else (
							"再读受潮的查档规条，确认封存层的禁令和时辰。"
							if not read_archive_rules
							else "封存层入口已经开放。可以先借罩灯和油布，也可以直接冒险进入。"
						)
					)
				)
				if location_id == "north_quay_record_house"
				else "等到白天乘摆渡前往北埠旧档房。"
			),
			"hint": "危险行动可以先准备。",
		}
	if (
		_has_fact(snapshot, "actor_discovered_item")
		or _has_fact(
			snapshot,
			"lake_town_public_granary_sealed_after_spoiled_grain"
		)
	):
		return {
			"stage": 2,
			"stage_count": 5,
			"completed": false,
			"title": "让旧铜牌开口",
			"summary": (
				"和陈米翻查陈家旧税契，确认公仓封存记录。"
				if location_id == "old_chen_shop"
				else "把验粮铜牌带回老陈铺子，请陈米辨认。"
			),
			"hint": "事实与物品会打开后续。",
		}
	return {
		"stage": 1,
		"stage_count": 5,
		"completed": false,
		"title": "调查废弃粮仓的异常",
		"summary": _stage_one_summary(snapshot, location_id),
		"hint": (
			"确认门槛痕迹后，粮仓入口和准备选择会开放。"
			if location_id == "abandoned_granary"
			else "读完告示并检查粮粉后，镇外路线会开放。"
		),
	}


func _stage_one_summary(snapshot: Variant, location_id: String) -> String:
	if location_id == "abandoned_granary":
		if not _has_fact(
			snapshot,
			"actor_inspected_trace",
			"target_id",
			"abandoned_granary_mold_trace"
		):
			return "先检查门槛上的霉斑，判断最近搬运粮袋的人如何避开朽木地板。"
		return "入口已经开放。先试探地板会降低风险，也可以直接踏进粮仓深处。"
	var read_notice := _has_fact(
		snapshot,
		"actor_read_object",
		"target_id",
		"old_chen_shop_price_notice"
	)
	var inspected_powder := _has_fact(
		snapshot,
		"actor_inspected_trace",
		"target_id",
		"gray_grain_powder"
	)
	if not read_notice and not inspected_powder:
		return "先读涨价告示，再检查柜脚旁的灰白粮粉，判断缺粮和异常粮袋是否来自同一条路。"
	if not read_notice:
		return "粮粉指向铺外；再读涨价告示，确认哪条运粮路线出了问题。"
	if not inspected_powder:
		return "告示说明北路断粮；再检查柜脚旁的灰白粮粉，确认异常粮袋的去向。"
	return "两条现场信息都指向镇外。前往废弃粮仓的路线已经开放。"


func _has_fact(
		snapshot: Variant,
		fact_type: String,
		field: String = "",
		value: String = ""
) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) != fact_type:
			continue
		if field == "" or str(fact.get(field, "")) == value:
			return true
	return false


func _has_challenge_outcome(
		snapshot: Variant,
		challenge_id: String,
		outcome: String
) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "actor_attempted_challenge"
			and str(fact.get("challenge_id", "")) == challenge_id
			and str(fact.get("outcome", "")) == outcome
		):
			return true
	return false


func _action_rows() -> Array:
	var rows: Array[Dictionary] = []
	var snapshot: Variant = session.get_snapshot()
	var combat_rows := _combat_action_rows()
	if not combat_rows.is_empty():
		return combat_rows
	var ambient_trace_ids := _ambient_trace_ids(snapshot)
	var surfaced_ambient_trace_count := 0
	for option: Dictionary in session.get_investigation_options():
		var action_type := str(
			option.get("action_type", "investigation")
		)
		rows.append({
			"action_id": str(option.get("option_id", "")),
			"investigation_option_id": str(
				option.get("option_id", "")
			),
			"event_type": "investigation",
			"label": str(option.get("label", "处理调查方向")),
			"action_type": action_type,
			"kind": _action_kind(action_type),
			"hint": str(option.get("hint", "")),
			"can_execute": bool(option.get("can_execute", false)),
		})
	for option: Dictionary in session.get_action_options():
		var action_type := str(option.get("action_type", "normal"))
		var target_id := str(option.get("target_id", ""))
		if target_id in ambient_trace_ids:
			if surfaced_ambient_trace_count >= 3:
				continue
			surfaced_ambient_trace_count += 1
		var can_execute := bool(option.get("can_execute", true))
		rows.append({
			"action_id": str(option.get("action_id", "")),
			"event_type": "player_action",
			"label": _action_label(option, can_execute),
			"action_type": action_type,
			"kind": _action_kind(action_type),
			"hint": _action_hint(option),
			"can_execute": can_execute,
		})
	for option: Dictionary in session.get_challenge_options():
		if not _surface_requirements_met(
			str(option.get("challenge_id", "")),
			snapshot
		):
			continue
		var action_type := str(option.get("action_type", "danger"))
		rows.append({
			"action_id": str(option.get("option_id", "")),
			"challenge_option_id": str(option.get("option_id", "")),
			"event_type": "challenge",
			"label": str(option.get("label", "面对眼前的危险")),
			"action_type": action_type,
			"kind": _action_kind(action_type),
			"hint": _challenge_action_hint(option),
			"can_execute": bool(option.get("can_execute", false)),
		})
	for option: Dictionary in session.get_return_echo_options():
		rows.append({
			"action_id": str(option.get("option_id", "")),
			"return_echo_option_id": str(
				option.get("option_id", "")
			),
			"event_type": "return_echo",
			"label": str(option.get("label", "请人辨认旧物")),
			"action_type": "relic",
			"kind": _action_kind("relic"),
			"hint": str(option.get("hint", "")),
			"can_execute": bool(option.get("can_execute", false)),
		})
	if _should_offer_north_quay_ferry_wait(snapshot):
		rows.append({
			"action_id": "wait_until_north_quay_ferry",
			"event_type": "ferry_wait",
			"label": "在铺里歇到北埠早船",
			"action_type": "life",
			"kind": _action_kind("life"),
			"hint": "一次推进到下一个 06:00；期间世界状态照常变化。",
			"can_execute": true,
		})
	return rows


func _combat_action_rows() -> Array:
	var rows: Array[Dictionary] = []
	for option: Dictionary in session.get_combat_encounter_options():
		var preview: Dictionary = option.get("preview", {})
		var approach_id := str(option.get("approach_id", ""))
		var approach_label := _combat_approach_label(approach_id)
		rows.append({
			"action_id": str(option.get("option_id", "")),
			"combat_option_id": str(option.get("option_id", "")),
			"event_type": "combat_encounter",
			"label": "[%s·%s] %s" % [
				approach_label,
				_required_roll_text(int(preview.get("required_roll", 7))),
				str(option.get("label", "处理遭遇")),
			],
			"action_type": str(option.get("action_type", "danger")),
			"kind": approach_label,
			"hint": _combat_action_hint(option),
			"can_execute": bool(option.get("can_execute", false)),
		})
	return rows


func _ambient_trace_ids(snapshot: Variant) -> Array:
	var rows: Array = []
	for trace: Dictionary in snapshot.get_visible_traces():
		if str(trace.get("actor_id", "")) == "":
			continue
		var trace_id := str(trace.get("id", trace.get("trace_id", "")))
		if trace_id != "":
			rows.append(trace_id)
	return rows


func _should_offer_north_quay_ferry_wait(snapshot: Variant) -> bool:
	if str(snapshot.location.get("id", "")) != "old_chen_shop":
		return false
	if not _has_fact(
		snapshot,
		"actor_read_object",
		"target_id",
		"old_chen_public_granary_tax_deed"
	):
		return false
	var hour := int(session.get_time_summary().get("hour", 0))
	return hour < 6 or hour >= 18


func _hours_until_north_quay_ferry() -> int:
	var hour := int(session.get_time_summary().get("hour", 0))
	if hour < 6:
		return 6 - hour
	return 24 - hour + 6


func _risk_view() -> Dictionary:
	var combat_risk := _combat_risk_view()
	if bool(combat_risk.get("active", false)):
		return combat_risk
	var options: Array = session.get_challenge_options()
	var snapshot: Variant = session.get_snapshot()
	if options.is_empty():
		return {"active": false}
	var attempt: Dictionary = {}
	var preparation: Dictionary = {}
	for option: Dictionary in options:
		if not _surface_requirements_met(
			str(option.get("challenge_id", "")),
			snapshot
		):
			continue
		if str(option.get("option_type", "")) == "attempt":
			attempt = option
		elif str(option.get("option_type", "")) == "prepare":
			preparation = option
	if attempt.is_empty():
		return {"active": false}
	var prepared := bool(attempt.get("preparation_applied", false))
	return {
		"active": true,
		"title": "眼前的风险　%s" % str(attempt.get("risk_label", "未知")),
		"description": str(attempt.get("risk_description", "")),
		"check_text": str(attempt.get("check_text", "")),
		"prepared": prepared,
		"preparation_text": (
			"准备已经完成，检定将获得 +%d。"
			% int(attempt.get("preparation_bonus", 0))
			if prepared
			else (
				"可先准备：检定 +%d；也可返回。"
				% int(preparation.get("preparation_bonus", 0))
				if not preparation.is_empty()
				else "可以直接尝试，也可以返回。"
			)
		),
		"failure_hint": str(attempt.get("failure_hint", "")),
	}


func _combat_risk_view() -> Dictionary:
	var options: Array = session.get_combat_encounter_options()
	if options.is_empty():
		return {"active": false}
	var first: Dictionary = options[0]
	var preview: Dictionary = first.get("preview", {})
	var enemy: Dictionary = preview.get("enemy_observation", {})
	var selection_context: Dictionary = first.get("selection_context", {})
	var features: Array[String] = []
	for feature: Variant in enemy.get("observable_features", []):
		features.append("• %s" % str(feature))
	var checks: Array[String] = []
	for option: Dictionary in options:
		var option_preview: Dictionary = option.get("preview", {})
		checks.append("%s %s" % [
			_combat_approach_label(str(option.get("approach_id", ""))),
			_required_roll_text(int(option_preview.get("required_roll", 7))),
		])
	return {
		"active": true,
		"title": "眼前的遭遇　%s" % str(enemy.get("danger_label", "未知")),
		"description": "%s\n%s\n%s" % [
			str(first.get("encounter_description", "")),
			str(enemy.get("display_name", "未知对手")),
			"\n".join(features),
		],
		"check_text": "d6 检定　%s" % "　/　".join(checks),
		"prepared": true,
		"preparation_text": (
			"地点、地区状态与在场实体筛出 %d 个可用候选；本次选择已锁定并会随存档保留。\n当前装备与伤势已经计入每个选择的有效数值。"
			% maxi(int(selection_context.get(
				"eligible_candidate_count", 1
			)), 1)
			if not selection_context.is_empty()
			else "当前装备与伤势已经计入每个选择的有效数值。"
		),
		"failure_hint": "选择会立刻推进 1 小时并只结算一次；失败会留下明确代价，但不会立即死亡。",
	}


func _travel_rows() -> Array:
	if not session.get_combat_encounter_options().is_empty():
		return []
	var rows: Array[Dictionary] = []
	var snapshot: Variant = session.get_snapshot()
	for option: Dictionary in session.get_travel_options():
		if not _surface_requirements_met(
			str(option.get("route_id", "")),
			snapshot
		):
			continue
		var hours := int(option.get("hours", 0))
		var food_cost := int(option.get("food_cost", 0))
		var can_travel := bool(option.get("can_travel", false))
		var cost_text := "%d 小时" % hours
		if food_cost > 0:
			cost_text += " / %d 食物" % food_cost
		var blocked_reason := str(option.get("blocked_reason", ""))
		var hint := "旅行会推进世界时间，沿途的事情也会继续发展。"
		if blocked_reason == "insufficient_food":
			hint = "随身食物不足，暂时无法走这条路。"
		elif blocked_reason == "missing_required_item":
			hint = str(
				option.get(
					"access_hint",
					"缺少这段远行要求的防护装备。"
				)
			)
		elif blocked_reason == "outside_access_window":
			hint = str(
				option.get(
					"access_hint",
					"这条路线当前还没有开放。"
				)
			)
		rows.append({
			"route_id": str(option.get("route_id", "")),
			"destination_name": str(option.get("destination_name", "未知地点")),
			"label": "%s　%s" % [
				str(option.get("label", "前往新的地点")),
				cost_text,
			],
			"hours": hours,
			"food_cost": food_cost,
			"can_travel": can_travel,
			"hint": hint,
		})
	return rows


func _surface_requirements_met(key: String, snapshot: Variant) -> bool:
	var requirements: Array = SURFACE_FACT_REQUIREMENTS.get(key, [])
	for requirement: Dictionary in requirements:
		if not _has_fact(
			snapshot,
			str(requirement.get("fact_type", "")),
			"target_id",
			str(requirement.get("target_id", ""))
		):
			return false
	return true


func _entity_row(entity: Dictionary, snapshot: Variant) -> Dictionary:
	var states: Dictionary = entity.get("states", {})
	var entity_type := str(entity.get("type", ""))
	return {
		"id": str(entity.get("id", "")),
		"name": str(entity.get("display_name", "未命名")),
		"description": str(entity.get("description", "")),
		"state_text": (
			_person_state_text(states)
			if entity_type == "person"
			else _object_state_text(entity, snapshot)
		),
	}


func _trace_row(trace: Dictionary) -> Dictionary:
	return {
		"id": str(trace.get("trace_id", "")),
		"name": str(trace.get("display_name", trace.get("title", "现场痕迹"))),
		"description": str(trace.get("description", "这里留下了此前行动的痕迹。")),
		"state_text": "此前行动留下的现场痕迹",
	}


func _rumor_row(rumor: Dictionary) -> Dictionary:
	return {
		"id": str(rumor.get("rumor_id", "")),
		"name": "传闻：%s" % str(rumor.get("title", "附近发生过一件事")),
		"description": str(rumor.get(
			"text_hint",
			rumor.get("summary", "这句话正在此地流传。")
		)),
		"state_text": "在此地流传",
	}


func _player_view(snapshot: Variant) -> Dictionary:
	var role := str(snapshot.get_player_value("role", "traveler"))
	var role_label := _role_label(role)
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) != "settlement_generated":
			continue
		role_label = "途经%s的旅人" % str(fact.get(
			"settlement_name", "这座聚落"
		))
		break
	var strength := int(snapshot.get_player_value("strength", 0))
	var dexterity := int(snapshot.get_player_value("dexterity", 0))
	var wisdom := int(snapshot.get_player_value("wisdom", 0))
	var charisma := int(snapshot.get_player_value("charisma", 0))
	var constitution := int(snapshot.get_player_value("constitution", 0))
	var perception := int(snapshot.get_player_value("perception", 0))
	var health := int(snapshot.get_player_value("health", 100))
	var fatigue := int(snapshot.get_player_value("fatigue", 0))
	var injury := str(snapshot.get_player_value("injury", "none"))
	var mist_salt_echo := str(
		snapshot.get_player_value("mist_salt_echo", "none")
	)
	var item_names: Array[String] = []
	for item: Dictionary in snapshot.get_player_items():
		item_names.append(_item_display_text(item))
	var long_term_line := ""
	if mist_salt_echo != "none":
		long_term_line = "\n长期痕迹　%s" % _mist_salt_echo_label(
			mist_salt_echo
		)
	return {
		"title": "无名旅人",
		"role": role_label,
		"food_count": int(snapshot.get_player_value("food_count", 0)),
		"strength": strength,
		"dexterity": dexterity,
		"wisdom": wisdom,
		"charisma": charisma,
		"constitution": constitution,
		"perception": perception,
		"health": health,
		"fatigue": fatigue,
		"injury": injury,
		"mist_salt_echo": mist_salt_echo,
		"items": item_names,
		"summary": "身份　%s%s\n力量 %d　敏捷 %d　智慧 %d\n魅力 %d　体质 %d　感知 %d\n食物　%d 份　健康　%d　疲劳　%d / 10\n伤势　%s\n随身物品　%s" % [
			role_label,
			long_term_line,
			strength,
			dexterity,
			wisdom,
			charisma,
			constitution,
			perception,
			int(snapshot.get_player_value("food_count", 0)),
			health,
			fatigue,
			_injury_label(injury),
			"、".join(item_names) if not item_names.is_empty() else "无",
		],
	}


func _region_status_rows(snapshot: Variant) -> Array:
	var rows: Array[Dictionary] = []
	var pressure_rows: Array[Dictionary] = []
	var current_settlement_id := _current_settlement_id(snapshot)
	var settlement_state: Dictionary = {}
	if current_settlement_id != "":
		for key: String in [
			"food_pressure", "resource_strain", "migration_tendency"
		]:
			settlement_state[key] = snapshot.get_entity_state(
				current_settlement_id, key, "low"
			)
	var sources := [
		[
			"food_pressure",
			settlement_state if not settlement_state.is_empty() else snapshot.region_state,
		],
		["public_order", snapshot.region_state],
		["settlement_isolation", snapshot.region_state],
		[
			"resource_strain",
			settlement_state if not settlement_state.is_empty() else snapshot.region_state,
		],
		[
			"migration_tendency",
			settlement_state if not settlement_state.is_empty() else snapshot.region_state,
		],
		["flood_risk", snapshot.region_state],
		["market_order", snapshot.institution],
		["local_guard_attention", snapshot.institution],
	]
	for source: Array in sources:
		var key := str(source[0])
		var values := source[1] as Dictionary
		if not values.has(key):
			continue
		pressure_rows.append({
			"key": key,
			"label": _status_label(key),
			"value": _state_value_label(str(values.get(key, ""))),
			"detail": _status_detail(key, str(values.get(key, ""))),
		})
	var at_hub := "public_space" in (
		snapshot.location.get("tags", []) as Array
	)
	var location_id := str(snapshot.location.get("id", ""))
	var network_rows := _settlement_network_rows(
		snapshot, current_settlement_id
	)
	if current_settlement_id != "":
		var capacity := _settlement_capacity(current_settlement_id)
		var pressure_days := int(snapshot.get_entity_state(
			current_settlement_id, "migration_pressure_days", 0
		))
		var neighbor_summary := "无"
		var organization_summary := "尚未形成"
		var recent_summary := "尚无跨聚落变化"
		for network_row: Dictionary in network_rows:
			if str(network_row.get("key", "")) == "settlement_neighbors":
				neighbor_summary = str(network_row.get("value", "无"))
			elif str(network_row.get("key", "")) == "settlement_organizations":
				organization_summary = str(network_row.get("value", "尚未形成"))
			elif str(network_row.get("key", "")) in [
				"latest_settlement_trade", "latest_settlement_migration",
				"latest_settlement_absorption", "latest_organization_restaff",
				"latest_organization_action", "latest_organization_lifecycle",
			]:
				recent_summary = "%s：%s" % [
					str(network_row.get("label", "最近变化")),
					str(network_row.get("value", "")),
				]
		rows.append({
			"key": "settlement_population",
			"label": "聚落人口",
			"value": "%d / %d · 相邻聚落 %s" % [
				_settlement_population(current_settlement_id),
				capacity,
				neighbor_summary,
			],
			"detail": (
				"当地组织 %s；%s；连续迁离压力 %d 天。" % [
					organization_summary, recent_summary, pressure_days
				]
				if pressure_days > 0
				else "当地组织 %s；%s。" % [
					organization_summary, recent_summary
				]
			),
		})
	rows.append_array(network_rows)
	rows.append_array(pressure_rows)
	for stock: Dictionary in snapshot.get_resource_stocks():
		if (
			current_settlement_id != ""
			and str(stock.get("settlement_id", "")) != current_settlement_id
		):
			continue
		if not at_hub and str(stock.get("location_id", "")) != location_id:
			continue
		var capacity := float(stock.get("capacity", 0.0))
		var current := float(stock.get("current", 0.0))
		var percent := 0 if capacity <= 0.0 else int(round(
			current * 100.0 / capacity
		))
		var status := str(stock.get("status", "abundant"))
		rows.append({
			"key": "resource_stock:%s" % str(stock.get("stock_id", "")),
			"label": str(stock.get("label", "本地资源")),
			"value": "%d%% · %s" % [percent, _resource_status_label(status)],
			"detail": "当前 %.1f / %.1f；按现有可靠性每天约恢复 %.1f。%s" % [
				current,
				capacity,
				float(stock.get("recovery_per_hour", 0.0)) * 24.0,
				_resource_stock_use_text(stock),
			],
		})
	var shortage_pressure := 0
	for pressure: Dictionary in snapshot.get_pressures():
		if (
			str(pressure.get("scope_id", "")) == location_id
			and str(pressure.get("pressure_type", "")) == "market_shortage"
		):
			shortage_pressure += int(pressure.get("value", 0))
	if shortage_pressure > 0:
		rows.append({
			"key": "market_shortage",
			"label": "收铺迹象",
			"value": "加剧",
			"detail": "商铺开始提前关门，能买到粮食的时间正在缩短。",
		})
	return rows


func _current_settlement_id(snapshot: Variant) -> String:
	var direct_settlement_id := str(snapshot.location.get("settlement_id", ""))
	if direct_settlement_id != "":
		return direct_settlement_id
	var location_id := str(snapshot.location.get("id", ""))
	var runtime: Dictionary = session.get_settlement_network_summary()
	for site: Dictionary in runtime.get("sites", []):
		if str(site.get("hub_location_id", "")) == location_id:
			return str(site.get("settlement_id", ""))
	for stock: Dictionary in snapshot.get_resource_stocks():
		if str(stock.get("location_id", "")) == location_id:
			var stock_settlement_id := str(stock.get("settlement_id", ""))
			if stock_settlement_id != "":
				return stock_settlement_id
	for entity: Dictionary in snapshot.get_entities():
		if (
			str(entity.get("type", "")) == "institution"
			and "generated_settlement" in (entity.get("tags", []) as Array)
			and str(snapshot.get_entity_state(
				str(entity.get("id", "")), "location_id", ""
			)) == location_id
		):
			return str(entity.get("id", ""))
	return ""


func _settlement_capacity(settlement_id: String) -> int:
	for site: Dictionary in session.get_settlement_network_summary().get(
		"sites", []
	):
		if str(site.get("settlement_id", "")) == settlement_id:
			return int(site.get("resident_capacity", 0))
	return int(session.get_snapshot().get_entity_state(
		settlement_id, "resident_capacity", 0
	))


func _settlement_population(settlement_id: String) -> int:
	var population := 0
	var entity_store: Variant = session.stores.get("entity_store")
	var state_store: Variant = session.stores.get("state_store")
	if entity_store == null or state_store == null:
		return population
	for entity: Dictionary in entity_store.list_entity_rows():
		if (
			str(entity.get("type", "")) == "person"
			and str(state_store.get_state(
				str(entity.get("id", "")), "settlement_id", ""
			)) == settlement_id
		):
			population += 1
	return population


func _settlement_network_rows(
		snapshot: Variant,
		settlement_id: String
) -> Array:
	var rows: Array[Dictionary] = []
	var runtime: Dictionary = session.get_settlement_network_summary()
	if settlement_id == "" or runtime.is_empty():
		return rows
	var site_names: Dictionary = {}
	for site: Dictionary in runtime.get("sites", []):
		site_names[str(site.get("settlement_id", ""))] = str(site.get(
			"settlement_name", "相邻聚落"
		))
	var neighbor_names: Array[String] = []
	var neighbor_details: Array[String] = []
	for link: Dictionary in runtime.get("links", []):
		var neighbor_id := ""
		if str(link.get("settlement_a_id", "")) == settlement_id:
			neighbor_id = str(link.get("settlement_b_id", ""))
		elif str(link.get("settlement_b_id", "")) == settlement_id:
			neighbor_id = str(link.get("settlement_a_id", ""))
		if neighbor_id == "":
			continue
		var neighbor_name := str(site_names.get(neighbor_id, "相邻聚落"))
		neighbor_names.append(neighbor_name)
		neighbor_details.append("%s（%d 小时，日运力 %.1f）" % [
			neighbor_name,
			int(link.get("travel_hours", 0)),
			float(link.get("capacity_per_day", 0.0)),
		])
	if not neighbor_names.is_empty():
		rows.append({
			"key": "settlement_neighbors",
			"label": "相邻聚落",
			"value": "、".join(neighbor_names),
			"detail": "；".join(neighbor_details),
		})
	var organization_names: Array[String] = []
	var organization_details: Array[String] = []
	for entity: Dictionary in snapshot.get_entities():
		if (
			"generated_organization" not in (entity.get("tags", []) as Array)
			or str(entity.get("lifecycle_status", "active")) == "retired"
			or str(entity.get("settlement_id", "")) != settlement_id
		):
			continue
		var active_position_count := 0
		var vacant_position_count := 0
		var position_rows: Array[String] = []
		for position_value: Variant in entity.get("positions", []):
			if not position_value is Dictionary:
				continue
			var position: Dictionary = position_value
			var founding_holder_id := str(position.get("founding_holder_id", ""))
			var expected_role := "%s::%s" % [
				str(entity.get("id", "")), str(position.get("position_id", ""))
			]
			var current_holder_id := _organization_role_holder(
				snapshot, settlement_id, expected_role
			)
			var current_holder := (
				_entity_name(current_holder_id)
				if current_holder_id != ""
				else "空缺（原%s）" % _entity_name(founding_holder_id)
			)
			if current_holder.begins_with("空缺"):
				vacant_position_count += 1
			else:
				active_position_count += 1
			position_rows.append("%s：%s" % [
				str(position.get("label", "成员")),
				current_holder,
			])
		organization_names.append("%s · %s" % [
			(
				"任职 %d / 空缺 %d" % [
					active_position_count, vacant_position_count
				]
				if active_position_count > 0 and vacant_position_count > 0
				else (
					"空缺 %d" % vacant_position_count
					if vacant_position_count > 0
					else "任职 %d" % active_position_count
				)
			),
			str(entity.get("display_name", "地方组织")),
		])
		var last_response_summary := str(snapshot.get_entity_state(
			str(entity.get("id", "")), "last_response_summary", ""
		))
		organization_details.append("%s。%s%s" % [
			str(entity.get("goal", "协调当地事务")),
			"；".join(position_rows),
			(
				"\n最近行动：%s" % last_response_summary
				if last_response_summary != ""
				else ""
			),
		])
	if not organization_names.is_empty():
		rows.append({
			"key": "settlement_organizations",
			"label": "当地组织",
			"value": "、".join(organization_names),
			"detail": "\n".join(organization_details),
		})

	var facts: Array = snapshot.get_facts()
	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if str(fact.get("fact_type", "")) != "settlement_trade_shipment":
			continue
		var source_id := str(fact.get("source_settlement_id", ""))
		var destination_id := str(fact.get(
			"destination_settlement_id", ""
		))
		if settlement_id != source_id and settlement_id != destination_id:
			continue
		var incoming := settlement_id == destination_id
		rows.append({
			"key": "latest_settlement_trade",
			"label": "最近货流",
			"value": "%s %.1f 份%s" % [
				"运入" if incoming else "运出",
				float(fact.get("amount", 0.0)),
				_good_label(str(fact.get("good_id", "物资"))),
			],
			"detail": str(fact.get("summary", "一批物资沿道路完成运输。")),
		})
		break

	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if str(fact.get("fact_type", "")) != "household_migrated":
			continue
		var source_id := str(fact.get("source_settlement_id", ""))
		var destination_id := str(fact.get(
			"destination_settlement_id", ""
		))
		if settlement_id != source_id and settlement_id != destination_id:
			continue
		var incoming := settlement_id == destination_id
		rows.append({
			"key": "latest_settlement_migration",
			"label": "最近迁移",
			"value": "%s %d 人" % [
				"迁入" if incoming else "迁出",
				(fact.get("member_ids", []) as Array).size(),
			],
			"detail": str(fact.get("summary", "一户居民迁往了相邻聚落。")),
		})
		break

	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if (
			str(fact.get("fact_type", ""))
			!= "migrant_absorption_evaluated"
			or str(fact.get("destination_settlement_id", ""))
			!= settlement_id
		):
			continue
		var member_count := int(fact.get("member_count", 0))
		var reemployed_count := int(fact.get("reemployed_count", 0))
		var unresolved_count := int(fact.get("unresolved_job_count", 0))
		var housed := str(fact.get("housing_status", "")) == "housed"
		rows.append({
			"key": "latest_settlement_absorption",
			"label": "迁入安顿" if housed and unresolved_count == 0 else "吸纳压力",
			"value": (
				"%d 人入住 · %d 人就业" % [member_count, reemployed_count]
				if housed
				else "%d 人临时安置 · %d 人待就业" % [
					member_count, unresolved_count
				]
			),
			"detail": str(fact.get(
				"summary", "迁入家庭的住房与生计已经完成一次真实评估。"
			)),
		})
		break

	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if (
			str(fact.get("fact_type", ""))
			!= "organization_position_filled"
			or str(fact.get("settlement_id", "")) != settlement_id
		):
			continue
		rows.append({
			"key": "latest_organization_restaff",
			"label": "组织补位",
			"value": "%s · %s" % [
				_entity_name(str(fact.get("target_id", ""))),
				str(fact.get("position_label", "成员")),
			],
			"detail": str(fact.get(
				"summary", "当地组织从居民中补入一名新成员。"
			)),
		})
		break

	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		var fact_type := str(fact.get("fact_type", ""))
		if (
			fact_type not in [
				"organization_runtime_formed",
				"organization_effectiveness_evaluated",
				"organization_goal_changed",
				"organization_goal_reactivated",
				"organization_runtime_retired",
			]
			or str(fact.get("settlement_id", "")) != settlement_id
		):
			continue
		rows.append({
			"key": "latest_organization_lifecycle",
			"label": {
				"organization_runtime_formed": "组织成立",
				"organization_effectiveness_evaluated": "效能复盘",
				"organization_goal_changed": "目标转向",
				"organization_goal_reactivated": "目标恢复",
				"organization_runtime_retired": "组织退场",
			}.get(fact_type, "组织变化"),
			"value": _entity_name(str(fact.get("organization_id", ""))),
			"detail": str(fact.get(
				"summary", "当地压力改变了组织的生命周期。"
			)),
		})
		break

	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		var fact_type := str(fact.get("fact_type", ""))
		if (
			fact_type not in [
				"organization_local_provisions_transferred",
				"organization_trade_coordinated",
				"organization_route_patrolled",
			]
			or str(fact.get("settlement_id", "")) != settlement_id
		):
			continue
		rows.append({
			"key": "latest_organization_action",
			"label": {
				"organization_local_provisions_transferred": "组织调粮",
				"organization_trade_coordinated": "货路协调",
				"organization_route_patrolled": "道路巡守",
			}.get(fact_type, "组织行动"),
			"value": _entity_name(str(fact.get("organization_id", ""))),
			"detail": str(fact.get(
				"summary", "当地组织依据当前压力采取了行动。"
			)),
		})
		break
	return rows


func _organization_role_holder(
		_snapshot: Variant,
		settlement_id: String,
		expected_role: String
) -> String:
	for entity: Dictionary in session.stores[
		"entity_store"
	].list_entity_rows():
		if str(entity.get("type", "")) != "person":
			continue
		var entity_id := str(entity.get("id", ""))
		if (
			str(session.stores["state_store"].get_state(
				entity_id, "settlement_id", ""
			)) == settlement_id
			and str(session.stores["state_store"].get_state(
				entity_id, "institution_role", ""
			)) == expected_role
		):
			return entity_id
	return ""


func _good_label(good_id: String) -> String:
	return {
		"food": "食物",
		"fiber": "纤维",
		"salt": "盐",
	}.get(good_id, good_id)


func _knowledge_rows(snapshot: Variant) -> Array:
	var rows: Array[String] = []
	for fact: Dictionary in snapshot.get_facts():
		if fact.has("observed_by_player") and not bool(
			fact.get("observed_by_player", false)
		):
			continue
		var fact_type := str(fact.get("fact_type", ""))
		var target_name := str(fact.get("target_display_name", ""))
		if target_name == "":
			target_name = _entity_name(str(fact.get("target_id", "")))
		var text := _fact_text(fact_type, target_name, fact)
		if text not in rows:
			rows.append(text)
	if rows.is_empty():
		rows.append("你还没有确认任何值得记下的事实。")
	return rows


func _investigation_view(snapshot: Variant) -> Dictionary:
	var location_id := str(snapshot.location.get("id", ""))
	for lead: Dictionary in snapshot.get_open_investigation_leads():
		if str(lead.get("location_id", "")) != location_id:
			continue
		var deferred := (
			str(lead.get("disposition", "fresh")) == "deferred"
		)
		return {
			"active": true,
			"lead_id": str(lead.get("lead_id", "")),
			"title": str(lead.get("title", "调查方向")),
			"summary": str(
				lead.get(
					"deferred_summary" if deferred else "summary",
					""
				)
			),
			"status": "已搁置，仍可追查" if deferred else "等待决定",
			"deferred": deferred,
			"source_fact_count": (
				(lead.get("source_fact_ids", []) as Array).size()
			),
			"source_item_count": (
				(lead.get("source_item_ids", []) as Array).size()
			),
		}
	return {"active": false}


func _chronicle_view(snapshot: Variant) -> Dictionary:
	var entries: Array = snapshot.get_player_chronicle_entries()
	if entries.is_empty():
		return {"active": false}
	var entry: Dictionary = entries[entries.size() - 1]
	return {
		"active": true,
		"title": str(entry.get("title", "个人纪事")),
		"body": str(entry.get("body", "")),
		"source_fact_count": (
			(entry.get("source_fact_ids", []) as Array).size()
		),
		"source_item_count": (
			(entry.get("source_item_ids", []) as Array).size()
		),
	}


func _feedback_view() -> Dictionary:
	if latest_result.is_empty():
		return {
			"status": "idle",
			"title": "局面刚刚展开",
			"body": "先看清这里的人和痕迹，再决定把手伸向哪里。",
			"details": [],
		}

	if latest_event_type == "world_tick":
		return _tick_feedback_view()
	if latest_event_type == "ferry_wait":
		return _ferry_wait_feedback_view()
	if latest_event_type == "travel":
		return _travel_feedback_view()
	if latest_event_type == "challenge":
		return _challenge_feedback_view()
	if latest_event_type == "combat_encounter":
		return _combat_encounter_feedback_view()
	if latest_event_type == "return_echo":
		return _return_echo_feedback_view()
	if latest_event_type == "investigation":
		return _investigation_feedback_view()

	if not bool(latest_result.get("success", false)):
		var error := str(latest_result.get("error", ""))
		var error_body := "当前局面无法执行这个行动。"
		if error == "candidate_not_found":
			error_body = "局面已经变化，这个行动不再可用。"
		elif error == "action_blocked":
			error_body = str(latest_result.get(
				"blocked_reason",
				"当前能力不足，无法执行这个行动。"
			))
		return {
			"status": "error",
			"title": "行动没有发生",
			"body": error_body,
			"details": [],
		}

	var transaction: Dictionary = latest_result.get("transaction_result", {})
	var narrative: Dictionary = transaction.get("narrative_result", {})
	var candidate: Dictionary = latest_result.get("candidate", {})
	var contract_status := str(latest_result.get("contract_status", ""))
	var title := str(narrative.get("title", ""))
	var body := _result_narrative(latest_result)
	if title == "":
		title = str(candidate.get("label", "行动已记录"))
	if body == "":
		body = (
			"你做出了这个选择。它已被记录，但还没有产生可结算的世界变化。"
			if contract_status == "candidate_only"
			else "行动已经发生。"
		)
	return {
		"status": contract_status,
		"title": title,
		"body": body,
		"details": _result_detail_lines(transaction, candidate),
	}


func _combat_encounter_feedback_view() -> Dictionary:
	if not bool(latest_result.get("success", false)):
		return {
			"status": "error",
			"title": "这次遭遇已经有了结果",
			"body": "局面已经变化，刚才的处理方式不能再次结算。",
			"details": ["没有追加事实，也没有再次消耗时间或装备。"],
		}

	var transaction: Dictionary = latest_result.get("transaction_result", {})
	var narrative: Dictionary = transaction.get("narrative_result", {})
	var preview: Dictionary = latest_result.get("preview", {})
	var formula := "掷骰 %d + %s %d = %d / 难度 %d" % [
			int(narrative.get("roll", 0)),
			_combat_score_label(str(preview.get("score_target", ""))),
			int(narrative.get("effective_score", 0)),
			int(narrative.get("total", 0)),
			int(narrative.get("difficulty", 0)),
		]
	var details: Array[String] = [formula]
	var settlement: Array[String] = []
	for change: Dictionary in transaction.get("state_changes", []):
		if str(change.get("entity_id", "")) != "player":
			continue
		var state_text := _state_change_text(change)
		if state_text != "":
			settlement.append(state_text)
	for change: Dictionary in transaction.get("item_changes", []):
		var item_text := _item_change_text(change)
		if item_text != "":
			settlement.append(item_text)
	for fact: Dictionary in transaction.get("facts_added", []):
		if str(fact.get("fact_type", "")) == "actor_injured_during_combat":
			settlement.append("伤势：%s" % _injury_label(str(
				fact.get("injury", "combat_bruising")
			)))
	var outcome_text := (
		"成功" if str(narrative.get("outcome", "")) == "success" else "失败"
	)
	var settlement_text := (
		"结算：%s" % "；".join(settlement)
		if not settlement.is_empty()
		else "结算：没有身体或装备损耗"
	)
	for modifier: Dictionary in narrative.get("modifier_explanations", []):
		var operation := str(modifier.get("operation", "add"))
		var value := int(round(float(modifier.get("value", 0))))
		var value_text := _signed_number(value) if operation == "add" else str(value)
		details.append("%s使%s %s：%s" % [
			str(modifier.get("source_label", "当前效果")),
			_combat_score_label(str(modifier.get("target", ""))),
			value_text,
			str(modifier.get("reason", "修正已经生效")),
		])
	for change: Dictionary in transaction.get("state_changes", []):
		var state_text := _state_change_text(change)
		if state_text != "":
			details.append(state_text)
	for change: Dictionary in transaction.get("item_changes", []):
		var item_text := _item_change_text(change)
		if item_text != "":
			details.append(item_text)
	for fact: Dictionary in transaction.get("facts_added", []):
		if bool(fact.get("show_in_feedback", false)):
			details.append(str(fact.get("summary", "")))
	details.append("这次遭遇已经结算，原来的三个选择已从行动栏撤下。")
	return {
		"status": str(narrative.get("outcome", "combat_encounter")),
		"title": str(narrative.get("title", "遭遇结果")),
		"body": "%s（%s）\n%s\n\n%s" % [
			formula,
			outcome_text,
			settlement_text,
			str(narrative.get("summary", "局面已经产生结果。")),
		],
		"details": details,
	}


func _investigation_feedback_view() -> Dictionary:
	if not bool(latest_result.get("success", false)):
		return {
			"status": "error",
			"title": "这条调查方向已经变化",
			"body": "当前局面不再允许重复执行这个选择。",
			"details": [],
		}

	var transaction: Dictionary = latest_result.get(
		"transaction_result",
		{}
	)
	var narrative: Dictionary = transaction.get("narrative_result", {})
	var option_type := str(latest_result.get("option_type", ""))
	var details: Array[String] = []
	if option_type == "defer":
		details.append("调查方向仍然保留，之后可以继续生活或回来追查")
		details.append("陈米会把税契匣留在柜台下")
	else:
		for change: Dictionary in transaction.get(
			"relationship_changes",
			[]
		):
			details.append(_relationship_change_text(change))
		for fact: Dictionary in transaction.get("facts_added", []):
			if (
				str(fact.get("fact_type", ""))
				== "actor_found_public_granary_archive_reference"
			):
				details.append(
					"新方向：%s"
					% str(fact.get("summary", ""))
				)
		details.append("验粮铜牌新增了用于比对公仓封印的物品履历")
	var entries: Array = transaction.get(
		"chronicle_entries_added",
		[]
	)
	if not entries.is_empty():
		details.append(
			"个人纪事新增：%s"
			% str(
				(entries[0] as Dictionary).get(
					"title",
					"调查方向"
				)
			)
		)
	return {
		"status": "investigation",
		"title": str(narrative.get("title", "调查方向")),
		"body": str(
			narrative.get(
				"summary",
				"你对这条调查方向作出了选择。"
			)
		),
		"details": details,
	}


func _return_echo_feedback_view() -> Dictionary:
	if not bool(latest_result.get("success", false)):
		return {
			"status": "error",
			"title": "这段旧事已经说过",
			"body": "眼前已经没有可重复结算的旧物回响。",
			"details": [],
		}

	var transaction: Dictionary = latest_result.get(
		"transaction_result",
		{}
	)
	var narrative: Dictionary = transaction.get("narrative_result", {})
	var details: Array[String] = []
	for change: Dictionary in transaction.get(
		"relationship_changes",
		[]
	):
		details.append(_relationship_change_text(change))
	for fact: Dictionary in transaction.get("facts_added", []):
		if (
			str(fact.get("fact_type", ""))
			== "lake_town_public_granary_sealed_after_spoiled_grain"
		):
			details.append(
				"新线索：%s" % str(fact.get("summary", ""))
			)
	var chronicle_entries: Array = transaction.get(
		"chronicle_entries_added",
		[]
	)
	if not chronicle_entries.is_empty():
		details.append(
			"个人纪事新增：%s"
			% str(
				(chronicle_entries[0] as Dictionary).get(
					"title",
					"被认出的旧物"
				)
			)
		)
	var investigation_changes: Array = transaction.get(
		"investigation_changes",
		[]
	)
	if not investigation_changes.is_empty():
		var lead: Dictionary = (
			(investigation_changes[0] as Dictionary).get("lead", {})
		)
		details.append(
			"新的调查方向：%s"
			% str(lead.get("title", "公仓封存记录"))
		)
	details.append("验粮铜牌新增了一段可追溯的物品履历")
	return {
		"status": "return_echo",
		"title": str(narrative.get("title", "旧物被认了出来")),
		"body": str(
			narrative.get(
				"summary",
				"眼前的人认出了你带回的旧物。"
			)
		),
		"details": details,
	}


func _challenge_feedback_view() -> Dictionary:
	if not bool(latest_result.get("success", false)):
		return {
			"status": "error",
			"title": "这个选择已经失效",
			"body": "眼前的危险已经有了结果，不能重复结算。",
			"details": [],
		}

	var transaction: Dictionary = latest_result.get("transaction_result", {})
	var narrative: Dictionary = transaction.get("narrative_result", {})
	var option_type := str(latest_result.get("option_type", ""))
	var details: Array[String] = []
	if option_type == "prepare":
		details.append(
			"准备耗时 %d 小时，并写入当前世界状态。"
			% int(latest_result.get("hours", 1))
		)
		for change: Dictionary in transaction.get("state_changes", []):
			if str(change.get("entity_id", "")) == "player":
				details.append(_state_change_text(change))
		for item_change: Dictionary in transaction.get("item_changes", []):
			var prepared_item: Dictionary = item_change.get("item", {})
			if str(prepared_item.get("item_def_id", "")) == "item.travel_ration":
				details.append(
					"随身食物 +%d 份（%s）" % [
						int(prepared_item.get("quantity", 1)),
						_item_display_text(prepared_item),
					]
				)
			else:
				details.append(
					"远行装备进入随身物品：%s"
					% _item_display_text(prepared_item, "未命名装备")
				)
	else:
		var preparation_bonus := int(narrative.get("preparation_bonus", 0))
		var formula := "掷骰 %d + %s %d" % [
			int(narrative.get("roll", 0)),
			_state_key_label(str(narrative.get("stat_key", "perception"))),
			int(narrative.get("stat_value", 0)),
		]
		if preparation_bonus > 0:
			formula += " + 准备 %d" % preparation_bonus
		formula += " = %d / 难度 %d" % [
			int(narrative.get("total", 0)),
			int(narrative.get("difficulty", 0)),
		]
		details.append(formula)
		if str(narrative.get("outcome", "")) == "success":
			var item_changes: Array = transaction.get("item_changes", [])
			if not item_changes.is_empty():
				var item: Dictionary = (
					(item_changes[0] as Dictionary).get("item", {})
				)
				details.append(
					"发现物进入随身物品：%s"
					% str(item.get("display_name", "未知物品"))
				)
			var chronicle_entries: Array = transaction.get(
				"chronicle_entries_added",
				[]
			)
			if not chronicle_entries.is_empty():
				details.append(
					"个人纪事新增：%s"
					% str(
						(chronicle_entries[0] as Dictionary).get(
							"title",
							"一次现场发现"
						)
					)
				)
		else:
			details.append("身体受到伤害，但这次行动没有夺走你的性命。")
	for fact: Dictionary in transaction.get("facts_added", []):
		if bool(fact.get("show_in_feedback", false)):
			details.append(str(fact.get("summary", "")))
	for change: Dictionary in transaction.get("state_changes", []):
		if (
			str(change.get("entity_id", "")) == "player"
			and str(change.get("key", "")) == "mist_salt_echo"
		):
			var consequence_text := _state_change_text(change)
			if consequence_text not in details:
				details.append(consequence_text)
	return {
		"status": str(narrative.get("outcome", "challenge")),
		"title": str(narrative.get("title", "冒险结果")),
		"body": str(narrative.get("summary", "局面已经产生结果。")),
		"details": details,
	}


func _travel_feedback_view() -> Dictionary:
	if not bool(latest_result.get("success", false)):
		var error := str(latest_result.get("error", ""))
		var body := "当前无法沿这条路线出发。"
		if error == "insufficient_food":
			body = "你带的食物不够走完这段路。"
		elif error == "missing_required_item":
			body = "这段路不能空手出发；你还缺少防盐面罩等必要防护。"
		elif error == "outside_access_window":
			body = "北埠摆渡已经停船；等到白天才能沿这条路线出发。"
		elif error == "route_not_discovered":
			body = "你还不知道该从哪里前往这个地点。"
		return {
			"status": "error",
			"title": "没有动身",
			"body": body,
			"details": [],
		}

	var transaction: Dictionary = latest_result.get("transaction_result", {})
	var narrative: Dictionary = transaction.get("narrative_result", {})
	var destination: Dictionary = latest_result.get("destination", {})
	var hours := int(latest_result.get("hours", 0))
	var food_cost := int(latest_result.get("food_cost", 0))
	var travel_cost_text := "经过 %d 小时。" % hours
	if food_cost > 0:
		travel_cost_text = "经过 %d 小时，消耗 %d 份食物。" % [
			hours,
			food_cost,
		]
	var details: Array[String] = [
		travel_cost_text,
		"现在位于%s。" % str(destination.get("display_name", "新的地点")),
	]
	var tick_result: Dictionary = latest_result.get("tick_result", {})
	if _world_change_count(tick_result) > 0:
		var tick_summary := _tick_narrative(tick_result)
		if tick_summary != "":
			details.append("你在路上时，原来的地方也发生了变化：%s" % tick_summary)
	return {
		"status": "travel",
		"title": str(narrative.get("title", "抵达新的地点")),
		"body": str(narrative.get("summary", "你抵达了新的地点。")),
		"details": details,
	}


func _tick_feedback_view() -> Dictionary:
	if not bool(latest_result.get("success", false)):
		return {
			"status": "error",
			"title": "时间没有推进",
			"body": "这个时间变化无法作用于当前世界。",
			"details": [],
		}

	if _world_change_count(latest_result) == 0:
		return {
			"status": "world_tick",
			"title": "一小时过去",
			"body": "这里没有立刻显现出新的变化，但世界时钟仍在向前。",
			"details": [],
		}

	var result_data := _local_organization_response_result(latest_result)
	if result_data.is_empty():
		var results: Array = latest_result.get(
			"observed_autonomous_results",
			[]
		)
		if results.is_empty():
			results = latest_result.get("observed_need_results", [])
		if results.is_empty():
			results = latest_result.get("network_results", [])
		if results.is_empty():
			results = latest_result.get("resource_results", [])
		if results.is_empty():
			results = latest_result.get("livelihood_results", [])
		if results.is_empty():
			results = latest_result.get("results", [])
		result_data = results[0] if not results.is_empty() else {}
	var narrative: Dictionary = result_data.get("narrative_result", {})
	var details := _tick_detail_lines(result_data)
	details.append_array(_need_detail_lines(latest_result))
	details.append_array(_decision_detail_lines(latest_result))
	return {
		"status": "world_tick",
		"title": str(narrative.get("title", "时间带来了变化")),
		"body": str(narrative.get(
			"summary", _tick_narrative(latest_result)
		)),
		"details": details,
	}


func _ferry_wait_feedback_view() -> Dictionary:
	if not bool(latest_result.get("success", false)):
		return {
			"status": "error",
			"title": "没能等到早船",
			"body": "当前世界时间无法推进到摆渡开船。",
			"details": [],
		}
	var details: Array[String] = [
		"时间推进了 %d 小时" % int(latest_result.get("waited_hours", 0)),
		"北埠摆渡现已开船（06:00 至 18:00）",
	]
	var world_change_count := _world_change_count(latest_result)
	if world_change_count > 0:
		details.append("等待期间发生了 %d 次世界变化" % world_change_count)
	return {
		"status": "ferry_wait",
		"title": "天亮前的短歇",
		"body": _ferry_wait_narrative(),
		"details": details,
	}


func _ferry_wait_narrative() -> String:
	return "你在铺子里歇到天亮。陈米叫醒你时，去北埠的第一班摆渡已经开始载客。"


func _tick_narrative(result: Dictionary) -> String:
	var local_response := _local_organization_response_result(result)
	if not local_response.is_empty():
		var local_narrative: Dictionary = local_response.get(
			"narrative_result", {}
		)
		var local_summary := str(local_narrative.get("summary", ""))
		if local_summary != "":
			return local_summary
	var summaries: Array[String] = []
	var results: Array = (
		result.get("results", []) as Array
	).duplicate(true)
	results.append_array(result.get("resource_results", []))
	results.append_array(result.get("network_results", []))
	results.append_array(result.get("livelihood_results", []))
	results.append_array(result.get("observed_need_results", []))
	results.append_array(result.get("observed_autonomous_results", []))
	for result_value: Variant in results:
		if not (result_value is Dictionary):
			continue
		var result_data := result_value as Dictionary
		var narrative: Dictionary = result_data.get("narrative_result", {})
		var summary := str(narrative.get("summary", ""))
		if summary != "":
			summaries.append(summary)
	if not summaries.is_empty():
		return " | ".join(summaries)
	var entries: Array = result.get("world_log_entries", [])
	if not entries.is_empty() and int(result.get("triggered_count", 0)) > 0:
		return str((entries[0] as Dictionary).get("narrative_summary", ""))
	return ""


func _local_organization_response_result(result: Dictionary) -> Dictionary:
	if session == null or not session.is_ready():
		return {}
	var settlement_id := _current_settlement_id(session.get_snapshot())
	if settlement_id == "":
		return {}
	var network_results: Array = result.get("network_results", [])
	for index: int in range(network_results.size() - 1, -1, -1):
		var result_value: Variant = network_results[index]
		if not result_value is Dictionary:
			continue
		var result_data: Dictionary = result_value
		for fact: Dictionary in result_data.get("facts_added", []):
			if (
				str(fact.get("fact_type", "")) in [
					"organization_local_provisions_transferred",
					"organization_trade_coordinated",
					"organization_route_patrolled",
					"organization_runtime_formed",
					"organization_effectiveness_evaluated",
					"organization_goal_changed",
					"organization_goal_reactivated",
					"organization_runtime_retired",
				]
				and str(fact.get("settlement_id", "")) == settlement_id
			):
				return result_data
	return {}


func _tick_detail_lines(result_data: Dictionary) -> Array:
	var rows: Array[String] = []
	for change: Dictionary in result_data.get("state_changes", []):
		rows.append(_state_change_text(change))
	for pressure: Dictionary in result_data.get("pressure_changes", []):
		if str(pressure.get("pressure_type", "")) == "market_shortage":
			rows.append("老陈铺子周围的粮食压力继续上升")
	for change: Dictionary in result_data.get("resource_changes", []):
		var stock: Dictionary = session.get_snapshot().get_resource_stock(str(
			change.get("stock_id", "")
		))
		var label := str(stock.get(
			"label", change.get("resource_label", "本地资源")
		))
		if str(change.get("operation", "")) == "consume":
			rows.append("%s因生产消耗 %.1f" % [
				label, float(change.get("amount", 0.0))
			])
		elif str(change.get("operation", "")) == "recover":
			rows.append("%s自然恢复 %.1f" % [
				label, float(change.get("amount", 0.0))
			])
	if not (result_data.get("facts_added", []) as Array).is_empty():
		rows.append("这次变化已经成为可追溯的世界事实")
	return rows


func _decision_detail_lines(result: Dictionary) -> Array:
	var rows: Array[String] = []
	var decisions: Array = result.get("observed_autonomous_decisions", [])
	for decision_value: Variant in decisions:
		if not (decision_value is Dictionary):
			continue
		var decision := decision_value as Dictionary
		var actor_name := _entity_name(str(decision.get("actor_id", "")))
		rows.append("这是%s根据当前处境自行作出的决定" % actor_name)
		var factors: Array = decision.get("matched_factors", [])
		for factor_value: Variant in factors:
			if not (factor_value is Dictionary):
				continue
			var label := str((factor_value as Dictionary).get("label", ""))
			if label != "":
				rows.append("促成决定：%s" % label)
	return rows


func _need_detail_lines(result: Dictionary) -> Array:
	var rows: Array[String] = []
	for change: Dictionary in result.get("observed_need_changes", []):
		rows.append("%s的%s从%s变为%s" % [
			_entity_name(str(change.get("actor_id", ""))),
			_state_key_label(str(change.get("need_key", ""))),
			_hunger_label(str(change.get("from", ""))),
			_hunger_label(str(change.get("to", ""))),
		])
	return rows


func _world_change_count(result: Dictionary) -> int:
	return (
		int(result.get("triggered_count", 0))
		+ int(result.get("observed_need_change_count", 0))
		+ int(result.get(
			"observed_autonomous_decision_count",
			0
		))
		+ int(result.get("livelihood_event_count", 0))
		+ int(result.get("resource_event_count", 0))
		+ int(result.get("network_event_count", 0))
	)


func _result_narrative(result: Dictionary) -> String:
	var world_log_entry: Dictionary = result.get("world_log_entry", {})
	var summary := str(world_log_entry.get("narrative_summary", ""))
	if summary != "":
		return summary
	var transaction: Dictionary = result.get("transaction_result", {})
	var narrative: Dictionary = transaction.get("narrative_result", {})
	return str(narrative.get("summary", narrative.get("body", "")))


func _result_detail_lines(
		transaction: Dictionary,
		candidate: Dictionary = {}
) -> Array:
	var rows: Array[String] = []
	for requirement: Dictionary in candidate.get("player_requirements", []):
		if not bool(requirement.get("met", false)):
			continue
		rows.append("%s %s，满足行动要求 %s" % [
			str(requirement.get("label", "能力")),
			_attribute_number(requirement.get("current", 0)),
			_attribute_number(requirement.get("required", 0)),
		])
	for change: Dictionary in transaction.get("state_changes", []):
		rows.append(_state_change_text(change))
	for change: Dictionary in transaction.get("relationship_changes", []):
		rows.append(_relationship_change_text(change))
	for change: Dictionary in transaction.get("item_changes", []):
		var item_text := _item_change_text(change)
		if item_text != "":
			rows.append(item_text)
	var facts: Array = transaction.get("facts_added", [])
	if not facts.is_empty():
		rows.append("形成了 %d 条可追溯事实" % facts.size())
	return rows


func _state_change_text(change: Dictionary) -> String:
	var entity_id := str(change.get("entity_id", ""))
	var key := str(change.get("key", ""))
	if key == "visible" and bool(change.get("to", false)):
		return "%s出现在现场" % _entity_name(entity_id)
	if key == "visible" and not bool(change.get("to", true)):
		return "%s已经离开现场" % _entity_name(entity_id)
	if key == "price_level" and str(change.get("to", "")) == "raised_again":
		return "%s上的价格又被改高" % _entity_name(entity_id)
	if entity_id == "player" and key == "food_count":
		return "随身食物 %s" % _signed_number(int(change.get("delta", 0)))
	if entity_id == "player" and key == "health":
		if change.has("to"):
			return "健康降至 %d" % int(change.get("to", 0))
		return "健康 %s，现为 %d" % [
			_signed_number(int(change.get("delta", 0))),
			int(session.get_snapshot().get_player_value("health", 0)),
		]
	if entity_id == "player" and key == "fatigue":
		return "疲劳 %s，现为 %d / 10" % [
			_signed_number(int(change.get("delta", 0))),
			int(session.get_snapshot().get_player_value("fatigue", 0)),
		]
	if entity_id == "player" and key == "injury":
		return "伤势：%s" % _injury_label(str(change.get("to", "")))
	if entity_id == "player" and key == "mist_salt_echo":
		return "长期痕迹：%s" % _mist_salt_echo_label(
			str(change.get("to", "faint"))
		)
	if entity_id == "player" and key == "mist_salt_expedition_prepared":
		return "雾盐旧井远行准备已经完成"
	if entity_id == "player" and key == "inventory_item_ids":
		return "随身物品发生变化"
	if key == "hunger" and str(change.get("operation", "")) == "decrease_tier":
		return "%s的饥饿有所缓和" % _entity_name(entity_id)
	return "%s的%s发生变化" % [_entity_name(entity_id), _state_key_label(key)]


func _relationship_change_text(change: Dictionary) -> String:
	return "%s对你的%s %s" % [
		_entity_name(str(change.get("source_id", ""))),
		_relationship_axis_label(str(change.get("axis", ""))),
		_signed_number(int(change.get("delta", 0))),
	]


func _item_change_text(change: Dictionary) -> String:
	var operation := str(change.get("operation", ""))
	var quantity := int(change.get("quantity", 1))
	if operation == "adjust_durability":
		var item: Dictionary = session.get_snapshot().get_item(str(change.get(
			"item_instance_id", ""
		)))
		var condition: Dictionary = item.get("condition", {})
		return "%s耐久降至 %d / %d" % [
			str(item.get("display_name", "装备")),
			int(condition.get("durability", change.get("to", 0))),
			int(condition.get("maximum_durability", 0)),
		]
	if operation == "consume":
		if str(change.get("item_def_id", "")) == "item.travel_ration":
			return "随身食物 -%d 份" % quantity
		return "消耗随身物品：%s" % _item_display_text(change)
	if operation == "create":
		return "随身物品增加：%s" % _item_display_text(
			change.get("item", {})
		)
	return ""


func _item_display_text(
		item: Dictionary,
		fallback: String = "未命名物品"
) -> String:
	var display_name := str(item.get("display_name", ""))
	if display_name == "" and str(item.get("item_def_id", "")) == "item.travel_ration":
		display_name = "旅行口粮"
	if display_name == "":
		display_name = fallback
	var quantity := int(item.get("quantity", 1))
	var condition: Dictionary = item.get("condition", {})
	var maximum_durability := int(condition.get("maximum_durability", 0))
	if maximum_durability > 0:
		display_name += " %d/%d" % [
			int(condition.get("durability", maximum_durability)),
			maximum_durability,
		]
	if quantity > 1:
		return "%s ×%d" % [display_name, quantity]
	return display_name


func _combat_action_hint(option: Dictionary) -> String:
	var preview: Dictionary = option.get("preview", {})
	var parts: Array[String] = [
		"d6 + %s %d，对难度 %d，%s" % [
			_combat_score_label(str(preview.get("score_target", ""))),
			int(preview.get("effective_score", 0)),
			int(preview.get("difficulty", 0)),
			_required_roll_text(int(preview.get("required_roll", 7))),
		]
	]
	var applied: Array[String] = []
	for modifier: Dictionary in preview.get("modifier_explanations", []):
		applied.append("%s %s" % [
			str(modifier.get("source_label", "当前效果")),
			_signed_number(int(round(float(modifier.get("value", 0))))),
		])
	if not applied.is_empty():
		parts.append("已计入：%s" % "、".join(applied))
	var costs: Array[String] = []
	var possible_costs: Dictionary = preview.get("possible_costs", {})
	for description: Variant in possible_costs.get("descriptions", []):
		costs.append(_combat_cost_text(str(description)))
	if not costs.is_empty():
		parts.append("失败可能：%s" % "；".join(costs))
	return "。".join(parts) + "。"


func _combat_cost_text(value: String) -> String:
	return value.replace("main_hand装备", "主手装备").replace(
		"utility装备", "工具装备"
	).replace("body_outer装备", "外衣装备")


func _combat_approach_label(approach_id: String) -> String:
	return {
		"fight_balanced": "交战",
		"retreat": "撤退",
		"negotiate": "交涉",
	}.get(approach_id, "应对")


func _combat_score_label(score_target: String) -> String:
	return {
		"combat.attack": "攻击",
		"combat.guard": "防守",
		"combat.escape": "撤离",
		"combat.influence": "影响",
		"combat.control": "控制",
	}.get(score_target, "有效数值")


func _required_roll_text(required_roll: int) -> String:
	if required_roll <= 1:
		return "必定成功"
	if required_roll <= 6:
		return "需 %d+" % required_roll
	return "当前无法成功"


func _find_combat_encounter_option(option_id: String) -> Dictionary:
	for option: Dictionary in session.get_combat_encounter_options():
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _find_action_option(action_id: String) -> Dictionary:
	for option: Dictionary in session.get_action_options():
		if str(option.get("action_id", "")) == action_id:
			return option.duplicate(true)
	return {}


func _find_travel_option(route_id: String) -> Dictionary:
	for option: Dictionary in session.get_travel_options():
		if str(option.get("route_id", "")) == route_id:
			return option.duplicate(true)
	return {}


func _find_challenge_option(option_id: String) -> Dictionary:
	for option: Dictionary in session.get_challenge_options():
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _find_return_echo_option(option_id: String) -> Dictionary:
	for option: Dictionary in session.get_return_echo_options():
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _find_investigation_option(option_id: String) -> Dictionary:
	for option: Dictionary in session.get_investigation_options():
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _entity_name(entity_id: String) -> String:
	if entity_id == "player":
		return "你"
	if not is_ready():
		return "某个对象"
	var entity: Dictionary = session.get_snapshot().get_entity(entity_id)
	return str(entity.get("display_name", "某个对象"))


func _location_context(location: Dictionary, snapshot: Variant) -> String:
	var labels: Array[String] = []
	for tag: Variant in location.get("tags", []):
		var label := _location_tag_label(str(tag))
		if label != "" and label not in labels:
			labels.append(label)
	var pressure := str(snapshot.get_region_state_value("food_pressure", ""))
	if pressure == "high":
		labels.append("粮食紧缺")
	return " · ".join(labels)


func _person_state_text(states: Dictionary) -> String:
	var rows: Array[String] = []
	if states.has("hunger"):
		rows.append("饥饿：%s" % _hunger_label(str(states.get("hunger", ""))))
	if states.has("fear"):
		rows.append("戒备：%s" % _fear_label(str(states.get("fear", ""))))
	if states.has("granary_record_stance"):
		rows.append(
			"旧事：%s"
			% _granary_record_stance_label(
				str(states.get("granary_record_stance", ""))
			)
		)
	return "　".join(rows)


func _object_state_text(entity: Dictionary, snapshot: Variant) -> String:
	var entity_id := str(entity.get("id", ""))
	var entity_type := str(entity.get("type", ""))
	var states: Dictionary = entity.get("states", {})
	var price_changed := str(states.get("price_level", "")) == "raised_again"
	if entity_type == "readable_notice" and bool(states.get("readable", false)):
		var read_state := (
			"已经读过"
			if _has_fact(snapshot, "actor_read_object", "target_id", entity_id)
			else "可以阅读"
		)
		return "刚被再次改高　%s" % read_state if price_changed else read_state
	if entity_type == "trace" and bool(states.get("inspectable", false)):
		var stock_rows: Array[String] = []
		for stock_id: Variant in states.get("resource_stock_ids", []):
			var stock: Dictionary = snapshot.get_resource_stock(str(stock_id))
			if stock.is_empty():
				continue
			var capacity := float(stock.get("capacity", 0.0))
			var percent := 0 if capacity <= 0.0 else int(round(
				float(stock.get("current", 0.0)) * 100.0 / capacity
			))
			stock_rows.append("%s %d%%（%s）" % [
				str(stock.get("label", "资源")),
				percent,
				_resource_status_label(str(stock.get("status", "abundant"))),
			])
		if not stock_rows.is_empty():
			return "资源水位：%s　%s" % [
				"、".join(stock_rows),
				"已经检查"
				if _has_fact(snapshot, "actor_inspected_trace", "target_id", entity_id)
				else "可以检查",
			]
		return (
			"已经检查"
			if _has_fact(snapshot, "actor_inspected_trace", "target_id", entity_id)
			else "可以检查"
		)
	return "就在眼前"


func _time_view() -> Dictionary:
	var summary: Dictionary = session.get_time_summary()
	var day := int(summary.get("day", 1))
	var hour := int(summary.get("hour", 0))
	return {
		"day": day,
		"hour": hour,
		"label": "第 %d 天　%02d:00" % [day, hour],
		"period": _time_period(hour),
	}


func _time_period(hour: int) -> String:
	if hour < 6:
		return "深夜"
	if hour < 12:
		return "上午"
	if hour < 18:
		return "下午"
	return "夜晚"


func _action_kind(action_type: String) -> String:
	return {
		"dialogue": "对话",
		"clue": "调查",
		"normal": "行动",
		"relationship": "关系",
		"military": "职责",
		"rumor": "传闻",
		"preparation": "准备",
		"danger": "危险",
		"relic": "旧物",
		"investigation": "追查",
		"life": "生活",
	}.get(action_type, "行动")


func _action_hint(option: Dictionary) -> String:
	if not bool(option.get("can_execute", true)):
		return str(option.get("blocked_reason", "当前能力不足"))
	var extra: Dictionary = option.get("extra", {})
	var contextual_hint := str(extra.get("hint", ""))
	if contextual_hint != "":
		return contextual_hint
	var mode := str(option.get("transaction_mode", ""))
	if mode == "candidate_only":
		return "记录选择，等待后续对话系统承接"
	return "由当前世界状态即时结算"


func _action_label(option: Dictionary, can_execute: bool) -> String:
	var label := str(option.get("label", "采取行动"))
	if can_execute:
		return label
	var requirements: Array = option.get("player_requirements", [])
	for requirement: Dictionary in requirements:
		if bool(requirement.get("met", false)):
			continue
		return "%s　[%s %s/%s]" % [
			label,
			str(requirement.get("label", "能力")),
			_attribute_number(requirement.get("current", 0)),
			_attribute_number(requirement.get("required", 0)),
		]
	return "%s　[当前不可用]" % label


func _attribute_number(value: Variant) -> String:
	var number := float(value)
	if is_equal_approx(number, round(number)):
		return str(int(number))
	return str(number)


func _challenge_action_hint(option: Dictionary) -> String:
	if str(option.get("option_type", "")) == "prepare":
		if bool(option.get("preparation_only", false)):
			return "%s；花费 %d 小时完成远行准备。" % [
				str(option.get("risk_description", "")),
				int(option.get("hours", 1)),
			]
		return "%s；花费 %d 小时后改变检定条件。" % [
			str(option.get("risk_description", "")),
			int(option.get("hours", 1)),
		]
	return "%s；%s；%s" % [
		str(option.get("check_text", "")),
		str(option.get("success_hint", "")),
		str(option.get("failure_hint", "")),
	]


func _role_label(role: String) -> String:
	return {
		"traveler": "途经湖湾镇的旅人",
		"squadmate": "同队士兵",
	}.get(role, role)


func _status_label(key: String) -> String:
	return {
		"food_pressure": "粮食压力",
		"public_order": "街面秩序",
		"settlement_isolation": "交通隔绝",
		"resource_strain": "资源负担",
		"migration_tendency": "迁离倾向",
		"flood_risk": "水患风险",
		"market_order": "市场状况",
		"local_guard_attention": "守卫关注",
	}.get(key, key)


func _status_detail(key: String, value: String) -> String:
	var details := {
		"food_pressure:high": "存粮正在收紧，价格和人心都受到了挤压。",
		"food_pressure:medium": "本地食物能维持多数家庭，但季节波动仍会造成缺口。",
		"food_pressure:low": "本地食物来源目前足以覆盖日常消耗。",
		"public_order:tense": "表面仍有秩序，但争执随时可能冒出来。",
		"public_order:stable": "来路风险和聚落规模尚未压垮日常秩序。",
		"settlement_isolation:high": "可用来路很少，交换和求援都容易中断。",
		"settlement_isolation:medium": "聚落有固定来路，但运量和可靠性仍然有限。",
		"settlement_isolation:low": "多条稳定来路维持着人员与物资交换。",
		"resource_strain:medium": "现有人口接近场址资源能够长期支撑的边缘。",
		"resource_strain:low": "场址资源对现有人口仍有余量。",
		"resource_strain:high": "多项生产资源已经接近停产线，聚落难以维持现有人口。",
		"migration_tendency:high": "持续短缺已经让部分家庭考虑离开。",
		"migration_tendency:medium": "资源波动让居民开始权衡外出谋生。",
		"migration_tendency:low": "当前资源水位尚未形成明显的迁离压力。",
		"flood_risk:high": "主要住地与生产设施容易受到季节水位影响。",
		"flood_risk:medium": "部分低地会受涨水影响，设施布局已经避开最危险水线。",
		"flood_risk:low": "聚落主体位于通常洪水难以抵达的位置。",
		"market_order:tense": "商贩惜售，买粮的人不愿空手离开。",
		"market_order:informal": "交换依靠熟人、集地和临时约定，还没有稳定市场规则。",
		"market_order:stable": "稳定运量已经支撑起较固定的交换秩序。",
		"local_guard_attention:medium": "守卫已经留意到异样，还没有正式介入。",
		"local_guard_attention:low": "这里没有常备守卫，安全主要依赖居民轮值。",
	}
	return str(details.get("%s:%s" % [key, value], "局势仍在变化。"))


func _state_value_label(value: String) -> String:
	return {
		"high": "高",
		"medium": "中等",
		"low": "低",
		"tense": "紧张",
		"stable": "稳定",
		"informal": "非正式",
	}.get(value, value)


func _resource_status_label(value: String) -> String:
	return {
		"abundant": "充足",
		"stable": "尚稳",
		"strained": "吃紧",
		"depleted": "不足以开工",
	}.get(value, value)


func _resource_stock_use_text(stock: Dictionary) -> String:
	var industries: Array[String] = []
	for value: Variant in stock.get("industry_ids", []):
		industries.append(_generated_industry_label(str(value)))
	if industries.is_empty():
		return "目前没有固定产业持续占用这项容量。"
	return "当前支撑%s。" % "、".join(industries)


func _hunger_label(value: String) -> String:
	return {
		"extreme": "濒临极限",
		"high": "严重",
		"medium": "缓和",
		"low": "轻微",
	}.get(value, value)


func _fear_label(value: String) -> String:
	return {
		"high": "惊惧",
		"medium": "不安",
		"low": "放松",
	}.get(value, value)


func _location_tag_label(tag: String) -> String:
	return {
		"town": "湖湾镇",
		"shop": "旧粮铺",
		"food_related": "粮食相关",
		"local_family_business": "本地人经营",
		"town_outskirts": "镇外",
		"abandoned": "废弃建筑",
		"granary": "旧粮仓",
		"dangerous": "不安地带",
		"waterfront": "北埠水岸",
		"archive": "旧档房",
		"tidal": "潮水侵蚀",
		"old_records": "旧卷封存",
		"wilderness": "城外荒野",
		"subterranean": "地下遗构",
		"anomalous": "异象区域",
		"ancient": "年代不明",
		"settlement": "聚落",
		"generated_location": "生成地点",
		"public_space": "公共集地",
		"hamlet": "小村",
		"village": "村镇",
		"small_town": "小镇",
		"workplace": "生产地点",
		"generated_facility": "因地形成",
		"fishery": "浅水渔业",
		"food_source": "食物来源",
		"farmland": "坡田",
		"craft": "手工作坊",
		"reeds": "泽苇资源",
		"herbalism": "泽地药草",
		"road": "道路运输",
		"transport": "短途转运",
		"market_access": "对外交换",
		"watch": "道路守望",
		"security": "聚落防护",
		"resource_site": "资源采集地",
	}.get(tag, "")


func _fact_text(
		fact_type: String,
		target_name: String,
		fact: Dictionary = {}
) -> String:
	if fact_type == "settlement_generated":
		var settlement_label := str(fact.get("settlement_name", target_name))
		return "%s由当前场址形成，可长期支撑约 %d 人，初始人口目标为 %d 人。" % [
			settlement_label,
			int(fact.get("resident_capacity", 0)),
			int(fact.get("population_target", 0)),
		]
	if fact_type == "settlement_industry_selected":
		var settlement_label := str(fact.get("settlement_name", target_name))
		return "%s形成了%s，来源是当地资源、地形或来路条件。" % [
			settlement_label,
			_generated_industry_label(str(fact.get("industry_id", ""))),
		]
	if fact_type == "settlement_resource_stock_established":
		return "%s形成长期库存：容量 %.1f，每天约恢复 %.1f。" % [
			str(fact.get("resource_label", "本地资源")),
			float(fact.get("capacity", 0.0)),
			float(fact.get("recovery_per_hour", 0.0)) * 24.0,
		]
	if fact_type == "resident_generation_completed":
		var settlement_label := str(fact.get("settlement_name", target_name))
		return "%s的初册记录了 %d 名居民与 %d 个家庭。" % [
			settlement_label,
			int(fact.get("resident_count", 0)),
			int(fact.get("household_count", 0)),
		]
	var summary := str(fact.get("summary", ""))
	if summary != "":
		if fact_type == "actor_read_object":
			return "你读过%s：%s" % [target_name, summary]
		if fact_type == "actor_inspected_trace":
			return "你检查过%s：%s" % [target_name, summary]
		if fact_type == "actor_requested_favor_from_target":
			return "你请%s帮过忙：%s" % [target_name, summary]
		if fact_type == "actor_heard_rumor_seed":
			return "你听到过“%s”：%s" % [target_name, summary]
		if fact_type in [
			"actor_resolved_combat_encounter",
			"mist_salt_claimant_driven_from_well_mouth",
			"mist_salt_claimant_won_brief_clash",
			"actor_withdrew_from_mist_salt_claimant",
			"actor_scrambled_away_from_mist_salt_claimant",
			"mist_salt_claimant_shared_water_warning",
			"mist_salt_claimant_refused_warning",
			"mist_salt_brine_boar_driven_off",
			"mist_salt_brine_boar_broke_guard",
			"actor_evaded_mist_salt_brine_boar",
			"actor_escaped_brine_boar_after_lantern_hit",
			"mist_salt_brine_boar_lured_from_well",
			"mist_salt_brine_boar_ignored_lure",
			"actor_injured_during_combat",
		]:
			return summary
	return {
		"actor_gave_food_to_target": "你给%s递过食物。" % target_name,
		"actor_asked_about_concealed_item": "你问过%s藏起来的东西。" % target_name,
		"actor_read_object": "你读过%s。" % target_name,
		"actor_inspected_trace": "你检查过%s。" % target_name,
		"actor_requested_favor_from_target": "你请%s帮过一次忙。" % target_name,
		"actor_heard_rumor_seed": "你听到过一条关于%s的传闻。" % target_name,
		"actor_asked_about_market_pressure": "你确认湖湾镇正承受粮食压力。",
		"actor_traveled_route": _travel_fact_text(fact),
		"actor_prepared_for_challenge": _challenge_preparation_fact_text(fact),
		"actor_attempted_challenge": _challenge_attempt_fact_text(fact),
		"actor_injured_during_challenge": _challenge_injury_fact_text(fact),
		"actor_injured_during_combat": "你在短遭遇中受了战斗挫伤。",
		"actor_resolved_combat_encounter": "你已经处理过井口的短遭遇。",
		"actor_discovered_item": _item_discovery_fact_text(target_name, fact),
		"actor_acquired_preparation_item": "你为远行备好了%s。" % target_name,
		"actor_prepared_mist_salt_expedition": "你在北埠用两小时劳动换得了往返口粮与防盐面罩。",
		"actor_acquired_mist_salt_echo": "你从雾盐旧井第二环回来后，呼吸里留下了不会随普通伤势消失的盐冷回响。",
		"actor_observed_mist_salt_filaments_follow_water": "你亲眼看见井下白丝逆着石壁渗水的方向弯曲。",
		"actor_found_lu_huai_second_ring_marker": "你在第二环发现了陆槐留下的验粮刻记，但仍不知道他后来去了哪里。",
		"chen_mi_recognized_granary_measure_token": "陈米认出了你带回的旧粮仓验粮铜牌。",
		"lake_town_public_granary_sealed_after_spoiled_grain": "陈米确认，湖湾镇公仓曾在霉粮被查出后封闭。",
		"investigation_lead_opened": "陈米说，陈家旧税契里也许夹着公仓封印抄件。",
		"actor_deferred_public_granary_investigation": "你暂时搁置了公仓封存记录，但仍可以回来追查。",
		"actor_investigated_public_granary_records": "你和陈米翻查过陈家保存的旧税契。",
		"actor_found_public_granary_archive_reference": "你查到验粮吏陆槐与北埠旧档房的记录。",
		"actor_found_lu_huai_last_inspection_record": "你在北埠旧档房找到了陆槐最后一页验粮簿。",
		"lu_huai_record_claimed_spoilage_was_not_mold": "陆槐的旧记录声称，那批粮里的白丝“不是霉”。",
		"lu_huai_recorded_departure_for_mist_salt_well": "陆槐留下前往雾盐旧井的日期，此后没有回档记录。",
		"merchant_closed_shop_early": "你亲眼看到老陈铺子提前收门，涨价告示也被再次改高。",
		"merchant_kept_shop_open": "陈米的饥饿缓和后，老陈决定暂时不收铺。",
	}.get(fact_type, "你确认了一条与此地有关的事实。")


func _travel_fact_text(fact: Dictionary) -> String:
	if str(fact.get("route_id", "")).begins_with("generated_route."):
		return "你走过聚落内部一段由实际设施形成的道路。"
	match str(fact.get("route_id", "")):
		"old_chen_shop_to_north_quay_record_house":
			return "你乘白天的摆渡抵达过北埠旧档房。"
		"north_quay_record_house_to_old_chen_shop":
			return "你从北埠旧档房沿北岸返回了老陈铺子。"
		"north_quay_record_house_to_mist_salt_well":
			return "你带着防盐面罩和往返口粮抵达了雾盐旧井。"
		"mist_salt_well_to_north_quay_record_house":
			return "你从雾盐旧井沿北岸荒路返回了北埠旧档房。"
		_:
			return "你完成过一段需要时间和食物的旅程。"


func _generated_industry_label(industry_id: String) -> String:
	return {
		"fishery": "浅水网渔",
		"terrace_farming": "坡田耕作",
		"reed_craft": "苇编与修具",
		"road_carting": "短途转运",
		"watch_service": "道路守望",
		"salt_gathering": "浅盐采集",
	}.get(industry_id, "一项本地生计")


func _challenge_preparation_fact_text(fact: Dictionary) -> String:
	if (
		str(fact.get("challenge_id", ""))
		== "north_quay_flooded_stack_search"
	):
		return "你借来罩灯和油布，等潮水退过刻痕后再进入封存层。"
	if (
		str(fact.get("challenge_id", ""))
		== "mist_salt_well_expedition_supply"
	):
		return "你帮闻简晒卷两小时，换得四份船饼和一只蜡布防盐面罩。"
	return "你在进入废弃粮仓前检查了朽木地板。"


func _challenge_attempt_fact_text(fact: Dictionary) -> String:
	var succeeded := str(fact.get("outcome", "")) == "success"
	if (
		str(fact.get("challenge_id", ""))
		== "north_quay_flooded_stack_search"
	):
		return (
			"你通过了北埠旧档房水浸封存层的风险检定。"
			if succeeded
			else "你没能通过北埠旧档房水浸封存层的风险检定。"
		)
	if (
		str(fact.get("challenge_id", ""))
		== "mist_salt_well_second_ring_descent"
	):
		return (
			"你深入了雾盐旧井第二环，并带回一份井下样本。"
			if succeeded
			else "你深入雾盐旧井第二环后被迫退回井口。"
		)
	return (
		"你通过了废弃粮仓的危险检定。"
		if succeeded
		else "你没能通过废弃粮仓的危险检定。"
	)


func _challenge_injury_fact_text(fact: Dictionary) -> String:
	if (
		str(fact.get("challenge_id", ""))
		== "north_quay_flooded_stack_search"
	):
		return "你在水浸封存层被断钉割伤了手掌。"
	if (
		str(fact.get("challenge_id", ""))
		== "mist_salt_well_second_ring_descent"
	):
		return "你在雾盐旧井第二环吸入盐雾并灼伤了喉咙。"
	return "你在废弃粮仓扭伤了脚踝。"


func _item_discovery_fact_text(
		target_name: String,
		fact: Dictionary
) -> String:
	if str(fact.get("location_id", "")) == "north_quay_record_house":
		return "你在北埠旧档房找到了%s。" % target_name
	if str(fact.get("location_id", "")) == "mist_salt_well":
		return "你在雾盐旧井第二环带回了%s。" % target_name
	return "你在废弃粮仓找到了%s。" % target_name


func _state_key_label(key: String) -> String:
	return {
		"hunger": "饥饿状态",
		"food_count": "食物数量",
		"strength": "力量",
		"dexterity": "敏捷",
		"wisdom": "智慧",
		"charisma": "魅力",
		"constitution": "体质",
		"perception": "感知",
		"health": "健康",
		"injury": "伤势",
		"mist_salt_echo": "雾盐回响",
	}.get(key, key)


func _injury_label(injury: String) -> String:
	return {
		"none": "无",
		"twisted_ankle": "脚踝扭伤",
		"archive_splinter_cut": "手掌割伤",
		"mist_salt_throat_burn": "盐雾灼伤",
		"combat_bruising": "战斗挫伤",
	}.get(injury, injury)


func _mist_salt_echo_label(value: String) -> String:
	return {
		"none": "无",
		"faint": "雾盐回响·微弱",
	}.get(value, value)


func _relationship_axis_label(axis: String) -> String:
	return {
		"gratitude": "感激",
		"trust": "信任",
		"fear": "畏惧",
		"debt": "亏欠",
		"familiarity": "熟悉",
	}.get(axis, axis)


func _signed_number(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)


func _granary_record_stance_label(stance: String) -> String:
	return {
		"waiting_for_return": "替你留着税契匣",
		"helped_search": "和你查到深夜",
	}.get(stance, stance)
