extends RefCounted

const Builder = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Needs = preload("res://scripts/sim/npc/npc_need_system.gd")
const Subsistence = preload("res://scripts/sim/npc/resident_subsistence.gd")
const Livelihood = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const Daily = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Market = preload("res://scripts/sim/economy/market_service.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")
const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Work = preload("res://scripts/sim/economy/resident_work_opportunities.gd")
const Danger = preload("res://scripts/sim/combat/world_danger_system.gd")
const PROFILE := {"version": 1, "help_wage": 3, "employer_food_limit": 8}


static func enabled(fixture: Dictionary) -> bool:
	return fixture.get("player_life", {}).get("version", 0) == 1


static func configure(fixture: Dictionary) -> String:
	var config: Variant = fixture.get("player_life", {})
	if not config is Dictionary:
		return "player_life_not_dictionary"
	if config.is_empty():
		return "player_life_missing_bootstrap" if fixture.has("player_life_generated") or fixture.get("resident_daily_life", {}).has("player_life") else ""
	if config.size() != PROFILE.size() or not PROFILE.keys().all(func(key: String) -> bool: return config.get(key) == PROFILE[key]):
		return "unsupported_player_life_profile"
	if not fixture.has("work_rules_generated"):
		return "player_life_requires_work_framework"
	if not fixture.has("world_danger_generated"):
		return "player_life_requires_body_recovery"
	if not Subsistence.enabled(fixture.get("resident_daily_life", {}).get("food_access", {}).get("subsistence", {})):
		return "player_life_requires_subsistence"
	if fixture.has("player_life_generated"):
		var generated: Variant = fixture.player_life_generated
		if not generated is Dictionary or generated.get("version") != 1 or str(generated.get("settlement_id", "")) == "":
			return "player_life_compiled_invalid"
		return "" if fixture.resident_daily_life.get("player_life", {}) == config else "player_life_compiled_mismatch"
	var location := str(fixture.location_id)
	var settlement := str(fixture.locations[location].get("generation_source", {}).get("settlement_id", ""))
	if settlement == "":
		return "player_life_requires_settlement"
	var tags: Array = fixture.player.get("tags", []).duplicate()
	for tag: String in ["player_controlled", "living_needs"]:
		if tag not in tags:
			tags.append(tag)
	fixture.player["tags"] = tags
	fixture.player.merge({"location_id": location, "settlement_id": settlement, "home_location_id": location,
		"age_years": 24, "alive": true, "life_status": "alive", "hunger": "low", "hunger_elapsed_hours": 0,
		"hunger_interval_hours": 6, "fatigue": 0, "daily_activity": "home", "daily_route_id": "",
		"daily_destination_id": "", "daily_travel_remaining": 0, "occupation_id": "traveler"}, true)
	fixture.resident_daily_life["player_life"] = config.duplicate(true)
	# The controlled body consumes food through needs, not an additional route toll.
	for route: Dictionary in fixture.get("travel_routes", []):
		route["food_cost"] = 0
	fixture["player_life_generated"] = {"version": 1, "settlement_id": settlement}
	return ""


# This owned read projection opts the controlled actor into shared resolvers,
# without handing it to NPC autonomy or creating another body/inventory store.
static func snapshot(context: Variant, stores: Dictionary, tick: Dictionary) -> Variant:
	var view: Variant = Builder.new().build_snapshot(context, stores, true, tick)
	var actor: Dictionary = stores.entity_store.get_entity(str(context.actor_id))
	actor["states"] = stores.state_store.list_states(str(context.actor_id))
	actor["location_id"] = str(actor.states.get("location_id", ""))
	view.entities.append(actor)
	return view


