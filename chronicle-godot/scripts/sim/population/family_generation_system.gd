extends RefCounted
class_name V5FamilyGenerationSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)

const ATTRIBUTE_KEYS := [
	"strength",
	"dexterity",
	"wisdom",
	"charisma",
	"constitution",
	"perception",
]


func resolve_daily_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		network_config: Dictionary,
		locations: Array
) -> Dictionary:
	var config: Dictionary = network_config.get("family_generation", {})
	if not bool(config.get("enabled", false)):
		return {"results": [], "events": []}
	var day := int(tick_event.get("day", 0))
	if day <= 0:
		return {"results": [], "events": []}

	var partnership_interval := maxi(int(config.get(
		"partnership_interval_days", 365
	)), 1)
	var conception_interval := maxi(int(config.get(
		"conception_interval_days", 90
	)), 1)
	var gestation_days := maxi(int(config.get("gestation_days", 280)), 1)
	var runs_partnership := day % partnership_interval == 0
	var runs_conception := day % conception_interval == 0
	var runs_birth := (
		day >= gestation_days
		and (day - gestation_days) % conception_interval == 0
	)
	var death_facts := _facts_on_day(snapshot, "resident_died", day)
	if (
		not runs_partnership
		and not runs_conception
		and not runs_birth
		and death_facts.is_empty()
	):
		return {"results": [], "events": []}

	var result = TransactionResultModel.new()
	var events: Array = []
	if not death_facts.is_empty():
		_append_inheritances(result, snapshot, death_facts, day, events)
		_append_empty_household_retirements(
			result, snapshot, death_facts, day, events
		)
	if runs_birth:
		_append_due_births(
			result, snapshot, network_config, config, day, events
		)
	if runs_conception:
		_append_conceptions(
			result, snapshot, network_config, config, day, events
		)
	if runs_partnership:
		_append_partnerships(
			result, snapshot, network_config, config, locations, day, events
		)
	if result.is_empty():
		return {"results": [], "events": events}
	result.mark_resolved("family_generation")
	return {"results": [result], "events": events}


func _append_inheritances(
		result: Variant,
		snapshot: Variant,
		death_facts: Array,
		day: int,
		events: Array
) -> void:
	for death_fact: Dictionary in death_facts:
		var death_fact_id := str(death_fact.get("fact_id", ""))
		var dead_id := str(death_fact.get("target_id", ""))
		if (
			dead_id == ""
			or _fact_references(
				snapshot, "resident_inheritance_transferred",
				"death_fact_id", death_fact_id
			)
		):
			continue
		var household_id := str(death_fact.get("household_id", ""))
		var heir_id := _inheritance_heir(snapshot, dead_id, household_id)
		if heir_id == "":
			continue
		var inherited_items: Array[String] = []
		for item: Dictionary in snapshot.get_items():
			var holder: Dictionary = item.get("holder", {})
			if (
				str(holder.get("kind", "")) == "entity"
				and str(holder.get("id", "")) == dead_id
			):
				inherited_items.append(str(item.get(
					"item_instance_id", item.get("id", "")
				)))
		if inherited_items.is_empty():
			continue
		inherited_items.sort()
		var inheritance_fact_id := (
			"fact.resident_inheritance_transferred.%s.day%d"
			% [_safe_id(dead_id), day]
		)
		result.add_fact({
			"fact_id": inheritance_fact_id,
			"fact_type": "resident_inheritance_transferred",
			"actor_id": heir_id,
			"target_id": dead_id,
			"death_fact_id": death_fact_id,
			"household_id": household_id,
			"heir_id": heir_id,
			"item_instance_ids": inherited_items.duplicate(),
			"source_fact_ids": [death_fact_id],
			"day": day,
			"summary": "%s接下了%s留下的 %d 件物品。" % [
				_entity_name(snapshot, heir_id),
				_entity_name(snapshot, dead_id),
				inherited_items.size(),
			],
		})
		var inherited_lookup: Dictionary = {}
		for item_id: String in inherited_items:
			inherited_lookup[item_id] = true
		var loadout: Dictionary = snapshot.get_equipment_loadout(dead_id)
		for slot_value: Variant in (loadout.get("slots", {}) as Dictionary).keys():
			var slot_id := str(slot_value)
			var equipped_value: Variant = (
				loadout.get("slots", {}) as Dictionary
			).get(slot_value)
			var equipped_id := "" if equipped_value == null else str(
				equipped_value
			)
			if equipped_id != "" and inherited_lookup.has(equipped_id):
				result.add_equipment_change({
					"operation": "equipment_clear",
					"entity_id": dead_id,
					"slot_id": slot_id,
					"source_fact_ids": [inheritance_fact_id],
					"updated_tick": day,
				})
		for item_id: String in inherited_items:
			result.add_item_change({
				"operation": "transfer",
				"item_instance_id": item_id,
				"new_holder": {"kind": "entity", "id": heir_id},
				"source_fact_ids": [inheritance_fact_id],
				"updated_tick": day,
			})
		result.add_chronicle_entry({
			"entry_id": "chronicle.resident_inheritance.%s.day%d" % [
				_safe_id(dead_id), day
			],
			"subject_id": household_id,
			"title": "%s留下的物品" % _entity_name(snapshot, dead_id),
			"body": "%s接管了遗留物品，物品履历继续保留原持有者与死亡来源。" % _entity_name(
				snapshot, heir_id
			),
			"source_fact_ids": [inheritance_fact_id],
			"day": day,
		})
		events.append({
			"event_type": "resident_inheritance_transferred",
			"resident_id": dead_id,
			"heir_id": heir_id,
			"item_count": inherited_items.size(),
			"day": day,
		})


