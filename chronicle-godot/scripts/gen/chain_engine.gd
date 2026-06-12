extends Node
class_name ChainEngine
@onready var WS: WorldState = _WorldState
const RNG_PATH := "_RNG"
const WS_PATH  := "_WorldState"

# ---------- Root / RNG / WorldState ----------
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

# ---------- 状态 ----------
var picker: WeightedPick = WeightedPick.new()
var last_event_id: String = ""
var last_next: Array = []
var _last_choices_cache: Array = []
var _awaiting_choice: bool = false  # 是否在等玩家点选项

func is_awaiting_choice() -> bool:
	return _awaiting_choice

func set_current_event(eid: String) -> void:
	last_event_id = eid
	_last_choices_cache.clear()
	_awaiting_choice = false

# ---------- 本轮上下文（由 GameGameWorldGeneration.produce_snapshot 写入） ----------
func _turn_ctx() -> Dictionary:
	var ws: WorldState = _ws()
	if ws == null:
		return {}
	var ctx_any: Variant = ws.get_meta("turn_ctx", {})
	return (ctx_any as Dictionary) if (ctx_any is Dictionary) else {}

func _ctx_get(path: String) -> Variant:
	var ctx: Dictionary = _turn_ctx()
	if ctx.is_empty() or path == "":
		return null
	var parts: PackedStringArray = path.split(".")
	var obj_any: Variant = ctx.get(parts[0], null)
	if not (obj_any is Dictionary):
		return null
	var obj: Dictionary = obj_any as Dictionary
	if parts.size() == 1:
		return obj
	return obj.get(parts[1], null)

func _ctx_string(path: String) -> String:
	var v: Variant = _ctx_get(path)
	return "" if v == null else String(v)

# 简单占位符替换：若整个字符串形如 "{flora.id}"，替换成 turn_ctx 对应值；否则原样返回
func _subst_placeholders(s: String) -> String:
	if s == "" or s == null:
		return ""
	if s.begins_with("{") and s.ends_with("}") and s.length() >= 3:
		var keypath: String = s.substr(1, s.length() - 2)
		var val: String = _ctx_string(keypath)
		return val if val != "" else s
	return s

# ---------- 条件判定 ----------
func _conditions_ok(ev: Dictionary) -> bool:
	if not ev.has("conditions"):
		return true
	var conds_any: Variant = ev["conditions"]
	if not (conds_any is Array):
		return true
	var conds: Array = conds_any as Array

	var ws: WorldState = _ws()

	for c_any: Variant in conds:
		if not (c_any is Dictionary):
			continue
		var c: Dictionary = c_any as Dictionary
		var t: String = String(c.get("type",""))

		if t == "flag_absent":
			if ws != null and bool(ws.flags.get(String(c.get("key","")), false)):
				return false

		elif t == "flag_present":
			if ws == null:
				return false
			if not bool(ws.flags.get(String(c.get("key","")), false)):
				return false

		elif t == "weather_in":
			if ws == null:
				return false
			var any_val: Variant = c.get("any", [])
			var any_arr: Array = (any_val as Array) if (any_val is Array) else []
			if ws.weather_tag == "" or not (ws.weather_tag in any_arr):
				return false

		elif t == "has_mark":
			if ws == null:
				return false
			if not (String(c.get("mark","")) in ws.journey_marks):
				return false

		elif t == "inv_gte":
			if ws == null:
				return false
			var need_key: String = String(c.get("key",""))
			var need_val: int = int(c.get("val", 0))
			var have_val: int = int(ws.inventory.get(need_key, 0))
			if have_val < need_val:
				return false

		elif t == "fact_gte":
			if ws == null:
				return false
			var k: String = String(c.get("key",""))
			var need: int = int(c.get("val", 1))
			if not ws.fact_gte(k, need):
				return false

		elif t == "meter_gte":
			if ws == null:
				return false
			var k2: String = String(c.get("key",""))
			var need2: int = int(c.get("val", 1))
			if not ws.meter_gte(k2, need2):
				return false


	return true