static func validate_save(fixture: Dictionary, stores: Dictionary, locations: Dictionary, player: String, here: String) -> String:
	if not enabled(fixture):
		return ""
	var state: Dictionary = stores.state_store.list_states(player)
	if "player_controlled" not in stores.entity_store.get_entity(player).get("tags", []) \
			or state.get("location_id") != here or not locations.has(here) \
			or state.get("settlement_id") != fixture.player_life_generated.settlement_id:
		return "save_player_life_identity_invalid"
	var route := str(state.get("daily_route_id", ""))
	var remaining: Variant = state.get("daily_travel_remaining", 0)
	if not (remaining is int or remaining is float) or float(remaining) != floor(float(remaining)) or remaining < 0:
		return "save_player_journey_invalid"
	if route != "":
		var matches: Array = fixture.get("travel_routes", []).filter(func(row: Dictionary) -> bool:
			return row.get("route_id") == route and row.get("from_location_id") == here \
				and row.get("to_location_id") == state.get("daily_destination_id") and remaining > 0 and remaining <= row.get("hours", 0))
		if matches.is_empty() or state.get("daily_activity") != "traveling":
			return "save_player_journey_invalid"
	elif remaining != 0 or state.get("daily_destination_id", "") != "":
		return "save_player_journey_invalid"
	return ""


static func tick(context: Variant, stores: Dictionary, time: Dictionary, profiles: Array, writer: Variant) -> String:
	var view: Variant = snapshot(context, stores, time)
	var actor: Dictionary = view.get_entity(str(context.actor_id))
	var data: Dictionary = Needs.new().resolve_tick(view, profiles, time, [actor])
	for result: Variant in data.results:
		if not writer.apply_result(result, stores):
			return "player_need_rejected"
	var state: Dictionary = actor.states
	if state.get("daily_route_id", "") != "":
		var remaining := maxi(int(state.daily_travel_remaining) - 1, 0)
		var result := Result.new()
		set_state(result, str(actor.id), "daily_travel_remaining", remaining)
		if remaining == 0:
			var destination := str(state.daily_destination_id)
			set_state(result, str(actor.id), "location_id", destination)
			set_state(result, str(actor.id), "daily_route_id", "")
			set_state(result, str(actor.id), "daily_destination_id", "")
			set_state(result, str(actor.id), "daily_activity", "home")
			set_state(result, str(actor.id), "fatigue", mini(int(state.get("fatigue", 0)) + 1, 10))
			var arrival_id := "fact.player_arrived.%s" % time.tick_event_id
			set_state(result, str(actor.id), "daily_presence_fact_id", arrival_id)
			result.add_fact({"fact_id": arrival_id, "fact_type": "actor_arrived",
				"actor_id": actor.id, "location_id": destination, "route_id": state.daily_route_id,
				"day": time.day, "hour": time.hour, "source_fact_ids": [state.get("daily_departure_fact_id", "")],
				"summary": "你沿道路抵达目的地，途中时间已经过去。"})
		result.mark_resolved("player_journey_progress")
		if not writer.apply_result(result, stores):
			return "player_journey_rejected"
		if remaining == 0 and not context.set_current_location(str(state.daily_destination_id)):
			return "player_arrival_location_invalid"
	return ""