func _append_empty_household_retirements(
		result: Variant,
		snapshot: Variant,
		death_facts: Array,
		day: int,
		events: Array
) -> void:
	var active_households: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		var household_id := str(snapshot.get_entity_state(
			person_id, "household_id", ""
		))
		if household_id != "":
			active_households[household_id] = true
	var death_by_household: Dictionary = {}
	for death_fact: Dictionary in death_facts:
		var household_id := str(death_fact.get("household_id", ""))
		if household_id != "":
			death_by_household[household_id] = str(death_fact.get(
				"fact_id", ""
			))
	for household: Dictionary in snapshot.get_entities_by_type("household"):
		var household_id := str(household.get("id", ""))
		if (
			household_id == ""
			or active_households.has(household_id)
			or not death_by_household.has(household_id)
		):
			continue
		_append_household_retirement(
			result,
			snapshot,
			household_id,
			str(death_by_household.get(household_id, "")),
			"last_member_died",
			day,
			events
		)


func _append_due_births(
		result: Variant,
		snapshot: Variant,
		network_config: Dictionary,
		config: Dictionary,
		day: int,
		events: Array
) -> void:
	var resolved: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) in [
			"resident_born", "resident_conception_ended"
		]:
			resolved[str(fact.get("conception_fact_id", ""))] = true
	for conception: Dictionary in snapshot.get_facts():
		if str(conception.get("fact_type", "")) != "resident_conceived":
			continue
		var conception_fact_id := str(conception.get("fact_id", ""))
		if (
			resolved.has(conception_fact_id)
			or int(conception.get("due_day", 0)) > day
		):
			continue
		var parent_ids := _parent_ids(conception)
		var active_parents: Array[String] = []
		for parent_id: String in parent_ids:
			if snapshot.is_entity_active(parent_id):
				active_parents.append(parent_id)
		if active_parents.is_empty():
			result.add_fact({
				"fact_id": "fact.resident_conception_ended.%s.day%d" % [
					_safe_id(conception_fact_id), day
				],
				"fact_type": "resident_conception_ended",
				"actor_id": str(conception.get("actor_id", "")),
				"target_id": str(conception.get("target_id", "")),
				"conception_fact_id": conception_fact_id,
				"reason": "no_surviving_parent",
				"source_fact_ids": [conception_fact_id],
				"day": day,
			})
			continue
		var household_id := _birth_household(snapshot, active_parents)
		if household_id == "" or not snapshot.is_entity_active(household_id):
			continue
		var settlement_id := str(snapshot.get_entity_state(
			active_parents[0], "settlement_id",
			conception.get("settlement_id", "")
		))
		var home_id := str(snapshot.get_entity_state(
			active_parents[0], "home_location_id", ""
		))
		var newborn_id := "born_resident.%s" % _safe_id(conception_fact_id)
		if not snapshot.get_entity(newborn_id).is_empty():
			continue
		var generation_index := _newborn_generation(snapshot, parent_ids)
		var display_name := _newborn_name(
			snapshot, active_parents[0], newborn_id, config
		)
		var birth_fact_id := "fact.resident_born.%s" % _safe_id(newborn_id)
		result.add_fact({
			"fact_id": birth_fact_id,
			"fact_type": "resident_born",
			"actor_id": active_parents[0],
			"target_id": newborn_id,
			"resident_id": newborn_id,
			"parent_ids": parent_ids.duplicate(),
			"surviving_parent_ids": active_parents.duplicate(),
			"household_id": household_id,
			"settlement_id": settlement_id,
			"home_location_id": home_id,
			"conception_fact_id": conception_fact_id,
			"generation_index": generation_index,
			"source_fact_ids": [conception_fact_id],
			"day": day,
			"summary": "%s在%s出生，成为这个家庭的新一代。" % [
				display_name, _entity_name(snapshot, household_id)
			],
		})
		var culture_id := str(config.get("culture_id", "culture.unknown"))
		result.add_entity_change({
			"operation": "create",
			"entity": {
				"id": newborn_id,
				"type": "person",
				"role": "dependent",
				"display_name": display_name,
				"description": "出生于世界推进中的%s居民，是第 %d 代家庭成员。" % [
					str(config.get("culture_label", "本地")), generation_index
				],
				"tags": [
					"generated_resident",
					"born_resident",
					"living_needs",
					"occupation_dependent",
					culture_id,
					"generation_%d" % generation_index,
				],
			},
			"source_fact_ids": [birth_fact_id],
			"day": day,
		})
		_append_newborn_states(
			result, snapshot, newborn_id, parent_ids, household_id,
			settlement_id, home_id, generation_index, config, day
		)
		_append_newborn_kinship(
			result, snapshot, newborn_id, parent_ids, household_id,
			birth_fact_id, day
		)
		result.add_chronicle_entry({
			"entry_id": "chronicle.resident_birth.%s" % _safe_id(newborn_id),
			"subject_id": household_id,
			"title": "%s出生" % display_name,
			"body": "这个孩子来自运行期形成的家庭关系，亲缘、居所和代际都保存在世界事实中。",
			"source_fact_ids": [birth_fact_id],
			"day": day,
		})
		events.append({
			"event_type": "resident_born",
			"resident_id": newborn_id,
			"household_id": household_id,
			"generation_index": generation_index,
			"day": day,
		})


