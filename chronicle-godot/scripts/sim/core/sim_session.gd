extends RefCounted
class_name V5SimSession

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const TravelResolverModel = preload("res://scripts/sim/travel/travel_resolver.gd")
const ChallengeResolverModel = preload(
	"res://scripts/sim/challenge/challenge_resolver.gd"
)
const ReturnEchoResolverModel = preload(
	"res://scripts/sim/echo/return_echo_resolver.gd"
)
const InvestigationResolverModel = preload(
	"res://scripts/sim/investigation/investigation_resolver.gd"
)
const WorldTickAdapterModel = preload(
	"res://scripts/sim/world_tick/world_tick_adapter.gd"
)
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const EntityStoreModel = preload("res://scripts/sim/entity/entity_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const CharacterFeatureStoreModel = preload(
	"res://scripts/sim/character_feature/character_feature_store.gd"
)
const RelationshipStoreModel = preload("res://scripts/sim/relationship/relationship_store.gd")
const MemoryStoreModel = preload("res://scripts/sim/memory/memory_store.gd")
const TraceStoreModel = preload("res://scripts/sim/trace/trace_store.gd")
const RumorStoreModel = preload("res://scripts/sim/rumor/rumor_store.gd")
const PressureStoreModel = preload("res://scripts/sim/pressure/pressure_store.gd")
const ObligationStoreModel = preload("res://scripts/sim/obligation/obligation_store.gd")
const ExchangeStoreModel = preload("res://scripts/sim/exchange/exchange_store.gd")
const ItemStoreModel = preload("res://scripts/sim/item/item_store.gd")
const ChronicleStoreModel = preload(
	"res://scripts/sim/chronicle/chronicle_store.gd"
)
const InvestigationLeadStoreModel = preload(
	"res://scripts/sim/investigation/investigation_lead_store.gd"
)
const DeferredConsequenceStoreModel = preload(
	"res://scripts/sim/deferred/deferred_consequence_store.gd"
)

const RELATIONSHIP_AXIS_DEFS_PATH := (
	"res://data/sim/raw/relationship_defs/relationship_axis_defs.json"
)
const STATE_DEFS_PATH := "res://data/sim/raw/state_defs/basic_state_defs.json"
const OBJECT_DEFS_PATH := "res://data/sim/raw/object_defs/basic_object_defs.json"
const CHARACTER_FEATURE_DEFS_PATH := (
	"res://data/sim/raw/character_feature_defs/basic_character_feature_defs.json"
)
const AUTONOMOUS_ACTION_RULES_PATH := (
	"res://data/sim/raw/npc_action_rules/basic_npc_action_rules.json"
)
const NPC_NEED_PROFILES_PATH := (
	"res://data/sim/raw/npc_need_profiles/basic_npc_need_profiles.json"
)

var registry: Variant = null
var context: Variant = null
var rules: Array = []
var stores: Dictionary = {}
var world_log: Variant = null
var snapshot_builder: Variant = null
var affordance_system: Variant = null
var resolver: Variant = null
var writer: Variant = null
var travel_resolver: Variant = null
var challenge_resolver: Variant = null
var return_echo_resolver: Variant = null
var investigation_resolver: Variant = null
var world_tick_adapter: Variant = null
var autonomous_action_rules: Array = []
var npc_need_profiles: Array = []
var travel_routes: Array = []
var challenge_definitions: Array = []
var return_echo_definitions: Array = []
var investigation_definitions: Array = []
var challenge_rng: RandomNumberGenerator = RandomNumberGenerator.new()

var fixture_id: String = ""
var initialized: bool = false
var action_count: int = 0
var travel_count: int = 0
var challenge_count: int = 0
var challenge_preparation_count: int = 0
var return_echo_count: int = 0
var investigation_count: int = 0
var investigation_defer_count: int = 0
var candidate_generation_count: int = 0
var world_tick_count: int = 0
var current_day: int = 1
var current_hour: int = 8
var elapsed_hours_since_start: int = 0


func start_from_fixture_path(fixture_path: String, raw_rule_paths: Array) -> Dictionary:
	var loader = SimRegistryModel.new()
	var fixture: Dictionary = loader.load_json(fixture_path)
	if fixture.is_empty():
		_reset_runtime()
		return _start_failure("fixture_not_loaded")
	return start_from_fixture_data(fixture, raw_rule_paths)


func start_from_fixture_data(fixture: Dictionary, raw_rule_paths: Array) -> Dictionary:
	_reset_runtime()
	if fixture.is_empty():
		return _start_failure("fixture_not_loaded")

	var definition_report: Dictionary = registry.load_raw_definition_files([
		STATE_DEFS_PATH,
		OBJECT_DEFS_PATH,
		CHARACTER_FEATURE_DEFS_PATH,
	])
	if not bool(definition_report.get("ok", false)):
		var failed := _start_failure("raw_definition_contract_invalid")
		failed["definition_report"] = definition_report
		return failed
	registry.load_action_rules(raw_rule_paths)
	rules = registry.get_action_rules()
	context = SimContextModel.new(fixture)
	fixture_id = str(fixture.get("fixture_id", ""))
	if fixture_id == "":
		return _start_failure("missing_fixture_id")

	_configure_world_time(fixture)
	travel_routes = (fixture.get("travel_routes", []) as Array).duplicate(true)
	challenge_definitions = (
		fixture.get("challenges", []) as Array
	).duplicate(true)
	return_echo_definitions = (
		fixture.get("return_echoes", []) as Array
	).duplicate(true)
	investigation_definitions = (
		fixture.get("investigations", []) as Array
	).duplicate(true)
	var autonomous_rule_data: Dictionary = registry.load_json(
		AUTONOMOUS_ACTION_RULES_PATH
	)
	autonomous_action_rules = (
		autonomous_rule_data.get("rules", []) as Array
	).duplicate(true)
	autonomous_action_rules.append_array(
		(fixture.get("autonomous_action_rules", []) as Array).duplicate(true)
	)
	var need_profile_data: Dictionary = registry.load_json(
		NPC_NEED_PROFILES_PATH
	)
	npc_need_profiles = (
		need_profile_data.get("profiles", []) as Array
	).duplicate(true)
	npc_need_profiles.append_array(
		(fixture.get("npc_need_profiles", []) as Array).duplicate(true)
	)
	world_tick_adapter.configure_autonomous_actions(
		autonomous_action_rules
	)
	world_tick_adapter.configure_need_profiles(npc_need_profiles)
	challenge_rng.seed = int(fixture.get("challenge_seed", 1))
	_create_stores(fixture)
	var entity_report: Dictionary = stores["entity_store"].get_contract_report()
	var state_report: Dictionary = stores["state_store"].get_contract_report()
	var character_feature_report: Dictionary = stores[
		"character_feature_store"
	].get_contract_report()
	if not bool(entity_report.get("ok", false)) or not bool(
		state_report.get("ok", false)
	) or not bool(character_feature_report.get("ok", false)):
		var failed := _start_failure("fixture_store_contract_invalid")
		failed["entity_report"] = entity_report
		failed["state_report"] = state_report
		failed["character_feature_report"] = character_feature_report
		return failed
	context.release_runtime_sources()
	initialized = true
	return {
		"success": true,
		"fixture_id": fixture_id,
		"rule_count": rules.size(),
		"challenge_definition_count": challenge_definitions.size(),
		"return_echo_definition_count": return_echo_definitions.size(),
		"investigation_definition_count": investigation_definitions.size(),
		"autonomous_action_rule_count": autonomous_action_rules.size(),
		"npc_need_profile_count": npc_need_profiles.size(),
		"candidate_count": get_action_candidates().size(),
		"definition_count": int(definition_report.get(
			"total_definition_count",
			0
		)),
		"definition_report": definition_report,
		"entity_contract_report": entity_report,
		"state_contract_report": state_report,
		"character_feature_contract_report": character_feature_report,
		"time": get_time_summary(),
	}


func is_ready() -> bool:
	return initialized


func get_snapshot() -> Variant:
	if not initialized:
		return null
	return snapshot_builder.build_snapshot(context, stores)


func get_action_candidates() -> Array:
	var snapshot: Variant = get_snapshot()
	if snapshot == null:
		return []
	return affordance_system.generate_candidates(snapshot, rules)


func get_action_options() -> Array:
	var rows: Array = []
	for candidate: Variant in get_action_candidates():
		rows.append(candidate.to_dict())
	return rows


