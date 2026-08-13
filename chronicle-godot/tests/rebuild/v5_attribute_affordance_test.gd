extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const WISDOM_ACTION := (
	"read_visible_readable_object:north_quay_visiting_rules"
)
const CHARISMA_ACTION := (
	"request_favor_from_indebted_person:chen_mi"
)
const FOOD_ACTION := "give_food_to_hungry_person:chen_mi"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. Attribute affordance surface loads")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var session: Variant = viewer.view_model.session
	var state_store: Variant = session.stores["state_store"]
	var relationship_store: Variant = session.stores["relationship_store"]
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer
	var action_heading := viewer.get_node("%ActionHeading") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel

	var food_fact_store: Variant = session.stores["fact_store"]
	food_fact_store.add_fact({
		"fact_id": "fact.test.attribute_affordance.consume_rations",
		"fact_type": "test_consumed_rations",
		"actor_id": "player",
		"tick": 1,
	})
	session.stores["item_store"].apply_item_change({
		"operation": "consume",
		"item_instance_id": "item_instance.lake_town.player_travel_rations",
		"quantity": 3,
		"source_fact_ids": [
			"fact.test.attribute_affordance.consume_rations"
		],
	})
	viewer.refresh_view()
	var food_button := _find_action_button(action_buttons, FOOD_ACTION)
	_check(
		food_button != null
		and food_button.disabled
		and "食物 0/1" in food_button.text
		and "食物不足：需要 1，当前 0" in food_button.tooltip_text
		and "受限 1 项" in action_heading.text,
		"2. Generic player minimum remains visible with a concrete reason"
	)

	state_store.set_state("player", "wisdom", 8)
	session.context.set_current_location("north_quay_record_house")
	viewer.refresh_view()
	var wisdom_button := _find_action_button(action_buttons, WISDOM_ACTION)
	_check(
		wisdom_button != null
		and wisdom_button.disabled
		and "[智慧]" in wisdom_button.text
		and "智慧 8/9" in wisdom_button.text
		and "智慧不足：需要 9，当前 8" in wisdom_button.tooltip_text,
		"3. Low wisdom exposes the blocked recognition action and value gap"
	)

	var action_count_before := int(session.action_count)
	var fact_count_before := int(
		session.get_store_summary().get("facts", 0)
	)
	var blocked_wisdom: Dictionary = session.execute_action(WISDOM_ACTION)
	_check(
		not bool(blocked_wisdom.get("success", true))
		and str(blocked_wisdom.get("error", "")) == "action_blocked"
		and "智慧不足" in str(blocked_wisdom.get("blocked_reason", ""))
		and int(session.action_count) == action_count_before
		and int(session.get_store_summary().get("facts", 0)) == fact_count_before,
		"4. Session rejects a bypass without writing facts or history"
	)

	var blocked_candidate: Variant = _find_candidate(
		session.get_action_candidates(),
		WISDOM_ACTION
	)
	var blocked_transaction: Variant = session.resolver.resolve_action(
		blocked_candidate,
		session.get_snapshot()
	)
	_check(
		str(blocked_transaction.contract_status) == "invalid_contract"
		and str(blocked_transaction.error_reason) == "action_blocked",
		"5. Transaction resolver independently rejects a blocked candidate"
	)

	state_store.set_state("player", "wisdom", 9)
	viewer.refresh_view()
	wisdom_button = _find_action_button(action_buttons, WISDOM_ACTION)
	_check(
		wisdom_button != null and not wisdom_button.disabled,
		"6. Raising wisdom makes the same recognition action executable"
	)
	wisdom_button.pressed.emit()
	await process_frame
	_check(
		"智慧 9，满足行动要求 9" in feedback_body.text
		and _find_action_button(action_buttons, WISDOM_ACTION) == null,
		"7. Successful recognition explains the attribute used and then clears"
	)

	viewer.restart_session()
	await process_frame
	await process_frame
	session = viewer.view_model.session
	state_store = session.stores["state_store"]
	relationship_store = session.stores["relationship_store"]
	state_store.set_state("player", "charisma", 5)
	relationship_store.set_relation("chen_mi", "player", "debt", 10)
	viewer.refresh_view()
	var charisma_button := _find_action_button(action_buttons, CHARISMA_ACTION)
	_check(
		charisma_button != null
		and charisma_button.disabled
		and "[魅力]" in charisma_button.text
		and "魅力 5/6" in charisma_button.text
		and "魅力不足：需要 6，当前 5" in charisma_button.tooltip_text,
		"8. Low charisma exposes the blocked negotiation and value gap"
	)

	var debt_before := int(
		relationship_store.get_relation("chen_mi", "player", "debt", 0)
	)
	var blocked_charisma: Dictionary = session.execute_action(CHARISMA_ACTION)
	_check(
		not bool(blocked_charisma.get("success", true))
		and str(blocked_charisma.get("error", "")) == "action_blocked"
		and int(relationship_store.get_relation(
			"chen_mi", "player", "debt", 0
		)) == debt_before,
		"9. Blocked negotiation cannot spend the relationship resource"
	)

	state_store.set_state("player", "charisma", 6)
	viewer.refresh_view()
	charisma_button = _find_action_button(action_buttons, CHARISMA_ACTION)
	_check(
		charisma_button != null and not charisma_button.disabled,
		"10. Raising charisma unlocks the same negotiation"
	)
	charisma_button.pressed.emit()
	await process_frame
	_check(
		"魅力 6，满足行动要求 6" in feedback_body.text
		and _find_action_button(action_buttons, CHARISMA_ACTION) == null
		and int(relationship_store.get_relation(
			"chen_mi", "player", "debt", 0
		)) < debt_before,
		"11. Successful negotiation reports charisma and consumes the favor"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _find_action_button(container: Node, action_id: String) -> Button:
	for child: Node in container.get_children():
		if (
			child is Button
			and str(child.get_meta("action_id", "")) == action_id
		):
			return child as Button
	return null


func _find_candidate(candidates: Array, action_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.action_id) == action_id:
			return candidate
	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 ATTRIBUTE AFFORDANCE PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 ATTRIBUTE AFFORDANCE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 ATTRIBUTE AFFORDANCE FAIL] " + failure)
	print(
		"[V5 ATTRIBUTE AFFORDANCE RESULT] FAIL (%d)"
		% failures.size()
	)
	quit(1)
