extends RefCounted
## Authored geography constrains bootstrap; it is not a second live world state.

const CATALOG_PATH := "res://data/sim/raw/world_defs/echo_realm_canon_v1.json"


static func prepare(fixture: Dictionary) -> Dictionary:
	if not fixture.has("world_canon"):
		return {"ok": true}
	if not fixture.world_canon is Dictionary:
		return _failure("canon_config_invalid")
	var config: Dictionary = fixture.world_canon
	if config.get("version") != 1:
		return _failure("canon_version_unsupported")
	var catalog: Variant = config.get("catalog_snapshot", {})
	if not catalog is Dictionary:
		return _failure("canon_snapshot_invalid")
	# A save retains its authored snapshot even if the source catalog later changes.
	if not config.has("catalog_snapshot"):
		if str(config.get("catalog_path", "")) != CATALOG_PATH:
			return _failure("canon_catalog_path_unknown")
		catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var validation := validate_catalog(catalog)
	if not validation.ok:
		return validation
	var scope := _row(catalog.simulation_scopes, str(config.get("scope_id", "")))
	if scope.is_empty():
		return _failure("canon_scope_unknown")
	var network: Dictionary = fixture.get("settlement_network_generation", {})
	for site: Dictionary in network.get("sites", []):
		if site.get("terrain", {}).get("terrain_id", "") not in scope.allowed_terrain_ids:
			return _failure("canon_terrain_outside_scope")
		for resource: Dictionary in site.get("resources", []):
			for tag: Variant in resource.get("tags", []):
				if tag in scope.excluded_resource_tags:
					return _failure("canon_resource_outside_scope:%s" % str(tag))
	config["catalog_snapshot"] = catalog.duplicate(true)
	return {"ok": true}


static func validate_catalog(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("catalog_id") != "canon.echo_realm" or value.get("version") != 1:
		return _failure("canon_catalog_invalid")
	var catalog: Dictionary = value
	for field: String in ["world_name", "current_era"]:
		if not _named(catalog.get(field)):
			return _failure("canon_label_missing:%s" % field)
	if not catalog.get("sources") is Dictionary or catalog.sources.is_empty():
		return _failure("canon_sources_missing")
	for source: Variant in catalog.sources.values():
		if not _named(source):
			return _failure("canon_source_path_invalid")
	var indices := {}
	for table: String in ["regions", "factions", "places", "history_anchors", "dependencies", "simulation_scopes"]:
		if not catalog.get(table) is Array or catalog[table].is_empty():
			return _failure("canon_table_invalid:%s" % table)
		indices[table] = {}
		for row: Variant in catalog[table]:
			if not row is Dictionary or not _named(row.get("id")) or indices[table].has(row.id):
				return _failure("canon_id_missing_or_duplicate:%s" % table)
			if table in ["regions", "places", "factions"] and not _named(row.get("name")):
				return _failure("canon_label_missing:%s" % table)
			if table == "regions" and (not _named(row.get("position")) or not _named(row.get("description"))):
				return _failure("canon_region_description_missing")
			if table != "simulation_scopes" and not catalog.sources.has(row.get("source", "")):
				return _failure("canon_source_unknown")
			indices[table][row.id] = row
	for table: String in ["regions", "places"]:
		for row: Dictionary in catalog[table]:
			if not row.get("faction_ids") is Array:
				return _failure("canon_factions_invalid")
			for faction: Variant in row.faction_ids:
				if not indices.factions.has(faction):
					return _failure("canon_faction_unknown")
	for place: Dictionary in catalog.places:
		if not indices.regions.has(place.get("region_id")):
			return _failure("canon_region_unknown")
		var visited := {place.id: true}
		var current: Dictionary = place
		while current.has("parent_place_id"):
			var parent: Variant = current.parent_place_id
			if not indices.places.has(parent) or visited.has(parent):
				return _failure("canon_place_parent_invalid")
			visited[parent] = true
			current = indices.places[parent]
	for relation: Dictionary in catalog.dependencies:
		if not indices.factions.has(relation.get("supplier")) or not indices.factions.has(relation.get("recipient")):
			return _failure("canon_dependency_unknown")
	for scope: Dictionary in catalog.simulation_scopes:
		if not indices.places.has(scope.get("place_id")) or not indices.regions.has(scope.get("region_id")) \
				or not indices.factions.has(scope.get("faction_id")):
			return _failure("canon_scope_reference_unknown")
		var place: Dictionary = indices.places[scope.place_id]
		if place.region_id != scope.region_id or scope.faction_id not in place.faction_ids:
			return _failure("canon_scope_affiliation_mismatch")
		if not scope.get("allowed_terrain_ids") is Array or scope.allowed_terrain_ids.is_empty() \
				or not scope.get("excluded_resource_tags") is Array:
			return _failure("canon_scope_constraints_invalid")
	return {"ok": true}


static func bind_locations(fixture: Dictionary) -> void:
	if not fixture.has("world_canon"):
		return
	var config: Dictionary = fixture.world_canon
	var scope := _row(config.catalog_snapshot.simulation_scopes, str(config.scope_id))
	for location: Dictionary in fixture.get("locations", {}).values():
		location["canon_origin"] = {"region_id": scope.region_id, "place_id": scope.place_id,
			"faction_id": scope.faction_id, "detail_kind": "generated_local_detail"}
	for entity: Dictionary in fixture.get("entities", []):
		if "generated_settlement" in entity.get("tags", []):
			entity["canon_origin"] = {"region_id": scope.region_id, "place_id": scope.place_id,
				"faction_id": scope.faction_id, "detail_kind": "generated_local_detail"}


static func public_context(fixture: Dictionary) -> Dictionary:
	var config: Dictionary = fixture.get("world_canon", {})
	if config.is_empty():
		return {}
	var catalog: Dictionary = config.catalog_snapshot
	var scope := _row(catalog.simulation_scopes, str(config.scope_id))
	var region := _row(catalog.regions, str(scope.region_id))
	var place := _row(catalog.places, str(scope.place_id))
	var faction := _row(catalog.factions, str(scope.faction_id))
	var regions: Array = []
	for row: Dictionary in catalog.regions:
		regions.append({"id": row.id, "name": row.name, "position": row.position})
	return {"world_name": catalog.world_name, "era": catalog.current_era,
		"region_id": region.id, "region_name": region.name, "place_id": place.id, "place_name": place.name,
		"faction_name": faction.name, "description": region.description,
		"regions": regions, "scope_note": "回音港周边小聚落正在运行；港城、其他地区与大势力尚未运行模拟。",
		"knowledge_kind": "authored_geographic_background"}


static func _row(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.get("id", "")) == id:
			return row
	return {}


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}


static func _named(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()
