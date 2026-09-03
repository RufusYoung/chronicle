extends SceneTree

const Session = preload("res://scripts/sim/core/sim_session.gd")
const Transaction = preload("res://scripts/sim/transaction/transaction_result.gd")
const Access = preload("res://scripts/sim/resource/resource_access.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")
const Lifecycle = preload("res://scripts/sim/organization/organization_lifecycle_system.gd")
const Response = preload("res://scripts/sim/organization/organization_response_system.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Work = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const FIXTURE := "res://data/sim/fixtures/generated_settlement_network_fixture.json"
const RULES := ["res://data/sim/raw/action_rules/basic_action_rules.json", "res://data/sim/raw/action_rules/domain_action_rules.json"]
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = Session.new()
	var started: Dictionary = session.start_from_fixture_path(FIXTURE, RULES)
	_check(bool(started.get("success", false)), "new economic world starts: " + JSON.stringify(started.get("error_reason", "")))
	if not session.is_ready():
		print(JSON.stringify(started))
		_finish()
		return
	_check(session.validate_persistent_references().get("ok", false), "initial ownership and funding references are valid")
	var initial := _currency(session)
	var advanced: Dictionary = session.advance_time(24, "economic_contract_autonomous")
	_check(advanced.get("success", false), "one full day advances")
	_check(_currency(session) == initial, "a day of wages cannot mint currency")
	_check(_facts(session, "npc_wage_paid").size() > 0, "service workers receive actual treasury payments")
	_check(session.validate_persistent_references().get("ok", false), "post-tick ownership references are valid")
	print("[ECONOMIC AUTHORITY SAMPLE] ", JSON.stringify({"initial_currency": initial, "current_currency": _currency(session), "paid_wages": _facts(session, "npc_wage_paid").size()}))
	_test_authority()
	_test_response_denial()
	_test_payments()
	_test_work_boundaries()
	_test_retirement()
	_test_save_and_legacy(session)
	_finish()


func _start() -> Variant:
	var session = Session.new()
	var report: Dictionary = session.start_from_fixture_path(FIXTURE, RULES)
	_check(report.get("success", false), "test world starts")
	return session


func _snapshot(session: Variant) -> Variant:
	return Snapshot.new().build_snapshot(session.context, session.stores, true)


func _transaction(id: String) -> Variant:
	var result = Transaction.new()
	result.add_fact({"fact_id": "fact.test.economic." + id, "fact_type": "test_injection", "summary": "经济边界测试注入"})
	result.mark_resolved("test_injection")
	return result


func _apply(session: Variant, result: Variant) -> bool:
	var ok: bool = session.writer.apply_result(result, session.stores)
	if not ok:
		print("[ECONOMIC TRANSACTION] ", JSON.stringify(session.writer.last_report))
	return ok


func _reject_unchanged(session: Variant, result: Variant, label: String, error: String = "") -> void:
	var before: Dictionary = session.get_save_store_data()
	var rejected := not _apply(session, result)
	_check(rejected and before == session.get_save_store_data() and (error == "" or error in str(session.writer.last_report)), label)


func _test_authority() -> void:
	var session = _start()
	var stock: Dictionary = {}
	for candidate: Dictionary in session.stores["resource_stock_store"].list_stocks():
		if str(candidate.get("source_kind", "")) == "traffic_capacity" and not candidate["access"]["organization_grants"].is_empty():
			stock = candidate
			break
	var organization := str(stock["access"]["organization_grants"].keys()[0])
	var manager := str(stock["access"]["manager_id"])
	var source := str(stock["access"]["source_fact_id"])
	var change := {"stock_id": stock["stock_id"], "operation": "consume", "reason": "organization_route_patrol",
		"actor_id": organization, "amount": 3.0, "day": 1, "source_fact_ids": [source]}
	var foreign := str(session.stores["entity_store"].list_entity_rows().filter(func(row: Dictionary) -> bool:
		return str(row.get("type", "")) == "institution" and str(row.get("settlement_id", "")) != manager)[0]["id"])
	for actor: String in ["", foreign]:
		var invalid = _transaction("foreign_" + actor)
		var row := change.duplicate(true)
		row["actor_id"] = actor
		invalid.add_resource_change(row)
		_reject_unchanged(session, invalid, "missing or foreign actor cannot use another commons")
	for operation: String in ["set", "adjust", "recover"]:
		var invalid = _transaction("bad_operation_" + operation)
		var row := change.duplicate(true)
		row["operation"] = operation
		invalid.add_resource_change(row)
		_reject_unchanged(session, invalid, "permission cannot authorize arbitrary operation " + operation)
	var mixed = _transaction("payment_and_invalid_resource")
	_check(Treasury.new(_snapshot(session)).append_payment(mixed, manager, organization, 2, mixed.facts_added[0]["fact_id"], 24), "mixed transaction payment is affordable")
	var no_actor := change.duplicate(true)
	no_actor["actor_id"] = ""
	mixed.add_resource_change(no_actor)
	_reject_unchanged(session, mixed, "resource denial rolls back money and facts too")
	var first = _transaction("quota_first")
	first.add_resource_change(change)
	_check(_apply(session, first), "authorized use consumes actual resource")
	var second = _transaction("quota_over")
	second.add_resource_change(change)
	_reject_unchanged(session, second, "daily resource quota blocks a second over-budget use", "organization_daily_limit")
	var next = _transaction("quota_next_day")
	change["day"] = 2
	change["amount"] = 1.0
	next.add_resource_change(change)
	_check(_apply(session, next), "usage allowance resets on the next world day")
	var batch_a = _transaction("batch_a")
	var batch_b = _transaction("batch_b")
	change["day"] = 3
	change["amount"] = 3.0
	batch_a.add_resource_change(change.duplicate(true))
	batch_b.add_resource_change(change.duplicate(true))
	var before: Dictionary = session.get_save_store_data()
	_check(not session.writer.apply_results([batch_a, batch_b], session.stores) and before == session.get_save_store_data(), "batch cannot double-spend a daily quota and rolls back both uses")
	var forged = _transaction("forged_grant")
	forged.add_resource_change({"stock_id": stock["stock_id"], "operation": "grant_access", "reason": "grant_access", "actor_id": manager,
		"organization_id": organization, "source_fact_ids": [source], "daily_limit": 4, "day": 3})
	_reject_unchanged(session, forged, "unrelated fact cannot serve as an authorization", "grant_fact_mismatch")
	var revoke = _transaction("revoke")
	Access.append_organization_access(revoke, _snapshot(session), manager, organization, [stock["stock_id"]], revoke.facts_added[0]["fact_id"], 3, true)
	_check(_apply(session, revoke), "manager can revoke actual local permission")
	var revoked = _transaction("revoked_use")
	revoked.add_resource_change(change)
	_reject_unchanged(session, revoked, "revoked permission cannot be used", "organization_not_authorized")
	for reserve: Dictionary in session.stores["resource_stock_store"].list_stocks():
		if str(reserve.get("source_kind", "")) != "trade_reserve":
			continue
		var credit = _transaction("unbacked_credit")
		credit.add_resource_change({"stock_id": reserve["stock_id"], "operation": "adjust", "reason": "network_trade_import", "actor_id": reserve["settlement_id"],
			"amount": 1, "source_fact_ids": [source], "day": 3})
		_reject_unchanged(session, credit, "authorized import cannot create supply without a matching export", "transfer_unbalanced")
		var recover = _transaction("reserve_recovery")
		recover.add_resource_change({"stock_id": reserve["stock_id"], "operation": "recover", "reason": "natural_recovery", "amount": 1})
		_reject_unchanged(session, recover, "finished reserves cannot naturally regenerate", "recovery_not_natural")
		break
	_check(session.validate_persistent_references().get("ok", false), "authorization history and usage references remain valid")
	var damaged := stock.duplicate(true)
	damaged["access"]["organization_grants"][organization]["daily_limit"] = -1
	_check(Access.shape_error(damaged, true) != "", "negative authorization quota is rejected")
	damaged = stock.duplicate(true)
	damaged["access"]["usage"]["unknown_organization"] = {"day": 1, "amount": 1}
	_check(Access.shape_error(damaged, true) != "", "usage cannot name an organization with no grant history")


func _test_payments() -> void:
	var session = _start()
	var manager := "generated_settlement.river_steps"
	var target := str(session.stores["entity_store"].list_entity_rows().filter(func(row: Dictionary) -> bool: return str(row.get("type", "")) == "person")[0]["id"])
	var treasury = Treasury.new(_snapshot(session))
	var starting := treasury.balance(manager)
	var recipient_start := treasury.balance(target)
	var split = _transaction("split_payment")
	_check(treasury.append_payment(split, manager, target, 2, split.facts_added[0]["fact_id"], 1), "partial stack payment plans")
	_check(_apply(session, split), "partial stack transfers real coins")
	_reject_unchanged(session, split, "replaying a partial payment cannot pay twice")
	var refund = _transaction("refund")
	var new_stack := str(split.item_changes[0]["new_item_instance_id"])
	refund.add_item_change({"operation": "transfer", "item_instance_id": new_stack, "new_holder": {"kind": "entity", "id": manager}, "source_fact_ids": [refund.facts_added[0]["fact_id"]]})
	_check(_apply(session, refund), "test injection restores split coins as a second payer stack")
	var all = _transaction("multi_stack")
	_check(Treasury.new(_snapshot(session)).append_payment(all, manager, target, starting, all.facts_added[0]["fact_id"], 2) and all.item_changes.size() >= 2, "payment spans multiple actual stacks")
	_check(_apply(session, all) and Treasury.new(_snapshot(session)).balance(manager) == 0 and Treasury.new(_snapshot(session)).balance(target) == recipient_start + starting, "payer debit equals recipient credit")
	_reject_unchanged(session, all, "stale whole-stack payment cannot transfer recipient property again", "payment_already_recorded")
	var returned = _transaction("return_payment")
	_check(Treasury.new(_snapshot(session)).append_payment(returned, target, manager, starting, returned.facts_added[0]["fact_id"], 3) and _apply(session, returned), "test injection returns coins to the original payer")
	var replay = _transaction("old_payment_after_return")
	_check(Treasury.new(_snapshot(session)).append_payment(replay, manager, target, 1, all.facts_added[0]["fact_id"], 4), "returned money would otherwise fund an old payment again")
	_reject_unchanged(session, replay, "recorded payment identity prevents replay even after money returns", "payment_already_recorded")
	var drain_again = _transaction("drain_again")
	Treasury.new(_snapshot(session)).append_payment(drain_again, manager, target, starting, drain_again.facts_added[0]["fact_id"], 5)
	_check(_apply(session, drain_again), "a genuinely new payment remains possible")
	var insufficient = _transaction("insufficient")
	_check(not Treasury.new(_snapshot(session)).append_payment(insufficient, manager, target, 1, "test", 3) and insufficient.item_changes.is_empty(), "insufficient funds plan no payment")
	var protected = _transaction("reserve")
	_check(not Treasury.new(_snapshot(session)).append_payment(protected, target, manager, 1, "test", 3, recipient_start + starting), "required reserve cannot be spent")
	var mint = _transaction("mint")
	mint.add_item_change({"operation": "increase_quantity", "item_instance_id": new_stack, "quantity": 1, "source_fact_ids": [mint.facts_added[0]["fact_id"]]})
	_reject_unchanged(session, mint, "ordinary transaction cannot mint copper", "currency_supply_changed")
	var missing_funding = _transaction("no_funding")
	Treasury.new(_snapshot(session)).append_funding(missing_funding, _snapshot(session), manager, target, missing_funding.facts_added[0]["fact_id"], 3)
	_check(missing_funding.item_changes.is_empty() and str(missing_funding.facts_added.back()["fact_type"]) == "organization_funding_unavailable", "empty treasury records unavailable funding without creating coins")


func _test_response_denial() -> void:
	var session = _start()
	var organization: Dictionary = session.stores["entity_store"].get_entity("generated_organization.reed_bay.provision_circle")
	var manager := str(organization["settlement_id"])
	for stock: Dictionary in session.stores["resource_stock_store"].list_stocks_for_settlement(manager):
		if "food" in stock.get("tags", []):
			session.stores["resource_stock_store"].apply_resource_change({"stock_id": stock["stock_id"], "operation": "set",
				"amount": 0 if str(stock.get("source_kind", "")) == "trade_reserve" else minf(6, float(stock["capacity"])), "reason": "test_injection"})
	session.stores["state_store"].apply_state_change({"entity_id": manager, "key": "food_pressure", "to": "high"})
	var revoke = _transaction("response_revoke")
	Access.append_organization_access(revoke, _snapshot(session), manager, str(organization["id"]), organization["resource_stock_ids"], revoke.facts_added[0]["fact_id"], 2, true)
	_check(_apply(session, revoke), "test injection withdraws a provisioning organization's local permissions")
	var tick := {"tick_event_id": "test.response_without_access", "day": 3, "hour": 8}
	var data: Dictionary = Response.new().resolve_tick(_snapshot(session), tick, session.world_tick_adapter.organization_runtime_config, session.get_settlement_network_summary())
	var blocked := 0
	for result: Variant in data.get("results", []):
		if result.facts_added.any(func(fact: Dictionary) -> bool: return str(fact.get("fact_type", "")) == "organization_resource_access_blocked"):
			blocked += 1
			_check(result.resource_changes.is_empty() and result.state_changes.is_empty() and _apply(session, result), "unauthorized response records refusal without applying the promised effect")
	_check(blocked > 0, "withdrawn access changes a real organization plan")
	var again: Dictionary = Response.new().resolve_tick(_snapshot(session), tick, session.world_tick_adapter.organization_runtime_config, session.get_settlement_network_summary())
	_check(not again.get("results", []).any(func(result: Variant) -> bool:
		return result.facts_added.any(func(fact: Dictionary) -> bool: return str(fact.get("fact_type", "")) == "organization_resource_access_blocked")), "same-day refusal is not duplicated endlessly")


func _test_work_boundaries() -> void:
	var session = _start()
	var profiles: Array = session.npc_livelihood_profiles.filter(func(row: Dictionary) -> bool: return int(row.get("wage_amount", 0)) > 0)
	_check(not profiles.is_empty(), "generated service occupations have wages rather than copper recipes")
	var treasury = Treasury.new(_snapshot(session))
	var sink := str(session.stores["entity_store"].list_entity_rows().filter(func(row: Dictionary) -> bool: return str(row.get("type", "")) == "person")[0]["id"])
	var drain = _transaction("drain_treasuries")
	for site: Dictionary in session.get_settlement_network_summary().get("sites", []):
		var manager := str(site["settlement_id"])
		var amount := treasury.balance(manager)
		if amount > 0:
			treasury.append_payment(drain, manager, sink, amount, drain.facts_added[0]["fact_id"], 1)
	_check(_apply(session, drain), "test injection empties treasuries by transfer, not deletion")
	for person: Dictionary in session.stores["entity_store"].list_entity_rows():
		if str(person.get("type", "")) == "person":
			session.stores["state_store"].apply_state_change({"entity_id": person["id"], "key": "livelihood_elapsed_hours", "to": 100})
	var work: Dictionary = Work.new().resolve_work_tick(_snapshot(session), profiles, {"tick_event_id": "test.empty_treasury", "elapsed_hours": 1, "day": 2, "hour": 8})
	var count := 0
	for result: Variant in work.get("results", []):
		count += result.facts_added.filter(func(row: Dictionary) -> bool: return str(row.get("fact_type", "")) == "npc_wage_work_declined").size()
		_check(result.item_changes.is_empty() and result.resource_changes.is_empty() and _apply(session, result), "unfunded work has no fabricated wage, product or input cost")
	_check(count > 0 and _currency(session) == 440, "workers decline unfunded shifts with recorded reasons and money conserved")
	var production: Dictionary = session.npc_livelihood_profiles.filter(func(row: Dictionary) -> bool: return not row.get("resource_inputs", []).is_empty())[0]
	var person := str(session.stores["entity_store"].list_entity_rows().filter(func(row: Dictionary) -> bool:
		return str(session.stores["state_store"].get_state(str(row["id"]), "settlement_id", "")) == str(production.get("settlement_id", "")) and str(row.get("type", "")) == "person")[0]["id"])
	var stock_id := str(production["resource_inputs"][0]["stock_id"])
	session.stores["resource_stock_store"].stocks[stock_id]["access"]["resident_production"] = false
	var available: Dictionary = {}
	for stock: Dictionary in session.stores["resource_stock_store"].list_stocks():
		available[str(stock["stock_id"])] = float(stock["current"])
	var plan: Dictionary = Work.new()._resource_plan(production, available, _snapshot(session), person)
	_check(not plan.get("ok", true) and str(plan.get("missing", {}).get("denial", "")) == "resident_use_denied", "production candidate refuses withdrawn commons permission before writing")


func _test_retirement() -> void:
	var session = _start()
	var organization: Dictionary = session.stores["entity_store"].list_entity_rows().filter(func(row: Dictionary) -> bool:
		return str(row.get("type", "")) == "institution" and not row.get("resource_stock_ids", []).is_empty())[0]
	var id := str(organization["id"])
	var manager := str(organization["settlement_id"])
	var treasury = Treasury.new(_snapshot(session))
	var amount := treasury.balance(id)
	var balance := treasury.balance(manager)
	var opening = _transaction("open_commitment")
	opening.add_exchange({"exchange_id": "exchange.test.retire", "exchange_type": "test_injection", "status": "open", "party_a": id, "party_b": manager, "source_fact_ids": [opening.facts_added[0]["fact_id"]]})
	_check(_apply(session, opening), "test injection gives retiring organization an open commitment")
	var result: Variant = Lifecycle.new()._retirement_result(_snapshot(session), session.stores["entity_store"].get_entity(manager), organization,
		opening.facts_added[0]["fact_id"], "test_injection", "测试注入：组织结束职责", 3)["result"]
	var unsafe = _transaction("unsafe_retirement")
	unsafe.facts_added.append_array(result.facts_added)
	unsafe.entity_changes.append_array(result.entity_changes)
	_reject_unchanged(session, unsafe, "retirement cannot strand actual treasury assets", "retirement_assets_unresolved")
	_check(_apply(session, result), "actual lifecycle retires organization and settles its boundaries atomically")
	_check(Treasury.new(_snapshot(session)).balance(id) == 0 and Treasury.new(_snapshot(session)).balance(manager) == balance + amount, "retirement returns exact remaining coins to manager")
	_check(session.stores["exchange_store"].find_open_exchanges().is_empty(), "retirement closes outstanding commitment")
	_check(session.validate_persistent_references().get("ok", false), "retired organization has no active grant or dangling references")
	_reject_unchanged(session, result, "retirement replay cannot reclaim assets twice")


func _test_save_and_legacy(session: Variant) -> void:
	var path := "user://tests/economic_authority.save.json"
	var before: Dictionary = session.get_save_store_data()
	var saved: Dictionary = session.save_to_path(path, {"save_id": "save.test.economic_authority"})
	var restored = Session.new()
	var loaded: Dictionary = restored.load_from_path(path)
	_check(saved.get("ok", false) and loaded.get("success", false) and _equivalent(before, restored.get_save_store_data()), "save roundtrip preserves real money and resource permissions")
	_check(restored.stores["item_store"].conserve_currency and restored.stores["resource_stock_store"].access_version == 1, "load retains strict economic mode without new endowments")
	var corrupt_id := str(restored.stores["resource_stock_store"].stocks.keys()[0])
	restored.stores["resource_stock_store"].stocks[corrupt_id]["access"]["source_fact_id"] = "missing"
	_check(not restored.validate_persistent_references().get("ok", true), "unknown commons source is invalid")
	var legacy_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	legacy_data.erase("economic_contract")
	var legacy = Session.new()
	var started: Dictionary = legacy.start_from_fixture_data(legacy_data, RULES)
	_check(started.get("success", false) and not legacy.stores["item_store"].conserve_currency and _facts(legacy, "initial_treasury_endowment").is_empty(), "legacy world gets no forced ownership or retroactive currency grant")
	var old_path := OS.get_environment("TEMP").path_join("chronicle-pre-economic-51e51a7.save.json")
	if FileAccess.file_exists(old_path):
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_path))
		var old = Session.new()
		var old_result: Dictionary = old.load_from_path(old_path)
		_check(old_result.get("success", false) and not old.stores["item_store"].conserve_currency and old.validate_persistent_references().get("ok", false)
			and _equivalent(original["stores"], old.get_save_store_data()), "actual pre-economic 30-day save loads with every Store unchanged in legacy mode")
		print("[ECONOMIC LEGACY SAMPLE] ", JSON.stringify({"path": old_path, "load_success": old_result.get("success", false), "endowments": _facts(old, "initial_treasury_endowment").size(), "currency": _currency(old)}))


func _currency(session: Variant) -> int:
	var total := 0
	for item: Dictionary in session.stores["item_store"].list_items():
		if str(item.get("item_def_id", "")) == Treasury.CURRENCY:
			total += int(item.get("quantity", 0))
	return total


func _equivalent(left: Variant, right: Variant) -> bool:
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _equivalent(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in left.size():
			if not _equivalent(left[index], right[index]):
				return false
		return true
	if (left is int or left is float) and (right is int or right is float):
		return is_equal_approx(float(left), float(right))
	return left == right


func _facts(session: Variant, kind: String) -> Array:
	return session.stores["fact_store"].list_facts().filter(func(fact: Dictionary) -> bool:
		return str(fact.get("fact_type", "")) == kind)


func _check(value: bool, message: String) -> void:
	print("[ECONOMIC AUTHORITY %s] %s" % ["PASS" if value else "FAIL", message])
	if not value:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	print("[ECONOMIC AUTHORITY RESULT] ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
