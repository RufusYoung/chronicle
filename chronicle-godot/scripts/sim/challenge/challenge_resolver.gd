extends RefCounted
class_name V5ChallengeResolver

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const ChallengeChronicleBuilderModel = preload(
	"res://scripts/sim/chronicle/challenge_chronicle_builder.gd"
)

var chronicle_builder: Variant = ChallengeChronicleBuilderModel.new()


func resolve_preparation(
		challenge: Dictionary,
		snapshot: Variant,
		event_id: int
) -> Variant:
	var result = TransactionResultModel.new()
	var preparation: Dictionary = challenge.get("preparation", {})
	var challenge_id := str(challenge.get("challenge_id", ""))
	var target_id := str(challenge.get("target_entity_id", ""))
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var state_key := str(preparation.get("state_key", "prepared"))

	result.add_state_change({
		"entity_id": target_id,
		"key": state_key,
		"to": true,
	})
	result.add_fact({
		"fact_id": "actor_prepared_for_challenge:%d" % event_id,
		"fact_type": "actor_prepared_for_challenge",
		"source_id": actor_id,
		"target_id": target_id,
		"challenge_id": challenge_id,
		"location_id": str(snapshot.location.get("id", "")),
		"preparation_bonus": int(preparation.get("bonus", 0)),
		"visibility": "known",
		"source_action": "challenge_preparation",
	})
	_apply_configured_state_changes(
		result,
		preparation.get("state_changes", []),
		actor_id,
		target_id
	)
	_apply_preparation_items(
		result,
		challenge,
		preparation,
		snapshot,
		event_id
	)
	_apply_configured_facts(
		result,
		preparation.get("additional_facts", []),
		challenge_id,
		snapshot,
		event_id,
		"challenge_preparation",
		["actor_prepared_for_challenge:%d" % event_id],
		{}
	)
	result.set_narrative_result({
		"title": str(preparation.get("narrative_title", "做好准备")),
		"summary": str(
			preparation.get("narrative", "你花时间检查了眼前的危险。")
		),
		"challenge_id": challenge_id,
		"outcome": "prepared",
	})
	result.mark_resolved("challenge_preparation")
	return result


func resolve_attempt(
		challenge: Dictionary,
		snapshot: Variant,
		roll: int,
		event_id: int,
		time_summary: Dictionary
) -> Variant:
	var result = TransactionResultModel.new()
	var challenge_id := str(challenge.get("challenge_id", ""))
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var target_id := str(challenge.get("target_entity_id", ""))
	var stat_key := str(challenge.get("stat_key", "perception"))
	var stat_value := int(snapshot.get_player_value(stat_key, 0))
	var difficulty := int(challenge.get("difficulty", 10))
	var preparation: Dictionary = challenge.get("preparation", {})
	var prepared := bool(snapshot.get_entity_state(
		target_id,
		str(preparation.get("state_key", "prepared")),
		false
	))
	var preparation_bonus := int(preparation.get("bonus", 0)) if prepared else 0
	var total := roll + stat_value + preparation_bonus
	var succeeded := total >= difficulty
	var outcome := "success" if succeeded else "failure"
	var status_key := str(challenge.get("status_state_key", "challenge_status"))

	result.add_state_change({
		"entity_id": target_id,
		"key": status_key,
		"to": outcome,
	})
	result.add_fact({
		"fact_id": "actor_attempted_challenge:%d" % event_id,
		"fact_type": "actor_attempted_challenge",
		"source_id": actor_id,
		"target_id": target_id,
		"challenge_id": challenge_id,
		"location_id": str(snapshot.location.get("id", "")),
		"roll": roll,
		"stat_key": stat_key,
		"stat_value": stat_value,
		"preparation_bonus": preparation_bonus,
		"total": total,
		"difficulty": difficulty,
		"outcome": outcome,
		"visibility": "known",
		"source_action": "challenge_check",
	})
	var attempt_consequences: Dictionary = challenge.get(
		"attempt_consequences",
		{}
	)
	_apply_configured_state_changes(
		result,
		attempt_consequences.get("state_changes", []),
		actor_id,
		target_id
	)
	_apply_configured_facts(
		result,
		attempt_consequences.get("additional_facts", []),
		challenge_id,
		snapshot,
		event_id,
		"challenge_check",
		["actor_attempted_challenge:%d" % event_id],
		time_summary
	)

	if succeeded:
		_apply_success(
			result,
			challenge,
			snapshot,
			event_id,
			time_summary
		)
		var chronicle_entry: Dictionary = chronicle_builder.build_entry(
			challenge,
			snapshot,
			result.facts_added,
			time_summary,
			event_id
		)
		if not chronicle_entry.is_empty():
			result.add_chronicle_entry(chronicle_entry)
	else:
		_apply_failure(result, challenge, snapshot, event_id)

	var outcome_data: Dictionary = (
		challenge.get("success", {})
		if succeeded
		else challenge.get("failure", {})
	)
	result.set_narrative_result({
		"title": str(outcome_data.get("narrative_title", "检定结果")),
		"summary": str(outcome_data.get("narrative", "局面已经产生结果。")),
		"challenge_id": challenge_id,
		"outcome": outcome,
		"roll": roll,
		"stat_key": stat_key,
		"stat_value": stat_value,
		"preparation_bonus": preparation_bonus,
		"total": total,
		"difficulty": difficulty,
	})
	result.mark_resolved("challenge_check")
	return result


