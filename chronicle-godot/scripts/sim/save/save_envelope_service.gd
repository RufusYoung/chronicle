extends RefCounted
class_name V5SaveEnvelopeService

const CURRENT_SCHEMA_VERSION := 1
const ALLOWED_SOURCE_KINDS := [
	"player_save",
	"test_fixture",
	"migration_fixture",
]


func finalize_envelope(source: Dictionary) -> Dictionary:
	var envelope := source.duplicate(true)
	envelope["schema_version"] = CURRENT_SCHEMA_VERSION
	envelope["payload_kind"] = "save_envelope"
	envelope.erase("integrity")
	envelope["integrity"] = {
		"algorithm": "sha256",
		"payload_hash": _payload_hash(envelope),
	}
	return envelope


func validate_and_migrate(source: Variant) -> Dictionary:
	if not source is Dictionary:
		return _failure("save_envelope_not_dictionary", "parse")
	var envelope := (source as Dictionary).duplicate(true)
	var migrations: Array[String] = []
	var version := int(envelope.get("schema_version", 0))
	if version > CURRENT_SCHEMA_VERSION:
		return _failure("save_schema_newer_than_runtime", "migration")
	while version < CURRENT_SCHEMA_VERSION:
		match version:
			0:
				var legacy_shape := _validate_v0_shape(envelope)
				if not bool(legacy_shape.get("ok", false)):
					return legacy_shape
				envelope = _migrate_v0_to_v1(envelope)
				migrations.append("v0_to_v1")
				version = 1
			_:
				return _failure(
					"save_migration_path_missing:%d" % version,
					"migration"
				)
	var validation := _validate_v1(envelope)
	if not bool(validation.get("ok", false)):
		validation["migrations"] = migrations
		return validation
	return {
		"ok": true,
		"error": "",
		"phase": "validated",
		"migrations": migrations,
		"envelope": envelope,
	}