func _append_conceptions(
		result: Variant,
		snapshot: Variant,
		network_config: Dictionary,
		config: Dictionary,
		day: int,
		events: Array
) -> void:
	var maximum_parent_age := maxi(int(config.get(
		"maximum_parent_age", 45
	)), 18)
	var maximum_children := maxi(int(config.get(
		"maximum_children_per_pair", 3
	)), 1)
	var cooldown_days := maxi(int(config.get(
		"birth_cooldown_days", 365
	)), 1)
	var gestation_days := maxi(int(config.get("gestation_days", 280)), 1)
	var chance := clampi(int(config.get(
		"conception_chance_percent", 18
	)), 0, 100)
	var maximum_per_settlement := maxi(int(config.get(
		"maximum_conceptions_per_settlement_per_cycle", 1
	)), 1)
	var formed_by_settlement: Dictionary = {}
	var population := _population_by_settlement(snapshot)
	var partnerships := _active_partnerships(snapshot)
	partnerships.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("pair_key", "")) < str(b.get("pair_key", ""))
	)
	for partnership: Dictionary in partnerships:
		var parent_ids: Array[String] = partnership.get("partner_ids", [])
		if parent_ids.size() != 2:
			continue
		var first_id := parent_ids[0]
		var second_id := parent_ids[1]
		var first_age := int(snapshot.get_entity_state(first_id, "age_years", 0))
		var second_age := int(snapshot.get_entity_state(second_id, "age_years", 0))
		if (
			first_age < 18 or second_age < 18
			or first_age > maximum_parent_age
			or second_age > maximum_parent_age
		):
			continue
		var household_id := str(snapshot.get_entity_state(
			first_id, "household_id", ""
		))
		var settlement_id := str(snapshot.get_entity_state(
			first_id, "settlement_id", ""
		))
		if (
			household_id == ""
			or settlement_id == ""
			or household_id != str(snapshot.get_entity_state(
				second_id, "household_id", ""
			))
			or settlement_id != str(snapshot.get_entity_state(
				second_id, "settlement_id", ""
			))
		):
			continue
		if int(formed_by_settlement.get(
			settlement_id, 0
		)) >= maximum_per_settlement:
			continue
		if _pending_conception(snapshot, parent_ids):
			continue
		if _children_for_pair(snapshot, parent_ids).size() >= maximum_children:
			continue
		var last_birth_day := _last_birth_day(snapshot, parent_ids)
		if last_birth_day > 0 and day - last_birth_day < cooldown_days:
			continue
		var resident_capacity := _site_value(
			network_config, settlement_id, "resident_capacity", 0
		)
		if (
			resident_capacity > 0
			and int(population.get(settlement_id, 0)) >= resident_capacity
		):
			continue
		var dwelling_capacity := _site_value(
			network_config, settlement_id, "dwelling_capacity", 6
		)
		if _household_members(snapshot, household_id).size() >= dwelling_capacity:
			continue
		var pair_key := str(partnership.get("pair_key", ""))
		var roll := 1 + _stable_noise("%d:%d:%s:conception" % [
			int(network_config.get("generation_seed", 1)), day, pair_key
		]) % 100
		if roll > chance:
			continue
		var conception_fact_id := "fact.resident_conceived.%s.day%d" % [
			_safe_id(pair_key), day
		]
		result.add_fact({
			"fact_id": conception_fact_id,
			"fact_type": "resident_conceived",
			"actor_id": first_id,
			"target_id": second_id,
			"parent_ids": parent_ids.duplicate(),
			"household_id": household_id,
			"settlement_id": settlement_id,
			"conception_roll": roll,
			"conception_chance_percent": chance,
			"due_day": day + gestation_days,
			"source_fact_ids": (
				partnership.get("source_fact_ids", []) as Array
			).duplicate(),
			"day": day,
			"summary": "%s开始准备迎接一名新家庭成员。" % _entity_name(
				snapshot, household_id
			),
		})
		formed_by_settlement[settlement_id] = int(
			formed_by_settlement.get(settlement_id, 0)
		) + 1
		events.append({
			"event_type": "resident_conceived",
			"parent_ids": parent_ids.duplicate(),
			"household_id": household_id,
			"due_day": day + gestation_days,
			"day": day,
		})


