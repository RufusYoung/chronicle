extends RefCounted
class_name LakeTownLivingSurfaceTemplates

const SUPPORTED_FACT_TYPES: Array[String] = [
	"lake_town_food_price_rising",
	"chen_mi_took_spoiled_grain",
	"old_chen_closed_shop_due_to_family_crisis",
	"chen_mi_ate_spoiled_grain",
	"chen_mi_fell_sick_from_spoiled_grain",
	"ma_shen_brought_porridge",
	"creditor_left_debt_notice",
	"guard_locked_abandoned_granary",
	"chen_mi_blocked_by_guard_seal",
	"guard_noticed_child_near_granary",
	"chen_mi_found_empty_granary",
	"chen_mi_returned_empty_handed",
	"chen_mi_endured_hunger",
	"chen_mi_weakened_from_enduring_hunger",
	"old_chen_sold_shop_goods_for_food",
	"chen_mi_collapsed_from_hunger",
	"old_chen_took_chen_mi_to_seek_help",
	"lake_town_emergency_credit_food",
	"ma_shen_emergency_food_for_chen_mi",
	"chen_mi_temporarily_stayed_with_ma_shen",
	"chen_mi_health_crashed_from_hunger",
]

const NPC_NAMES := {
	"old_chen": "老陈",
	"chen_mi": "陈米",
	"ma_shen": "玛婶",
	"liu_zhangfang": "刘账房",
	"wardens": "守卫",
}
const LOCATION_NAMES := {
	"old_chen_shop": "老陈的铺子",
	"abandoned_granary": "废弃粮仓",
	"lake_town_market": "湖湾镇集市",
	"ma_shen_home_temp": "玛婶临时住所",
}
const FACT_LINES := {
	"lake_town_food_price_rising": "粮价又涨了，店门边多了一张涨价告示。",
	"chen_mi_took_spoiled_grain": "陈米取走了一袋发霉麦子。",
	"old_chen_closed_shop_due_to_family_crisis": "老陈因为家里撑不住，今天没有正常开门。",
	"chen_mi_ate_spoiled_grain": "陈米已经吃下了发霉麦子。",
	"chen_mi_fell_sick_from_spoiled_grain": "发霉麦子让陈米病了起来。",
	"ma_shen_brought_porridge": "玛婶端来了一碗粥。",
	"creditor_left_debt_notice": "刘账房留下了新的催债告示。",
	"guard_locked_abandoned_granary": "废弃粮仓门上多了一道守卫封条。",
	"chen_mi_blocked_by_guard_seal": "陈米在粮仓门前被封条挡了回来。",
	"guard_noticed_child_near_granary": "守卫开始注意粮仓附近的孩子。",
	"chen_mi_found_empty_granary": "陈米发现粮仓里已经空了。",
	"chen_mi_returned_empty_handed": "陈米空着手回到老陈店门口。",
	"chen_mi_endured_hunger": "陈米把饥饿忍了下来，没有去碰粮仓。",
	"chen_mi_weakened_from_enduring_hunger": "长期饥饿让陈米明显虚弱。",
	"old_chen_sold_shop_goods_for_food": "老陈卖掉了一些店里的旧货换食物。",
	"chen_mi_collapsed_from_hunger": "陈米倒在老陈铺子的台阶边。",
	"old_chen_took_chen_mi_to_seek_help": "老陈带着陈米离开铺子去求助。",
	"lake_town_emergency_credit_food": "集市给了这家人一份临时赊食。",
	"ma_shen_emergency_food_for_chen_mi": "玛婶把紧急食物送到陈米身边。",
	"chen_mi_temporarily_stayed_with_ma_shen": "陈米暂时住到了玛婶那里。",
	"chen_mi_health_crashed_from_hunger": "陈米的健康因为长期饥饿严重恶化。",
}
const TRACE_LINES := {
	"price_rise_notice": "店门边贴着涨价后的粮价牌。",
	"closed_shop": "铺门没有完全打开，门边没有正常做买卖的动静。",
	"child_hiding_bag": "陈米看见有人靠近时，把旧布袋往身后挪了一下。",
	"spoiled_grain_bag": "布袋口露出灰白色的发霉麦粒。",
	"small_footprints_near_guard_seal": "封条前有几行小脚印，脚印又折回镇里。",
	"guard_question_marks_at_granary": "粮仓门前留下了守卫盘问后的记号。",
	"empty_hands_at_shop_step": "店门台阶边只剩一双空手。",
	"old_chen_waited_at_door": "老陈站在门边等她回来。",
	"child_sitting_silent_at_shop_step": "陈米安静坐在台阶上，看起来很虚弱。",
	"neighbor_paused_near_shop_step": "有邻居在店门前停了一会儿。",
	"child_collapsed_at_shop_step": "门槛边有孩子倒下后留下的凌乱痕迹。",
	"emergency_food_bowl": "一只盛过热食的碗还放在门边。",
}


