extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_resident_hamlet_fixture.json"
)
const TEST_SEEDS := [62001, 62002, 62003, 62004, 62005]
const SIMULATION_HOURS := 120

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var summaries: Array = []
	var total_neighbor_facts := 0
	var total_workmate_facts := 0
	var total_employment_facts := 0
	var total_cross_household_meals := 0
	var total_failed_requests := 0
	var total_unmet_food := 0
	var total_social_traces := 0
	var total_daily_chronicles := 0
	var total_invalid_reference_seeds := 0
	var total_failed_transactions := 0

	for seed: int in TEST_SEEDS:
		var session = SimSessionModel.new()
		var start: Dictionary = session.start_from_fixture_path(
			FIXTURE_PATH,
			[],
			{"challenge_seed_override": seed}
		)
		_check(
			bool(start.get("success", false)),
			"seed %d 可以启动生成居民社会压力世界" % seed
		)
		if not bool(start.get("success", false)):
			continue

		var generation: Dictionary = start.get("resident_generation", {})
		var household_ids: Array = generation.get("household_ids", [])
		var social_report := _generated_social_report(session, household_ids)
		var relation_before: Dictionary = session.stores[
			"relationship_store"
		].to_save_data()
		var tick_result: Dictionary = session.advance_time(
			SIMULATION_HOURS,
			"generated_social_pressure_probe",
			{"scope_type": "global", "scope_id": ""}
		)
		var cross_meals: Array = session.stores[
			"fact_store"
		].find_facts_by_type("npc_cross_household_shared_food")
		var failed_requests: Array = session.stores[
			"fact_store"
		].find_facts_by_type("npc_cross_household_food_request_failed")
		var unmet_food: Array = session.stores[
			"fact_store"
		].find_facts_by_type("npc_household_food_unmet")
		var social_traces := _social_traces(session)
		var daily_chronicles := _daily_social_chronicles(session)
		var cross_report := _cross_household_meal_report(
			session, cross_meals, relation_before
		)
		var refusal_report := _failed_request_report(
			session, failed_requests, relation_before
		)
		var reference_report: Dictionary = session.validate_persistent_references()
		var transaction_report := _livelihood_transaction_report(tick_result)

		_check(
			bool(social_report.get("neighbor_households_covered", false))
			and int(social_report.get("source_error_count", 0)) == 0,
			"seed %d 的每个家庭都由有来源的邻里事实接入聚落关系网" % seed
		)
		_check(
			cross_meals.size() + failed_requests.size() > 0,
			"seed %d 的家庭缺粮触发了跨家庭援助或求助受挫" % seed
		)
		_check(
			bool(cross_report.get("ok", false)),
			"seed %d 的跨家庭援助消耗真实食物并形成感激、信任或债务" % seed
		)
		_check(
			bool(refusal_report.get("ok", false)),
			"seed %d 的求助受挫具有关系来源并形成轻微怨气" % seed
		)
		_check(
			bool(reference_report.get("ok", false))
			and bool(transaction_report.get("ok", false)),
			"seed %d 推进五天后无悬空引用或失败的社会压力事务" % seed
		)
		_check(
			not social_traces.is_empty()
			and _trace_sources_exist(session, social_traces)
			and daily_chronicles.size() >= 4,
			"seed %d 的跨家庭行为形成有事实来源的痕迹与每日聚落纪事" % seed
		)

		total_neighbor_facts += int(social_report.get("neighbor_fact_count", 0))
		total_workmate_facts += int(social_report.get("workmate_fact_count", 0))
		total_employment_facts += int(social_report.get(
			"employment_fact_count", 0
		))
		total_cross_household_meals += cross_meals.size()
		total_failed_requests += failed_requests.size()
		total_unmet_food += unmet_food.size()
		total_social_traces += social_traces.size()
		total_daily_chronicles += daily_chronicles.size()
		if not bool(reference_report.get("ok", false)):
			total_invalid_reference_seeds += 1
		total_failed_transactions += int(transaction_report.get(
			"error_count", 0
		))
		summaries.append({
			"seed": seed,
			"household_count": household_ids.size(),
			"neighbor_fact_count": int(social_report.get(
				"neighbor_fact_count", 0
			)),
			"workmate_fact_count": int(social_report.get(
				"workmate_fact_count", 0
			)),
			"employment_fact_count": int(social_report.get(
				"employment_fact_count", 0
			)),
			"cross_household_meal_count": cross_meals.size(),
			"failed_request_count": failed_requests.size(),
			"unmet_food_fact_count": unmet_food.size(),
			"social_trace_count": social_traces.size(),
			"daily_chronicle_count": daily_chronicles.size(),
			"reference_ok": bool(reference_report.get("ok", false)),
			"transaction_ok": bool(transaction_report.get("ok", false)),
		})

	_check(
		total_neighbor_facts > 0
		and total_workmate_facts > 0
		and total_employment_facts > 0,
		"五种子合计生成邻里、工友和正式受雇三类有来源关系"
	)
	_check(
		total_cross_household_meals > 0
		and total_failed_requests > 0
		and total_unmet_food > 0,
		"五种子同时出现跨家庭援助、求助受挫和未解除的真实稀缺"
	)
	_check(
		total_invalid_reference_seeds == 0
		and total_failed_transactions == 0,
		"五种子社会压力网络无悬空引用或失败事务"
	)
	_check(
		total_social_traces > 0 and total_daily_chronicles >= 20,
		"五种子社会压力形成可供后续调查与界面投影消费的痕迹和纪事"
	)
	print("[V5 GENERATED SOCIAL PRESSURE BATCH] %s" % JSON.stringify({
		"seed_count": TEST_SEEDS.size(),
		"simulation_hours_per_seed": SIMULATION_HOURS,
		"neighbor_fact_count": total_neighbor_facts,
		"workmate_fact_count": total_workmate_facts,
		"employment_fact_count": total_employment_facts,
		"cross_household_meal_count": total_cross_household_meals,
		"failed_request_count": total_failed_requests,
		"unmet_food_fact_count": total_unmet_food,
		"social_trace_count": total_social_traces,
		"daily_chronicle_count": total_daily_chronicles,
		"invalid_reference_seed_count": total_invalid_reference_seeds,
		"failed_transaction_count": total_failed_transactions,
		"seeds": summaries,
	}))
	_finish()