static func options(session: Variant) -> Array:
	if not enabled(session.fixture_source_data):
		return []
	var view: Variant = snapshot(session.context, session.stores, session.get_time_summary())
	var actor: Dictionary = view.get_entity(str(session.context.actor_id))
	if actor.states.get("daily_route_id", "") != "":
		return [row("continue", "继续赶路", "尚需 %d 小时；途中不能交易或作业，饥饿仍会增长。" % actor.states.daily_travel_remaining)]
	if not session.get_combat_encounter_options().is_empty():
		return []
	var rows: Array = []
	var food: Dictionary = Danger.recovery_food(view, str(actor.id))
	if not food.is_empty() and actor.states.get("hunger", "none") != "none":
		rows.append(row("eat", "吃一份随身食物", "消耗1份食物和1小时，饥饿降低两级，也能支持伤后恢复。"))
	rows.append(row("rest", "休息一小时", "恢复疲劳，世界和饥饿不会暂停；伤势恢复还需要真实食物。"))
	for report: Dictionary in available_reports(session, view):
		var option := row("inquire:" + str(report.speaker_id), "问%s：那批粮后来呢？" % report.speaker_name,
			"对方会谈自己亲历的新情况；已经问过且没有变化时，不会反复出现。")
		option["report"] = report
		rows.append(option)
	var config: Dictionary = session.fixture_source_data.resident_daily_life
	for profile: Dictionary in gather_profiles(session, view, actor):
		if profile.workplace_id != actor.states.location_id:
			continue
		var id := "gather:" + str(profile.occupation_id)
		var reason := work_denial(session, actor, true)
		rows.append(row(id, "采集自己的口粮", "采得至多%d份归自己携带；公用资源枯竭或危险会使作业中断。" % profile.products[0].quantity, reason, int(profile.work_interval_hours)))
		for employer: Dictionary in employers(view, actor, session.fixture_source_data.player_life):
			rows.append(row("help:" + str(employer.id) + ":" + str(profile.occupation_id), "帮%s采收" % employer.display_name,
				"产物交给对方，完成时领取%d铜币。对方离开、缺钱或资源不足会停工。" % PROFILE.help_wage, reason, int(profile.work_interval_hours)))
	for entry: Dictionary in work_profiles(session, view, actor):
		var profile: Dictionary = entry.profile
		var plan := Recipe.new(view, session.registry).plan_inputs(profile, str(actor.id), "preview", Danger.hour(view.world_time))
		var reason := work_denial(session, actor, true)
		if reason == "" and not plan.ok:
			reason = Livelihood.new()._work_denial_label(str(plan.missing.denial))
		var effect := "实际投入材料、使用并磨损手边的工具，成品由你携带。"
		if entry.kind == "maintenance":
			effect = "投入本地材料修补耐久耗尽的工具；修补次数和可恢复耐久均有限。"
		else:
			var outputs: Array[String] = []
			for product: Dictionary in profile.products:
				outputs.append("%s×%d" % [session.registry.get_definition("item", str(product.item_def_id)).display_name, product.quantity])
			effect = "产物：%s。" % "、".join(outputs) + effect
		rows.append(row(entry.id, str(profile.label), effect, reason, int(profile.work_interval_hours)))
	for offer: Dictionary in offers(view, actor, config.food_access, session.stores, session.npc_livelihood_profiles):
		var offered_item: Dictionary = session.stores.item_store.get_item(str(offer.item_instance_id))
		var condition: Dictionary = offer.get("item", {}).get("condition", {})
		var detail := "耐久%d/%d，耗尽后可尝试在作坊修补。" % [condition.durability, condition.maximum_durability] if condition.has("durability") else ""
		var uses: Array[String] = []
		for profile: Dictionary in session.npc_livelihood_profiles:
			for spec: Dictionary in profile.get("work_recipe", {}).get("tools", []):
				if Recipe.matches(offered_item, spec.query):
					var use := "可用于%s，每次磨损%d。" % [profile.label, spec.wear]
					if use not in uses:
						uses.append(use)
					break
		detail += "".join(uses)
		rows.append(row("buy:" + str(offer.item_instance_id), "向%s买1件%s · %d铜币" % [offer.seller_name, offer.display_name, offer.unit_price],
			detail + "真实现货归你携带；对方保留基本口粮和自用作业工具。",
			"铜币不足" if Food.balance(view.get_items_for_holder(str(actor.id)), str(actor.id)) < int(offer.unit_price) else ""))
	return rows


static func row(id: String, label: String, hint: String, reason: String = "", hours: int = 1) -> Dictionary:
	return {"action_id": id, "event_type": "player_life", "label": label, "hint": hint,
		"hours": hours, "cost": "至多%d小时" % hours if hours > 1 else "1小时",
		"known_effect": hint, "tradeoff": reason,
		"can_execute": reason == "", "blocked_reason": reason, "action_type": "life"}


static func gather_profiles(session: Variant, view: Variant, actor: Dictionary) -> Array:
	return Subsistence.candidates(actor, session.npc_livelihood_profiles,
		session.fixture_source_data.resident_daily_life.food_access.subsistence, view)


static func employers(view: Variant, actor: Dictionary, config: Dictionary) -> Array:
	var rows: Array = []
	for person: Dictionary in view.get_entities_by_type("person"):
		if person.id == actor.id or "generated_resident" not in person.get("tags", []) \
				or person.states.get("location_id") != actor.states.location_id or person.states.get("daily_route_id", "") != "" \
				or not person.states.get("alive", true) or person.states.get("danger_opponent_id", "") != "":
			continue
		var held: Array = view.get_items_for_holder(str(person.id))
		var depot := Storage.stock_holder(view, str(person.id))
		if Food.food_quantity(held, str(person.id)) + Food.food_quantity(view.get_items_for_holder(depot), depot) >= int(config.employer_food_limit):
			continue
		if Food.balance(held, str(person.id)) >= int(config.help_wage):
			rows.append(person)
	return rows


