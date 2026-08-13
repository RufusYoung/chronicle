extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const FIXTURE := (
	"res://data/sim/fixtures/seventh_outpost_first_winter_fixture.json"
)
const MARKET_POLICY_ID := "market_policy.seventh_outpost_canteen"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = SimSessionModel.new()
	var start: Dictionary = session.start_from_fixture_path(FIXTURE, [])
	_check(bool(start.get("success", false)), "1. First-winter fixture starts")
	if not bool(start.get("success", false)):
		push_error("[V5 FIRST WINTER MARKET START REPORT] %s" % str(start))
		_finish()
		return

	var initial_snapshot = session.get_snapshot()
	var stock: Dictionary = session.get_market_stock_view(MARKET_POLICY_ID)
	var offer := _first_offer(stock)
	_check(
		int(offer.get("available_quantity", 0)) == 6
		and int(offer.get("unit_price", 0)) == 3
		and str(offer.get("quote_summary", "")).contains("粮食压力")
		and str(offer.get("quote_summary", "")).contains("玛塔的信任"),
		"2. Quote exposes stock, food pressure, trust, and price"
	)
	_check(
		_item_quantity(initial_snapshot, "player", "item.copper_coin") == 12
		and _item_quantity(initial_snapshot, "player", "item.travel_ration") == 2
		and _pressure_value(initial_snapshot, "food_pressure") == 2,
		"3. Fixture initializes real currency, rations, and pressure"
	)

	var rejected: Dictionary = session.execute_market_trade(
		MARKET_POLICY_ID,
		{
			"item_instance_id": str(offer.get("item_instance_id", "")),
			"quantity": 1,
			"quoted_unit_price": 2,
		}
	)
	var after_rejection = session.get_snapshot()
	_check(
		not bool(rejected.get("success", false))
		and str(rejected.get("error", "")) == "quote_changed"
		and _item_quantity(after_rejection, "player", "item.copper_coin") == 12
		and _item_quantity(after_rejection, "cook_marta", "item.travel_ration") == 6
		and after_rejection.get_open_exchanges().is_empty(),
		"4. Stale quote rejects without mutating any store"
	)

	var purchased: Dictionary = session.execute_market_trade(
		MARKET_POLICY_ID,
		{
			"item_instance_id": str(offer.get("item_instance_id", "")),
			"quantity": 1,
			"quoted_unit_price": int(offer.get("unit_price", 0)),
		}
	)
	var after_purchase = session.get_snapshot()
	var next_stock: Dictionary = session.get_market_stock_view(MARKET_POLICY_ID)
	_check(
		bool(purchased.get("success", false))
		and int(purchased.get("total_price", 0)) == 3
		and _item_quantity(after_purchase, "player", "item.copper_coin") == 9
		and _item_quantity(after_purchase, "player", "item.travel_ration") == 3
		and _item_quantity(after_purchase, "cook_marta", "item.travel_ration") == 5
		and _item_quantity(after_purchase, "cook_marta", "item.copper_coin") == 3,
		"5. Purchase atomically transfers goods and payment"
	)
	_check(
		after_purchase.get_facts().size() == initial_snapshot.get_facts().size() + 1
		and after_purchase.exchanges.size() == 1
		and _pressure_value(after_purchase, "food_pressure") == 3
		and int(_first_offer(next_stock).get("unit_price", 0)) == 4,
		"6. Purchase leaves a fact, exchange, and pressure-sensitive next quote"
	)
	var malformed_policy: Dictionary = session.market_policies[0].duplicate(true)
	malformed_policy["accepted_currency_item_def_ids"] = []
	var malformed: Dictionary = session.market_service.execute_trade(
		malformed_policy,
		{
			"buyer_entity_id": "player",
			"item_instance_id": str(
				_first_offer(next_stock).get("item_instance_id", "")
			),
			"quantity": 1,
			"quoted_unit_price": int(
				_first_offer(next_stock).get("unit_price", 0)
			),
		},
		session.stores,
		session.writer,
		session.get_time_summary()
	)
	var after_malformed = session.get_snapshot()
	_check(
		not bool(malformed.get("success", false))
		and str(malformed.get("error", ""))
			== "market_currency_not_configured"
		and after_malformed.get_facts().size() == after_purchase.get_facts().size()
		and after_malformed.exchanges.size() == after_purchase.exchanges.size(),
		"7. Malformed currency policy fails explicitly without mutation"
	)

	_finish()


func _first_offer(stock: Dictionary) -> Dictionary:
	var offers: Array = stock.get("offers", [])
	return {} if offers.is_empty() else (offers[0] as Dictionary)


func _item_quantity(snapshot: Variant, owner_id: String, item_def_id: String) -> int:
	var quantity := 0
	for item: Dictionary in snapshot.get_items():
		var holder: Dictionary = item.get("holder", {})
		if (
			str(holder.get("kind", "")) == "entity"
			and str(holder.get("id", "")) == owner_id
			and str(item.get("item_def_id", "")) == item_def_id
		):
			quantity += int(item.get("quantity", 0))
	return quantity


func _pressure_value(snapshot: Variant, pressure_type: String) -> int:
	var value := 0
	for pressure: Dictionary in snapshot.get_pressures():
		if str(pressure.get("pressure_type", "")) == pressure_type:
			value += int(pressure.get("value", 0))
	return value


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 FIRST WINTER MARKET PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 FIRST WINTER MARKET RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 FIRST WINTER MARKET FAIL] " + failure)
	print("[V5 FIRST WINTER MARKET RESULT] FAIL (%d)" % failures.size())
	quit(1)
