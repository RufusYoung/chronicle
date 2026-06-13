extends RefCounted
class_name WorldSimState


class RegionState:
	extends RefCounted

	var id: String = ""
	var name: String = ""
	var danger: float = 0.0
	var order: float = 0.0
	var scarcity: float = 0.0
	var mystic: float = 0.0
	var food: float = 0.0
	var herbs: float = 0.0
	var relics: float = 0.0
	var information: float = 0.0
	var beasts: float = 0.0
	var population: float = 0.0
	var owner_faction_id: String = ""
	var tags: Array[String] = []
	var recent_changes: Array[Dictionary] = []

	static func from_dictionary(data: Dictionary) -> RegionState:
		var region := RegionState.new()
		region.id = String(data.get("id", ""))
		region.name = String(data.get("name", region.id))
		region.danger = float(data.get("danger", 0.0))
		region.order = float(data.get("order", 0.0))
		region.scarcity = float(data.get("scarcity", 0.0))
		region.mystic = float(data.get("mystic", 0.0))
		region.food = float(data.get("food", 0.0))
		region.herbs = float(data.get("herbs", 0.0))
		region.relics = float(data.get("relics", 0.0))
		region.information = float(data.get("information", 0.0))
		region.beasts = float(data.get("beasts", 0.0))
		region.population = float(data.get("population", 0.0))
		region.owner_faction_id = String(data.get("owner_faction_id", ""))
		for tag: Variant in data.get("tags", []):
			region.tags.append(String(tag))
		return region

	func resource_value(resource_id: String) -> float:
		match resource_id:
			"food":
				return food
			"herbs":
				return herbs
			"relics":
				return relics
			"information":
				return information
		return 0.0

	func set_resource_value(resource_id: String, value: float) -> void:
		var clamped := clampf(value, 0.0, 100.0)
		match resource_id:
			"food":
				food = clamped
			"herbs":
				herbs = clamped
			"relics":
				relics = clamped
			"information":
				information = clamped

	func to_dictionary() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"danger": danger,
			"order": order,
			"scarcity": scarcity,
			"mystic": mystic,
			"food": food,
			"herbs": herbs,
			"relics": relics,
			"information": information,
			"beasts": beasts,
			"population": population,
			"owner_faction_id": owner_faction_id,
			"tags": tags.duplicate(),
		}


class FactionState:
	extends RefCounted

	var id: String = ""
	var name: String = ""
	var power: float = 0.0
	var wealth: float = 0.0
	var food_need: float = 0.0
	var hostility_to_player: float = 0.0
	var relations: Dictionary = {}
	var goal: String = ""
	var known_facts: Array[String] = []
	var active_region_id: String = ""

	static func from_dictionary(data: Dictionary) -> FactionState:
		var faction := FactionState.new()
		faction.id = String(data.get("id", ""))
		faction.name = String(data.get("name", faction.id))
		faction.power = float(data.get("power", 0.0))
		faction.wealth = float(data.get("wealth", 0.0))
		faction.food_need = float(data.get("food_need", 0.0))
		faction.hostility_to_player = float(data.get("hostility_to_player", 0.0))
		faction.relations = (data.get("relations", {}) as Dictionary).duplicate(true)
		faction.goal = String(data.get("goal", ""))
		for fact_id: Variant in data.get("known_facts", []):
			faction.known_facts.append(String(fact_id))
		faction.active_region_id = String(data.get("active_region_id", ""))
		return faction

	func to_dictionary() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"power": power,
			"wealth": wealth,
			"food_need": food_need,
			"hostility_to_player": hostility_to_player,
			"relations": relations.duplicate(true),
			"goal": goal,
			"known_facts": known_facts.duplicate(),
			"active_region_id": active_region_id,
		}


class WorldFact:
	extends RefCounted

	var id: String = ""
	var day: int = 0
	var type: String = ""
	var region_id: String = ""
	var faction_id: String = ""
	var data: Dictionary = {}


class WorldNews:
	extends RefCounted

	var id: String = ""
	var day: int = 0
	var region_id: String = ""
	var source: String = ""
	var summary: String = ""
	var truth_level: float = 1.0
	var related_fact_id: String = ""
	var news_key: String = ""
	var stage: int = 1
	var occurrence_count: int = 1
	var world_cause: String = ""
	var related_fact_ids: Array[String] = []
	var kind: String = "news"


class LeadCandidate:
	extends RefCounted

	var id: String = ""
	var day: int = 0
	var type: String = ""
	var region_id: String = ""
	var source_faction_id: String = ""
	var world_cause: String = ""
	var urgency: float = 0.0
	var freshness: float = 1.0
	var risk: float = 0.0
	var possible_actions: Array[String] = []
	var projected_consequences: Dictionary = {}
	var related_fact_id: String = ""


var day: int = 0
var seed: int = 0
var regions: Dictionary = {}
var factions: Dictionary = {}
var world_facts: Array[WorldFact] = []
var world_news: Array[WorldNews] = []
var news_history: Dictionary = {}
var lead_candidates: Array[LeadCandidate] = []
var rng_state: int = 0


func get_region(region_id: String) -> RegionState:
	return regions.get(region_id) as RegionState


func get_faction(faction_id: String) -> FactionState:
	return factions.get(faction_id) as FactionState


func add_fact(
		type_name: String,
		region_id: String,
		faction_id: String,
		fact_data: Dictionary = {}
	) -> WorldFact:
	var fact := WorldFact.new()
	fact.id = "fact_d%02d_%03d_%s" % [day, world_facts.size() + 1, type_name]
	fact.day = day
	fact.type = type_name
	fact.region_id = region_id
	fact.faction_id = faction_id
	fact.data = fact_data.duplicate(true)
	world_facts.append(fact)
	var faction := get_faction(faction_id)
	if faction != null and not fact.id in faction.known_facts:
		faction.known_facts.append(fact.id)
	return fact


func add_news(
		region_id: String,
		source: String,
		summary: String,
		truth_level: float,
		related_fact_id: String,
		metadata: Dictionary = {}
	) -> WorldNews:
	var news := WorldNews.new()
	news.id = "news_d%02d_%03d" % [day, world_news.size() + 1]
	news.day = day
	news.region_id = region_id
	news.source = source
	news.summary = summary
	news.truth_level = clampf(truth_level, 0.0, 1.0)
	news.related_fact_id = related_fact_id
	news.news_key = String(metadata.get("news_key", ""))
	news.stage = int(metadata.get("stage", 1))
	news.occurrence_count = int(metadata.get("occurrence_count", 1))
	news.world_cause = String(metadata.get("world_cause", ""))
	for fact_id: Variant in metadata.get("related_fact_ids", [related_fact_id]):
		news.related_fact_ids.append(String(fact_id))
	news.kind = String(metadata.get("kind", "news"))
	world_news.append(news)
	return news


func find_lead(lead_id: String) -> LeadCandidate:
	for lead: LeadCandidate in lead_candidates:
		if lead.id == lead_id:
			return lead
	return null


func snapshot() -> Dictionary:
	var region_snapshot: Dictionary = {}
	for region_id: String in regions:
		var region := get_region(region_id)
		region_snapshot[region_id] = region.to_dictionary()
	var faction_snapshot: Dictionary = {}
	for faction_id: String in factions:
		var faction := get_faction(faction_id)
		faction_snapshot[faction_id] = faction.to_dictionary()
	return {
		"day": day,
		"regions": region_snapshot,
		"factions": faction_snapshot,
		"news_count": world_news.size(),
		"news_history_count": news_history.size(),
		"lead_count": lead_candidates.size(),
	}