func _append_partnerships(
		result: Variant,
		snapshot: Variant,
		network_config: Dictionary,
		config: Dictionary,
		locations: Array,
		day: int,
		events: Array
) -> void:
	var minimum_age := maxi(int(config.get("minimum_partnership_age", 18)), 18)
	var maximum_age := maxi(int(config.get("maximum_partnership_age", 60)), minimum_age)
	var maximum_gap := maxi(int(config.get("maximum_partner_age_gap", 20)), 0)
	var chance := clampi(int(config.get(
		"partnership_chance_percent", 42
	)), 0, 100)
	var maximum_per_settlement := maxi(int(config.get(
		"maximum_partnerships_per_settlement_per_cycle", 1
	)), 1)
	var partnered: Dictionary = {}
	for partnership: Dictionary in _active_partnerships(snapshot):
		for partner_id: String in partnership.get("partner_ids", []):
			partnered[partner_id] = true
	var candidates_by_settlement: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		var age := int(snapshot.get_entity_state(person_id, "age_years", 0))
		var settlement_id := str(snapshot.get_entity_state(
			person_id, "settlement_id", ""
		))
		if (
			"generated_resident" not in (person.get("tags", []) as Array)
			or partnered.has(person_id)
			or settlement_id == ""
			or age < minimum_age
			or age > maximum_age
			or _has_dependent_child(snapshot, person_id)
		):
			continue
		if not candidates_by_settlement.has(settlement_id):
			candidates_by_settlement[settlement_id] = []
		(candidates_by_settlement[settlement_id] as Array).append(person_id)
	var occupancy := _home_occupancy(snapshot)
	var reserved_homes: Dictionary = {}
	var used_people: Dictionary = {}
	var settlement_ids: Array[String] = []
	for value: Variant in candidates_by_settlement.keys():
		settlement_ids.append(str(value))
	settlement_ids.sort()
	for settlement_id: String in settlement_ids:
		var candidates: Array = candidates_by_settlement[settlement_id]
		candidates.sort()
		var pairs: Array[Dictionary] = []
		for first_index: int in range(candidates.size()):
			for second_index: int in range(first_index + 1, candidates.size()):
				var first_id := str(candidates[first_index])
				var second_id := str(candidates[second_index])
				if str(snapshot.get_entity_state(
					first_id, "household_id", ""
				)) == str(snapshot.get_entity_state(
					second_id, "household_id", ""
				)):
					continue
				if _are_close_kin(snapshot, first_id, second_id):
					continue
				var age_gap := absi(int(snapshot.get_entity_state(
					first_id, "age_years", 0
				)) - int(snapshot.get_entity_state(
					second_id, "age_years", 0
				)))
				if age_gap > maximum_gap:
					continue
				var pair_key := _pair_key(first_id, second_id)
				var roll := 1 + _stable_noise("%d:%d:%s:partnership" % [
					int(network_config.get("generation_seed", 1)), day, pair_key
				]) % 100
				if roll > chance:
					continue
				pairs.append({
					"first_id": first_id,
					"second_id": second_id,
					"pair_key": pair_key,
					"roll": roll,
					"score": _partnership_score(
						snapshot, first_id, second_id, age_gap, pair_key
					),
				})
		pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("score", 0)) != int(b.get("score", 0)):
				return int(a.get("score", 0)) > int(b.get("score", 0))
			return str(a.get("pair_key", "")) < str(b.get("pair_key", ""))
		)
		var formed_count := 0
		for pair: Dictionary in pairs:
			if formed_count >= maximum_per_settlement:
				break
			var first_id := str(pair.get("first_id", ""))
			var second_id := str(pair.get("second_id", ""))
			if used_people.has(first_id) or used_people.has(second_id):
				continue
			var placement := _partnership_placement(
				snapshot, network_config, locations, occupancy, reserved_homes,
				settlement_id, first_id, second_id, day
			)
			if placement.is_empty():
				continue
			_append_partnership_result(
				result, snapshot, config, pair, placement,
				settlement_id, day, events
			)
			used_people[first_id] = true
			used_people[second_id] = true
			formed_count += 1


