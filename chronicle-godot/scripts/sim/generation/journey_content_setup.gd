extends RefCounted

const PATH := "res://data/sim/raw/content/echo_port_journeys_v1.json"


static func register_items(fixture: Dictionary, registry: Variant) -> String:
	if not fixture.get("journey_rules", {}) is Dictionary or not fixture.get("journey_rules", {}).get("item_defs", []) is Array:
		return "journey_definitions_invalid"
	for definition: Variant in fixture.get("journey_rules", {}).get("item_defs", []):
		if not definition is Dictionary or not registry.register_definition("item", str(definition.get("item_def_id", "")), definition):
			return "journey_item_definition_invalid"
	return ""


static func configure(fixture: Dictionary, registry: Variant) -> String:
	if not fixture.has("journey_rules"):
		return "journey_missing_rules" if fixture.has("journey_generated") else ""
	if not fixture.journey_rules is Dictionary:
		return "journey_rules_invalid"
	var pack: Dictionary = fixture.journey_rules
	var error := validate(pack, registry)
	if error != "":
		return error
	if not fixture.has("integration_generated"):
		return "journey_requires_integrated_world"
	if fixture.has("journey_generated"):
		var generated: Variant = fixture.journey_generated
		if not generated is Dictionary or not generated.get("bindings") is Dictionary or not generated.get("signature") is String:
			return "journey_compiled_invalid"
		if not generated.bindings.values().all(func(value: Variant) -> bool: return value is String):
			return "journey_bindings_invalid"
		for key: String in ["entity_ids", "item_ids", "route_ids"]:
			if not _marks_valid(generated.get(key)):
				return "journey_compiled_ids_invalid"
		return "" if fixture.journey_generated.signature == _signature(fixture) else "journey_signature_mismatch"
	var bindings := {}
	var entity_ids: Array = []
	var item_ids: Array = []
	var route_ids: Array = []
	for site: Dictionary in pack.sites:
		if not fixture.locations.has(site.parent):
			return "journey_parent_missing:" + str(site.parent)
		var id := "journey_location." + str(site.id)
		bindings[site.id] = id
		var parent: Dictionary = fixture.locations[site.parent]
		fixture.locations[id] = {"id": id, "display_name": site.name, "description": site.description,
			"tags": ["journey_site", "generated_local_detail"], "canon_origin": parent.get("canon_origin", {}).duplicate(true),
			"journey_purpose": site.purpose}
		_add_routes(fixture, str(site.parent), id, int(site.hours), route_ids)
	for host: Dictionary in pack.hosts:
		var candidates: Array = fixture.entities.filter(func(person: Dictionary) -> bool:
			return person.get("states", {}).get("settlement_id") == host.settlement \
				and person.get("states", {}).get("occupation_id") == host.occupation)
		if candidates.is_empty():
			return "journey_host_missing:" + str(host.id)
		var representatives: Array = fixture.entities.filter(func(e: Dictionary) -> bool: return e.has("representative_id")).map(func(e: Dictionary) -> String: return str(e.representative_id))
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if (a.id in representatives) != (b.id in representatives):
				return a.id not in representatives
			return str(a.id) < str(b.id))
		var person: Dictionary = candidates[0]
		var home := str(person.states.home_location_id)
		bindings[host.id] = home
		bindings[host.id + "_actor"] = person.id
		person["guesthouse_rules"] = {"version": 1, "location_id": home, "open_hour": 17, "close_hour": 24, "opening_score": 38}
		var place: Dictionary = fixture.locations[home]
		place["journey_purpose"] = host.purpose
		place["journey_host_id"] = person.id
		place["display_name"] = host.name
		place["description"] = "这户人家把灶间与一间空房留给行路人。主人仍要外出谋生，在家才接待客人。家里的粮柜不是公用货架。"
		place.tags.append("guesthouse")
		for resident: Dictionary in fixture.entities:
			if resident.get("states", {}).get("location_id") == home:
				resident.states.visible = true
		var commons := "generated_location." + str(host.settlement).trim_prefix("generated_settlement.") + ".commons"
		_add_routes(fixture, commons, home, 1, route_ids)
		# Finite opening stock belongs to this resident, not to a replenishing shop ledger.
		_add_item(fixture, str(host.id) + ".coins", "item.copper_coin", 24, str(person.id), item_ids)
		fixture.economic_generation_result.initial_currency_total += 24
		_add_item(fixture, str(host.id) + ".meals", "item.smoked_lake_fish", 6, str(person.id), item_ids)
		_add_item(fixture, str(host.id) + ".drinks", "item.hearth_malt_drink", 8, str(person.id), item_ids)
	for cache: Dictionary in pack.caches:
		var id := "journey_cache." + str(cache.id)
		var location := str(bindings.get(cache.location, cache.location))
		if not fixture.locations.has(location):
			return "journey_cache_location_missing"
		entity_ids.append(id)
		fixture.entities.append({"id": id, "type": "environment_detail", "display_name": cache.name,
			"description": "有限的物品留存在这里，不会因等待或重新进入而补满。", "tags": ["journey_cache"],
			"states": {"location_id": location, "visible": false}})
		for index: int in range(cache.items.size()):
			var item: Dictionary = cache.items[index]
			_add_item(fixture, str(cache.id) + "." + str(index), str(item.item_def_id), int(item.quantity), id, item_ids)
	fixture["journey_generated"] = {"bindings": bindings, "entity_ids": entity_ids, "item_ids": item_ids, "route_ids": route_ids}
	for event: Dictionary in pack.events:
		if not fixture.locations.has(str(bindings.get(event.location, event.location))):
			return "journey_event_location_missing:" + str(event.id)
	fixture.journey_generated["signature"] = _signature(fixture)
	return ""


