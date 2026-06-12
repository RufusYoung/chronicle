# res://scripts/gen/event_generator.gd
extends Node
class_name EventGenerator
@onready var WS: WorldState = _WorldState
var picker: WeightedPick = WeightedPick.new()  # WeightedPick 需有 class_name

# --- 取 Root / WorldState（避免“outside active scene tree”） ---
const WS_PATH := "_WorldState"

func _root() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null

func _ws() -> WorldState:
	var r: Node = _root()
	return r.get_node_or_null(WS_PATH) as WorldState if r != null else null

# ================== 事件抽取（保持原有接口） ==================
# 从 region 中挑一个事件：
# 1) 优先 region.events 数组
# 2) 若无，则尝试 region.pools.events
func choose_event(region: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var items: Array = []

	var ev_any: Variant = region.get("events", null)
	if ev_any is Array:
		items = ev_any as Array
	else:
		var pools_any: Variant = region.get("pools", null)
		if pools_any is Dictionary:
			var pools: Dictionary = pools_any as Dictionary
			var pools_ev_any: Variant = pools.get("events", null)
			if pools_ev_any is Array:
				items = pools_ev_any as Array

	return picker.pick_weighted(items, ctx)

# ================== 文本渲染（模板化，占位符替换） ==================
# 兼容老接口：event_text(ev)；也支持传入当轮 snapshot：event_text(ev, snap_ctx)
# snap_ctx 期望是 RegionGenerator.snapshot 返回的字典（含 weather/micro_loc/subloc/flora/fauna/encounter/event）
func event_text(ev: Dictionary, snap_ctx: Dictionary = {}) -> String:
	if ev.is_empty():
		return ""

	# 1) line 直接返回（若给了上下文，也做模板替换）
	var line_any: Variant = ev.get("line", null)
	if line_any is String:
		var line: String = line_any as String
		if line != "":
			return _render_template(line, snap_ctx)

	# 2) 准备 title / text
	var title: String = ""
	var text: String = ""

	var t_any: Variant = ev.get("title", null)
	if t_any is String:
		title = t_any as String

	var text_any: Variant = ev.get("text", null)
	if text_any is String:
		text = text_any as String
	else:
		# 3) 没有 text，就看 text_templates
		var tpl_any: Variant = ev.get("text_templates", null)
		if tpl_any is Array:
			var arr: Array = tpl_any as Array
			var candidates: Array[String] = []
			for it in arr:
				if it is String:
					candidates.append(it as String)
			if candidates.size() > 0:
				var idx: int = randi() % candidates.size()
				text = candidates[idx]

	# 4) 模板替换（支持 {weather.name} / {flora.name} / {time} / {day} / {hour} / {region_id} 等）
	if title != "":
		title = _render_template(title, snap_ctx)
	if text != "":
		text = _render_template(text, snap_ctx)

	# 5) 组装
	if title != "" and text != "":
		return "[b]" + title + "[/b]\n" + text
	if title != "":
		return title
	if text != "":
		return text

	# 6) 兜底：name
	var name_any: Variant = ev.get("name", "")
	if name_any is String:
		return _render_template(name_any as String, snap_ctx)
	return ""

# ================== 占位符工具 ==================

# 把模板里的 {path} 做替换；path 可以是:
# - 常量：time / day / hour / region_id
# - 当前抽到的元素：weather.name / micro_loc.desc / subloc.name / flora.name / fauna.name / encounter.name / hazard.name
func _render_template(tpl: String, snap_ctx: Dictionary) -> String:
	if tpl == "" or snap_ctx.is_empty():
		# 没上下文就直接返回原文（兼容旧数据）
		return tpl

	var re := RegEx.new()
	var ok := re.compile("{([A-Za-z0-9_\\.]+)}")
	if ok != OK:
		return tpl

	var result := re.search_all(tpl)
	if result == null:
		return tpl

	var pieces: Array[String] = []
	var last_end: int = 0

	for m in result:
		var s: int = m.get_start(0)
		var e: int = m.get_end(0)
		var key: String = m.get_string(1)
		# 追加前一段原文
		pieces.append(tpl.substr(last_end, s - last_end))
		# 追加替换值
		pieces.append(_lookup_placeholder(key, snap_ctx))
		last_end = e

	# 末尾收尾
	pieces.append(tpl.substr(last_end))
	return "".join(pieces)

func _lookup_placeholder(key: String, snap_ctx: Dictionary) -> String:
	var ws: WorldState = _ws()

	# 基本常量
	if key == "time":
		return _fmt_time()
	if key == "day":
		return str(ws.day) if ws != null else ""
	if key == "hour":
		return str(ws.hour) if ws != null else ""
	if key == "region_id":
		return String(ws.current_region_id) if ws != null else ""

	# 简写：直接取某对象的 name/desc，如 {flora} 相当于 {flora.name}
	if not key.contains("."):
		var item_any: Variant = snap_ctx.get(key, null)
		if item_any is Dictionary:
			var item: Dictionary = item_any as Dictionary
			if item.has("name"):
				return String(item["name"])
			if item.has("desc"):
				return String(item["desc"])
		return ""

	# 点路径：cat.field
	var parts: PackedStringArray = key.split(".")
	if parts.size() < 2:
		return ""
	var cat: String = parts[0]
	var fld: String = parts[1]

	var obj_any: Variant = snap_ctx.get(cat, null)
	if not (obj_any is Dictionary):
		return ""
	var obj: Dictionary = obj_any as Dictionary
	var val: Variant = obj.get(fld, "")
	return String(val)

func _fmt_time() -> String:
	var ws: WorldState = _ws()
	if ws == null:
		return ""
	match ws.time_of_day:
		"dawn":
			return "清晨"
		"day":
			return "白日"
		"dusk":
			return "黄昏"
		"night":
			return "夜晚"
		_:
			return ws.time_of_day