func _append_partnership_result(
		result: Variant,
		snapshot: Variant,
		config: Dictionary,
		pair: Dictionary,
		placement: Dictionary,
		settlement_id: String,
		day: int,
		events: Array
) -> void:
	var first_id := str(pair.get("first_id", ""))
	var second_id := str(pair.get("second_id", ""))
	var pair_key := str(pair.get("pair_key", ""))
	var household_id := str(placement.get("household_id", ""))
	var home_id := str(placement.get("home_id", ""))
	var partnership_fact_id := "fact.resident_partnership_formed.%s.day%d" % [
		_safe_id(pair_key), day
	]
	var source_fact_ids := _partnership_source_facts(
		snapshot, first_id, second_id
	)
	result.add_fact({
		"fact_id": partnership_fact_id,
		"fact_type": "resident_partnership_formed",
		"actor_id": first_id,
		"target_id": second_id,
		"partner_ids": [first_id, second_id],
		"relationship_kind": "partner",
		"household_id": household_id,
		"settlement_id": settlement_id,
		"home_location_id": home_id,
		"partnership_roll": int(pair.get("roll", 0)),
		"partnership_score": int(pair.get("score", 0)),
		"source_fact_ids": source_fact_ids,
		"day": day,
		"summary": "%s与%s决定共同生活。" % [
			_entity_name(snapshot, first_id),
			_entity_name(snapshot, second_id),
		],
	})
	if bool(placement.get("created_household", false)):
		var household_fact_id := "fact.household_formed.%s" % _safe_id(
			household_id
		)
		var surname := _surname(_entity_name(snapshot, first_id))
		result.add_fact({
			"fact_id": household_fact_id,
			"fact_type": "household_formed",
			"actor_id": first_id,
			"target_id": household_id,
			"partner_ids": [first_id, second_id],
			"settlement_id": settlement_id,
			"home_location_id": home_id,
			"source_fact_ids": [partnership_fact_id],
			"day": day,
			"summary": "%s与%s在空置住屋中建立了新的家庭。" % [
				_entity_name(snapshot, first_id),
				_entity_name(snapshot, second_id),
			],
		})
		result.add_entity_change({
			"operation": "create",
			"entity": {
				"id": household_id,
				"type": "household",
				"display_name": "%s家" % surname,
				"description": "由运行期伴侣关系与可用住屋形成的家庭。",
				"tags": [
					"generated_household", "runtime_household",
					str(config.get("culture_id", "culture.unknown")),
				],
			},
			"source_fact_ids": [household_fact_id],
			"day": day,
		})
		for state_change: Dictionary in [
			{"key": "visible", "to": false},
			{"key": "location_id", "to": home_id},
		]:
			result.add_state_change({
				"entity_id": household_id,
				"key": str(state_change.get("key", "")),
				"to": state_change.get("to"),
			})
	var moved_from_households: Dictionary = {}
	for person_id: String in placement.get("moved_person_ids", []):
		var old_household_id := str(snapshot.get_entity_state(
			person_id, "household_id", ""
		))
		if old_household_id != "" and old_household_id != household_id:
			moved_from_households[old_household_id] = int(
				moved_from_households.get(old_household_id, 0)
			) + 1
		for change: Dictionary in [
			{"key": "household_id", "to": household_id},
			{"key": "home_location_id", "to": home_id},
			{"key": "location_id", "to": home_id},
		]:
			result.add_state_change({
				"entity_id": person_id,
				"key": str(change.get("key", "")),
				"to": change.get("to"),
			})
		if str(snapshot.get_entity_state(
			person_id, "livelihood_status", ""
		)) in ["dependent", "retired", "unemployed"]:
			result.add_state_change({
				"entity_id": person_id,
				"key": "workplace_id",
				"to": home_id,
			})
		result.add_fact({
			"fact_id": "fact.resident_household_changed.%s.day%d" % [
				_safe_id(person_id), day
			],
			"fact_type": "resident_household_changed",
			"actor_id": person_id,
			"target_id": household_id,
			"previous_household_id": old_household_id,
			"household_id": household_id,
			"settlement_id": settlement_id,
			"home_location_id": home_id,
			"reason": "partnership_formed",
			"source_fact_ids": [partnership_fact_id],
			"day": day,
		})
	for old_household_value: Variant in moved_from_households.keys():
		var old_household_id := str(old_household_value)
		if _household_members(snapshot, old_household_id).size() <= int(
			moved_from_households.get(old_household_id, 0)
		):
			_append_household_retirement(
				result,
				snapshot,
				old_household_id,
				partnership_fact_id,
				"members_formed_new_household",
				day,
				events
			)
	for change: Dictionary in [
		{"source_id": first_id, "target_id": second_id, "axis": "trust", "delta": 12},
		{"source_id": first_id, "target_id": second_id, "axis": "familiarity", "delta": 20},
		{"source_id": second_id, "target_id": first_id, "axis": "trust", "delta": 12},
		{"source_id": second_id, "target_id": first_id, "axis": "familiarity", "delta": 20},
	]:
		result.add_relationship_change(change)
	result.add_chronicle_entry({
		"entry_id": "chronicle.resident_partnership.%s.day%d" % [
			_safe_id(pair_key), day
		],
		"subject_id": household_id,
		"title": "%s与%s组成家庭" % [
			_entity_name(snapshot, first_id),
			_entity_name(snapshot, second_id),
		],
		"body": "两名居民依据年龄、亲缘边界、既有关系与住房条件开始共同生活。",
		"source_fact_ids": [partnership_fact_id],
		"day": day,
	})
	events.append({
		"event_type": "resident_partnership_formed",
		"partner_ids": [first_id, second_id],
		"household_id": household_id,
		"created_household": bool(placement.get("created_household", false)),
		"day": day,
	})


func _append_newborn_states(
		result: Variant,
		snapshot: Variant,
		newborn_id: String,
		parent_ids: Array[String],
		household_id: String,
		settlement_id: String,
		home_id: String,
		generation_index: int,
		config: Dictionary,
		day: int
) -> void:
	var temperament_ids: Array = config.get("temperament_ids", [])
	var temperament := "steady"
	if not temperament_ids.is_empty():
		temperament = str(temperament_ids[
			_stable_noise("%s:temperament" % newborn_id) % temperament_ids.size()
		])
	var states := {
		"visible": false,
		"location_id": home_id,
		"age_years": 0,
		"age_progress_days": 0,
		"generation_index": generation_index,
		"birth_day": day,
		"life_expectancy_years": 72 + _stable_noise(
			"%s:life_expectancy" % newborn_id
		) % 21,
		"life_stage": "child",
		"life_status": "alive",
		"alive": true,
		"settlement_id": settlement_id,
		"household_id": household_id,
		"home_location_id": home_id,
		"workplace_id": home_id,
		"occupation_id": "dependent",
		"livelihood_status": "dependent",
		"temperament": temperament,
		"health": 90 + _stable_noise("%s:health" % newborn_id) % 11,
		"fatigue": 0,
		"hunger": "low",
		"livelihood_elapsed_hours": 0,
		"livelihood_cycle_count": 0,
		"institution_role": "",
	}
	for attribute: String in ATTRIBUTE_KEYS:
		var total := 0
		var count := 0
		for parent_id: String in parent_ids:
			if not snapshot.get_entity(parent_id).is_empty():
				total += int(snapshot.get_entity_state(parent_id, attribute, 6))
				count += 1
		var inherited := 6 if count == 0 else int(round(float(total) / count))
		inherited += _stable_noise("%s:%s" % [newborn_id, attribute]) % 3 - 1
		if attribute in ["strength", "constitution"]:
			inherited -= 2
		states[attribute] = clampi(inherited, 2, 16)
	for state_key: String in states.keys():
		result.add_state_change({
			"entity_id": newborn_id,
			"key": state_key,
			"to": states[state_key],
		})


