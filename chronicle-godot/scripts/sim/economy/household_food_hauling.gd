extends RefCounted
class_name V5HouseholdFoodHauling

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Family = preload("res://scripts/sim/npc/household_provisioning.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Budget = preload("res://scripts/sim/economy/household_food_budget.gd")
const Assistance = preload("res://scripts/sim/npc/community_assistance.gd")
const TYPE := "household_food_hauling"
const PROFILE := {"version": 1, "fee": 4, "maximum_hours": 4, "deadline_hours": 18,
	"retry_hours": 6, "payer_reserve": 1, "maximum_portions": 4}


static func enabled(config: Dictionary) -> bool:
	return int(config.get("version", 0)) == 1


static func validate_config(config: Dictionary) -> String:
	if int(config.get("version", 0)) not in [0, 1]:
		return "unsupported_household_food_hauling_version"
	if enabled(config):
		if config.has("allow_new_contracts") and not config.allow_new_contracts is bool:
			return "invalid_food_hauling_dispatch_flag"
		for key: String in PROFILE:
			var value: Variant = config.get(key)
			if not (value is int or value is float) or float(value) != float(int(value)) or int(value) < 1:
				return "invalid_household_food_hauling_config"
	return ""


static func is_carrier(actor: Dictionary, config: Dictionary) -> bool:
	return enabled(config) and "generated_resident" in actor.get("tags", []) \
		and actor.get("states", {}).get("occupation_id") == "road_carter"


static func active_order(snapshot: Variant, actor: String) -> Dictionary:
	for order: Dictionary in snapshot.exchanges:
		if order.get("exchange_type") == TYPE and order.get("party_b") == actor \
				and order.get("status") in ["in_transit", "returning"]:
			return order
	return {}


static func assigned_targets(snapshot: Variant, payer: String, tick: Dictionary) -> Array:
	var targets: Array = []
	for order: Dictionary in snapshot.exchanges:
		if order.get("exchange_type") == TYPE and order.get("party_a") == payer \
				and Family.absolute_hour(tick) < int(order.get("deadline_tick", 0)):
			targets.append_array(order.get("recipient_ids", []))
	return targets


static func recently_visited(snapshot: Variant, carrier: String, place: String, tick: Dictionary, config: Dictionary) -> bool:
	for fact: Dictionary in snapshot.get_facts_by_actor(carrier):
		if fact.get("fact_type") == "food_hauling_no_contract" and fact.get("actor_id") == carrier \
				and fact.get("location_id") == place and Family.absolute_hour(tick) - Family.absolute_hour(fact) < int(config.retry_hours):
			return true
	return false


func plan_contact(snapshot: Variant, carrier: Dictionary, tick: Dictionary, config: Dictionary,
		family_config: Dictionary, stores: Dictionary, find_route: Callable, budget_config: Dictionary = {}, community_config: Dictionary = {}) -> Dictionary:
	if not enabled(config) or not _present(carrier):
		return {}
	var active := active_order(snapshot, str(carrier.id))
	if not active.is_empty():
		return _progress(snapshot, carrier, active, tick, stores, budget_config)
	var self_dispatch := str(carrier.states.get("daily_intent_id", "")).begins_with("community_delivery:")
	if self_dispatch and carrier.states.get("location_id") == carrier.states.get("workplace_id"):
		var self_config := config.duplicate(true)
		self_config.fee = 0
		var depot: Dictionary = snapshot.get_entity(Storage.depot_id(str(carrier.id)))
		for need: Dictionary in Assistance.requests(snapshot, carrier, tick, community_config, budget_config):
			if str(carrier.states.daily_intent_id) == "community_delivery:" + str(need.request_root_fact_id) and not depot.is_empty():
				need["self_delivery"] = true
				return _try_order(snapshot, carrier, carrier, depot, need, tick, self_config, stores, find_route)
	if not is_carrier(carrier, config):
		return {}
	if not bool(config.get("allow_new_contracts", true)):
		return {}
	var location := str(carrier.states.get("location_id", ""))
	if carrier.states.get("daily_activity") not in ["seeking_work", "seeking_food", "arrived"] \
			or recently_visited(snapshot, str(carrier.id), location, tick, config):
		return {}
	var is_worksite := false
	for depot: Dictionary in snapshot.get_entities_by_type("environment_detail"):
		if "worksite_food_store" not in depot.get("tags", []) or depot.get("stock_location_id") != location:
			continue
		is_worksite = true
		var owner: Dictionary = snapshot.get_entity(str(depot.stock_custodian_id))
		if not _present(owner) or owner.states.get("location_id") != location:
			continue
		var need := Family.request(snapshot, owner, tick, family_config)
		if Budget.enabled(budget_config):
			need = Budget.request(snapshot, owner, tick, budget_config)
		var needs: Array = [need] if not need.is_empty() else []
		needs.append_array(Assistance.requests(snapshot, owner, tick, community_config, budget_config))
		for request: Dictionary in needs:
			var planned := _try_order(snapshot, carrier, owner, depot, request, tick, config, stores, find_route)
			if not planned.is_empty():
				return planned
	if is_worksite:
		var fact := _fact("fact.haul_visit.%s.%d" % [carrier.id, Family.absolute_hour(tick)], "food_hauling_no_contract", carrier, tick,
			"%s到场询问送粮差事，没有谈成具备存粮、付款能力和收货需求的托付。" % carrier.display_name)
		var result := Result.new()
		result.add_fact(fact)
		result.mark_resolved("food_hauling_no_contract")
		return {"transaction": result, "events": [fact]}
	return {}


func _try_order(snapshot: Variant, carrier: Dictionary, owner: Dictionary, depot: Dictionary, need: Dictionary,
		tick: Dictionary, config: Dictionary, stores: Dictionary, find_route: Callable) -> Dictionary:
	var location := str(carrier.states.location_id)
	if need.home_location_id == location:
		return {}
	var route: Dictionary = find_route.call(location, str(need.home_location_id))
	if route.is_empty() or int(route.total_hours) > int(need.get("maximum_hours", config.maximum_hours)):
		return {}
	var targets: Array = []
	for remembered: Dictionary in need.targets:
		var already_sent := false
		for order: Dictionary in snapshot.exchanges:
			if order.get("exchange_type") == TYPE and order.get("party_a") == owner.id \
					and Family.absolute_hour(tick) < int(order.get("deadline_tick", 0)) \
					and remembered.target_id in order.get("recipient_ids", []):
				already_sent = true
		if not already_sent:
			targets.append(str(remembered.target_id))
	targets = targets.slice(0, int(config.maximum_portions))
	var amount := int(need.get("pantry_portions", targets.size()))
	var food := Storage.quantity(stores.item_store.list_items_for_owner(str(depot.id)), str(depot.id))
	var fee := int(config.fee)
	if targets.is_empty() or food < amount + int(need.get("retained_portions", config.payer_reserve)) \
			or Food.balance(stores.item_store.list_items_for_owner(str(owner.id)), str(owner.id)) < fee:
		return {}
	var hour := Family.absolute_hour(tick)
	if need.get("community_withheld", false):
		for previous: Dictionary in snapshot.get_facts_by_actor(str(owner.id)):
			if previous.get("fact_type") == "community_aid_withheld" and previous.get("community_policy_id") == need.community_policy_id and previous.get("requester_id") == need.requester_id:
				return {}
		var withheld := _fact("fact.community_aid_withheld.%s.%d" % [owner.id, hour], "community_aid_withheld", owner, tick,
			"%s能承担这次送粮，但听到的本地留粮约定尚未解除，暂不接受邻聚落的送粮请求。货与钱仍归本人。" % owner.display_name, need.source_fact_ids)
		withheld.merge({"target_id": carrier.id, "requester_id": need.requester_id, "community_policy_id": need.community_policy_id})
		var refusal := Result.new()
		refusal.add_fact(withheld)
		refusal.mark_resolved("community_aid_withheld")
		return {"transaction": refusal, "events": [withheld]}
	var id := "exchange.food_haul.%s.%s.%d" % [owner.id, carrier.id, hour]
	var fact_id := "fact." + id
	var result := Result.new()
	var escrow := {"kind": "escrow", "id": id}
	var sources: Array = need.source_fact_ids.duplicate()
	var remaining := amount
	for item: Dictionary in stores.item_store.list_items_for_owner(str(depot.id)):
		if not Food.is_food(item) or remaining <= 0:
			continue
		var source := str(item.get("provenance", {}).get("created_by_fact_id", ""))
		for history: Dictionary in item.get("history", []):
			if history.get("event_type") in ["transferred", "split_from"]:
				source = str(history.get("fact_id", source))
		if source != "" and source not in sources:
			sources.append(source)
		remaining -= int(item.quantity)
	_move(result, stores.item_store.list_items_for_owner(str(depot.id)), amount, escrow, fact_id, hour, false)
	_move(result, stores.item_store.list_items_for_owner(str(owner.id)), fee, escrow, fact_id, hour, true)
	var order := {"exchange_id": id, "exchange_type": TYPE, "status": "in_transit", "party_a": owner.id,
		"party_b": carrier.id, "origin_location_id": location, "destination_location_id": need.home_location_id,
		"stock_entity_id": depot.id, "recipient_ids": targets, "delivered_ids": [], "fee": fee,
		"quantity": amount, "created_tick": hour, "deadline_tick": hour + int(config.deadline_hours),
		"source_fact_ids": [fact_id], "need_fact_ids": need.source_fact_ids}
	if need.has("pantry_id"):
		order["pantry_id"] = need.pantry_id
		order["delivered_portions"] = 0
	if need.has("community_request_id"):
		for key: String in ["community_request_id", "request_root_fact_id", "requester_id", "community_policy_id"]:
			order[key] = need[key]
	if need.get("self_delivery", false):
		order["self_delivery"] = true
	result.add_exchange(order)
	var destination := "邻聚落请求者的共有粮柜" if need.has("community_request_id") else ("家中共有粮柜" if need.has("pantry_id") else "家人手中")
	var fact := _fact(fact_id, "food_hauling_accepted", carrier, tick,
		"%s接下%s的送粮托付：把 %d 份送到%s后，才可领取已封存的 %d 枚铜币。" % [carrier.display_name, owner.display_name, amount, destination, fee], sources)
	fact.merge({"target_id": owner.id, "exchange_id": id, "quantity": amount, "fee": fee,
		"destination_location_id": need.home_location_id, "recipient_ids": targets})
	if need.has("community_request_id"):
		fact["community_request_id"] = need.community_request_id
		fact["requester_id"] = need.requester_id
	if need.get("self_delivery", false):
		fact["self_delivery"] = true
		fact.summary = "%s决定暂放手边工作，亲自把 %d 份自有口粮送到邻聚落请求者的粮柜。货物已单独装好，只能实际送达或原路带回，没有额外报酬。" % [owner.display_name, amount]
	result.add_fact(fact)
	result.mark_resolved("food_hauling_accepted")
	return {"transaction": result, "events": [fact]}


func _progress(snapshot: Variant, carrier: Dictionary, order: Dictionary, tick: Dictionary, stores: Dictionary, budget_config: Dictionary = {}) -> Dictionary:
	var error := _validate_escrow(order, stores)
	if error != "":
		return {"error": error}
	var hour := Family.absolute_hour(tick)
	var place := str(carrier.states.get("location_id", ""))
	var id := str(order.exchange_id)
	var escrow := {"kind": "escrow", "id": id}
	var items: Array = stores.item_store.list_items_for_holder(escrow)
	var result := Result.new()
	var sources: Array = order.source_fact_ids
	var fact_id := "fact.food_haul.%s.%d" % [id, hour]
	var fact: Dictionary = {}
	if order.status == "returning" and place == order.origin_location_id:
		# The carrier returns the parcel physically. Cash stays in the owner's depot until collected.
		_move(result, items, 100000, {"kind": "entity", "id": str(order.stock_entity_id)}, fact_id, hour, false)
		var owner: Dictionary = snapshot.get_entity(str(order.party_a))
		var money_holder := str(owner.id) if _present(owner) and owner.states.get("location_id") == place else str(order.stock_entity_id)
		_move(result, items, 100000, {"kind": "entity", "id": money_holder}, fact_id, hour, true)
		result.add_exchange_update({"exchange_id": id, "status": "returned", "returned_tick": hour,
			"source_fact_ids": sources + [fact_id]})
		fact = _fact(fact_id, "food_hauling_returned", carrier, tick, "%s把未交出的粮食与未领取的运费带回原作业地。" % carrier.display_name, sources)
	elif order.status == "in_transit" and hour >= int(order.deadline_tick):
		result.add_exchange_update({"exchange_id": id, "status": "returning", "source_fact_ids": sources + [fact_id]})
		fact = _fact(fact_id, "food_hauling_return_started", carrier, tick, "%s的送粮托付已逾期，停止交付，携余粮与运费返回。" % carrier.display_name, sources)
	elif order.status == "in_transit" and place == order.destination_location_id and order.has("pantry_id"):
		var pantry: Dictionary = snapshot.get_entity(str(order.pantry_id))
		var stock := Food.food_quantity(stores.item_store.list_items_for_owner(str(order.pantry_id)), str(order.pantry_id))
		if not Budget.enabled(budget_config) or pantry.get("stock_location_id") != place:
			return {"error": "food_hauling_pantry_access_invalid"}
		if stock + int(order.quantity) > int(budget_config.capacity):
			result.add_exchange_update({"exchange_id": id, "status": "returning", "source_fact_ids": sources + [fact_id]})
			fact = _fact(fact_id, "food_hauling_return_started", carrier, tick, "%s到场发现粮柜已满，不能凭空卸货领钱，携带原货返回。" % carrier.display_name, sources)
		else:
			_move(result, items, int(order.quantity), {"kind": "entity", "id": str(order.pantry_id)}, fact_id, hour, false)
			_move(result, items, int(order.fee), {"kind": "entity", "id": str(carrier.id)}, fact_id, hour, true)
			result.add_exchange_update({"exchange_id": id, "status": "settled", "delivered_portions": order.quantity,
				"settled_tick": hour, "source_fact_ids": sources + [fact_id]})
			fact = _fact(fact_id, "food_hauling_stocked", carrier, tick, "%s把 %d 份托运粮食存入约定的家庭粮柜，领取 %d 枚铜币。家人仍须回家取粮才能吃到。" % [carrier.display_name, int(order.quantity), int(order.fee)], sources)
			fact.merge({"pantry_id": order.pantry_id, "payer_id": order.party_a, "quantity": order.quantity, "fee_paid": order.fee})
			if order.get("self_delivery", false):
				fact.summary = "%s亲自把 %d 份自有口粮送入约定的邻里粮柜；这趟路花了自己的时间，没有运费收入。" % [carrier.display_name, int(order.quantity)]
			if order.has("community_request_id"):
				fact["community_request_id"] = order.community_request_id
				if not order.get("self_delivery", false):
					fact.summary += " 这是%s听到请求后自愿出粮并付运费的邻里援助。" % snapshot.get_entity(str(order.party_a)).display_name
	elif order.status == "in_transit" and place == order.destination_location_id:
		var delivered: Array = order.delivered_ids.duplicate()
		for recipient: String in order.recipient_ids:
			if recipient in delivered:
				continue
			var target: Dictionary = snapshot.get_entity(recipient)
			if not _present(target) or target.states.get("location_id") != place:
				continue
			# At the door the recipient can accept useful reserves, but never an unwanted surplus.
			if Food.food_quantity(stores.item_store.list_items_for_owner(recipient), recipient) >= 2:
				continue
			var available: Array = stores.item_store.list_items_for_holder(escrow)
			_move(result, available, 1, {"kind": "entity", "id": recipient}, fact_id, hour, false)
			delivered.append(recipient)
			# One recipient per transaction avoids reusing a pre-transfer stack snapshot.
			fact = _fact(fact_id, "food_hauling_delivered", carrier, tick, "%s把托运的一份粮食当面交给%s。" % [carrier.display_name, target.display_name], sources)
			fact.merge({"target_id": recipient, "payer_id": order.party_a, "quantity": 1})
			result.add_memory({"memory_id": "memory." + fact_id, "memory_type": "received_hauled_food",
				"owner_id": recipient, "target_id": carrier.id, "source_fact_id": fact_id, "source_fact_ids": [fact_id], "summary": fact.summary})
			result.add_relationship_change({"source_id": recipient, "target_id": str(carrier.id), "axis": "trust", "delta": 1})
			var complete: bool = delivered.size() == order.recipient_ids.size()
			var update := {"exchange_id": id, "delivered_ids": delivered, "source_fact_ids": sources + [fact_id]}
			if complete:
				_move(result, items, int(order.fee), {"kind": "entity", "id": str(carrier.id)}, fact_id, hour, true)
				update.merge({"status": "settled", "settled_tick": hour})
				fact["fee_paid"] = order.fee
				fact["summary"] += " 约定收货人均已收到粮食，领取 %d 枚铜币运费。" % int(order.fee)
			result.add_exchange_update(update)
			break
	if fact.is_empty():
		return {}
	fact["exchange_id"] = id
	result.add_fact(fact)
	result.mark_resolved("food_hauling_progress")
	return {"transaction": result, "events": [fact]}


func _move(result: Variant, items: Array, amount: int, holder: Dictionary, fact_id: String, hour: int, currency: bool) -> int:
	var moved := 0
	for item: Dictionary in items:
		if (item.get("item_def_id") != Food.CURRENCY if currency else not Food.is_food(item)) or moved >= amount:
			continue
		var count := mini(amount - moved, int(item.quantity))
		var change := {"item_instance_id": item.item_instance_id, "new_holder": holder,
			"expected_holder": item.holder, "source_fact_ids": [fact_id], "updated_tick": hour}
		if count == int(item.quantity):
			change["operation"] = "transfer"
		else:
			change.merge({"operation": "split_stack", "quantity": count,
				"new_item_instance_id": "%s.%s.%d" % [fact_id, "cash" if currency else "food", moved]})
		result.add_item_change(change)
		moved += count
	return moved


static func validate_order(order: Dictionary, stores: Dictionary, locations: Dictionary) -> String:
	if order.get("exchange_type") != TYPE:
		return ""
	if order.get("status") not in ["in_transit", "returning", "returned", "settled"]:
		return "invalid_food_haul_status"
	for key: String in ["party_a", "party_b", "stock_entity_id"]:
		if not stores.entity_store.has_entity(str(order.get(key, ""))):
			return "invalid_food_haul_party"
	var self_delivery: bool = order.get("self_delivery", false) == true
	if (order.party_a == order.party_b and not self_delivery) or stores.entity_store.get_entity(str(order.party_a)).get("type") != "person" \
			or stores.entity_store.get_entity(str(order.party_b)).get("type") != "person":
		return "invalid_food_haul_party"
	var depot: Dictionary = stores.entity_store.get_entity(str(order.stock_entity_id))
	if depot.get("stock_custodian_id") != order.party_a or depot.get("stock_location_id") != order.get("origin_location_id"):
		return "invalid_food_haul_ownership"
	for key: String in ["origin_location_id", "destination_location_id"]:
		if not locations.has(str(order.get(key, ""))):
			return "invalid_food_haul_location"
	for key: String in ["fee", "quantity", "created_tick", "deadline_tick"]:
		var value: Variant = order.get(key)
		var minimum := 0 if key == "fee" and self_delivery else 1
		if not (value is int or value is float) or int(value) < minimum or float(value) != float(int(value)):
			return "invalid_food_haul_terms"
	if self_delivery and (order.party_a != order.party_b or order.fee != 0 or not order.has("community_request_id")):
		return "invalid_self_food_haul_terms"
	if not order.get("recipient_ids") is Array or not order.get("delivered_ids") is Array \
			or order.recipient_ids.is_empty() or (not order.has("pantry_id") and order.recipient_ids.size() != int(order.quantity)) \
			or int(order.deadline_tick) <= int(order.created_tick):
		return "invalid_food_haul_terms"
	if order.has("pantry_id"):
		var delivered: Variant = order.get("delivered_portions")
		if not (delivered is int or delivered is float) or float(delivered) != float(int(delivered)) \
				or int(delivered) not in [0, int(order.quantity)] or not order.delivered_ids.is_empty():
			return "invalid_food_haul_delivery"
		var pantry: Dictionary = stores.entity_store.get_entity(str(order.pantry_id))
		if "household_food_store" not in pantry.get("tags", []) or pantry.get("stock_location_id") != order.destination_location_id:
			return "invalid_food_haul_pantry"
	var seen: Array = []
	for recipient: Variant in order.recipient_ids:
		if not recipient is String or recipient in seen or stores.entity_store.get_entity(str(recipient)).get("type") != "person":
			return "invalid_food_haul_recipient"
		seen.append(recipient)
	seen.clear()
	for recipient: Variant in order.delivered_ids:
		if not recipient is String or recipient not in order.recipient_ids or recipient in seen:
			return "invalid_food_haul_delivery"
		seen.append(recipient)
	for key: String in ["source_fact_ids", "need_fact_ids"]:
		if not order.get(key) is Array or order[key].is_empty():
			return "invalid_food_haul_evidence"
		for source: Variant in order[key]:
			if not source is String or stores.fact_store.get_fact(str(source)).is_empty():
				return "invalid_food_haul_evidence"
	var accepted: Dictionary = stores.fact_store.get_fact(str(order.source_fact_ids[0]))
	if bool(accepted.get("self_delivery", false)) != self_delivery:
		return "invalid_self_food_haul_agreement"
	if order.has("community_request_id"):
		var request: Dictionary = stores.fact_store.get_fact(str(order.community_request_id))
		var root: Dictionary = stores.fact_store.get_fact(str(order.get("request_root_fact_id", "")))
		var policy: Dictionary = stores.fact_store.get_fact(str(order.get("community_policy_id", "")))
		var policy_root: Dictionary = stores.fact_store.get_fact(str(policy.get("root_fact_id", policy.get("fact_id", ""))))
		var group: Dictionary = stores.entity_store.get_entity(str(policy_root.get("subject_id", "")))
		var terms: Dictionary = root.get("payload", {}).get("delivery_request", {})
		if request.get("fact_type") != "community_message_heard" or request.get("actor_id") != order.party_a \
				or request.get("root_fact_id") != root.get("fact_id") or request.get("subject_id") != order.get("requester_id") \
				or request.fact_id not in order.need_fact_ids \
				or terms.get("pantry_id") != order.get("pantry_id") or terms.get("home_location_id") != order.destination_location_id \
				or not terms.has("quantity") or int(order.quantity) > int(terms.quantity) or accepted.get("community_request_id") != request.fact_id \
				or accepted.get("requester_id") != order.requester_id:
			return "invalid_community_food_haul_evidence"
		if Family.absolute_hour(request) > int(order.created_tick):
			return "invalid_community_food_haul_permission"
		if not _known_at(stores, str(order.party_a), str(request.fact_id), int(order.created_tick)):
			return "invalid_community_food_haul_expired_request"
		if order.get("community_policy_id", "") != "" and (policy.get("topic") != "policy" or policy_root.get("fact_type") != "community_policy_changed" \
				or policy.get("actor_id") != order.party_a or policy.get("fact_id") not in order.need_fact_ids \
				or policy_root.get("payload", {}).get("policy") not in ["open", "relief"] or order.party_a not in group.get("member_ids", []) \
				or Family.absolute_hour(policy) > int(order.created_tick)):
			return "invalid_community_food_haul_permission"
		if not policy.is_empty() and not _known_at(stores, str(order.party_a), str(policy.fact_id), int(order.created_tick)):
			return "invalid_community_food_haul_expired_policy"
		for recipient: String in order.recipient_ids:
			if recipient not in terms.get("recipient_ids", []):
				return "invalid_community_food_haul_recipient"
	elif order.has("pantry_id"):
		var witnessed := false
		for source: String in order.need_fact_ids:
			var observation: Dictionary = stores.fact_store.get_fact(source)
			witnessed = witnessed or (observation.get("fact_type") == "household_pantry_observed" \
				and observation.get("actor_id") == order.party_a and observation.get("pantry_id") == order.pantry_id)
		if not witnessed:
			return "invalid_food_haul_pantry_evidence"
	if accepted.get("fact_type") != "food_hauling_accepted" or accepted.get("exchange_id") != order.get("exchange_id") \
			or accepted.get("actor_id") != order.party_b or accepted.get("target_id") != order.party_a \
			or accepted.get("quantity") != order.quantity or accepted.get("fee") != order.fee \
			or accepted.get("recipient_ids") != order.recipient_ids or accepted.get("destination_location_id") != order.destination_location_id \
			or Family.absolute_hour(accepted) != int(order.created_tick):
		return "invalid_food_haul_agreement"
	if order.status in ["settled", "returned"]:
		var receipt: Dictionary = stores.fact_store.get_fact(str(order.source_fact_ids.back()))
		var expected := "food_hauling_returned" if order.status == "returned" else ("food_hauling_stocked" if order.has("pantry_id") else "food_hauling_delivered")
		if receipt.get("fact_type") != expected or receipt.get("exchange_id") != order.exchange_id \
				or receipt.get("actor_id") != order.party_b or (order.status == "settled" and receipt.get("fee_paid") != order.fee):
			return "invalid_food_haul_receipt"
	return _validate_escrow(order, stores)


static func _known_at(stores: Dictionary, owner: String, source: String, tick: int) -> bool:
	for memory: Dictionary in stores.memory_store.memories:
		if memory.get("memory_type") == "community_report" and memory.get("owner_id") == owner \
				and memory.get("source_fact_id") == source and int(memory.get("learned_hour", tick + 1)) <= tick \
				and tick < int(memory.get("expires_hour", -1)):
			return true
	return false


static func validate_custody(stores: Dictionary) -> String:
	var contracts := {}
	var busy_carriers := {}
	for order: Dictionary in stores.exchange_store.list_exchanges():
		if order.get("exchange_type") != TYPE:
			continue
		contracts[str(order.get("exchange_id", ""))] = true
		if order.get("status") in ["in_transit", "returning"]:
			var carrier := str(order.get("party_b", ""))
			if busy_carriers.has(carrier):
				return "multiple_active_food_hauls_for_carrier"
			busy_carriers[carrier] = true
	for item: Dictionary in stores.item_store.list_items():
		var holder: Dictionary = item.get("holder", {})
		if holder.get("kind") == "escrow" and str(holder.get("id", "")).begins_with("exchange.food_haul.") \
				and not contracts.has(str(holder.id)):
			return "orphan_food_haul_cargo"
	return ""


static func _validate_escrow(order: Dictionary, stores: Dictionary) -> String:
	var food := 0
	var cash := 0
	for item: Dictionary in stores.item_store.list_items_for_holder({"kind": "escrow", "id": str(order.exchange_id)}):
		if Food.is_food(item):
			food += int(item.quantity)
		elif item.get("item_def_id") == Food.CURRENCY:
			cash += int(item.quantity)
		else:
			return "invalid_food_haul_cargo"
	var closed: bool = order.status in ["returned", "settled"]
	var delivered := int(order.get("delivered_portions", order.delivered_ids.size()))
	if food != (0 if closed else int(order.quantity) - delivered) or cash != (0 if closed else int(order.fee)):
		return "invalid_food_haul_escrow"
	if order.status == "settled" and delivered != int(order.quantity):
		return "invalid_food_haul_settlement"
	return ""


static func _present(actor: Dictionary) -> bool:
	var state: Dictionary = actor.get("states", {})
	return not actor.is_empty() and bool(state.get("alive", true)) and state.get("life_status", "alive") == "alive" \
		and state.get("daily_route_id", "") == ""


func _fact(id: String, type: String, carrier: Dictionary, tick: Dictionary, summary: String, sources: Array = []) -> Dictionary:
	return {"fact_id": id, "fact_type": type, "actor_id": carrier.id, "location_id": carrier.states.get("location_id", ""),
		"day": tick.day, "hour": tick.hour, "summary": summary, "source_fact_ids": sources}
