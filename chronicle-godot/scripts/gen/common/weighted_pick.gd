extends Node
class_name WeightedPick

const RNG_PATH := "_RNG"
const WS_PATH  := "_WorldState"

# —— 新增：拿到世界状态（避免 Could not find type "WorldState"）——
@onready var WS: WorldState = _WorldState

func weighted_pick(pool: Array) -> Dictionary:
	var sum := 0.0
	for it in pool:
		if it is Dictionary:
			sum += float((it as Dictionary).get("weight", 1.0))
	if sum <= 0.0:
		return {}
	var r := randf() * sum
	var acc := 0.0
	for it2 in pool:
		if it2 is Dictionary:
			acc += float((it2 as Dictionary).get("weight", 1.0))
			if r <= acc:
				return it2
	return (pool.back() as Dictionary)

func _root() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null

func _rng() -> RNG:
	var r: Node = _root()
	return r.get_node_or_null(RNG_PATH) as RNG if r != null else null

func _ws() -> WorldState:
	var r: Node = _root()
	return r.get_node_or_null(WS_PATH) as WorldState if r != null else null

# ---------- 条件判定（与 ChainEngine 语义一致的最小集合） ----------
func _cond_ok(when: Dictionary) -> bool:
	var ws: WorldState = _ws()

	# weather_in: ["fog","rain",...]
	if when.has("weather_in"):
		var any_val: Variant = when.get("weather_in", [])
		var any: Array = (any_val as Array) if any_val is Array else []
		var tag: String = "" if ws == null else String(ws.weather_tag)
		if tag == "" or not (tag in any):
			return false

	# time_in: ["day","night","dawn","dusk"]
	if when.has("time_in"):
		var times_val: Variant = when.get("time_in", [])
		var times: Array = (times_val as Array) if times_val is Array else []
		var tod: String = "" if ws == null else String(ws.time_of_day)
		if tod == "" or not (tod in times):
			return false

	# flag_present / flag_absent
	if when.has("flag_present"):
		var fp: String = String(when.get("flag_present",""))
		if ws == null or not bool(ws.flags.get(fp, false)):
			return false

	if when.has("flag_absent"):
		var fa: String = String(when.get("flag_absent",""))
		if ws != null and bool(ws.flags.get(fa, false)):
			return false

	# has_mark
	if when.has("has_mark"):
		var mk: String = String(when.get("has_mark",""))
		if ws == null or not (mk in ws.journey_marks):
			return false

	return true

# ---------- 单条目权重 ----------
func _entry_weight(e: Variant, _ctx: Dictionary) -> float:
	if not (e is Dictionary):
		return 1.0
	var d: Dictionary = e as Dictionary

	# 基础权重
	var w: float = float(d.get("weight", 1.0))
	if w <= 0.0:
		return 0.0

	# 条件加权（cond_weight 是数组）
	if d.has("cond_weight"):
		var cws_any: Variant = d.get("cond_weight", null)
		if cws_any is Array:
			var cws: Array = cws_any as Array
			for cw_any: Variant in cws:
				if cw_any is Dictionary:
					var cw: Dictionary = cw_any as Dictionary
					var when_any: Variant = cw.get("when", {})
					var mul_val: Variant = cw.get("mul", 1.0)
					var mul: float = float(mul_val)
					if (when_any is Dictionary) and _cond_ok(when_any as Dictionary):
						w *= max(0.0, mul)

	# 重复衰减（可选）：依赖 WorldState，但做了安全兜底
	var ws: WorldState = _ws()
	if ws != null and d.has("id"):
		var eid: String = String(d["id"])
		# 用 Node.metadata 存 seen_counts，避免要求 WS 必须先声明该字段
		var seen_map_any: Variant = ws.get_meta("seen_counts", {})
		var seen_map: Dictionary = seen_map_any as Dictionary
		var seen: int = int(seen_map.get(eid, 0))
		var decay: float = float(d.get("decay", 0.85))
		if seen > 0:
			w *= pow(decay, seen)

	return max(w, 0.0)

# ---------- 加权随机 ----------
func pick_weighted(list: Array, ctx: Dictionary = {}) -> Dictionary:
	if list.is_empty():
		return {}
	var rng: RNG = _rng()
	if rng == null:
		push_error("[WeightedPick] RNG autoload not found at /root/%s" % RNG_PATH)
		return {}

	var total: float = 0.0
	var wts: Array[float] = []
	for it in list:
		var wi: float = _entry_weight(it, ctx)
		wts.append(wi)
		total += wi
	if total <= 0.0:
		return {}

	var r: float = rng.f() * total
	var acc: float = 0.0
	for i in range(wts.size()):
		acc += wts[i]
		if r <= acc:
			var sel: Variant = list[i]
			var out: Dictionary = (sel as Dictionary) if sel is Dictionary else {}

			# 抽中后记录 seen_counts（同样用 metadata 做到“可选且安全”）
			if not out.is_empty():
				var ws: WorldState = _ws()
				if ws != null and out.has("id"):
					var eid: String = String(out["id"])
					var sm_any: Variant = ws.get_meta("seen_counts", {})
					var sm: Dictionary = sm_any as Dictionary
					sm[eid] = int(sm.get(eid, 0)) + 1
					ws.set_meta("seen_counts", sm)

			return out
	return {}