func _generated_social_report(
		session: Variant,
		household_ids: Array
) -> Dictionary:
	var covered_households: Dictionary = {}
	var counts := {
		"settlement_neighbor": 0,
		"workmate": 0,
		"employee_of": 0,
		"employer_of": 0,
	}
	var source_errors := 0
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"generated_social_relation"
	):
		var kind := str(fact.get("relationship_kind", ""))
		if counts.has(kind):
			counts[kind] = int(counts.get(kind, 0)) + 1
		if kind == "settlement_neighbor":
			covered_households[str(fact.get("source_household_id", ""))] = true
			covered_households[str(fact.get("target_household_id", ""))] = true
		if kind in counts.keys() and not _fact_sources_exist(session, fact):
			source_errors += 1
	covered_households.erase("")
	return {
		"neighbor_households_covered": (
			covered_households.size() == household_ids.size()
		),
		"neighbor_fact_count": int(counts.get("settlement_neighbor", 0)),
		"workmate_fact_count": int(counts.get("workmate", 0)),
		"employment_fact_count": (
			int(counts.get("employee_of", 0))
			+ int(counts.get("employer_of", 0))
		),
		"source_error_count": source_errors,
	}


func _cross_household_meal_report(
		session: Variant,
		facts: Array,
		before: Dictionary
) -> Dictionary:
	var errors: Array = []
	for fact: Dictionary in facts:
		var donor_id := str(fact.get("actor_id", ""))
		var requester_id := str(fact.get("requester_id", ""))
		var relationship_fact_id := str(fact.get("relationship_fact_id", ""))
		if (
			str(fact.get("household_id", "")) == ""
			or str(fact.get("provider_household_id", "")) == ""
			or str(fact.get("household_id", ""))
			== str(fact.get("provider_household_id", ""))
			or relationship_fact_id == ""
			or session.stores["fact_store"].get_fact(
				relationship_fact_id
			).is_empty()
		):
			errors.append("invalid_cross_household_source:%s" % str(fact.get(
				"fact_id", ""
			)))
			continue
		var old_axes: Dictionary = (before.get(
			requester_id, {}
		) as Dictionary).get(donor_id, {})
		var old_debt := int(old_axes.get("debt", 0))
		var new_debt := int(session.stores["relationship_store"].get_relation(
			requester_id, donor_id, "debt", 0
		))
		if new_debt <= old_debt:
			errors.append("debt_not_changed:%s" % str(fact.get("fact_id", "")))
	return {"ok": errors.is_empty(), "errors": errors}


