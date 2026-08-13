extends RefCounted
class_name V5NpcLivelihoodSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)

const HUNGRY_LEVELS := ["high", "extreme"]
const MAX_FATIGUE := 10


func resolve_work_tick(
		snapshot: Variant,
		profiles: Array,
		tick_event: Dictionary
) -> Dictionary:
	if int(tick_event.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var profile_by_occupation := _profiles_by_occupation(profiles)
	if profile_by_occupation.is_empty():
		return {"results": [], "events": []}

	var result = TransactionResultModel.new()
	var events: Array = []
	var produced_count := 0
	for actor: Dictionary in _sorted_people(snapshot):
		var actor_id := str(actor.get("id", ""))
		var occupation_id := str(snapshot.get_entity_state(
			actor_id, "occupation_id", ""
		))
		if not profile_by_occupation.has(occupation_id):
			continue
		var profile: Dictionary = profile_by_occupation[occupation_id]
		if not _actor_matches_profile(actor, profile):
			continue
		var interval := maxi(int(profile.get("work_interval_hours", 8)), 1)
		var elapsed := int(snapshot.get_entity_state(
			actor_id, "livelihood_elapsed_hours", 0
		)) + 1
		if elapsed < interval:
			result.add_state_change({
				"entity_id": actor_id,
				"key": "livelihood_elapsed_hours",
				"to": elapsed,
			})
			continue

		var cycle_count := int(snapshot.get_entity_state(
			actor_id, "livelihood_cycle_count", 0
		)) + 1
		var fact_id := "fact.npc_livelihood.%s.%s" % [
			_safe_id(actor_id),
			_safe_id(str(tick_event.get("tick_event_id", "tick"))),
		]
		var products: Array = profile.get("products", [])
		var product_rows: Array = []
		for product_index: int in range(products.size()):
			var product: Dictionary = products[product_index]
			var item_def_id := str(product.get("item_def_id", ""))
			var quantity := maxi(int(product.get("quantity", 1)), 1)
			if item_def_id == "":
				continue
			product_rows.append({
				"item_def_id": item_def_id,
				"quantity": quantity,
			})
			_append_product_changes(
				result,
				snapshot,
				actor_id,
				item_def_id,
				quantity,
				fact_id,
				tick_event,
				product_index
			)

		result.add_fact({
			"fact_id": fact_id,
			"fact_type": "npc_livelihood_produced",
			"actor_id": actor_id,
			"location_id": str(snapshot.get_entity_state(
				actor_id, "workplace_id", ""
			)),
			"occupation_id": occupation_id,
			"livelihood_cycle_count": cycle_count,
			"products": product_rows,
			"day": int(tick_event.get("day", 0)),
			"tick_event_id": str(tick_event.get("tick_event_id", "")),
			"summary": str(profile.get(
				"work_summary",
				"%s完成了一轮日常生计。" % str(actor.get(
					"display_name", actor_id
				))
			)),
		})
		result.add_state_change({
			"entity_id": actor_id,
			"key": "livelihood_elapsed_hours",
			"to": elapsed - interval,
		})
		result.add_state_change({
			"entity_id": actor_id,
			"key": "livelihood_cycle_count",
			"to": cycle_count,
		})
		var fatigue := int(snapshot.get_entity_state(actor_id, "fatigue", 0))
		if fatigue < MAX_FATIGUE:
			result.add_state_change({
				"entity_id": actor_id,
				"key": "fatigue",
				"to": fatigue + 1,
			})
		events.append({
			"event_type": "livelihood_produced",
			"actor_id": actor_id,
			"occupation_id": occupation_id,
			"products": product_rows.duplicate(true),
			"fact_id": fact_id,
		})
		produced_count += 1

	if result.is_empty():
		return {"results": [], "events": events}
	if produced_count > 0:
		result.set_narrative_result({
			"title": "聚落生计继续运转",
			"summary": "%d 名居民完成了各自的一轮工作，产物已经进入真实物品库存。" % produced_count,
			"tone": "ordinary_life",
		})
	result.mark_resolved("npc_livelihood_work")
	return {"results": [result], "events": events}


func resolve_household_support(
		snapshot: Variant,
		tick_event: Dictionary
) -> Dictionary:
	if int(tick_event.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var households := _households(snapshot)
	var available_quantity := _available_item_quantities(snapshot)
	var result = TransactionResultModel.new()
	var events: Array = []
	var shared_count := 0
	var meal_count := 0

	for recipient: Dictionary in _sorted_people(snapshot):
		var recipient_id := str(recipient.get("id", ""))
		var hunger := str(snapshot.get_entity_state(
			recipient_id, "hunger", "none"
		))
		if hunger not in HUNGRY_LEVELS:
			continue
		var household_id := str(snapshot.get_entity_state(
			recipient_id, "household_id", ""
		))
		if household_id == "" or not households.has(household_id):
			continue
		var food := _find_food(
			snapshot,
			recipient_id,
			households[household_id],
			available_quantity
		)
		if food.is_empty():
			var unmet_fact_id := "fact.npc_household_food_unmet.%s.day_%d" % [
				_safe_id(recipient_id),
				int(tick_event.get("day", 0)),
			]
			if not _snapshot_has_fact(snapshot, unmet_fact_id):
				result.add_fact({
					"fact_id": unmet_fact_id,
					"fact_type": "npc_household_food_unmet",
					"actor_id": recipient_id,
					"household_id": household_id,
					"hunger": hunger,
					"tick_event_id": str(tick_event.get("tick_event_id", "")),
					"summary": "%s的同住家庭暂时拿不出一份食物。" % str(
						recipient.get("display_name", recipient_id)
					),
				})
				events.append({
					"event_type": "household_food_unmet",
					"actor_id": recipient_id,
					"household_id": household_id,
					"fact_id": unmet_fact_id,
				})
			continue

		var item_id := str(food.get("item_instance_id", ""))
		var donor_id := str(food.get("holder_id", recipient_id))
		available_quantity[item_id] = int(available_quantity.get(item_id, 0)) - 1
		var fact_id := "fact.npc_household_meal.%s.%s" % [
			_safe_id(recipient_id),
			_safe_id(str(tick_event.get("tick_event_id", "tick"))),
		]
		var shared := donor_id != recipient_id
		result.add_fact({
			"fact_id": fact_id,
			"fact_type": (
				"npc_household_shared_food" if shared else "npc_self_meal"
			),
			"actor_id": donor_id,
			"target_id": recipient_id,
			"household_id": household_id,
			"item_instance_id": item_id,
			"item_def_id": str(food.get("item_def_id", "")),
			"hunger_before": hunger,
			"tick_event_id": str(tick_event.get("tick_event_id", "")),
			"summary": (
				"同住者拿出一份食物，先让%s吃下。" % str(
					recipient.get("display_name", recipient_id)
				)
				if shared
				else "%s吃下了一份自己留存的食物。" % str(
					recipient.get("display_name", recipient_id)
				)
			),
		})
		result.add_state_change({
			"entity_id": recipient_id,
			"key": "hunger",
			"degrade": 2,
		})
		result.add_item_change({
			"operation": "consume",
			"item_instance_id": item_id,
			"quantity": 1,
			"source_fact_ids": [fact_id],
			"beneficiary_id": recipient_id,
			"provider_id": donor_id,
		})
		if shared:
			result.add_relationship_change({
				"source_id": recipient_id,
				"target_id": donor_id,
				"axis": "gratitude",
				"delta": 3,
			})
			result.add_relationship_change({
				"source_id": recipient_id,
				"target_id": donor_id,
				"axis": "trust",
				"delta": 1,
			})
			result.add_relationship_change({
				"source_id": donor_id,
				"target_id": recipient_id,
				"axis": "familiarity",
				"delta": 1,
			})
			shared_count += 1
		events.append({
			"event_type": "household_shared_food" if shared else "self_meal",
			"actor_id": donor_id,
			"target_id": recipient_id,
			"household_id": household_id,
			"item_instance_id": item_id,
			"fact_id": fact_id,
		})
		meal_count += 1

	if result.is_empty():
		return {"results": [], "events": events}
	if meal_count > 0:
		result.set_narrative_result({
			"title": "家中的食物被重新分配",
			"summary": "%d 人吃到了食物，其中 %d 份来自同住者。" % [
				meal_count, shared_count
			],
			"tone": "ordinary_life",
		})
	result.mark_resolved("npc_household_support")
	return {"results": [result], "events": events}


func _append_product_changes(
		result: Variant,
		snapshot: Variant,
		actor_id: String,
		item_def_id: String,
		quantity: int,
		fact_id: String,
		tick_event: Dictionary,
		product_index: int
) -> void:
	var remaining := quantity
	var existing := _partial_stack(snapshot, actor_id, item_def_id)
	if not existing.is_empty():
		var capacity := int(existing.get("max_stack", 1)) - int(
			existing.get("quantity", 0)
		)
		var added := mini(remaining, maxi(capacity, 0))
		if added > 0:
			result.add_item_change({
				"operation": "increase_quantity",
				"item_instance_id": str(existing.get("item_instance_id", "")),
				"quantity": added,
				"source_fact_ids": [fact_id],
			})
			remaining -= added
	if remaining <= 0:
		return
	var item_instance_id := "item_instance.livelihood.%s.%s.%02d" % [
		_safe_id(actor_id),
		_safe_id(str(tick_event.get("tick_event_id", "tick"))),
		product_index,
	]
	result.add_item_change({
		"operation": "create",
		"source_fact_ids": [fact_id],
		"item": {
			"item_instance_id": item_instance_id,
			"item_def_id": item_def_id,
			"holder": {"kind": "entity", "id": actor_id},
			"quantity": remaining,
			"condition": {},
			"custom_tags": ["livelihood_product"],
			"provenance": {
				"producer_id": actor_id,
				"occupation_id": str(snapshot.get_entity_state(
					actor_id, "occupation_id", ""
				)),
			},
			"history": [],
			"created_tick": _tick_value(tick_event),
			"updated_tick": _tick_value(tick_event),
		},
	})


func _profiles_by_occupation(profiles: Array) -> Dictionary:
	var rows: Dictionary = {}
	for profile: Dictionary in profiles:
		var occupation_id := str(profile.get("occupation_id", ""))
		if occupation_id != "":
			rows[occupation_id] = profile.duplicate(true)
	return rows


func _actor_matches_profile(actor: Dictionary, profile: Dictionary) -> bool:
	var tags: Array = actor.get("tags", [])
	for tag: Variant in profile.get("actor_tags_all", []):
		if tag not in tags:
			return false
	return true


func _sorted_people(snapshot: Variant) -> Array:
	var rows: Array = snapshot.get_entities_by_type("person")
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return rows


func _households(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for person: Dictionary in _sorted_people(snapshot):
		var person_id := str(person.get("id", ""))
		var household_id := str(snapshot.get_entity_state(
			person_id, "household_id", ""
		))
		if household_id == "":
			continue
		if not rows.has(household_id):
			rows[household_id] = []
		(rows[household_id] as Array).append(person_id)
	return rows


func _available_item_quantities(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for item: Dictionary in snapshot.get_items():
		rows[str(item.get("item_instance_id", ""))] = int(item.get(
			"quantity", 0
		))
	return rows


func _find_food(
		snapshot: Variant,
		recipient_id: String,
		household_members: Array,
		available_quantity: Dictionary
) -> Dictionary:
	var ordered_members: Array = household_members.duplicate()
	ordered_members.sort_custom(func(a: Variant, b: Variant) -> bool:
		var a_id := str(a)
		var b_id := str(b)
		if a_id == recipient_id:
			return true
		if b_id == recipient_id:
			return false
		var a_support := int(snapshot.get_relation(
			recipient_id, a_id, "trust", 0
		)) + int(snapshot.get_relation(recipient_id, a_id, "familiarity", 0))
		var b_support := int(snapshot.get_relation(
			recipient_id, b_id, "trust", 0
		)) + int(snapshot.get_relation(recipient_id, b_id, "familiarity", 0))
		return a_support > b_support if a_support != b_support else a_id < b_id
	)
	for holder_id: Variant in ordered_members:
		for item: Dictionary in snapshot.get_items():
			var item_id := str(item.get("item_instance_id", ""))
			var holder: Dictionary = item.get("holder", {})
			if (
				str(holder.get("kind", "")) == "entity"
				and str(holder.get("id", "")) == str(holder_id)
				and "food" in (item.get("tags", []) as Array)
				and "consume" in (item.get("capabilities", []) as Array)
				and int(available_quantity.get(item_id, 0)) > 0
			):
				var row := item.duplicate(true)
				row["holder_id"] = str(holder_id)
				return row
	return {}


func _partial_stack(
		snapshot: Variant,
		actor_id: String,
		item_def_id: String
) -> Dictionary:
	for item: Dictionary in snapshot.get_items():
		var holder: Dictionary = item.get("holder", {})
		if (
			str(holder.get("kind", "")) == "entity"
			and str(holder.get("id", "")) == actor_id
			and str(item.get("item_def_id", "")) == item_def_id
			and int(item.get("quantity", 0)) < int(item.get("max_stack", 1))
		):
			return item.duplicate(true)
	return {}


func _snapshot_has_fact(snapshot: Variant, fact_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _tick_value(tick_event: Dictionary) -> int:
	return int(tick_event.get("day", 0)) * 24 + int(
		tick_event.get("hour", 0)
	)


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")