func _apply_configured_state_changes(
		result: Variant,
		change_values: Variant,
		actor_id: String,
		target_id: String
) -> void:
	if not change_values is Array:
		return
	for change_value: Variant in change_values:
		if not change_value is Dictionary:
			continue
		var change := (change_value as Dictionary).duplicate(true)
		var entity_id := str(change.get("entity_id", "actor"))
		if entity_id == "actor":
			entity_id = actor_id
		elif entity_id == "target":
			entity_id = target_id
		if (
			entity_id == ""
			or str(change.get("key", "")) == ""
			or (
				not change.has("to")
				and not change.has("delta")
				and not change.has("degrade")
			)
		):
			continue
		change["entity_id"] = entity_id
		result.add_state_change(change)


func _apply_preparation_items(
		result: Variant,
		challenge: Dictionary,
		preparation: Dictionary,
		snapshot: Variant,
		event_id: int
) -> void:
	var item_values: Variant = preparation.get("items", [])
	if not item_values is Array:
		return
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var inventory_item_ids: Array = (
		snapshot.get_player_value("inventory_item_ids", []) as Array
	).duplicate(true)
	var inventory_changed := false
	for item_value: Variant in item_values:
		if not item_value is Dictionary:
			continue
		var item := (item_value as Dictionary).duplicate(true)
		var item_id := str(item.get("item_id", item.get("id", "")))
		if item_id == "":
			continue
		item["item_id"] = item_id
		item["owner_id"] = actor_id
		var provenance: Dictionary = (
			item.get("provenance", {}) as Dictionary
		).duplicate(true)
		provenance["acquired_at"] = str(snapshot.location.get("id", ""))
		provenance["source_preparation_id"] = str(
			challenge.get("challenge_id", "")
		)
		item["provenance"] = provenance
		result.add_item_change({
			"operation": "create",
			"item": item,
		})
		if item_id not in inventory_item_ids:
			inventory_item_ids.append(item_id)
			inventory_changed = true
		result.add_fact({
			"fact_id": "actor_acquired_preparation_item:%d:%s"
				% [event_id, item_id],
			"fact_type": "actor_acquired_preparation_item",
			"source_id": actor_id,
			"target_id": item_id,
			"target_display_name": str(
				item.get("display_name", "远行装备")
			),
			"challenge_id": str(challenge.get("challenge_id", "")),
			"location_id": str(snapshot.location.get("id", "")),
			"cause_fact_ids": [
				"actor_prepared_for_challenge:%d" % event_id
			],
			"visibility": "known",
			"source_action": "challenge_preparation",
		})
	if inventory_changed:
		result.add_state_change({
			"entity_id": actor_id,
			"key": "inventory_item_ids",
			"to": inventory_item_ids,
		})


func _apply_configured_facts(
		result: Variant,
		fact_values: Variant,
		challenge_id: String,
		snapshot: Variant,
		event_id: int,
		source_action: String,
		cause_fact_ids: Array,
		time_summary: Dictionary
) -> void:
	if not fact_values is Array:
		return
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var fact_index := 0
	for fact_value: Variant in fact_values:
		if not fact_value is Dictionary:
			continue
		var definition := fact_value as Dictionary
		var fact_type := str(definition.get("fact_type", ""))
		if fact_type == "":
			continue
		fact_index += 1
		var fact := definition.duplicate(true)
		fact["fact_id"] = "%s:%d:%d" % [
			str(definition.get("fact_id_prefix", fact_type)),
			event_id,
			fact_index,
		]
		fact["source_id"] = str(definition.get("source_id", actor_id))
		fact["target_id"] = str(
			definition.get(
				"target_id",
				challenge_id
			)
		)
		fact["challenge_id"] = challenge_id
		fact["location_id"] = str(snapshot.location.get("id", ""))
		fact["cause_fact_ids"] = cause_fact_ids.duplicate()
		if not time_summary.is_empty():
			fact["day"] = int(time_summary.get("day", 1))
			fact["hour"] = int(time_summary.get("hour", 0))
		fact["visibility"] = str(definition.get("visibility", "known"))
		fact["source_action"] = source_action
		fact.erase("fact_id_prefix")
		result.add_fact(fact)


func _apply_success(
		result: Variant,
		challenge: Dictionary,
		snapshot: Variant,
		event_id: int,
		time_summary: Dictionary
) -> void:
	var success: Dictionary = challenge.get("success", {})
	var visible_entity_id := str(success.get("visible_entity_id", ""))
	if visible_entity_id != "":
		result.add_state_change({
			"entity_id": visible_entity_id,
			"key": "visible",
			"to": true,
		})

	var item: Dictionary = (success.get("item", {}) as Dictionary).duplicate(true)
	var item_id := str(item.get("item_id", item.get("id", "")))
	if item_id != "":
		_apply_success_item(
			result,
			challenge,
			snapshot,
			time_summary,
			event_id,
			item,
			item_id
		)
	_apply_additional_success_facts(
		result,
		challenge,
		snapshot,
		event_id,
		time_summary,
		item_id
	)


