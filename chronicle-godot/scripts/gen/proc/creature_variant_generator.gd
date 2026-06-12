extends RefCounted
class_name CreatureVariantGenerator

const SIZES := [
	{"id":"tiny", "name":"微型", "weight":12, "hp_mul":0.7, "atk_mul":0.7},
	{"id":"small", "name":"小型", "weight":20, "hp_mul":0.85, "atk_mul":0.85},
	{"id":"normal", "name":"常体", "weight":40, "hp_mul":1.0, "atk_mul":1.0},
	{"id":"large", "name":"大型", "weight":20, "hp_mul":1.25, "atk_mul":1.2},
	{"id":"colossal", "name":"巨型", "weight":8, "hp_mul":1.6, "atk_mul":1.45}
]

const HABITS := [
	{"id":"ambush", "name":"伏击", "weight":16, "tags":["stealth","burst"]},
	{"id":"pack", "name":"群猎", "weight":16, "tags":["group","pressure"]},
	{"id":"territorial", "name":"领地", "weight":14, "tags":["defense","rage"]},
	{"id":"scavenger", "name":"食腐", "weight":14, "tags":["loot","disease"]},
	{"id":"timid", "name":"怯行", "weight":12, "tags":["escape","low_risk"]},
	{"id":"mystic", "name":"异感", "weight":10, "tags":["omen","sanity"]},
	{"id":"nocturnal", "name":"夜行", "weight":18, "tags":["night","vision"]}
]

const BEHAVIORS := [
	{"id":"charge", "name":"冲锋", "weight":16},
	{"id":"circle", "name":"迂回", "weight":14},
	{"id":"feint", "name":"佯退", "weight":14},
	{"id":"screech", "name":"尖啸", "weight":12},
	{"id":"pounce", "name":"扑袭", "weight":14},
	{"id":"stalk", "name":"尾随", "weight":16},
	{"id":"ward", "name":"守视", "weight":14}
]

const LOOT_TAGS := [
	{"id":"hide", "name":"皮料", "weight":18},
	{"id":"meat", "name":"肉材", "weight":18},
	{"id":"bone", "name":"骨材", "weight":16},
	{"id":"gland", "name":"腺囊", "weight":12},
	{"id":"feather", "name":"羽材", "weight":12},
	{"id":"core", "name":"核晶", "weight":10},
	{"id":"fang", "name":"獠牙", "weight":14}
]

func roll(rng: RandomNumberGenerator, base_creature: Dictionary, region_id: String="") -> Dictionary:
	var base_name: String = String(base_creature.get("name", base_creature.get("id", "未知生物")))
	var base_id: String = String(base_creature.get("id", "unknown"))
	var base_weight: int = int(base_creature.get("weight", 6))

	var size: Dictionary = _pick_weighted(rng, SIZES)
	var habit: Dictionary = _pick_weighted(rng, HABITS)
	var behavior: Dictionary = _pick_weighted(rng, BEHAVIORS)

	var loot_count: int = rng.randi_range(1, 3)
	var loot: Array[String] = []
	var used: Dictionary = {}
	for _i in range(loot_count):
		var lk: Dictionary = _pick_unique_weighted(rng, LOOT_TAGS, used)
		if lk.is_empty():
			break
		loot.append(String(lk.get("name", "")))

	var danger: int = max(1, int(round((base_weight / 3.0) * float(size.get("atk_mul", 1.0)))))
	if "mystic" in (habit.get("tags", []) as Array):
		danger += 1
	if String(size.get("id", "normal")) == "colossal":
		danger += 2

	var hp_score: int = max(5, int(round(20.0 * float(size.get("hp_mul", 1.0)))))
	var dodge: int = 4 + int(rng.randi_range(0, 6))
	if String(habit.get("id", "")) == "timid":
		dodge += 2

	var tag_list: Array[String] = []
	tag_list.append(String(size.get("id", "normal")))
	tag_list.append(String(habit.get("id", "ambush")))
	tag_list.append(String(behavior.get("id", "stalk")))
	if region_id != "":
		tag_list.append("region:" + region_id)

	var id: String = "cv.%s.%s.%s.%04d" % [
		base_id,
		String(size.get("id", "normal")),
		String(habit.get("id", "ambush")),
		rng.randi_range(1000, 9999)
	]

	var size_name: String = String(size.get("name", "常体"))
	var habit_name: String = String(habit.get("name", "伏击"))
	var full_name: String = ""
	if size_name == "常体":
		full_name = "%s%s" % [habit_name, base_name]
	else:
		full_name = "%s%s%s" % [size_name, habit_name, base_name]

	return {
		"id": id,
		"name": full_name,
		"base_id": base_id,
		"size": String(size.get("name", "常体")),
		"habit": String(habit.get("name", "伏击")),
		"behavior": String(behavior.get("name", "尾随")),
		"danger": danger,
		"hp_score": hp_score,
		"dodge": dodge,
		"loot_tags": loot,
		"tags": tag_list
	}

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