func get_travel_options() -> Array:
	if not initialized:
		return []
	var rows: Array = []
	var snapshot: Variant = get_snapshot()
	var food_count := int(snapshot.get_player_value("food_count", 0))
	for route: Dictionary in travel_routes:
		if str(route.get("from_location_id", "")) != context.location_id:
			continue
		if not _route_discovery_requirements_met(route, snapshot):
			continue
		var to_location_id := str(route.get("to_location_id", ""))
		var destination: Dictionary = context.get_location(to_location_id)
		var route_food_cost := int(route.get("food_cost", 0))
		var food_cost := maxi(route_food_cost, 0)
		var access_contract_valid := _route_access_contract_valid(route)
		var access_allowed := _route_access_time_allows(route)
		var required_items_ready := _route_required_items_met(
			route,
			snapshot
		)
		var can_travel := (
			not destination.is_empty()
			and int(route.get("hours", 0)) > 0
			and route_food_cost >= 0
			and food_count >= food_cost
			and access_contract_valid
			and access_allowed
			and required_items_ready
		)
		rows.append({
			"route_id": str(route.get("route_id", "")),
			"from_location_id": context.location_id,
			"to_location_id": to_location_id,
			"destination_name": str(
				destination.get("display_name", to_location_id)
			),
			"label": str(route.get("label", "前往新的地点")),
			"hours": int(route.get("hours", 0)),
			"food_cost": food_cost,
			"access_hint": str(route.get("access_hint", "")),
			"can_travel": can_travel,
			"blocked_reason": (
				"" if can_travel else _travel_blocked_reason(
					route,
					destination,
					int(route.get("hours", 0)),
					food_count,
					route_food_cost,
					snapshot
				)
			),
		})
	return rows


func get_challenge_options() -> Array:
	if not initialized:
		return []
	var snapshot: Variant = get_snapshot()
	var rows: Array = []
	for challenge: Dictionary in challenge_definitions:
		if str(challenge.get("location_id", "")) != context.location_id:
			continue
		if not _challenge_requirements_met(challenge, snapshot):
			continue
		var target_id := str(challenge.get("target_entity_id", ""))
		if snapshot.get_entity(target_id).is_empty():
			continue
		var status_key := str(
			challenge.get("status_state_key", "challenge_status")
		)
		var available_status := str(
			challenge.get("available_status", "available")
		)
		if str(snapshot.get_entity_state(
			target_id,
			status_key,
			available_status
		)) != available_status:
			continue

		var preparation: Dictionary = challenge.get("preparation", {})
		var preparation_state_key := str(
			preparation.get("state_key", "prepared")
		)
		var prepared := bool(snapshot.get_entity_state(
			target_id,
			preparation_state_key,
			false
		))
		var stat_key := str(challenge.get("stat_key", "perception"))
		var stat_value := int(snapshot.get_player_value(stat_key, 0))
		var preparation_bonus := int(preparation.get("bonus", 0))
		var check_text := "d%d + %s %d%s / 难度 %d" % [
			int(challenge.get("die_sides", 20)),
			str(challenge.get("stat_label", stat_key)),
			stat_value,
			(
				" + 准备 %d" % preparation_bonus
				if prepared
				else ""
			),
			int(challenge.get("difficulty", 10)),
		]
		if not prepared and not preparation.is_empty():
			rows.append({
				"option_id": str(preparation.get(
					"option_id",
					"prepare:%s" % str(challenge.get("challenge_id", ""))
				)),
				"challenge_id": str(challenge.get("challenge_id", "")),
				"option_type": "prepare",
				"action_type": "preparation",
				"label": str(preparation.get("label", "[准备] 检查危险")),
				"hours": int(preparation.get("hours", 1)),
				"risk_label": str(challenge.get("risk_label", "未知")),
				"risk_description": str(
					challenge.get("risk_description", "")
				),
				"check_text": check_text,
				"preparation_only": bool(
					challenge.get("preparation_only", false)
				),
				"preparation_applied": false,
				"preparation_bonus": preparation_bonus,
				"can_execute": true,
				"blocked_reason": "",
			})

		if not bool(challenge.get("preparation_only", false)):
			var attempt: Dictionary = challenge.get("attempt", {})
			rows.append({
				"option_id": str(attempt.get(
					"option_id",
					"attempt:%s" % str(challenge.get("challenge_id", ""))
				)),
				"challenge_id": str(challenge.get("challenge_id", "")),
				"option_type": "attempt",
				"action_type": "danger",
				"label": str(attempt.get("label", "[危险] 尝试进入")),
				"hours": int(
					attempt.get("hours", challenge.get("hours", 1))
				),
				"risk_label": str(challenge.get("risk_label", "未知")),
				"risk_description": str(
					challenge.get("risk_description", "")
				),
				"check_text": check_text,
				"preparation_applied": prepared,
				"preparation_bonus": preparation_bonus if prepared else 0,
				"success_hint": str(
					(challenge.get("success", {}) as Dictionary).get(
						"hint",
						""
					)
				),
				"failure_hint": str(
					(challenge.get("failure", {}) as Dictionary).get(
						"hint",
						""
					)
				),
				"can_execute": true,
				"blocked_reason": "",
			})
	return rows


func get_return_echo_options() -> Array:
	if not initialized:
		return []
	var snapshot: Variant = get_snapshot()
	var rows: Array = []
	for definition: Dictionary in return_echo_definitions:
		if not _return_echo_is_available(definition, snapshot):
			continue
		var target_id := str(definition.get("target_entity_id", ""))
		var target: Dictionary = snapshot.get_entity(target_id)
		var item_id := str(definition.get("required_item_id", ""))
		var item: Dictionary = snapshot.get_item(item_id)
		rows.append({
			"option_id": str(
				definition.get(
					"option_id",
					"return_echo:%s"
					% str(definition.get("echo_id", ""))
				)
			),
			"echo_id": str(definition.get("echo_id", "")),
			"target_entity_id": target_id,
			"target_display_name": str(
				target.get("display_name", target_id)
			),
			"item_id": item_id,
			"item_display_name": str(
				item.get("display_name", item_id)
			),
			"label": str(
				definition.get("label", "[旧物] 请对方辨认")
			),
			"hours": int(definition.get("hours", 1)),
			"action_type": "relic",
			"hint": str(
				definition.get(
					"hint",
					"让眼前的人辨认你从旅途中带回的旧物。"
				)
			),
			"can_execute": true,
			"blocked_reason": "",
		})
	return rows


func execute_return_echo_option(
		option_id: String,
		metadata: Dictionary = {}
) -> Dictionary:
	if not initialized:
		return _return_echo_failure(
			"session_not_initialized",
			option_id
		)
	var option := _find_return_echo_option(option_id)
	if option.is_empty():
		return _return_echo_failure(
			"return_echo_option_not_found",
			option_id
		)
	var definition := _find_return_echo_definition(
		str(option.get("echo_id", ""))
	)
	if definition.is_empty():
		return _return_echo_failure(
			"return_echo_definition_not_found",
			option_id
		)
	var hours := int(option.get("hours", 1))
	if hours <= 0:
		return _return_echo_failure(
			"invalid_return_echo_hours",
			option_id
		)

	var tick_result := advance_time(
		hours,
		"after_return_echo",
		{
			"scope_type": "location",
			"scope_id": context.location_id,
			"source": str(
				metadata.get(
					"source",
					"SimSession.execute_return_echo_option"
				)
			),
			"label": str(option.get("label", "辨认旧物")),
		}
	)
	if not bool(tick_result.get("success", false)):
		return _return_echo_failure(
			str(tick_result.get("error_reason", "world_tick_failed")),
			option_id
		)

	var transaction_result: Variant = return_echo_resolver.resolve(
		definition,
		get_snapshot(),
		return_echo_count + 1,
		get_time_summary()
	)
	if str(transaction_result.contract_status) == "invalid_contract":
		return _return_echo_failure(
			str(transaction_result.error_reason),
			option_id
		)
	writer.apply_result(transaction_result, stores)

	var event_id := return_echo_count + 1
	var log_entry := _build_return_echo_log_entry(
		option,
		transaction_result,
		event_id
	)
	world_log.append_entry(log_entry)
	return_echo_count += 1
	return {
		"success": true,
		"error": "",
		"fixture_id": fixture_id,
		"option_id": option_id,
		"echo_id": str(option.get("echo_id", "")),
		"item_id": str(option.get("item_id", "")),
		"target_id": str(option.get("target_entity_id", "")),
		"transaction_result": transaction_result.to_dict(),
		"tick_result": tick_result,
		"world_log_entry": log_entry.duplicate(true),
		"time": get_time_summary(),
		"return_echo_count": return_echo_count,
		"store_summary": get_store_summary(),
	}