static func offers(view: Variant, actor: Dictionary, config: Dictionary, stores: Dictionary, profiles: Array = []) -> Array:
	var rows: Array = []
	for seller: Dictionary in view.get_entities_by_type("person"):
		if seller.id == actor.id or seller.states.get("location_id") != actor.states.location_id \
				or seller.states.get("daily_route_id", "") != "" or not seller.states.get("alive", true):
			continue
		var holders: Array = [str(seller.id)]
		var depot := Storage.stock_holder(view, str(seller.id))
		if depot != "":
			holders.append(depot)
		for holder: String in holders:
			rows.append_array(Food.new()._seller_offers(view, seller, str(actor.id), holder,
				str(actor.states.location_id), config, stores, {}, false, view.world_time))
		for offer: Dictionary in Work.stock_offers(view, seller, str(actor.id), profiles, stores):
			if not Food.is_food(offer.item) and offer.item.item_def_id != Food.CURRENCY:
				rows.append(offer)
	return rows


static func work_profiles(session: Variant, view: Variant, actor: Dictionary) -> Array:
	var rows: Array = []
	for profile: Dictionary in session.npc_livelihood_profiles:
		if not Recipe.enabled(profile) or profile.get("settlement_id") != actor.states.get("settlement_id") \
				or profile.get("workplace_id") != actor.states.get("location_id") or int(profile.get("wage_amount", 0)) > 0:
			continue
		var own := profile.duplicate(true)
		own["actor_tags_all"] = ["player_controlled"]
		rows.append({"id": "work:" + str(own.work_recipe.recipe_id), "profile": own, "kind": "production"})
	for profile: Dictionary in Work.repair_profiles(view, actor, session.fixture_source_data.resident_daily_life):
		if profile.workplace_id != actor.states.location_id:
			continue
		var own := profile.duplicate(true)
		own["actor_tags_all"] = ["player_controlled"]
		rows.append({"id": "repair:" + str(own.work_recipe.recipe_id), "profile": own, "kind": "maintenance"})
	return rows


static func work_denial(session: Variant, actor: Dictionary, next_hour: bool = false) -> String:
	var config: Dictionary = session.fixture_source_data.resident_daily_life
	if not Daily.work_time("subsistence", posmod(session.current_hour + (1 if next_hour else 0), 24), config):
		return "天黑了，白天再作业"
	if int(actor.states.get("health", 100)) < 40:
		return "身体太虚弱，先休养"
	if int(actor.states.get("fatigue", 0)) >= int(config.rest_fatigue):
		return "太疲劳，先休息"
	return ""


