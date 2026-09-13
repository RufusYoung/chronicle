extends RefCounted

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Combat = preload("res://scripts/sim/combat/combat_encounter_resolver.gd")
const Builder = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")


static func enabled(config: Dictionary) -> bool:
	return config.get("version", 0) == 1


static func hour(tick: Dictionary) -> int:
	return int(tick.get("day", 1)) * 24 + int(tick.get("hour", 0))


static func active(threat: Dictionary, tick: Dictionary, config: Dictionary) -> bool:
	return enabled(config) and "world_threat" in threat.get("tags", []) \
		and bool(threat.get("states", {}).get("alive", false)) \
		and int(threat.get("states", {}).get("health", 0)) > int(config.threat.retreat_health) \
		and int(threat.states.get("danger_retreat_until", 0)) <= hour(tick) \
		and int(tick.get("hour", 0)) >= int(config.threat.start_hour) \
		and int(tick.get("hour", 0)) < int(config.threat.end_hour)


static func person(snapshot: Variant, id: String) -> Dictionary:
	if id == str(snapshot.get_player_value("id", "player")):
		var states: Dictionary = snapshot.player.duplicate(true)
		states["location_id"] = str(snapshot.location.get("id", ""))
		return {"id": id, "display_name": snapshot.get_player_value("display_name", "旅人"),
			"states": states, "tags": []}
	return snapshot.get_entity(id)


static func opponent(snapshot: Variant, id: String, tick: Dictionary, config: Dictionary) -> Dictionary:
	if not enabled(config) or not bool(config.get("contacts_enabled", true)):
		return {}
	var actor := person(snapshot, id)
	var states: Dictionary = actor.get("states", {})
	if not bool(states.get("alive", true)) or states.get("daily_route_id", "") != "" \
			or int(states.get("danger_grace_until", 0)) > hour(tick):
		return {}
	var location := str(states.get("location_id", snapshot.location.get("id", "") if id == snapshot.player.get("id") else ""))
	for threat: Dictionary in snapshot.get_entities_by_type("creature"):
		if active(threat, tick, config) and threat.states.get("location_id") == location:
			return threat
	return {}


static func wounds(snapshot: Variant, id: String) -> Array:
	return snapshot.get_trait_instances(id).filter(func(row: Dictionary) -> bool:
		return row.get("trait_def_id") == "trait.combat_bruising" and row.get("status", "active") == "active" and row.get("stage_id") != "healed")


static func needs_recovery(snapshot: Variant, id: String) -> bool:
	return wounds(snapshot, id).any(func(row: Dictionary) -> bool: return int(row.get("recovery_progress", 0)) < 6)


static func known_danger(snapshot: Variant, id: String, location: String, now: int) -> Dictionary:
	var latest := {}
	for memory: Dictionary in snapshot.get_memories(id):
		if memory.get("memory_type") == "world_danger_seen" and memory.get("location_id") == location \
				and int(memory.get("expires_hour", 0)) > now and int(memory.get("observed_hour", 0)) <= now:
			if latest.is_empty() or int(memory.observed_hour) > int(latest.observed_hour):
				latest = memory
	return latest if latest.get("danger_present", true) else {}


func options(snapshot: Variant, actor_id: String, tick: Dictionary, config: Dictionary, registry: Variant) -> Array:
	var threat := opponent(snapshot, actor_id, tick, config)
	if threat.is_empty():
		return []
	var encounter := definition(snapshot, actor_id, threat, config)
	var resolver := Combat.new()
	resolver.configure(registry)
	var rows: Array = []
	for approach: Dictionary in encounter.approaches:
		var preview := resolver.preview(encounter, snapshot, str(approach.approach_id), actor_id)
		rows.append({"option_id": "world_combat:%s:%s" % [threat.id, approach.approach_id],
			"encounter_id": encounter.encounter_id, "enemy_id": threat.id, "approach_id": approach.approach_id,
			"label": approach.label, "hours": 1, "can_execute": preview.get("can_execute", false),
			"action_type": "danger", "world_danger": true, "encounter_description": encounter.description,
			"effect_description": approach.effect_description, "preview": preview})
	return rows


