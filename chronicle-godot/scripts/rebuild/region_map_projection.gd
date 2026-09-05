extends RefCounted
## Public road topology only. No remote resident goals, inventories or debug facts.

const CanonWorld = preload("res://scripts/sim/generation/canon_world_setup.gd")

const TERRAIN_NAMES := {"wetland": "湿地", "waterfront": "水岸", "riverside": "河岸",
	"fertile": "沃土", "upland": "高地", "windy": "多风", "roadside": "临路",
	"slope": "缓坡", "defensible": "易守", "marsh": "湿地", "lake_edge": "湖岸"}


func build(session: Variant, current_settlement_id: String) -> Dictionary:
	var network: Dictionary = session.get_settlement_network_summary()
	if network.is_empty():
		return {}
	var sites: Array = []
	for site: Dictionary in network.get("sites", []):
		var id := str(site.get("settlement_id", ""))
		var terrain: Array[String] = []
		for tag: String in site.get("terrain_tags", []):
			if TERRAIN_NAMES.has(tag) and terrain.size() < 2:
				terrain.append(TERRAIN_NAMES[tag])
		sites.append({"id": id, "name": str(site.get("settlement_name", "")),
			"hub_location_id": str(site.get("hub_location_id", "")),
			"terrain_label": " · ".join(terrain)})
	var roads: Array = []
	for link: Dictionary in network.get("links", []):
		roads.append({"id": str(link.get("link_id", "")),
			"from": str(link.get("settlement_a_id", "")), "to": str(link.get("settlement_b_id", "")),
			"hours": int(link.get("travel_hours", 0))})
	var result := {"layout": "topology_not_geography", "seed": int(network.get("generation_seed", 0)),
		"current_settlement_id": current_settlement_id, "sites": sites, "roads": roads}
	var canon := CanonWorld.public_context(session.fixture_source_data)
	if not canon.is_empty():
		result["canon"] = canon
	return result