func build_fact_line(fact: Dictionary, context: Dictionary = {}) -> String:
	var type_name := str(fact.get("type", ""))
	if FACT_LINES.has(type_name):
		return str(FACT_LINES[type_name])
	return "这里发生了一件尚未命名的湖湾镇事件。fact type: %s" % type_name


func build_trace_line(trace: Dictionary, context: Dictionary = {}) -> String:
	var type_name := str(trace.get("type", ""))
	if TRACE_LINES.has(type_name):
		return str(TRACE_LINES[type_name])
	var tags := trace.get("description_tags", []) as Array
	if not tags.is_empty():
		return "可见痕迹：%s。" % ", ".join(tags)
	return "%s 留下了一条可见痕迹。" % type_name


func build_person_line(
		npc_id: String,
		npc_state: Dictionary,
		context: Dictionary = {}
	) -> String:
	var parts: Array[String] = []
	_append_metric(parts, "饥饿", npc_state.get("hunger", "-"))
	_append_metric(parts, "恐惧", npc_state.get("fear", "-"))
	_append_health(parts, npc_state.get("health", "-"))
	_append_metric(parts, "压力", npc_state.get("stress", "-"))
	_append_metric(parts, "债务", npc_state.get("debt", "-"))
	if str(npc_state.get("location_id", "-")) != "-":
		parts.append(
			"位置：%s"
			% location_name(str(npc_state.get("location_id", "")))
		)
	var tags := npc_state.get("status_tags", []) as Array
	if not tags.is_empty():
		parts.append("状态：%s" % " / ".join(tags))
	return "%s：%s" % [npc_name(npc_id), "；".join(parts)]


func build_location_line(
		location_id: String,
		location_state: Dictionary,
		context: Dictionary = {}
	) -> String:
	var parts: Array[String] = []
	if location_state.has("is_open") and str(
			location_state.get("is_open", "-")
		) != "-":
		parts.append(
			"开门：%s"
			% ("是" if bool(location_state.get("is_open", false)) else "否")
		)
	if location_state.has("partial_open") and str(
			location_state.get("partial_open", "-")
		) != "-":
		parts.append(
			"半开：%s"
			% (
				"是"
				if bool(location_state.get("partial_open", false))
				else "否"
			)
		)
	_append_metric(parts, "粮食", location_state.get("food_stock", "-"))
	_append_metric(
		parts,
		"发霉麦子",
		location_state.get("spoiled_grain_stock", "-")
	)
	var tags := location_state.get("status_tags", []) as Array
	if not tags.is_empty():
		parts.append("状态：%s" % " / ".join(tags))
	return "%s：%s" % [location_name(location_id), "；".join(parts)]


