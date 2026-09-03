extends RefCounted
class_name V5NpcLivelihoodSystem

const IndustryCatalog = preload("res://scripts/sim/settlement/industry_runtime_catalog.gd")
const Access = preload("res://scripts/sim/resource/resource_access.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")

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
	var profiles_by_scope := _profiles_by_scope(IndustryCatalog.profiles(snapshot, profiles))
	if profiles_by_scope.is_empty():
		return {"results": [], "events": []}

	var result = TransactionResultModel.new()
	var events: Array = []
	var produced_count := 0
	var blocked_count := 0
	var available_resources := _available_resource_amounts(snapshot)
	var treasury = Treasury.new(snapshot)
	for actor: Dictionary in _sorted_people(snapshot):
		var actor_id := str(actor.get("id", ""))
		var occupation_id := str(snapshot.get_entity_state(
			actor_id, "occupation_id", ""
		))
		var settlement_id := str(snapshot.get_entity_state(
			actor_id, "settlement_id", ""
		))
		var profile_key := _profile_key(settlement_id, occupation_id)
		var fallback_key := _profile_key("", occupation_id)
		if not profiles_by_scope.has(profile_key) and not profiles_by_scope.has(
			fallback_key
		):
			continue
		var profile: Dictionary = profiles_by_scope.get(
			profile_key, profiles_by_scope.get(fallback_key, {})
		)
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

		var fact_id := "fact.npc_livelihood.%s.%s" % [
			_safe_id(actor_id),
			_safe_id(str(tick_event.get("tick_event_id", "tick"))),
		]
		var wage := int(profile.get("wage_amount", 0))
		var reserve := int(snapshot.get_entity_state(settlement_id, "treasury_reserve", 0))
		var wage_missing := wage > 0 and treasury.balance(settlement_id) - reserve < wage
		var resource_plan := {"ok": false, "missing": {"label": "可支付薪酬", "amount": wage,
			"available": maxi(treasury.balance(settlement_id) - reserve, 0), "denial": "treasury_insufficient"}} if wage_missing else _resource_plan(profile, available_resources, snapshot, actor_id)
		if not bool(resource_plan.get("ok", false)):
			var blocked_resource: Dictionary = resource_plan.get("missing", {})
			var blocked_count_for_actor := int(snapshot.get_entity_state(
				actor_id, "livelihood_blocked_count", 0
			)) + 1
			result.add_fact({
				"fact_id": fact_id,
				"fact_type": "npc_wage_work_declined" if wage_missing else "npc_livelihood_blocked_resource",
				"actor_id": actor_id,
				"settlement_id": settlement_id,
				"location_id": str(snapshot.get_entity_state(
					actor_id, "workplace_id", ""
				)),
				"occupation_id": occupation_id,
				"stock_id": str(blocked_resource.get("stock_id", "")),
				"resource_label": str(blocked_resource.get(
					"label", "生产资源"
				)),
				"required": float(blocked_resource.get("amount", 0.0)),
				"available": float(blocked_resource.get("available", 0.0)),
				"blocked_reason": str(blocked_resource.get("denial", "resource_shortage")),
				"day": int(tick_event.get("day", 0)),
				"tick_event_id": str(tick_event.get("tick_event_id", "")),
				"summary": "%s未开工：%s。没有扣取生产投入或发放物品。" % [
					str(actor.get("display_name", actor_id)),
					"聚落可支付的薪酬不足" if wage_missing else ("没有该资源的生产使用权" if str(blocked_resource.get("denial", "")) != "" else str(blocked_resource.get("label", "生产资源")) + "不足"),
				],
			})
			result.add_state_change({
				"entity_id": actor_id,
				"key": "livelihood_elapsed_hours",
				"to": elapsed - interval,
			})
			result.add_state_change({
				"entity_id": actor_id,
				"key": "livelihood_blocked_count",
				"to": blocked_count_for_actor,
			})
			events.append({
				"event_type": "livelihood_blocked_resource",
				"actor_id": actor_id,
				"occupation_id": occupation_id,
				"stock_id": str(blocked_resource.get("stock_id", "")),
				"resource_label": str(blocked_resource.get(
					"label", "生产资源"
				)),
				"fact_id": fact_id,
			})
			blocked_count += 1
			continue

		var cycle_count := int(snapshot.get_entity_state(
			actor_id, "livelihood_cycle_count", 0
		)) + 1
		var resource_inputs: Array = resource_plan.get("changes", [])
		for input: Dictionary in resource_inputs:
			var resource_change := input.duplicate(true)
			resource_change["operation"] = "consume"
			resource_change["source_fact_ids"] = [fact_id]
			resource_change["tick"] = _tick_value(tick_event)
			resource_change["reason"] = "livelihood_production"
			resource_change["actor_id"] = actor_id
			resource_change["day"] = int(tick_event.get("day", 0))
			result.add_resource_change(resource_change)
		if wage > 0:
			treasury.append_payment(result, settlement_id, actor_id, wage, fact_id, _tick_value(tick_event), reserve)
			result.add_fact({"fact_id": fact_id + ".wage", "fact_type": "npc_wage_paid", "actor_id": settlement_id,
				"target_id": actor_id, "settlement_id": settlement_id, "amount": wage, "source_fact_ids": [fact_id], "day": int(tick_event.get("day", 0)),
				"summary": "%s从聚落金库实际领取 %d 枚铜币。" % [actor.get("display_name", actor_id), wage]})
			result.add_exchange({"exchange_id": "exchange." + fact_id, "exchange_type": "service_wage_payment",
				"status": "settled", "party_a": settlement_id, "party_b": actor_id,
				"terms": {"amount": wage, "currency_item_def_id": Treasury.CURRENCY}, "source_fact_ids": [fact_id],
				"created_tick": _tick_value(tick_event), "settled_tick": _tick_value(tick_event)})
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
			"resource_inputs": resource_inputs.duplicate(true),
			"day": int(tick_event.get("day", 0)),
			"tick_event_id": str(tick_event.get("tick_event_id", "")),
			"summary": ("%s完成一轮%s，聚落实际支付 %d 枚铜币。" % [actor.get("display_name", actor_id), profile.get("label", "服务"), wage]) if wage > 0 else str(profile.get(
				"work_summary",
				"%s完成了一轮日常生计。" % str(actor.get(
					"display_name", actor_id
				))
			)) + ("（旧版薪酬模型：铜币由规则生成，尚未实际付款。）" if _contains_currency_product(products) else ""),
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
			"summary": (
					"%d 名居民完成了工作，实际产物或薪酬进入库存；另有 %d 人因资源、权限或薪酬条件未满足而停工。" % [
					produced_count, blocked_count
				]
				if blocked_count > 0
				else "%d 名居民完成了工作，实际产物或薪酬已进入物品库存。" % produced_count
			),
			"tone": "ordinary_life",
		})
	elif blocked_count > 0:
		result.set_narrative_result({
			"title": "开工条件尚未满足",
			"summary": "%d 名居民因资源、使用权限或可支付薪酬不足而未开工；具体原因已留下记录，没有扣取生产投入。" % blocked_count,
			"tone": "work_blocked",
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
	var external_links := _external_support_links(snapshot)
	var available_quantity := _available_item_quantities(snapshot)
	var result = TransactionResultModel.new()
	var events: Array = []
	var shared_count := 0
	var external_shared_count := 0
	var failed_request_count := 0
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
			food = _find_external_food(
				snapshot,
				recipient_id,
				household_id,
				households[household_id],
				external_links,
				available_quantity
			)
		if food.is_empty():
			var contact := _best_external_contact(
				snapshot,
				household_id,
				households[household_id],
				external_links
			)
			if not contact.is_empty() and _append_failed_food_request(
				result,
				snapshot,
				recipient,
				recipient_id,
				household_id,
				hunger,
				contact,
				tick_event,
				events
			):
				failed_request_count += 1
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
					"day": int(tick_event.get("day", 0)),
					"hour": int(tick_event.get("hour", 0)),
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
		var external := bool(food.get("external_support", false))
		var requester_id := str(food.get("requester_id", recipient_id))
		available_quantity[item_id] = int(available_quantity.get(item_id, 0)) - 1
		var fact_id := "fact.npc_household_meal.%s.%s" % [
			_safe_id(recipient_id),
			_safe_id(str(tick_event.get("tick_event_id", "tick"))),
		]
		var shared := donor_id != recipient_id
		result.add_fact({
			"fact_id": fact_id,
			"fact_type": "npc_cross_household_shared_food" if external else (
				"npc_household_shared_food" if shared else "npc_self_meal"
			),
			"actor_id": donor_id,
			"target_id": recipient_id,
			"requester_id": requester_id,
			"household_id": household_id,
			"provider_household_id": str(food.get(
				"provider_household_id", household_id
			)),
			"relationship_kind": str(food.get("relationship_kind", "")),
			"relationship_fact_id": str(food.get("relationship_fact_id", "")),
			"source_fact_ids": (
				[str(food.get("relationship_fact_id", ""))] if external else []
			),
			"item_instance_id": item_id,
			"item_def_id": str(food.get("item_def_id", "")),
			"hunger_before": hunger,
			"day": int(tick_event.get("day", 0)),
			"hour": int(tick_event.get("hour", 0)),
			"tick_event_id": str(tick_event.get("tick_event_id", "")),
			"summary": (
				"%s沿着%s关系向邻近家庭求助，%s拿出一份食物给%s。" % [
					_entity_name(snapshot, requester_id),
					_relationship_label(str(food.get("relationship_kind", ""))),
					_entity_name(snapshot, donor_id),
					str(recipient.get("display_name", recipient_id)),
				]
				if external
				else
				"同住者拿出一份食物，先让%s吃下。" % str(
					recipient.get("display_name", recipient_id)
				)
				if shared
				else "%s吃下了一份自己留存的食物。" % str(
					recipient.get("display_name", recipient_id)
				)
			),
		})
		if external:
			result.add_trace({
				"trace_id": "trace.npc_cross_household_food.%s.%s" % [
					_safe_id(recipient_id),
					_safe_id(str(tick_event.get("tick_event_id", "tick"))),
				],
				"trace_type": "shared_food_container",
				"actor_id": donor_id,
				"target_id": recipient_id,
				"location_id": str(snapshot.get_entity_state(
					recipient_id, "home_location_id", ""
				)),
				"source_fact_id": fact_id,
				"source_fact_ids": [fact_id],
				"source_fact_type": "npc_cross_household_shared_food",
				"display_name": "邻家食物留下的盛装物",
				"description": "装过一份外借食物的包布或浅篮，归还前留在受助家庭里。",
				"visible": false,
				"inspectable": true,
				"freshness": "fresh",
				"tags": ["food_help", "neighbor_debt", "generated_trace"],
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
		if external:
			result.add_relationship_change({
				"source_id": requester_id,
				"target_id": donor_id,
				"axis": "gratitude",
				"delta": 4,
			})
			result.add_relationship_change({
				"source_id": requester_id,
				"target_id": donor_id,
				"axis": "trust",
				"delta": 1,
			})
			result.add_relationship_change({
				"source_id": requester_id,
				"target_id": donor_id,
				"axis": "debt",
				"delta": 2,
			})
			result.add_relationship_change({
				"source_id": donor_id,
				"target_id": requester_id,
				"axis": "familiarity",
				"delta": 1,
			})
			if recipient_id != requester_id:
				result.add_relationship_change({
					"source_id": recipient_id,
					"target_id": donor_id,
					"axis": "gratitude",
					"delta": 2,
				})
			external_shared_count += 1
		elif shared:
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
			"event_type": "cross_household_shared_food" if external else (
				"household_shared_food" if shared else "self_meal"
			),
			"actor_id": donor_id,
			"target_id": recipient_id,
			"household_id": household_id,
			"provider_household_id": str(food.get(
				"provider_household_id", household_id
			)),
			"requester_id": requester_id,
			"relationship_kind": str(food.get("relationship_kind", "")),
			"item_instance_id": item_id,
			"fact_id": fact_id,
		})
		meal_count += 1

	_append_daily_social_chronicle(result, snapshot, tick_event)
	if result.is_empty():
		return {"results": [], "events": events}
	if meal_count > 0:
		result.set_narrative_result({
			"title": "聚落中的食物被重新分配",
			"summary": "%d 人吃到了食物，其中 %d 份来自同住者，%d 份来自邻里或工友；另有 %d 次跨家庭求助没有得到食物。" % [
				meal_count, shared_count, external_shared_count, failed_request_count
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


func _available_resource_amounts(snapshot: Variant) -> Dictionary:
	var rows := {}
	for stock: Dictionary in snapshot.get_resource_stocks():
		rows[str(stock.get("stock_id", ""))] = float(stock.get("current", 0.0))
	return rows


func _resource_plan(profile: Dictionary, available: Dictionary, snapshot: Variant = null, actor_id: String = "") -> Dictionary:
	var changes: Array = []
	for value: Variant in profile.get("resource_inputs", []):
		if not value is Dictionary:
			continue
		var input := value as Dictionary
		var stock_id := str(input.get("stock_id", ""))
		var amount := float(input.get("amount_per_cycle", input.get("amount", 0.0)))
		if stock_id == "" or amount <= 0.0:
			continue
		var current := float(available.get(stock_id, 0.0))
		var denial := "" if snapshot == null else Access.denial(snapshot, snapshot.get_resource_stock(stock_id), actor_id, "livelihood_production", amount)
		if current + 0.0001 < amount or denial != "":
			return {
				"ok": false,
				"changes": [],
				"missing": {
					"stock_id": stock_id,
					"label": str(input.get("label", "生产资源")),
					"amount": amount,
					"available": current,
					"denial": denial,
				},
			}
		changes.append({
			"stock_id": stock_id,
			"amount": amount,
			"resource_label": str(input.get("label", "生产资源")),
		})
	for change: Dictionary in changes:
		var stock_id := str(change.get("stock_id", ""))
		available[stock_id] = float(available.get(stock_id, 0.0)) - float(
			change.get("amount", 0.0)
		)
	return {"ok": true, "changes": changes, "missing": {}}


func _contains_currency_product(products: Array) -> bool:
	for product: Dictionary in products:
		if str(product.get("item_def_id", "")) == Treasury.CURRENCY:
			return true
	return false


func _profiles_by_scope(profiles: Array) -> Dictionary:
	var rows: Dictionary = {}
	for profile: Dictionary in profiles:
		var occupation_id := str(profile.get("occupation_id", ""))
		if occupation_id != "":
			rows[_profile_key(
				str(profile.get("settlement_id", "")), occupation_id
			)] = profile.duplicate(true)
	return rows


func _profile_key(settlement_id: String, occupation_id: String) -> String:
	return "%s::%s" % [settlement_id, occupation_id]


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


func _external_support_links(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		var relationship_kind := str(fact.get("relationship_kind", ""))
		if (
			str(fact.get("fact_type", "")) != "generated_social_relation"
			or relationship_kind not in ["settlement_neighbor", "workmate"]
		):
			continue
		var source_id := str(fact.get("actor_id", ""))
		var target_id := str(fact.get("target_id", ""))
		if source_id == "" or target_id == "":
			continue
		if not rows.has(source_id):
			rows[source_id] = []
		(rows[source_id] as Array).append({
			"requester_id": source_id,
			"contact_id": target_id,
			"relationship_kind": relationship_kind,
			"relationship_fact_id": str(fact.get("fact_id", "")),
		})
	return rows


func _external_contacts(
		snapshot: Variant,
		recipient_household_id: String,
		household_members: Array,
		external_links: Dictionary
) -> Array:
	var contacts: Array = []
	var seen: Dictionary = {}
	for member_value: Variant in household_members:
		var requester_id := str(member_value)
		for link: Dictionary in external_links.get(requester_id, []):
			var contact_id := str(link.get("contact_id", ""))
			var contact_household_id := str(snapshot.get_entity_state(
				contact_id, "household_id", ""
			))
			if (
				contact_id == ""
				or contact_household_id == ""
				or contact_household_id == recipient_household_id
			):
				continue
			var key := "%s>%s" % [requester_id, contact_id]
			if seen.has(key):
				continue
			seen[key] = true
			var row := link.duplicate(true)
			row["provider_household_id"] = contact_household_id
			row["support_score"] = _external_support_score(
				snapshot, requester_id, contact_id,
				str(link.get("relationship_kind", ""))
			)
			contacts.append(row)
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := int(a.get("support_score", 0))
		var b_score := int(b.get("support_score", 0))
		if a_score != b_score:
			return a_score > b_score
		return str(a.get("contact_id", "")) < str(b.get("contact_id", ""))
	)
	return contacts


func _find_external_food(
		snapshot: Variant,
		recipient_id: String,
		recipient_household_id: String,
		household_members: Array,
		external_links: Dictionary,
		available_quantity: Dictionary
) -> Dictionary:
	for contact: Dictionary in _external_contacts(
		snapshot,
		recipient_household_id,
		household_members,
		external_links
	):
		var contact_id := str(contact.get("contact_id", ""))
		if int(snapshot.get_relation(
			str(contact.get("requester_id", recipient_id)),
			contact_id,
			"trust",
			0
		)) < -10:
			continue
		var food := _find_food(
			snapshot, contact_id, [contact_id], available_quantity
		)
		if food.is_empty():
			continue
		food["external_support"] = true
		food["requester_id"] = str(contact.get("requester_id", recipient_id))
		food["provider_household_id"] = str(contact.get(
			"provider_household_id", ""
		))
		food["relationship_kind"] = str(contact.get(
			"relationship_kind", ""
		))
		food["relationship_fact_id"] = str(contact.get(
			"relationship_fact_id", ""
		))
		return food
	return {}


func _best_external_contact(
		snapshot: Variant,
		recipient_household_id: String,
		household_members: Array,
		external_links: Dictionary
) -> Dictionary:
	var contacts := _external_contacts(
		snapshot,
		recipient_household_id,
		household_members,
		external_links
	)
	return {} if contacts.is_empty() else (contacts[0] as Dictionary).duplicate(
		true
	)


func _external_support_score(
		snapshot: Variant,
		requester_id: String,
		contact_id: String,
		relationship_kind: String
) -> int:
	return (
		int(snapshot.get_relation(requester_id, contact_id, "trust", 0))
		+ int(snapshot.get_relation(requester_id, contact_id, "familiarity", 0))
		+ (8 if relationship_kind == "workmate" else 4)
	)


func _append_failed_food_request(
		result: Variant,
		snapshot: Variant,
		recipient: Dictionary,
		recipient_id: String,
		household_id: String,
		hunger: String,
		contact: Dictionary,
		tick_event: Dictionary,
		events: Array
) -> bool:
	var fact_id := "fact.npc_cross_household_food_request_failed.%s.day_%d" % [
		_safe_id(recipient_id),
		int(tick_event.get("day", 0)),
	]
	if _snapshot_has_fact(snapshot, fact_id):
		return false
	var requester_id := str(contact.get("requester_id", recipient_id))
	var contact_id := str(contact.get("contact_id", ""))
	var relationship_kind := str(contact.get("relationship_kind", ""))
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "npc_cross_household_food_request_failed",
		"actor_id": requester_id,
		"target_id": contact_id,
		"beneficiary_id": recipient_id,
		"household_id": household_id,
		"contact_household_id": str(contact.get("provider_household_id", "")),
		"relationship_kind": relationship_kind,
		"relationship_fact_id": str(contact.get("relationship_fact_id", "")),
		"source_fact_ids": [str(contact.get("relationship_fact_id", ""))],
		"hunger": hunger,
		"day": int(tick_event.get("day", 0)),
		"hour": int(tick_event.get("hour", 0)),
		"tick_event_id": str(tick_event.get("tick_event_id", "")),
		"summary": "%s沿着%s关系替%s求过一份食物，但对方当时也拿不出来。" % [
			_entity_name(snapshot, requester_id),
			_relationship_label(relationship_kind),
			str(recipient.get("display_name", recipient_id)),
		],
	})
	result.add_trace({
		"trace_id": "trace.npc_failed_food_request.%s.day_%d" % [
			_safe_id(recipient_id),
			int(tick_event.get("day", 0)),
		],
		"trace_type": "unanswered_food_request",
		"actor_id": requester_id,
		"target_id": contact_id,
		"location_id": str(snapshot.get_entity_state(
			recipient_id, "home_location_id", ""
		)),
		"source_fact_id": fact_id,
		"source_fact_ids": [fact_id],
		"source_fact_type": "npc_cross_household_food_request_failed",
		"display_name": "空手而回的求助痕迹",
		"description": "门边的泥印和空篮说明有人曾为食物跑过一趟，却没有带回东西。",
		"visible": false,
		"inspectable": true,
		"freshness": "fresh",
		"tags": ["food_request", "social_strain", "generated_trace"],
	})
	result.add_relationship_change({
		"source_id": requester_id,
		"target_id": contact_id,
		"axis": "trust",
		"delta": -1,
	})
	result.add_relationship_change({
		"source_id": requester_id,
		"target_id": contact_id,
		"axis": "resentment",
		"delta": 1,
	})
	events.append({
		"event_type": "cross_household_food_request_failed",
		"actor_id": requester_id,
		"target_id": contact_id,
		"beneficiary_id": recipient_id,
		"household_id": household_id,
		"relationship_kind": relationship_kind,
		"fact_id": fact_id,
	})
	return true


func _append_daily_social_chronicle(
		result: Variant,
		snapshot: Variant,
		tick_event: Dictionary
) -> void:
	var day := int(tick_event.get("day", 0))
	if int(tick_event.get("hour", 0)) != 23 or day <= 0:
		return
	var settlement_id := _generated_settlement_id(snapshot)
	if settlement_id == "":
		return
	var entry_id := "chronicle.generated_social_pressure.%s.day_%d" % [
		_safe_id(settlement_id), day,
	]
	for entry: Dictionary in snapshot.get_chronicle_entries():
		if str(entry.get("entry_id", "")) == entry_id:
			return
	var relevant_types := [
		"npc_cross_household_shared_food",
		"npc_cross_household_food_request_failed",
		"npc_food_debt_repaid",
		"npc_food_request_conflict",
		"npc_household_food_unmet",
	]
	var source_facts: Array = []
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) in relevant_types
			and int(fact.get("day", 0)) == day
		):
			source_facts.append(fact)
	for fact: Dictionary in result.facts_added:
		if (
			str(fact.get("fact_type", "")) in relevant_types
			and int(fact.get("day", 0)) == day
		):
			source_facts.append(fact)
	if source_facts.is_empty():
		return
	var source_fact_ids: Array[String] = []
	var help_count := 0
	var failed_count := 0
	var repayment_count := 0
	var conflict_count := 0
	var unmet_count := 0
	for fact: Dictionary in source_facts:
		var fact_id := str(fact.get("fact_id", ""))
		if fact_id != "" and fact_id not in source_fact_ids:
			source_fact_ids.append(fact_id)
		match str(fact.get("fact_type", "")):
			"npc_cross_household_shared_food":
				help_count += 1
			"npc_cross_household_food_request_failed":
				failed_count += 1
			"npc_food_debt_repaid":
				repayment_count += 1
			"npc_food_request_conflict":
				conflict_count += 1
			"npc_household_food_unmet":
				unmet_count += 1
	result.add_chronicle_entry({
		"entry_id": entry_id,
		"entry_type": "settlement_daily_life",
		"subject_id": settlement_id,
		"title": "第%d天的邻里食物往来" % day,
		"body": "这一天，聚落中有 %d 份食物跨过家门、%d 次实物偿还；%d 次求助空手而回，其中 %d 组关系发生争执，仍留下 %d 条没有解除的缺粮记录。" % [
			help_count, repayment_count, failed_count, conflict_count, unmet_count,
		],
		"day": day,
		"hour": 23,
		"location_id": str(snapshot.location.get("id", "")),
		"source_fact_ids": source_fact_ids,
		"source_fact_types": relevant_types.duplicate(),
		"claims": [{
			"text": "邻里食物往来与缺粮压力来自当日居民行为。",
			"fact_ids": source_fact_ids.duplicate(),
		}],
		"tags": ["generated", "daily_life", "food_pressure", "settlement"],
	})


func _generated_settlement_id(snapshot: Variant) -> String:
	for person: Dictionary in _sorted_people(snapshot):
		var settlement_id := str(snapshot.get_entity_state(
			str(person.get("id", "")), "settlement_id", ""
		))
		if settlement_id != "":
			return settlement_id
	return ""


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	for entity: Dictionary in snapshot.get_entities_by_type("person"):
		if str(entity.get("id", "")) == entity_id:
			return str(entity.get("display_name", entity_id))
	return entity_id


func _relationship_label(relationship_kind: String) -> String:
	return "工友" if relationship_kind == "workmate" else "邻里"


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
