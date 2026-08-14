extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_resident_hamlet_fixture.json"
)
const TEST_SEEDS := [62001, 62002, 62003, 62004, 62005]
const SIMULATION_HOURS := 120
const REQUIRED_PRODUCT_DEFS := [
	"item.fresh_fish_portion",
	"item.root_vegetable_portion",
	"item.woven_reed_mat",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var summaries: Array = []
	var total_workers := 0
	var total_stalled_workers := 0
	var total_isolated_residents := 0
	var total_invalid_references := 0
	var total_shared_meals := 0
	var total_unmet_food_facts := 0

	for seed: int in TEST_SEEDS:
		var session = SimSessionModel.new()
		var start: Dictionary = session.start_from_fixture_path(
			FIXTURE_PATH,
			[],
			{"challenge_seed_override": seed}
		)
		_check(
			bool(start.get("success", false)),
			"seed %d 可以启动生成居民世界" % seed
		)
		if not bool(start.get("success", false)):
			continue

		var report: Dictionary = start.get("resident_generation", {})
		var resident_ids: Array = report.get("resident_ids", [])
		var workers := _worker_ids(session, resident_ids)
		var isolated_before := _isolated_resident_count(session, resident_ids)
		var sourceful_before := _sourceful_social_report(session, resident_ids)
		var relation_before: Dictionary = session.stores[
			"relationship_store"
		].to_save_data()
		var tick_result: Dictionary = session.advance_time(
			SIMULATION_HOURS,
			"generated_livelihood_network_probe",
			{"scope_type": "global", "scope_id": ""}
		)
		var production_facts: Array = session.stores[
			"fact_store"
		].find_facts_by_type("npc_livelihood_produced")
		var shared_meals: Array = session.stores[
			"fact_store"
		].find_facts_by_type("npc_household_shared_food")
		var self_meals: Array = session.stores[
			"fact_store"
		].find_facts_by_type("npc_self_meal")
		var unmet_food: Array = session.stores[
			"fact_store"
		].find_facts_by_type("npc_household_food_unmet")
		var stalled_workers := _stalled_worker_count(
			session, workers, production_facts
		)
		var reference_report: Dictionary = (
			session.validate_persistent_references()
		)
		var item_report := _livelihood_item_report(session)
		var transaction_report := _livelihood_transaction_report(tick_result)

		_check(
			workers.size() >= 3
			and production_facts.size() > workers.size() * 3
			and _fact_day_count(production_facts) >= 5
			and stalled_workers == 0,
			"seed %d 的每名劳动者跨至少五个日历日完成多轮生产，没有一次性工作停滞" % seed
		)
		_check(
			_required_products_exist(session)
			and bool(item_report.get("ok", false)),
			"seed %d 生成渔获、农产和手工品，物品数量与来源履历合法" % seed
		)
		_check(
			not self_meals.is_empty()
			and not shared_meals.is_empty()
			and _shared_meals_changed_relationships(
				session, shared_meals, relation_before
			),
			"seed %d 的饥饿触发自食和家庭援助，援助真实改变关系" % seed
		)
		_check(
			isolated_before == 0
			and bool(sourceful_before.get("ok", false)),
			"seed %d 的居民均有有来源的同住、监护或受照料关系" % seed
		)
		_check(
			bool(reference_report.get("ok", false))
			and bool(transaction_report.get("ok", false)),
			"seed %d 推进五天后无悬空引用或被拒绝的生计事务" % seed
		)

		total_workers += workers.size()
		total_stalled_workers += stalled_workers
		total_isolated_residents += isolated_before
		if not bool(reference_report.get("ok", false)):
			total_invalid_references += 1
		total_shared_meals += shared_meals.size()
		total_unmet_food_facts += unmet_food.size()
		summaries.append({
			"seed": seed,
			"resident_count": resident_ids.size(),
			"worker_count": workers.size(),
			"production_fact_count": production_facts.size(),
			"self_meal_count": self_meals.size(),
			"shared_meal_count": shared_meals.size(),
			"unmet_food_fact_count": unmet_food.size(),
			"livelihood_item_count": int(item_report.get("item_count", 0)),
			"stalled_worker_count": stalled_workers,
			"isolated_resident_count": isolated_before,
			"reference_ok": bool(reference_report.get("ok", false)),
			"transaction_ok": bool(transaction_report.get("ok", false)),
		})

	var aggregate := {
		"seed_count": TEST_SEEDS.size(),
		"simulation_hours_per_seed": SIMULATION_HOURS,
		"worker_count": total_workers,
		"stalled_worker_count": total_stalled_workers,
		"stagnation_rate": (
			0.0 if total_workers == 0
			else float(total_stalled_workers) / float(total_workers)
		),
		"isolated_resident_count": total_isolated_residents,
		"invalid_reference_seed_count": total_invalid_references,
		"shared_meal_count": total_shared_meals,
		"unmet_food_fact_count": total_unmet_food_facts,
		"seeds": summaries,
	}
	_check(
		total_workers > 0
		and total_stalled_workers == 0
		and total_isolated_residents == 0
		and total_invalid_references == 0
		and total_shared_meals > 0,
		"五种子批量验收的停滞率、孤立人口和悬空引用均为零"
	)
	print("[V5 GENERATED LIVELIHOOD BATCH] %s" % JSON.stringify(aggregate))
	_finish()


func _worker_ids(session: Variant, resident_ids: Array) -> Array:
	var rows: Array = []
	for resident_id: String in resident_ids:
		var entity: Dictionary = session.stores["entity_store"].get_entity(
			resident_id
		)
		if "generated_worker" in (entity.get("tags", []) as Array):
			rows.append(resident_id)
	return rows


func _fact_day_count(facts: Array) -> int:
	var days: Dictionary = {}
	for fact: Dictionary in facts:
		days[int(fact.get("day", 0))] = true
	days.erase(0)
	return days.size()


func _stalled_worker_count(
		session: Variant,
		workers: Array,
		production_facts: Array
) -> int:
	var fact_counts: Dictionary = {}
	for fact: Dictionary in production_facts:
		var actor_id := str(fact.get("actor_id", ""))
		fact_counts[actor_id] = int(fact_counts.get(actor_id, 0)) + 1
	var count := 0
	for worker_id: String in workers:
		if (
			int(fact_counts.get(worker_id, 0)) < 2
			or int(session.stores["state_store"].get_state(
				worker_id, "livelihood_cycle_count", 0
			)) < 2
		):
			count += 1
	return count


func _sourceful_social_report(
		session: Variant,
		resident_ids: Array
) -> Dictionary:
	var linked: Dictionary = {}
	var kinds: Dictionary = {}
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"generated_social_relation"
	):
		var actor_id := str(fact.get("actor_id", ""))
		var target_id := str(fact.get("target_id", ""))
		var kind := str(fact.get("relationship_kind", ""))
		if (
			actor_id in resident_ids
			and target_id in resident_ids
			and kind in ["co_resident", "guardian", "dependent"]
			and not (fact.get("source_fact_ids", []) as Array).is_empty()
		):
			linked[actor_id] = true
			kinds[kind] = true
	return {
		"ok": linked.size() == resident_ids.size()
		and kinds.has("co_resident"),
		"linked_count": linked.size(),
		"kinds": kinds.keys(),
	}


