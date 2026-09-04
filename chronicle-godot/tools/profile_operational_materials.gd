extends SceneTree

const Session = preload("res://scripts/sim/core/sim_session.gd")
const FIXTURE := "res://data/sim/fixtures/generated_settlement_network_fixture.json"
const RULES := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const OUTPUT := "user://tests/operational_material_profile.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var days := 7
	var seed := 81001
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--days="):
			days = clampi(argument.trim_prefix("--days=").to_int(), 1, 30)
		elif argument.begins_with("--seed="):
			seed = argument.trim_prefix("--seed=").to_int()
	var variants := [
		{"id": "disabled", "procurement": false, "materials": false},
		{"id": "demand_only", "procurement": false, "materials": true},
		{"id": "full_lifecycle", "procurement": true, "materials": true},
	]
	var reports: Array = []
	var passed := true
	for variant: Dictionary in variants:
		var report := _profile_variant(seed, days, variant)
		reports.append(report)
		passed = passed and bool(report.get("success", false))
		print("[OPERATIONAL MATERIAL PROFILE] ", JSON.stringify(report))
	var output_report := {
		"passed": passed,
		"seed": seed,
		"days": days,
		"variants": reports,
		"method": (
			"Same generated fixture and seed; full-day simulation only; "
			+ "persistent-reference validation runs once after timing."
		),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if output == null:
		push_error("Cannot write operational material profile: " + OUTPUT)
		passed = false
	else:
		output.store_string(JSON.stringify(output_report, "\t"))
		output.close()
	print("[OPERATIONAL MATERIAL PROFILE RESULT] ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)


func _profile_variant(seed: int, days: int, variant: Dictionary) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	data["challenge_seed"] = seed
	var generation: Dictionary = data.get(
		"settlement_network_generation", {}
	).duplicate(true)
	var procurement: Dictionary = generation.get("local_procurement", {}).duplicate(true)
	procurement["enabled"] = bool(variant.get("procurement", false))
	generation["local_procurement"] = procurement
	if not bool(variant.get("materials", false)):
		generation["operational_material_uses"] = []
	data["settlement_network_generation"] = generation
	var session = Session.new()
	var startup_started := Time.get_ticks_msec()
	var start: Dictionary = session.start_from_fixture_data(data, RULES)
	var startup_ms := Time.get_ticks_msec() - startup_started
	if not bool(start.get("success", false)):
		return {
			"id": str(variant.get("id", "")),
			"success": false,
			"startup_ms": startup_ms,
			"error": start,
		}
	var day_ms: Array[int] = []
	var simulation_started := Time.get_ticks_msec()
	for day_index: int in range(1, days + 1):
		var day_started := Time.get_ticks_msec()
		var tick: Dictionary = session.advance_time(
			24,
			"operational_material_profile",
			{
				"scope_type": "global",
				"scope_id": "",
				"source": "profile_operational_materials",
				"label": "operational material ablation",
			}
		)
		day_ms.append(Time.get_ticks_msec() - day_started)
		if not bool(tick.get("success", false)):
			return {
				"id": str(variant.get("id", "")),
				"success": false,
				"startup_ms": startup_ms,
				"day": day_index,
				"error": tick,
			}
	var simulation_ms := Time.get_ticks_msec() - simulation_started
	var references: Dictionary = session.validate_persistent_references()
	return {
		"id": str(variant.get("id", "")),
		"success": bool(references.get("ok", false)),
		"startup_ms": startup_ms,
		"simulation_ms": simulation_ms,
		"day_ms": day_ms,
		"fact_count": session.stores["fact_store"].list_facts().size(),
		"item_count": session.stores["item_store"].list_items().size(),
		"open_obligation_count": session.stores[
			"obligation_store"
		].find_open_obligations().size(),
		"material_demand_count": _fact_count(
			session, "operational_material_demand_opened"
		),
		"material_use_count": _fact_count(session, "operational_material_used"),
		"material_worn_out_count": _fact_count(
			session, "operational_material_worn_out"
		),
		"procurement_count": _fact_count(session, "local_rope_procured"),
		"reference_errors": references.get("errors", []),
	}


func _fact_count(session: Variant, fact_type: String) -> int:
	var count := 0
	for fact: Dictionary in session.stores["fact_store"].list_facts():
		if str(fact.get("fact_type", "")) == fact_type:
			count += 1
	return count
