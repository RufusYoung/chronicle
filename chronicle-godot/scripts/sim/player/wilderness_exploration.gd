extends RefCounted

const Setup = preload("res://scripts/sim/generation/wilderness_setup.gd")
const Brief = preload("res://scripts/sim/player/brief_actions.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Market = preload("res://scripts/sim/economy/market_service.gd")
const Sources = preload("res://scripts/sim/item/item_causal_sources.gd")
const Equipment = preload("res://scripts/sim/player/player_equipment.gd")
const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")


static func site_here(session: Variant) -> Dictionary:
	if not Setup.enabled(session.fixture_source_data):
		return {}
	var generated: Dictionary = session.fixture_source_data.wilderness_generated.sites
	for site: Dictionary in session.fixture_source_data.wilderness_rules.sites:
		if generated[site.id].location_id == str(session.context.location_id):
			return site
	return {}


static func conditions(session: Variant, site: Dictionary, after_minutes: int = 0) -> Dictionary:
	var minutes := int(session.elapsed_hours_since_start) * 60 + int(session.stores.state_store.get_state(str(session.context.actor_id), "player_action_minutes", 0)) + after_minutes
	var period := int(site.period_hours) * 60
	var offset := int(session.fixture_source_data.wilderness_generated.sites[site.id].phase_offset) * 60
	var phase := ((minutes + offset) % period) * 3 / period
	var boundary := ((minutes + offset) * 3 / period + 1) * period / 3 - (minutes + offset)
	return {"phase": phase, "name": ["退水，石面露出", "回水，低处渐湿", "涌水，窄石沿被淹"][phase],
		"changes_in_minutes": boundary, "epoch": (minutes + offset) * 3 / period,
		"night": (int(session.current_hour) + (after_minutes + int(session.stores.state_store.get_state(str(session.context.actor_id), "player_action_minutes", 0))) / 60) % 24 < 6 \
			or (int(session.current_hour) + (after_minutes + int(session.stores.state_store.get_state(str(session.context.actor_id), "player_action_minutes", 0))) / 60) % 24 >= 18}


static func deposit(session: Variant, site: Dictionary, feature: Dictionary) -> String:
	return str(session.fixture_source_data.wilderness_generated.sites[site.id].features[feature.id])


static func surveyed(session: Variant, owner: String) -> bool:
	return session.stores.fact_store.list_facts().any(func(f: Dictionary) -> bool:
		return f.get("fact_type") == "wilderness_survey" and f.get("actor_id") == str(session.context.actor_id) and f.get("target_id") == owner)


static func stock(session: Variant, owner: String) -> Array:
	if session.stores.state_store.get_state(owner, "location_id", "") != str(session.context.location_id):
		return []
	var items: Array = session.stores.item_store.list_items_for_owner(owner)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.item_instance_id) < str(b.item_instance_id))
	return items.filter(func(i: Dictionary) -> bool: return int(i.quantity) > 0)


static func rope(session: Variant) -> Dictionary:
	for item: Dictionary in session.stores.item_store.list_items_for_owner(str(session.context.actor_id)):
		if Recipe.matches(item, {"tags_all": ["rope"]}) and int(item.quantity) > 0 and int(item.get("condition", {}).get("durability", 0)) >= 1:
			return item
	return {}


static func outlook(session: Variant) -> Dictionary:
	var site := site_here(session)
	if site.is_empty():
		return {}
	var water := conditions(session, site)
	var lines: Array[String] = ["眼前水况：%s，约%d分钟后变化。%s" % [water.name, water.changes_in_minutes, "天暗，取物更险。" if water.night else ""]]
	var visible := []
	for feature: Dictionary in site.features:
		var owner := deposit(session, site, feature)
		var known := surveyed(session, owner)
		var items := stock(session, owner) if known else []
		var descriptions: Array[String] = []
		for item: Dictionary in items:
			descriptions.append("%s×%d（耐久%d/%d）" % [item.display_name, item.quantity, item.get("condition", {}).get("durability", 0), item.get("condition", {}).get("maximum_durability", 0)])
		var names: Array[String] = []
		for item: Dictionary in items:
			names.append("%s×%d" % [item.display_name, item.quantity])
		lines.append("%s：%s" % [feature.name, ("、".join(names) if not items.is_empty() else "已查过，眼下没有可取的东西。") if known else "尚未勘察；" + ("落脚处较稳。" if int(feature.exposure) == 0 else "狭窄石沿临水。")])
		visible.append({"id": owner, "name": feature.name, "surveyed": known, "items": descriptions})
	lines.append("退路：高处小径通往两村，不必把东西拿完才离开。")
	water.erase("epoch")
	return {"title": site.name, "body": "\n".join(lines), "description": site.description, "water": water, "features": visible}