static func validate(pack: Dictionary, registry: Variant) -> String:
	if pack.get("version") != 1:
		return "journey_version_unsupported"
	if not _keys_valid(pack, ["version", "item_defs", "sites", "hosts", "caches", "events"]):
		return "journey_unknown_rule"
	for key: String in ["item_defs", "sites", "hosts", "caches", "events"]:
		if not pack.get(key) is Array:
			return "journey_list_missing:" + key
	var ids := {}
	for key: String in ["sites", "hosts", "caches", "events"]:
		ids[key] = []
		for entry: Variant in pack[key]:
			if not entry is Dictionary or not entry.get("id") is String or str(entry.id).is_empty() or entry.id in ids[key]:
				return "journey_duplicate_or_invalid_id:" + key
			ids[key].append(entry.id)
	for cache: Dictionary in pack.caches:
		if not cache.get("location") is String or not cache.get("name") is String or not cache.get("items") is Array:
			return "journey_cache_invalid"
		for item: Variant in cache.items:
			if not item is Dictionary or not registry.has_definition("item", str(item.get("item_def_id", ""))) or not _integer(item.get("quantity"), 1, 99):
				return "journey_item_invalid"
	for site: Dictionary in pack.sites:
		if not _integer(site.get("hours"), 1, 6):
			return "journey_route_hours_invalid"
		for key: String in ["parent", "name", "description", "purpose"]:
			if not site.get(key) is String:
				return "journey_site_invalid:" + key
	for host: Dictionary in pack.hosts:
		for key: String in ["settlement", "occupation", "name", "purpose"]:
			if not host.get(key) is String:
				return "journey_host_invalid:" + key
	for event: Dictionary in pack.events:
		if not _keys_valid(event, ["id", "location", "title", "body", "cache", "host", "requires", "requires_done", "window", "choices"]):
			return "journey_unknown_event_field"
		for key: String in ["location", "title", "body"]:
			if not event.get(key) is String:
				return "journey_event_text_invalid"
		if not event.get("choices") is Array or event.choices.is_empty():
			return "journey_choices_missing"
		if event.has("cache") and event.cache not in ids.caches:
			return "journey_cache_reference_invalid"
		if event.has("host") and event.host not in ids.hosts:
			return "journey_host_reference_invalid"
		if not _marks_valid(event.get("requires", [])) or not _marks_valid(event.get("requires_done", [])):
			return "journey_requirements_invalid"
		for required: String in event.get("requires_done", []):
			if required not in ids.events or required == event.id:
				return "journey_event_reference_invalid"
		if event.has("window") and (not event.window is Array or event.window.size() != 2 or not event.window.all(func(h: Variant) -> bool: return _integer(h, 0, 23))):
			return "journey_window_invalid"
		var choices: Array = []
		for choice: Variant in event.choices:
			if not choice is Dictionary or not choice.get("id") is String or choice.id in choices:
				return "journey_choice_id_invalid"
			choices.append(choice.id)
			if not _keys_valid(choice, ["id", "label", "hours", "hint", "check", "success", "failure", "requires", "tool_tag", "tool_wear", "give", "payment", "trust"]):
				return "journey_unknown_choice_field"
			if not _integer(choice.get("hours"), 0, 6) or not choice.get("label") is String or not choice.get("hint") is String:
				return "journey_choice_invalid"
			if not _marks_valid(choice.get("requires", [])) or not _integer(choice.get("payment", 0), -99, 99) or not _integer(choice.get("trust", 0), -10, 10):
				return "journey_choice_cost_invalid"
			if (choice.has("give") or choice.has("payment") or choice.has("trust")) and not event.has("host"):
				return "journey_choice_host_missing"
			if choice.has("give") and (not choice.give is Dictionary or not registry.has_definition("item", str(choice.give.get("item_def_id", ""))) or not _integer(choice.give.get("quantity"), 1, 99)):
				return "journey_give_invalid"
			if choice.has("tool_tag") and (not choice.tool_tag is String or not _integer(choice.get("tool_wear"), 1, 10)):
				return "journey_tool_invalid"
			if choice.has("check") and (not choice.check is Dictionary or choice.check.get("attribute") not in ["strength", "dexterity", "perception", "constitution", "wisdom", "charisma"] or not _integer(choice.check.get("difficulty"), 1, 30) or not choice.has("failure")):
				return "journey_check_invalid"
			for key: String in ["success", "failure"]:
				if key == "failure" and not choice.has(key):
					continue
				var outcome: Variant = choice.get(key)
				if not outcome is Dictionary or not outcome.get("text") is String or not _marks_valid(outcome.get("marks", [])) or not _integer(outcome.get("health", 0), -30, 0) or not outcome.get("keep_open", false) is bool or not outcome.get("loot", []) is Array:
					return "journey_outcome_invalid"
				if not _keys_valid(outcome, ["text", "marks", "health", "keep_open", "loot"]):
					return "journey_unknown_outcome_field"
				var loot_defs: Array = []
				for loot: Variant in outcome.get("loot", []):
					if not loot is Dictionary or not event.has("cache") or not _integer(loot.get("quantity"), 1, 99) or not registry.has_definition("item", str(loot.get("item_def_id", ""))) or loot.item_def_id in loot_defs:
						return "journey_loot_invalid"
					loot_defs.append(loot.item_def_id)
					var cache: Dictionary = pack.caches.filter(func(c: Dictionary) -> bool: return c.id == event.cache)[0]
					if cache.location != event.location:
						return "journey_loot_remote"
					var stock := 0
					for item: Dictionary in cache.items:
						if item.item_def_id == loot.item_def_id:
							stock += int(item.quantity)
					if stock < int(loot.quantity):
						return "journey_loot_exceeds_source"
	return ""


