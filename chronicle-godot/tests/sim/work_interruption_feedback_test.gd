extends "res://tests/sim/world_content_contract_test.gd"


func _run() -> void:
	var live := Live.new()
	var options := OPTIONS.duplicate(true)
	options.merge({"challenge_seed_override": 86021, "content_extension_version": 2, "body_rules_version": 1}, true)
	_check(live.start(options).success, "natural interrupted-work world starts")
	_check(live.perform_travel("generated_route.echo_landing.commons_to_fishery").success, "walk to actual workplace")
	_check(live.act_player_life("gather:net_fisher").success, "gather own food")
	_check(live.act_player_life("ask_local:generated_resident.echo_landing.001").success, "learn from present employer")
	var result: Dictionary = live.act_player_life("help:generated_resident.echo_landing.001:net_fisher")
	_check(result.success and not result.work_completed, "accepted operation is distinct from completed work")
	_check(result.hours == 3 and result.work_progress_hours == 2, "elapsed time differs from completed work progress")
	var feedback: Dictionary = live.build_view_data().feedback
	_check(feedback.status == "interrupted" and feedback.title == "作业中断", "UI does not label interruption as success")
	_check("陶苇已离开现场" in feedback.body and "或" not in feedback.body, "public receipt names actual local cause, not a list of guesses")
	_check("2/4" in feedback.body and "未领工资" in feedback.body, "receipt states progress and real payment")
	_check("同一雇主在场且能付款" in str(feedback.details), "full receipt gives conditional continuation, not guaranteed work")
	_check(live.build_view_data().player.coins == 0 and live.build_view_data().player.food_count == 6, "no fabricated payment or output")
	_check(live.save_to_path("user://tests/work_interruption/interrupted.ui.json", true).success, "actual interrupted UI checkpoint retained")
	_check(live.act_player_life("incident:food_at_hand:share").success, "actual alternative remains available")
	_check(live.session.save_to_path("user://tests/work_interruption/after_share.json").ok, "natural replay native checkpoint")
	_check(not live.session.stores.fact_store.list_facts().any(func(f: Dictionary) -> bool: return f.get("fact_type") == "test_injection"), "natural route contains no injection")
	_finish()
