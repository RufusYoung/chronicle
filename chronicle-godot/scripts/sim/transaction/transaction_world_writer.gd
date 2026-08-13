extends RefCounted
class_name V5TransactionWorldWriter

const EXTERNAL_PROJECTION_KEYS := [
	"injury",
	"mist_salt_echo",
	"inventory_item_ids",
]

var last_report: Dictionary = {"ok": true, "error": ""}


func apply_result(result: Variant, stores: Dictionary) -> bool:
	last_report = _preflight_item_and_equipment(result, stores)
	if not bool(last_report.get("ok", false)):
		if result != null and result.has_method("mark_invalid_contract"):
			result.mark_invalid_contract(
				str(result.transaction_mode),
				str(last_report.get("error", "transaction_preflight_failed"))
			)
		return false

	var fact_store: Variant = stores.get("fact_store")
	if fact_store != null:
		for fact: Dictionary in result.facts_added:
			fact_store.add_fact(fact)

	var state_store: Variant = stores.get("state_store")
	if state_store != null:
		for state_change: Dictionary in result.state_changes:
			if str(state_change.get("key", "")) in EXTERNAL_PROJECTION_KEYS:
				continue
			state_store.apply_state_change(state_change)

	var character_feature_store: Variant = stores.get("character_feature_store")
	if character_feature_store != null:
		character_feature_store.apply_facts(result.facts_added)

	var relationship_store: Variant = stores.get("relationship_store")
	if relationship_store != null:
		for relationship_change: Dictionary in result.relationship_changes:
			relationship_store.apply_relationship_change(relationship_change)

	var memory_store: Variant = stores.get("memory_store")
	if memory_store != null:
		for memory: Dictionary in result.memories_added:
			memory_store.add_memory(memory)

	var trace_store: Variant = stores.get("trace_store")
	if trace_store != null:
		for trace: Dictionary in result.traces_added:
			trace_store.add_trace(trace)

	var rumor_store: Variant = stores.get("rumor_store")
	if rumor_store != null:
		for rumor: Dictionary in result.rumors_added:
			rumor_store.add_rumor_seed(rumor)

	var pressure_store: Variant = stores.get("pressure_store")
	if pressure_store != null:
		for pressure_change: Dictionary in result.pressure_changes:
			pressure_store.add_pressure_change(pressure_change)

	var obligation_store: Variant = stores.get("obligation_store")
	if obligation_store != null:
		for obligation: Dictionary in result.obligations_added:
			obligation_store.add_obligation(obligation)
		for obligation_update: Dictionary in result.obligation_updates:
			obligation_store.apply_obligation_update(obligation_update)

	var exchange_store: Variant = stores.get("exchange_store")
	if exchange_store != null:
		for exchange: Dictionary in result.exchanges_added:
			exchange_store.add_exchange(exchange)
		for exchange_update: Dictionary in result.exchange_updates:
			exchange_store.apply_exchange_update(exchange_update)

	var deferred_consequence_store: Variant = stores.get("deferred_consequence_store")
	if deferred_consequence_store != null:
		for consequence: Dictionary in result.deferred_consequences_added:
			deferred_consequence_store.add_deferred_consequence(consequence)
		for consequence_update: Dictionary in result.deferred_consequence_updates:
			deferred_consequence_store.apply_deferred_consequence_update(consequence_update)

	var item_store: Variant = stores.get("item_store")
	if item_store != null:
		for item_change: Dictionary in result.item_changes:
			item_store.apply_item_change(item_change)

	var equipment_store: Variant = stores.get("equipment_store")
	if equipment_store != null:
		for equipment_change: Dictionary in result.equipment_changes:
			equipment_store.apply_equipment_change(equipment_change)

	var chronicle_store: Variant = stores.get("chronicle_store")
	if chronicle_store != null:
		for entry: Dictionary in result.chronicle_entries_added:
			chronicle_store.add_entry(entry)

	var investigation_store: Variant = stores.get("investigation_store")
	if investigation_store != null:
		for change: Dictionary in result.investigation_changes:
			investigation_store.apply_change(change)
	return true


func _preflight_item_and_equipment(
		result: Variant,
		stores: Dictionary
) -> Dictionary:
	if result.item_changes.is_empty() and result.equipment_changes.is_empty():
		return {"ok": true, "error": ""}
	var fact_store: Variant = stores.get("fact_store")
	var item_store: Variant = stores.get("item_store")
	var equipment_store: Variant = stores.get("equipment_store")
	if fact_store == null or item_store == null:
		return {"ok": false, "error": "item_equipment_preflight_store_missing"}
	if not result.equipment_changes.is_empty() and equipment_store == null:
		return {"ok": false, "error": "equipment_store_missing"}

	var preview_fact_store = fact_store.get_script().new()
	for fact: Dictionary in fact_store.list_facts():
		preview_fact_store.add_fact(fact)
	for fact: Dictionary in result.facts_added:
		preview_fact_store.add_fact(fact)
	var preview_item_store = item_store.fork_for_preflight(preview_fact_store)
	for item_change: Dictionary in result.item_changes:
		if not preview_item_store.apply_item_change(item_change):
			return {
				"ok": false,
				"error": "item_preflight_failed:%s" % preview_item_store.last_error,
			}
	if equipment_store == null:
		return {"ok": true, "error": ""}
	var preview_equipment_store = equipment_store.fork_for_preflight(
		preview_item_store,
		preview_fact_store
	)
	for equipment_change: Dictionary in result.equipment_changes:
		if not preview_equipment_store.apply_equipment_change(equipment_change):
			return {
				"ok": false,
				"error": "equipment_preflight_failed:%s"
					% preview_equipment_store.last_error,
			}
	var integrity: Dictionary = preview_equipment_store.validate_integrity()
	if not bool(integrity.get("ok", false)):
		return {
			"ok": false,
			"error": "equipment_integrity_failed:%s"
				% str((integrity.get("errors", []) as Array)[0]),
		}
	return {"ok": true, "error": ""}
