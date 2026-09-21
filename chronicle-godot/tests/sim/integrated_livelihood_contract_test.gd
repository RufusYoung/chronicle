extends "res://tests/sim/community_assistance_contract_test.gd"

const IntegrationOptions = preload("res://tests/sim/world_integration_contract_test.gd")
const Activity = preload("res://scripts/sim/npc/resident_activity_choice.gd")


func _run() -> void:
	var live := Live.new()
	_check(live.start(IntegrationOptions.options()).success, "integrated livelihood fixture starts")
	if not live.is_ready():
		_finish()
		return
	var id := "generated_resident.echo_landing.001"
	var fixture: Dictionary = live.session.fixture_source_data.duplicate(true)
	var resident: Dictionary = _entity(fixture, id)
	resident.states.merge({"location_id": resident.states.workplace_id, "daily_route_id": "", "hunger": "extreme", "fatigue": 0}, true)
	fixture.initial_items = fixture.initial_items.filter(func(item: Dictionary) -> bool:
		return item.holder.id != id or "food" not in live.session.registry.get_definition("item", item.item_def_id).get("tags", []))
	var session: Variant = _session(fixture)
	var snapshot: Variant = _snapshot(session)
	var actor: Dictionary = snapshot.get_entity(id)
	var profiles: Array = fixture.generated_livelihood_profiles
	var profile: Dictionary = profiles.filter(func(p: Dictionary) -> bool: return p.occupation_id == actor.states.occupation_id and p.settlement_id == actor.states.settlement_id)[0]
	var site := str(profile.workplace_id)
	var rows: Array = []
	Activity.propose(rows, "work", site, "working", "测试注入：常规捕捞", [], "recipe:" + str(profile.work_recipe.recipe_id))
	Activity.propose(rows, "forage", site, "foraging", "测试注入：已知家庭缺粮", ["test_injection.known_need"], "subsistence")
	var choice := Activity.choose(rows, actor, [], Daily.new(), snapshot, profiles, session.registry, fixture.resident_daily_life.activity_choice, fixture.resident_daily_life.food_access)
	_check(choice.kind == "work", "capable food producer serves personal and known family need through higher-output job")
	snapshot.items = snapshot.items.duplicate(true)
	for item: Dictionary in snapshot.items:
		if item.holder.id == id and "rope" in item.get("tags", []):
			item.condition.durability = 0
	choice = Activity.choose(rows, actor, [], Daily.new(), snapshot, profiles, session.registry, fixture.resident_daily_life.activity_choice, fixture.resident_daily_life.food_access)
	_check(choice.kind == "forage", "broken net tool changes same need to hand gathering, not phantom professional output")
	actor.states.health = 32
	var router := Daily.new()
	var routes: Array = router._routes(snapshot, session.settlement_network_runtime, session.context.locations, session.world_tick_adapter.daily_life_routes, fixture.resident_daily_life)
	var food_goal: String = router._food_goal(snapshot, actor, routes, profiles, {"day": 1, "hour": 12}, fixture.resident_daily_life.food_access,
		session.settlement_network_runtime, session.context.locations, snapshot.items, {})
	_check(food_goal != "", "injured food producer can seek food instead of being permanently forbidden to shop")
	var old_config: Dictionary = fixture.resident_daily_life.food_access.duplicate(true)
	old_config.subsistence.erase("integration_version")
	var healthy: Variant = _snapshot(session)
	healthy.items = healthy.items.filter(func(item: Dictionary) -> bool: return item.holder.id != id or not Food.is_food(item))
	food_goal = router._food_goal(healthy, actor, routes, profiles, {"day": 1, "hour": 12}, old_config,
		session.settlement_network_runtime, session.context.locations, healthy.items, {})
	_check(food_goal == "", "old producer-shopping rules remain unchanged")
	_finish()