func _failed_request_report(
		session: Variant,
		facts: Array,
		before: Dictionary
) -> Dictionary:
	var errors: Array = []
	for fact: Dictionary in facts:
		var source_id := str(fact.get("actor_id", ""))
		var target_id := str(fact.get("target_id", ""))
		var relationship_fact_id := str(fact.get("relationship_fact_id", ""))
		if (
			relationship_fact_id == ""
			or session.stores["fact_store"].get_fact(
				relationship_fact_id
			).is_empty()
		):
			errors.append("invalid_failed_request_source:%s" % str(fact.get(
				"fact_id", ""
			)))
			continue
		var old_axes: Dictionary = (before.get(
			source_id, {}
		) as Dictionary).get(target_id, {})
		var old_resentment := int(old_axes.get("resentment", 0))
		var new_resentment := int(session.stores[
			"relationship_store"
		].get_relation(source_id, target_id, "resentment", 0))
		if new_resentment <= old_resentment:
			errors.append("resentment_not_changed:%s" % str(fact.get(
				"fact_id", ""
			)))
	return {"ok": errors.is_empty(), "errors": errors}


func _fact_sources_exist(session: Variant, fact: Dictionary) -> bool:
	var source_ids: Array = fact.get("source_fact_ids", [])
	if source_ids.is_empty():
		return false
	for source_value: Variant in source_ids:
		if session.stores["fact_store"].get_fact(str(source_value)).is_empty():
			return false
	return true


func _social_traces(session: Variant) -> Array:
	var rows: Array = []
	for trace: Dictionary in session.stores["trace_store"].list_traces():
		if str(trace.get("trace_type", "")) in [
			"shared_food_container", "unanswered_food_request"
		]:
			rows.append(trace)
	return rows


func _daily_social_chronicles(session: Variant) -> Array:
	var rows: Array = []
	for entry: Dictionary in session.stores["chronicle_store"].list_entries():
		if str(entry.get("entry_type", "")) == "settlement_daily_life":
			rows.append(entry)
	return rows


func _trace_sources_exist(session: Variant, traces: Array) -> bool:
	for trace: Dictionary in traces:
		var fact_id := str(trace.get("source_fact_id", ""))
		if (
			fact_id == ""
			or session.stores["fact_store"].get_fact(fact_id).is_empty()
		):
			return false
	return true


func _livelihood_transaction_report(tick_result: Dictionary) -> Dictionary:
	var errors: Array = []
	for result: Dictionary in tick_result.get("livelihood_results", []):
		if str(result.get("contract_status", "")) != "resolved":
			errors.append(str(result.get("error_reason", "unknown_error")))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"error_count": errors.size(),
	}


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GENERATED SOCIAL PRESSURE RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 GENERATED SOCIAL PRESSURE FAIL] " + failure)
		print(
			"[V5 GENERATED SOCIAL PRESSURE RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GENERATED SOCIAL PRESSURE PASS] " + label)
	else:
		failures.append(label)
