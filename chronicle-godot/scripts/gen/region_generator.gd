# res://scripts/gen/common/region_generator.gd
extends Node
class_name RegionGenerator
@onready var WS: WorldState = _WorldState
var picker: WeightedPick = WeightedPick.new()

# --- 取 Root / WorldState（统一方式，避免 outside active scene tree） ---
const WS_PATH := "_WorldState"

func _root() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null

func _ws() -> WorldState:
	var r: Node = _root()
	return r.get_node_or_null(WS_PATH) as WorldState if r != null else null

# --- 内部工具：统一从 region 里拿池 ---
func _pool(region: Dictionary, key: String) -> Array:
	var pools_any: Variant = region.get("pools", null)
	if pools_any is Dictionary:
		var pools: Dictionary = pools_any as Dictionary
		var arr_any: Variant = pools.get(key, null)
		if arr_any is Array:
			return arr_any as Array
	return []

# 顶层数组（若没有则可选回退到 pools.xxx）
func _top_or_pool(region: Dictionary, top_key: String, pool_key: String) -> Array:
	var arr_any: Variant = region.get(top_key, null)
	if arr_any is Array:
		return arr_any as Array
	return _pool(region, pool_key)

# -----------------------------
# 抽取函数（只读 region，不内置任何数据）
# -----------------------------
func choose_weather(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = _pool_multi(region, ["weather", "weathers"])
	var w: Dictionary = picker.pick_weighted(items, ctx)
	if not w.is_empty():
		var tag: String = _derive_weather_tag(w)
		if tag != "":
			var ws: WorldState = _ws()
			if ws != null:
				ws.weather_tag = tag
	return w


func choose_micro_location(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = _pool(region, "micro_locations")
	return picker.pick_weighted(items, ctx)

func choose_sublocation(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = _pool_multi(region, ["sublocations", "sublocs"])
	return picker.pick_weighted(items, ctx)

func choose_flora(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = _pool(region, "flora")
	return picker.pick_weighted(items, ctx)

func choose_fauna(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = _pool(region, "fauna")
	return picker.pick_weighted(items, ctx)

func choose_encounter(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = _top_or_pool(region, "encounters", "encounters")
	return picker.pick_weighted(items, ctx)

func choose_hazard(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = _pool(region, "hazards")
	return picker.pick_weighted(items, ctx)


func choose_event(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = _top_or_pool(region, "events", "events")
	return picker.pick_weighted(items, ctx)

# 统一入口：一次取若干片段，交给 UI 逐段展示
func snapshot(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	# 固定顺序：天气 → 微地点 → 子地点 → 植物 → 生物 → 危险 → 遭遇 → 事件
	var w: Dictionary  = choose_weather(region, ctx)
	var mi: Dictionary = choose_micro_location(region, ctx)
	var sub: Dictionary = choose_sublocation(region, ctx)
	var fl: Dictionary = choose_flora(region, ctx)
	var fa: Dictionary = choose_fauna(region, ctx)
	var hz: Dictionary = choose_hazard(region, ctx)
	var en: Dictionary = choose_encounter(region, ctx)
	var ev: Dictionary = choose_event(region, ctx)

	return {
		"weather":   w,
		"micro_loc": mi,
		"subloc":    sub,
		"flora":     fl,
		"fauna":     fa,
		"hazard":    hz,
		"encounter": en,
		"event":     ev
	}


# 从天气条目推导一个稳定的标签（优先用 tags，其次从 id/name 猜）
func _derive_weather_tag(w: Dictionary) -> String:
	var tags_any: Variant = w.get("tags", null)
	if tags_any is Array and (tags_any as Array).size() > 0:
		return String((tags_any as Array)[0])

	var src: String = ""
	if w.has("id"):
		src = String(w["id"]).to_lower()
	elif w.has("name"):
		src = String(w["name"]).to_lower()

	if src.find("fog") >= 0 or src.find("雾") >= 0:
		return "fog"
	if src.find("rain") >= 0 or src.find("雨") >= 0:
		return "rain"
	if src.find("snow") >= 0 or src.find("雪") >= 0:
		return "snow"
	if src.find("storm") >= 0 or src.find("雷") >= 0 or src.find("暴") >= 0:
		return "storm"
	if src.find("glow") >= 0 or src.find("萤") >= 0 or src.find("光") >= 0:
		return "glow"
	return ""

func _pool_multi(region: Dictionary, keys: Array) -> Array:
	var pools_any: Variant = region.get("pools", null)
	if not (pools_any is Dictionary):
		return []
	var pools: Dictionary = pools_any as Dictionary
	for k_any in keys:
		var k := String(k_any)
		var arr_any: Variant = pools.get(k, null)
		if arr_any is Array:
			return arr_any as Array
	return []
