# res://scripts/gen/registry.gd
extends Node
class_name Registry

var pools: Dictionary = {}   # family -> { id -> entry }
var _inited: bool = false

func _ready() -> void:
	if not _inited:
		load_common_registry()
		_inited = true

# 既能读“字典根”，也能读“数组根”的安全加载（不触发 JsonUtil 的类型报错）
func _load_map(path: String) -> Dictionary:
	var text: String = JsonUtil.read_text(path)
	if text == "":
		return {}
	var v: Variant = JsonUtil.parse_any(text)

	# 1) 根是字典：直接返回
	if v is Dictionary:
		return (v as Dictionary)

	# 2) 根是数组：转成 {id: item} 的映射
	if v is Array:
		var out: Dictionary = {}
		var arr: Array = v as Array
		for it in arr:
			if it is Dictionary:
				var item: Dictionary = it as Dictionary
				var id: String = String(item.get("id",""))
				if id != "":
					out[id] = item
		return out

	# 3) 其他情况：给个温和提醒
	push_warning("[Registry] Unsupported JSON root at %s" % path)
	return {}

func _load_family(family: String, path: String) -> void:
	var mp: Dictionary = _load_map(path)
	if mp.is_empty():
		push_warning("[Registry] Empty or missing pool: %s (%s)" % [family, path])
	pools[family] = mp

func load_common_registry() -> void:
	_load_family("weather",    "res://data/common/weather.json")
	_load_family("flora",      "res://data/common/flora.json")
	_load_family("creatures",  "res://data/common/creatures.json")
	# hazards / hazard 兼容
	var hz: Dictionary = _load_map("res://data/common/hazards.json")
	if hz.is_empty():
		hz = _load_map("res://data/common/hazard.json")
	pools["hazards"] = hz
	# 这些是你数据里会用到的
	_load_family("resources",  "res://data/common/resources.json")
	_load_family("traits",     "res://data/common/traits.json")
	_load_family("loot",       "res://data/common/loot.json")

func get_pool(family: String) -> Dictionary:
	return pools.get(_alias_family(family), {})

func get_entry(family: String, id: String) -> Dictionary:
	var fam: String = _alias_family(family)
	var mp: Dictionary = pools.get(fam, {})
	return mp.get(id, {})

# 家族名别名（兼容单/复数写法）
func _alias_family(family: String) -> String:
	# 已存在就直接用
	if pools.has(family):
		return family
	# 常见的单复数字段
	if family == "creature" and pools.has("creatures"):
		return "creatures"
	if family == "hazard" and pools.has("hazards"):
		return "hazards"
	if family == "resource" and pools.has("resources"):
		return "resources"
	# 兜底：原样返回
	return family

# 批量把 entries 里的 {ref, override, ...} 解析成“落地副本”（其余字段保留）
func resolve_ref_array(arr: Array) -> Array:
	var out: Array = []
	for it in arr:
		if it is Dictionary:
			var ent: Dictionary = it as Dictionary
			out.append(resolve_ref(ent))
	return out

# 解析 {"ref":"common:family:id", "override":{...}}；保留同级字段（weight/q等）
func resolve_ref(entry: Dictionary) -> Dictionary:
	if not entry.has("ref"):
		return entry.duplicate(true)

	var ref: String = String(entry.get("ref",""))
	var parts: PackedStringArray = ref.split(":")
	if parts.size() < 3:
		push_warning("[Registry] Bad ref: %s" % ref)
		return entry.duplicate(true)

	var scope: String = parts[0]  # "common" 或 "region"
	var family: String = _alias_family(parts[1])
	var rid: String = parts[2]

	var base: Dictionary = {}
	if scope == "common":
		base = get_entry(family, rid)
	else:
		# 若 RegionLoader 预先挂了如 pools["region:flora"]，这里也能查到
		var pool_key: String = "%s:%s" % [scope, family]
		var mp: Dictionary = pools.get(pool_key, {})
		base = mp.get(rid, {})

	if base.is_empty():
		push_warning("[Registry] Unknown ref: %s" % ref)
		return entry.duplicate(true)

	# 先做基底合并（支持 override）
	var extra_any: Variant = entry.get("override", {})
	var extra: Dictionary = (extra_any as Dictionary) if extra_any is Dictionary else {}
	var merged: Dictionary = DeepMerge.new().deep_merge(base, extra)

	# 再把 entry 自己携带的同级字段（如 weight/q/tags...）补回去，ref/override 除外
	for k in entry.keys():
		if k == "ref" or k == "override":
			continue
		merged[k] = entry[k]

	return merged
