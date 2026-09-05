extends SceneTree

const Canon = preload("res://scripts/sim/generation/canon_world_setup.gd")
const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
var checks := 0
var failures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Canon.CATALOG_PATH))
	_check(Canon.validate_catalog(catalog).ok, "authored catalog references valid")
	_check(catalog.regions.size() == 6 and catalog.factions.size() == 17, "six original macro regions and seventeen organizations")
	_check(catalog.unresolved.size() == 3, "conflicting authored geography retained as unresolved")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Live.CANON_WORLD))
	var original := JSON.stringify(fixture)
	var copy := fixture.duplicate(true)
	_check(Canon.prepare(copy).ok and JSON.stringify(fixture) == original, "prepared copy does not mutate input")
	var prepared := JSON.stringify(copy)
	_check(Canon.prepare(copy).ok and JSON.stringify(copy) == prepared, "preparation idempotent")
	copy.world_canon.catalog_path = "res://not_a_live_dependency.json"
	_check(Canon.prepare(copy).ok, "embedded save snapshot does not depend on current file path")
	copy.world_canon.catalog_snapshot.version = 99
	_check(not Canon.prepare(copy).ok, "unknown embedded canon version rejected")
	copy = fixture.duplicate(true)
	copy.world_canon.scope_id = "seventh_outpost"
	_check(not Canon.prepare(copy).ok, "prototype cannot silently become a canon anchor")
	copy = fixture.duplicate(true)
	copy.settlement_network_generation.sites[0].resources[0].tags.append("brine")
	_check(not Canon.prepare(copy).ok, "test injection: unsupported salt water resource rejected")
	copy = fixture.duplicate(true)
	copy.settlement_network_generation.sites[0].terrain.terrain_id = "windy_upland"
	_check(not Canon.prepare(copy).ok, "test injection: outside-scope terrain rejected")
	var invalid := catalog.duplicate(true)
	invalid.places[0].faction_ids = ["unknown"]
	_check(not Canon.validate_catalog(invalid).ok, "dangling faction rejected")
	invalid = catalog.duplicate(true)
	invalid.regions.append(invalid.regions[0].duplicate(true))
	_check(not Canon.validate_catalog(invalid).ok, "duplicate authored id rejected")
	invalid = catalog.duplicate(true)
	invalid.places[0].parent_place_id = invalid.places[0].id
	_check(not Canon.validate_catalog(invalid).ok, "cyclic place ancestry rejected")
	invalid = catalog.duplicate(true)
	invalid.simulation_scopes[0].faction_id = "wardens_kingdom"
	_check(not Canon.validate_catalog(invalid).ok, "western kingdom cannot become lake community by scope typo")
	invalid = catalog.duplicate(true)
	invalid.regions[0].erase("name")
	_check(not Canon.validate_catalog(invalid).ok, "incomplete embedded labels rejected before projection")
	var signatures: Array = []
	for seed: int in [81001, 82002, 81001]:
		var model := Live.new()
		_check(model.start({"scenario": "echo_realm", "challenge_seed_override": seed}).success, "canon formal start %d" % seed)
		if not model.is_ready():
			continue
		var region: Dictionary = model.build_view_data().region_map
		_check(region.sites.size() == 2 and region.roads.size() == 1, "runtime scope has two distinct small settlements")
		_check(region.canon.place_name == "回音港" and region.canon.faction_name == "湖上自由民", "public geography matches authored anchor")
		var residents := 0
		for entity: Dictionary in model.session.stores.entity_store.entities.values():
			if "generated_resident" in entity.get("tags", []):
				residents += 1
		_check(residents == 16, "sixteen residents, not port city population")
		for location: Dictionary in model.session.context.locations.values():
			_check(location.get("canon_origin", {}).get("place_id") == "echo_port", "generated place preserves parent anchor")
		_check(not model.session.fixture_source_data.has("organization_generation_result"), "catalog factions not fabricated as live organizations")
		_check(model.session.advance_time(24, "canon_passive", {"scope_type": "global", "scope_id": ""}).success, "day of autonomous world time")
		_check(model.session.action_count == 0 and model.session.travel_count == 0, "no player actions in passive sample")
		_check(model.session.validate_persistent_references().ok, "native runtime reference audit")
		var path := "user://tests/canon_world/day1_%d.json" % seed
		_check(model.save_to_path(path, true).success, "canon and native world saved")
		var restored := Live.new()
		_check(restored.load_from_path(path).success, "canon world restored")
		_check(_state(model) == _state(restored), "all Stores time RNG and history restored")
		_check(restored.build_view_data().region_map.canon == region.canon, "authored background restored without reskin")
		model.session.advance_time(1, "continuation", {"scope_type": "global", "scope_id": ""})
		restored.session.advance_time(1, "continuation", {"scope_type": "global", "scope_id": ""})
		_check(_state(model) == _state(restored), "native continuation equal")
		signatures.append(_state(model))
	_check(signatures.size() == 3 and signatures[0] != signatures[1], "seeds retain different actual world states")
	_check(signatures.size() == 3 and signatures[0] == signatures[2], "same seed reproduces complete day-one continuation")
	var legacy := Live.new()
	_check(legacy.start({"scenario": "generated_network", "challenge_seed_override": 81001}).success, "legacy synthetic network retained")
	_check(not legacy.session.fixture_source_data.has("world_canon") and not legacy.build_view_data().region_map.has("canon"), "legacy world is not promoted to authored geography")
	print("CANON_WORLD_CONTRACT_RESULT %d checks %s" % [checks, "PASS" if failures.is_empty() else str(failures)])
	quit(0 if failures.is_empty() else 1)


func _state(model: Variant) -> String:
	var e: Dictionary = model.session.build_save_envelope()
	return JSON.stringify(JSON.parse_string(JSON.stringify({"stores": e.stores, "session": e.session,
		"world_time": e.world_time, "rng_states": e.rng_states, "world_log": e.world_log}, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