func definition(snapshot: Variant, actor_id: String, threat: Dictionary, config: Dictionary) -> Dictionary:
	var actor := person(snapshot, actor_id)
	var advantage := mini(int(actor.states.get("danger_advantage", 0)), 4)
	var injury := "combat_bruising" if wounds(snapshot, actor_id).is_empty() else ""
	var enemy: Dictionary = config.threat.duplicate(true)
	enemy.merge({"entity_id": threat.id, "display_name": threat.display_name, "danger_label": "领地冲突",
		"observable_tags": ["wildlife", "territorial", "charging"],
		"observable_features": ["只守着眼前这片觅食地，不会追到远处。", "身体状况 %d/%d；受到重创会退入灌丛。" % [int(threat.states.health), int(config.threat.health)],
			"已稳住的优势 %d/4；进攻或撤离时消耗。" % advantage]}, true)
	var fatigue_cost := 1 if int(actor.states.get("fatigue", 0)) < 10 else 0
	var hit := {"base_health_loss": 6, "fatigue_gain": fatigue_cost, "injury": injury,
		"injury_label": "战斗挫伤", "durability_slot": "body_outer", "durability_loss": 2}
	var safe := {"fatigue_gain": fatigue_cost, "durability_slot": "main_hand", "durability_loss": 1}
	return {"encounter_id": "world_danger." + str(threat.id), "enemy": enemy,
		"description": "这是仍在持续的交锋。每次选择占用一小时的周旋与寻找机会，世界其余地方照常生活。",
		"approaches": [
			{"approach_id": "attack", "label": "抓住空隙进攻", "score_target": "combat.attack", "attack_bonus": advantage,
				"action_tags": ["attack", "combat_melee"], "success": safe, "failure": hit,
				"effect_description": "成功削减对方健康，未重创前仍需继续交锋；消耗已积累优势。"},
			{"approach_id": "guard", "label": "稳住防守，寻找机会", "score_target": "combat.guard", "guard_bonus": 3,
				"difficulty": int(enemy.attack), "action_tags": ["defend"], "success": safe, "failure": hit,
				"effect_description": "成功积累 2 点优势，上限 4，改善下一次进攻或脱离；仍耗费时间与体力。"},
			{"approach_id": "withdraw", "label": "寻找退路，脱离接触", "score_target": "combat.escape", "escape_bonus": advantage,
				"difficulty": int(enemy.escape_difficulty), "action_tags": ["withdraw"], "success": safe, "failure": hit,
				"effect_description": "成功打开两小时离场窗口，可以沿原道路离开；失败会受伤，不能瞬移回家。"}
		]}


