extends RefCounted
class_name V5ResourceAccess

const MANAGER_USES := [
	"settlement_daily_consumption", "network_trade_export", "network_trade_import",
	"network_trade_transport", "settlement_dwelling_construction",
	"settlement_facility_expansion", "industry_construction",
]
const ORGANIZATION_USES := [
	"organization_local_provisioning_source", "organization_local_provisioning_reserve",
	"organization_trade_coordination", "organization_route_patrol",
]
const CREDIT_USES := ["network_trade_import", "organization_local_provisioning_reserve"]


static func policy(manager_id: String, fact_id: String) -> Dictionary:
	return {"version": 1, "manager_id": manager_id, "source_fact_id": fact_id,
		"resident_production": true, "manager_uses": MANAGER_USES.duplicate(),
		"organization_grants": {}, "usage": {}}


static func grant(fact_id: String, limit: float = 4.0) -> Dictionary:
	return {"active": true, "source_fact_id": fact_id,
		"uses": ORGANIZATION_USES.duplicate(), "daily_limit": limit}


static func manager_allows(stock: Dictionary, manager: String, purpose: String) -> bool:
	if not stock.has("access"):
		return true
	return str(stock["access"].get("manager_id", "")) == manager and purpose in stock["access"].get("manager_uses", [])


static func shape_error(stock: Dictionary, required: bool = false) -> String:
	if not stock.has("access"):
		return "policy_missing" if required else ""
	if not stock["access"] is Dictionary:
		return "policy_not_dictionary"
	var access: Dictionary = stock["access"]
	if int(access.get("version", 0)) != 1 or str(access.get("manager_id", "")) == "":
		return "policy_identity_invalid"
	if str(access.get("source_fact_id", "")) == "" or not access.get("resident_production") is bool:
		return "policy_source_or_resident_rule_invalid"
	if not access.get("manager_uses") is Array or not access.get("organization_grants") is Dictionary or not access.get("usage") is Dictionary:
		return "policy_rules_invalid"
	for purpose: Variant in access["manager_uses"]:
		if str(purpose) not in MANAGER_USES:
			return "manager_use_unknown"
	for id: String in access["organization_grants"]:
		var row: Variant = access["organization_grants"][id]
		if id == "" or not row is Dictionary or not row.get("active") is bool or not row.get("uses") is Array:
			return "grant_invalid"
		if str(row.get("source_fact_id", "")) == "" or not is_finite(float(row.get("daily_limit", 0))) or float(row.get("daily_limit", 0)) <= 0:
			return "grant_limit_or_source_invalid"
		for purpose: Variant in row["uses"]:
			if str(purpose) not in ORGANIZATION_USES:
				return "grant_use_unknown"
	for id: String in access["usage"]:
		var row: Variant = access["usage"][id]
		if not access["organization_grants"].has(id) or not row is Dictionary or int(row.get("day", -1)) < 0 or not is_finite(float(row.get("amount", -1))) or float(row.get("amount", -1)) < 0:
			return "usage_invalid"
	return ""


static func denial(snapshot: Variant, stock: Dictionary, actor_id: String, purpose: String, amount: float = 0, day: int = 0) -> String:
	if not stock.has("access"):
		return ""
	return _permission_error(stock, actor_id, snapshot.get_entity(actor_id),
		str(snapshot.get_entity_state(actor_id, "settlement_id", "")),
		str(snapshot.get_entity_state(actor_id, "life_status", "alive")), purpose, amount, day)


