extends RefCounted
class_name EquipmentGenerator

const RARITIES := [
	{"id":"common", "name":"普通", "weight":56, "mul":1.0, "affix_count":[0,1]},
	{"id":"uncommon", "name":"精良", "weight":26, "mul":1.15, "affix_count":[1,2]},
	{"id":"rare", "name":"稀有", "weight":12, "mul":1.35, "affix_count":[2,3]},
	{"id":"epic", "name":"史诗", "weight":5, "mul":1.6, "affix_count":[3,4]},
	{"id":"legendary", "name":"传说", "weight":1, "mul":2.0, "affix_count":[4,5]}
]

const BASE_TYPES := [
	{"id":"sword", "name":"长剑", "slot":"weapon", "base":{"atk":8, "crit":2}},
	{"id":"spear", "name":"长枪", "slot":"weapon", "base":{"atk":7, "acc":3}},
	{"id":"bow", "name":"长弓", "slot":"weapon", "base":{"atk":6, "dex":2}},
	{"id":"staff", "name":"法杖", "slot":"weapon", "base":{"int":3, "sanity":3}},
	{"id":"armor", "name":"护甲", "slot":"armor", "base":{"hp":10, "con":2}},
	{"id":"cloak", "name":"披风", "slot":"armor", "base":{"dex":2, "wis":2}},
	{"id":"ring", "name":"戒指", "slot":"trinket", "base":{"cha":2, "sanity":2}},
	{"id":"boots", "name":"靴子", "slot":"boots", "base":{"move":2, "fatigue_resist":2}}
]

const MATERIALS := [
	{"id":"iron", "name":"铁", "weight":28, "mod":{"atk":2, "hp":2}},
	{"id":"steel", "name":"钢", "weight":22, "mod":{"atk":3, "con":1}},
	{"id":"obsidian", "name":"黑曜石", "weight":12, "mod":{"crit":3, "sanity":-1}},
	{"id":"moon_silver", "name":"月银", "weight":10, "mod":{"wis":2, "sanity":2}},
	{"id":"starbone", "name":"星骨", "weight":8, "mod":{"int":2, "cha":1}},
	{"id":"drift_wood", "name":"流木", "weight":12, "mod":{"dex":2, "move":2}},
	{"id":"fog_fiber", "name":"雾纤", "weight":8, "mod":{"fatigue_resist":3, "hp":-1}}
]

const AFFIXES := [
	{"id":"swift", "name":"疾行", "weight":18, "mod":{"move":3, "dex":1}},
	{"id":"bulwark", "name":"壁垒", "weight":16, "mod":{"hp":6, "con":2}},
	{"id":"keen", "name":"锐刃", "weight":16, "mod":{"atk":4, "crit":2}},
	{"id":"scholar", "name":"求知", "weight":14, "mod":{"int":3, "wis":2}},
	{"id":"oracle", "name":"先见", "weight":10, "mod":{"wis":3, "sanity":4}},
	{"id":"bloodline", "name":"血誓", "weight":9, "mod":{"atk":5, "hp":-4}},
	{"id":"hollow", "name":"空蚀", "weight":8, "mod":{"sanity":-4, "crit":4}},
	{"id":"merchant", "name":"商契", "weight":9, "mod":{"cha":3, "coin_gain":2}}
]

const SIDE_EFFECTS := [
	{"id":"none", "name":"无副作用", "weight":64, "mod":{}},
	{"id":"cold_touch", "name":"寒触", "weight":10, "mod":{"cold":6}},
	{"id":"sleep_leak", "name":"扰眠", "weight":8, "mod":{"sleep":-4}},
	{"id":"hunger_bite", "name":"噬饥", "weight":8, "mod":{"hunger":-4}},
	{"id":"mad_whisper", "name":"低语", "weight":6, "mod":{"sanity":-5}},
	{"id":"life_tithe", "name":"汲命", "weight":4, "mod":{"hp":-6, "atk":2}}
]