func get_investigation_options() -> Array:
	if not initialized:
		return []
	var snapshot: Variant = get_snapshot()
	var rows: Array = []
	for lead: Dictionary in snapshot.get_open_investigation_leads():
		var definition := _find_investigation_definition(
			str(lead.get("lead_id", ""))
		)
		if (
			definition.is_empty()
			or not _investigation_lead_is_available(
				definition,
				lead,
				snapshot
			)
		):
			continue
		var investigate: Dictionary = definition.get("investigate", {})
		if not investigate.is_empty():
			rows.append(_investigation_option_row(
				investigate,
				lead
			))
		var defer: Dictionary = definition.get("defer", {})
		if (
			str(lead.get("disposition", "fresh")) == "fresh"
			and not defer.is_empty()
		):
			rows.append(_investigation_option_row(defer, lead))
	return rows


func execute_investigation_option(
		option_id: String,
		metadata: Dictionary = {}
) -> Dictionary:
	if not initialized:
		return _investigation_failure(
			"session_not_initialized",
			option_id
		)
	var option := _find_investigation_option(option_id)
	if option.is_empty():
		return _investigation_failure(
			"investigation_option_not_found",
			option_id
		)
	var lead_id := str(option.get("lead_id", ""))
	var lead: Dictionary = get_snapshot().get_investigation_lead(
		lead_id
	)
	var definition := _find_investigation_definition(lead_id)
	if lead.is_empty() or definition.is_empty():
		return _investigation_failure(
			"investigation_definition_not_found",
			option_id
		)
	var hours := int(option.get("hours", 0))
	if hours <= 0:
		return _investigation_failure(
			"invalid_investigation_hours",
			option_id
		)

	var option_type := str(option.get("option_type", ""))
	var tick_result := advance_time(
		hours,
		"after_investigation_%s" % option_type,
		{
			"scope_type": "location",
			"scope_id": context.location_id,
			"source": str(
				metadata.get(
					"source",
					"SimSession.execute_investigation_option"
				)
			),
			"label": str(option.get("label", "处理调查方向")),
		}
	)
	if not bool(tick_result.get("success", false)):
		return _investigation_failure(
			str(tick_result.get("error_reason", "world_tick_failed")),
			option_id
		)

	var event_id := (
		investigation_count
		+ investigation_defer_count
		+ 1
	)
	var transaction_result: Variant = investigation_resolver.resolve(
		definition,
		lead,
		option_type,
		get_snapshot(),
		event_id,
		get_time_summary()
	)
	if str(transaction_result.contract_status) == "invalid_contract":
		return _investigation_failure(
			str(transaction_result.error_reason),
			option_id
		)
	writer.apply_result(transaction_result, stores)

	var log_entry := _build_investigation_log_entry(
		option,
		transaction_result,
		event_id
	)
	world_log.append_entry(log_entry)
	if option_type == "defer":
		investigation_defer_count += 1
	else:
		investigation_count += 1
	return {
		"success": true,
		"error": "",
		"fixture_id": fixture_id,
		"option_id": option_id,
		"option_type": option_type,
		"lead_id": lead_id,
		"transaction_result": transaction_result.to_dict(),
		"tick_result": tick_result,
		"world_log_entry": log_entry.duplicate(true),
		"time": get_time_summary(),
		"investigation_count": investigation_count,
		"investigation_defer_count": investigation_defer_count,
		"store_summary": get_store_summary(),
	}


func execute_challenge_option(
		option_id: String,
		metadata: Dictionary = {}
) -> Dictionary:
	if not initialized:
		return _challenge_failure("session_not_initialized", option_id)
	var option := _find_challenge_option(option_id)
	if option.is_empty():
		return _challenge_failure("challenge_option_not_found", option_id)
	var challenge := _find_challenge_definition(
		str(option.get("challenge_id", ""))
	)
	if challenge.is_empty():
		return _challenge_failure("challenge_not_found", option_id)

	var option_type := str(option.get("option_type", ""))
	var die_sides := int(challenge.get("die_sides", 20))
	var roll := 0
	if option_type == "attempt":
		if metadata.has("roll_override"):
			if str(metadata.get("source", "")) != "test_injection":
				return _challenge_failure(
					"roll_override_requires_test_injection",
					option_id
				)
			roll = int(metadata.get("roll_override", 0))
			if roll < 1 or roll > die_sides:
				return _challenge_failure("invalid_roll_override", option_id)
		else:
			roll = challenge_rng.randi_range(1, die_sides)
	elif option_type != "prepare":
		return _challenge_failure("invalid_challenge_option", option_id)

	var hours := int(option.get("hours", 1))
	if hours <= 0:
		return _challenge_failure("invalid_challenge_hours", option_id)
	var tick_result := advance_time(
		hours,
		"after_challenge_%s" % option_type,
		{
			"scope_type": "location",
			"scope_id": context.location_id,
			"source": "SimSession.execute_challenge_option",
			"label": str(option.get("label", "challenge")),
		}
	)
	if not bool(tick_result.get("success", false)):
		return _challenge_failure(
			str(tick_result.get("error_reason", "world_tick_failed")),
			option_id
		)

	var snapshot: Variant = get_snapshot()
	var event_id := challenge_count + challenge_preparation_count + 1
	var transaction_result: Variant
	if option_type == "prepare":
		transaction_result = challenge_resolver.resolve_preparation(
			challenge,
			snapshot,
			event_id
		)
	else:
		transaction_result = challenge_resolver.resolve_attempt(
			challenge,
			snapshot,
			roll,
			event_id,
			get_time_summary()
		)
	writer.apply_result(transaction_result, stores)

	var log_entry := _build_challenge_log_entry(
		option,
		transaction_result,
		event_id
	)
	world_log.append_entry(log_entry)
	if option_type == "prepare":
		challenge_preparation_count += 1
	else:
		challenge_count += 1

	var narrative: Dictionary = transaction_result.narrative_result
	return {
		"success": str(transaction_result.contract_status)
			!= "invalid_contract",
		"error": str(transaction_result.error_reason),
		"fixture_id": fixture_id,
		"option_id": option_id,
		"challenge_id": str(option.get("challenge_id", "")),
		"option_type": option_type,
		"outcome": str(narrative.get("outcome", "")),
		"hours": hours,
		"roll": roll,
		"transaction_result": transaction_result.to_dict(),
		"tick_result": tick_result,
		"world_log_entry": log_entry.duplicate(true),
		"time": get_time_summary(),
		"challenge_count": challenge_count,
		"challenge_preparation_count": challenge_preparation_count,
		"store_summary": get_store_summary(),
	}


func travel(route_id: String, metadata: Dictionary = {}) -> Dictionary:
	if not initialized:
		return _travel_failure("session_not_initialized", route_id)

	var route := _find_travel_route(route_id, context.location_id)
	if route.is_empty():
		return _travel_failure("route_not_found", route_id)
	if not _route_discovery_requirements_met(route, get_snapshot()):
		return _travel_failure("route_not_discovered", route_id)

	var to_location_id := str(route.get("to_location_id", ""))
	var destination: Dictionary = context.get_location(to_location_id)
	var hours := int(route.get("hours", 0))
	var food_cost := int(route.get("food_cost", 0))
	if destination.is_empty():
		return _travel_failure("destination_not_found", route_id)
	if (
		hours <= 0
		or food_cost < 0
		or not _route_access_contract_valid(route)
	):
		return _travel_failure("invalid_route_contract", route_id)
	if not _route_access_time_allows(route):
		return _travel_failure("outside_access_window", route_id)
	var pre_travel_snapshot: Variant = get_snapshot()
	if not _route_required_items_met(route, pre_travel_snapshot):
		return _travel_failure("missing_required_item", route_id)
	if int(pre_travel_snapshot.get_player_value("food_count", 0)) < food_cost:
		return _travel_failure("insufficient_food", route_id)

	var from_location_id: String = str(context.location_id)
	var tick_metadata := {
		"scope_type": "location",
		"scope_id": from_location_id,
		"source": "SimSession.travel",
		"label": str(route.get("label", "travel")),
		"time_key": str(route.get("time_key", "after_route_travel")),
		"include_due_checks": true,
	}
	var raw_tick_metadata: Variant = metadata.get("tick_metadata", {})
	if not raw_tick_metadata is Dictionary:
		return _travel_failure("invalid_tick_metadata", route_id)
	tick_metadata.merge(
		(raw_tick_metadata as Dictionary),
		true
	)
	tick_metadata["scope_type"] = "location"
	tick_metadata["scope_id"] = from_location_id
	var tick_result := advance_time(
		hours,
		str(route.get("trigger_key", "after_route_travel")),
		tick_metadata
	)
	if not bool(tick_result.get("success", false)):
		return _travel_failure(
			str(tick_result.get("error_reason", "world_tick_failed")),
			route_id
		)

	var snapshot: Variant = get_snapshot()
	var transaction_result: Variant = travel_resolver.resolve(
		route,
		snapshot,
		travel_count + 1
	)
	writer.apply_result(transaction_result, stores)
	if not context.set_current_location(to_location_id):
		return _travel_failure("destination_switch_failed", route_id)

	var log_entry := _build_travel_log_entry(
		route,
		transaction_result,
		travel_count
	)
	world_log.append_entry(log_entry)
	travel_count += 1
	return {
		"success": true,
		"error": "",
		"fixture_id": fixture_id,
		"route_id": route_id,
		"from_location_id": from_location_id,
		"to_location_id": to_location_id,
		"destination": destination.duplicate(true),
		"hours": hours,
		"food_cost": food_cost,
		"transaction_result": transaction_result.to_dict(),
		"tick_result": tick_result,
		"world_log_entry": log_entry.duplicate(true),
		"time": get_time_summary(),
		"travel_count": travel_count,
		"store_summary": get_store_summary(),
	}