static func options(session: Variant) -> Array:
	var site := site_here(session)
	if site.is_empty() or not session.get_combat_encounter_options().is_empty() or session.stores.state_store.get_state(str(session.context.actor_id), "daily_route_id", "") != "":
		return []
	var rows := []
	for feature: Dictionary in site.features:
		var owner := deposit(session, site, feature)
		if not surveyed(session, owner):
			rows.append(row("shore_survey:" + str(feature.id), "查看" + str(feature.name), "站在高处辨认实际物品和落脚处；10分钟，不下水，也不保证发现东西。", 10))
			continue
		for item: Dictionary in stock(session, owner):
			for method: String in ["hand", "rope"]:
				var plan := attempt_plan(session, site, feature, item, method)
				var hint := "%s%s\n耗%d疲劳；d6+敏捷%d 对 %d，成功%d/6。失败健康-%d，东西仍留在原处。%s" % [
					Equipment.purchase_description(session, item, "取得"), "先搭绳再靠近，磨损1耐久" if method == "rope" else "不使用绳具，直接踩近取物",
					plan.fatigue, plan.attribute, plan.difficulty, plan.chance, plan.damage,
					"行动中水势会变，已按较险水况计算。" if plan.crosses_phase else ""]
				var option := row("shore_take:" + str(feature.id) + ":" + str(item.item_instance_id) + ":" + method,
					("搭绳取1件" if method == "rope" else "徒手取1件") + str(item.display_name), hint, plan.minutes, plan.denial)
				option["wilderness_family"] = "取回" + str(item.display_name) + " · " + str(feature.name)
				option["item_instance_id"] = item.item_instance_id
				option["item_description"] = Equipment.purchase_description(session, item, "取得")
				option["choice_summary"] = "成功%d/6 · 疲劳+%d · 失手健康-%d%s" % [plan.chance, plan.fatigue, plan.damage, " · 绳耐久-1" if method == "rope" else ""]
				option["requires_confirmation"] = true
				rows.append(option)
	var water := conditions(session, site)
	var waiting := row("shore_wait", "等到水势变化，再作决定", "在高处等候；身体吃紧或遇险会提前停止，不保证下一阶段更容易。", int(water.changes_in_minutes))
	rows.append(waiting)
	return rows


static func row(id: String, label: String, hint: String, minutes: int, denial: String = "") -> Dictionary:
	return {"action_id": id, "event_type": "player_life", "label": label, "hint": hint, "known_effect": hint,
		"hours": 0, "minutes": minutes, "cost": "%d分钟" % minutes, "tradeoff": "",
		"can_execute": denial == "", "blocked_reason": denial, "action_type": "life", "life_group": "exploration", "foreground": true}


static func attempt_plan(session: Variant, site: Dictionary, feature: Dictionary, item: Dictionary, method: String) -> Dictionary:
	var actor := str(session.context.actor_id)
	var state: Dictionary = session.stores.state_store.list_states(actor)
	var minutes := 30 if method == "rope" else 20
	var water := conditions(session, site)
	var later := conditions(session, site, minutes)
	var level := maxi(int(water.phase), int(later.phase))
	var exposure := int(feature.exposure) + level
	var fatigue := 1 if method == "rope" else 2
	var attribute := int(state.get("dexterity", 10))
	var difficulty := 12 + exposure + int(state.get("fatigue", 0)) / 3 + (2 if water.night or later.night else 0) - (3 if method == "rope" else 0)
	var denial := ""
	if level == 2 and int(feature.exposure) == 2:
		denial = "水已淹没窄石沿；可等水退、查看近岸，或从高处离开"
	elif int(state.get("health", 100)) < 20:
		denial = "伤势过重，先休养；高处退路仍可走"
	elif int(state.get("fatigue", 0)) + fatigue > 9:
		denial = "体力不足以完成并安全退回；先休整或离开"
	elif method == "rope" and rope(session).is_empty():
		denial = "需要本人携带至少1耐久的绳具；可以先勘察、徒手尝试或回去找绳"
	elif method == "hand" and session.stores.fact_store.list_facts().any(func(f: Dictionary) -> bool:
		return f.get("fact_type") == "wilderness_attempt" and f.get("actor_id") == actor \
			and f.get("target_id") == deposit(session, site, feature) and not f.get("passed", true) and f.get("water_epoch") == water.epoch):
		denial = "刚才失足的落脚点已不稳；这轮水况下须改用绳具，或等水势改变"
	return {"minutes": minutes, "fatigue": fatigue, "attribute": attribute, "difficulty": difficulty,
		"chance": clampi(7 - (difficulty - attribute), 0, 6), "damage": maxi(1, 2 + exposure * 2 - (3 if method == "rope" else 0)),
		"denial": denial, "water_epoch": water.epoch, "crosses_phase": water.phase != later.phase, "item_id": item.item_instance_id}