func resolve_round(snapshot: Variant, actor_id: String, threat: Dictionary, approach: String,
		roll: int, tick: Dictionary, config: Dictionary, registry: Variant) -> Variant:
	if threat.is_empty() or opponent(snapshot, actor_id, tick, config).get("id") != threat.get("id") or roll not in range(1, 7):
		var invalid := Result.new()
		invalid.mark_invalid_contract("world_danger", "world_danger_contact_or_roll_invalid")
		return invalid
	var resolver := Combat.new()
	resolver.configure(registry)
	var encounter := definition(snapshot, actor_id, threat, config)
	# Actor and absolute hour make NPC and player facts unique in the same encounter.
	encounter.encounter_id += "." + actor_id
	var result: Variant = resolver.resolve_attempt(encounter, snapshot, approach, roll, hour(tick), tick, actor_id)
	if result.contract_status != "resolved":
		return result
	var actor := person(snapshot, actor_id)
	var source: String = result.facts[0].fact_id
	result.facts[0]["location_id"] = threat.states.location_id
	result.facts_added[0]["location_id"] = threat.states.location_id
	var success: bool = result.narrative_result.outcome == "success"
	_change(result, actor_id, "danger_round_hour", hour(tick))
	_change(result, actor_id, "danger_opponent_id", threat.id)
	_change(result, actor_id, "danger_advantage", mini(int(actor.states.get("danger_advantage", 0)) + 2, 4) if approach == "guard" and success else 0)
	var description := "没能稳住局面，身体与装备承受了这次失手。"
	var ended := false
	var dispersed := false
	var enemy_health_after := int(threat.states.health)
	if success and approach == "attack":
		var damage := int(config.threat.damage) + maxi(int(result.narrative_result.total) - int(result.narrative_result.difficulty), 0)
		var remaining := maxi(int(threat.states.health) - damage, 1)
		enemy_health_after = remaining
		_change(result, str(threat.id), "health", remaining)
		description = "击退了它的扑撞，对方健康从 %d 降至 %d。" % [int(threat.states.health), remaining]
		if remaining <= int(config.threat.retreat_health):
			_change(result, str(threat.id), "danger_retreat_until", hour(tick) + int(config.retreat_hours))
			_change(result, str(threat.id), "visible", false)
			ended = true
			dispersed = true
			description += "它受创后缩回这片地的灌丛，暂时不再阻拦来人。"
	elif success and approach == "guard":
		description = "稳住了距离，积累 2 点优势。下一次进攻或脱离更有把握，对方还没有离开。"
	elif success and approach == "withdraw":
		ended = true
		_change(result, actor_id, "danger_grace_until", hour(tick) + 3)
		description = "脱开了近身接触，仍在现场边缘。有两小时可以沿道路离开，不会自动回到家。"
	if ended:
		_change(result, actor_id, "danger_opponent_id", "")
		_change(result, actor_id, "danger_advantage", 0)
	if "generated_resident" in actor.get("tags", []):
		_change(result, actor_id, "daily_activity", "blocked")
		_change(result, actor_id, "daily_activity_reason", "刚刚交锋，无法同时上工；需要离开危险地带或休养")
	var fact := _fact("world_danger_round", actor_id, tick, threat, description)
	fact.merge({"source_fact_ids": [source], "approach_id": approach, "outcome": result.narrative_result.outcome,
		"threat_dispersed": dispersed, "enemy_health_before": int(threat.states.health), "enemy_health_after": enemy_health_after,
		"ended": ended, "health_before": actor.states.get("health", 100), "applied_costs": result.narrative_result.applied_costs})
	result.add_fact(fact)
	_remember(result, actor_id, threat, tick, config, fact.fact_id, not dispersed)
	result.narrative_result.title = "脱离交锋" if ended else "交锋仍在继续"
	result.narrative_result.summary = (str(actor.display_name) + "：" if "generated_resident" in actor.get("tags", []) else "") + description
	result.narrative_result["location_id"] = threat.states.location_id
	result.narrative_result["world_danger"] = true
	result.narrative_result["ended"] = ended
	return result