func execute_action(action_id: String, metadata: Dictionary = {}) -> Dictionary:
	if not initialized:
		return _execution_failure("session_not_initialized", action_id)

	var snapshot: Variant = get_snapshot()
	var candidates: Array = affordance_system.generate_candidates(snapshot, rules)
	candidate_generation_count += 1
	var candidate: Variant = _find_candidate_by_action_id(candidates, action_id)
	if candidate == null:
		return _candidate_not_found(action_id, "", "", candidates)
	if not bool(candidate.can_execute):
		return _candidate_blocked(candidate, candidates.size())
	return _execute_candidate(snapshot, candidate, candidates.size(), metadata)


func execute_selection(
		rule_id: String,
		target_id: String = "",
		metadata: Dictionary = {}
) -> Dictionary:
	if not initialized:
		return _execution_failure("session_not_initialized", "")

	var snapshot: Variant = get_snapshot()
	var candidates: Array = affordance_system.generate_candidates(snapshot, rules)
	candidate_generation_count += 1
	var candidate: Variant = _find_candidate(candidates, rule_id, target_id)
	if candidate == null:
		return _candidate_not_found("", rule_id, target_id, candidates)
	if not bool(candidate.can_execute):
		return _candidate_blocked(candidate, candidates.size())
	return _execute_candidate(snapshot, candidate, candidates.size(), metadata)


func advance_time(
		hours: int,
		trigger_key: String,
		metadata: Dictionary = {}
) -> Dictionary:
	if not initialized:
		return _tick_failure("session_not_initialized")
	if hours <= 0:
		return _tick_failure("invalid_elapsed_hours")

	var scope_type := str(metadata.get("scope_type", "location"))
	var scope_id := str(metadata.get("scope_id", context.location_id))
	var next_time := _projected_time(hours)
	var due_kinds_value: Variant = metadata.get(
		"due_kinds",
		["obligation", "exchange"]
	)
	if not (due_kinds_value is Array):
		return _tick_failure("invalid_due_kinds")
	var due_kinds: Array = (due_kinds_value as Array).duplicate(true)
	var tick_event := {
		"tick_event_id": str(metadata.get(
			"tick_event_id",
			"%s_time_%d" % [fixture_id, world_tick_count + 1]
		)),
		"tick_type": "time_event",
		"trigger_key": trigger_key,
		"scope_type": scope_type,
		"scope_id": scope_id,
		"day": int(next_time.get("day", current_day)),
		"time_key": str(metadata.get("time_key", trigger_key)),
		"source": str(metadata.get("source", "SimSession.advance_time")),
		"label": str(metadata.get("label", "advance time")),
		"elapsed_hours": hours,
		"max_triggers": int(metadata.get("max_triggers", 0)),
		"include_due_checks": bool(metadata.get("include_due_checks", true)),
		"due_kinds": due_kinds,
	}
	return advance_world(tick_event, hours)


func advance_world(tick_event: Dictionary, elapsed_hours_delta: int = 0) -> Dictionary:
	if not initialized:
		return _tick_failure("session_not_initialized")

	var result: Dictionary = world_tick_adapter.apply_tick_event(
		context,
		stores,
		tick_event
	)
	for entry: Dictionary in result.get("world_log_entries", []):
		world_log.append_entry(entry)

	if bool(result.get("success", false)):
		_advance_clock(maxi(elapsed_hours_delta, 0))
		world_tick_count += 1

	result["fixture_id"] = fixture_id
	result["time"] = get_time_summary()
	result["world_tick_count"] = world_tick_count
	result["session_world_log_summary"] = get_world_log_summary()
	return result


func get_time_summary() -> Dictionary:
	return {
		"day": current_day,
		"hour": current_hour,
		"world_tick_count": world_tick_count,
		"elapsed_hours": elapsed_hours_since_start,
	}


func get_world_log_entries() -> Array:
	if world_log == null:
		return []
	return world_log.list_entries()


func get_world_log_summary() -> Dictionary:
	if world_log == null:
		return {}
	return world_log.summary()


func get_store_summary() -> Dictionary:
	if not initialized:
		return _empty_store_summary()
	return {
		"entities": stores["entity_store"].list_entities().size(),
		"facts": stores["fact_store"].list_facts().size(),
		"states": _count_states(stores["state_store"]),
		"character_features": _count_character_features(
			stores["character_feature_store"]
		),
		"relationships": _count_relationship_axes(stores["relationship_store"]),
		"memories": stores["memory_store"].memories.size(),
		"traces": stores["trace_store"].list_traces().size(),
		"rumors": stores["rumor_store"].list_rumors().size(),
		"pressures": stores["pressure_store"].list_pressures().size(),
		"obligations": stores["obligation_store"].list_obligations().size(),
		"exchanges": stores["exchange_store"].list_exchanges().size(),
		"items": stores["item_store"].list_items().size(),
		"chronicle_entries": (
			stores["chronicle_store"].list_entries().size()
		),
		"investigation_leads": (
			stores["investigation_store"].list_leads().size()
		),
		"deferred_consequences": (
			stores["deferred_consequence_store"]
			.list_deferred_consequences()
			.size()
		),
	}


func get_store_snapshots() -> Dictionary:
	if not initialized:
		return {}
	return {
		"entities": stores["entity_store"].list_entities(),
		"facts": stores["fact_store"].list_facts(),
		"states": stores["state_store"].states.duplicate(true),
		"talent_assignments": stores[
			"character_feature_store"
		].list_talent_assignments(),
		"trait_instances": stores[
			"character_feature_store"
		].list_trait_instances(),
		"mark_instances": stores[
			"character_feature_store"
		].list_mark_instances(),
		"skill_progress": stores[
			"character_feature_store"
		].list_skill_progress(),
		"relationships": stores["relationship_store"].relations.duplicate(true),
		"memories": stores["memory_store"].memories.duplicate(true),
		"traces": stores["trace_store"].list_traces(),
		"rumors": stores["rumor_store"].list_rumors(),
		"pressures": stores["pressure_store"].list_pressures(),
		"obligations": stores["obligation_store"].list_obligations(),
		"exchanges": stores["exchange_store"].list_exchanges(),
		"items": stores["item_store"].list_items(),
		"chronicle_entries": stores["chronicle_store"].list_entries(),
		"investigation_leads": stores["investigation_store"].list_leads(),
		"deferred_consequences": (
			stores["deferred_consequence_store"].list_deferred_consequences()
		),
	}


