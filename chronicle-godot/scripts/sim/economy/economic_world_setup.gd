extends RefCounted
class_name V5EconomicWorldSetup

const Access = preload("res://scripts/sim/resource/resource_access.gd")
const Money = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")


static func configure_fixture(source: Dictionary) -> Dictionary:
	var config: Dictionary = source.get("economic_contract", {})
	if config.is_empty() or int(config.get("version", 0)) == 0:
		return {"ok": true, "fixture": source}
	if int(config.get("version", 0)) != 1:
		return {"ok": false, "error": "economic_version_unsupported"}
	if source.has("economic_generation_result"):
		return {"ok": true, "fixture": source}
	var fixture := source.duplicate(true)
	var sites: Array = fixture.get("settlement_network_runtime", {}).get("sites", [])
	if sites.is_empty():
		return {"ok": false, "error": "economic_settlements_missing"}
	var stocks: Array = fixture.get("initial_resource_stocks", [])
	var entities: Array = fixture.get("entities", [])
	var facts: Array = fixture.get("known_facts", [])
	var items: Array = fixture.get("initial_items", [])
	var total := 0
	for item: Dictionary in items:
		if str(item.get("item_def_id", "")) == Money.CURRENCY:
			total += int(item.get("quantity", 0))
	for site: Dictionary in sites:
		var manager := str(site["settlement_id"])
		var grant_amount := maxi(int(config.get("organization_seed_grant", 12)), 0)
		var balance := clampi(int(config.get("settlement_initial_coins", 120)), 1, 9999)
		total += balance
		var source_id := "fact.economic_endowment." + manager
		var commons_id := "fact.resource_commons." + manager
		var stock_ids: Array = []
		for stock: Dictionary in stocks:
			if str(stock.get("settlement_id", "")) == manager:
				stock_ids.append(str(stock["stock_id"]))
				stock["access"] = Access.policy(manager, commons_id)
		facts.append({"fact_id": source_id, "fact_type": "initial_treasury_endowment", "actor_id": manager,
			"target_id": manager, "amount": balance, "day": 1,
			"summary": "聚落开局拥有 %d 枚公共铜币；后续支出只能使用实际持有的钱。" % balance})
		facts.append({"fact_id": commons_id, "fact_type": "resource_commons_established", "actor_id": manager,
			"target_id": manager, "stock_ids": stock_ids, "source_fact_ids": [source_id], "day": 1,
			"summary": "聚落共同管理当地资源，居民可用于本地生产，组织使用另需许可与额度。"})
		for entity: Dictionary in entities:
			if str(entity.get("id", "")) == manager:
				var states: Dictionary = entity.get("states", {})
				states.merge({"economic_contract_version": 1, "treasury_reserve": maxi(int(config.get("treasury_reserve", 12)), 0),
					"organization_seed_grant": grant_amount}, true)
				entity["states"] = states
			if str(entity.get("type", "")) != "institution" or str(entity.get("settlement_id", "")) != manager:
				continue
			var organization := str(entity["id"])
			var grant_id := "fact.resource_access." + organization + ".initial"
			var authorized: Array = []
			for stock: Dictionary in stocks:
				if str(stock["stock_id"]) in entity.get("resource_stock_ids", []) and str(stock.get("settlement_id", "")) == manager:
					stock["access"]["organization_grants"][organization] = Access.grant(grant_id)
					authorized.append(str(stock["stock_id"]))
			facts.append({"fact_id": grant_id, "fact_type": "resource_access_granted", "actor_id": manager,
				"target_id": organization, "stock_ids": authorized, "source_fact_ids": [commons_id], "day": 1,
				"summary": "聚落授予当地组织限定用途的使用权，每项库存每日最多支用 4 单位。"})
			var amount := mini(grant_amount, balance)
			if amount > 0:
				var funding_id := "fact.treasury_funding." + organization
				facts.append({"fact_id": funding_id, "fact_type": "organization_treasury_funded", "actor_id": manager,
					"target_id": organization, "amount": amount, "source_fact_ids": [source_id], "day": 1,
					"summary": "开局公共金库分配 %d 枚铜币给当地组织，没有额外增发。" % amount})
				items.append(_coins(organization, amount, [source_id, funding_id]))
				balance -= amount
		if balance > 0:
			items.append(_coins(manager, balance, [source_id]))
	fixture["initial_resource_stocks"] = stocks
	fixture["initial_items"] = items
	fixture["entities"] = entities
	fixture["known_facts"] = facts
	_configure_wages(fixture.get("generated_livelihood_profiles", []))
	_configure_wages(fixture.get("settlement_network_runtime", {}).get("industry_occupation_templates", []))
	fixture["economic_generation_result"] = {"version": 1, "initial_currency_total": total}
	return {"ok": true, "fixture": fixture}


static func _coins(holder: String, amount: int, sources: Array) -> Dictionary:
	return {"item_instance_id": "item.treasury." + holder, "item_def_id": Money.CURRENCY,
		"holder": {"kind": "entity", "id": holder}, "quantity": amount,
		"source_fact_ids": sources, "provenance": {"source_kind": "initial_treasury_endowment"}}


static func _configure_wages(profiles: Array) -> void:
	for profile: Dictionary in profiles:
		var products: Array = []
		var wage := 0
		for product: Dictionary in profile.get("products", []):
			if str(product.get("item_def_id", "")) == Money.CURRENCY:
				wage += int(product.get("quantity", 0))
			else:
				products.append(product)
		if wage > 0:
			profile["wage_amount"] = wage
			profile["products"] = products
