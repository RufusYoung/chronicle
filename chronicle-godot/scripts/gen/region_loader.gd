# res://scripts/gen/region_loader.gd
extends Node
class_name RegionLoader

# 读取 JSON（要求字典根）
func _read_json_map(path: String) -> Dictionary:
	var text := JsonUtil.read_text(path)
	if text == "":
		push_warning("[RegionLoader] Empty file: %s" % path)
		return {}
	var v: Variant = JsonUtil.parse_any(text)
	if v is Dictionary:
		return (v as Dictionary)
	push_warning("[RegionLoader] Region JSON must be a Dictionary root: %s" % path)
	return {}

# 解析单条：支持 {"ref": "...", "override": {...}}
func _resolve_entry(entry: Dictionary) -> Dictionary:
	if entry.has("ref"):
		# _Registry 是你已经设置的 Autoload（全局单例）
		return _Registry.resolve_ref(entry)
	return entry

# 暴露给 world_generation.gd 调用的入口
func load_region_from_path(path: String) -> Dictionary:
	var region := _read_json_map(path)
	if region.is_empty():
		return {}

	# 规范化 pools：逐家族处理数组，解析其中的 ref
	var pools_any: Variant = region.get("pools", {})
	if pools_any is Dictionary:
		var pools: Dictionary = pools_any
		for family in pools.keys():
			var arr_any: Variant = pools[family]
			if arr_any is Array:
				var out: Array = []
				for it in (arr_any as Array):
					if it is Dictionary:
						out.append(_resolve_entry(it))
				pools[family] = out
			else:
				# 不是数组就给出提醒，避免后续崩
				push_warning("[RegionLoader] Pool '%s' is not an Array in %s" % [String(family), path])
		region["pools"] = pools
	else:
		region["pools"] = {}  # 保证字段存在，避免后续空引用

	# 可选：补一个基本字段，防止上游必填读取崩溃
	if not region.has("id"):
		region["id"] = path.get_file().get_basename()

	return region
