extends RefCounted
class_name LocalStoryPipeline

const HistoryQualityAuditModel = preload(
	"res://scripts/sim/history_quality_audit.gd"
)

var audit_contract := HistoryQualityAuditModel.new()


func run_days(
		state: Variant,
		module: Variant,
		days: int,
		profile: Dictionary = {}
	) -> Dictionary:
	if state == null or module == null:
		return {"error": "missing_state_or_module"}
	if not profile.is_empty():
		module.initialize_module_state(state, profile)
	var ticks: Array[Dictionary] = []
	for _day: int in range(maxi(days, 0)):
		ticks.append(tick_once(state, module))
	var signature: Dictionary = module.build_history_signature(state)
	var audit: Dictionary = audit_contract.normalize(
		module.audit_quality(state, signature)
	)
	return {
		"seed": int(state.get("seed")),
		"days": maxi(days, 0),
		"state": state,
		"ticks": ticks,
		"signature": signature,
		"signature_hash": _build_signature_hash(module, signature),
		"audit": audit,
	}


func tick_once(state: Variant, module: Variant) -> Dictionary:
	var fact_start := _value_size(state.get("world_facts"))
	var trace_start := _value_size(state.get("traces"))
	var memory_start := _value_size(state.get("memories"))
	var narratable_start := _value_size(state.get("narratable_states"))
	module.tick_module(state)
	var audit: Dictionary = audit_contract.normalize(
		module.audit_quality(state)
	)
	return {
		"day": int(state.get("day")),
		"created_fact_ids": _ids_since(
			state.get("world_facts") as Array,
			fact_start
		),
		"created_trace_ids": _ids_since(
			state.get("traces") as Array,
			trace_start
		),
		"created_memory_ids": _ids_since(
			state.get("memories") as Array,
			memory_start
		),
		"created_narratable_state_ids": _ids_since(
			state.get("narratable_states") as Array,
			narratable_start
		),
		"quality_flags": (
			audit.get("quality_flags", []) as Array
		).duplicate(),
	}


func run_seed_batch(
		module: Variant,
		seeds: Array,
		days: int
	) -> Dictionary:
	var results: Array[Dictionary] = []
	if (
		module == null
		or not module.has_method("create_state_for_seed")
	):
		return {
			"error": "module_missing_create_state_for_seed",
			"runs": results,
		}
	for seed_value: Variant in seeds:
		var seed := int(seed_value)
		var state: Variant = module.create_state_for_seed(seed)
		if state == null:
			continue
		var profile: Dictionary = {}
		if module.has_method("build_profile_for_seed"):
			profile = module.build_profile_for_seed(seed)
		results.append(run_days(state, module, days, profile))

	var reproducibility: Array[Dictionary] = []
	for index: int in range(mini(3, results.size())):
		var seed := int(results[index].get("seed", 0))
		var repeated_state: Variant = module.create_state_for_seed(seed)
		var repeated_profile: Dictionary = {}
		if module.has_method("build_profile_for_seed"):
			repeated_profile = module.build_profile_for_seed(seed)
		var repeated := run_days(
			repeated_state,
			module,
			days,
			repeated_profile
		)
		reproducibility.append({
			"seed": seed,
			"matches": (
				results[index].get("signature", {})
				== repeated.get("signature", {})
				and results[index].get("signature_hash", "")
				== repeated.get("signature_hash", "")
			),
		})

	var summary := build_batch_summary(results)
	summary["days"] = days
	summary["runs"] = results
	summary["reproducibility"] = reproducibility
	summary["all_reproducible"] = _all_reproducible(
		reproducibility
	)
	return summary


func build_batch_summary(results: Array) -> Dictionary:
	var unique_hashes: Dictionary = {}
	var outcome_counts: Dictionary = {}
	var unresolved_count := 0
	var dangling_count := 0
	var impossible_count := 0
	var fact_count := 0
	var trace_count := 0
	var memory_count := 0
	var narratable_count := 0
	for result_value: Variant in results:
		var result := result_value as Dictionary
		unique_hashes[String(result.get("signature_hash", ""))] = true
		var signature := result.get("signature", {}) as Dictionary
		var outcome := String(signature.get("outcome_class", ""))
		if outcome != "":
			outcome_counts[outcome] = (
				int(outcome_counts.get(outcome, 0)) + 1
			)
		var audit := result.get("audit", {}) as Dictionary
		unresolved_count += (
			1
			if bool(audit.get("unresolved_extreme_hunger", false))
			else 0
		)
		dangling_count += (
			1
			if bool(audit.get("dangling_major_fact", false))
			else 0
		)
		impossible_count += (
			1
			if bool(audit.get("impossible_shop_state", false))
			else 0
		)
		var state: Variant = result.get("state")
		if state != null:
			fact_count += _value_size(state.get("world_facts"))
			trace_count += _value_size(state.get("traces"))
			memory_count += _value_size(state.get("memories"))
			narratable_count += _value_size(
				state.get("narratable_states")
			)
	return {
		"seed_count": results.size(),
		"unique_signature_count": unique_hashes.size(),
		"outcome_counts": outcome_counts,
		"outcome_class_count": outcome_counts.size(),
		"unresolved_extreme_hunger_count": unresolved_count,
		"dangling_major_fact_count": dangling_count,
		"impossible_shop_state_count": impossible_count,
		"world_fact_count": fact_count,
		"trace_count": trace_count,
		"memory_count": memory_count,
		"narratable_state_count": narratable_count,
	}


func _ids_since(values: Array, start_index: int) -> Array:
	var output: Array[String] = []
	for index: int in range(start_index, values.size()):
		var value: Variant = values[index]
		if value is Dictionary:
			output.append(String((value as Dictionary).get("id", "")))
		elif value is Object:
			output.append(String((value as Object).get("id")))
	return output


func _value_size(value: Variant) -> int:
	return value.size() if value is Array else 0


func _build_signature_hash(
		module: Variant,
		signature: Dictionary
	) -> String:
	if module.has_method("build_history_hash"):
		return String(module.build_history_hash(signature))
	return JSON.stringify(signature).sha256_text().substr(0, 16)


func _all_reproducible(results: Array[Dictionary]) -> bool:
	for result: Dictionary in results:
		if not bool(result.get("matches", false)):
			return false
	return not results.is_empty()
