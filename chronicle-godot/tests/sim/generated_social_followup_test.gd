extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_resident_hamlet_fixture.json"
)
const TEST_SEEDS := [62001, 62002, 62003, 62004, 62005]
const SIMULATION_HOURS := 168

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var summaries: Array = []
	var total_kinship_facts := 0
	var total_mentorship_facts := 0
	var total_repayments := 0
	var total_conflicts := 0
	var total_repayment_exchanges := 0
	var total_relief_pressure := 0
	var invalid_reference_seeds := 0
	var failed_followup_transactions := 0

	for seed: int in TEST_SEEDS:
		var session = SimSessionModel.new()
		var start: Dictionary = session.start_from_fixture_path(
			FIXTURE_PATH,
			[],
			{"challenge_seed_override": seed}
		)
		_check(
			bool(start.get("success", false)),
			"seed %d 可以启动二阶社会演化世界" % seed
		)
		if not bool(start.get("success", false)):
			continue

		var source_report := _relationship_source_report(session)
		var tick_result: Dictionary = session.advance_time(
			SIMULATION_HOURS,
			"generated_social_followup_probe",
			{"scope_type": "global", "scope_id": ""}
		)
		var repayments: Array = session.stores[
			"fact_store"
		].find_facts_by_type("npc_food_debt_repaid")
		var conflicts: Array = session.stores[
			"fact_store"
		].find_facts_by_type("npc_food_request_conflict")
		var repayment_exchanges := _repayment_exchanges(session)
		var settlement_id := str((start.get(
			"resident_generation", {}
		) as Dictionary).get("settlement_id", ""))
		if settlement_id == "":
			settlement_id = "reedbank_hamlet"
		var relief_pressure := int(session.stores[
			"pressure_store"
		].get_pressure_value(settlement_id, "food_relief_demand"))
		var followup_report := _followup_transaction_report(tick_result)
		var repayment_report := _repayment_report(
			session, repayments, repayment_exchanges
		)
		var conflict_report := _conflict_report(session, conflicts)
		var reference_report: Dictionary = session.validate_persistent_references()

		_check(
			int(source_report.get("kinship_fact_count", 0)) > 0
			and int(source_report.get("source_error_count", 0)) == 0,
			"seed %d 生成有家庭来源的伴侣、亲子或手足事实" % seed
		)
		_check(
			bool(repayment_report.get("ok", false)),
			"seed %d 的实物偿债可追溯到食物援助、物品履历和已结算交换" % seed
		)
		_check(
			bool(conflict_report.get("ok", false)),
			"seed %d 的重复拒绝争执可追溯并改变关系与聚落压力" % seed
		)
		_check(
			bool(followup_report.get("ok", false))
			and bool(reference_report.get("ok", false)),
			"seed %d 的二阶社会事务全部提交且无悬空引用" % seed
		)

		total_kinship_facts += int(source_report.get("kinship_fact_count", 0))
		total_mentorship_facts += int(source_report.get(
			"mentorship_fact_count", 0
		))
		total_repayments += repayments.size()
		total_conflicts += conflicts.size()
		total_repayment_exchanges += repayment_exchanges.size()
		total_relief_pressure += relief_pressure
		failed_followup_transactions += int(followup_report.get("error_count", 0))
		if not bool(reference_report.get("ok", false)):
			invalid_reference_seeds += 1
		summaries.append({
			"seed": seed,
			"kinship_fact_count": int(source_report.get(
				"kinship_fact_count", 0
			)),
			"mentorship_fact_count": int(source_report.get(
				"mentorship_fact_count", 0
			)),
			"repayment_fact_count": repayments.size(),
			"conflict_fact_count": conflicts.size(),
			"repayment_exchange_count": repayment_exchanges.size(),
			"food_relief_demand": relief_pressure,
			"reference_ok": bool(reference_report.get("ok", false)),
			"transaction_ok": bool(followup_report.get("ok", false)),
		})

	_check(
		total_kinship_facts > 0 and total_mentorship_facts > 0,
		"五种子合计生成亲缘与师徒两类有来源关系"
	)
	_check(
		total_repayments > 0
		and total_repayments == total_repayment_exchanges,
		"五种子形成真实实物偿还，且每次偿还对应一个已结算交换"
	)
	_check(
		total_conflicts > 0 and total_relief_pressure > 0,
		"五种子中的重复拒绝会升级为争执并积累组织救济需求"
	)
	_check(
		invalid_reference_seeds == 0 and failed_followup_transactions == 0,
		"五种子二阶社会演化无悬空引用或失败事务"
	)
	print("[V5 GENERATED SOCIAL FOLLOWUP BATCH] %s" % JSON.stringify({
		"seed_count": TEST_SEEDS.size(),
		"simulation_hours_per_seed": SIMULATION_HOURS,
		"kinship_fact_count": total_kinship_facts,
		"mentorship_fact_count": total_mentorship_facts,
		"repayment_fact_count": total_repayments,
		"conflict_fact_count": total_conflicts,
		"repayment_exchange_count": total_repayment_exchanges,
		"food_relief_demand": total_relief_pressure,
		"invalid_reference_seed_count": invalid_reference_seeds,
		"failed_followup_transaction_count": failed_followup_transactions,
		"seeds": summaries,
	}))
	_finish()