func build_result_summary(extra: Dictionary = {}) -> Dictionary:
	if not initialized:
		var failed := {
			"fixture_id": fixture_id,
			"success": false,
			"error": "session_not_initialized",
			"steps_executed": action_count,
			"world_log": get_world_log_entries(),
			"store_summary": get_store_summary(),
		}
		failed.merge(extra, true)
		return failed

	var final_snapshot: Variant = get_snapshot()
	var final_candidates: Array = affordance_system.generate_candidates(final_snapshot, rules)
	var result := {
		"fixture_id": fixture_id,
		"success": true,
		"steps_executed": action_count,
		"journeys_completed": travel_count,
		"challenges_resolved": challenge_count,
		"challenge_preparations": challenge_preparation_count,
		"return_echoes_resolved": return_echo_count,
		"investigations_resolved": investigation_count,
		"investigations_deferred": investigation_defer_count,
		"world_ticks_executed": world_tick_count,
		"time": get_time_summary(),
		"candidate_selection_source": "ActionAffordanceSystem",
		"candidate_context_source": "SimSnapshot",
		"resolver_context_source": "SimSnapshot",
		"candidate_generation_count": candidate_generation_count,
		"world_log": get_world_log_entries(),
		"world_log_summary": get_world_log_summary(),
		"snapshot_summary": _snapshot_summary(final_snapshot, final_candidates),
		"store_summary": get_store_summary(),
		"store_snapshots": get_store_snapshots(),
	}
	result.merge(extra, true)
	return result


func _reset_runtime() -> void:
	registry = SimRegistryModel.new()
	context = null
	rules = []
	stores = {}
	world_log = SimWorldLogModel.new()
	snapshot_builder = SimSnapshotBuilderModel.new()
	affordance_system = ActionAffordanceModel.new()
	resolver = TransactionResolverModel.new()
	writer = TransactionWorldWriterModel.new()
	travel_resolver = TravelResolverModel.new()
	challenge_resolver = ChallengeResolverModel.new()
	return_echo_resolver = ReturnEchoResolverModel.new()
	investigation_resolver = InvestigationResolverModel.new()
	world_tick_adapter = WorldTickAdapterModel.new()
	autonomous_action_rules = []
	npc_need_profiles = []
	travel_routes = []
	challenge_definitions = []
	return_echo_definitions = []
	investigation_definitions = []
	challenge_rng = RandomNumberGenerator.new()
	fixture_id = ""
	initialized = false
	action_count = 0
	travel_count = 0
	challenge_count = 0
	challenge_preparation_count = 0
	return_echo_count = 0
	investigation_count = 0
	investigation_defer_count = 0
	candidate_generation_count = 0
	world_tick_count = 0
	current_day = 1
	current_hour = 8
	elapsed_hours_since_start = 0


func _create_stores(fixture: Dictionary) -> void:
	var entity_store = EntityStoreModel.new()
	entity_store.configure_definitions(
		registry.list_definitions("object"),
		false
	)
	entity_store.load_from_context(context)
	var state_store = StateStoreModel.new()
	state_store.configure_definitions(
		registry.list_definitions("state"),
		entity_store,
		false
	)
	state_store.load_from_context(context)
	var relationship_store = RelationshipStoreModel.new()
	relationship_store.load_axis_defs(RELATIONSHIP_AXIS_DEFS_PATH)
	var deferred_store = DeferredConsequenceStoreModel.new()
	var item_store = ItemStoreModel.new()
	item_store.load_initial_items(
		(fixture.get("initial_items", []) as Array).duplicate(true)
	)
	var fact_store = FactStoreModel.new()
	for fact: Dictionary in fixture.get("known_facts", []):
		fact_store.add_fact(fact)
	var character_feature_store = CharacterFeatureStoreModel.new()
	character_feature_store.configure({
		"talent": registry.list_definitions("talent"),
		"trait": registry.list_definitions("trait"),
		"mark": registry.list_definitions("mark"),
		"skill": registry.list_definitions("skill"),
	}, entity_store, fact_store)
	character_feature_store.load_initial_data(fixture, context)
	stores = {
		"entity_store": entity_store,
		"fact_store": fact_store,
		"state_store": state_store,
		"character_feature_store": character_feature_store,
		"relationship_store": relationship_store,
		"memory_store": MemoryStoreModel.new(),
		"trace_store": TraceStoreModel.new(),
		"rumor_store": RumorStoreModel.new(),
		"pressure_store": PressureStoreModel.new(),
		"obligation_store": ObligationStoreModel.new(),
		"exchange_store": ExchangeStoreModel.new(),
		"item_store": item_store,
		"chronicle_store": ChronicleStoreModel.new(),
		"investigation_store": InvestigationLeadStoreModel.new(),
		"deferred_consequence_store": deferred_store,
	}
	for consequence: Dictionary in fixture.get(
		"initial_deferred_consequences",
		[]
	):
		deferred_store.add_deferred_consequence(consequence)


func _execute_candidate(
		snapshot: Variant,
		candidate: Variant,
		candidate_count: int,
		metadata: Dictionary
) -> Dictionary:
	var transaction_result: Variant = resolver.resolve_action(candidate, snapshot)
	writer.apply_result(transaction_result, stores)

	var step_index := int(metadata.get("step_index", action_count))
	var step_id := str(metadata.get("step_id", "live_action_%d" % action_count))
	var log_entry := _build_world_log_entry(
		step_index,
		step_id,
		candidate,
		transaction_result,
		candidate_count
	)
	world_log.append_entry(log_entry)
	action_count += 1

	var contract_status := str(transaction_result.contract_status)
	return {
		"success": contract_status != "invalid_contract",
		"error": str(transaction_result.error_reason),
		"fixture_id": fixture_id,
		"step_index": step_index,
		"step_id": step_id,
		"action_id": str(candidate.action_id),
		"rule_id": str(candidate.rule_id),
		"target_id": str(candidate.target_id),
		"contract_status": contract_status,
		"candidate": candidate.to_dict(),
		"transaction_result": transaction_result.to_dict(),
		"world_log_entry": log_entry.duplicate(true),
		"store_summary": get_store_summary(),
	}


func _configure_world_time(fixture: Dictionary) -> void:
	var time_data: Dictionary = fixture.get("world_time", {})
	current_day = maxi(int(time_data.get("day", 1)), 1)
	current_hour = posmod(int(time_data.get("hour", 8)), 24)


func _projected_time(hours: int) -> Dictionary:
	var absolute_hour := current_hour + maxi(hours, 0)
	return {
		"day": current_day + int(absolute_hour / 24),
		"hour": posmod(absolute_hour, 24),
	}


func _advance_clock(hours: int) -> void:
	var projected := _projected_time(hours)
	current_day = int(projected.get("day", current_day))
	current_hour = int(projected.get("hour", current_hour))
	elapsed_hours_since_start += maxi(hours, 0)


func _find_candidate_by_action_id(candidates: Array, action_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.action_id) == action_id:
			return candidate
	return null


func _find_travel_route(route_id: String, from_location_id: String) -> Dictionary:
	for route: Dictionary in travel_routes:
		if str(route.get("route_id", "")) != route_id:
			continue
		if str(route.get("from_location_id", "")) != from_location_id:
			continue
		return route.duplicate(true)
	return {}


func _find_challenge_option(option_id: String) -> Dictionary:
	for option: Dictionary in get_challenge_options():
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _find_challenge_definition(challenge_id: String) -> Dictionary:
	for challenge: Dictionary in challenge_definitions:
		if str(challenge.get("challenge_id", "")) == challenge_id:
			return challenge.duplicate(true)
	return {}


func _challenge_requirements_met(
		challenge: Dictionary,
		snapshot: Variant
) -> bool:
	var facts: Array = snapshot.get_facts()
	for fact_type_value: Variant in challenge.get(
		"required_fact_types",
		[]
	):
		if not _facts_include_type(facts, str(fact_type_value)):
			return false
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var inventory_item_ids: Array = snapshot.get_player_value(
		"inventory_item_ids",
		[]
	)
	for item_id_value: Variant in challenge.get(
		"required_item_ids",
		[]
	):
		var item_id := str(item_id_value)
		var item: Dictionary = snapshot.get_item(item_id)
		if (
			item_id == ""
			or item.is_empty()
			or str(item.get("owner_id", "")) != actor_id
			or item_id not in inventory_item_ids
		):
			return false
	return true


func _find_return_echo_option(option_id: String) -> Dictionary:
	for option: Dictionary in get_return_echo_options():
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _find_return_echo_definition(echo_id: String) -> Dictionary:
	for definition: Dictionary in return_echo_definitions:
		if str(definition.get("echo_id", "")) == echo_id:
			return definition.duplicate(true)
	return {}


