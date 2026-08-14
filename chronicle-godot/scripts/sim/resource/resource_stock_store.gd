extends RefCounted
class_name V5ResourceStockStore

const EPSILON := 0.0001

var stocks: Dictionary = {}
var last_error: String = ""


func load_initial_stocks(data: Variant) -> Dictionary:
	return load_save_data(data)


func list_stocks() -> Array:
	var ids: Array = stocks.keys()
	ids.sort()
	var rows: Array = []
	for stock_id: Variant in ids:
		rows.append((stocks[stock_id] as Dictionary).duplicate(true))
	return rows


func get_stock(stock_id: String) -> Dictionary:
	if not stocks.has(stock_id):
		return {}
	return (stocks[stock_id] as Dictionary).duplicate(true)


func list_stocks_for_settlement(settlement_id: String) -> Array:
	var rows: Array = []
	for stock: Dictionary in list_stocks():
		if str(stock.get("settlement_id", "")) == settlement_id:
			rows.append(stock)
	return rows


func list_stocks_for_location(location_id: String) -> Array:
	var rows: Array = []
	for stock: Dictionary in list_stocks():
		if str(stock.get("location_id", "")) == location_id:
			rows.append(stock)
	return rows


func apply_resource_change(change: Dictionary) -> bool:
	last_error = ""
	var stock_id := str(change.get("stock_id", ""))
	if stock_id == "" or not stocks.has(stock_id):
		return _reject("resource_stock_unknown:%s" % stock_id)
	var operation := str(change.get("operation", ""))
	if operation not in ["consume", "recover", "adjust", "set"]:
		return _reject("resource_operation_invalid:%s" % operation)
	var stock: Dictionary = (stocks[stock_id] as Dictionary).duplicate(true)
	var current := float(stock.get("current", 0.0))
	var capacity := float(stock.get("capacity", 0.0))
	var amount := float(change.get("amount", 0.0))
	var next := current
	match operation:
		"consume":
			if amount <= 0.0:
				return _reject("resource_consume_amount_invalid:%s" % stock_id)
			if amount > current + EPSILON:
				return _reject("resource_stock_underflow:%s" % stock_id)
			next = current - amount
		"recover":
			if amount < 0.0:
				return _reject("resource_recovery_amount_invalid:%s" % stock_id)
			next = minf(current + amount, capacity)
		"adjust":
			next = current + amount
		"set":
			next = amount
	if next < -EPSILON or next > capacity + EPSILON:
		return _reject("resource_stock_bounds_invalid:%s" % stock_id)
	next = _rounded(clampf(next, 0.0, capacity))
	stock["current"] = next
	stock["status"] = status_for(
		next,
		capacity,
		float(stock.get("operating_floor", 1.0))
	)
	stock["change_count"] = int(stock.get("change_count", 0)) + 1
	stock["last_operation"] = operation
	stock["last_delta"] = _rounded(next - current)
	stock["last_tick"] = int(change.get("tick", stock.get("last_tick", 0)))
	stock["last_source_fact_ids"] = (
		(change.get("source_fact_ids", []) as Array).duplicate(true)
		if change.get("source_fact_ids", []) is Array
		else []
	)
	stocks[stock_id] = stock
	return true


func to_save_data() -> Array:
	return list_stocks()


func load_save_data(data: Variant) -> Dictionary:
	stocks.clear()
	last_error = ""
	var errors: Array[String] = []
	if not data is Array:
		return {"ok": false, "errors": ["save_resource_stocks_not_array"]}
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_resource_stock_not_dictionary")
			continue
		var stock := (value as Dictionary).duplicate(true)
		var error := _stock_error(stock)
		if error != "":
			errors.append(error)
			continue
		var stock_id := str(stock.get("stock_id", ""))
		if stocks.has(stock_id):
			errors.append("resource_stock_duplicate:%s" % stock_id)
			continue
		stock["capacity"] = _rounded(float(stock.get("capacity", 0.0)))
		stock["current"] = _rounded(float(stock.get("current", 0.0)))
		stock["recovery_per_hour"] = _rounded(float(
			stock.get("recovery_per_hour", 0.0)
		))
		stock["operating_floor"] = _rounded(float(
			stock.get("operating_floor", 1.0)
		))
		stock["status"] = status_for(
			float(stock["current"]),
			float(stock["capacity"]),
			float(stock["operating_floor"])
		)
		stocks[stock_id] = stock
	return {"ok": errors.is_empty(), "errors": errors}


func validate_integrity() -> Dictionary:
	var errors: Array[String] = []
	for stock: Dictionary in list_stocks():
		var error := _stock_error(stock)
		if error != "":
			errors.append(error)
	return {"ok": errors.is_empty(), "errors": errors}


static func status_for(
		current: float,
		capacity: float,
		operating_floor: float = 1.0
) -> String:
	if capacity <= 0.0 or current + EPSILON < operating_floor:
		return "depleted"
	var ratio := current / capacity
	if ratio < 0.30:
		return "strained"
	if ratio < 0.65:
		return "stable"
	return "abundant"


func _stock_error(stock: Dictionary) -> String:
	var stock_id := str(stock.get("stock_id", ""))
	if stock_id == "":
		return "resource_stock_id_missing"
	if str(stock.get("source_id", "")) == "":
		return "resource_stock_source_missing:%s" % stock_id
	if str(stock.get("settlement_id", "")) == "":
		return "resource_stock_settlement_missing:%s" % stock_id
	var capacity := float(stock.get("capacity", 0.0))
	var current := float(stock.get("current", -1.0))
	if capacity <= 0.0:
		return "resource_stock_capacity_invalid:%s" % stock_id
	if current < 0.0 or current > capacity + EPSILON:
		return "resource_stock_current_invalid:%s" % stock_id
	if float(stock.get("recovery_per_hour", 0.0)) < 0.0:
		return "resource_stock_recovery_invalid:%s" % stock_id
	if not stock.get("tags", []) is Array:
		return "resource_stock_tags_invalid:%s" % stock_id
	return ""


func _reject(error: String) -> bool:
	last_error = error
	return false


func _rounded(value: float) -> float:
	return round(value * 1000.0) / 1000.0