static func _permission_error(stock: Dictionary, actor_id: String, actor: Dictionary, settlement: String, life: String, purpose: String, amount: float, day: int) -> String:
	var access: Dictionary = stock.get("access", {})
	var kind := str(stock.get("source_kind", ""))
	if purpose in CREDIT_USES and kind != "trade_reserve":
		return "use_stock_kind_invalid"
	if purpose in ["organization_trade_coordination", "organization_route_patrol", "network_trade_transport"] and kind != "traffic_capacity":
		return "use_stock_kind_invalid"
	if purpose in ["organization_local_provisioning_source", "network_trade_export"] and kind != "natural_resource":
		return "use_stock_kind_invalid"
	if actor_id == "" or actor.is_empty() or str(actor.get("lifecycle_status", "active")) == "retired" or life == "dead":
		return "actor_unavailable"
	if actor_id == str(access.get("manager_id", "")):
		return "" if purpose in access.get("manager_uses", []) or purpose in ["grant_access", "revoke_access"] else "manager_use_denied"
	if purpose == "livelihood_production":
		return "" if str(actor.get("type", "")) == "person" and settlement == str(access.get("manager_id", "")) and bool(access.get("resident_production", false)) else "resident_use_denied"
	var permission: Dictionary = access.get("organization_grants", {}).get(actor_id, {})
	if not bool(permission.get("active", false)) or purpose not in permission.get("uses", []):
		return "organization_not_authorized"
	if str(actor.get("type", "")) != "institution" or str(actor.get("settlement_id", settlement)) != str(access.get("manager_id", "")):
		return "organization_outside_scope"
	var usage: Dictionary = access.get("usage", {}).get(actor_id, {})
	var used := float(usage.get("amount", 0)) if int(usage.get("day", -1)) == day else 0.0
	if purpose not in CREDIT_USES and used + amount > float(permission.get("daily_limit", 0)) + 0.0001:
		return "organization_daily_limit"
	return ""


static func validate_change(change: Dictionary, stores: Dictionary) -> String:
	var resource_store: Variant = stores["resource_stock_store"]
	var stock: Dictionary = resource_store.get_stock(str(change.get("stock_id", "")))
	if stock.is_empty():
		return "stock_unknown"
	if not stock.has("access"):
		return "policy_missing" if int(resource_store.access_version) > 0 else ""
	var operation := str(change.get("operation", ""))
	var reason := str(change.get("reason", ""))
	var amount := float(change.get("amount", 0))
	if operation == "recover":
		if reason != "natural_recovery" or str(stock.get("source_kind", "")) not in ["natural_resource", "traffic_capacity"] or amount < 0 or amount > float(stock.get("recovery_per_hour", 0)) + 0.0001:
			return "recovery_not_natural"
		return ""
	var actor_id := str(change.get("actor_id", ""))
	var entity_store: Variant = stores["entity_store"]
	var states: Variant = stores["state_store"]
	var error := _permission_error(stock, actor_id, entity_store.get_entity(actor_id),
		str(states.get_state(actor_id, "settlement_id", "")), str(states.get_state(actor_id, "life_status", "alive")),
		reason, amount, int(change.get("day", -1)))
	if error != "":
		return error
	var sources: Variant = change.get("source_fact_ids", [])
	if not sources is Array or sources.is_empty():
		return "source_missing"
	for id: Variant in sources:
		if stores["fact_store"].get_fact(str(id)).is_empty():
			return "source_unknown"
	if operation in ["grant_access", "revoke_access"]:
		if reason != operation or actor_id != str(stock["access"]["manager_id"]):
			return "grant_issuer_invalid"
		var target := str(change.get("organization_id", ""))
		var entity: Dictionary = entity_store.get_entity(target)
		if str(entity.get("type", "")) != "institution" or str(entity.get("settlement_id", "")) != actor_id:
			return "grant_recipient_invalid"
		if operation == "grant_access" and not entity_store.is_entity_active(target):
			return "grant_recipient_retired"
		var fact: Dictionary = stores["fact_store"].get_fact(str(sources[0]))
		var expected := "resource_access_granted" if operation == "grant_access" else "resource_access_revoked"
		if str(fact.get("fact_type", "")) != expected or str(fact.get("actor_id", "")) != actor_id or str(fact.get("target_id", "")) != target or str(stock["stock_id"]) not in fact.get("stock_ids", []):
			return "grant_fact_mismatch"
		return ""
	if int(change.get("day", -1)) < 0 or not is_finite(amount) or amount <= 0:
		return "usage_amount_or_day_invalid"
	if (reason in CREDIT_USES and operation != "adjust") or (reason not in CREDIT_USES and operation != "consume"):
		return "operation_not_authorized"
	return ""