static func execute(session: Variant, id: String) -> Dictionary:
	var selected: Array = options(session).filter(func(option: Dictionary) -> bool: return option.action_id == id and option.can_execute)
	if selected.is_empty():
		return {"success": false, "error": "player_life_option_unavailable"}
	var actor := str(session.context.actor_id)
	if id == "continue":
		var advanced: Dictionary = session.advance_time(1, "player_journey")
		var remaining: int = session.stores.state_store.get_state(actor, "daily_travel_remaining", 0)
		return feedback(advanced, "沿路前行了一小时，尚需%d小时。" % remaining if remaining > 0 else "已经抵达%s。" % session.context.location.get("display_name", "目的地"))
	if id == "rest":
		var before: Variant = session.get_snapshot()
		var recovered: Dictionary = session.recover_from_danger()
		var after: Variant = session.get_snapshot()
		return feedback(recovered, "休息一小时，疲劳%d→%d，健康%d→%d；消耗%d份食物，还剩%d份。伤势恢复需要食物与持续休养。" % [
			before.player.fatigue, after.player.fatigue, before.player.health, after.player.health,
			int(before.player.food_count) - int(after.player.food_count), after.player.food_count])
	var view: Variant = snapshot(session.context, session.stores, session.get_time_summary())
	if id.begins_with("inquire:"):
		var report: Dictionary = selected[0].report
		var result := Result.new()
		result.add_fact({"fact_id": "fact.player_heard_update.%d" % session.elapsed_hours_since_start,
			"fact_type": "player_heard_livelihood_update", "actor_id": actor, "speaker_id": report.speaker_id,
			"location_id": session.context.location_id, "day": session.current_day, "hour": session.current_hour,
			"source_fact_ids": [report.update_id, report.contribution_id], "related_update_id": report.update_id,
			"contribution_id": report.contribution_id, "report_fact_type": report.fact_type,
			"summary": report.text})
		result.mark_resolved("player_heard_livelihood_update")
		if not session.writer.apply_result(result, session.stores):
			return {"success": false, "error": result.error_reason}
		return feedback(session.advance_time(1, "player_local_conversation"), report.text)
	if id == "eat":
		var food: Dictionary = Danger.recovery_food(view, actor)
		var result := Result.new()
		var fact_id := "fact.player_meal.%d" % session.elapsed_hours_since_start
		result.add_fact({"fact_id": fact_id, "fact_type": "actor_ate", "actor_id": actor, "source_id": actor,
			"location_id": session.context.location_id, "day": session.current_day, "hour": session.current_hour,
			"item_instance_id": food.item_instance_id, "summary": "你吃掉一份%s，饥饿减轻了。" % food.display_name})
		result.add_item_change({"operation": "consume", "item_instance_id": food.item_instance_id, "quantity": 1,
			"beneficiary_id": actor, "provider_id": actor, "source_fact_ids": [fact_id]})
		result.add_state_change({"entity_id": actor, "key": "hunger", "degrade": 2})
		set_state(result, actor, "hunger_elapsed_hours", 0)
		set_state(result, actor, "danger_rest_nourished_until", Danger.hour(session.get_time_summary()) + 6)
		result.mark_resolved("player_meal")
		if not session.writer.apply_result(result, session.stores):
			return {"success": false, "error": result.error_reason}
		return feedback(session.advance_time(1, "player_meal"), result.facts_added[0].summary)
	if id.begins_with("buy:"):
		for offer: Dictionary in offers(view, view.get_entity(actor), session.fixture_source_data.resident_daily_life.food_access, session.stores, session.npc_livelihood_profiles):
			if id != "buy:" + str(offer.item_instance_id) or int(offer.surplus) < 1:
				continue
			var summary := "你向%s支付%d枚铜币，买下1件%s，已放入行囊。" % [offer.seller_name, offer.unit_price, offer.display_name]
			var trade: Dictionary = Market.new().plan_trade(offer.policy, {"buyer_entity_id": actor,
				"item_instance_id": offer.item_instance_id, "quantity": 1, "quoted_unit_price": offer.unit_price,
				"exchange_id": "exchange.player_food.%d" % session.elapsed_hours_since_start, "summary": summary}, session.stores, session.get_time_summary())
			if not trade.get("success", false):
				return trade
			if not session.writer.apply_result(trade.transaction, session.stores):
				return {"success": false, "error": trade.transaction.error_reason}
			return feedback(session.advance_time(1, "player_purchase"), summary)
		return {"success": false, "error": "local_stock_changed"}
	return work(session, id)