func _append_newborn_kinship(
		result: Variant,
		snapshot: Variant,
		newborn_id: String,
		parent_ids: Array[String],
		household_id: String,
		birth_fact_id: String,
		day: int
) -> void:
	for parent_id: String in parent_ids:
		if snapshot.get_entity(parent_id).is_empty():
			continue
		for row: Dictionary in [
			{"actor_id": parent_id, "target_id": newborn_id, "kind": "parent_of"},
			{"actor_id": newborn_id, "target_id": parent_id, "kind": "child_of"},
		]:
			result.add_fact({
				"fact_id": "fact.runtime_kinship.%s.%s.%s" % [
					_safe_id(str(row.get("kind", ""))),
					_safe_id(str(row.get("actor_id", ""))),
					_safe_id(str(row.get("target_id", ""))),
				],
				"fact_type": "runtime_kinship_formed",
				"actor_id": str(row.get("actor_id", "")),
				"target_id": str(row.get("target_id", "")),
				"household_id": household_id,
				"relationship_kind": str(row.get("kind", "")),
				"source_fact_ids": [birth_fact_id],
				"day": day,
			})
		for change: Dictionary in [
			{"source_id": parent_id, "target_id": newborn_id, "axis": "trust", "to": 55},
			{"source_id": parent_id, "target_id": newborn_id, "axis": "familiarity", "to": 70},
			{"source_id": newborn_id, "target_id": parent_id, "axis": "trust", "to": 45},
			{"source_id": newborn_id, "target_id": parent_id, "axis": "familiarity", "to": 70},
		]:
			result.add_relationship_change(change)
	var siblings := _children_for_pair(snapshot, parent_ids)
	for sibling_id: String in siblings:
		if sibling_id == newborn_id or not snapshot.is_entity_active(sibling_id):
			continue
		for pair: Array in [[newborn_id, sibling_id], [sibling_id, newborn_id]]:
			var source_id := str(pair[0])
			var target_id := str(pair[1])
			result.add_fact({
				"fact_id": "fact.runtime_kinship.sibling.%s.%s" % [
					_safe_id(source_id), _safe_id(target_id)
				],
				"fact_type": "runtime_kinship_formed",
				"actor_id": source_id,
				"target_id": target_id,
				"household_id": household_id,
				"relationship_kind": "sibling",
				"source_fact_ids": [birth_fact_id],
				"day": day,
			})
			result.add_relationship_change({
				"source_id": source_id,
				"target_id": target_id,
				"axis": "familiarity",
				"to": 60,
			})


func _active_partnerships(snapshot: Variant) -> Array[Dictionary]:
	var rows_by_pair: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("relationship_kind", "")) != "partner":
			continue
		var first_id := str(fact.get("actor_id", ""))
		var second_id := str(fact.get("target_id", ""))
		if (
			first_id == "" or second_id == ""
			or not snapshot.is_entity_active(first_id)
			or not snapshot.is_entity_active(second_id)
		):
			continue
		var pair_key := _pair_key(first_id, second_id)
		if not rows_by_pair.has(pair_key):
			rows_by_pair[pair_key] = {
				"pair_key": pair_key,
				"partner_ids": _sorted_pair(first_id, second_id),
				"source_fact_ids": [],
			}
		var row: Dictionary = rows_by_pair[pair_key]
		var fact_id := str(fact.get("fact_id", ""))
		if fact_id != "" and fact_id not in (row.get(
			"source_fact_ids", []
		) as Array):
			(row["source_fact_ids"] as Array).append(fact_id)
		rows_by_pair[pair_key] = row
	var rows: Array[Dictionary] = []
	for row_value: Variant in rows_by_pair.values():
		rows.append(row_value as Dictionary)
	return rows


func _pending_conception(snapshot: Variant, parent_ids: Array[String]) -> bool:
	var resolved: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) in [
			"resident_born", "resident_conception_ended"
		]:
			resolved[str(fact.get("conception_fact_id", ""))] = true
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "resident_conceived"
			and _same_pair(_parent_ids(fact), parent_ids)
			and not resolved.has(str(fact.get("fact_id", "")))
		):
			return true
	return false


func _children_for_pair(snapshot: Variant, parent_ids: Array[String]) -> Array[String]:
	var children: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("relationship_kind", "")) == "parent_of"
			and str(fact.get("actor_id", "")) in parent_ids
		):
			children[str(fact.get("target_id", ""))] = true
	var rows: Array[String] = []
	for child_value: Variant in children.keys():
		var child_id := str(child_value)
		if child_id != "":
			rows.append(child_id)
	rows.sort()
	return rows


func _last_birth_day(snapshot: Variant, parent_ids: Array[String]) -> int:
	var latest := 0
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "resident_born"
			and _same_pair(_parent_ids(fact), parent_ids)
		):
			latest = maxi(latest, int(fact.get("day", 0)))
	return latest


func _has_dependent_child(snapshot: Variant, parent_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("relationship_kind", "")) == "parent_of"
			and str(fact.get("actor_id", "")) == parent_id
			and snapshot.is_entity_active(str(fact.get("target_id", "")))
			and int(snapshot.get_entity_state(
				str(fact.get("target_id", "")), "age_years", 0
			)) < 18
		):
			return true
	return false


func _are_close_kin(snapshot: Variant, first_id: String, second_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("relationship_kind", "")) not in [
			"parent_of", "child_of", "sibling"
		]:
			continue
		var actor_id := str(fact.get("actor_id", ""))
		var target_id := str(fact.get("target_id", ""))
		if (
			(actor_id == first_id and target_id == second_id)
			or (actor_id == second_id and target_id == first_id)
		):
			return true
	return false