func _isolated_resident_count(session: Variant, resident_ids: Array) -> int:
	var count := 0
	for resident_id: String in resident_ids:
		if session.stores["relationship_store"].list_relations_for(
			resident_id
		).is_empty():
			count += 1
	return count


func _required_products_exist(session: Variant) -> bool:
	var definitions: Dictionary = {}
	for item: Dictionary in session.stores["item_store"].list_items():
		definitions[str(item.get("item_def_id", ""))] = true
	for item_def_id: String in REQUIRED_PRODUCT_DEFS:
		if not definitions.has(item_def_id):
			return false
	return true


func _livelihood_item_report(session: Variant) -> Dictionary:
	var errors: Array = []
	var count := 0
	for item: Dictionary in session.stores["item_store"].list_items():
		if "livelihood_product" not in (item.get("tags", []) as Array):
			continue
		count += 1
		var quantity := int(item.get("quantity", 0))
		var holder_kind := str((item.get("holder", {}) as Dictionary).get(
			"kind", ""
		))
		if holder_kind != "destroyed" and (
			quantity < 1 or quantity > int(item.get("max_stack", 1))
		):
			errors.append("invalid_quantity:%s" % str(item.get(
				"item_instance_id", ""
			)))
		var provenance: Dictionary = item.get("provenance", {})
		var created_by := str(provenance.get("created_by_fact_id", ""))
		if created_by == "" or session.stores["fact_store"].get_fact(
			created_by
		).is_empty():
			errors.append("missing_provenance:%s" % str(item.get(
				"item_instance_id", ""
			)))
		for history: Dictionary in item.get("history", []):
			var fact_id := str(history.get("fact_id", ""))
			if fact_id == "" or session.stores["fact_store"].get_fact(
				fact_id
			).is_empty():
				errors.append("missing_history_fact:%s" % fact_id)
	return {"ok": errors.is_empty(), "errors": errors, "item_count": count}


func _shared_meals_changed_relationships(
		session: Variant,
		shared_meals: Array,
		before: Dictionary
) -> bool:
	for fact: Dictionary in shared_meals:
		var donor_id := str(fact.get("actor_id", ""))
		var recipient_id := str(fact.get("target_id", ""))
		var old_targets: Dictionary = before.get(recipient_id, {})
		var old_axes: Dictionary = old_targets.get(donor_id, {})
		var old_gratitude := int(old_axes.get("gratitude", 0))
		var new_gratitude := int(session.stores[
			"relationship_store"
		].get_relation(recipient_id, donor_id, "gratitude", 0))
		if new_gratitude > old_gratitude:
			return true
	return false


func _livelihood_transaction_report(tick_result: Dictionary) -> Dictionary:
	var errors: Array = []
	for result: Dictionary in tick_result.get("livelihood_results", []):
		if str(result.get("contract_status", "")) != "resolved":
			errors.append(str(result.get("error_reason", "unknown_error")))
	return {"ok": errors.is_empty(), "errors": errors}


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GENERATED LIVELIHOOD NETWORK RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 GENERATED LIVELIHOOD NETWORK FAIL] " + failure)
		print(
			"[V5 GENERATED LIVELIHOOD NETWORK RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GENERATED LIVELIHOOD NETWORK PASS] " + label)
	else:
		failures.append(label)
