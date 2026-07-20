extends RefCounted
class_name V5TravelResolver

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


func resolve(
		route: Dictionary,
		snapshot: Variant,
		journey_id: int
) -> Variant:
	var result = TransactionResultModel.new()
	var route_id := str(route.get("route_id", ""))
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var from_location_id := str(
		route.get("from_location_id", snapshot.location.get("id", ""))
	)
	var to_location_id := str(route.get("to_location_id", ""))
	var food_cost := int(route.get("food_cost", 0))
	var hours := int(route.get("hours", 0))

	result.add_fact({
		"fact_id": "actor_traveled_route:%d" % journey_id,
		"fact_type": "actor_traveled_route",
		"source_id": actor_id,
		"target_id": to_location_id,
		"route_id": route_id,
		"from_location_id": from_location_id,
		"to_location_id": to_location_id,
		"hours": hours,
		"food_cost": food_cost,
		"visibility": "known",
		"source_action": "travel",
	})
	if food_cost > 0:
		result.add_state_change({
			"entity_id": actor_id,
			"key": "food_count",
			"delta": -food_cost,
		})
	result.set_narrative_result({
		"title": str(route.get("narrative_title", "旅途")),
		"summary": str(route.get("narrative", "你抵达了新的地点。")),
		"route_id": route_id,
		"from_location_id": from_location_id,
		"to_location_id": to_location_id,
	})
	result.mark_resolved("travel")
	return result