func run_tick(context: Variant, stores: Dictionary, tick: Dictionary, config: Dictionary,
		registry: Variant, writer: Variant, contacts_only: bool = false) -> Dictionary:
	var output := {"ok": true, "results": [], "events": []}
	if not enabled(config):
		return output
	var snapshot: Variant = Builder.new().build_snapshot(context, stores, true, tick)
	if not contacts_only:
		var recovering: Variant = recovery(snapshot, tick, config)
		if not writer.apply_result(recovering, stores):
			return {"ok": false, "error": recovering.error_reason}
		output.results.append(recovering)
		output.events.append_array(recovering.facts_added)
	var ids: Array = snapshot.get_entities_by_type("person").filter(func(row: Dictionary) -> bool:
		return "generated_resident" in row.get("tags", [])).map(func(row: Dictionary) -> String: return str(row.id))
	ids.append(str(snapshot.player.get("id", "player")))
	ids.sort()
	for id: String in ids:
		snapshot = Builder.new().build_snapshot(context, stores, true, tick)
		var actor := person(snapshot, id)
		var old := str(actor.states.get("danger_opponent_id", ""))
		var threat := opponent(snapshot, id, tick, config)
		var result := Result.new()
		if threat.is_empty():
			if old != "":
				var previous: Dictionary = snapshot.get_entity(old)
				if previous.get("states", {}).get("location_id") == actor.states.get("location_id") and actor.states.get("daily_route_id", "") == "":
					var fact := _fact("world_danger_cleared", id, tick, previous, "%s亲眼看到对方退入灌丛，眼前暂时可以通行。" % actor.display_name)
					result.add_fact(fact)
					_remember(result, id, previous, tick, config, fact.fact_id, false)
				_change(result, id, "danger_opponent_id", "")
				_change(result, id, "danger_advantage", 0)
		elif old == "":
			var place: Dictionary = context.locations.get(str(threat.states.location_id), {})
			var fact := _fact("world_danger_contact", id, tick, threat, "%s在%s撞见了%s，原定活动被打断。" % [actor.display_name, place.get("display_name", "这里"), threat.display_name])
			result.add_fact(fact)
			_remember(result, id, threat, tick, config, fact.fact_id)
			_change(result, id, "danger_opponent_id", threat.id)
			_change(result, id, "danger_advantage", 0)
			if "generated_resident" in actor.get("tags", []):
				_change(result, id, "daily_activity", "blocked")
				_change(result, id, "daily_activity_reason", "眼前有危险，暂时无法作业")
		elif not contacts_only and int(actor.states.get("danger_round_hour", 0)) < hour(tick):
			var approach := "withdraw"
			var companions: int = snapshot.get_entities_by_type("person").filter(func(row: Dictionary) -> bool:
				return row.states.get("location_id") == threat.states.location_id and row.states.get("daily_route_id", "") == "" \
					and int(row.states.get("age_years", 0)) >= 18).size()
			if int(actor.states.get("health", 100)) >= 65 and int(actor.states.get("fatigue", 0)) < 7 \
					and (actor.states.get("occupation_id") == "watch_hand" or (companions >= 2 and actor.states.get("temperament") != "cautious")):
				approach = "guard" if int(actor.states.get("danger_advantage", 0)) == 0 else "attack"
			var roll := 1 + posmod(hash("%s:%s:%d:%d" % [id, threat.id, hour(tick), int(config.get("seed", 1))]), 6)
			result = resolve_round(snapshot, id, threat, approach, roll, tick, config, registry)
			if result.contract_status == "invalid_contract":
				return {"ok": false, "error": result.error_reason}
			result.facts_added.back()["decision_basis"] = {"health": actor.states.get("health", 100),
				"fatigue": actor.states.get("fatigue", 0), "temperament": actor.states.get("temperament", ""),
				"present_adults": companions, "occupation": actor.states.get("occupation_id", ""), "approach": approach}
		if result.is_empty():
			continue
		result.mark_resolved("world_danger")
		if not writer.apply_result(result, stores):
			return {"ok": false, "error": result.error_reason}
		output.results.append(result)
		output.events.append_array(result.facts_added.filter(func(row: Dictionary) -> bool: return str(row.get("fact_type", "")).begins_with("world_danger")))
	return output


func recovery(snapshot: Variant, tick: Dictionary, config: Dictionary) -> Variant:
	var result := Result.new()
	for threat: Dictionary in snapshot.get_entities_by_type("creature"):
		if "world_threat" in threat.get("tags", []) and not active(threat, tick, config):
			_change(result, str(threat.id), "visible", false)
			if int(threat.states.get("health", 0)) < int(config.threat.health):
				_change(result, str(threat.id), "health", int(threat.states.health) + 1)
		elif active(threat, tick, config) and not bool(threat.states.get("visible", false)):
			_change(result, str(threat.id), "visible", true)
	var actors: Array = snapshot.get_entities_by_type("person")
	actors.append(person(snapshot, str(snapshot.player.get("id", "player"))))
	for actor: Dictionary in actors:
		var id := str(actor.id)
		var is_player := id == str(snapshot.player.get("id", "player"))
		if (not is_player and "generated_resident" not in actor.get("tags", [])) or actor.states.get("daily_activity") != "resting" \
				or actor.states.get("daily_route_id", "") != "" \
				or not opponent(snapshot, id, tick, config).is_empty():
			continue
		if is_player and int(actor.states.get("fatigue", 0)) > 0:
			_change(result, id, "fatigue", int(actor.states.fatigue) - 1)
		if actor.states.get("hunger") == "extreme" or (is_player and int(actor.states.get("danger_rest_nourished_until", 0)) < hour(tick)):
			continue
		var injuries := wounds(snapshot, id)
		if injuries.is_empty() and int(actor.states.get("health", 100)) >= 100:
			continue
		var fact := {"fact_id": "fact.world_danger_recovery.%s.%d" % [id, hour(tick)],
			"fact_type": "actor_rested_with_injury", "actor_id": id, "source_id": id,
			"location_id": actor.states.location_id, "day": tick.day, "hour": tick.hour,
			"summary": "%s休养了一小时，这一小时没有上工。" % actor.display_name,
			"source_fact_ids": [], "trait_instance_ids": [], "required_recovery_hours": config.recovery_hours}
		for injury: Dictionary in injuries:
			fact.source_fact_ids.append_array(injury.get("source_fact_ids", []))
			fact.trait_instance_ids.append(injury.trait_instance_id)
		result.add_fact(fact)
		_change(result, id, "health", mini(int(actor.states.get("health", 100)) + int(config.rest_health_gain), 100))
		for injury: Dictionary in injuries:
			result.add_character_feature_change({"operation": "recover_trait", "trait_instance_id": injury.trait_instance_id,
				"source_fact_id": fact.fact_id, "required_hours": config.recovery_hours})
	result.mark_resolved("world_danger_recovery")
	return result


