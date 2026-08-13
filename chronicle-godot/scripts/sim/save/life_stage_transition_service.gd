extends RefCounted
class_name V5LifeStageTransitionService

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const SCHEMA_VERSION := 4
const DEFAULT_TARGET_FIXTURE_ID := "seventh_outpost_first_winter"
const PLAYER_STATE_EXCLUSIONS := [
	"location_id",
	"service_day",
	"fatigue",
	"training",
	"last_duty",
]
const ENTITY_STATE_EXCLUSIONS := ["location_id"]


func build_player_transition(
		source_session: Variant,
		options: Dictionary = {}
) -> Dictionary:
	if source_session == null or not source_session.is_ready():
		return {}
	var actor_id := str(source_session.context.actor_id)
	var target_fixture_id := str(options.get(
		"target_fixture_id", DEFAULT_TARGET_FIXTURE_ID
	))
	if target_fixture_id == "":
		return {}
	var persistent_entity_ids := _existing_entity_ids(
		source_session,
		options.get("persistent_entity_ids", []),
		actor_id
	)
	var facts: Array = source_session.stores["fact_store"].to_save_data()
	var player_relationships := _player_relationships(
		source_session.stores["relationship_store"].to_save_data(),
		actor_id
	)
	var linked_ids := _linked_entity_ids(player_relationships, actor_id)
	for entity_id: String in persistent_entity_ids:
		if entity_id not in linked_ids:
			linked_ids.append(entity_id)
	var carried_owner_ids: Array = [actor_id]
	carried_owner_ids.append_array(persistent_entity_ids)
	var relationships := _relationships_between_ids(
		source_session.stores["relationship_store"].to_save_data(),
		carried_owner_ids + linked_ids
	)
	var items: Array = []
	for owner_id: String in carried_owner_ids:
		items.append_array(source_session.stores[
			"item_store"
		].list_items_for_owner(owner_id))
	for item: Dictionary in items:
		var provided_by := str((item.get("provenance", {}) as Dictionary).get(
			"provided_by", ""
		))
		if provided_by != "" and provided_by not in linked_ids:
			linked_ids.append(provided_by)
	var linked_entities: Dictionary = {}
	for entity_id: String in linked_ids:
		var entity: Dictionary = source_session.stores[
			"entity_store"
		].get_entity(entity_id)
		if not entity.is_empty():
			linked_entities[entity_id] = entity
	var features: Dictionary = source_session.stores[
		"character_feature_store"
	].to_save_data()
	var entity_states: Dictionary = {}
	for entity_id: String in persistent_entity_ids:
		entity_states[entity_id] = source_session.stores[
			"state_store"
		].list_states(entity_id)
	var equipment_loadouts: Dictionary = {}
	for owner_id: String in carried_owner_ids:
		var loadout: Dictionary = source_session.stores[
			"equipment_store"
		].get_loadout(owner_id)
		if not loadout.is_empty():
			equipment_loadouts[owner_id] = loadout
	return {
		"schema_version": SCHEMA_VERSION,
		"payload_kind": "life_stage_transition",
		"source_fixture_id": str(source_session.fixture_id),
		"target_fixture_id": target_fixture_id,
		"actor_entity_id": actor_id,
		"world_time": {
			"day": int(source_session.current_day),
			"hour": int(source_session.current_hour),
			"tick": int(source_session.world_tick_count),
			"elapsed_hours": int(source_session.elapsed_hours_since_start),
		},
		"rng_states": {
			"challenge_rng_state": str(source_session.challenge_rng.state),
		},
		"player_states": source_session.stores[
			"state_store"
		].list_states(actor_id),
		"persistent_entity_ids": persistent_entity_ids,
		"entity_states": entity_states,
		"linked_entities": linked_entities,
		"relationships": relationships,
		"facts": facts,
		"memories": _owned_memories(
			source_session.stores["memory_store"].to_save_data(),
			carried_owner_ids
		),
		"character_features": {
			"talent_assignments": _owned_rows_for_ids(
				features.get("talent_assignments", []), carried_owner_ids
			),
			"trait_instances": _owned_rows_for_ids(
				features.get("trait_instances", []), carried_owner_ids
			),
			"mark_instances": _owned_rows_for_ids(
				features.get("mark_instances", []), carried_owner_ids
			),
			"skill_progress": _owned_rows_for_ids(
				features.get("skill_progress", []), carried_owner_ids
			),
		},
		"items": _canonical_item_records(items),
		"equipment_loadouts": equipment_loadouts,
		"pressures": _scoped_rows(
			source_session.stores["pressure_store"].to_save_data(),
			persistent_entity_ids,
			"scope_id"
		),
		"chronicle_entries": _subject_rows_for_ids(
			source_session.stores["chronicle_store"].to_save_data(),
			carried_owner_ids
		),
		"world_log": source_session.world_log.to_save_data(),
	}