func _return_echo_is_available(
		definition: Dictionary,
		snapshot: Variant
) -> bool:
	if (
		str(definition.get("location_id", ""))
		!= str(snapshot.location.get("id", ""))
	):
		return false
	var target_id := str(definition.get("target_entity_id", ""))
	if target_id == "" or snapshot.get_entity(target_id).is_empty():
		return false
	if not bool(snapshot.get_entity_state(target_id, "visible", false)):
		return false
	var completion_state_key := str(
		definition.get("completion_state_key", "return_echo_completed")
	)
	if bool(snapshot.get_entity_state(
		target_id,
		completion_state_key,
		false
	)):
		return false

	var item_id := str(definition.get("required_item_id", ""))
	var item: Dictionary = snapshot.get_item(item_id)
	var actor_id := str(snapshot.get_player_value("id", "player"))
	if item.is_empty() or str(item.get("owner_id", "")) != actor_id:
		return false
	var inventory_ids: Array = snapshot.get_player_value(
		"inventory_item_ids",
		[]
	)
	if item_id not in inventory_ids:
		return false
	for required_tag: Variant in definition.get(
		"required_item_tags",
		[]
	):
		if str(required_tag) not in (item.get("tags", []) as Array):
			return false
	var provenance: Dictionary = item.get("provenance", {})
	var required_provenance: Dictionary = definition.get(
		"required_item_provenance",
		{}
	)
	for key: String in required_provenance.keys():
		if provenance.get(key) != required_provenance.get(key):
			return false

	var facts: Array = snapshot.get_facts()
	for fact_type: Variant in definition.get(
		"required_fact_types",
		[]
	):
		if not _facts_include_type(facts, str(fact_type)):
			return false
	for route_id: Variant in definition.get("required_route_ids", []):
		if not _facts_include_route(facts, str(route_id)):
			return false
	var challenge_id := str(
		definition.get("required_challenge_id", "")
	)
	if (
		challenge_id != ""
		and not _facts_include_successful_challenge(
			facts,
			challenge_id
		)
	):
		return false
	return _facts_include_item_discovery(facts, item_id)


func _facts_include_type(facts: Array, fact_type: String) -> bool:
	for fact: Dictionary in facts:
		if str(fact.get("fact_type", "")) == fact_type:
			return true
	return false


func _facts_include_route(facts: Array, route_id: String) -> bool:
	for fact: Dictionary in facts:
		if (
			str(fact.get("fact_type", "")) == "actor_traveled_route"
			and str(fact.get("route_id", "")) == route_id
		):
			return true
	return false


func _facts_include_successful_challenge(
		facts: Array,
		challenge_id: String
) -> bool:
	for fact: Dictionary in facts:
		if (
			str(fact.get("fact_type", ""))
				== "actor_attempted_challenge"
			and str(fact.get("challenge_id", "")) == challenge_id
			and str(fact.get("outcome", "")) == "success"
		):
			return true
	return false


func _facts_include_item_discovery(
		facts: Array,
		item_id: String
) -> bool:
	for fact: Dictionary in facts:
		if (
			str(fact.get("fact_type", "")) == "actor_discovered_item"
			and str(fact.get("target_id", "")) == item_id
		):
			return true
	return false


func _find_investigation_option(option_id: String) -> Dictionary:
	for option: Dictionary in get_investigation_options():
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _find_investigation_definition(lead_id: String) -> Dictionary:
	for definition: Dictionary in investigation_definitions:
		if str(definition.get("lead_id", "")) == lead_id:
			return definition.duplicate(true)
	return {}


func _investigation_option_row(
		option: Dictionary,
		lead: Dictionary
) -> Dictionary:
	return {
		"option_id": str(option.get("option_id", "")),
		"option_type": str(option.get("option_type", "")),
		"lead_id": str(lead.get("lead_id", "")),
		"lead_title": str(lead.get("title", "调查方向")),
		"label": str(option.get("label", "处理调查方向")),
		"hours": int(option.get("hours", 0)),
		"action_type": str(
			option.get("action_type", "investigation")
		),
		"hint": str(option.get("hint", "")),
		"can_execute": true,
		"blocked_reason": "",
	}


func _investigation_lead_is_available(
		definition: Dictionary,
		lead: Dictionary,
		snapshot: Variant
) -> bool:
	var location_id := str(snapshot.location.get("id", ""))
	if (
		str(definition.get("location_id", "")) != location_id
		or str(lead.get("location_id", "")) != location_id
	):
		return false
	var target_id := str(definition.get("target_entity_id", ""))
	if (
		snapshot.get_entity(target_id).is_empty()
		or not bool(snapshot.get_entity_state(
			target_id,
			"visible",
			false
		))
	):
		return false

	var facts: Array = snapshot.get_facts()
	for source_fact_id: Variant in lead.get("source_fact_ids", []):
		if not _facts_include_id(facts, str(source_fact_id)):
			return false
	var required_fact_type := str(
		definition.get("required_fact_type", "")
	)
	if (
		required_fact_type != ""
		and not _facts_include_type_for_target(
			facts,
			required_fact_type,
			str(lead.get("lead_id", ""))
		)
	):
		return false

	var item_id := str(definition.get("required_item_id", ""))
	var item: Dictionary = snapshot.get_item(item_id)
	var actor_id := str(snapshot.get_player_value("id", "player"))
	if item.is_empty() or str(item.get("owner_id", "")) != actor_id:
		return false
	return item_id in (
		snapshot.get_player_value("inventory_item_ids", []) as Array
	)


func _facts_include_id(facts: Array, fact_id: String) -> bool:
	for fact: Dictionary in facts:
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _facts_include_type_for_target(
		facts: Array,
		fact_type: String,
		target_id: String
) -> bool:
	for fact: Dictionary in facts:
		if (
			str(fact.get("fact_type", "")) == fact_type
			and str(fact.get("target_id", "")) == target_id
		):
			return true
	return false


func _find_candidate(candidates: Array, rule_id: String, target_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) != rule_id:
			continue
		if target_id != "" and str(candidate.target_id) != target_id:
			continue
		return candidate
	return null


func _candidate_not_found(
		action_id: String,
		rule_id: String,
		target_id: String,
		candidates: Array
) -> Dictionary:
	return {
		"success": false,
		"error": "candidate_not_found",
		"fixture_id": fixture_id,
		"action_id": action_id,
		"rule_id": rule_id,
		"target_id": target_id,
		"candidate_count": candidates.size(),
		"available_action_ids": _candidate_action_ids(candidates),
		"store_summary": get_store_summary(),
	}


func _candidate_blocked(candidate: Variant, candidate_count: int) -> Dictionary:
	return {
		"success": false,
		"error": "action_blocked",
		"blocked_reason": str(candidate.blocked_reason),
		"fixture_id": fixture_id,
		"action_id": str(candidate.action_id),
		"rule_id": str(candidate.rule_id),
		"target_id": str(candidate.target_id),
		"candidate_count": candidate_count,
		"candidate": candidate.to_dict(),
		"store_summary": get_store_summary(),
	}


func _execution_failure(error: String, action_id: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"fixture_id": fixture_id,
		"action_id": action_id,
		"store_summary": get_store_summary(),
	}


func _travel_failure(error: String, route_id: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"fixture_id": fixture_id,
		"route_id": route_id,
		"travel_count": travel_count,
		"time": get_time_summary(),
		"world_tick_count": world_tick_count,
		"store_summary": get_store_summary(),
	}


func _challenge_failure(error: String, option_id: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"fixture_id": fixture_id,
		"option_id": option_id,
		"challenge_count": challenge_count,
		"challenge_preparation_count": challenge_preparation_count,
		"time": get_time_summary(),
		"world_tick_count": world_tick_count,
		"store_summary": get_store_summary(),
	}


func _return_echo_failure(error: String, option_id: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"fixture_id": fixture_id,
		"option_id": option_id,
		"return_echo_count": return_echo_count,
		"time": get_time_summary(),
		"world_tick_count": world_tick_count,
		"store_summary": get_store_summary(),
	}


func _investigation_failure(error: String, option_id: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"fixture_id": fixture_id,
		"option_id": option_id,
		"investigation_count": investigation_count,
		"investigation_defer_count": investigation_defer_count,
		"time": get_time_summary(),
		"world_tick_count": world_tick_count,
		"store_summary": get_store_summary(),
	}


