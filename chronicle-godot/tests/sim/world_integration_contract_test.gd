extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Integration = preload("res://scripts/sim/generation/world_integration.gd")
const Gear = preload("res://scripts/sim/equipment/resident_equipment.gd")
const ThreatFood = preload("res://scripts/sim/combat/threat_subsistence.gd")
const Builder = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Access = preload("res://scripts/sim/resource/resource_access.gd")
var failures: Array = []
var checks := 0


static func options(seed: int = 81001) -> Dictionary:
	return {"scenario": "echo_realm", "challenge_seed_override": seed,
		"household_food_hauling_version": 1, "worksite_food_storage_version": 1,
		"household_food_budget_version": 1, "resident_subsistence_version": 1, "work_rules_version": 1,
		"community_rules_version": 1, "world_danger_version": 1, "player_life_version": 2,
		"content_extension_version": 2, "body_rules_version": 1, "integration_rules_version": 1}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var model := Live.new()
	var start: Dictionary = model.start(options())
	check(start.success, "explicit integrated world starts: " + str(start.get("error", "")))
	if not start.success:
		quit(1)
		return
	var path := "user://tests/world_integration_contract/initial.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(model.save_to_path(path, true).success, "native save")
	var other := Live.new()
	var loaded: Dictionary = other.load_from_path(path)
	check(loaded.success, "native restore: " + str(loaded.get("error", "")))
	var old := Live.new()
	var old_options := options()
	old_options.erase("integration_rules_version")
	check(old.start(old_options).success, "previous world still starts")
	check(not old.session.registry.has_definition("item", "item.woven_reed_vest"), "old world acquires no new equipment definitions")
	_threat_case(model)
	print("WORLD_INTEGRATION_CONTRACT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _threat_case(model: Variant) -> void:
	var session: Variant = model.session
	var snapshot: Variant = Builder.new().build_snapshot(session.context, session.stores, true)
	var threat: Dictionary = snapshot.get_entity("world_threat.field_boar")
	var config: Dictionary = session.fixture_source_data.world_danger
	var rules: Dictionary = config.foraging
	var tick := {"day": 1, "hour": 12}
	for number: int in range(int(rules.work_hours)):
		var result: Variant = ThreatFood.resolve(snapshot, tick, config)
		var committed: bool = session.writer.apply_result(result, session.stores)
		check(committed, "test injection: repeated controlled feeding tick %d: %s" % [number, "" if committed else str(session.writer.last_report)])
		snapshot = Builder.new().build_snapshot(session.context, session.stores, true)
	var meals: Array = snapshot.get_facts_by_type("world_threat_fed")
	check(meals.size() == 1, "finite work precedes one wildlife meal")
	if meals.is_empty():
		return
	var stock: Dictionary = snapshot.get_resource_stock(meals[0].stock_id)
	check(stock.last_delta == -float(rules.amount), "wildlife consumes same finite resource stock as residents")
	check(snapshot.get_entity(threat.id).states.danger_retreat_until == 36 + int(rules.sated_hours), "feeding gives finite respite")
	check(Access.denial(snapshot, stock, "generated_resident.echo_terrace.001", "wildlife_foraging", rules.amount, 1) != "",
		"resident cannot use wildlife permission to bypass commons rules")
	check(Access.denial(snapshot, stock, threat.id, "wildlife_foraging", float(rules.amount) + 1, 1) != "",
		"feeding permission cannot exceed configured finite meal")
	var remote := stock.duplicate(true)
	remote.location_id = "generated_location.echo_landing.commons"
	check(Access.denial(snapshot, remote, threat.id, "wildlife_foraging", rules.amount, 1) != "",
		"threat cannot consume remote resources")
	var wrong_food := stock.duplicate(true)
	wrong_food.tags = ["stone"]
	check(Access.denial(snapshot, wrong_food, threat.id, "wildlife_foraging", rules.amount, 1) != "",
		"configured diet cannot consume unrelated material")
	check(ThreatFood.resolve(snapshot, tick, config).is_empty(), "sated threat does not eat again or emit an infinite event")
	var empty: Variant = Builder.new().build_snapshot(session.context, session.stores, true)
	# Counterexamples use isolated snapshots, never alter the running native world.
	for entity: Dictionary in empty.entities:
		if entity.id == threat.id:
			entity.states.danger_retreat_until = 0
			entity.states.threat_foraging_hours = int(rules.work_hours) - 1
	for resource: Dictionary in empty.resource_stocks:
		resource.current = 0
	var denied: Variant = ThreatFood.resolve(empty, tick, config)
	check(denied.facts_added.is_empty() and denied.resource_changes.is_empty(), "depleted food cannot create a meal or forced respite")
	var damaged: Dictionary = session.fixture_source_data.duplicate(true)
	damaged.resident_daily_life.activity_choice.weights.resupply += 1
	check(Integration.configure(damaged, session.registry).begins_with("integration_signature_mismatch"), "changed compiled rules cannot masquerade as old integration")


func check(passed: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)