func roll(rng: RandomNumberGenerator, seed_tag: String="") -> Dictionary:
	var rarity: Dictionary = _pick_weighted(rng, RARITIES)
	var base: Dictionary = _pick_weighted(rng, BASE_TYPES)
	var mat: Dictionary = _pick_weighted(rng, MATERIALS)
	var side: Dictionary = _pick_weighted(rng, SIDE_EFFECTS)

	var ac_range: Array = rarity.get("affix_count", [0, 1])
	var affix_count: int = rng.randi_range(int(ac_range[0]), int(ac_range[1]))
	var used: Dictionary = {}
	var affixes: Array[Dictionary] = []
	for _i in range(affix_count):
		var af: Dictionary = _pick_unique_weighted(rng, AFFIXES, used)
		if af.is_empty():
			break
		affixes.append(af)

	var stat_mod: Dictionary = {}
	_merge_mod(stat_mod, base.get("base", {}))
	_merge_mod(stat_mod, mat.get("mod", {}))
	for af in affixes:
		_merge_mod(stat_mod, af.get("mod", {}))
	_merge_scaled(stat_mod, float(rarity.get("mul", 1.0)))
	_merge_mod(stat_mod, side.get("mod", {}))

	var affix_names: Array[String] = []
	for af2 in affixes:
		affix_names.append(String(af2.get("name", "")))
	var rid: String = String(rarity.get("id", "common"))
	var sid: String = String(side.get("id", "none"))
	var rarity_prefix: Dictionary = {
		"common": "",
		"uncommon": "精制",
		"rare": "稀有",
		"epic": "史诗",
		"legendary": "传说"
	}
	var name: String = "%s%s%s" % [
		String(rarity_prefix.get(rid, "")),
		String(mat.get("name", "")),
		String(base.get("name", ""))
	]
	if not affix_names.is_empty():
		name += "·" + affix_names[0]
	var uniq: int = rng.randi_range(1000, 9999)
	var item_id: String = "eq.%s.%s.%s.%d" % [String(base.get("id", "item")), rid, sid, uniq]
	if seed_tag != "":
		item_id += "." + seed_tag

	return {
		"id": item_id,
		"name": name,
		"slot": String(base.get("slot", "trinket")),
		"rarity": String(rarity.get("id", "common")),
		"rarity_name": String(rarity.get("name", "普通")),
		"material": String(mat.get("id", "iron")),
		"material_name": String(mat.get("name", "铁")),
		"base_type": String(base.get("id", "item")),
		"affixes": affix_names,
		"side_effect": String(side.get("name", "无副作用")),
		"mods": stat_mod
	}

func _merge_mod(dst: Dictionary, mod_any: Variant) -> void:
	if not (mod_any is Dictionary):
		return
	var mod: Dictionary = mod_any as Dictionary
	for k in mod.keys():
		dst[k] = float(dst.get(k, 0.0)) + float(mod[k])

func _merge_scaled(dst: Dictionary, mul: float) -> void:
	for k in dst.keys():
		dst[k] = round(float(dst[k]) * mul)

func _pick_unique_weighted(rng: RandomNumberGenerator, pool: Array, used: Dictionary) -> Dictionary:
	var filtered: Array = []
	for p in pool:
		if not (p is Dictionary):
			continue
		var d: Dictionary = p as Dictionary
		var pid: String = String(d.get("id", ""))
		if pid == "" or used.get(pid, false):
			continue
		filtered.append(d)
	if filtered.is_empty():
		return {}
	var out: Dictionary = _pick_weighted(rng, filtered)
	var oid: String = String(out.get("id", ""))
	if oid != "":
		used[oid] = true
	return out

func _pick_weighted(rng: RandomNumberGenerator, pool: Array) -> Dictionary:
	var sum: float = 0.0
	for p in pool:
		if p is Dictionary:
			sum += float((p as Dictionary).get("weight", 1.0))
	if sum <= 0.0:
		return {}
	var r: float = rng.randf() * sum
	var acc: float = 0.0
	for p2 in pool:
		if not (p2 is Dictionary):
			continue
		var d2: Dictionary = p2 as Dictionary
		acc += float(d2.get("weight", 1.0))
		if r <= acc:
			return d2
	return (pool.back() as Dictionary) if not pool.is_empty() and pool.back() is Dictionary else {}