func _partnership_score(
		snapshot: Variant,
		first_id: String,
		second_id: String,
		age_gap: int,
		pair_key: String
) -> int:
	return (
		int(snapshot.get_relation(first_id, second_id, "familiarity", 0))
		+ int(snapshot.get_relation(second_id, first_id, "familiarity", 0))
		+ int(snapshot.get_relation(first_id, second_id, "trust", 0))
		+ int(snapshot.get_relation(second_id, first_id, "trust", 0))
		+ maxi(20 - age_gap, 0)
		+ _stable_noise("%s:compatibility" % pair_key) % 21
	)


func _partnership_placement(
		snapshot: Variant,
		network_config: Dictionary,
		locations: Array,
		occupancy: Dictionary,
		reserved_homes: Dictionary,
		settlement_id: String,
		first_id: String,
		second_id: String,
		day: int
) -> Dictionary:
	var homes: Array[String] = []
	for location_value: Variant in locations:
		if not location_value is Dictionary:
			continue
		var location: Dictionary = location_value
		var home_id := str(location.get("id", ""))
		if (
			str(location.get("settlement_id", "")) == settlement_id
			and "settlement_dwelling" in (location.get("tags", []) as Array)
			and int(occupancy.get(home_id, 0)) == 0
			and not reserved_homes.has(home_id)
		):
			homes.append(home_id)
	homes.sort()
	if not homes.is_empty():
		var home_id := homes[0]
		reserved_homes[home_id] = true
		return {
			"household_id": "runtime_household.%s.day%d.%s" % [
				_safe_id(settlement_id),
				day,
				_safe_id(_pair_key(first_id, second_id)),
			],
			"home_id": home_id,
			"moved_person_ids": [first_id, second_id],
			"created_household": true,
		}
	var dwelling_capacity := _site_value(
		network_config, settlement_id, "dwelling_capacity", 6
	)
	var options: Array[Dictionary] = []
	for row: Dictionary in [
		{"host": first_id, "mover": second_id},
		{"host": second_id, "mover": first_id},
	]:
		var host_id := str(row.get("host", ""))
		var household_id := str(snapshot.get_entity_state(
			host_id, "household_id", ""
		))
		var members := _household_members(snapshot, household_id)
		if household_id != "" and members.size() < dwelling_capacity:
			options.append({
				"household_id": household_id,
				"home_id": str(snapshot.get_entity_state(
					host_id, "home_location_id", ""
				)),
				"moved_person_ids": [str(row.get("mover", ""))],
				"created_household": false,
				"member_count": members.size(),
			})
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("member_count", 0)) != int(b.get("member_count", 0)):
			return int(a.get("member_count", 0)) < int(b.get("member_count", 0))
		return str(a.get("household_id", "")) < str(b.get("household_id", ""))
	)
	return {} if options.is_empty() else options[0]


func _append_household_retirement(
		result: Variant,
		snapshot: Variant,
		household_id: String,
		source_fact_id: String,
		reason: String,
		day: int,
		events: Array
) -> void:
	if household_id == "" or source_fact_id == "":
		return
	var retirement_fact_id := "fact.household_extinguished.%s.day%d" % [
		_safe_id(household_id), day
	]
	result.add_fact({
		"fact_id": retirement_fact_id,
		"fact_type": "household_extinguished",
		"actor_id": household_id,
		"target_id": household_id,
		"household_id": household_id,
		"reason": reason,
		"source_fact_ids": [source_fact_id],
		"day": day,
		"summary": "%s已经没有继续生活在其中的成员。" % _entity_name(
			snapshot, household_id
		),
	})
	result.add_entity_change({
		"operation": "retire",
		"entity_id": household_id,
		"retired_fact_id": retirement_fact_id,
		"reason": "household_extinguished",
		"source_fact_ids": [retirement_fact_id],
		"day": day,
	})
	result.add_chronicle_entry({
		"entry_id": "chronicle.household_extinguished.%s.day%d" % [
			_safe_id(household_id), day
		],
		"subject_id": household_id,
		"title": "%s不再作为当前家庭存在" % _entity_name(
			snapshot, household_id
		),
		"body": "家庭实体退出当前人口结构，但成员、住屋与过往事实仍可追溯。",
		"source_fact_ids": [retirement_fact_id],
		"day": day,
	})
	events.append({
		"event_type": "household_extinguished",
		"household_id": household_id,
		"day": day,
	})


func _inheritance_heir(
		snapshot: Variant, dead_id: String, household_id: String
) -> String:
	for partnership: Dictionary in _active_partnerships_for_history(snapshot):
		var partner_ids: Array[String] = partnership.get("partner_ids", [])
		if dead_id not in partner_ids:
			continue
		for partner_id: String in partner_ids:
			if partner_id != dead_id and snapshot.is_entity_active(partner_id):
				return partner_id
	var candidates := _household_members(snapshot, household_id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var age_a := int(snapshot.get_entity_state(a, "age_years", 0))
		var age_b := int(snapshot.get_entity_state(b, "age_years", 0))
		return age_a > age_b if age_a != age_b else a < b
	)
	return "" if candidates.is_empty() else candidates[0]


func _active_partnerships_for_history(snapshot: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("relationship_kind", "")) != "partner":
			continue
		var first_id := str(fact.get("actor_id", ""))
		var second_id := str(fact.get("target_id", ""))
		var pair_key := _pair_key(first_id, second_id)
		if first_id == "" or second_id == "" or seen.has(pair_key):
			continue
		seen[pair_key] = true
		rows.append({
			"pair_key": pair_key,
			"partner_ids": _sorted_pair(first_id, second_id),
		})
	return rows