func _apply_success_item(
		result: Variant,
		challenge: Dictionary,
		snapshot: Variant,
		time_summary: Dictionary,
		event_id: int,
		item: Dictionary,
		item_id: String
) -> void:
	var actor_id := str(snapshot.get_player_value("id", "player"))
	item["item_id"] = item_id
	item["owner_id"] = actor_id
	var provenance: Dictionary = (
		item.get("provenance", {}) as Dictionary
	).duplicate(true)
	provenance["discovered_at"] = str(snapshot.location.get("id", ""))
	provenance["source_challenge_id"] = str(challenge.get("challenge_id", ""))
	provenance["discovered_day"] = int(time_summary.get("day", 1))
	provenance["discovered_hour"] = int(time_summary.get("hour", 0))
	item["provenance"] = provenance
	result.add_item_change({
		"operation": "create",
		"item": item,
	})

	var inventory_item_ids: Array = (
		snapshot.get_player_value("inventory_item_ids", []) as Array
	).duplicate(true)
	if item_id not in inventory_item_ids:
		inventory_item_ids.append(item_id)
	result.add_state_change({
		"entity_id": actor_id,
		"key": "inventory_item_ids",
		"to": inventory_item_ids,
	})
	result.add_fact({
		"fact_id": "actor_discovered_item:%d" % event_id,
		"fact_type": "actor_discovered_item",
		"source_id": actor_id,
		"target_id": item_id,
		"target_display_name": str(item.get("display_name", "发现物")),
		"challenge_id": str(challenge.get("challenge_id", "")),
		"location_id": str(snapshot.location.get("id", "")),
		"visibility": "known",
		"source_action": "challenge_check",
	})


func _apply_additional_success_facts(
		result: Variant,
		challenge: Dictionary,
		snapshot: Variant,
		event_id: int,
		time_summary: Dictionary,
		item_id: String
) -> void:
	var success: Dictionary = challenge.get("success", {})
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var challenge_id := str(challenge.get("challenge_id", ""))
	var cause_fact_ids: Array[String] = [
		"actor_attempted_challenge:%d" % event_id,
	]
	if item_id != "":
		cause_fact_ids.append("actor_discovered_item:%d" % event_id)
	var fact_index := 0
	for fact_value: Variant in success.get("additional_facts", []):
		if not fact_value is Dictionary:
			continue
		fact_index += 1
		var definition := fact_value as Dictionary
		var fact_type := str(definition.get("fact_type", ""))
		if fact_type == "":
			continue
		var fact := definition.duplicate(true)
		fact["fact_id"] = "%s:%d:%d" % [
			str(definition.get("fact_id_prefix", fact_type)),
			event_id,
			fact_index,
		]
		fact["source_id"] = str(
			definition.get("source_id", actor_id)
		)
		fact["target_id"] = str(
			definition.get("target_id", item_id)
		)
		fact["challenge_id"] = challenge_id
		fact["location_id"] = str(snapshot.location.get("id", ""))
		fact["cause_fact_ids"] = cause_fact_ids.duplicate()
		fact["day"] = int(time_summary.get("day", 1))
		fact["hour"] = int(time_summary.get("hour", 0))
		fact["visibility"] = str(
			definition.get("visibility", "known")
		)
		fact["source_action"] = "challenge_check"
		fact.erase("fact_id_prefix")
		result.add_fact(fact)


func _apply_failure(
		result: Variant,
		challenge: Dictionary,
		snapshot: Variant,
		event_id: int
) -> void:
	var failure: Dictionary = challenge.get("failure", {})
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var health_before := int(snapshot.get_player_value("health", 100))
	var health_loss := maxi(int(failure.get("health_loss", 0)), 0)
	var health_after := maxi(health_before - health_loss, 1)
	var injury_key := str(failure.get("injury_key", "injury"))
	var injury_value := str(failure.get("injury_value", "minor_injury"))
	result.add_state_change({
		"entity_id": actor_id,
		"key": "health",
		"to": health_after,
	})
	result.add_state_change({
		"entity_id": actor_id,
		"key": injury_key,
		"to": injury_value,
	})
	result.add_fact({
		"fact_id": "actor_injured_during_challenge:%d" % event_id,
		"fact_type": "actor_injured_during_challenge",
		"source_id": actor_id,
		"target_id": str(challenge.get("target_entity_id", "")),
		"challenge_id": str(challenge.get("challenge_id", "")),
		"location_id": str(snapshot.location.get("id", "")),
		"health_loss": health_before - health_after,
		"injury": injury_value,
		"visibility": "known",
		"source_action": "challenge_check",
	})
