extends SceneTree

const Session = preload("res://scripts/sim/core/sim_session.gd")
const FIXTURE := "res://data/sim/fixtures/generated_settlement_network_fixture.json"
const RULES := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json"
]
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var reports: Array = []
	for seed: int in [81001, 81001, 82002]:
		var session = Session.new()
		_check(
			bool(
				(
					session
					. start_from_fixture_path(FIXTURE, RULES, {"challenge_seed_override": seed})
					. get("success", false)
				)
			),
			"natural seed %d starts" % seed
		)
		for day: int in range(1, 8):
			_check(
				bool(
					(
						session
						. advance_time(
							24, "industry_history", {"scope_type": "global", "scope_id": ""}
						)
						. get("success", false)
					)
				),
				"seed %d day %d advances" % [seed, day]
			)
		var histories: Array = session.stores["fact_store"].list_facts().filter(
			func(fact: Dictionary) -> bool:
				return (
					str(fact.get("fact_type", ""))
					in ["settlement_industry_founded", "settlement_industry_retired"]
				)
		)
		var rope_count := 0
		for item: Dictionary in session.stores["item_store"].list_items():
			if str(item.get("item_def_id", "")) == "item.fiber_rope":
				rope_count += int(item.get("quantity", 0))
		_check(
			not histories.is_empty() and rope_count > 0,
			"seed %d develops a productive industry without intervention" % seed
		)
		_check(
			bool(session.validate_persistent_references().get("ok", false)),
			"seed %d keeps persistent references valid" % seed
		)
		var structural_history: Array = []
		for fact: Dictionary in histories:
			structural_history.append([
				fact.get("industry_id", ""), fact.get("day", 0),
				fact.get("actor_id", ""), fact.get("former_occupation_id", "")
			])
		var report := {
			"seed": seed,
			"days": 7,
			"injected_behavior_count": 0,
			"history": histories,
			"rope_count": rope_count,
			"structural_history": structural_history,
			"store_signature": JSON.stringify(session.get_save_store_data()).sha256_text()
		}
		reports.append(report)
		print("[INDUSTRY HISTORY] ", JSON.stringify(report))
	_check(
		reports[0] == reports[1], "same seed repeats the complete saved world and industry history"
	)
	_check(
		reports[0]["structural_history"] != reports[2]["structural_history"],
		"different seeds change a founding date, occupation or actual founder, not just names"
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var output := FileAccess.open("user://tests/generated_industry_history.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": failures.is_empty(), "runs": reports}, "\t"))
	output.close()
	print("[INDUSTRY HISTORY RESULT] ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	print("[INDUSTRY HISTORY %s] %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)