func build_summary(card_type: String, context: Dictionary) -> String:
	var fact_types := context.get("fact_types", []) as Array
	var lines: Array[String] = []
	if "chen_mi_took_spoiled_grain" in fact_types:
		lines.append("老陈的铺子今天没有正常开门。")
		if _has_trace(context, "spoiled_grain_bag"):
			lines.append("陈米抱着一只旧布袋，袋口露出灰白色的发霉麦粒。")
		else:
			lines.append("陈米取走发霉麦子的事实已经被记录下来。")
		if _has_trace(context, "child_hiding_bag"):
			lines.append("她看见有人靠近时，把布袋往身后挪了一下。")
	elif "guard_locked_abandoned_granary" in fact_types:
		lines.append("废弃粮仓门上多了一道守卫封条。")
		lines.append("这条封锁来自已经发生的粮食危机事实。")
	elif "chen_mi_blocked_by_guard_seal" in fact_types:
		lines.append("陈米走到粮仓门前，又被封条挡了回来。")
		lines.append("她的恐惧上升，粮仓附近也留下了小脚印。")
	elif "chen_mi_collapsed_from_hunger" in fact_types:
		lines.append("陈米倒在老陈铺子的门槛边。")
		lines.append("她的饥饿已经进入极高区间，健康也在下降。")
	elif "old_chen_took_chen_mi_to_seek_help" in fact_types:
		lines.append("老陈没有继续守在柜台后。")
		lines.append("他带着陈米离开铺子，去镇上寻找帮助。")
	elif "chen_mi_temporarily_stayed_with_ma_shen" in fact_types:
		lines.append("陈米暂时住到了玛婶那里。")
		lines.append("这不是新剧情，而是此前救助链留下的安置结果。")
	elif "chen_mi_returned_empty_handed" in fact_types:
		lines.append("陈米空着手回到老陈店门口。")
		lines.append("空粮仓的后果开始落回这家人身上。")
	elif (
		"chen_mi_endured_hunger" in fact_types
		or "chen_mi_weakened_from_enduring_hunger" in fact_types
	):
		lines.append("陈米把饥饿忍了下来。")
		lines.append("她坐在店门边，变得虚弱又沉默。")
	elif "old_chen_sold_shop_goods_for_food" in fact_types:
		lines.append("老陈卖掉了一些店里的旧货。")
		lines.append("铺子还在，但货架上的空处变多了。")
	else:
		for fact_value: Variant in context.get("facts", []):
			lines.append(build_fact_line(fact_value as Dictionary, context))
			if lines.size() >= 3:
				break
	if lines.is_empty() and context.has("state_reason"):
		lines.append(str(context.get("state_reason", "")))
	if lines.is_empty():
		lines.append("湖湾镇今天没有新的重大场面，只留下状态延续。")
	return "\n".join(lines.slice(0, 4))


func value_level(value: Variant) -> String:
	if value is String and str(value) == "-":
		return "-"
	var number := float(value)
	if number <= 30.0:
		return "低"
	if number <= 60.0:
		return "中"
	if number <= 85.0:
		return "高"
	return "极高"


func npc_name(npc_id: String) -> String:
	return str(NPC_NAMES.get(npc_id, npc_id))


func location_name(location_id: String) -> String:
	return str(LOCATION_NAMES.get(location_id, location_id))


func _append_metric(parts: Array[String], label: String, value: Variant) -> void:
	if value is String and str(value) == "-":
		return
	parts.append("%s：%s（%s）" % [label, value_level(value), str(value)])


func _append_health(parts: Array[String], value: Variant) -> void:
	if value is String and str(value) == "-":
		return
	var number := float(value)
	var state := "稳定"
	if number <= 30.0:
		state = "严重下降"
	elif number <= 60.0:
		state = "下降"
	elif number <= 85.0:
		state = "偏弱"
	parts.append("健康：%s（%s）" % [state, str(value)])


func _has_trace(context: Dictionary, trace_type: String) -> bool:
	for trace_value: Variant in context.get("traces", []):
		var trace := trace_value as Dictionary
		if str(trace.get("type", "")) == trace_type:
			return true
	return false
