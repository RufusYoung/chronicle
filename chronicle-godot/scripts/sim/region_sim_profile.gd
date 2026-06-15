extends RefCounted
class_name RegionSimProfile

const LakeTownSeedProfileModel = preload(
	"res://scripts/sim/lake_town_seed_profile.gd"
)

var lake_town_seed_profile := LakeTownSeedProfileModel.new()


func build_region_profile(
		seed_value: int,
		module_id: String,
		region_id: String
	) -> Dictionary:
	return {
		"profile_id": "%s_%d" % [module_id, seed_value],
		"seed": seed_value,
		"region_id": region_id,
		"module_id": module_id,
		"macro_pressure": {},
		"resources": {},
		"social_roles": {},
		"npc_bias": {},
		"location_bias": {},
		"external_pressure": {},
		"quality_targets": {},
	}


func wrap_lake_town_seed_profile(
		seed_profile: Dictionary
	) -> Dictionary:
	var seed_value := int(seed_profile.get("seed", 0))
	var profile := build_region_profile(
		seed_value,
		"lake_town_food_crisis",
		"border_town"
	)
	profile["profile_id"] = "lake_town_food_crisis_%d" % seed_value
	profile["macro_pressure"] = (
		seed_profile.get("macro_pressure", {}) as Dictionary
	).duplicate(true)
	profile["resources"] = {
		"abandoned_granary": (
			seed_profile.get("abandoned_granary", {}) as Dictionary
		).duplicate(true),
		"lake_town_market": (
			seed_profile.get("lake_town_market", {}) as Dictionary
		).duplicate(true),
	}
	profile["social_roles"] = {
		"old_chen": "shopkeeper_and_guardian",
		"chen_mi": "dependent_child",
		"ma_shen": "neighbor_helper",
		"liu_zhangfang": "creditor",
	}
	profile["npc_bias"] = {
		"old_chen": (
			seed_profile.get("old_chen", {}) as Dictionary
		).duplicate(true),
		"chen_mi": (
			seed_profile.get("chen_mi", {}) as Dictionary
		).duplicate(true),
		"ma_shen": (
			seed_profile.get("ma_shen", {}) as Dictionary
		).duplicate(true),
		"liu_zhangfang": (
			seed_profile.get("liu_zhangfang", {}) as Dictionary
		).duplicate(true),
	}
	profile["location_bias"] = {
		"abandoned_granary": (
			seed_profile.get("abandoned_granary", {}) as Dictionary
		).duplicate(true),
		"lake_town_market": (
			seed_profile.get("lake_town_market", {}) as Dictionary
		).duplicate(true),
	}
	var macro := seed_profile.get("macro_pressure", {}) as Dictionary
	profile["external_pressure"] = {
		"guard_pressure": float(
			macro.get("guard_pressure_bias", 0.0)
		),
		"market_disruption": float(
			macro.get("market_disruption_bias", 0.0)
		),
	}
	profile["quality_targets"] = {
		"unresolved_extreme_hunger": 0,
		"dangling_major_fact": 0,
		"impossible_shop_state": 0,
	}
	profile["legacy_profile"] = seed_profile.duplicate(true)
	return profile


func build_lake_town_region_profile(seed_value: int) -> Dictionary:
	return wrap_lake_town_seed_profile(
		lake_town_seed_profile.build_profile(seed_value)
	)


func describe_region_profile(profile: Dictionary) -> Dictionary:
	return {
		"profile_id": String(profile.get("profile_id", "")),
		"seed": int(profile.get("seed", 0)),
		"region_id": String(profile.get("region_id", "")),
		"module_id": String(profile.get("module_id", "")),
		"macro_pressure": (
			profile.get("macro_pressure", {}) as Dictionary
		).duplicate(true),
		"resource_ids": (
			profile.get("resources", {}) as Dictionary
		).keys(),
		"social_role_ids": (
			profile.get("social_roles", {}) as Dictionary
		).keys(),
		"npc_bias_ids": (
			profile.get("npc_bias", {}) as Dictionary
		).keys(),
		"location_bias_ids": (
			profile.get("location_bias", {}) as Dictionary
		).keys(),
		"external_pressure": (
			profile.get("external_pressure", {}) as Dictionary
		).duplicate(true),
		"quality_targets": (
			profile.get("quality_targets", {}) as Dictionary
		).duplicate(true),
	}