func apply_to_controller(controller: Variant, transition: Variant) -> Dictionary:
	if controller == null or not controller.is_ready():
		return _failure("transition_target_not_ready", "target")
	var normalized_transition: Variant = _migrate_transition(
		transition, controller.session
	)
	var contract := _validate_transition(normalized_transition)
	if not bool(contract.get("ok", false)):
		return contract
	var data := normalized_transition as Dictionary
	var session: Variant = controller.session
	if str(session.fixture_id) != str(data.get("target_fixture_id", "")):
		return _failure("transition_target_fixture_mismatch", "target")
	var actor_id := str(data.get("actor_entity_id", ""))
	if actor_id != str(session.context.actor_id):
		return _failure("transition_actor_mismatch", "target")
	var backup: Dictionary = session.build_save_envelope({
		"save_id": "save.transition.preflight.%s" % str(session.fixture_id),
		"source_kind": "test_fixture",
	})
	if backup.is_empty():
		return _failure("transition_preflight_snapshot_failed", "preflight")
	var preview = SimSessionModel.new()
	var preview_restore: Dictionary = preview.load_from_save_envelope(backup)
	if not bool(preview_restore.get("success", false)):
		return _failure(
			"transition_preflight_restore_failed:%s" % str(
				preview_restore.get("error", "unknown_error")
			),
			"preflight"
		)
	var preflight: Dictionary = _apply_transition_data(preview, data)
	if not bool(preflight.get("success", false)):
		preflight["phase"] = "preflight"
		return preflight
	var committed_envelope: Dictionary = preview.build_save_envelope({
		"save_id": "save.transition.committed.%s" % str(session.fixture_id),
		"source_kind": "test_fixture",
	})
	var commit_report: Dictionary = session.load_from_save_envelope(
		committed_envelope
	)
	if not bool(commit_report.get("success", false)):
		var rollback_report: Dictionary = session.load_from_save_envelope(backup)
		_refresh_controller_resolver(controller)
		var failure := _failure(
			"transition_commit_failed:%s" % str(
				commit_report.get("error", "unknown_error")
			),
			"commit"
		)
		failure["rollback_ok"] = bool(rollback_report.get("success", false))
		return failure
	if controller.has_method("set_entry_transition"):
		controller.set_entry_transition(data)
	_refresh_controller_resolver(controller)
	return {
		"success": true,
		"ok": true,
		"error": "",
		"phase": "transition_applied",
		"source_fixture_id": str(data.get("source_fixture_id", "")),
		"target_fixture_id": str(data.get("target_fixture_id", "")),
		"candidate_count": controller.get_duty_options().size(),
		"migrations": contract.get("migrations", []),
	}