static func recovery_food(snapshot: Variant, id: String) -> Dictionary:
	for item: Dictionary in snapshot.get_items_for_holder(id):
		if Food.is_food(item) and int(item.get("quantity", 0)) > 0:
			return item
	return {}


# Associate resumed physical work with a real, still-active retreat window.
# The player may have contributed damage while an NPC landed the final blow.
static func work_clearance(snapshot: Variant, actor: String, location: String, tick: Dictionary, config: Dictionary) -> Dictionary:
	if not enabled(config):
		return {}
	if snapshot.get_entity_state(actor, "location_id", "") != location or snapshot.get_entity_state(actor, "daily_route_id", "") != "":
		return {}
	var clear := {}
	var contribution := ""
	var facts: Array = snapshot.get_facts()
	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if fact.get("location_id") != location or fact.get("fact_type") != "world_danger_round":
			continue
		if clear.is_empty():
			if not fact.get("threat_dispersed", false):
				continue
			clear = fact
			if hour(tick) - hour(clear) >= int(config.retreat_hours) or active(snapshot.get_entity(str(clear.target_id)), tick, config):
				return {}
		elif fact.get("threat_dispersed", false):
			break
		if fact.get("target_id") != clear.target_id:
			continue
		if hour(clear) - hour(fact) > 6:
			break
		if fact.get("actor_id") == str(snapshot.player.id) and int(fact.get("enemy_health_after", 0)) < int(fact.get("enemy_health_before", 0)):
			contribution = str(fact.fact_id)
			break
	if clear.is_empty() or contribution == "":
		return {}
	for fact: Dictionary in snapshot.get_facts_by_actor(actor):
		if fact.get("actor_id") == actor and fact.get("fact_type") == "world_danger_contact" and fact.get("target_id") == clear.target_id \
				and hour(fact) <= hour(clear) and hour(clear) - hour(fact) <= 24:
			return {"fact_id": clear.fact_id, "source_fact_ids": [clear.fact_id, contribution, fact.fact_id]}
	return {}


static func _change(result: Variant, id: String, key: String, value: Variant) -> void:
	result.add_state_change({"entity_id": id, "key": key, "to": value})


static func _fact(kind: String, id: String, tick: Dictionary, threat: Dictionary, summary: String) -> Dictionary:
	return {"fact_id": "fact.%s.%s.%d" % [kind, id, hour(tick)], "fact_type": kind,
		"actor_id": id, "source_id": id, "target_id": threat.id, "location_id": threat.states.location_id,
		"day": tick.day, "hour": tick.hour, "summary": summary}


static func _remember(result: Variant, id: String, threat: Dictionary, tick: Dictionary, config: Dictionary, fact: String, present: bool = true) -> void:
	result.add_memory({"memory_id": "memory." + fact, "owner_id": id, "subject_id": threat.id,
		"memory_type": "world_danger_seen", "source_fact_id": fact, "location_id": threat.states.location_id,
		"observed_hour": hour(tick), "expires_hour": hour(tick) + int(config.memory_hours),
		"danger_present": present, "summary": "亲眼见到这里有危险，在一段时间内不轻易返回。" if present else "亲眼见到眼前的威胁退却，暂时不再因此回避。"})
