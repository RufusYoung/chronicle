extends RefCounted
class_name V5TransactionWorldWriter


func apply_result(result: Variant, stores: Dictionary) -> void:
	var fact_store: Variant = stores.get("fact_store")
	if fact_store != null:
		for fact: Dictionary in result.facts_added:
			fact_store.add_fact(fact)

	var state_store: Variant = stores.get("state_store")
	if state_store != null:
		for state_change: Dictionary in result.state_changes:
			state_store.apply_state_change(state_change)

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