func save_to_path(path: String, envelope: Dictionary) -> Dictionary:
	var validation := validate_and_migrate(envelope)
	if not bool(validation.get("ok", false)):
		return validation
	var normalized: Dictionary = validation.get("envelope", {})
	var absolute_dir := ProjectSettings.globalize_path(path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _failure(
			"save_directory_create_failed:%d" % directory_error,
			"write"
		)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure(
			"save_file_open_failed:%d" % FileAccess.get_open_error(),
			"write"
		)
	var encoded := JSON.stringify(normalized, "  ", true, false)
	file.store_string(encoded)
	file.close()
	return {
		"ok": true,
		"error": "",
		"phase": "written",
		"path": path,
		"byte_count": encoded.to_utf8_buffer().size(),
		"envelope": normalized,
	}


func load_from_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("save_file_not_found", "read")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(
			"save_file_open_failed:%d" % FileAccess.get_open_error(),
			"read"
		)
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return _failure("save_json_invalid", "parse")
	var result := validate_and_migrate(parsed)
	result["path"] = path
	return result


func _validate_v1(envelope: Dictionary) -> Dictionary:
	if int(envelope.get("schema_version", 0)) != CURRENT_SCHEMA_VERSION:
		return _failure("save_schema_version_invalid", "contract")
	if str(envelope.get("payload_kind", "")) != "save_envelope":
		return _failure("save_payload_kind_invalid", "contract")
	if str(envelope.get("source_kind", "")) not in ALLOWED_SOURCE_KINDS:
		return _failure("save_source_kind_invalid", "contract")
	for key: String in [
		"save_id",
		"world_id",
		"build_id",
		"bootstrap",
		"world_time",
		"rng_states",
		"session",
		"stores",
		"world_log",
		"definition_manifest",
		"integrity",
	]:
		if not envelope.has(key):
			return _failure("save_required_field_missing:%s" % key, "contract")
	for key: String in [
		"bootstrap",
		"world_time",
		"rng_states",
		"session",
		"stores",
		"definition_manifest",
		"integrity",
	]:
		if not envelope.get(key) is Dictionary:
			return _failure("save_field_not_dictionary:%s" % key, "contract")
	if not envelope.get("world_log") is Array:
		return _failure("save_world_log_not_array", "contract")
	var integrity: Dictionary = envelope.get("integrity", {})
	if str(integrity.get("algorithm", "")) != "sha256":
		return _failure("save_integrity_algorithm_invalid", "integrity")
	var expected_hash := str(integrity.get("payload_hash", ""))
	var payload := envelope.duplicate(true)
	payload.erase("integrity")
	if expected_hash == "" or expected_hash != _payload_hash(payload):
		return _failure("save_payload_hash_mismatch", "integrity")
	return {"ok": true, "error": "", "phase": "contract"}


func _validate_v0_shape(source: Dictionary) -> Dictionary:
	for key: String in [
		"session",
		"runtime_cursors",
		"bootstrap",
		"world_time",
		"rng_states",
		"stores",
		"definition_manifest",
	]:
		if source.has(key) and not source.get(key) is Dictionary:
			return _failure("save_v0_field_not_dictionary:%s" % key, "migration")
	if source.has("world_log") and not source.get("world_log") is Array:
		return _failure("save_v0_world_log_not_array", "migration")
	var session_value: Variant = source.get("session", {})
	if (
		session_value is Dictionary
		and (session_value as Dictionary).has("runtime_cursors")
		and not (session_value as Dictionary).get("runtime_cursors") is Dictionary
	):
		return _failure(
			"save_v0_session_runtime_cursors_not_dictionary", "migration"
		)
	return {"ok": true, "error": "", "phase": "migration"}


func _migrate_v0_to_v1(source: Dictionary) -> Dictionary:
	var legacy := source.duplicate(true)
	var session_data: Dictionary = legacy.get("session", {})
	if not session_data.has("actor_entity_id"):
		session_data["actor_entity_id"] = str(legacy.get("actor_entity_id", "player"))
	if not session_data.has("current_location_id"):
		session_data["current_location_id"] = str(legacy.get("location_id", ""))
	if not session_data.has("runtime_cursors"):
		session_data["runtime_cursors"] = (
			legacy.get("runtime_cursors", {}) as Dictionary
		).duplicate(true)
	var migrated := {
		"schema_version": 1,
		"payload_kind": "save_envelope",
		"save_id": str(legacy.get("save_id", "migration.v0")),
		"world_id": str(legacy.get("world_id", "")),
		"build_id": str(legacy.get("build_id", "chronicle-v5.5")),
		"created_at_utc": str(legacy.get("created_at_utc", "")),
		"saved_at_utc": str(legacy.get("saved_at_utc", "")),
		"source_kind": str(legacy.get("source_kind", "migration_fixture")),
		"bootstrap": (
			legacy.get("bootstrap", {}) as Dictionary
		).duplicate(true),
		"world_time": (
			legacy.get("world_time", {}) as Dictionary
		).duplicate(true),
		"rng_states": (
			legacy.get("rng_states", {}) as Dictionary
		).duplicate(true),
		"session": session_data,
		"stores": (legacy.get("stores", {}) as Dictionary).duplicate(true),
		"world_log": (legacy.get("world_log", []) as Array).duplicate(true),
		"definition_manifest": (
			legacy.get("definition_manifest", {}) as Dictionary
		).duplicate(true),
	}
	return finalize_envelope(migrated)


func _payload_hash(payload: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(_canonical_json(payload).to_utf8_buffer())
	return context.finish().hex_encode()


func _canonical_json(payload: Dictionary) -> String:
	# Godot 4.5 can shift the last binary digit when a full-precision decimal is
	# parsed and stringified again. The shortest representation is stable across
	# that disk round trip while retaining the value's practical precision.
	var first_pass := JSON.stringify(payload, "", true, false)
	var json_value: Variant = JSON.parse_string(first_pass)
	return JSON.stringify(json_value, "", true, false)


func _failure(error: String, phase: String) -> Dictionary:
	return {"ok": false, "error": error, "phase": phase}