func _apply_transition_data(session: Variant, data: Dictionary) -> Dictionary:
	var actor_id := str(data.get("actor_entity_id", ""))
	var linked_entities: Dictionary = data.get("linked_entities", {})
	for entity_id: String in linked_entities.keys():
		if session.stores["entity_store"].has_entity(entity_id):
			continue
		if not session.stores["entity_store"].add_entity(
			entity_id, linked_entities[entity_id]
		):
			return _failure("transition_entity_invalid:%s" % entity_id, "entities")
	var facts := _merge_rows_by_id(
		data.get("facts", []),
		session.stores["fact_store"].to_save_data(),
		"fact_id"
	)
	facts.append({
		"fact_id": "fact.transition.%s.to.%s" % [
			str(data.get("source_fixture_id", "")),
			str(data.get("target_fixture_id", "")),
		],
		"fact_type": "actor_entered_life_stage",
		"actor_id": actor_id,
		"source_fixture_id": str(data.get("source_fixture_id", "")),
		"target_fixture_id": str(data.get("target_fixture_id", "")),
		"day": int((data.get("world_time", {}) as Dictionary).get("day", 1)),
	})
	var fact_report: Dictionary = session.stores[
		"fact_store"
	].load_save_data(facts)
	if not bool(fact_report.get("ok", false)):
		return _store_failure("facts", fact_report)
	var states: Dictionary = session.stores["state_store"].to_save_data()
	var player_states: Dictionary = (
		states.get(actor_id, {}) as Dictionary
	).duplicate(true)
	for key: String in (data.get("player_states", {}) as Dictionary).keys():
		if key not in PLAYER_STATE_EXCLUSIONS:
			player_states[key] = data["player_states"][key]
	states[actor_id] = player_states
	for entity_id: String in (data.get("entity_states", {}) as Dictionary).keys():
		if entity_id == actor_id:
			continue
		var carried_states: Variant = data["entity_states"].get(entity_id)
		if not carried_states is Dictionary:
			return _failure(
				"transition_entity_state_invalid:%s" % entity_id,
				"states"
			)
		var merged_states: Dictionary = (
			states.get(entity_id, {}) as Dictionary
		).duplicate(true)
		for key: String in (carried_states as Dictionary).keys():
			if key not in ENTITY_STATE_EXCLUSIONS:
				merged_states[key] = carried_states.get(key)
		states[entity_id] = merged_states
	var state_report: Dictionary = session.stores[
		"state_store"
	].load_save_data(states)
	if not bool(state_report.get("ok", false)):
		return _store_failure("states", state_report)
	var relationship_report: Dictionary = session.stores[
		"relationship_store"
	].load_save_data(_merge_relationships(
		session.stores["relationship_store"].to_save_data(),
		data.get("relationships", {})
	))
	if not bool(relationship_report.get("ok", false)):
		return _store_failure("relationships", relationship_report)
	var feature_report: Dictionary = session.stores[
		"character_feature_store"
	].load_save_data(_merge_feature_data(
		session.stores["character_feature_store"].to_save_data(),
		data.get("character_features", {})
	))
	if not bool(feature_report.get("ok", false)):
		return _store_failure("character_features", feature_report)
	var item_report: Dictionary = session.stores["item_store"].load_save_data(
		_merge_rows_by_id(
			data.get("items", []),
			session.stores["item_store"].to_save_data(),
			"item_instance_id"
		)
	)
	if not bool(item_report.get("ok", false)):
		return _store_failure("items", item_report)
	var equipment_report: Dictionary = session.stores[
		"equipment_store"
	].load_save_data(_merge_equipment_loadouts(
		session.stores["equipment_store"].to_save_data(),
		data.get("equipment_loadouts", {})
	))
	if not bool(equipment_report.get("ok", false)):
		return _store_failure("equipment_loadouts", equipment_report)
	var pressure_report: Dictionary = session.stores[
		"pressure_store"
	].load_save_data(_merge_rows_by_id(
		data.get("pressures", []),
		session.stores["pressure_store"].to_save_data(),
		"pressure_id"
	))
	if not bool(pressure_report.get("ok", false)):
		return _store_failure("pressures", pressure_report)
	var memory_report: Dictionary = session.stores[
		"memory_store"
	].load_save_data(_merge_rows_by_id(
		session.stores["memory_store"].to_save_data(),
		data.get("memories", []),
		"memory_id"
	))
	if not bool(memory_report.get("ok", false)):
		return _store_failure("memories", memory_report)
	var chronicle_report: Dictionary = session.stores[
		"chronicle_store"
	].load_save_data(_merge_rows_by_id(
		session.stores["chronicle_store"].to_save_data(),
		data.get("chronicle_entries", []),
		"entry_id"
	))
	if not bool(chronicle_report.get("ok", false)):
		return _store_failure("chronicle_entries", chronicle_report)
	var world_log_report: Dictionary = session.world_log.load_save_data(
		data.get("world_log", [])
	)
	if not bool(world_log_report.get("ok", false)):
		return _store_failure("world_log", world_log_report)
	session.world_log.append_entry({
		"entry_type": "life_stage_transition",
		"source_fixture_id": str(data.get("source_fixture_id", "")),
		"target_fixture_id": str(data.get("target_fixture_id", "")),
		"actor_id": actor_id,
		"contract_status": "resolved",
	})
	var time_data: Dictionary = data.get("world_time", {})
	session.current_day = maxi(int(time_data.get("day", 1)), 1)
	session.current_hour = posmod(int(time_data.get("hour", 8)), 24)
	session.world_tick_count = maxi(int(time_data.get("tick", 0)), 0)
	session.elapsed_hours_since_start = maxi(int(
		time_data.get("elapsed_hours", 0)
	), 0)
	var rng_states: Dictionary = data.get("rng_states", {})
	session.challenge_rng.state = int(str(rng_states.get(
		"challenge_rng_state", "0"
	)))
	var references: Dictionary = session.validate_persistent_references()
	if not bool(references.get("ok", false)):
		return references
	return {
		"success": true,
		"ok": true,
		"error": "",
		"phase": "transition_preflight_applied",
		"source_fixture_id": str(data.get("source_fixture_id", "")),
		"target_fixture_id": str(data.get("target_fixture_id", "")),
	}