func _birth_household(snapshot: Variant, active_parents: Array[String]) -> String:
	var first_household := str(snapshot.get_entity_state(
		active_parents[0], "household_id", ""
	))
	if active_parents.size() == 1:
		return first_household
	var second_household := str(snapshot.get_entity_state(
		active_parents[1], "household_id", ""
	))
	return first_household if first_household == second_household else first_household


func _newborn_generation(snapshot: Variant, parent_ids: Array[String]) -> int:
	var generation := 0
	for parent_id: String in parent_ids:
		generation = maxi(generation, int(snapshot.get_entity_state(
			parent_id, "generation_index", 0
		)))
	return generation + 1


func _newborn_name(
		snapshot: Variant,
		primary_parent_id: String,
		newborn_id: String,
		config: Dictionary
) -> String:
	var surname := _surname(_entity_name(snapshot, primary_parent_id))
	var given_names: Array = config.get("given_names", [])
	if given_names.is_empty():
		return "%s家新生儿%d" % [surname, _stable_noise(newborn_id) % 1000]
	var used_names: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		used_names[str(person.get("display_name", ""))] = true
	var start := _stable_noise("%s:name" % newborn_id) % given_names.size()
	for offset: int in range(given_names.size()):
		var candidate := "%s%s" % [
			surname, str(given_names[(start + offset) % given_names.size()])
		]
		if not used_names.has(candidate):
			return candidate
	return "%s%s%d" % [
		surname, str(given_names[start]), _stable_noise(newborn_id) % 1000
	]


func _partnership_source_facts(
		snapshot: Variant, first_id: String, second_id: String
) -> Array[String]:
	var rows: Array[String] = []
	for fact: Dictionary in snapshot.get_facts():
		var actor_id := str(fact.get("actor_id", ""))
		var target_id := str(fact.get("target_id", ""))
		if (
			(actor_id == first_id and target_id == second_id)
			or (actor_id == second_id and target_id == first_id)
			or (
				str(fact.get("fact_type", "")) in [
					"resident_generated", "resident_born"
				]
				and target_id in [first_id, second_id]
			)
		):
			var fact_id := str(fact.get("fact_id", ""))
			if fact_id != "" and fact_id not in rows:
				rows.append(fact_id)
		if rows.size() >= 4:
			break
	return rows


func _population_by_settlement(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var settlement_id := str(snapshot.get_entity_state(
			str(person.get("id", "")), "settlement_id", ""
		))
		if settlement_id != "":
			rows[settlement_id] = int(rows.get(settlement_id, 0)) + 1
	return rows


func _home_occupancy(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var home_id := str(snapshot.get_entity_state(
			str(person.get("id", "")), "home_location_id", ""
		))
		if home_id != "":
			rows[home_id] = int(rows.get(home_id, 0)) + 1
	return rows


func _household_members(snapshot: Variant, household_id: String) -> Array[String]:
	var rows: Array[String] = []
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if str(snapshot.get_entity_state(
			person_id, "household_id", ""
		)) == household_id:
			rows.append(person_id)
	rows.sort()
	return rows


func _site_value(
		network_config: Dictionary,
		settlement_id: String,
		key: String,
		default_value: int
) -> int:
	for site_value: Variant in network_config.get("sites", []):
		if (
			site_value is Dictionary
			and str((site_value as Dictionary).get("settlement_id", ""))
			== settlement_id
		):
			return int((site_value as Dictionary).get(key, default_value))
	return default_value


func _facts_on_day(
		snapshot: Variant, fact_type: String, day: int
) -> Array:
	var rows: Array = []
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == fact_type
			and int(fact.get("day", 0)) == day
		):
			rows.append(fact)
	return rows


func _fact_references(
		snapshot: Variant,
		fact_type: String,
		key: String,
		value: String
) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == fact_type
			and str(fact.get(key, "")) == value
		):
			return true
	return false


func _parent_ids(fact: Dictionary) -> Array[String]:
	var rows: Array[String] = []
	for value: Variant in fact.get("parent_ids", []):
		var parent_id := str(value)
		if parent_id != "" and parent_id not in rows:
			rows.append(parent_id)
	if rows.is_empty():
		for key: String in ["actor_id", "target_id"]:
			var parent_id := str(fact.get(key, ""))
			if parent_id != "" and parent_id not in rows:
				rows.append(parent_id)
	rows.sort()
	return rows


func _same_pair(first: Array[String], second: Array[String]) -> bool:
	return first.size() == 2 and second.size() == 2 and _pair_key(
		first[0], first[1]
	) == _pair_key(second[0], second[1])


func _pair_key(first_id: String, second_id: String) -> String:
	var pair := _sorted_pair(first_id, second_id)
	return "%s::%s" % [pair[0], pair[1]]


func _sorted_pair(first_id: String, second_id: String) -> Array[String]:
	var rows: Array[String] = [first_id, second_id]
	rows.sort()
	return rows


func _surname(display_name: String) -> String:
	return display_name.left(1) if display_name != "" else "新"


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	var entity: Dictionary = snapshot.get_entity(entity_id)
	return str(entity.get("display_name", entity_id))


func _stable_noise(key: String) -> int:
	return int(("0x" + key.sha256_text().substr(0, 8)).hex_to_int() % 1000000)


func _safe_id(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace(":", "_").replace(
		"/", "_"
	)