static func validate_references(stores: Dictionary) -> String:
	var resource_store: Variant = stores["resource_stock_store"]
	for stock: Dictionary in resource_store.list_stocks():
		var error := shape_error(stock, int(resource_store.access_version) > 0)
		if error != "":
			return error
		if not stock.has("access"):
			continue
		var access: Dictionary = stock["access"]
		var manager := str(access["manager_id"])
		var fact: Dictionary = stores["fact_store"].get_fact(str(access["source_fact_id"]))
		if not stores["entity_store"].has_entity(manager) or manager != str(stock.get("settlement_id", "")) or str(fact.get("fact_type", "")) != "resource_commons_established" or str(fact.get("actor_id", "")) != manager or str(stock.get("stock_id", "")) not in fact.get("stock_ids", []):
			return "manager_or_source_invalid"
		for id: String in access["organization_grants"]:
			var permission: Dictionary = access["organization_grants"][id]
			var organization: Dictionary = stores["entity_store"].get_entity(id)
			var grant_fact: Dictionary = stores["fact_store"].get_fact(str(permission["source_fact_id"]))
			if str(organization.get("type", "")) != "institution" or str(organization.get("settlement_id", "")) != manager or str(grant_fact.get("fact_type", "")) not in ["resource_access_granted", "resource_access_revoked"] or str(grant_fact.get("actor_id", "")) != manager or str(grant_fact.get("target_id", "")) != id or str(stock.get("stock_id", "")) not in grant_fact.get("stock_ids", []):
				return "grant_reference_invalid"
			if bool(permission["active"]) != (str(grant_fact["fact_type"]) == "resource_access_granted") or (bool(permission["active"]) and not stores["entity_store"].is_entity_active(id)):
				return "grant_status_invalid"
	return ""


static func validate_transfers(changes: Array, stores: Dictionary) -> String:
	var debits: Dictionary = {}
	var credits: Dictionary = {}
	for change: Dictionary in changes:
		var stock: Dictionary = stores["resource_stock_store"].get_stock(str(change.get("stock_id", "")))
		if not stock.has("access"):
			continue
		var reason := str(change.get("reason", ""))
		var family := "network" if reason in ["network_trade_export", "network_trade_import"] else "provision"
		if reason not in CREDIT_USES and reason not in ["network_trade_export", "organization_local_provisioning_source"]:
			continue
		var sources: Array = change.get("source_fact_ids", [])
		if sources.is_empty():
			return "transfer_source_missing"
		var key := family + ":" + str(sources[0])
		var totals := credits if reason in CREDIT_USES else debits
		totals[key] = float(totals.get(key, 0)) + float(change.get("amount", 0))
	for key: String in credits:
		if not is_equal_approx(float(credits[key]), float(debits.get(key, 0))):
			return "transfer_unbalanced"
	for key: String in debits:
		if not credits.has(key):
			return "transfer_destination_missing"
	return ""


static func apply_metadata(stock: Dictionary, change: Dictionary) -> void:
	if not stock.has("access"):
		return
	var access: Dictionary = stock["access"]
	var operation := str(change.get("operation", ""))
	if operation in ["grant_access", "revoke_access"]:
		var id := str(change["organization_id"])
		var row: Dictionary = grant(str(change["source_fact_ids"][0]), float(change.get("daily_limit", 4)))
		row["active"] = operation == "grant_access"
		access["organization_grants"][id] = row
	elif operation == "consume" and access["organization_grants"].has(str(change.get("actor_id", ""))):
		var id := str(change["actor_id"])
		var day := int(change.get("day", 0))
		var usage: Dictionary = access["usage"].get(id, {})
		var used := float(usage.get("amount", 0)) if int(usage.get("day", -1)) == day else 0.0
		access["usage"][id] = {"day": day, "amount": used + float(change.get("amount", 0))}


static func append_organization_access(result: Variant, snapshot: Variant, manager: String, organization: String, stock_ids: Array, source: String, day: int, revoke: bool = false) -> void:
	var eligible: Array = []
	for id: Variant in stock_ids:
		var stock: Dictionary = snapshot.get_resource_stock(str(id))
		if stock.has("access") and str(stock["access"].get("manager_id", "")) == manager:
			eligible.append(str(id))
	if eligible.is_empty():
		return
	var fact_id := "fact.resource_access.%s.%s.day%d" % [organization, "revoke" if revoke else "grant", day]
	result.add_fact({"fact_id": fact_id, "fact_type": "resource_access_revoked" if revoke else "resource_access_granted",
		"actor_id": manager, "target_id": organization, "stock_ids": eligible,
		"source_fact_ids": [source], "day": day,
		"summary": "聚落收回组织的公共资源使用许可。" if revoke else "聚落授予组织限定用途与每日额度的公共资源使用许可。"})
	for id: String in eligible:
		var operation := "revoke_access" if revoke else "grant_access"
		result.add_resource_change({"stock_id": id, "operation": operation, "reason": operation,
			"actor_id": manager, "organization_id": organization, "daily_limit": 4.0,
			"source_fact_ids": [fact_id], "day": day})
