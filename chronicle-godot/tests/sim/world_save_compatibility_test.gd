extends SceneTree

const Content = preload("res://scripts/sim/generation/world_content_extension.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Content.V2_PATH))
	# Captured from the unmodified v2 pack under Godot 4.5.1, before 4.6 changed JSON.
	var old := {"version": 2.0, "id": "echo_port_life_v2",
		"definition_hash": "0a289dc9b8c8f0866155e690356ac44dd2b8395e128aff8d838f70eda06a85cc"}
	_check(Content._signature_matches(pack, old), "4.5.1 definition fingerprint accepted")
	_check(Content._signature_matches(pack, Content.signature(pack)), "current engine fingerprint accepted")
	var changed := pack.duplicate(true)
	changed.item_defs[0].base_mass += 0.01
	_check(not Content._signature_matches(changed, old), "changed numeric definition rejected")
	changed = pack.duplicate(true)
	changed.incidents[0].body += "changed"
	_check(not Content._signature_matches(changed, old), "changed narrative definition rejected")
	var malformed := old.duplicate()
	malformed["extra"] = true
	_check(not Content._signature_matches(pack, malformed), "unknown signature field rejected")
	malformed = old.duplicate()
	malformed.id = "other"
	_check(not Content._signature_matches(pack, malformed), "other identity rejected")
	print("SAVE_COMPATIBILITY_RESULT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)