# ---------- 效果执行（含从上下文取值的变体与占位符） ----------
# 读取当轮上下文（我们在 GameGameWorldGeneration.produce_snapshot 里用 ws.set_meta("turn_ctx", snap) 写过）
func _ctx() -> Dictionary:
	var ws := _ws()
	if ws == null:
		return {}
	var v: Variant = ws.get_meta("turn_ctx")
	return v as Dictionary if v is Dictionary else {}



func _apply_effects(effects: Array) -> void:
	if effects.is_empty():
		return
	var ws: WorldState = _ws()
	if ws == null:
		return

	for e_any: Variant in effects:
		if not (e_any is Dictionary):
			continue
		var e: Dictionary = e_any as Dictionary
		var op: String = String(e.get("op",""))

		if op == "set_flag":
			var k: String = _subst_placeholders(String(e.get("key","")))
			var v: bool = bool(e.get("val", true))
			if k != "":
				ws.flags[k] = v

		elif op == "add_mark":
			var m: String = _subst_placeholders(String(e.get("mark","")))
			if m != "" and not (m in ws.journey_marks):
				ws.journey_marks.append(m)

		elif op == "inv_add":
			var k_add: String = _subst_placeholders(String(e.get("key","")))
			var v_add: int = int(e.get("val", 0))
			if k_add != "":
				ws.inventory[k_add] = int(ws.inventory.get(k_add, 0)) + v_add

		elif op == "inv_consume":
			var k_c: String = _subst_placeholders(String(e.get("key","")))
			var v_c: int = int(e.get("val", 0))
			if k_c != "":
				ws.inventory[k_c] = max(0, int(ws.inventory.get(k_c, 0)) - v_c)

		elif op == "fact_add":
			var fk := String(e.get("key",""))
			var fv := int(e.get("val", 1))
			if fk != "":
				ws.fact_add(fk, fv)

		elif op == "meter_add":
			var mk := String(e.get("key",""))
			var mv := int(e.get("val", 1))
			if mk != "":
				ws.meter_add(mk, mv)

		elif op == "chronicle_push":
			var msg := String(e.get("text",""))
			if msg != "":
				var rid := ws.current_region_id
				ws.chronicle_push("[%s D%02d H%02d] %s" % [rid, ws.day, ws.hour, msg])

		# ===== 新增：从“当轮上下文 turn_ctx”构造键/值 =====

		elif op == "set_flag_from_ctx":
			# {"op":"set_flag_from_ctx","path":"flora.id","prefix":"seen:","suffix":""}
			var path: String   = String(e.get("path",""))
			var prefix: String = String(e.get("prefix",""))
			var suffix: String = String(e.get("suffix",""))
			var valkey: String = _ctx_string(path)
			if valkey != "":
				ws.flags[prefix + valkey + suffix] = bool(e.get("val", true))

		elif op == "add_mark_from_ctx":
			# {"op":"add_mark_from_ctx","path":"fauna.id","prefix":"met:","suffix":""}
			var p2: String   = String(e.get("path",""))
			var pre2: String = String(e.get("prefix",""))
			var suf2: String = String(e.get("suffix",""))
			var mkey: String = _ctx_string(p2)
			if mkey != "":
				var mark: String = pre2 + mkey + suf2
				if not (mark in ws.journey_marks):
					ws.journey_marks.append(mark)

		elif op == "fact_add_from_ctx":
			# {"op":"fact_add_from_ctx","path":"subloc.id","prefix":"seen:","suffix":"", "val":1}
			var p3 := String(e.get("path",""))
			var pre3 := String(e.get("prefix",""))
			var suf3 := String(e.get("suffix",""))
			var v3 := int(e.get("val", 1))
			var key3 := _ctx_string(p3)
			if key3 != "":
				ws.fact_add(pre3 + key3 + suf3, v3)

		elif op == "meter_add_from_ctx":
			# {"op":"meter_add_from_ctx","path":"weather.id","prefix":"silence.","suffix":".tension","val":1}
			var p4 := String(e.get("path",""))
			var pre4 := String(e.get("prefix",""))
			var suf4 := String(e.get("suffix",""))
			var v4 := int(e.get("val", 1))
			var key4 := _ctx_string(p4)
			if key4 != "":
				ws.meter_add(pre4 + key4 + suf4, v4)


		# 可继续扩：time_advance / sanity_hp / counter_add 等

