# res://scripts/sys/world_state.gd
extends Node
class_name WorldState

# ---- 基本时间/环境 ----
var day: int = 1
var hour: int = 8
var time_of_day: String = "day"  # "dawn" / "day" / "dusk" / "night"
var weather_tag: String = ""

# ---- 轻量世界状态（供事件判定用）----
var flags: Dictionary = {}
var counters: Dictionary = {}
var meters: Dictionary = {}
var facts: Dictionary = {}
var inventory: Dictionary = {}
var journey_marks: Array[String] = []

# ---- 叙事辅助 ----
var chronicle_lines: Array[String] = []
var last_snippet_line: String = ""

# ---- 当前区域 ----
var current_region_path: String = ""
var current_region_id: String = ""

# ---- 天气播报节流 ----
var _last_weather_id: String = ""

func reset_run() -> void:
	day = 1
	hour = 8
	time_of_day = "day"
	weather_tag = ""
	flags.clear()
	counters.clear()
	meters.clear()
	facts.clear()
	inventory.clear()
	journey_marks.clear()
	chronicle_lines.clear()
	last_snippet_line = ""
	current_region_path = ""
	current_region_id = ""
	_last_weather_id = ""

func set_weather(new_weather: String) -> bool:
	# 返回 true 表示这次需要对外播报一次“天气转为 …”
	if new_weather == "":
		return false
	if new_weather == _last_weather_id:
		return false
	_last_weather_id = new_weather
	weather_tag = new_weather
	return true

# ---- flag/counter/meter ----
func flag_set(k: String, v: bool=true) -> void:
	flags[k] = v

func flag_get(k: String) -> bool:
	return bool(flags.get(k, false))

func counter_add(k: String, inc: int) -> void:
	counters[k] = int(counters.get(k, 0)) + inc

func counter_get(k: String) -> int:
	return int(counters.get(k, 0))

func meter_add(k: String, inc: int, min_val: int=-2147483648, max_val: int=2147483647) -> void:
	var cur := int(meters.get(k, 0)) + inc
	if cur < min_val:
		cur = min_val
	if cur > max_val:
		cur = max_val
	meters[k] = cur

func meter_get(k: String) -> int:
	return int(meters.get(k, 0))

func meter_gte(k: String, v: int) -> bool:
	return meter_get(k) >= v

# ---- facts ----
func fact_add(k: String, inc: int=1) -> void:
	facts[k] = int(facts.get(k, 0)) + inc

func fact_get(k: String) -> int:
	return int(facts.get(k, 0))

func fact_gte(k: String, v: int) -> bool:
	return fact_get(k) >= v

# ---- inventory ----
func inv_add(k: String, inc: int=1) -> void:
	inventory[k] = int(inventory.get(k, 0)) + inc

func inv_consume(k: String, dec: int=1) -> void:
	var cur: int = int(inventory.get(k, 0)) - dec
	inventory[k] = max(0, cur)

func inv_get(k: String) -> int:
	return int(inventory.get(k, 0))

# ---- chronicle ----
func chronicle_push(line: String) -> void:
	if line == "":
		return
	chronicle_lines.append(line)

func chronicle_tail(n: int=20) -> Array[String]:
	if n <= 0:
		return []
	if chronicle_lines.size() <= n:
		return chronicle_lines.duplicate()
	return chronicle_lines.slice(chronicle_lines.size() - n, chronicle_lines.size())

# ---- 时间帮助 ----
func tick_hours(h: int=1) -> void:
	if h <= 0:
		return
	var total: int = hour + h
	day += total / 24
	hour = total % 24
	time_of_day = _name_time_of_day(hour)

func _name_time_of_day(h: int) -> String:
	if h < 5:
		return "night"
	elif h < 8:
		return "dawn"
	elif h < 18:
		return "day"
	elif h < 20:
		return "dusk"
	return "night"