static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high


static func _marks_valid(value: Variant) -> bool:
	return value is Array and value.all(func(v: Variant) -> bool: return v is String and not v.is_empty())


static func _keys_valid(value: Dictionary, keys: Array) -> bool:
	return value.keys().all(func(key: Variant) -> bool: return key in keys)


static func _add_routes(fixture: Dictionary, parent: String, child: String, hours: int, ids: Array) -> void:
	for pair: Array in [[parent, child], [child, parent]]:
		var id := "journey_route." + str(pair[0]) + "." + str(pair[1])
		ids.append(id)
		fixture.travel_routes.append({"route_id": id, "from_location_id": pair[0], "to_location_id": pair[1],
			"hours": hours, "food_cost": 0, "label": "前往" + str(fixture.locations[pair[1]].display_name),
			"narrative_title": "抵达", "narrative": str(fixture.locations[pair[1]].description)})


static func _add_item(fixture: Dictionary, id: String, definition: String, quantity: int, holder: String, ids: Array) -> void:
	var instance := "item_instance.journey." + id
	ids.append(instance)
	fixture.initial_items.append({"item_instance_id": instance, "item_def_id": definition,
		"holder": {"kind": "entity", "id": holder}, "quantity": quantity, "provenance": {"source": "journey_initial_stock_v1"}})


