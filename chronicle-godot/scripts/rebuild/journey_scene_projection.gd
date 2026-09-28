extends RefCounted

# Public geography and personal memories only; no remote NPC or inventory queries.
static func apply(session: Variant, view: Dictionary) -> void:
	if not session.PlayerLife.Journey.enabled(session) or int(view.player.get("travel_remaining", 0)) > 0:
		return
	var known: Dictionary = session.PlayerLife.Journey.knowledge(session)
	var routes: Array = session.fixture_source_data.travel_routes
	var bindings: Dictionary = session.fixture_source_data.journey_generated.bindings
	var here := str(view.location.id)
	var directions := {}
	for row: Dictionary in routes:
		if row.from_location_id == here:
			directions[str(row.route_id)] = str(row.to_location_id)
	var cues: Array = []
	for option: Dictionary in view.travel_options:
		var target: String = directions.get(str(option.route_id), "")
		var cue := ""
		var priority := 9
		if target.ends_with(".landing") and ("shore_box" not in known.closed or "cave_bundle" not in known.closed):
			cue = "沿湖去泊台；那里也通向回水洞"
			priority = 0
		elif target.ends_with("echo_landing.watch_post"):
			cue = "去旧哨棚辨认上废灯台的路" if "beacon_climb" not in known.closed else "旧哨棚通往你已经探索或放弃的灯台"
			priority = 1 if "beacon_climb" not in known.closed else 8
		elif target.ends_with("echo_terrace.watch_post"):
			cue = "从哨棚探听断崖小径的去向" if "cliff_pack" not in known.closed else "哨棚通往你已经探索或放弃的断崖小径"
			priority = 1 if "cliff_pack" not in known.closed else 8
		elif target.ends_with("echo_landing.road_yard"):
			cue = "循车辙去车场，看看沿路有什么" if "road_cord" not in known.closed else "去车场与实际在场的居民交往；旧绳卷不刷新"
			priority = 2 if "road_cord" not in known.closed else 8
		elif target.ends_with(".road_yard"):
			cue = "去车场看看本地来往的人与货；不保证有人停留"
			priority = 5
		elif target == "journey_location.lake_cave":
			cue = "沿水声探入回水洞；留意岩壁刻痕" if "cave_bundle" not in known.closed else "回水洞这一处已探索或放弃；不会刷新包裹"
			priority = 0 if "cave_bundle" not in known.closed else 8
		elif target == "journey_location.old_beacon":
			cue = "去废灯台查明旧灯的来由" if "beacon_climb" not in known.closed else "重返已走过的废灯台；旧木柜不会刷新"
			priority = 0 if "beacon_climb" not in known.closed else 8
		elif target == "journey_location.cliff_path":
			cue = "踏上断崖小径，先判断是否值得下坡" if "cliff_pack" not in known.closed else "这处旅行包已取走或放弃；可继续走别的路"
			priority = 0 if "cliff_pack" not in known.closed else 8
		elif target in [bindings.get("landing_host", ""), bindings.get("terrace_host", "")]:
			cue = "去客舍找人交谈、买卖或借宿；主人可能外出"
			if target == bindings.get("landing_host") and "found_host_cord" in known.marks and "return_cord" not in known.closed:
				cue = "你记得绳上的红线：去客舍找失主，当面决定还不还"
			priority = 2
		elif target.ends_with(".commons"):
			cue = "前往另一处聚落，看看不同的路与生活" if ".network." in str(option.route_id) else "回到聚落岔路，再选旧哨棚或客舍"
			priority = 3
		if cue != "":
			option["purpose"] = cue
			option["lead_source"] = "public_geography_and_personal_memory"
			cues.append(cue)
		option["lead_priority"] = priority
	view.travel_options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("lead_priority", 9)) < int(b.get("lead_priority", 9)))
	view["journey_guidance"] = {"directions": cues, "source": "public_geography_and_personal_memory"}
	if not view.get("journey_event", {}).is_empty() or not session.get_combat_encounter_options().is_empty():
		return
	view.decision.question = "想沿哪条线索走，还是先与这里的人打交道？"
	view.decision.rule = "选择下方路线即可出发；问路、进食和买卖不必先做。赶路期间，居民仍会继续自己的生活。"
	view.decision.stakes = []
	if view.player.get("hunger") == "extreme":
		view.decision.stakes.append(str(view.player.get("body_condition", "极饿会损耗健康，先考虑进食")))
	var satiation := int(view.player.get("satiation_remaining_minutes", 0))
	if satiation > 0:
		view.decision.stakes.append("这餐还能维持约%d小时%d分钟饱腹，可留给探路" % [satiation / 60, satiation % 60])
	if int(view.player.get("health", 100)) < 40 or int(view.player.get("fatigue", 0)) >= 8:
		view.decision.stakes.append("身体已经吃紧，远行前要考虑休整；并非必须把所有行动都点一遍")
	if here in [bindings.get("landing_host", ""), bindings.get("terrace_host", "")]:
		var host := str(session.context.location.get("journey_host_id", ""))
		if not session.PlayerLife.Journey.host_present(session, host):
			view.location.description = "灶间暂时没有人接待。这里并非全天候商店，你不必守着空屋等。可返回聚落岔路继续探路，傍晚再来碰面。"
	elif here.ends_with(".commons"):
		view.location.description = "聚落外，湖岸与坡上的路在这里分开。泊台旁有通往回水洞的小路，旧哨棚是上废灯台的起点；车场和客舍则在村路另一边。" if "echo_landing" in here else "坡田外的路在集地分开。哨棚通向断崖小径，车场连着两地来路，客舍在居民家中。"
		view.location.description += "\n你可以现在就选个去向，不必先找一份活做。"
	var sales: Array = view.actions.filter(func(row: Dictionary) -> bool: return str(row.action_id).begins_with("sell_food:") and row.get("can_execute", false))
	if int(view.player.get("food_count", 0)) > 4:
		view.decision.stakes.append("现场有人愿意付钱收粮，打开「出售食物」查看数量与价钱" if not sales.is_empty() else "暂时没有有钱且需要备粮的买方；可去居民作业地或傍晚的客舍碰面，不必继续采食")