func _travel_blocked_reason(
		route: Dictionary,
		destination: Dictionary,
		hours: int,
		food_count: int,
		food_cost: int,
		snapshot: Variant
) -> String:
	if destination.is_empty():
		return "destination_not_found"
	if hours <= 0:
		return "invalid_route_contract"
	if food_cost < 0:
		return "invalid_route_contract"
	if not _route_access_contract_valid(route):
		return "invalid_route_contract"
	if not _route_access_time_allows(route):
		return "outside_access_window"
	if not _route_required_items_met(route, snapshot):
		return "missing_required_item"
	if food_count < food_cost:
		return "insufficient_food"
	return ""


func _route_discovery_requirements_met(
		route: Dictionary,
		snapshot: Variant
) -> bool:
	var required_fact_type := str(
		route.get("required_fact_type", "")
	)
	if required_fact_type == "":
		return true
	var required_target_id := str(
		route.get("required_fact_target_id", "")
	)
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) != required_fact_type:
			continue
		if (
			required_target_id == ""
			or str(fact.get("target_id", "")) == required_target_id
		):
			return true
	return false


func _route_required_items_met(
		route: Dictionary,
		snapshot: Variant
) -> bool:
	var required_item_values: Variant = route.get("required_item_ids", [])
	if not required_item_values is Array:
		return false
	var actor_id := str(snapshot.get_player_value("id", "player"))
	var inventory_item_ids: Array = snapshot.get_player_value(
		"inventory_item_ids",
		[]
	)
	for item_value: Variant in required_item_values:
		var item_id := str(item_value)
		var item: Dictionary = snapshot.get_item(item_id)
		if (
			item_id == ""
			or item.is_empty()
			or str(item.get("owner_id", "")) != actor_id
			or item_id not in inventory_item_ids
		):
			return false
	return true


func _route_access_time_allows(route: Dictionary) -> bool:
	if (
		not route.has("available_hour_start")
		and not route.has("available_hour_end")
	):
		return true
	if not _route_access_contract_valid(route):
		return false
	var start_hour := int(route.get("available_hour_start", -1))
	var end_hour := int(route.get("available_hour_end", -1))
	if start_hour < end_hour:
		return current_hour >= start_hour and current_hour < end_hour
	return current_hour >= start_hour or current_hour < end_hour


func _route_access_contract_valid(route: Dictionary) -> bool:
	var has_start := route.has("available_hour_start")
	var has_end := route.has("available_hour_end")
	if not has_start and not has_end:
		return true
	if has_start != has_end:
		return false
	var start_hour := int(route.get("available_hour_start", -1))
	var end_hour := int(route.get("available_hour_end", -1))
	return (
		start_hour >= 0
		and start_hour <= 23
		and end_hour >= 1
		and end_hour <= 24
		and start_hour != end_hour
	)


func _tick_failure(error: String) -> Dictionary:
	return {
		"success": false,
		"error_reason": error,
		"fixture_id": fixture_id,
		"time": get_time_summary(),
		"world_tick_count": world_tick_count,
		"store_summary": get_store_summary(),
	}


func _start_failure(error: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"fixture_id": fixture_id,
		"rule_count": rules.size(),
		"candidate_count": 0,
	}


func _build_world_log_entry(
		step_index: int,
		step_id: String,
		candidate: Variant,
		result: Variant,
		candidate_count: int
) -> Dictionary:
	return {
		"entry_type": "player_action",
		"step_index": step_index,
		"step_id": step_id,
		"rule_id": str(candidate.rule_id),
		"action_id": str(candidate.action_id),
		"target_id": str(candidate.target_id),
		"target_display_name": str(candidate.target_display_name),
		"selected_from_candidates": true,
		"candidate_context_source": "SimSnapshot",
		"resolver_context_source": "SimSnapshot",
		"transaction_mode": str(result.transaction_mode),
		"contract_status": str(result.contract_status),
		"skip_reason": str(result.skip_reason),
		"error_reason": str(result.error_reason),
		"candidate_count": candidate_count,
		"facts_added": _fact_types(result.facts_added),
		"fact_ids": _fact_ids(result.facts_added),
		"state_changes": result.state_changes.duplicate(true),
		"state_change_count": result.state_changes.size(),
		"relationship_changes": result.relationship_changes.duplicate(true),
		"relationship_change_count": result.relationship_changes.size(),
		"memories_added": result.memories_added.duplicate(true),
		"memory_types": _memory_types(result.memories_added),
		"memory_count": result.memories_added.size(),
		"traces_added": result.traces_added.duplicate(true),
		"trace_types": _trace_types(result.traces_added),
		"trace_count": result.traces_added.size(),
		"rumors_added": result.rumors_added.duplicate(true),
		"rumor_seed_ids": _rumor_seed_ids(result.rumors_added),
		"rumor_seed_count": result.rumors_added.size(),
		"pressure_changes": result.pressure_changes.duplicate(true),
		"pressure_change_count": result.pressure_changes.size(),
		"obligations_added": result.obligations_added.duplicate(true),
		"obligation_count": result.obligations_added.size(),
		"exchanges_added": result.exchanges_added.duplicate(true),
		"exchange_count": result.exchanges_added.size(),
		"deferred_consequences_added": result.deferred_consequences_added.duplicate(true),
		"deferred_consequence_count": result.deferred_consequences_added.size(),
		"obligation_updates": result.obligation_updates.duplicate(true),
		"obligation_update_count": result.obligation_updates.size(),
		"exchange_updates": result.exchange_updates.duplicate(true),
		"exchange_update_count": result.exchange_updates.size(),
		"deferred_consequence_updates": result.deferred_consequence_updates.duplicate(true),
		"deferred_consequence_update_count": result.deferred_consequence_updates.size(),
		"item_changes": result.item_changes.duplicate(true),
		"item_change_count": result.item_changes.size(),
		"narrative_summary": _narrative_summary(result.narrative_result),
		"narrative_result": result.narrative_result.duplicate(true),
	}


func _build_travel_log_entry(
		route: Dictionary,
		result: Variant,
		journey_index: int
) -> Dictionary:
	return {
		"entry_type": "travel",
		"step_index": journey_index,
		"step_id": "travel_%d" % journey_index,
		"route_id": str(route.get("route_id", "")),
		"from_location_id": str(route.get("from_location_id", "")),
		"to_location_id": str(route.get("to_location_id", "")),
		"hours": int(route.get("hours", 0)),
		"food_cost": int(route.get("food_cost", 0)),
		"transaction_mode": str(result.transaction_mode),
		"contract_status": str(result.contract_status),
		"skip_reason": str(result.skip_reason),
		"error_reason": str(result.error_reason),
		"facts_added": _fact_types(result.facts_added),
		"fact_ids": _fact_ids(result.facts_added),
		"state_changes": result.state_changes.duplicate(true),
		"state_change_count": result.state_changes.size(),
		"relationship_change_count": 0,
		"memory_count": 0,
		"trace_count": 0,
		"rumor_seed_count": 0,
		"pressure_change_count": 0,
		"obligation_count": 0,
		"exchange_count": 0,
		"deferred_consequence_count": 0,
		"obligation_update_count": 0,
		"exchange_update_count": 0,
		"deferred_consequence_update_count": 0,
		"item_change_count": 0,
		"narrative_summary": _narrative_summary(result.narrative_result),
		"narrative_result": result.narrative_result.duplicate(true),
	}


func _build_challenge_log_entry(
		option: Dictionary,
		result: Variant,
		event_id: int
) -> Dictionary:
	return {
		"entry_type": (
			"challenge_preparation"
			if str(option.get("option_type", "")) == "prepare"
			else "challenge_check"
		),
		"step_index": event_id - 1,
		"step_id": "challenge_%d" % event_id,
		"challenge_id": str(option.get("challenge_id", "")),
		"option_id": str(option.get("option_id", "")),
		"option_type": str(option.get("option_type", "")),
		"transaction_mode": str(result.transaction_mode),
		"contract_status": str(result.contract_status),
		"skip_reason": str(result.skip_reason),
		"error_reason": str(result.error_reason),
		"facts_added": _fact_types(result.facts_added),
		"fact_ids": _fact_ids(result.facts_added),
		"state_changes": result.state_changes.duplicate(true),
		"state_change_count": result.state_changes.size(),
		"relationship_change_count": 0,
		"memory_count": 0,
		"trace_count": 0,
		"rumor_seed_count": 0,
		"pressure_change_count": 0,
		"obligation_count": 0,
		"exchange_count": 0,
		"deferred_consequence_count": 0,
		"obligation_update_count": 0,
		"exchange_update_count": 0,
		"deferred_consequence_update_count": 0,
		"item_changes": result.item_changes.duplicate(true),
		"item_change_count": result.item_changes.size(),
		"narrative_summary": _narrative_summary(result.narrative_result),
		"narrative_result": result.narrative_result.duplicate(true),
	}