static func _signature(fixture: Dictionary) -> String:
	var generated: Dictionary = fixture.journey_generated.duplicate(true)
	generated.erase("signature")
	var locations := {}
	for id: String in generated.bindings.values():
		if fixture.locations.has(id):
			locations[id] = fixture.locations[id]
	var compiled := {"rules": fixture.journey_rules, "generated": generated, "locations": locations,
		"entities": fixture.entities.filter(func(e: Dictionary) -> bool: return e.id in generated.entity_ids),
		"hosts": fixture.entities.filter(func(e: Dictionary) -> bool: return e.has("guesthouse_rules")).map(func(e: Dictionary) -> Dictionary: return {"id": e.id, "guesthouse_rules": e.guesthouse_rules}),
		"items": fixture.initial_items.filter(func(i: Dictionary) -> bool: return i.item_instance_id in generated.item_ids),
		"routes": fixture.travel_routes.filter(func(r: Dictionary) -> bool: return r.route_id in generated.route_ids)}
	return JSON.stringify(JSON.parse_string(JSON.stringify(compiled)), "", true).sha256_text()


static func validate_save(fixture: Dictionary, stores: Dictionary) -> String:
	var rules: Dictionary = fixture.get("journey_rules", {})
	var ids: Array = rules.get("events", []).map(func(e: Dictionary) -> String: return str(e.id))
	var resolved := {}
	var hosts := {}
	for person: Dictionary in fixture.get("entities", []):
		if person.has("guesthouse_rules"):
			hosts[person.id] = person.guesthouse_rules
	for person: Dictionary in stores.entity_store.list_entity_rows():
		if person.get("guesthouse_rules", {}) != hosts.get(person.id, {}):
			return "save_guesthouse_host_rules_invalid"
	for fact: Dictionary in stores.fact_store.list_facts():
		if fact.get("fact_type") == "journey_learned":
			var sources: Array = fact.get("source_fact_ids", [])
			if sources.size() != 1:
				return "save_journey_knowledge_source_invalid"
			var origin: Dictionary = stores.fact_store.get_fact(str(sources[0]))
			if origin.get("fact_type") != "journey_choice" or origin.get("event_id") not in ids:
				return "save_journey_knowledge_source_invalid"
			var origin_event: Dictionary = rules.events.filter(func(e: Dictionary) -> bool: return e.id == origin.event_id)[0]
			var choices: Array = origin_event.choices.filter(func(c: Dictionary) -> bool: return c.id == origin.get("choice_id"))
			if choices.is_empty() or fact.get("target_id") not in choices[0].get("success" if origin.get("passed", false) else "failure", {}).get("marks", []):
				return "save_journey_knowledge_mark_invalid"
			continue
		if fact.get("fact_type") != "journey_choice":
			continue
		if fact.get("event_id") not in ids or not fact.get("closed") is bool or fact.get("actor_id") != str(fixture.player.id):
			return "save_journey_fact_invalid"
		var event: Dictionary = rules.events.filter(func(e: Dictionary) -> bool: return e.id == fact.event_id)[0]
		var choices: Array = event.choices.filter(func(c: Dictionary) -> bool: return c.id == fact.get("choice_id"))
		if choices.is_empty() or not fact.get("passed") is bool or not _integer(fact.get("roll"), 0, 6):
			return "save_journey_choice_invalid"
		var expected_location := str(fixture.journey_generated.bindings.get(event.location, event.location))
		if fact.get("location_id") != expected_location:
			return "save_journey_choice_location_invalid"
		var outcome: Dictionary = choices[0].get("success" if fact.passed else "failure", {})
		if outcome.is_empty() or fact.closed == outcome.get("keep_open", false):
			return "save_journey_choice_outcome_invalid"
		if resolved.has(fact.event_id):
			return "save_journey_already_closed"
		if fact.closed:
			resolved[fact.event_id] = true
	return ""