# ---------- 引擎控制 ----------
func reset() -> void:
	last_event_id = ""
	last_next.clear()
	_last_choices_cache.clear()
	_awaiting_choice = false

# ---------- 事件池 / 索引 ----------
func _global_events(region: Dictionary) -> Array:
	var items: Array = JsonUtil.dict_get_array(region, "events", [])
	if items.is_empty():
		var pools_any: Variant = region.get("pools", null)
		if pools_any is Dictionary:
			var pools: Dictionary = pools_any as Dictionary
			items = JsonUtil.dict_get_array(pools, "events", [])
	return items

func _index_events(region: Dictionary) -> Dictionary:
	var by_id: Dictionary = {}

	var top: Array = JsonUtil.dict_get_array(region, "events", [])
	for e_any: Variant in top:
		if e_any is Dictionary:
			var e: Dictionary = e_any as Dictionary
			var eid: String = String(e.get("id",""))
			if eid != "":
				by_id[eid] = e

	var pools_any: Variant = region.get("pools", null)
	if pools_any is Dictionary:
		var pools: Dictionary = pools_any as Dictionary
		var pool_events: Array = JsonUtil.dict_get_array(pools, "events", [])
		for e2_any: Variant in pool_events:
			if e2_any is Dictionary:
				var e2: Dictionary = e2_any as Dictionary
				var eid2: String = String(e2.get("id",""))
				if eid2 != "":
					by_id[eid2] = e2

	return by_id

# ---------- 抽取 ----------
func _pick_from_next(events_by_id: Dictionary, next_list: Array) -> Dictionary:
	var cands: Array = []
	for n_any: Variant in next_list:
		if not (n_any is Dictionary):
			continue
		var n: Dictionary = n_any as Dictionary
		var eid: String = String(n.get("id",""))
		var w: float = float(n.get("weight", 1.0))
		if eid == "":
			continue
		var tgt_any: Variant = events_by_id.get(eid, {})
		if not (tgt_any is Dictionary):
			continue
		var tgt: Dictionary = tgt_any as Dictionary
		if tgt.is_empty():
			continue
		if not _conditions_ok(tgt):
			continue
		var wrapped: Dictionary = (tgt.duplicate(true) as Dictionary)
		wrapped["weight"] = w
		cands.append(wrapped)
	return picker.pick_weighted(cands, {})

func _pick_global(region: Dictionary) -> Dictionary:
	var pool: Array = _global_events(region)
	var cands: Array = []
	for ev_any: Variant in pool:
		if ev_any is Dictionary:
			var ev: Dictionary = ev_any as Dictionary
			if _conditions_ok(ev):
				var bump: float = 1.0
				if bool(ev.get("starter", false)):
					bump *= 2.0
				if ev.has("next"):
					bump *= 1.3
				if ev.has("choices"):
					bump *= 1.3
				var dup: Dictionary = (ev.duplicate(true) as Dictionary)
				dup["weight"] = float(ev.get("weight", 1.0)) * bump
				cands.append(dup)
	return picker.pick_weighted(cands, {})