static func work(session: Variant, id: String) -> Dictionary:
	var actor_id := str(session.context.actor_id)
	var view: Variant = snapshot(session.context, session.stores, session.get_time_summary())
	var actor: Dictionary = view.get_entity(actor_id)
	var parts := id.split(":")
	var employer := str(parts[1]) if parts[0] == "help" else ""
	var profile: Dictionary = {}
	var work_kind := "production"
	for candidate: Dictionary in gather_profiles(session, view, actor):
		if candidate.occupation_id == parts[-1] and candidate.workplace_id == actor.states.location_id:
			profile = candidate
	if id.begins_with("work:") or id.begins_with("repair:"):
		for entry: Dictionary in work_profiles(session, view, actor):
			if entry.id == id:
				profile = entry.profile
				work_kind = entry.kind
	if profile.is_empty():
		return {"success": false, "error": "work_site_unavailable"}
	var prepare := Result.new()
	if actor.states.get("daily_intent_id", "") != id:
		set_state(prepare, actor_id, "subsistence_elapsed_hours", 0)
	set_state(prepare, actor_id, "daily_intent_id", id)
	set_state(prepare, actor_id, "daily_activity", "foraging")
	var start_id := "fact.player_work_started.%d" % session.elapsed_hours_since_start
	prepare.add_fact({"fact_id": start_id, "fact_type": "player_work_started", "actor_id": actor_id,
		"location_id": session.context.location_id, "employer_id": employer, "day": session.current_day, "hour": session.current_hour,
		"summary": "你在现场开始%s。" % profile.label if employer == "" else "你接受在场者的采收短工，完成后当面交货收取报酬。"})
	set_state(prepare, actor_id, "daily_presence_fact_id", start_id)
	prepare.mark_resolved("player_work_started")
	if not session.writer.apply_result(prepare, session.stores):
		return {"success": false, "error": prepare.error_reason}
	var summary := "作业暂时中断，已经用掉的时间不会退回。"
	var hours := 0
	for index: int in range(int(profile.work_interval_hours)):
		if work_denial(session, actor, true) != "":
			summary = "天色或身体条件已不适合继续。已完成%d/%d小时；下次选择同一作业可接着做，换作业会重新准备。" % [int(session.stores.state_store.get_state(actor_id, "subsistence_elapsed_hours", 0)), profile.work_interval_hours]
			break
		var tick: Dictionary = session.advance_time(1, "player_work")
		if not tick.get("success", false):
			return tick
		hours += 1
		view = snapshot(session.context, session.stores, session.get_time_summary())
		actor = view.get_entity(actor_id)
		if not session.get_combat_encounter_options().is_empty() or work_denial(session, actor) != "":
			break
		var employer_row: Dictionary = view.get_entity(employer)
		if employer != "" and (employer_row.is_empty() or employer_row.states.get("location_id") != actor.states.location_id \
				or employer_row.states.get("daily_route_id", "") != "" or not employer_row.states.get("alive", true) \
				or employer_row.states.get("danger_opponent_id", "") != "" or Treasury.new(view).balance(employer) < int(PROFILE.help_wage)):
			summary = "雇主已经离开现场、遇险或无法支付。采收停止，未凭空发薪；可以改为自己采食。"
			break
		var time: Dictionary = session.get_time_summary()
		time.merge({"elapsed_hours": 1, "tick_event_id": "player_work.%d" % session.elapsed_hours_since_start}, true)
		var resolved: Dictionary = Livelihood.new().resolve_work_tick(view, session.npc_livelihood_profiles,
			time, session.fixture_source_data.resident_daily_life, session.registry,
			{"actor": actor, "profile": profile, "kind": work_kind, "output_holder": employer if employer != "" else actor_id})
		if resolved.has("error"):
			return {"success": false, "error": resolved.error}
		var completed := false
		for result: Variant in resolved.results:
			for fact: Dictionary in result.facts_added:
				if fact.get("fact_type") in ["npc_livelihood_produced", "npc_work_maintained"]:
					completed = true
					if employer != "":
						if not Treasury.new(view).append_payment(result, employer, actor_id, PROFILE.help_wage, str(fact.fact_id), Danger.hour(time)):
							return {"success": false, "error": "employer_payment_unavailable"}
						fact["employer_id"] = employer
						fact["wage_amount"] = PROFILE.help_wage
						fact["summary"] = "你帮%s完成采收，%d份产物交给对方，领取%d枚实际铜币。" % [view.get_entity(employer).display_name, profile.products[0].quantity, PROFILE.help_wage]
					summary = str(fact.summary)
				elif fact.get("fact_type") == "npc_livelihood_blocked_resource":
					summary = str(fact.summary)
			if not session.writer.apply_result(result, session.stores):
				return {"success": false, "error": result.error_reason}
		if completed or not resolved.events.is_empty():
			break
	var finish := Result.new()
	set_state(finish, actor_id, "daily_activity", "home")
	finish.mark_resolved("player_work_paused")
	if not session.writer.apply_result(finish, session.stores):
		return {"success": false, "error": finish.error_reason}
	return feedback({"success": true, "hours": hours}, summary)


static func feedback(result: Dictionary, body: String) -> Dictionary:
	result["player_life_feedback"] = {"status": "success" if result.get("success", false) else "blocked",
		"title": "行动之后", "body": body, "details": []}
	return result