func _build_return_echo_log_entry(
		option: Dictionary,
		result: Variant,
		event_id: int
) -> Dictionary:
	return {
		"entry_type": "return_echo",
		"step_index": event_id - 1,
		"step_id": "return_echo_%d" % event_id,
		"echo_id": str(option.get("echo_id", "")),
		"option_id": str(option.get("option_id", "")),
		"target_id": str(option.get("target_entity_id", "")),
		"item_id": str(option.get("item_id", "")),
		"transaction_mode": str(result.transaction_mode),
		"contract_status": str(result.contract_status),
		"skip_reason": str(result.skip_reason),
		"error_reason": str(result.error_reason),
		"facts_added": _fact_types(result.facts_added),
		"fact_ids": _fact_ids(result.facts_added),
		"state_changes": result.state_changes.duplicate(true),
		"state_change_count": result.state_changes.size(),
		"relationship_changes": result.relationship_changes.duplicate(true),
		"relationship_change_count": result.relationship_changes.size(),
		"memories_added": result.memories_added.duplicate(true),
		"memory_types": _memory_types(result.memories_added),
		"memory_count": result.memories_added.size(),
		"trace_count": 0,
		"rumor_seed_count": 0,
		"pressure_change_count": 0,
		"obligation_count": 0,
		"exchange_count": 0,
		"deferred_consequence_count": 0,
		"obligation_update_count": 0,
		"exchange_update_count": 0,
		"deferred_consequence_update_count": 0,
		"item_changes": result.item_changes.duplicate(true),
		"item_change_count": result.item_changes.size(),
		"chronicle_entries_added": (
			result.chronicle_entries_added.duplicate(true)
		),
		"chronicle_entry_count": (
			result.chronicle_entries_added.size()
		),
		"investigation_changes": (
			result.investigation_changes.duplicate(true)
		),
		"investigation_change_count": (
			result.investigation_changes.size()
		),
		"narrative_summary": _narrative_summary(
			result.narrative_result
		),
		"narrative_result": result.narrative_result.duplicate(true),
	}


func _build_investigation_log_entry(
		option: Dictionary,
		result: Variant,
		event_id: int
) -> Dictionary:
	return {
		"entry_type": "investigation_choice",
		"step_index": event_id - 1,
		"step_id": "investigation_%d" % event_id,
		"lead_id": str(option.get("lead_id", "")),
		"option_id": str(option.get("option_id", "")),
		"option_type": str(option.get("option_type", "")),
		"hours": int(option.get("hours", 0)),
		"transaction_mode": str(result.transaction_mode),
		"contract_status": str(result.contract_status),
		"skip_reason": str(result.skip_reason),
		"error_reason": str(result.error_reason),
		"facts_added": _fact_types(result.facts_added),
		"fact_ids": _fact_ids(result.facts_added),
		"state_changes": result.state_changes.duplicate(true),
		"state_change_count": result.state_changes.size(),
		"relationship_changes": result.relationship_changes.duplicate(true),
		"relationship_change_count": result.relationship_changes.size(),
		"memories_added": result.memories_added.duplicate(true),
		"memory_types": _memory_types(result.memories_added),
		"memory_count": result.memories_added.size(),
		"trace_count": 0,
		"rumor_seed_count": 0,
		"pressure_change_count": 0,
		"obligation_count": 0,
		"exchange_count": 0,
		"deferred_consequence_count": 0,
		"obligation_update_count": 0,
		"exchange_update_count": 0,
		"deferred_consequence_update_count": 0,
		"item_changes": result.item_changes.duplicate(true),
		"item_change_count": result.item_changes.size(),
		"chronicle_entries_added": (
			result.chronicle_entries_added.duplicate(true)
		),
		"chronicle_entry_count": (
			result.chronicle_entries_added.size()
		),
		"investigation_changes": (
			result.investigation_changes.duplicate(true)
		),
		"investigation_change_count": (
			result.investigation_changes.size()
		),
		"narrative_summary": _narrative_summary(
			result.narrative_result
		),
		"narrative_result": result.narrative_result.duplicate(true),
	}


func _snapshot_summary(snapshot: Variant, candidates: Array) -> Dictionary:
	return {
		"final_fact_count": snapshot.get_facts().size(),
		"final_trace_count": snapshot.get_visible_traces().size(),
		"final_rumor_count": snapshot.get_rumor_seeds().size(),
		"final_relationship_count": _count_snapshot_relationship_axes(snapshot),
		"final_memory_count": snapshot.memories.size(),
		"final_pressure_count": snapshot.get_pressures().size(),
		"final_obligation_count": snapshot.obligations.size(),
		"final_exchange_count": snapshot.exchanges.size(),
		"final_deferred_consequence_count": snapshot.deferred_consequences.size(),
		"final_item_count": snapshot.get_items().size(),
		"final_chronicle_entry_count": (
			snapshot.get_chronicle_entries().size()
		),
		"final_investigation_lead_count": (
			snapshot.get_investigation_leads().size()
		),
		"final_open_investigation_lead_count": (
			snapshot.get_open_investigation_leads().size()
		),
		"final_candidate_probe": {
			"rule_ids": _candidate_rule_ids(candidates),
			"action_ids": _candidate_action_ids(candidates),
		},
	}


func _fact_types(facts: Array) -> Array:
	var rows: Array = []
	for fact: Dictionary in facts:
		rows.append(str(fact.get("fact_type", fact.get("type", ""))))
	return rows


func _fact_ids(facts: Array) -> Array:
	var rows: Array = []
	for fact: Dictionary in facts:
		rows.append(str(fact.get("fact_id", "")))
	return rows


func _memory_types(memories: Array) -> Array:
	var rows: Array = []
	for memory: Dictionary in memories:
		rows.append(str(memory.get("memory_type", "")))
	return rows


func _trace_types(traces: Array) -> Array:
	var rows: Array = []
	for trace: Dictionary in traces:
		rows.append(str(trace.get("trace_type", "")))
	return rows


func _rumor_seed_ids(rumors: Array) -> Array:
	var rows: Array = []
	for rumor: Dictionary in rumors:
		rows.append(str(rumor.get("rumor_id", "")))
	return rows


func _narrative_summary(narrative_result: Dictionary) -> String:
	if narrative_result.has("summary"):
		return str(narrative_result.get("summary", ""))
	return str(narrative_result.get("body", ""))


func _candidate_rule_ids(candidates: Array) -> Array:
	var rows: Array = []
	for candidate: Variant in candidates:
		rows.append(str(candidate.rule_id))
	return rows


func _candidate_action_ids(candidates: Array) -> Array:
	var rows: Array = []
	for candidate: Variant in candidates:
		rows.append(str(candidate.action_id))
	return rows


func _count_states(state_store: Variant) -> int:
	var count := 0
	for entity_id: String in state_store.states.keys():
		var entity_states: Dictionary = state_store.states[entity_id]
		count += entity_states.size()
	return count


func _count_relationship_axes(relationship_store: Variant) -> int:
	var count := 0
	for source_id: String in relationship_store.relations.keys():
		var source_relations: Dictionary = relationship_store.relations[source_id]
		for target_id: String in source_relations.keys():
			var target_relations: Dictionary = source_relations[target_id]
			count += target_relations.size()
	return count


func _count_character_features(store: Variant) -> int:
	return (
		store.list_talent_assignments().size()
		+ store.list_trait_instances().size()
		+ store.list_mark_instances().size()
		+ store.list_skill_progress().size()
	)


func _count_snapshot_relationship_axes(snapshot: Variant) -> int:
	var count := 0
	for source_id: String in snapshot.relationships.keys():
		var source_relations: Dictionary = snapshot.relationships[source_id]
		for target_id: String in source_relations.keys():
			var target_relations: Dictionary = source_relations[target_id]
			count += target_relations.size()
	return count


func _empty_store_summary() -> Dictionary:
	return {
		"entities": 0,
		"facts": 0,
		"states": 0,
		"character_features": 0,
		"relationships": 0,
		"memories": 0,
		"traces": 0,
		"rumors": 0,
		"pressures": 0,
		"obligations": 0,
		"exchanges": 0,
		"deferred_consequences": 0,
		"items": 0,
		"chronicle_entries": 0,
		"investigation_leads": 0,
	}