static func execute(session: Variant, id: String) -> Dictionary:
	var offered := options(session).filter(func(r: Dictionary) -> bool: return r.action_id == id and r.can_execute)
	if offered.is_empty():
		return {"success": false, "error": "wilderness_option_unavailable"}
	if id == "shore_wait":
		var waited: Dictionary = session.PlayerLife.Situations.wait_here(session, int(offered[0].minutes))
		if waited.get("success", false):
			waited.player_life_feedback.body += "\n现在%s。" % conditions(session, site_here(session)).name
		return waited
	var site := site_here(session)
	var feature: Dictionary = site.features.filter(func(f: Dictionary) -> bool: return f.id == id.get_slice(":", 1))[0]
	var owner := deposit(session, site, feature)
	var actor := str(session.context.actor_id)
	var fact_id := "fact.wilderness." + Brief.stamp(session)
	var result := Result.new()
	var body := ""
	var compact := ""
	var title := "看清了" + str(feature.name)
	var minutes := 10
	var rng_before: int = session.challenge_rng.state
	if id.begins_with("shore_survey:"):
		var names: Array[String] = []
		var items := stock(session, owner)
		for item: Dictionary in items:
			names.append("%s×%d；%s" % [item.display_name, item.quantity, Equipment.purchase_description(session, item, "取得")])
		body = "这里没有可带走的实物。你没有下水，可以看看另一处，或者沿高处离开。" if names.is_empty() else "石缝里实际留着：\n" + "\n".join(names) + "\n东西尚未归你；是否取、取哪件、承担什么风险，由你决定。"
		compact = str(feature.name) + ("已查清：没有可取物。" if names.is_empty() else "已查清；东西还在石缝里，尚未取走。")
		result.add_fact({"fact_id": fact_id, "fact_type": "wilderness_survey", "actor_id": actor, "target_id": owner,
			"location_id": session.context.location_id, "day": session.current_day, "hour": session.current_hour,
			"observed_item_ids": items.map(func(i: Dictionary) -> String: return str(i.item_instance_id)),
			"observed_items": items.map(func(i: Dictionary) -> Dictionary: return {"id": i.item_instance_id, "name": i.display_name, "quantity": i.quantity}), "summary": body})
	else:
		var item_id := id.get_slice(":", 2)
		var method := id.get_slice(":", 3)
		var item: Dictionary = session.stores.item_store.get_item(item_id)
		var plan := attempt_plan(session, site, feature, item, method)
		minutes = int(plan.minutes)
		var roll: int = session.challenge_rng.randi_range(1, 6)
		var passed: bool = roll + int(plan.attribute) >= int(plan.difficulty)
		var sources: Array = []
		Sources.append_to(sources, item)
		if passed:
			Market.new()._add_stack_transfer(result, item, 1, actor, "wilderness", fact_id, fact_id, int(session.elapsed_hours_since_start))
			result.item_changes.back()["expected_holder"] = item.holder
			Sources.append_to(result.item_changes.back().source_fact_ids, item)
			body = "你带回了1件%s，它已进入行囊。原处实物减少1件；可使用、穿戴，或留给真正需要它的买方。" % item.display_name
			title = "取回" + str(item.display_name)
			compact = "取得%s×1。" % item.display_name
		else:
			var before := int(session.stores.state_store.get_state(actor, "health", 100))
			var after := maxi(1, before - int(plan.damage))
			result.add_state_change({"entity_id": actor, "key": "health", "to": after})
			body = "你脚下打滑，退回高处。健康%d→%d；%s仍在原处，没有收入行囊。这轮水况下不能再徒手踏同一落点。" % [before, after, item.display_name]
			title = "失足后撤回"
			compact = "失足撤回，健康%d→%d；没有取得物品。" % [before, after]
		var fatigue := int(session.stores.state_store.get_state(actor, "fatigue", 0))
		result.add_state_change({"entity_id": actor, "key": "fatigue", "to": fatigue + int(plan.fatigue)})
		body += "\n疲劳%d→%d。d6掷出%d + 敏捷%d / 难度%d。" % [fatigue, fatigue + int(plan.fatigue), roll, plan.attribute, plan.difficulty]
		compact += "疲劳+%d%s。" % [plan.fatigue, "，绳耐久-1" if method == "rope" else ""]
		if method == "rope":
			body += "\n" + wear_rope(session, result, rope(session), fact_id, sources)
		result.add_fact({"fact_id": fact_id, "fact_type": "wilderness_attempt", "actor_id": actor, "target_id": owner,
			"item_instance_id": item_id, "method": method, "passed": passed, "roll": roll, "difficulty": plan.difficulty,
			"water_epoch": plan.water_epoch, "location_id": session.context.location_id, "day": session.current_day,
			"hour": session.current_hour, "source_fact_ids": sources, "summary": body})
	Brief.append(result, session, minutes)
	result.mark_resolved("wilderness_action")
	if not session.writer.apply_result(result, session.stores):
		session.challenge_rng.state = rng_before
		return {"success": false, "error": result.error_reason}
	var response := Brief.advance(session, "wilderness_action", minutes)
	response["player_life_feedback"] = {"title": title, "body": body, "compact_body": compact, "details": [], "summary_details": []}
	return response