static func observed_followups(session: Variant) -> Array:
	var rows: Array = []
	var facts: Array = session.stores.fact_store.list_facts()
	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if fact.get("fact_type") == "player_heard_livelihood_update" and fact.get("actor_id") == str(session.context.actor_id):
			rows.append({"fact_id": fact.fact_id, "source_fact_id": fact.related_update_id, "text": fact.summary})
			if rows.size() >= 3:
				break
			continue
		if fact.get("fact_type") not in ["npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"] \
				or not fact.get("observed_by_player", false):
			continue
		var source := _contribution(session, fact.get("source_fact_ids", []))
		if source == "":
			continue
		var name: String = session.stores.entity_store.get_entity(str(fact.target_id)).get("display_name", "眼前的人")
		rows.append({"fact_id": fact.fact_id, "source_fact_id": source,
			"text": "第%d天 %02d:00，你看见%s吃下了食物。这批库存有你参与采收的补充；混合存放后不逐份区分来源。" % [fact.day, fact.hour, name]})
		if rows.size() >= 3:
			break
	return rows


static func local_tick_summary(session: Variant, result: Dictionary) -> String:
	if session.stores.state_store.get_state(str(session.context.actor_id), "daily_route_id", "") != "":
		return "路程仍在继续，尚看不到目的地的情况。"
	var summaries: Array[String] = []
	var witnessed := {}
	for collection: String in ["results", "livelihood_results", "observed_need_results", "observed_autonomous_results", "danger_results"]:
		for transaction: Dictionary in result.get(collection, []):
			for fact: Dictionary in transaction.get("facts_added", []):
				if fact.get("location_id", fact.get("actual_location_id", "")) != session.context.location_id or witnessed.has(fact.get("fact_id")):
					continue
				if fact.get("fact_type") not in ["npc_livelihood_produced", "npc_work_maintained", "actor_arrived", "npc_daily_arrived"] \
						and not fact.get("observed_by_player", false):
					continue
				var summary := str(fact.get("summary", ""))
				if summary != "":
					witnessed[fact.fact_id] = true
					summaries.append(summary)
					if summaries.size() >= 2:
						return "\n".join(summaries)
	return "\n".join(summaries)


static func available_reports(session: Variant, view: Variant) -> Array:
	var reports: Array = []
	var heard := {}
	var heard_outcomes := {}
	for fact: Dictionary in session.stores.fact_store.list_facts():
		if fact.get("fact_type") == "player_heard_livelihood_update" and fact.get("actor_id") == str(session.context.actor_id):
			heard[str(fact.related_update_id)] = true
			heard_outcomes["%s|%s|%s" % [fact.get("speaker_id", ""), fact.get("contribution_id", ""), fact.get("report_fact_type", "")]] = true
	for person: Dictionary in view.get_entities_by_type("person"):
		if person.id == session.context.actor_id or person.states.get("location_id") != session.context.location_id \
				or person.states.get("daily_route_id", "") != "" or not person.states.get("alive", true):
			continue
		var facts: Array = view.get_facts_by_actor(str(person.id))
		for index: int in range(facts.size() - 1, -1, -1):
			var fact: Dictionary = facts[index]
			if fact.get("actor_id") != person.id or heard.has(str(fact.fact_id)) \
					or fact.get("fact_type") not in ["household_pantry_stored", "household_food_delivered", "npc_self_meal", "npc_household_shared_food"]:
				continue
			var source := _contribution(session, fact.get("source_fact_ids", []))
			if source == "" or heard_outcomes.has("%s|%s|%s" % [person.id, source, fact.fact_type]):
				continue
			reports.append({"speaker_id": person.id, "speaker_name": person.display_name, "update_id": fact.fact_id,
				"contribution_id": source, "fact_type": fact.fact_type,
				"text": "%s谈起你上次采收后的相关情况：第%d天，%s" % [person.display_name, fact.day, fact.summary]})
			break
	return reports


static func _contribution(session: Variant, sources: Array) -> String:
	var pending: Array = sources.duplicate()
	var visited := {}
	for index: int in range(64):
		if pending.is_empty():
			break
		var id := str(pending.pop_front())
		if visited.has(id):
			continue
		visited[id] = true
		var fact: Dictionary = session.stores.fact_store.get_fact(id)
		if fact.get("actor_id") == str(session.context.actor_id) and fact.get("fact_type") == "npc_livelihood_produced":
			return id
		pending.append_array(fact.get("source_fact_ids", []))
	return ""


static func set_state(result: Variant, actor: String, key: String, value: Variant) -> void:
	result.add_state_change({"entity_id": actor, "key": key, "to": value})
