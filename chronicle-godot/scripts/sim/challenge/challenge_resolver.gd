extends RefCounted
class_name V5ChallengeResolver

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


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

	if succeeded:
		_apply_success(
			result,
			challenge,
			snapshot,
			event_id,
			time_summary
		)
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


func _apply_success(
		result: Variant,
		challenge: Dictionary,
		snapshot: Variant,
		event_id: int,
		time_summary: Dictionary
) -> void:
	var success: Dictionary = challenge.get("success", {})
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var visible_entity_id := str(success.get("visible_entity_id", ""))
	if visible_entity_id != "":
		result.add_state_change({
			"entity_id": visible_entity_id,
			"key": "visible",
			"to": true,
		})

	var item: Dictionary = (success.get("item", {}) as Dictionary).duplicate(true)
	var item_id := str(item.get("item_id", item.get("id", "")))
	if item_id == "":
		return
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