func _relationship_source_report(session: Variant) -> Dictionary:
	var kinship_count := 0
	var mentorship_count := 0
	var source_errors := 0
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"generated_social_relation"
	):
		var kind := str(fact.get("relationship_kind", ""))
		if kind in ["partner", "parent_of", "child_of", "sibling"]:
			kinship_count += 1
		elif kind in ["mentor_of", "apprentice_of"]:
			mentorship_count += 1
		else:
			continue
		for source_value: Variant in fact.get("source_fact_ids", []):
			if session.stores["fact_store"].get_fact(str(source_value)).is_empty():
				source_errors += 1
	return {
		"kinship_fact_count": kinship_count,
		"mentorship_fact_count": mentorship_count,
		"source_error_count": source_errors,
	}


func _repayment_exchanges(session: Variant) -> Array:
	var rows: Array = []
	for exchange: Dictionary in session.stores["exchange_store"].list_exchanges():
		if str(exchange.get("exchange_type", "")) == (
			"in_kind_food_debt_repayment"
		):
			rows.append(exchange)
	return rows


func _repayment_report(
		session: Variant,
		facts: Array,
		exchanges: Array
) -> Dictionary:
	var errors: Array = []
	var exchange_ids: Dictionary = {}
	for exchange: Dictionary in exchanges:
		exchange_ids[str(exchange.get("exchange_id", ""))] = exchange
	for fact: Dictionary in facts:
		var fact_id := str(fact.get("fact_id", ""))
		var exchange_id := str(fact.get("exchange_id", ""))
		if not exchange_ids.has(exchange_id) or str((
			exchange_ids[exchange_id] as Dictionary
		).get("status", "")) != "settled":
			errors.append("missing_settled_exchange:%s" % fact_id)
		if not _all_fact_sources_exist(session, fact):
			errors.append("missing_repayment_source:%s" % fact_id)
		if not _item_history_contains_fact(session, fact_id):
			errors.append("missing_repayment_item_history:%s" % fact_id)
	return {"ok": errors.is_empty(), "errors": errors}


func _conflict_report(session: Variant, facts: Array) -> Dictionary:
	var errors: Array = []
	var conflict_fact_ids: Dictionary = {}
	var untraced_sites: Dictionary = {}
	for fact: Dictionary in facts:
		var fact_id := str(fact.get("fact_id", ""))
		var actor_id := str(fact.get("actor_id", ""))
		var target_id := str(fact.get("target_id", ""))
		var has_same_day_failure := false
		for source_fact_id: Variant in fact.get("source_fact_ids", []):
			var source_fact: Dictionary = session.stores["fact_store"].get_fact(
				str(source_fact_id)
			)
			if (
				str(source_fact.get("fact_type", ""))
				== "npc_cross_household_food_request_failed"
				and int(source_fact.get("day", -1)) == int(fact.get("day", -2))
			):
				has_same_day_failure = true
				break
		conflict_fact_ids[fact_id] = true
		untraced_sites["%s@%s" % [
			actor_id,
			str(session.stores["state_store"].get_state(
				actor_id, "home_location_id", ""
			)),
		]] = true
		if (
			not _all_fact_sources_exist(session, fact)
			or not has_same_day_failure
			or int(fact.get("resentment_before", 0)) < 3
			or int(session.stores["relationship_store"].get_relation(
				actor_id, target_id, "resentment", 0
			)) <= 0
			or int(session.stores["relationship_store"].get_relation(
				target_id, actor_id, "fear", 0
			)) <= 0
		):
			errors.append("invalid_conflict_consequence:%s" % fact_id)
	for trace: Dictionary in session.stores["trace_store"].find_traces_by_type(
		"food_request_argument"
	):
		var source_fact_id := str(trace.get("source_fact_id", ""))
		if not conflict_fact_ids.has(source_fact_id):
			errors.append("unknown_conflict_trace_source:%s" % source_fact_id)
			continue
		untraced_sites.erase("%s@%s" % [
			str(trace.get("actor_id", "")),
			str(trace.get("location_id", "")),
		])
	for site_key: Variant in untraced_sites.keys():
		errors.append("missing_current_conflict_trace:%s" % str(site_key))
	return {"ok": errors.is_empty(), "errors": errors}


func _all_fact_sources_exist(session: Variant, fact: Dictionary) -> bool:
	var source_ids: Array = fact.get("source_fact_ids", [])
	if source_ids.is_empty():
		return false
	for source_value: Variant in source_ids:
		if session.stores["fact_store"].get_fact(str(source_value)).is_empty():
			return false
	return true


func _item_history_contains_fact(session: Variant, fact_id: String) -> bool:
	for item: Dictionary in session.stores["item_store"].list_items():
		for history: Dictionary in item.get("history", []):
			if str(history.get("fact_id", "")) == fact_id:
				return true
	return false


func _followup_transaction_report(tick_result: Dictionary) -> Dictionary:
	var errors: Array = []
	for result: Dictionary in tick_result.get("social_followup_results", []):
		if str(result.get("contract_status", "")) != "resolved":
			errors.append(str(result.get("error_reason", "unknown_error")))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"error_count": errors.size(),
	}


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GENERATED SOCIAL FOLLOWUP RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 GENERATED SOCIAL FOLLOWUP FAIL] " + failure)
		print(
			"[V5 GENERATED SOCIAL FOLLOWUP RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GENERATED SOCIAL FOLLOWUP PASS] " + label)
	else:
		failures.append(label)
