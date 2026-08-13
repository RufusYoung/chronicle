extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const SimRunnerModel = preload("res://scripts/sim/core/sim_runner.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const EntityStoreModel = preload("res://scripts/sim/entity/entity_store.gd")
const ItemStoreModel = preload("res://scripts/sim/item/item_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const RelationshipStoreModel = preload("res://scripts/sim/relationship/relationship_store.gd")
const MemoryStoreModel = preload("res://scripts/sim/memory/memory_store.gd")
const TraceStoreModel = preload("res://scripts/sim/trace/trace_store.gd")
const RumorStoreModel = preload("res://scripts/sim/rumor/rumor_store.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const EFFECT_TEMPLATES_PATH := "res://data/sim/raw/effect_templates/basic_effect_templates.json"
const RELATIONSHIP_AXIS_DEFS_PATH := "res://data/sim/raw/relationship_defs/relationship_axis_defs.json"
const ITEM_DEFS_PATH := "res://data/sim/raw/item_defs/basic_item_defs.json"
const SLOT_DEFS_PATH := (
	"res://data/sim/raw/equipment_slot_defs/basic_equipment_slot_defs.json"
)
const LAKE_TOWN_FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const SEVENTH_OUTPOST_FIXTURE_PATH := "res://data/sim/fixtures/seventh_outpost_ration_fixture.json"
const SEVENTH_OUTPOST_CONCEAL_SCENARIO_PATH := "res://data/sim/fixtures/scenarios/seventh_outpost_conceal_sequence.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw_rule_paths := [BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	var registry = SimRegistryModel.new()
	registry.load_raw_definition_files([ITEM_DEFS_PATH, SLOT_DEFS_PATH])
	registry.load_action_rules(raw_rule_paths)
	var rules: Array = registry.get_action_rules()
	var affordance_system = ActionAffordanceModel.new()
	var snapshot_builder = SimSnapshotBuilderModel.new()
	var transaction_resolver = TransactionResolverModel.new()
	var writer = TransactionWorldWriterModel.new()

	var effect_resolver = EffectTemplateResolverModel.new()
	effect_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)
	_check(
		not effect_resolver.get_template("give_food_help_effect").is_empty()
		and not effect_resolver.get_template("inquiry_concealed_item_effect").is_empty(),
		"1. 能加载 basic_effect_templates.json"
	)

	var outpost_context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	var outpost_stores := _make_stores(outpost_context, registry)
	var outpost_snapshot = snapshot_builder.build_snapshot(outpost_context, outpost_stores)
	var outpost_candidates: Array = affordance_system.generate_candidates(outpost_snapshot, rules)
	var ask_candidate = _find_candidate(outpost_candidates, "ask_about_concealed_item", "recruit_elai")
	var ask_template_result = effect_resolver.resolve_template(
		"inquiry_concealed_item_effect",
		ask_candidate,
		outpost_snapshot
	)
	_check(
		_result_has_fact(ask_template_result, "actor_asked_about_concealed_item"),
		"2. EffectTemplateResolver 能解析 inquiry_concealed_item_effect"
	)

	var ask_result = transaction_resolver.resolve_action(ask_candidate, outpost_snapshot)
	_check(
		not ask_result.is_empty(),
		"3. TransactionResolver 能接受 SimSnapshot"
	)
	_check(
		_result_has_fact(ask_result, "actor_asked_about_concealed_item"),
		"4. ask_about_concealed_item 基于 snapshot 产生 actor_asked_about_concealed_item"
	)
	_check(
		_result_has_memory(ask_result, "recruit_elai", "being_questioned_about_hidden_item"),
		"5. ask_about_concealed_item 产生 being_questioned_about_hidden_item memory"
	)
	_check(
		_relationship_delta_exists(ask_result, "recruit_elai", "player", "fear", 5),
		"6. ask_about_concealed_item 产生 target -> player fear +5"
	)

	var lake_context = SimContextModel.new(registry.load_json(LAKE_TOWN_FIXTURE_PATH))
	var lake_stores := _make_stores(lake_context, registry)
	var lake_snapshot = snapshot_builder.build_snapshot(lake_context, lake_stores)
	var lake_candidates: Array = affordance_system.generate_candidates(lake_snapshot, rules)
	var give_food_candidate = _find_candidate(lake_candidates, "give_food_to_hungry_person", "chen_mi")
	var give_food_result = transaction_resolver.resolve_action(give_food_candidate, lake_snapshot)
	writer.apply_result(give_food_result, lake_stores)
	_check(
		lake_stores["state_store"].get_state("chen_mi", "hunger") == "medium",
		"7. give_food_to_hungry_person 基于 snapshot 仍产生 hunger 降级"
	)

	var report_stores := _make_stores(outpost_context, registry)
	var report_snapshot = snapshot_builder.build_snapshot(outpost_context, report_stores)
	var report_candidates: Array = affordance_system.generate_candidates(report_snapshot, rules)
	var report_candidate = _find_candidate(
		report_candidates,
		"report_discipline_violation_to_superior",
		"recruit_elai"
	)
	var report_result = transaction_resolver.resolve_action(report_candidate, report_snapshot)
	_check(
		not report_result.traces_added.is_empty()
		and not report_result.rumors_added.is_empty()
		and not str(report_result.narrative_result.get("summary", "")).is_empty(),
		"8. report_discipline_violation_to_superior 基于 snapshot 仍产生 trace / rumor / narrative"
	)

	var runner = SimRunnerModel.new()
	var runner_result: Dictionary = runner.run_sequence(
		SEVENTH_OUTPOST_FIXTURE_PATH,
		SEVENTH_OUTPOST_CONCEAL_SCENARIO_PATH,
		raw_rule_paths
	)
	var world_log: Array = runner_result.get("world_log", [])
	_check(
		bool(runner_result.get("success", false))
		and world_log.size() >= 2
		and _entry_has_fact(world_log[0], "actor_asked_about_concealed_item"),
		"9. SimRunner 执行 conceal sequence 时，第一步不再是无事务写回"
	)
	_check(
		_entry_has_fact(world_log[0], "actor_asked_about_concealed_item"),
		"10. SimRunner WorldLog 中 conceal sequence 第一步包含 actor_asked_about_concealed_item"
	)
	_check(
		_all_entries_use_snapshot_resolver(world_log),
		"11. WorldLog entry 的 resolver_context_source 为 SimSnapshot"
	)

	_finish()


func _make_stores(context: Variant, registry: Variant) -> Dictionary:
	var entity_store = EntityStoreModel.new()
	entity_store.load_from_context(context)
	var fact_store = FactStoreModel.new()
	var item_store = ItemStoreModel.new()
	item_store.configure(
		registry.list_definitions("item"),
		entity_store,
		context.locations,
		fact_store
	)
	item_store.load_initial_items(
		(registry.load_json(
			LAKE_TOWN_FIXTURE_PATH
		).get("initial_items", []) as Array).duplicate(true)
		if str(context.fixture_id) == "lake_town_food_crisis"
		else (registry.load_json(
			SEVENTH_OUTPOST_FIXTURE_PATH
		).get("initial_items", []) as Array).duplicate(true)
	)
	var state_store = StateStoreModel.new()
	state_store.load_from_context(context)
	var relationship_store = RelationshipStoreModel.new()
	relationship_store.load_axis_defs(RELATIONSHIP_AXIS_DEFS_PATH)
	return {
		"entity_store": entity_store,
		"fact_store": fact_store,
		"state_store": state_store,
		"item_store": item_store,
		"relationship_store": relationship_store,
		"memory_store": MemoryStoreModel.new(),
		"trace_store": TraceStoreModel.new(),
		"rumor_store": RumorStoreModel.new(),
	}


func _find_candidate(candidates: Array, rule_id: String, target_id: String = "") -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) != rule_id:
			continue
		if target_id != "" and str(candidate.target_id) != target_id:
			continue
		return candidate
	return null


func _result_has_fact(result: Variant, fact_type: String) -> bool:
	for fact: Dictionary in result.facts_added:
		if str(fact.get("fact_type", "")) == fact_type:
			return true
	return false


func _result_has_memory(result: Variant, owner_id: String, memory_type: String) -> bool:
	for memory: Dictionary in result.memories_added:
		if (
			str(memory.get("owner_id", "")) == owner_id
			and str(memory.get("memory_type", "")) == memory_type
		):
			return true
	return false


func _relationship_delta_exists(
	result: Variant,
	source_id: String,
	target_id: String,
	axis: String,
	delta: int
) -> bool:
	for change: Dictionary in result.relationship_changes:
		if (
			str(change.get("source_id", "")) == source_id
			and str(change.get("target_id", "")) == target_id
			and str(change.get("axis", "")) == axis
			and int(change.get("delta", 0)) == delta
		):
			return true
	return false


func _entry_has_fact(entry: Dictionary, fact_type: String) -> bool:
	return fact_type in (entry.get("facts_added", []) as Array)


func _all_entries_use_snapshot_resolver(entries: Array) -> bool:
	for entry: Dictionary in entries:
		if str(entry.get("resolver_context_source", "")) != "SimSnapshot":
			return false
	return true


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE FAIL] " + failure)
		print("[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 SNAPSHOT TRANSACTION EFFECT TEMPLATE PASS] " + message)
	else:
		failures.append(message)