static func wear_rope(session: Variant, result: Variant, item: Dictionary, fact_id: String, sources: Array) -> String:
	var id := str(item.item_instance_id)
	var tick := int(session.elapsed_hours_since_start)
	if int(item.quantity) > 1:
		id = fact_id + ".rope"
		result.add_item_change({"operation": "split_stack", "item_instance_id": item.item_instance_id, "quantity": 1,
			"new_item_instance_id": id, "expected_holder": item.holder, "source_fact_ids": [fact_id], "updated_tick": tick})
	var remaining := int(item.condition.durability) - 1
	result.add_item_change({"operation": "adjust_durability", "item_instance_id": id, "to": remaining,
		"expected_holder": item.holder, "source_fact_ids": [fact_id], "updated_tick": tick})
	Sources.append_to(sources, item)
	return "%s实际磨损1，余%d耐久；不论取物成败都已使用。" % [item.display_name, remaining]


static func notes(session: Variant) -> Array:
	if not Setup.enabled(session.fixture_source_data):
		return []
	var entries := {}
	for fact: Dictionary in session.stores.fact_store.list_facts():
		if fact.get("actor_id") != str(session.context.actor_id):
			continue
		if fact.get("fact_type") == "wilderness_survey":
			entries[fact.target_id] = {"location_id": fact.location_id, "day": int(fact.day), "hour": int(fact.hour),
				"source_fact_id": fact.fact_id, "items": fact.get("observed_items", []).duplicate(true), "feature_id": fact.target_id,
				"legacy": not fact.has("observed_items")}
		elif fact.get("fact_type") == "wilderness_attempt" and fact.get("passed", false) and entries.has(fact.target_id):
			for item: Dictionary in entries[fact.target_id].items:
				if item.id == fact.item_instance_id:
					item.quantity = maxi(0, int(item.quantity) - 1)
	var rows := []
	for entry: Dictionary in entries.values():
		var names: Array[String] = []
		for item: Dictionary in entry.items:
			item.quantity = int(item.quantity)
			if int(item.quantity) > 0:
				names.append("%s×%d" % [item.name, item.quantity])
		entry["place"] = session.context.locations.get(entry.location_id, {}).get("display_name", "曾到过的浅岸")
		entry["text"] = "第%d天%02d时在%s勘察：%s。已扣除自己后来取走的东西；不更新远处现况。" % [entry.day, entry.hour, entry.place, "记得仍有" + "、".join(names) if not names.is_empty() else "未留下已知可取物"]
		if entry.legacy:
			entry.text = "第%d天%02d时在%s留下过勘察记录；详细内容见旅途记录，不倒填远处物品数量。" % [entry.day, entry.hour, entry.place]
		rows.append(entry)
	return rows