func next_event(region: Dictionary) -> Dictionary:
	# 等待玩家选择时不推进
	if _awaiting_choice:
		return {}

	var events_by_id: Dictionary = _index_events(region)
	_last_choices_cache.clear()

	# 1) 先沿 last_event 的 next
	if last_event_id != "":
		var prev_any: Variant = events_by_id.get(last_event_id, {})
		if prev_any is Dictionary:
			var prev: Dictionary = prev_any as Dictionary
			var next_list_any: Variant = prev.get("next", null)
			if next_list_any is Array:
				var cand: Dictionary = _pick_from_next(events_by_id, next_list_any as Array)
				if not cand.is_empty():
					last_event_id = String(cand.get("id",""))
					_apply_effects(JsonUtil.dict_get_array(cand, "effects", []))
					_last_choices_cache = _filter_choices(JsonUtil.dict_get_array(cand, "choices", []))
					_awaiting_choice = _last_choices_cache.size() > 0
					return cand

	# 2) 回退到全局池
	var g: Dictionary = _pick_global(region)
	if not g.is_empty():
		last_event_id = String(g.get("id",""))
		_apply_effects(JsonUtil.dict_get_array(g, "effects", []))
		_last_choices_cache = _filter_choices(JsonUtil.dict_get_array(g, "choices", []))
		_awaiting_choice = _last_choices_cache.size() > 0
		return g

	return {}

# ---------- 选项 ----------
func _filter_choices(raw: Array) -> Array:
	var out: Array = []
	for c_any: Variant in raw:
		if not (c_any is Dictionary):
			continue
		var c: Dictionary = c_any as Dictionary
		var ok: bool = true
		if c.has("conditions"):
			# 复用事件条件格式：把 choice.conditions 包到一个假的 ev 里交给 _conditions_ok
			var tmp: Dictionary = {"conditions": c["conditions"]}
			ok = _conditions_ok(tmp)
		if ok:
			out.append(c)
	return out

func current_choices(region: Dictionary) -> Array:
	if _last_choices_cache.is_empty():
		if last_event_id == "":
			return []
		var events_by_id: Dictionary = _index_events(region)
		var ev_any: Variant = events_by_id.get(last_event_id, {})
		if ev_any is Dictionary:
			var ev: Dictionary = ev_any as Dictionary
			_last_choices_cache = _filter_choices(JsonUtil.dict_get_array(ev, "choices", []))
	_awaiting_choice = _last_choices_cache.size() > 0
	return _last_choices_cache

func apply_choice(choice_id: String, region: Dictionary) -> Dictionary:
	if last_event_id == "":
		push_warning("[ChainEngine] apply_choice called but no last_event_id.")
		return {}

	var events_by_id: Dictionary = _index_events(region)
	var ev_any: Variant = events_by_id.get(last_event_id, {})
	if not (ev_any is Dictionary):
		return {}

	var ev: Dictionary = ev_any as Dictionary
	var choices: Array = JsonUtil.dict_get_array(ev, "choices", [])
	var target: Dictionary = {}
	for c_any: Variant in choices:
		if c_any is Dictionary and String((c_any as Dictionary).get("id","")) == choice_id:
			target = c_any
			break
	if target.is_empty():
		push_warning("[ChainEngine] choice not found: %s" % choice_id)
		return {}

	# 选项效果先执行（支持占位符与 from_ctx）
	_apply_effects(JsonUtil.dict_get_array(target, "effects", []))

	# goto：留在本地区
# goto：留在本区
	var goto_id: String = String(target.get("goto_event",""))
	if goto_id != "":
		var tgt_any: Variant = events_by_id.get(goto_id, {})
		if tgt_any is Dictionary:
			var tgt: Dictionary = tgt_any as Dictionary
			last_event_id = goto_id

			# ★ 新增：立即执行目标事件的 effects（之前没执行）
			_apply_effects(JsonUtil.dict_get_array(tgt, "effects", []))

			_last_choices_cache = _filter_choices(JsonUtil.dict_get_array(tgt, "choices", []))
			_awaiting_choice = _last_choices_cache.size() > 0
			return {"type":"event", "event": tgt}


	# travel：交给上层切区；本地链重置
	var travel_region: String = String(target.get("travel_to_region",""))
	if travel_region != "":
		var spawn: String = String(target.get("spawn_event",""))
		reset()
		return {"type":"travel", "region_id": travel_region, "spawn_event": spawn}

	# 没有跳转：可能只是施加效果
	_last_choices_cache = _filter_choices(choices)
	_awaiting_choice = _last_choices_cache.size() > 0
	return {"type":"event", "event": ev}