func _validate_transition(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("transition_not_dictionary", "contract")
	var data := value as Dictionary
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		return _failure("transition_schema_invalid", "contract")
	if str(data.get("payload_kind", "")) != "life_stage_transition":
		return _failure("transition_payload_kind_invalid", "contract")
	for key: String in [
		"source_fixture_id", "target_fixture_id", "actor_entity_id"
	]:
		if str(data.get(key, "")) == "":
			return _failure("transition_field_missing:%s" % key, "contract")
	for key: String in [
		"world_time",
		"rng_states",
		"player_states",
		"entity_states",
		"linked_entities",
		"relationships",
		"character_features",
		"equipment_loadouts",
	]:
		if not data.get(key) is Dictionary:
			return _failure("transition_field_not_dictionary:%s" % key, "contract")
	for key: String in [
		"persistent_entity_ids",
		"facts",
		"memories",
		"items",
		"pressures",
		"chronicle_entries",
		"world_log",
	]:
		if not data.get(key) is Array:
			return _failure("transition_field_not_array:%s" % key, "contract")
	return {
		"ok": true,
		"error": "",
		"phase": "contract",
		"migrations": data.get("_migrations", []),
	}


func _migrate_transition(value: Variant, target_session: Variant) -> Variant:
	if not value is Dictionary:
		return value
	var data := (value as Dictionary).duplicate(true)
	if int(data.get("schema_version", 0)) != 3:
		return data
	data["schema_version"] = SCHEMA_VERSION
	data["rng_states"] = {
		"challenge_rng_state": str(target_session.challenge_rng.state),
	}
	data["_migrations"] = ["life_stage_transition_v3_to_v4"]
	return data


func _player_relationships(source: Dictionary, actor_id: String) -> Dictionary:
	var result: Dictionary = {}
	for source_id: String in source.keys():
		for target_id: String in (source[source_id] as Dictionary).keys():
			if source_id != actor_id and target_id != actor_id:
				continue
			if not result.has(source_id):
				result[source_id] = {}
			result[source_id][target_id] = (
				(source[source_id] as Dictionary)[target_id] as Dictionary
			).duplicate(true)
	return result


func _linked_entity_ids(relationships: Dictionary, actor_id: String) -> Array:
	var ids: Array = []
	for source_id: String in relationships.keys():
		if source_id != actor_id and source_id not in ids:
			ids.append(source_id)
		for target_id: String in (relationships[source_id] as Dictionary).keys():
			if target_id != actor_id and target_id not in ids:
				ids.append(target_id)
	return ids


func _existing_entity_ids(
		source_session: Variant,
		value: Variant,
		actor_id: String
) -> Array:
	var ids: Array = []
	if not value is Array:
		return ids
	for raw_id: Variant in value:
		var entity_id := str(raw_id)
		if (
			entity_id == ""
			or entity_id == actor_id
			or entity_id in ids
			or not source_session.stores["entity_store"].has_entity(entity_id)
		):
			continue
		ids.append(entity_id)
	return ids


func _relationships_between_ids(source: Dictionary, entity_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for source_id: String in source.keys():
		if source_id not in entity_ids:
			continue
		for target_id: String in (source[source_id] as Dictionary).keys():
			if target_id not in entity_ids:
				continue
			if not result.has(source_id):
				result[source_id] = {}
			result[source_id][target_id] = (
				(source[source_id] as Dictionary)[target_id] as Dictionary
			).duplicate(true)
	return result


func _owned_rows_for_ids(value: Variant, owner_ids: Array) -> Array:
	var rows: Array = []
	if not value is Array:
		return rows
	for row: Dictionary in value:
		if str(row.get("owner_entity_id", "")) in owner_ids:
			rows.append(row.duplicate(true))
	return rows


func _owned_memories(value: Variant, owner_ids: Array) -> Array:
	var rows: Array = []
	if not value is Array:
		return rows
	for row: Dictionary in value:
		if str(row.get("owner_id", "")) in owner_ids:
			rows.append(row.duplicate(true))
	return rows


func _subject_rows_for_ids(value: Variant, subject_ids: Array) -> Array:
	var rows: Array = []
	if not value is Array:
		return rows
	for row: Dictionary in value:
		if str(row.get("subject_id", "")) in subject_ids:
			rows.append(row.duplicate(true))
	return rows


func _scoped_rows(value: Variant, scope_ids: Array, scope_key: String) -> Array:
	var rows: Array = []
	if not value is Array:
		return rows
	for row: Dictionary in value:
		if str(row.get(scope_key, "")) in scope_ids:
			rows.append(row.duplicate(true))
	return rows


func _canonical_item_records(items: Array) -> Array:
	var rows: Array = []
	for item: Dictionary in items:
		var row := item.duplicate(true)
		for key: String in [
			"id",
			"item_id",
			"owner_id",
			"item_type",
			"equip_slots",
			"capabilities",
			"base_mass",
			"base_value",
			"modifiers",
			"tags",
			"display_name",
		]:
			row.erase(key)
		rows.append(row)
	return rows


func _merge_rows_by_id(
		base_value: Variant,
		added_value: Variant,
		id_key: String
) -> Array:
	var rows: Array = []
	var ids: Dictionary = {}
	for collection: Variant in [base_value, added_value]:
		if not collection is Array:
			continue
		for row: Dictionary in collection:
			var id := str(row.get(id_key, ""))
			if id == "" or ids.has(id):
				continue
			ids[id] = true
			rows.append(row.duplicate(true))
	return rows


func _merge_relationships(base: Dictionary, added: Variant) -> Dictionary:
	var result := base.duplicate(true)
	if not added is Dictionary:
		return result
	for source_id: String in (added as Dictionary).keys():
		if not result.has(source_id):
			result[source_id] = {}
		for target_id: String in ((added as Dictionary)[source_id] as Dictionary).keys():
			result[source_id][target_id] = (
				((added as Dictionary)[source_id] as Dictionary)[target_id]
				as Dictionary
			).duplicate(true)
	return result


func _merge_feature_data(base: Dictionary, added: Variant) -> Dictionary:
	var result := base.duplicate(true)
	if not added is Dictionary:
		return result
	for key: String in [
		"talent_assignments", "trait_instances", "mark_instances", "skill_progress"
	]:
		result[key] = _merge_rows_by_id(
			(added as Dictionary).get(key, []),
			result.get(key, []),
			{
				"talent_assignments": "talent_assignment_id",
				"trait_instances": "trait_instance_id",
				"mark_instances": "mark_instance_id",
				"skill_progress": "skill_progress_id",
			}[key]
		)
	return result


func _merge_equipment_loadouts(base: Dictionary, added: Variant) -> Dictionary:
	var result := base.duplicate(true)
	if not added is Dictionary:
		return result
	for entity_id: String in (added as Dictionary).keys():
		var added_loadout: Variant = (added as Dictionary).get(entity_id)
		if not added_loadout is Dictionary:
			continue
		if not result.has(entity_id):
			result[entity_id] = (added_loadout as Dictionary).duplicate(true)
			continue
		var merged: Dictionary = (result[entity_id] as Dictionary).duplicate(true)
		var merged_slots: Dictionary = (
			merged.get("slots", {}) as Dictionary
		).duplicate(true)
		var added_slots: Dictionary = (
			(added_loadout as Dictionary).get("slots", {}) as Dictionary
		)
		for slot_id: String in added_slots.keys():
			if _equipment_item_id(merged_slots.get(slot_id)) == "":
				merged_slots[slot_id] = added_slots.get(slot_id)
		merged["slots"] = merged_slots
		merged["updated_tick"] = maxi(
			int(merged.get("updated_tick", 0)),
			int((added_loadout as Dictionary).get("updated_tick", 0))
		)
		result[entity_id] = merged
	return result


func _equipment_item_id(value: Variant) -> String:
	if value == null:
		return ""
	if value is Dictionary:
		return str((value as Dictionary).get("item_instance_id", ""))
	return str(value)


func _refresh_controller_resolver(controller: Variant) -> void:
	var resolver: Variant = controller.get("action_contract_resolver")
	if resolver != null and resolver.has_method("configure"):
		resolver.configure(controller.session.registry)


func _store_failure(store_key: String, report: Dictionary) -> Dictionary:
	return _failure(
		"transition_store_invalid:%s:%s" % [
			store_key,
			",".join(report.get("errors", [])),
		],
		"stores"
	)


func _failure(error: String, phase: String) -> Dictionary:
	return {"success": false, "ok": false, "error": error, "phase": phase}
