extends "res://tests/sim/world_content_contract_test.gd"

const Choice = preload("res://scripts/sim/npc/resident_activity_choice.gd")


func _run() -> void:
	var frozen := _runtime_hashes("res://scripts")
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Content.DEFAULT_PATH))
	pack.id = "heldout_content_extension"
	var food: Dictionary = pack.item_defs[0].duplicate(true)
	food.item_def_id = "item.chargrilled_lake_fish"
	food.display_name = "炭烤湖鱼"
	food.display_name_key = "item.chargrilled_lake_fish.name"
	food.tags = ["food", "processed_food", "grilled_fish"]
	food.base_value = 6
	pack.item_defs.append(food)
	var recipe: Dictionary = pack.work_rules.overrides[0].recipe_variants[0].duplicate(true)
	recipe.label = "炭烤湖鱼"
	recipe.work_interval_hours = 3
	recipe.work_recipe.recipe_id = "recipe.chargrill_fish"
	recipe.products[0].item_def_id = food.item_def_id
	pack.work_rules.overrides[0].recipe_variants.append(recipe)
	var path := "user://tests/world_content/heldout_pack.json"
	_write_json(path, pack)
	var options := OPTIONS.duplicate(true)
	options.content_extension_path = path
	var live := Live.new()
	_check(live.start(options).success, "third food and recipe start through formal external data path")
	if not live.is_ready():
		_finish()
		return
	var session: Variant = live.session
	_processing_case(session.fixture_source_data, "recipe.chargrill_fish")
	var route: Dictionary = session.get_travel_options().filter(func(row: Dictionary) -> bool: return str(row.route_id).ends_with("commons_to_fishery"))[0]
	_check(session.travel(route.route_id).success, "heldout player reaches real processing site")
	_check(Life.options(session).any(func(row: Dictionary) -> bool: return row.action_id == "work:recipe.chargrill_fish" and "鲜鱼" in row.hint), "heldout recipe automatically reaches public player decisions with actual inputs")
	_configuration_choices(session)
	_check(session.save_to_path("user://tests/world_content/heldout_native.json").ok, "heldout definition embeds in native save")
	# Remove the external definition to prove that loading consumes the sealed bootstrap.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/world_content/heldout_native.json").success, "heldout native save restores without external data file")
	_check(restored.registry.has_definition("item", food.item_def_id), "restored registry still contains heldout food")
	_check(session.advance_time(3, "heldout_continue").success and restored.advance_time(3, "heldout_continue").success and _signature(session) == _signature(restored), "heldout native continuation is identical")
	for fault: String in ["unknown_input", "unused_item", "unused_override", "missing_resource"]:
		var invalid := pack.duplicate(true)
		match fault:
			"unknown_input": invalid.work_rules.overrides[0].recipe_variants[-1].work_recipe.item_inputs[0].query.item_def_id = "item.no_such_material"
			"unused_item": invalid.item_defs[-1].tags = ["decoration_without_consumer"]
			"unused_override": invalid.work_rules.overrides[0].product_query = {"tags_all": ["absent_occupation_output"]}
			"missing_resource": invalid.work_rules.overrides[0].recipe_variants[-1].resource_inputs = [{"stock_id": "missing.stock", "amount_per_cycle": 1}]
		_write_json(path, invalid)
		_check(not Live.new().start(options).success, "formal extension rejects " + fault)
	_check(frozen == _runtime_hashes("res://scripts"), "all runtime script hashes unchanged across heldout expansion")
	_write_json("user://tests/world_content/data_only_proof.json", {"runtime_hashes": frozen, "content_pack": pack,
		"checks": checks, "failures": failures, "evidence_kind": "data_only_extension_and_test_injection", "human_ui_play": false})
	print("WORLD_CONTENT_DATA_ONLY_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _configuration_choices(session: Variant) -> void:
	var snapshot: Variant = _snapshot(session)
	var assigned := {}
	for actor: Dictionary in snapshot.get_entities_by_type("person"):
		if actor.has("content_variant_id"):
			assigned[actor.content_variant_id] = true
	_check(assigned.size() == 2, "both resident configurations instantiate inside the existing population")
	var entry := _profile(session.fixture_source_data, "recipe.net_fishing")
	var actor: Dictionary = snapshot.get_entity(entry.actor).duplicate(true)
	actor.states.location_id = entry.primary.workplace_id
	actor.states.hunger = "none"
	var choices: Array = []
	Choice.propose(choices, "rest", actor.states.location_id, "resting", "optional rest")
	Choice.propose(choices, "work", actor.states.location_id, "working", "ordinary labor", [], "recipe:recipe.net_fishing")
	var kinds: Array = []
	for variant: Dictionary in session.fixture_source_data.content_extension.resident_variants:
		actor.states.fatigue = variant.states.fatigue
		kinds.append(Choice.choose(choices, actor, [], null, snapshot, [], session.registry, Choice.PROFILE, {}).kind)
	_check(kinds == ["rest", "work"], "same actor and candidates choose differently from authored fatigue values")
	var config: Dictionary = session.fixture_source_data.world_danger
	var threat: Dictionary = snapshot.get_entities_by_type("creature").filter(func(row: Dictionary) -> bool: return "world_threat" in row.tags)[0]
	_check(not Life.Danger.active(threat, {"day": 2, "hour": 7}, config) and Life.Danger.active(threat, {"day": 2, "hour": 9}, config), "authored threat schedule gates actual encounter availability")


func _runtime_hashes(path: String) -> Dictionary:
	var rows := {}
	for file: String in DirAccess.get_files_at(path):
		if file.ends_with(".gd"):
			rows[path + "/" + file] = FileAccess.get_sha256(path + "/" + file)
	for folder: String in DirAccess.get_directories_at(path):
		rows.merge(_runtime_hashes(path + "/" + folder))
	return rows


func _write_json(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.close()
