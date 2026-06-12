
extends Node

var rng := RandomNumberGenerator.new()

var current_region_id: String = "mirrorlake_forest"
var current_region: Dictionary = {"id":"mirrorlake_forest", "name":"\u955c\u6e56\u68ee\u6797\u5e26"}

var time_hours: int = 8
var day: int = 1

var hp: int = 88
var hp_max: int = 100
var sanity: int = 76
var sanity_max: int = 100
var energy: int = 30
var energy_max: int = 36
var ration: int = 3

var strength: int = 11
var dexterity: int = 10
var intellect: int = 10
var charisma: int = 9
var constitution: int = 11
var wisdom: int = 10

var world_state: Dictionary = {
	"danger": 32,
	"order": 48,
	"scarcity": 35
}
var active_thread: Dictionary = {
	"id": "thread.echo",
	"name": "\u56de\u58f0\u94fe",
	"stage": 2,
	"desc": "\u955c\u6e56\u8fb9\u754c\u7684\u5f02\u5e38\u56de\u54cd\u6b63\u5728\u6269\u6563\u3002"
}

var goal_reminders: Array[Dictionary] = [
	{"text":"\u9152\u4fdd\u63d0\u5230\u897f\u4fa7\u9057\u8ff9\u6709\u5f02\u5e38\u52a8\u9759\u3002", "hint_target":"\u897f\u4fa7\u8db3\u8ff9"},
	{"text":"\u540c\u4f34\u75c5\u60c5\u52a0\u91cd\uff0c\u4f60\u8fd8\u7f3a\u4e00\u4efd\u8349\u836f\u3002", "hint_target":"\u6cb3\u8fb9\u8349\u836f"}
]

var leads: Array[Dictionary] = []
var lead_nonce: int = 0

var recent_visible_outcomes: Array[String] = []
var rumor_feed: Array[String] = []
var unknown_outcomes: Array[String] = []

var pending_event: Dictionary = {}
var backlog: Array[Dictionary] = []
var backlog_nonce: int = 0

var active_micro: Dictionary = {}
var micro_nonce: int = 0
var micro_fingerprint_h: Dictionary = {}
var last_pick_text: String = ""
var queued_event_from_lead: Dictionary = {}
var lead_feedback_queue: Array[String] = []
var last_recommended_titles: Array[String] = []
var recommendation_shift_needed: bool = false

var guidance_due: bool = true
var last_guidance_h: int = -9999

func _ready() -> void:
	rng.randomize()

func bootstrap(_path: String, reset_time: bool=true) -> void:
	rng.randomize()
	if reset_time:
		time_hours = 8
		day = 1
	_reset_runtime()

func _reset_runtime() -> void:
	leads.clear()
	lead_nonce = 0
	recent_visible_outcomes.clear()
	rumor_feed.clear()
	unknown_outcomes.clear()
	lead_feedback_queue.clear()
	queued_event_from_lead.clear()
	last_recommended_titles.clear()
	recommendation_shift_needed = false
	pending_event.clear()
	backlog.clear()
	backlog_nonce = 0
	active_micro.clear()
	micro_nonce = 0
	micro_fingerprint_h.clear()
	guidance_due = true
	last_guidance_h = -9999
	_ensure_leads_from_percepts(3)

func has_pending_choice() -> bool:
	return (not pending_event.is_empty()) or (not active_micro.is_empty())

func get_backlog_count() -> int:
	return backlog.size()

func get_player_panel() -> Dictionary:
	return {
		"hp": hp, "hp_max": hp_max,
		"sanity": sanity, "sanity_max": sanity_max,
		"energy": energy, "energy_max": energy_max,
		"ration": ration,
		"str": strength, "dex": dexterity, "int": intellect,
		"cha": charisma, "con": constitution, "wis": wisdom
	}

func get_goal_panel_v02() -> Dictionary:
	_prune_leads()
	var lead_lines: Array[String] = []
	for l_any in leads:
		if lead_lines.size() >= 2:
			break
		if l_any is Dictionary:
			lead_lines.append(_lead_title(l_any as Dictionary))
	var reminder_lines: Array[String] = []
	for r_any in goal_reminders:
		if reminder_lines.size() >= 2:
			break
		if r_any is Dictionary:
			reminder_lines.append(String((r_any as Dictionary).get("text", "")))
	return {
		"location": String(current_region.get("name", "\u672a\u77e5\u5730\u70b9")),
		"leads": lead_lines,
		"reminders": reminder_lines,
		"thread": "%s %d/3\uff1a%s" % [
			String(active_thread.get("name", "\u65e0\u7ebf\u7a0b")),
			int(active_thread.get("stage", 1)),
			String(active_thread.get("desc", ""))
		],
		"recent_outcome": recent_visible_outcomes[recent_visible_outcomes.size() - 1] if not recent_visible_outcomes.is_empty() else ""
	}

func get_action_board() -> Dictionary:
	_process_expiry()
	_try_trigger_event_from_mature_lead()
	var quick: Array[Dictionary] = [
		_action_entry("sys.v03.backlog.open", "\u5f85\u529e(%d)" % backlog.size(), "", "", "", false, false),
		_action_entry("sys.v03.rumor.open", "\u4f20\u95fb", "", "", "", false, false)
	]
	if not active_micro.is_empty():
		var split_m: Dictionary = _split_actions(_micro_stage_actions(), false)
		return {
			"mode": "event",
			"event_header": _micro_header_text(),
			"guidance": {},
			"actions": split_m.get("primary", []),
			"more_actions": split_m.get("more", []),
			"quick": quick
		}
	if not pending_event.is_empty():
		var split_e: Dictionary = _split_actions(_event_stage_actions(), false)
		return {
			"mode": "event",
			"event_header": _event_header_text(),
			"guidance": {},
			"actions": split_e.get("primary", []),
			"more_actions": split_e.get("more", []),
			"quick": quick
		}
	var split_f: Dictionary = _split_actions(_recommended_actions(), false)
	return {
		"mode": "free",
		"event_header": "",
		"guidance": _guidance_payload(),
		"actions": split_f.get("primary", []),
		"more_actions": split_f.get("more", []),
		"quick": quick
	}

func produce_snapshot() -> Dictionary:
	_process_expiry()
	_try_trigger_event_from_mature_lead()
	var snap: Dictionary = {
		"region_id": current_region_id,
		"day": day,
		"hour": time_hours,
		"time_of_day": _time_of_day_label()
	}
	if has_pending_choice():
		snap["event_text"] = "\u5f53\u524d\u6709\u5f85\u51b3\u9636\u6bb5\uff0c\u8bf7\u5148\u5728\u4e0b\u65b9\u5b8c\u6210\u9009\u9879\u3002"
		return snap
	_advance_time(1)
	_process_expiry()
	if guidance_due or time_hours - last_guidance_h >= 6:
		guidance_due = false
		last_guidance_h = time_hours
		snap["event_text"] = _guidance_block_text()
		return snap
	if rng.randf() < 0.22:
		_spawn_segment_free_event()
		snap["event_text"] = "\u4f60\u9047\u5230\u4e86\u4e00\u4e2a\u9700\u8981\u7acb\u5373\u8868\u6001\u7684\u4e8b\u4ef6\uff0c\u884c\u52a8\u677f\u5df2\u5207\u6362\u4e3a\u4e8b\u4ef6\u9636\u6bb5\u3002"
		return snap
	if rng.randf() < 0.10:
		_spawn_segment_locked_event()
		snap["event_text"] = "\u7a81\u53d1\u8fde\u6bb5\u4e8b\u4ef6\u538b\u4e0a\u6765\u4e86\uff0c\u8bf7\u5148\u5b8c\u6210\u8fde\u7eed\u5904\u7f6e\u3002"
		return snap
	var rumor_line: String = _pop_rumor_line()
	if rumor_line != "":
		snap["event_text"] = rumor_line
		return snap
	if not lead_feedback_queue.is_empty():
		snap["event_text"] = lead_feedback_queue.pop_front()
		return snap
	snap["event_text"] = "\u4f60\u4ecd\u5728\u81ea\u7531\u884c\u52a8\u4e2d\uff0c\u53ef\u4ee5\u76f4\u63a5\u9009\u62e9\u4e0b\u4e00\u6b65\u3002"
	return snap

func apply_choice(choice_id: String) -> Dictionary:
	return apply_system_choice(choice_id)

func apply_system_choice(choice_id: String) -> Dictionary:
	if choice_id == "":
		return _action_result("\u8fd9\u4e2a\u9009\u9879\u65e0\u6548\u3002")
	if choice_id.begins_with("sys.v03.backlog."):
		return _apply_backlog_choice(choice_id)
	if choice_id.begins_with("sys.v03.rumor."):
		return _apply_rumor_choice(choice_id)
	if choice_id.begins_with("sys.v03.micro."):
		var parts: PackedStringArray = choice_id.split(".")
		if parts.size() >= 4:
			return _apply_micro_style(String(parts[3]))
		return _action_result("\u884c\u52a8\u6b65\u9aa4\u6307\u4ee4\u65e0\u6548\u3002")
	if choice_id.begins_with("sys.v03.lead."):
		return _apply_lead_action(choice_id)
	if choice_id == "sys.v03.free.observe":
		var lf: Dictionary = _get_top_actionable_lead_by_type("footprint")
		if lf.is_empty():
			return _action_result("\u5f53\u524d\u6ca1\u6709\u53ef\u8ddf\u8fdb\u7684\u8db3\u8ff9\u7ebf\u7d22\u3002")
		return _start_micro("track", _lead_title(lf), String(lf.get("lead_id", lf.get("id", ""))), "\u517c\u5bb9\u5165\u53e3\u81ea\u52a8\u9009\u7ebf\u7d22")
	if choice_id == "sys.v03.free.push":
		var ls: Dictionary = _get_top_actionable_lead_by_type("smoke")
		if ls.is_empty():
			return _action_result("\u5f53\u524d\u6ca1\u6709\u53ef\u8ddf\u8fdb\u7684\u70df\u6e90\u7ebf\u7d22\u3002")
		return _start_micro("investigate", _lead_title(ls), String(ls.get("lead_id", ls.get("id", ""))), "\u517c\u5bb9\u5165\u53e3\u81ea\u52a8\u9009\u7ebf\u7d22")
	if choice_id == "sys.v03.free.forage":
		var lr: Dictionary = _get_top_actionable_lead_by_type("river")
		if lr.is_empty():
			return _action_result("\u5f53\u524d\u6ca1\u6709\u53ef\u8ddf\u8fdb\u7684\u6cb3\u8fb9\u7ebf\u7d22\u3002")
		return _start_micro("forage", _lead_title(lr), String(lr.get("lead_id", lr.get("id", ""))), "\u517c\u5bb9\u5165\u53e3\u81ea\u52a8\u9009\u7ebf\u7d22")
	if choice_id == "sys.v03.free.rest":
		return _action_result("\u5f53\u524d\u7248\u672c\u7684\u4f11\u6574\u5df2\u5e76\u5165\u5177\u4f53\u7ebf\u7d22\u884c\u52a8\uff0c\u8bf7\u4ece\u300c\u884c\u52a8\u9762\u677f\u300d\u9009\u62e9\u76ee\u6807\u5316\u884c\u52a8\u3002")
	if choice_id == "sys.v03.free.ask":
		var lm: Dictionary = _get_top_actionable_lead_by_type("rumor")
		if lm.is_empty():
			return _action_result("\u5f53\u524d\u6ca1\u6709\u53ef\u8ddf\u8fdb\u7684\u6d88\u606f\u7ebf\u7d22\u3002")
		return _start_micro("ask", _lead_title(lm), String(lm.get("lead_id", lm.get("id", ""))), "\u517c\u5bb9\u5165\u53e3\u81ea\u52a8\u9009\u7ebf\u7d22")
	if choice_id.begins_with("sys.v03.event."):
		return _apply_event_choice(choice_id)
	if choice_id == "sys.v02.tool.map" or choice_id == "sys.v03.tool.map":
		return _action_result("\u5730\u56fe\u5df2\u6253\u5f00\uff1a\u53ef\u67e5\u770b\u8def\u7ebf\u3001\u5c01\u9501\u533a\u548c\u5f02\u5e38\u70ed\u70b9\u3002")
	if choice_id == "sys.v02.tool.log" or choice_id == "sys.v03.tool.log":
		var logs: Array[String] = ["\u65e5\u5fd7\u6458\u8981\uff1a"]
		if not recent_visible_outcomes.is_empty():
			for l in recent_visible_outcomes.slice(max(0, recent_visible_outcomes.size() - 3), recent_visible_outcomes.size()):
				logs.append("- " + String(l))
		if logs.size() == 1:
			logs.append("- \u6682\u65f6\u6ca1\u6709\u65b0\u8bb0\u5f55\u3002")
		return _action_result("\n".join(logs))
	if choice_id == "sys.v02.tool.growth" or choice_id == "sys.v03.tool.growth":
		return _action_result("\u6210\u957f\u9762\u677f\u5df2\u6253\u5f00\uff1a\u7279\u8d28\u53d8\u5316\u4f1a\u5f71\u54cd\u4f60\u7684\u540e\u7eed\u9009\u9879\u3002")
	if choice_id == "sys.v02.tool.inventory" or choice_id == "sys.v03.tool.inventory":
		return _action_result("\u80cc\u5305\u5df2\u6253\u5f00\uff1a\u53ef\u4ee5\u67e5\u770b\u53e3\u7cae\u3001\u5de5\u5177\u548c\u836f\u6750\u3002")
	if choice_id == "sys.v02.tool.system" or choice_id == "sys.v03.tool.system":
		return _action_result("\u7cfb\u7edf\u9762\u677f\uff1a\u53ef\u4ece\u300c\u5f85\u529e\u300d\u4e0e\u300c\u4f20\u95fb\u300d\u5165\u53e3\u8ddf\u8fdb\u4e2d\u671f\u540e\u679c\u3002")
	return _action_result("\u6682\u65f6\u65e0\u6cd5\u6267\u884c\u8fd9\u4e2a\u9009\u9879\u3002")

func _action_entry(id: String, title: String, why: String, cost: String, direction: String, objectified: bool=true, disabled: bool=false) -> Dictionary:
	return {"id":id, "title":title, "why":why, "cost":cost, "direction":direction, "objectified":objectified, "disabled":disabled}

func _split_actions(actions: Array[Dictionary], fill_context: bool) -> Dictionary:
	var uniq: Array[Dictionary] = _unique_actions(actions)
	var primary: Array[Dictionary] = []
	var more: Array[Dictionary] = []
	for i in range(uniq.size()):
		if i < 6:
			primary.append(uniq[i])
		elif i < 10:
			more.append(uniq[i])
	if fill_context and primary.size() < 3:
		for c in _context_actions():
			if primary.size() >= 3:
				break
			var exists: bool = false
			for p in primary:
				if String(p.get("id", "")) == String(c.get("id", "")):
					exists = true
					break
			if not exists:
				primary.append(c)
	return {"primary": primary, "more": more}

func _unique_actions(items: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for it_any in items:
		if not (it_any is Dictionary):
			continue
		var it: Dictionary = it_any as Dictionary
		if bool(it.get("disabled", false)):
			continue
		var title: String = String(it.get("title", "")).strip_edges()
		if title == "":
			continue
		var key: String = title.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		out.append(it)
	return out
func _build_percepts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var footprint: Dictionary = _get_top_actionable_lead_by_type("footprint")
	var smoke: Dictionary = _get_top_actionable_lead_by_type("smoke")
	var river: Dictionary = _get_top_actionable_lead_by_type("river")
	var rumor: Dictionary = _get_top_actionable_lead_by_type("rumor")

	if footprint.is_empty():
		out.append({"type":"footprint", "text":"\u897f\u4fa7\u571f\u8def\u6709\u65ad\u7eed\u8db3\u8ff9\u3002", "target":"\u897f\u4fa7", "direction":"\u897f\u4fa7"})
	else:
		var ff: int = int(footprint.get("freshness", 70))
		out.append({
			"type":"footprint",
			"text":"\u897f\u4fa7\u8db3\u8ff9%s\u3002" % ("\u8fd8\u7b97\u6e05\u6670" if ff >= 45 else "\u5df2\u88ab\u98ce\u96e8\u51b2\u5f97\u53d1\u865a"),
			"target": String(footprint.get("target_dir_or_place", "\u897f\u4fa7")),
			"direction": String(footprint.get("target_dir_or_place", "\u897f\u4fa7"))
		})

	if smoke.is_empty():
		out.append({"type":"smoke", "text":"\u4e1c\u5317\u5929\u9645\u6709\u65ad\u7eed\u708a\u70df\u3002", "target":"\u4e1c\u5317", "direction":"\u4e1c\u5317"})
	else:
		var sf: int = int(smoke.get("freshness", 70))
		out.append({
			"type":"smoke",
			"text":"\u4e1c\u5317\u70df\u67f1%s\u3002" % ("\u7a33\u5b9a\u53ef\u8fa8" if sf >= 45 else "\u6b63\u5728\u53d8\u6de1\uff0c\u53ef\u80fd\u5f88\u5feb\u6563\u53bb"),
			"target": String(smoke.get("target_dir_or_place", "\u4e1c\u5317")),
			"direction": String(smoke.get("target_dir_or_place", "\u4e1c\u5317"))
		})

	if river.is_empty():
		out.append({"type":"river", "text":"\u5357\u4fa7\u53ef\u542c\u89c1\u6c34\u58f0\u3002", "target":"\u5357\u4fa7\u6cb3\u8fb9", "direction":"\u5357\u4fa7"})
	else:
		var rrisk: String = String(river.get("risk_hint", "\u4e2d\u98ce\u9669"))
		out.append({
			"type":"river",
			"text":"\u6cb3\u8fb9\u533a\u57df\u76ee\u524d\u4e3a%s\u3002" % rrisk,
			"target": String(river.get("target_dir_or_place", "\u6cb3\u8fb9")),
			"direction": String(river.get("target_dir_or_place", "\u6cb3\u8fb9"))
		})

	if not rumor.is_empty():
		out.append({
			"type":"rumor",
			"text":"\u9547\u91cc\u6d88\u606f\u8fd8\u5728\u6d41\u52a8\uff0c\u4f46\u53e3\u98ce\u5f00\u59cb\u51fa\u73b0\u5206\u6b67\u3002",
			"target": String(rumor.get("target_dir_or_place", "\u9547\u91cc")),
			"direction": String(rumor.get("target_dir_or_place", "\u9547\u91cc"))
		})

	if int(world_state.get("danger", 0)) >= 45:
		out.append({"type":"patrol", "text":"\u5317\u4fa7\u5de1\u903b\u8def\u7ebf\u6bd4\u5e73\u65f6\u66f4\u5bc6\u96c6\u3002", "target":"\u5317\u4fa7", "direction":"\u5317\u4fa7"})
	return out.slice(0, 4)

func _guidance_payload() -> Dictionary:
	var percepts_raw: Array[Dictionary] = _build_percepts()
	_ensure_percept_lead_links(percepts_raw)
	var percepts: Array[String] = []
	for p in percepts_raw.slice(0, 3):
		if p is Dictionary:
			percepts.append(String((p as Dictionary).get("text", "")))
	var reminders: Array[String] = []
	for r_any in goal_reminders.slice(0, 2):
		if r_any is Dictionary:
			reminders.append(String((r_any as Dictionary).get("text", "")))
	var summary: String = "\u7ebf\u7d22\u6b63\u5728\u53d8\u5316\uff0c\u5148\u51b3\u5b9a\u8981\u8ddf\u8fdb\u54ea\u6761\u8def\u3002"
	return {"percepts": percepts, "reminders": reminders, "summary": summary}

func _guidance_block_text() -> String:
	var g: Dictionary = _guidance_payload()
	var lines: Array[String] = []
	lines.append("[b]\u4f60\u6ce8\u610f\u5230\uff1a[/b]")
	for p in (g.get("percepts", []) as Array):
		lines.append("- " + String(p))
	lines.append("[b]\u4f60\u60f3\u8d77\uff1a[/b]")
	for r in (g.get("reminders", []) as Array):
		lines.append("- " + String(r))
	lines.append("[b]\u603b\u7ed3\uff1a[/b] " + String(g.get("summary", "\u5148\u9009\u4e00\u6761\u6700\u503c\u5f97\u8ddf\u8fdb\u7684\u7ebf\u7d22\u3002")))
	return "\n".join(lines)

func _lead_title(lead: Dictionary) -> String:
	return _lead_stage_title(lead)

func _risk_to_cost(risk_hint: String) -> String:
	if risk_hint == "\u4f4e\u98ce\u9669":
		return "1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669"
	if risk_hint == "\u9ad8\u98ce\u9669":
		return "1\u5c0f\u65f6\uff5c\u9ad8\u98ce\u9669"
	return "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669"

func _lead_stage_title(lead: Dictionary) -> String:
	var lt: String = String(lead.get("lead_type", lead.get("type", "footprint")))
	var st: int = int(lead.get("stage", 0))
	var target: String = String(lead.get("target_dir_or_place", lead.get("direction", "\u9644\u8fd1")))
	var variant: int = int(lead.get("title_variant", 0))
	var titles: Array[String] = []
	match lt:
		"footprint":
			if st <= 0:
				titles = ["\u6cbf\u8db3\u8ff9\u5f80%s\u8ffd\u67e5" % target, "\u987a\u7740%s\u7684\u8db3\u8ff9\u7eed\u8ddf" % target]
			elif st == 1:
				titles = ["\u68c0\u67e5\u8db3\u8ff9\u5c94\u8def\u5e76\u5224\u65ad\u53bb\u5411", "\u6cbf\u5c94\u8def\u91cd\u7ec4\u8db3\u8ff9\u7ebf\u7d22"]
			else:
				titles = ["\u6f5c\u4f0f\u89c2\u5bdf\u5c3d\u5934\u7591\u4f3c\u8425\u5730", "\u8fd1\u8eab\u8bd5\u63a2\u8db3\u8ff9\u6e90\u5934\u52a8\u9759"]
		"smoke":
			if st <= 0:
				titles = ["\u524d\u5f80%s\u70df\u67f1\u5904\u5bfb\u627e\u4eba\u70df" % target, "\u5bf9\u51c6%s\u708a\u70df\u8def\u7ebf\u63a8\u8fdb" % target]
			elif st == 1:
				titles = ["\u7ed5\u5230\u4e0a\u98ce\u4fa7\u5224\u8bfb\u70df\u6e90", "\u8c03\u6574\u89c6\u89d2\u8ffd\u70df\u5230\u4e0b\u4e00\u4e2a\u70b9"]
			else:
				titles = ["\u8fd1\u8eab\u70df\u6e90\u533a\u57df\u8fdb\u884c\u8bd5\u63a2", "\u5077\u542c\u70df\u6e90\u9644\u8fd1\u4ea4\u8c08\u58f0"]
		"river":
			if st <= 0:
				titles = ["\u5faa\u6c34\u58f0\u53bb%s\u627e\u8349\u836f\u4e0e\u8865\u6c34" % target, "\u53bb%s\u5148\u786e\u4fdd\u53ef\u7528\u6c34\u6e90" % target]
			elif st == 1:
				titles = ["\u6cbf\u6cb3\u5cb8\u7b5b\u9009\u8349\u836f\u5e76\u6807\u8bb0\u53d6\u6c34\u70b9", "\u5728\u6cb3\u8fb9\u6392\u67e5\u836f\u6750\u4e0e\u6ce5\u5370"]
			else:
				titles = ["\u987a\u6d41\u800c\u4e0b\u8ffd\u67e5\u8349\u836f\u6e90\u5934", "\u6cbf\u6cb3\u8fdb\u5165\u4e0b\u4e00\u4e2a\u91c7\u96c6\u70ed\u70b9"]
		"rumor":
			if st <= 0:
				titles = ["\u56de\u9547\u6253\u542c\u201c%s\u201d\u7684\u51c6\u786e\u6d88\u606f" % target, "\u53bb\u9547\u91cc\u91cd\u65b0\u6821\u5bf9\u201c%s\u201d\u7ebf\u7d22" % target]
			elif st == 1:
				titles = ["\u9501\u5b9a\u80af\u5f00\u53e3\u7684\u7ebf\u4eba", "\u5bfb\u627e\u63d0\u5230%s\u7684\u6d88\u606f\u4e2d\u95f4\u4eba" % target]
			else:
				titles = ["\u8d74\u7ea6\u6838\u9a8c\u60c5\u62a5\u771f\u5047", "\u5728\u9547\u53e3\u4e0e\u7ebf\u4eba\u5bf9\u8d28\u6d88\u606f"]
		_:
			titles = ["\u8c03\u67e5%s" % target]
	return titles[variant % titles.size()]

func _lead_direction_text(lead: Dictionary) -> String:
	var lt: String = String(lead.get("lead_type", "footprint"))
	var st: int = int(lead.get("stage", 0))
	match lt:
		"footprint":
			return "\u63a8\u8fdb\u8db3\u8ff9\u7ebf\u7d22\uff5c%s" % ("\u53ef\u80fd\u5f15\u6765\u76d8\u67e5" if st >= 1 else "\u53ef\u80fd\u51fa\u73b0\u5c94\u8def")
		"smoke":
			return "\u63a8\u8fdb\u4eba\u70df\u7ebf\u7d22\uff5c%s" % ("\u53ef\u80fd\u89e6\u53d1\u5f53\u573a\u4ea4\u6d89" if st >= 1 else "\u53ef\u80fd\u83b7\u5f97\u65b0\u4eba\u8109")
		"river":
			return "\u63a8\u8fdb\u8865\u7ed9\u7ebf\uff5c%s" % ("\u53ef\u80fd\u9047\u5230\u4e89\u62a2" if st >= 1 else "\u53ef\u80fd\u89e3\u9501\u836f\u6750\u7ebf")
		"rumor":
			return "\u63a8\u8fdb\u6d88\u606f\u7ebf\uff5c%s" % ("\u53ef\u80fd\u8f6c\u5165\u4e8b\u4ef6\u5bf9\u8d28" if st >= 1 else "\u53ef\u80fd\u83b7\u5f97\u65b0\u5f15\u8350")
		_:
			return "\u63a8\u8fdb\u7ebf\u7d22\uff5c\u7ed3\u679c\u672a\u77e5"

func _lead_hint_text(lead: Dictionary) -> String:
	var lt: String = String(lead.get("lead_type", "footprint"))
	var target: String = String(lead.get("target_dir_or_place", "\u9644\u8fd1"))
	match lt:
		"footprint":
			return "\u6765\u81ea\u201c\u8db3\u8ff9\u5411%s\u201d" % target
		"smoke":
			return "\u6765\u81ea\u201c%s\u65b9\u5411\u70df\u67f1\u201d" % target
		"river":
			return "\u6765\u81ea\u201c%s\u6c34\u58f0\u4e0e\u6f6e\u6e7f\u75d5\u8ff9\u201d" % target
		"rumor":
			return "\u6765\u81ea\u201c\u9547\u91cc\u5173\u4e8e%s\u7684\u98ce\u58f0\u201d" % target
		_:
			return "\u6765\u81ea\u73af\u5883\u7ebf\u7d22"

func _add_lead(lead_type: String, target: String, direction: String, source: String, stage: int=0, freshness: int=80, risk_hint: String="\u4e2d\u98ce\u9669") -> String:
	lead_nonce += 1
	var lead_id: String = "lead_%d" % lead_nonce
	leads.append({
		"lead_id": lead_id,
		"id": lead_id,
		"lead_type": lead_type,
		"type": lead_type,
		"target_dir_or_place": direction,
		"direction": direction,
		"target": target,
		"source": source,
		"stage": clamp(stage, 0, 3),
		"freshness": clamp(freshness, 0, 100),
		"risk_hint": risk_hint,
		"title_variant": rng.randi_range(0, 1),
		"last_update_h": time_hours
	})
	_trim_leads(8)
	return lead_id

func _find_lead(lead_id: String) -> int:
	for i in range(leads.size()):
		var l_any: Variant = leads[i]
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		if String(l.get("lead_id", l.get("id", ""))) == lead_id:
			return i
	return -1

func _prune_leads() -> void:
	var keep: Array[Dictionary] = []
	for l_any in leads:
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		if int(l.get("freshness", 0)) > 0:
			keep.append(l)
	leads = keep

func _trim_leads(max_count: int) -> void:
	while leads.size() > max_count:
		var worst_idx: int = 0
		var worst_score: int = 9999
		for i in range(leads.size()):
			var l: Dictionary = leads[i]
			var sc: int = int(l.get("freshness", 0)) + int(l.get("stage", 0)) * 10
			if sc < worst_score:
				worst_score = sc
				worst_idx = i
		leads.remove_at(worst_idx)

func _get_top_lead_by_type(lead_type: String) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = -9999
	for l_any in leads:
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		if String(l.get("lead_type", l.get("type", ""))) != lead_type:
			continue
		var score: int = int(l.get("freshness", 0)) + int(l.get("stage", 0)) * 8
		if score > best_score:
			best_score = score
			best = l
	return best

func _get_top_actionable_lead_by_type(lead_type: String) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = -9999
	for l_any in leads:
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		if String(l.get("lead_type", l.get("type", ""))) != lead_type:
			continue
		var stage: int = int(l.get("stage", 0))
		var fresh: int = int(l.get("freshness", 0))
		if stage >= 3 or fresh <= 0:
			continue
		var score: int = fresh + stage * 8
		if score > best_score:
			best_score = score
			best = l
	return best

func _ensure_core_leads() -> void:
	if _get_top_actionable_lead_by_type("footprint").is_empty():
		_add_lead("footprint", "\u897f\u4fa7\u8db3\u8ff9", "\u897f\u8fb9", "\u5f15\u5bfc\u611f\u77e5", 0, 82, "\u4e2d\u98ce\u9669")
	if _get_top_actionable_lead_by_type("smoke").is_empty():
		_add_lead("smoke", "\u4e1c\u5317\u70df\u67f1", "\u4e1c\u5317", "\u5f15\u5bfc\u611f\u77e5", 0, 78, "\u4e2d\u98ce\u9669")
	if _get_top_actionable_lead_by_type("river").is_empty():
		_add_lead("river", "\u6cb3\u8fb9\u8349\u836f", "\u5357\u4fa7\u6cb3\u8fb9", "\u5f15\u5bfc\u611f\u77e5", 0, 76, "\u4f4e\u98ce\u9669")
	if _get_top_actionable_lead_by_type("rumor").is_empty():
		_add_lead("rumor", "\u897f\u4fa7\u9057\u8ff9", "\u9547\u91cc", "\u6302\u5ff5\u76ee\u6807", 0, 74, "\u4f4e\u98ce\u9669")

func _actionable_lead_count() -> int:
	var cnt: int = 0
	for l_any in leads:
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		if int(l.get("freshness", 0)) > 0 and int(l.get("stage", 0)) < 3:
			cnt += 1
	return cnt

func _ensure_leads_from_percepts(min_count: int) -> void:
	_prune_leads()
	_ensure_core_leads()
	if _actionable_lead_count() >= min_count:
		return
	for p in _build_percepts():
		if _actionable_lead_count() >= min_count:
			break
		if p is Dictionary:
			var pt: String = String((p as Dictionary).get("type", "footprint"))
			if pt != "footprint" and pt != "smoke" and pt != "river" and pt != "rumor":
				continue
			_add_lead(pt, String((p as Dictionary).get("target", "\u7ebf\u7d22")), String((p as Dictionary).get("direction", "\u9644\u8fd1")), "\u5f15\u5bfc\u611f\u77e5")

func _ensure_percept_lead_links(percepts: Array[Dictionary]) -> void:
	for p in percepts:
		var p_type: String = String(p.get("type", "footprint"))
		if p_type != "footprint" and p_type != "smoke" and p_type != "river" and p_type != "rumor":
			continue
		var p_dir: String = String(p.get("direction", "\u9644\u8fd1"))
		var found: bool = false
		for l_any in leads:
			if l_any is Dictionary:
				var l: Dictionary = l_any as Dictionary
				if String(l.get("lead_type", l.get("type", ""))) == p_type and String(l.get("target_dir_or_place", l.get("direction", ""))) == p_dir:
					found = true
					break
		if not found:
			_add_lead(p_type, String(p.get("target", "\u7ebf\u7d22")), p_dir, "\u5f15\u5bfc\u611f\u77e5")

func _recommended_actions() -> Array[Dictionary]:
	_ensure_leads_from_percepts(4)
	var cands: Array[Dictionary] = []
	var scored: Array[Dictionary] = []
	for l_any in leads:
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		var st: int = int(l.get("stage", 0))
		var fresh: int = int(l.get("freshness", 0))
		if st >= 3 or fresh <= 0:
			continue
		var score: int = _lead_recommend_score(l)
		scored.append({"score": score, "lead": l})

	var ordered: Array[Dictionary] = []
	for s in scored:
		var inserted: bool = false
		for i in range(ordered.size()):
			if int(s.get("score", 0)) > int(ordered[i].get("score", 0)):
				ordered.insert(i, s)
				inserted = true
				break
		if not inserted:
			ordered.append(s)

	for s in ordered:
		if cands.size() >= 6:
			break
		var lead: Dictionary = s.get("lead", {}) as Dictionary
		var lid: String = String(lead.get("lead_id", lead.get("id", "")))
		cands.append(_action_entry(
			"sys.v03.lead.execute." + lid,
			_lead_stage_title(lead),
			_lead_hint_text(lead),
			_risk_to_cost(String(lead.get("risk_hint", "\u4e2d\u98ce\u9669"))),
			_lead_direction_text(lead),
			true,
			false
		))
	if cands.size() < 3:
		_ensure_core_leads()
		for l_any in leads:
			if cands.size() >= 6:
				break
			if not (l_any is Dictionary):
				continue
			var l2: Dictionary = l_any as Dictionary
			var st2: int = int(l2.get("stage", 0))
			var fresh2: int = int(l2.get("freshness", 0))
			if st2 >= 3 or fresh2 <= 0:
				continue
			var lid2: String = String(l2.get("lead_id", l2.get("id", "")))
			var exists: bool = false
			for c in cands:
				if String(c.get("id", "")) == "sys.v03.lead.execute." + lid2:
					exists = true
					break
			if exists:
				continue
			cands.append(_action_entry(
				"sys.v03.lead.execute." + lid2,
				_lead_stage_title(l2),
				_lead_hint_text(l2),
				_risk_to_cost(String(l2.get("risk_hint", "\u4e2d\u98ce\u9669"))),
				_lead_direction_text(l2),
				true,
				false
			))
	var uniq: Array[Dictionary] = _unique_actions(cands)
	if recommendation_shift_needed and not last_recommended_titles.is_empty():
		uniq = _enforce_recommended_delta(uniq, 2)
	recommendation_shift_needed = false
	last_recommended_titles.clear()
	for a in uniq:
		last_recommended_titles.append(String(a.get("title", "")))
	return uniq

func _lead_recommend_score(lead: Dictionary) -> int:
	var score: int = int(lead.get("freshness", 0)) + int(lead.get("stage", 0)) * 12
	var risk: String = String(lead.get("risk_hint", "\u4e2d\u98ce\u9669"))
	if risk == "\u4f4e\u98ce\u9669":
		score += 6
	elif risk == "\u9ad8\u98ce\u9669":
		score -= 5
	return score

func _count_recommended_delta(new_actions: Array[Dictionary]) -> int:
	var changed: int = 0
	var new_titles: Array[String] = []
	for a in new_actions:
		var t: String = String(a.get("title", ""))
		new_titles.append(t)
		if not last_recommended_titles.has(t):
			changed += 1
	for old_t in last_recommended_titles:
		if not new_titles.has(old_t):
			changed += 1
	return changed

func _enforce_recommended_delta(actions: Array[Dictionary], min_delta: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = _unique_actions(actions.duplicate(true))
	var changed: int = _count_recommended_delta(out)
	if changed >= min_delta:
		return out
	for i in range(out.size()):
		if changed >= min_delta:
			break
		var row: Dictionary = out[i]
		var id_text: String = String(row.get("id", ""))
		if not id_text.begins_with("sys.v03.lead.execute."):
			continue
		var lead_id: String = id_text.trim_prefix("sys.v03.lead.execute.")
		var li: int = _find_lead(lead_id)
		if li < 0:
			continue
		var lead: Dictionary = leads[li]
		lead["title_variant"] = int(lead.get("title_variant", 0)) + 1
		lead["last_update_h"] = time_hours
		leads[li] = lead
		row["title"] = _lead_stage_title(lead)
		row["why"] = _lead_hint_text(lead)
		row["direction"] = _lead_direction_text(lead)
		out[i] = row
		changed = _count_recommended_delta(out)
	return _unique_actions(out)

func _context_actions() -> Array[Dictionary]:
	return []

func _start_micro(action_key: String, target_label: String, lead_id: String, source_reason: String) -> Dictionary:
	if not pending_event.is_empty():
		return _action_result("\u5f53\u524d\u4e8b\u4ef6\u672a\u51b3\uff0c\u8bf7\u5148\u5b8c\u6210\u4e8b\u4ef6\u9636\u6bb5\u3002")
	if lead_id == "":
		return _action_result("\u8bf7\u5148\u4ece\u53ef\u7528\u7ebf\u7d22\u4e2d\u9009\u4e00\u6761\u5177\u4f53\u884c\u52a8\u3002")
	var li: int = _find_lead(lead_id)
	if li < 0:
		return _action_result("\u8fd9\u6761\u7ebf\u7d22\u5df2\u5931\u6548\uff0c\u8bf7\u5148\u89c2\u5bdf\u83b7\u53d6\u65b0\u7ebf\u7d22\u3002")
	var lead: Dictionary = leads[li]
	var lead_type: String = String(lead.get("lead_type", "footprint"))
	var lead_stage: int = int(lead.get("stage", 0))
	micro_nonce += 1
	var fp: String = "%s|%s|%s" % [action_key, current_region_id, target_label]
	var repeated: bool = false
	if micro_fingerprint_h.has(fp):
		var old_h: int = int(micro_fingerprint_h.get(fp, -9999))
		if time_hours - old_h < 24:
			repeated = true
	micro_fingerprint_h[fp] = time_hours
	active_micro = {
		"id": "micro_%d" % micro_nonce, "action_key": action_key, "title": target_label,
		"lead_id": lead_id,
		"lead_type": lead_type,
		"stage": 1,
		"max_stage": 3 if lead_stage >= 2 else 2,
		"source_reason": source_reason,
		"repeat_variant": repeated,
		"state": {"progress": 0, "exposure": 0, "strategy": "", "finale": ""}
	}
	return _action_result("\u884c\u52a8\u5df2\u5f00\u59cb\uff1a%s\n\u7b2c1\u6b65\uff1a\u5148\u9009\u4e00\u4e2a\u63a8\u8fdb\u7b56\u7565\u3002" % target_label)

func _micro_header_text() -> String:
	return "[b]\u5f53\u524d\u884c\u52a8\u6b65\u9aa4[/b]\n\u5730\u70b9\uff1a%s\n\u76ee\u6807\uff1a%s\n\u9636\u6bb5\uff1a%d/%d" % [
		String(current_region.get("name", "\u672a\u77e5\u5730\u70b9")),
		String(active_micro.get("title", "\u672a\u547d\u540d\u76ee\u6807")),
		int(active_micro.get("stage", 1)),
		int(active_micro.get("max_stage", 2))
	]

func _micro_stage_actions() -> Array[Dictionary]:
	if active_micro.is_empty():
		return []
	var stage: int = int(active_micro.get("stage", 1))
	var max_stage: int = int(active_micro.get("max_stage", 2))
	var reason: String = String(active_micro.get("source_reason", "\u6765\u81ea\u5f53\u524d\u7ebf\u7d22"))
	var repeat_variant: bool = bool(active_micro.get("repeat_variant", false))
	if stage >= 2 and max_stage >= 3:
		return _micro_finale_actions()
	var risky_why: String = "\u6765\u81ea\u65f6\u95f4\u538b\u529b\u4e0e\u8feb\u5207\u6027"
	if repeat_variant:
		risky_why = "\u8fd9\u6761\u8def\u7ebf\u8fd1\u671f\u88ab\u91cd\u590d\u4f7f\u7528\uff0c\u5f3a\u63a8\u53cd\u566c\u66f4\u9ad8"
	return [
		_action_entry("sys.v03.micro.cautious", "\u8c28\u614e\u63a8\u8fdb", "\u6765\u81ea\u7ebf\u7d22\u7a33\u5b9a\u9700\u6c42\uff1a" + reason, "1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669", "\u4fe1\u606f\u66f4\u7a33\uff0c\u4f46\u8282\u594f\u6162", true, false),
		_action_entry("sys.v03.micro.quick", "\u5feb\u901f\u63a8\u8fdb", "\u6765\u81ea\u5f53\u524d\u65f6\u95f4\u538b\u529b", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u63a8\u8fdb\u66f4\u5feb\uff0c\u66b4\u9732\u4e5f\u66f4\u9ad8", true, false),
		_action_entry("sys.v03.micro.trick", "\u53d6\u5de7\u5229\u7528\u6761\u4ef6", risky_why + "\uff08\u9700\u4eba\u8109/\u5730\u5f62/\u65f6\u673a\uff09", "1\u5c0f\u65f6\uff5c\u4e2d\u9ad8\u98ce\u9669", "\u6210\u529f\u6709\u989d\u5916\u673a\u4f1a\uff0c\u5931\u624b\u6613\u53cd\u566c", true, false)
	]

func _micro_finale_actions() -> Array[Dictionary]:
	var lt: String = String(active_micro.get("lead_type", "footprint"))
	match lt:
		"footprint":
			return [
				_action_entry("sys.v03.micro.sneak", "\u6f5c\u5165\u8fd1\u8ddd\u79bb\u89c2\u5bdf", "\u6765\u81ea\u8db3\u8ff9\u6e90\u5934\u5df2\u63a5\u8fd1", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u504f\u4fe1\u606f\u4e0e\u8bc1\u636e", true, false),
				_action_entry("sys.v03.micro.contact", "\u51fa\u58f0\u8bd5\u63a2\u5bf9\u65b9", "\u6765\u81ea\u5feb\u901f\u7ed3\u675f\u610f\u56fe", "1\u5c0f\u65f6\uff5c\u9ad8\u98ce\u9669", "\u53ef\u80fd\u76f4\u63a5\u8f6c\u5165\u4e8b\u4ef6", true, false),
				_action_entry("sys.v03.micro.detour", "\u7ed5\u5230\u65c1\u4fa7\u8bbe\u4f0f", "\u6765\u81ea\u5730\u5f62\u5229\u7528\u7b56\u7565", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u53ef\u80fd\u8981\u5230\u673a\u4f1a\uff0c\u4e5f\u53ef\u80fd\u843d\u7a7a", true, false)
			]
		"smoke":
			return [
				_action_entry("sys.v03.micro.sneak", "\u8fdc\u8ddd\u65c1\u542c\u70df\u6e90\u5bf9\u8bdd", "\u6765\u81ea\u708a\u70df\u6e90\u5df2\u9501\u5b9a", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u504f\u4fe1\u606f\u4e0e\u673a\u4f1a", true, false),
				_action_entry("sys.v03.micro.contact", "\u4e0a\u524d\u4ea4\u6d89\u8bd5\u95ee", "\u6765\u81ea\u4eba\u70df\u4ea4\u4e92\u8bc9\u6c42", "1\u5c0f\u65f6\uff5c\u4e2d\u9ad8\u98ce\u9669", "\u53ef\u80fd\u5feb\u901f\u89e3\u9501\u8d44\u6e90\u7ebf", true, false),
				_action_entry("sys.v03.micro.detour", "\u7ed5\u81f3\u4e0a\u98ce\u4fa7\u7ee7\u7eed\u8bd5\u63a2", "\u6765\u81ea\u4fdd\u5b88\u8def\u5f84", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u66f4\u7a33\u5b9a\uff0c\u4f46\u53ef\u80fd\u9519\u8fc7\u7a97\u53e3", true, false)
			]
		"river":
			return [
				_action_entry("sys.v03.micro.sneak", "\u987a\u6d41\u641c\u67e5\u4e0a\u6e38\u6ce5\u5370", "\u6765\u81ea\u8349\u836f\u6e90\u5934\u5df2\u8fd1", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u504f\u4fe1\u606f\u7ebf", true, false),
				_action_entry("sys.v03.micro.contact", "\u5728\u6cb3\u8fb9\u76f4\u63a5\u95ee\u8be2\u91c7\u836f\u4eba", "\u6765\u81ea\u4ea4\u6d89\u8bc9\u6c42", "1\u5c0f\u65f6\uff5c\u4e2d\u9ad8\u98ce\u9669", "\u53ef\u80fd\u7acb\u5373\u83b7\u5f97\u7a00\u6709\u4fe1\u606f", true, false),
				_action_entry("sys.v03.micro.detour", "\u6d89\u6c34\u7ed5\u5230\u53e6\u4e00\u4fa7\u8bd5\u91c7", "\u6765\u81ea\u7ed5\u884c\u7b56\u7565", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u964d\u4f4e\u51b2\u7a81\uff0c\u4f46\u53ef\u80fd\u7a7a\u624b", true, false)
			]
		"rumor":
			return [
				_action_entry("sys.v03.micro.sneak", "\u5728\u9152\u9986\u65c1\u542c\u7ebf\u4eba\u53e3\u98ce", "\u6765\u81ea\u6d88\u606f\u66f4\u65b0\u9700\u6c42", "1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669", "\u504f\u4fe1\u606f\uff0c\u4f46\u51c6\u786e\u5ea6\u4e0d\u7a33", true, false),
				_action_entry("sys.v03.micro.contact", "\u6b63\u9762\u627e\u7ebf\u4eba\u5bf9\u8d28", "\u6765\u81ea\u5feb\u901f\u786e\u8ba4\u8bc9\u6c42", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u53ef\u80fd\u7acb\u5373\u8f6c\u5165\u4e8b\u4ef6", true, false),
				_action_entry("sys.v03.micro.detour", "\u7528\u65e7\u4eba\u60c5\u8ba9\u4e2d\u95f4\u4eba\u5f00\u53e3", "\u6765\u81ea\u53d6\u5de7\u7b56\u7565", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u6210\u529f\u53ef\u5f00\u542f\u673a\u4f1a\uff0c\u5931\u8d25\u4f1a\u53cd\u566c", true, false)
			]
		_:
			return [
				_action_entry("sys.v03.micro.sneak", "\u8c28\u614e\u63a5\u8fd1", "\u6765\u81ea\u7ebf\u7d22\u63a8\u8fdb\u8282\u70b9", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u504f\u4fe1\u606f", true, false),
				_action_entry("sys.v03.micro.contact", "\u76f4\u63a5\u8bd5\u63a2", "\u6765\u81ea\u5feb\u901f\u89e3\u51b3\u8bc9\u6c42", "1\u5c0f\u65f6\uff5c\u4e2d\u9ad8\u98ce\u9669", "\u504f\u63a8\u8fdb", true, false),
				_action_entry("sys.v03.micro.detour", "\u7ed5\u8def\u7ee7\u7eed", "\u6765\u81ea\u56de\u9000\u7b56\u7565", "1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "\u4fdd\u5b88\u63a8\u8fdb", true, false)
			]

func _apply_micro_style(style: String) -> Dictionary:
	if active_micro.is_empty():
		return _action_result("\u5f53\u524d\u6ca1\u6709\u8fdb\u884c\u4e2d\u7684\u884c\u52a8\u6b65\u9aa4\u3002")
	var stage: int = int(active_micro.get("stage", 1))
	var max_stage: int = int(active_micro.get("max_stage", 2))
	if stage == 1 and style != "cautious" and style != "quick" and style != "trick":
		return _action_result("\u8bf7\u5148\u4ece\u4e09\u4e2a\u7b56\u7565\u4e2d\u9009\u4e00\u4e2a\u3002")
	if stage >= 2 and max_stage >= 3 and style != "sneak" and style != "contact" and style != "detour":
		return _action_result("\u8bf7\u9009\u62e9\u4e00\u4e2a\u63a5\u8fd1\u65b9\u5f0f\u3002")
	_advance_time(1)
	_process_expiry()
	var st: Dictionary = active_micro.get("state", {})
	if stage == 1:
		st["strategy"] = style
		st["progress"] = int(st.get("progress", 0)) + (2 if style == "quick" else 1)
		st["exposure"] = int(st.get("exposure", 0)) + (2 if style == "quick" else (1 if style == "trick" else 0))
	else:
		st["finale"] = style
		st["progress"] = int(st.get("progress", 0)) + 1
		st["exposure"] = int(st.get("exposure", 0)) + (1 if style == "contact" else 0)
	active_micro["state"] = st
	if stage == 1 and max_stage >= 3:
		active_micro["stage"] = 2
		return _action_result("\u4f60\u5df2\u5b9a\u4e0b\u63a8\u8fdb\u7b56\u7565\uff0c\u63a5\u4e0b\u6765\u8981\u9009\u62e9\u63a5\u8fd1\u65b9\u5f0f\u3002")
	var strategy: String = String(st.get("strategy", "quick"))
	var finale: String = String(st.get("finale", ""))
	var outcome: Dictionary = _roll_micro_outcome(strategy, finale)
	var text: String = _apply_micro_outcome(outcome)
	active_micro.clear()
	if pending_event.is_empty() and not queued_event_from_lead.is_empty():
		pending_event = queued_event_from_lead.duplicate(true)
		queued_event_from_lead.clear()
		text += "\n\u7ebf\u7d22\u5df2\u8ffd\u5230\u6e90\u5934\uff0c\u4e8b\u4ef6\u9636\u6bb5\u5df2\u51fa\u73b0\u3002"
	return _action_result(text)

func _roll_micro_outcome(strategy: String, finale: String) -> Dictionary:
	var action_key: String = String(active_micro.get("action_key", "observe"))
	var lead_id: String = String(active_micro.get("lead_id", ""))
	var lead_type: String = String(active_micro.get("lead_type", "footprint"))
	var st: Dictionary = active_micro.get("state", {})
	var chance: float = 0.52
	match strategy:
		"cautious":
			chance += 0.10
		"quick":
			chance += 0.02
		"trick":
			var can_trick: bool = charisma >= 10 or int(world_state.get("order", 0)) >= 45
			chance += 0.07 if can_trick else -0.12
		_:
			chance += 0.0
	match finale:
		"sneak":
			chance += 0.05
		"contact":
			chance += 0.0
		"detour":
			chance += 0.02
		_:
			chance += 0.0
	chance += float(int(st.get("progress", 0))) * 0.015
	chance -= float(int(st.get("exposure", 0))) * 0.02
	if bool(active_micro.get("repeat_variant", false)):
		chance -= 0.05
	if lead_id != "":
		var li: int = _find_lead(lead_id)
		if li >= 0:
			var lead: Dictionary = leads[li]
			chance += float(int(lead.get("freshness", 60)) - 50) / 220.0
			chance -= float(int(lead.get("stage", 0))) * 0.03
			var risk_hint: String = String(lead.get("risk_hint", "\u4e2d\u98ce\u9669"))
			if risk_hint == "\u4f4e\u98ce\u9669":
				chance += 0.04
			elif risk_hint == "\u9ad8\u98ce\u9669":
				chance -= 0.08
	var roll: float = rng.randf()
	var success: bool = roll <= chance - 0.08
	var result_kind: String = "neutral"
	if success:
		result_kind = "success"
	elif roll >= chance + 0.08:
		result_kind = "fail"
	var buckets: Array[String] = []
	match result_kind:
		"success":
			buckets = ["A", "C"]
			if rng.randf() < 0.35:
				buckets.append("B")
			if rng.randf() < 0.18:
				buckets.append("E")
		"neutral":
			buckets = ["A", "D"]
			if rng.randf() < 0.35:
				buckets.append("C")
		"fail":
			buckets = ["D", "B"]
			if rng.randf() < 0.26:
				buckets.append("E")
		_:
			buckets = ["A", "D"]
	return {
		"success": success,
		"kind": result_kind,
		"buckets": buckets,
		"text": _pick_micro_result_text(lead_type, result_kind),
		"strategy": strategy,
		"finale": finale,
		"action_key": action_key
	}

func _apply_micro_outcome(outcome: Dictionary) -> String:
	var kind: String = String(outcome.get("kind", "neutral"))
	var strategy: String = String(outcome.get("strategy", "quick"))
	var buckets: Array = outcome.get("buckets", []) as Array
	var lead_id: String = String(active_micro.get("lead_id", ""))
	var lead_type: String = String(active_micro.get("lead_type", "footprint"))
	var lines: Array[String] = [String(outcome.get("text", "\u7ed3\u679c\u5df2\u751f\u6548\u3002"))]
	for b_any in buckets:
		var b: String = String(b_any)
		match b:
			"A":
				_spawn_info_followup_lead(lead_type)
				lines.append("\u4f60\u62ff\u5230\u4e86\u65b0\u4fe1\u606f\uff0c\u63a8\u8350\u884c\u52a8\u5df2\u66f4\u65b0\u3002")
			"B":
				lines.append("\u5f53\u5730\u4eba\u8bb0\u4f4f\u4e86\u4f60\u7684\u5904\u7406\u65b9\u5f0f\uff0c\u5173\u7cfb\u9762\u4ea7\u751f\u4e86\u53d8\u5316\u3002")
			"C":
				goal_reminders.push_front({"text":"\u4f60\u83b7\u5f97\u4e86\u4e00\u4e2a\u65b0\u5f15\u8350\uff0c\u53ef\u4ee5\u53bb\u4e1c\u5317\u70df\u67f1\u8bd5\u8bd5\u3002", "hint_target":"\u4e1c\u5317\u70df\u67f1"})
				if goal_reminders.size() > 4:
					goal_reminders.resize(4)
				lines.append("\u65b0\u673a\u4f1a\u88ab\u6253\u5f00\uff0c\u4f60\u53ef\u4ee5\u8d70\u4e00\u6761\u4e0d\u540c\u7684\u8def\u5f84\u3002")
			"D":
				world_state["danger"] = clamp(int(world_state.get("danger", 0)) + 6, 0, 100)
				_push_rumor("\u6709\u4eba\u8bf4\u4f60\u5728\u9644\u8fd1\u7684\u884c\u52a8\u5f15\u6765\u4e86\u4e0d\u5c11\u6ce8\u610f\u3002", "micro")
				lines.append("\u53cd\u566c\u4fe1\u53f7\u4e0a\u5347\uff1a\u9644\u8fd1\u5371\u9669\u7a0b\u5ea6\u63d0\u9ad8\u3002")
			"E":
				world_state["order"] = clamp(int(world_state.get("order", 0)) - 12, 0, 100)
				_push_rumor("\u544a\u793a\u677f\u65b0\u589e\u4e86\u8def\u7f51\u98ce\u9669\u63d0\u793a\uff0c\u591a\u6570\u4eba\u5f00\u59cb\u7ed5\u8def\u3002", "struct")
				lines.append("\u7ed3\u6784\u53d8\u5316\uff1a\u8be5\u5730\u533a\u8def\u7f51\u98ce\u9669\u7b49\u7ea7\u53d1\u751f\u4e86\u660e\u663e\u53d8\u5316\u3002")
	_apply_lead_progress_after_micro(lead_id, kind, strategy, lines)
	_bump_other_lead_variants(lead_id)
	_add_visible_outcome("%s\uff1a%s" % [String(active_micro.get("title", "\u884c\u52a8")), String(outcome.get("text", ""))])
	lines.append("\u53ef\u89c1\u56de\u6d41\uff1a\u7ebf\u7d22\u6c60\u4e0e\u63a8\u8350\u884c\u52a8\u5df2\u66f4\u65b0\u3002")
	recommendation_shift_needed = true
	guidance_due = true
	return "\n".join(lines)

func _spawn_info_followup_lead(lead_type: String) -> void:
	match lead_type:
		"footprint":
			_add_lead("footprint", "\u65b0\u6ce5\u75d5", "\u897f\u5317", "\u4fe1\u606f\u53cd\u9988", 0, 68, "\u4e2d\u98ce\u9669")
		"smoke":
			_add_lead("smoke", "\u65b0\u708a\u70df\u70b9", "\u4e1c\u5317", "\u4fe1\u606f\u53cd\u9988", 0, 66, "\u4e2d\u98ce\u9669")
		"river":
			_add_lead("river", "\u4e0b\u6e38\u6f6e\u6e7f\u75d5", "\u4e1c\u5357\u6cb3\u6ee9", "\u4fe1\u606f\u53cd\u9988", 0, 65, "\u4f4e\u98ce\u9669")
		"rumor":
			_add_lead("rumor", "\u65b0\u7248\u9057\u8ff9\u6d88\u606f", "\u9547\u91cc", "\u4fe1\u606f\u53cd\u9988", 0, 64, "\u4f4e\u98ce\u9669")
		_:
			_add_lead("footprint", "\u65b0\u8db3\u8ff9", "\u897f\u5317", "\u4fe1\u606f\u53cd\u9988", 0, 64, "\u4e2d\u98ce\u9669")

func _pick_micro_result_text(lead_type: String, kind: String) -> String:
	var success_pool: Array[String] = []
	var fail_pool: Array[String] = []
	var neutral_pool: Array[String] = []
	match lead_type:
		"footprint":
			success_pool = ["\u4f60\u8bfb\u51fa\u4e86\u8db3\u8ff9\u8f6c\u6298\uff0c\u8ffd\u7ebf\u8def\u5f84\u66f4\u6e05\u6670\u4e86\u3002", "\u8fd9\u6b21\u7b56\u7565\u5bf9\u4e0a\u4e86\u8282\u594f\uff0c\u8db3\u8ff9\u63a8\u8fdb\u5f88\u987a\u3002", "\u4f60\u5728\u6ce5\u75d5\u91cc\u62ff\u5230\u4e86\u786e\u5b9a\u4fe1\u53f7\uff0c\u53ef\u4ee5\u5f80\u524d\u538b\u4e86\u3002"]
			fail_pool = ["\u4f60\u8ddf\u5230\u4e86\u4f2a\u88c5\u8def\u5f84\uff0c\u8fd9\u6761\u7ebf\u7684\u98ce\u9669\u660e\u663e\u4e0a\u6765\u4e86\u3002", "\u8fd9\u6b21\u5224\u65ad\u5931\u8bef\uff0c\u8db3\u8ff9\u5728\u89c6\u91ce\u91cc\u65ad\u5f00\u4e86\u3002", "\u4f60\u8fc7\u65e9\u66b4\u9732\u4e86\u884c\u8e2a\uff0c\u5bf9\u65b9\u5f00\u59cb\u53cd\u5411\u8bbe\u9632\u3002"]
			neutral_pool = ["\u4f60\u4fdd\u4f4f\u4e86\u7ebf\u7d22\uff0c\u4f46\u8fd8\u6ca1\u62ff\u5230\u51b3\u5b9a\u6027\u8282\u70b9\u3002", "\u8db3\u8ff9\u8fd8\u80fd\u7ee7\u7eed\u8ddf\uff0c\u53ea\u662f\u9700\u8981\u6362\u4e2a\u5207\u5165\u65b9\u5f0f\u3002", "\u8fd9\u4e00\u6b65\u628a\u5c40\u52bf\u7a33\u4f4f\u4e86\uff0c\u771f\u6b63\u7a81\u7834\u5728\u4e0b\u4e00\u8f6e\u3002"]
		"smoke":
			success_pool = ["\u4f60\u9501\u5b9a\u4e86\u70df\u6e90\u6709\u6548\u533a\uff0c\u4eba\u70df\u7ebf\u5f00\u59cb\u6709\u56de\u5e94\u3002", "\u4f60\u5728\u4e0a\u98ce\u4fa7\u62ff\u5230\u4e86\u7a33\u5b9a\u4fe1\u606f\uff0c\u8fd9\u6b21\u63a8\u8fdb\u6210\u529f\u4e86\u3002", "\u708a\u70df\u8282\u5f8b\u88ab\u4f60\u8bfb\u5bf9\uff0c\u7ebf\u7d22\u8fdb\u5165\u4e86\u4e0b\u4e00\u9636\u6bb5\u3002"]
			fail_pool = ["\u70df\u67f1\u5728\u4f60\u63a5\u8fd1\u524d\u5c31\u53d8\u5f97\u6df7\u4e71\uff0c\u8fd9\u6b21\u8ddf\u8fdb\u53d7\u632b\u3002", "\u4f60\u8fc7\u65e9\u4e0a\u524d\uff0c\u70df\u6e90\u9644\u8fd1\u7684\u4eba\u5bf9\u4f60\u8d77\u4e86\u8b66\u89c9\u3002", "\u4f60\u8ffd\u5230\u4e86\u7a7a\u706b\u5806\uff0c\u8fd9\u6761\u7ebf\u7d22\u56de\u62a5\u964d\u4e0b\u6765\u4e86\u3002"]
			neutral_pool = ["\u4f60\u5df2\u8fdb\u5165\u70df\u6e90\u8fb9\u754c\uff0c\u4f46\u8fd8\u9700\u8981\u518d\u6d4b\u4e00\u6b65\u3002", "\u4eba\u70df\u7ebf\u6682\u65f6\u7a33\u4f4f\u4e86\uff0c\u4ecd\u9700\u66f4\u51c6\u7684\u5207\u5165\u70b9\u3002", "\u4f60\u62ff\u5230\u4e86\u90e8\u5206\u60c5\u62a5\uff0c\u540e\u7eed\u7b56\u7565\u4f1a\u51b3\u5b9a\u6210\u8d25\u3002"]
		"river":
			success_pool = ["\u4f60\u5b9a\u4f4d\u4e86\u53ef\u7528\u6cb3\u8fb9\u533a\uff0c\u8865\u7ed9\u7ebf\u8fdb\u5ea6\u4e0a\u6765\u4e86\u3002", "\u4f60\u5728\u6cb3\u6ee9\u62ff\u5230\u4e86\u8fde\u8d2f\u75d5\u8ff9\uff0c\u4e0b\u4e00\u6b65\u66f4\u597d\u8d70\u3002", "\u8fd9\u6b21\u7b5b\u67e5\u6709\u6548\uff0c\u8349\u836f\u7ebf\u7d22\u4ece\u6a21\u7cca\u53d8\u5b9e\u4e86\u3002"]
			fail_pool = ["\u4f60\u8bef\u5165\u4e86\u4f4e\u6548\u533a\uff0c\u8017\u65f6\u53c8\u62ac\u9ad8\u4e86\u98ce\u9669\u3002", "\u6cb3\u7ebf\u5224\u65ad\u8dd1\u504f\u4e86\uff0c\u73b0\u5728\u8fd9\u6761\u7ebf\u66f4\u96be\u76f4\u63a5\u63a8\u8fdb\u3002", "\u4f60\u7684\u6d89\u6c34\u9009\u62e9\u8ba9\u7ebf\u7d22\u5012\u9000\u4e86\u4e00\u622a\u3002"]
			neutral_pool = ["\u4f60\u8fd8\u6ca1\u627e\u5230\u51b3\u5b9a\u8282\u70b9\uff0c\u4f46\u8fd9\u6761\u7ebf\u4ecd\u53ef\u7ee7\u7eed\u3002", "\u6cb3\u8fb9\u7ebf\u7d22\u5904\u4e8e\u8fc7\u6e21\u6bb5\uff0c\u9700\u8981\u518d\u8ffd\u4e00\u6b65\u3002", "\u4f60\u4fdd\u4f4f\u4e86\u8865\u7ed9\u7a97\u53e3\uff0c\u4f46\u8fd8\u6ca1\u6709\u62ff\u5230\u786c\u7ed3\u679c\u3002"]
		"rumor":
			success_pool = ["\u4f60\u628a\u53e3\u98ce\u6821\u51c6\u6210\u4e86\u53ef\u843d\u5730\u7684\u60c5\u62a5\u3002", "\u4f60\u62ff\u5230\u4e86\u5173\u952e\u7ebf\u4eba\u7684\u786e\u8ba4\uff0c\u6d88\u606f\u7ebf\u63a8\u8fdb\u6210\u529f\u3002", "\u4f60\u8ffd\u5230\u4e86\u4f20\u95fb\u6e90\u5934\uff0c\u5f88\u5feb\u5c31\u80fd\u8f6c\u5165\u4e8b\u4ef6\u9636\u6bb5\u3002"]
			fail_pool = ["\u7ebf\u4eba\u4e34\u65f6\u6539\u53e3\uff0c\u8fd9\u6761\u6d88\u606f\u7ebf\u53d8\u5f97\u66f4\u4e0d\u7a33\u5b9a\u3002", "\u4f60\u7684\u8bd5\u63a2\u88ab\u5bf9\u65b9\u8bc6\u7834\uff0c\u9547\u91cc\u5f00\u59cb\u51fa\u73b0\u53cd\u5411\u98ce\u58f0\u3002", "\u4f60\u62ff\u5230\u4e86\u8bef\u5bfc\u7248\u6d88\u606f\uff0c\u5f53\u524d\u8def\u7ebf\u88ab\u62d6\u6162\u4e86\u3002"]
			neutral_pool = ["\u4f60\u6574\u5408\u4e86\u90e8\u5206\u6d88\u606f\uff0c\u4f46\u8fd8\u5dee\u4e00\u4e2a\u786e\u8ba4\u73af\u8282\u3002", "\u6d88\u606f\u7ebf\u6682\u65f6\u7a33\u4f4f\uff0c\u4ecd\u9700\u8981\u66f4\u4e3b\u52a8\u7684\u540e\u7eed\u5904\u7406\u3002", "\u4f60\u907f\u5f00\u4e86\u6700\u574f\u7ed3\u679c\uff0c\u4f46\u4e5f\u8fd8\u6ca1\u62ff\u5230\u6700\u597d\u56de\u62a5\u3002"]
		_:
			success_pool = ["\u4f60\u5b8c\u6210\u4e86\u4e00\u6b65\u6709\u6548\u63a8\u8fdb\u3002"]
			fail_pool = ["\u8fd9\u6b21\u5904\u7406\u5931\u624b\uff0c\u5c40\u52bf\u66f4\u7d27\u4e86\u3002"]
			neutral_pool = ["\u8fd9\u6b21\u7ed3\u679c\u5904\u4e8e\u4e2d\u95f4\u6001\u3002"]
	var pool: Array[String] = neutral_pool
	if kind == "success":
		pool = success_pool
	elif kind == "fail":
		pool = fail_pool
	return _pick_text(pool)

func _apply_lead_progress_after_micro(lead_id: String, kind: String, strategy: String, lines: Array[String]) -> void:
	var idx: int = _find_lead(lead_id)
	if idx < 0:
		return
	var lead: Dictionary = leads[idx]
	var stage: int = int(lead.get("stage", 0))
	var fresh: int = int(lead.get("freshness", 70))
	var removed: bool = false
	match kind:
		"success":
			lead["stage"] = min(3, stage + 1)
			lead["freshness"] = clamp(fresh + 10, 0, 100)
			lead["risk_hint"] = "\u4f4e\u98ce\u9669" if strategy == "cautious" else "\u4e2d\u98ce\u9669"
			lines.append("\u7ebf\u7d22\u63a8\u8fdb\uff1a\u8fd9\u6761\u7ebf\u5df2\u7ecf\u63a8\u5230\u4e0b\u4e00\u9636\u6bb5\u3002")
		"neutral":
			lead["freshness"] = clamp(fresh - 8, 0, 100)
			lead["risk_hint"] = "\u4e2d\u98ce\u9669"
			if rng.randf() < 0.55:
				_spawn_variant_lead_from(lead)
				lines.append("\u7ebf\u7d22\u5206\u5316\uff1a\u51fa\u73b0\u4e86\u4e00\u6761\u65b0\u53d8\u4f53\u7ebf\u7d22\u3002")
			lines.append("\u7ebf\u7d22\u72b6\u6001\uff1a\u8fdb\u5c55\u6709\u9650\uff0c\u4e0b\u6b21\u9700\u8981\u6362\u7b56\u7565\u3002")
		"fail":
			lead["freshness"] = clamp(fresh - 22, 0, 100)
			lead["risk_hint"] = "\u9ad8\u98ce\u9669"
			if stage > 0 and rng.randf() < 0.65:
				lead["stage"] = stage - 1
			if int(lead.get("freshness", 0)) <= 0:
				leads.remove_at(idx)
				removed = true
				lines.append("\u7ebf\u7d22\u65ad\u88c2\uff1a\u8fd9\u6761\u7ebf\u7d22\u6682\u65f6\u8ffd\u4e0d\u4e0a\u4e86\u3002")
			else:
				lines.append("\u7ebf\u7d22\u53d7\u632b\uff1a\u8fd9\u6761\u7ebf\u7684\u98ce\u9669\u7b49\u7ea7\u63d0\u5347\u4e86\u3002")
		_:
			pass
	if not removed:
		lead["title_variant"] = int(lead.get("title_variant", 0)) + 1
		lead["last_update_h"] = time_hours
		leads[idx] = lead
		if int(lead.get("stage", 0)) >= 3:
			_queue_event_from_lead(lead)
			lines.append("\u7ebf\u7d22\u6536\u675f\uff1a\u5df2\u903c\u8fd1\u6e90\u5934\uff0c\u4e8b\u4ef6\u9636\u6bb5\u5373\u5c06\u5c55\u5f00\u3002")

func _spawn_variant_lead_from(base_lead: Dictionary) -> void:
	var lt: String = String(base_lead.get("lead_type", "footprint"))
	var stage: int = int(base_lead.get("stage", 0))
	match lt:
		"footprint":
			_add_lead("footprint", "\u6df7\u4e71\u8db3\u8ff9", "\u897f\u5317\u4fa7", "\u7ebf\u7d22\u5206\u5316", max(0, stage - 1), 58, "\u9ad8\u98ce\u9669")
		"smoke":
			_add_lead("smoke", "\u65ad\u7eed\u70df\u7ebf", "\u4e1c\u5317\u4fa7", "\u7ebf\u7d22\u5206\u5316", max(0, stage - 1), 56, "\u4e2d\u98ce\u9669")
		"river":
			_add_lead("river", "\u53e6\u4e00\u6bb5\u6cb3\u6e7e", "\u4e1c\u5357\u6cb3\u6ee9", "\u7ebf\u7d22\u5206\u5316", max(0, stage - 1), 55, "\u4e2d\u98ce\u9669")
		"rumor":
			_add_lead("rumor", "\u4e89\u8bae\u7248\u6d88\u606f", "\u65e7\u9152\u9986", "\u7ebf\u7d22\u5206\u5316", max(0, stage - 1), 54, "\u4e2d\u98ce\u9669")
		_:
			pass

func _bump_other_lead_variants(exclude_lead_id: String) -> void:
	var ranked: Array[Dictionary] = []
	for i in range(leads.size()):
		var l_any: Variant = leads[i]
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		if String(l.get("lead_id", l.get("id", ""))) == exclude_lead_id:
			continue
		if int(l.get("stage", 0)) >= 3 or int(l.get("freshness", 0)) <= 0:
			continue
		ranked.append({"idx": i, "score": _lead_recommend_score(l)})

	var ordered: Array[Dictionary] = []
	for r in ranked:
		var inserted: bool = false
		for j in range(ordered.size()):
			if int(r.get("score", 0)) > int(ordered[j].get("score", 0)):
				ordered.insert(j, r)
				inserted = true
				break
		if not inserted:
			ordered.append(r)

	var changed: int = 0
	for row in ordered:
		if changed >= 2:
			break
		var idx: int = int(row.get("idx", -1))
		if idx < 0 or idx >= leads.size():
			continue
		var lead: Dictionary = leads[idx]
		lead["title_variant"] = int(lead.get("title_variant", 0)) + 1
		lead["freshness"] = max(0, int(lead.get("freshness", 0)) - 6)
		lead["last_update_h"] = time_hours
		leads[idx] = lead
		changed += 1

func _remove_lead_by_id(lead_id: String) -> void:
	var idx: int = _find_lead(lead_id)
	if idx >= 0:
		leads.remove_at(idx)

func _queue_event_from_lead(lead: Dictionary) -> void:
	if not queued_event_from_lead.is_empty():
		return
	var lt: String = String(lead.get("lead_type", "footprint"))
	var region_name: String = String(current_region.get("name", "\u672a\u77e5\u5730\u70b9"))
	var thread_label: String = "%s %d/3" % [String(active_thread.get("name", "\u65e0\u7ebf\u7a0b")), int(active_thread.get("stage", 1))]
	var title: String = "\u7ebf\u7d22\u6e90\u5934\u4e8b\u4ef6"
	var options: Array[Dictionary] = []
	var segment: String = "free"
	if lt == "footprint":
		title = "\u8db3\u8ff9\u5c3d\u5934\uff1a\u7591\u4f3c\u76d8\u67e5\u70b9"
		segment = "locked" if rng.randf() < 0.45 else "free"
		options = [
			{"id":"sneak", "title":"\u8d34\u8fb9\u6f5c\u884c\u5224\u8bfb\u5bf9\u65b9\u89c4\u6a21", "why":"\u6765\u81ea\u8db3\u8ff9\u6e90\u5934\u5df2\u663e\u5f62", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "direction":"\u504f\u4fe1\u606f\u4e0e\u5e03\u5c40"},
			{"id":"direct", "title":"\u6b63\u9762\u63a5\u89e6\u8bd5\u63a2", "why":"\u6765\u81ea\u5feb\u901f\u7ed3\u7b97\u8bc9\u6c42", "cost":"1\u5c0f\u65f6\uff5c\u9ad8\u98ce\u9669", "direction":"\u53ef\u80fd\u7acb\u5373\u5bf9\u6297"},
			{"id":"detour", "title":"\u7ed5\u5230\u4e0a\u4fa7\u89c2\u5bdf\u9000\u8def", "why":"\u6765\u81ea\u4fdd\u5b88\u7b56\u7565", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "direction":"\u504f\u7a33\u5b9a\u4f46\u8f83\u6162"}
		]
	elif lt == "smoke":
		title = "\u708a\u70df\u6e90\u5934\uff1a\u8425\u5730\u70ed\u70b9"
		options = [
			{"id":"listen", "title":"\u5728\u5916\u5708\u65c1\u542c\u5bf9\u8bdd", "why":"\u6765\u81ea\u70df\u6e90\u5df2\u9501\u5b9a", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "direction":"\u4fe1\u606f\u4f18\u5148"},
			{"id":"approach", "title":"\u5e26\u7406\u7531\u9760\u8fd1\u8bd5\u95ee", "why":"\u6765\u81ea\u4ea4\u6d89\u8bc9\u6c42", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u9ad8\u98ce\u9669", "direction":"\u53ef\u80fd\u5feb\u901f\u83b7\u5f97\u673a\u4f1a"},
			{"id":"wait", "title":"\u5728\u98ce\u53e3\u5916\u56f4\u7b49\u5f85\u53d8\u5316", "why":"\u6765\u81ea\u7b49\u7a97\u53e3\u7b56\u7565", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "direction":"\u964d\u98ce\u9669\u4f46\u53ef\u80fd\u9519\u8fc7"}
		]
	elif lt == "river":
		title = "\u6cb3\u8fb9\u6e90\u5934\uff1a\u91c7\u836f\u70b9\u7ea0\u7eb7"
		options = [
			{"id":"mediate", "title":"\u5148\u8c03\u505c\u518d\u95ee\u6765\u8def", "why":"\u6765\u81ea\u6cb3\u8fb9\u7ea0\u7eb7\u4fe1\u53f7", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "direction":"\u5173\u7cfb\u4e0e\u4fe1\u606f"},
			{"id":"grab", "title":"\u62a2\u5148\u62ff\u8d70\u53ef\u7528\u8d44\u6e90", "why":"\u6765\u81ea\u7d27\u6025\u8865\u7ed9\u8bc9\u6c42", "cost":"1\u5c0f\u65f6\uff5c\u9ad8\u98ce\u9669", "direction":"\u77ed\u671f\u6536\u76ca\u4f46\u6613\u53cd\u566c"},
			{"id":"observe", "title":"\u5728\u4e0a\u6e38\u89c2\u5bdf\u7b49\u7b2c\u4e8c\u6ce2", "why":"\u6765\u81ea\u4fdd\u5b88\u8ba1\u5212", "cost":"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669", "direction":"\u4fe1\u606f\u79ef\u7d2f"}
		]
	else:
		title = "\u7ebf\u4eba\u5bf9\u8d28\uff1a\u771f\u5047\u6d88\u606f"
		options = [
			{"id":"verify", "title":"\u9010\u6761\u6838\u5bf9\u6d88\u606f\u6765\u6e90", "why":"\u6765\u81ea\u6d88\u606f\u94fe\u51b2\u7a81", "cost":"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669", "direction":"\u4fe1\u606f\u8d28\u91cf\u63d0\u5347"},
			{"id":"press", "title":"\u76f4\u63a5\u65bd\u538b\u8981\u7ed3\u8bba", "why":"\u6765\u81ea\u65f6\u95f4\u538b\u529b", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u9ad8\u98ce\u9669", "direction":"\u53ef\u80fd\u5feb\u8fdb\u6216\u5f15\u53d1\u53cd\u611f"},
			{"id":"side", "title":"\u7528\u4e2d\u95f4\u4eba\u4fa7\u9762\u6c42\u8bc1", "why":"\u6765\u81ea\u53d6\u5de7\u7b56\u7565", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "direction":"\u53ef\u80fd\u6253\u5f00\u65b0\u673a\u4f1a"}
		]
	queued_event_from_lead = {
		"id":"ev_lead_%d" % (time_hours * 10 + rng.randi_range(1, 9)),
		"segment": segment,
		"title": title,
		"location": region_name,
		"thread_label": thread_label,
		"deadline_h": time_hours + rng.randi_range(5, 8),
		"allow_leave": true,
		"trigger_reason": "\u4f60\u628a\u7ebf\u7d22\u8ffd\u5230\u4e86\u6e90\u5934\u3002",
		"stage": 1,
		"max_stage": rng.randi_range(2, 3),
		"options": options
	}
	_remove_lead_by_id(String(lead.get("lead_id", lead.get("id", ""))))

func _try_trigger_event_from_mature_lead() -> bool:
	if not pending_event.is_empty() or not active_micro.is_empty():
		return false
	var picked: Dictionary = {}
	for l_any in leads:
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		if int(l.get("stage", 0)) >= 3:
			picked = l
			break
	if not picked.is_empty():
		_queue_event_from_lead(picked)
	if pending_event.is_empty() and not queued_event_from_lead.is_empty():
		pending_event = queued_event_from_lead.duplicate(true)
		queued_event_from_lead.clear()
		lead_feedback_queue.append("\u7ebf\u7d22\u6e90\u5934\u66b4\u9732\uff1a\u884c\u52a8\u9762\u677f\u5df2\u5207\u6362\u4e3a\u4e8b\u4ef6\u9636\u6bb5\u3002")
		return true
	return false

func _apply_lead_action(choice_id: String) -> Dictionary:
	var parts: PackedStringArray = choice_id.split(".")
	if parts.size() < 5:
		return _action_result("\u7ebf\u7d22\u884c\u52a8\u65e0\u6548\u3002")
	var lead_id: String = String(parts[parts.size() - 1])
	var idx: int = _find_lead(lead_id)
	if idx < 0:
		return _action_result("\u8fd9\u6761\u7ebf\u7d22\u5df2\u5931\u6548\u3002")
	var lead: Dictionary = leads[idx]
	var title: String = _lead_title(lead)
	var lead_type: String = String(lead.get("lead_type", "footprint"))
	match lead_type:
		"footprint":
			return _start_micro("track", title, lead_id, "\u6765\u81ea\u8db3\u8ff9\u7ebf\u7d22")
		"smoke":
			return _start_micro("investigate", title, lead_id, "\u6765\u81ea\u70df\u67f1\u7ebf\u7d22")
		"river":
			return _start_micro("forage", title, lead_id, "\u6765\u81ea\u6cb3\u8fb9\u7ebf\u7d22")
		"rumor":
			return _start_micro("ask", title, lead_id, "\u6765\u81ea\u9547\u91cc\u6d88\u606f\u7ebf")
		_:
			return _start_micro("observe", title, lead_id, "\u6765\u81ea\u73af\u5883\u7ebf\u7d22")

func _spawn_segment_free_event(reason: String="") -> void:
	if not pending_event.is_empty() or not active_micro.is_empty():
		return
	var remain: int = rng.randi_range(5, 9)
	pending_event = {
		"id":"ev_free_%d" % (time_hours * 10 + rng.randi_range(1, 9)),
		"segment":"free",
		"title":"\u8857\u5934\u6c42\u52a9\uff1a\u53d7\u4f24\u4fe1\u4f7f",
		"location": String(current_region.get("name", "\u672a\u77e5\u5730\u70b9")),
		"thread_label":"%s %d/3" % [String(active_thread.get("name", "\u65e0\u7ebf\u7a0b")), int(active_thread.get("stage", 1))],
		"deadline_h": time_hours + remain,
		"allow_leave": true,
		"trigger_reason": reason if reason != "" else "\u4f60\u5728\u8282\u70b9\u79fb\u52a8\u65f6\u89e6\u53d1\u4e86\u8fd9\u6761\u6c42\u52a9\u7ebf\u7d22",
		"options": [
			{"id":"help", "title":"\u5148\u6b62\u8840\u518d\u8be2\u95ee\u53bb\u5411", "why":"\u6765\u81ea\u73b0\u573a\u4f24\u60c5\u4fe1\u53f7", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "direction":"\u53ef\u80fd\u83b7\u5f97\u5f15\u8350\u548c\u65b0\u7ebf\u7d22"},
			{"id":"ask", "title":"\u4e0d\u51fa\u624b\uff0c\u5148\u8ffd\u95ee\u7ec6\u8282", "why":"\u6765\u81ea\u53ef\u7591\u8e2a\u8ff9\u548c\u8eab\u4efd\u4e0d\u660e", "cost":"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669", "direction":"\u504f\u4fe1\u606f\u6536\u76ca\u3001\u673a\u4f1a\u4e0d\u7a33"},
			{"id":"escort", "title":"\u62a4\u9001\u5bf9\u65b9\u53bb\u9547\u53e3", "why":"\u6765\u81ea\u5b89\u5168\u4f18\u5148\u7b56\u7565", "cost":"2\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "direction":"\u504f\u5173\u7cfb\u4e0e\u58f0\u671b\uff0c\u53ef\u80fd\u89e6\u53d1\u540e\u7eed"}
		]
	}

func _spawn_segment_locked_event() -> void:
	if not pending_event.is_empty() or not active_micro.is_empty():
		return
	pending_event = {
		"id":"ev_lock_%d" % (time_hours * 10 + rng.randi_range(1, 9)),
		"segment":"locked",
		"title":"\u7a81\u53d1\u8ffd\u9010\uff1a\u6797\u95f4\u5f71\u5b50\u8fd1\u8eab",
		"location": String(current_region.get("name", "\u672a\u77e5\u5730\u70b9")),
		"thread_label":"%s %d/3" % [String(active_thread.get("name", "\u65e0\u7ebf\u7a0b")), int(active_thread.get("stage", 1))],
		"stage": 1,
		"max_stage": rng.randi_range(2, 3),
		"trigger_reason":"\u5371\u9669\u503c\u4e0a\u5347\u5f15\u53d1\u4e86\u8fde\u6bb5\u51b2\u7a81",
		"options": [
			{"id":"dodge", "title":"\u4f4e\u8eab\u7ed5\u884c\u89c4\u907f", "why":"\u6765\u81ea\u5730\u5f62\u906e\u853d\u6761\u4ef6", "cost":"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669", "direction":"\u7a33\u4f4f\u66b4\u9732\u5ea6\u5e76\u4e89\u53d6\u4e0b\u4e00\u6b65"},
			{"id":"counter", "title":"\u56de\u5934\u53cd\u538b\u5236", "why":"\u6765\u81ea\u4e3b\u52a8\u638c\u63a7\u7b56\u7565", "cost":"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669", "direction":"\u5feb\u901f\u63a8\u8fdb\uff0c\u4f46\u53ef\u80fd\u53d7\u4f24"},
			{"id":"burst", "title":"\u5168\u529b\u51b2\u51fb\u8131\u79bb", "why":"\u6765\u81ea\u65f6\u95f4\u538b\u529b\u4e0e\u8feb\u5207\u6027", "cost":"1\u5c0f\u65f6\uff5c\u9ad8\u98ce\u9669", "direction":"\u53ef\u80fd\u7acb\u5373\u8131\u56f0\uff0c\u4e5f\u53ef\u80fd\u8fde\u7eed\u53cd\u566c"}
		]
	}
func _event_header_text() -> String:
	if pending_event.is_empty():
		return "[b]\u5f53\u524d\u4e8b\u4ef6\u9636\u6bb5[/b]"
	var seg: String = String(pending_event.get("segment", "free"))
	var remain: String = ""
	if seg == "free":
		remain = "\u8fd8\u5269 %dh" % max(0, int(pending_event.get("deadline_h", time_hours)) - time_hours)
	else:
		remain = "\u8fd8\u9700 %d \u6b65" % max(1, int(pending_event.get("max_stage", 2)) - int(pending_event.get("stage", 1)) + 1)
	return "[b]%s[/b]\n\u5730\u70b9\uff1a%s\n\u7ebf\u7a0b\uff1a%s\n\u5269\u4f59\uff1a%s" % [
		String(pending_event.get("title", "\u4e8b\u4ef6")),
		String(pending_event.get("location", "\u672a\u77e5\u5730\u70b9")),
		String(pending_event.get("thread_label", "\u65e0\u7ebf\u7a0b")),
		remain
	]

func _event_stage_actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for op_any in pending_event.get("options", []):
		if op_any is Dictionary:
			var op: Dictionary = op_any as Dictionary
			out.append(_action_entry("sys.v03.event.option." + String(op.get("id", "")), String(op.get("title", "\u4e8b\u4ef6\u9009\u9879")), String(op.get("why", "\u6765\u81ea\u4e8b\u4ef6\u4fe1\u53f7")), String(op.get("cost", "\u7acb\u5373\u51b3\u7b56")), String(op.get("direction", "\u63a8\u8fdb\u4e8b\u4ef6\u7ebf\u7a0b")), true, false))
	if String(pending_event.get("segment", "free")) == "free":
		out.append(_action_entry("sys.v03.event.defer", "\u7a0d\u540e\u5904\u7406\uff08\u653e\u5165\u5f85\u529e\uff09", "\u6765\u81ea\u65f6\u9650\u4e8b\u4ef6\u7684\u7f13\u5904\u9700\u6c42", "\u7acb\u5373\u9000\u51fa\u672c\u9636\u6bb5", "\u4f1a\u5728\u622a\u6b62\u540e\u81ea\u52a8\u8fc7\u671f\u5e76\u5199\u56de\u4e16\u754c", true, false))
		if bool(pending_event.get("allow_leave", false)):
			out.append(_action_entry("sys.v03.event.leave", "\u79bb\u5f00\u73b0\u573a", "\u6765\u81ea\u81ea\u4fdd\u8003\u91cf", "\u7acb\u5373\u9000\u51fa", "\u53ef\u80fd\u4ea7\u751f\u8d1f\u9762\u4f20\u95fb\u6216\u5173\u7cfb\u53d8\u5316", true, false))
	return out

func _apply_event_choice(choice_id: String) -> Dictionary:
	if pending_event.is_empty():
		return _action_result("\u5f53\u524d\u6ca1\u6709\u5f85\u5904\u7406\u4e8b\u4ef6\u3002")
	if choice_id == "sys.v03.event.defer":
		backlog_nonce += 1
		var item: Dictionary = pending_event.duplicate(true)
		item["backlog_id"] = "backlog_%d" % backlog_nonce
		backlog.append(item)
		pending_event.clear()
		guidance_due = true
		return _action_result("\u4e8b\u4ef6\u5df2\u653e\u5165\u5f85\u529e\u5217\u8868\uff0c\u8d85\u8fc7\u65f6\u9650\u4f1a\u81ea\u52a8\u8fc7\u671f\u5e76\u4ea7\u751f\u540e\u679c\u3002")
	if choice_id == "sys.v03.event.leave":
		world_state["danger"] = clamp(int(world_state.get("danger", 0)) + 3, 0, 100)
		_push_rumor("\u4f60\u79bb\u5f00\u4e86\u73b0\u573a\u6c42\u52a9\uff0c\u8fd9\u4ef6\u4e8b\u5f88\u5feb\u88ab\u4f20\u5f00\u4e86\u3002", "event")
		pending_event.clear()
		guidance_due = true
		return _action_result("\u4f60\u9009\u62e9\u4e86\u79bb\u5f00\uff0c\u5c40\u52bf\u98ce\u9669\u7565\u6709\u4e0a\u6d6e\u3002")
	if not choice_id.begins_with("sys.v03.event.option."):
		return _action_result("\u4e8b\u4ef6\u9009\u9879\u65e0\u6548\u3002")
	if String(pending_event.get("segment", "free")) == "locked":
		_advance_time(1)
		var stage: int = int(pending_event.get("stage", 1)) + 1
		if stage <= int(pending_event.get("max_stage", 2)):
			pending_event["stage"] = stage
			return _action_result("\u4f60\u6297\u4f4f\u4e86\u8fd9\u4e00\u6b65\u51b2\u51fb\uff0c\u8fd8\u9700\u7ee7\u7eed\u5904\u7406\u3002")
		pending_event.clear()
		world_state["danger"] = clamp(int(world_state.get("danger", 0)) - 6, 0, 100)
		_add_visible_outcome("\u4f60\u5b8c\u6210\u4e86\u4e00\u6b21\u8fde\u6bb5\u5371\u673a\u5904\u7406\uff0c\u73b0\u573a\u538b\u529b\u88ab\u538b\u4e0b\u53bb\u4e86\u3002")
		guidance_due = true
		return _action_result("\u8fde\u6bb5\u4e8b\u4ef6\u7ed3\u675f\uff0c\u4f60\u91cd\u65b0\u56de\u5230\u81ea\u7531\u884c\u52a8\u3002")
	var out: String = _resolve_free_event_option(choice_id.trim_prefix("sys.v03.event.option."))
	pending_event.clear()
	guidance_due = true
	return _action_result(out)

func _resolve_free_event_option(opt_id: String) -> String:
	_advance_time(1)
	var lines: Array[String] = []
	if opt_id == "help":
		if rng.randf() < 0.6:
			_add_lead("rumor", "\u897f\u4fa7\u9057\u8ff9", "\u9547\u53e3", "\u4e8b\u4ef6\u56de\u9988")
			lines.append("\u4f60\u7a33\u4f4f\u4f24\u8005\u540e\u5f97\u5230\u4e86\u4e00\u6761\u65b0\u7ebf\u7d22\u3002")
			lines.append("\u53ef\u89c1\u56de\u6d41\uff1a\u56de\u9547\u6253\u542c\u9057\u8ff9\u7684\u884c\u52a8\u5df2\u89e3\u9501\u3002")
		else:
			world_state["danger"] = clamp(int(world_state.get("danger", 0)) + 5, 0, 100)
			_push_rumor("\u6709\u4eba\u8bf4\u4f60\u63d2\u624b\u540e\u4e8b\u60c5\u53cd\u800c\u53d8\u4e71\u4e86\u3002", "event")
			lines.append("\u4f60\u88ab\u8bef\u4f1a\u4e3a\u504f\u888b\u67d0\u65b9\uff0c\u73b0\u573a\u98ce\u9669\u4e0a\u5347\u3002")
	elif opt_id == "ask":
		_add_lead("footprint", "\u7591\u4f3c\u8f6c\u8fd0\u8def\u5f84", "\u897f\u5357", "\u4e8b\u4ef6\u8be2\u95ee")
		lines.append("\u4f60\u95ee\u51fa\u4e86\u53ef\u8ffd\u8e2a\u7684\u8def\u5f84\u4fe1\u606f\u3002")
		lines.append("\u53ef\u89c1\u56de\u6d41\uff1a\u63a8\u8350\u884c\u52a8\u4e2d\u51fa\u73b0\u4e86\u65b0\u7684\u8ffd\u7ebf\u9009\u9879\u3002")
	elif opt_id == "escort":
		world_state["order"] = clamp(int(world_state.get("order", 0)) + 12, 0, 100)
		_push_rumor("\u9547\u53e3\u544a\u793a\u8bf4\u4f60\u534f\u52a9\u62a4\u9001\u4e86\u4f24\u8005\uff0c\u4e00\u6761\u5c0f\u8def\u88ab\u4e34\u65f6\u5f00\u901a\u3002", "struct")
		lines.append("\u4f60\u5b8c\u6210\u4e86\u62a4\u9001\uff0c\u5f53\u5730\u79e9\u5e8f\u597d\u8f6c\u3002")
		lines.append("\u7ed3\u6784\u53d8\u5316\uff1a\u5c0f\u8def\u72b6\u6001\u53d1\u751f\u4e86\u53ef\u89c1\u8c03\u6574\u3002")
	else:
		lines.append("\u4f60\u5b8c\u6210\u4e86\u4e8b\u4ef6\u51b3\u7b56\u3002")
	_add_visible_outcome(lines[0])
	return "\n".join(lines)

func _apply_backlog_choice(choice_id: String) -> Dictionary:
	if choice_id != "sys.v03.backlog.open":
		return _action_result("\u5f85\u529e\u6307\u4ee4\u65e0\u6548\u3002")
	if backlog.is_empty():
		return _action_result("\u5f85\u529e\u5217\u8868\u4e3a\u7a7a\u3002")
	var best_idx: int = 0
	var best_remain: int = 9999
	for i in range(backlog.size()):
		var b: Dictionary = backlog[i]
		var remain: int = max(0, int(b.get("deadline_h", time_hours)) - time_hours)
		if remain < best_remain:
			best_remain = remain
			best_idx = i
	pending_event = backlog[best_idx].duplicate(true)
	backlog.remove_at(best_idx)
	return _action_result("\u5df2\u6062\u590d\u5f85\u529e\u4e8b\u4ef6\uff1a%s" % String(pending_event.get("title", "\u4e8b\u4ef6")))

func _apply_rumor_choice(choice_id: String) -> Dictionary:
	if choice_id != "sys.v03.rumor.open":
		return _action_result("\u4f20\u95fb\u6307\u4ee4\u65e0\u6548\u3002")
	if rumor_feed.is_empty():
		return _action_result("\u6700\u8fd1\u6ca1\u6709\u65b0\u4f20\u95fb\u3002")
	var lines: Array[String] = ["\u6700\u8fd1\u4f20\u95fb\uff1a"]
	for r in rumor_feed.slice(max(0, rumor_feed.size() - 4), rumor_feed.size()):
		lines.append("- " + String(r))
	if not unknown_outcomes.is_empty():
		lines.append("- \u8fd8\u6709\u4e00\u4e9b\u540e\u679c\u6ca1\u6709\u56de\u6d41\u5230\u4f60\u8fd9\u91cc\u3002")
	return _action_result("\n".join(lines))

func _process_expiry() -> void:
	var keep: Array[Dictionary] = []
	for b_any in backlog:
		if not (b_any is Dictionary):
			continue
		var b: Dictionary = b_any as Dictionary
		if time_hours < int(b.get("deadline_h", time_hours + 1)):
			keep.append(b)
		else:
			_apply_expired_outcome(b)
	backlog = keep

func _apply_expired_outcome(item: Dictionary) -> void:
	var title: String = String(item.get("title", "\u4e8b\u4ef6"))
	world_state["danger"] = clamp(int(world_state.get("danger", 0)) + 4, 0, 100)
	var line: String = "\u4f60\u5ef6\u540e\u7684\u300c%s\u300d\u5df2\u81ea\u884c\u6f14\u5316\u3002" % title
	if rng.randf() < 0.28:
		world_state["order"] = clamp(int(world_state.get("order", 0)) - 12, 0, 100)
		line = "\u300c%s\u300d\u8fc7\u671f\u540e\u5f15\u53d1\u4e86\u7ed3\u6784\u53d8\u5316\uff0c\u5f53\u5730\u8def\u7f51\u98ce\u9669\u4e0a\u5347\u3002" % title
	var know: float = rng.randf()
	if know < 0.55:
		var rumor: String = line
		if rng.randf() < 0.2:
			rumor = "\u6709\u4eba\u8bf4\u300c%s\u300d\u7684\u7ed3\u679c\u53ef\u80fd\u548c\u4f20\u8a00\u4e0d\u4e00\u6837\u3002" % title
		_push_rumor(rumor, "expired")
		_add_visible_outcome("\u53ef\u89c1\u56de\u6d41\uff1a" + rumor)
	elif know < 0.8:
		_push_rumor("\u53ea\u542c\u5230\u7247\u6bb5\u6d88\u606f\uff1a\u300c%s\u300d\u597d\u50cf\u6709\u7ed3\u679c\u4e86\u3002" % title, "expired")
	else:
		unknown_outcomes.append("\u4f60\u79bb\u5f00\u5f53\u5730\u540e\u9519\u8fc7\u4e86\u300c%s\u300d\u7684\u7ed3\u5c40\u3002" % title)

func _add_visible_outcome(line: String) -> void:
	if line == "":
		return
	recent_visible_outcomes.append(line)
	if recent_visible_outcomes.size() > 6:
		recent_visible_outcomes.pop_front()

func _push_rumor(text: String, _source: String) -> void:
	if text == "":
		return
	rumor_feed.append(text)
	if rumor_feed.size() > 12:
		rumor_feed.pop_front()

func _pop_rumor_line() -> String:
	if rumor_feed.is_empty():
		return ""
	return "[i]\u4f20\u95fb[/i] " + rumor_feed.pop_front()

func _pick_text(arr: Array[String]) -> String:
	if arr.is_empty():
		return ""
	if arr.size() == 1:
		last_pick_text = arr[0]
		return arr[0]
	var idx: int = rng.randi_range(0, arr.size() - 1)
	if arr[idx] == last_pick_text:
		idx = (idx + 1) % arr.size()
	last_pick_text = arr[idx]
	return arr[idx]

func _time_of_day_label() -> String:
	if time_hours < 6:
		return "\u6df1\u591c"
	if time_hours < 12:
		return "\u767d\u5929"
	if time_hours < 18:
		return "\u4e0b\u5348"
	return "\u591c\u665a"

func _decay_leads_one_hour() -> void:
	var next: Array[Dictionary] = []
	var turned_once: bool = false
	var variant_bases: Array[Dictionary] = []
	for l_any in leads:
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		var fresh: int = int(l.get("freshness", 0))
		var stage: int = int(l.get("stage", 0))
		var dec: int = 6 + stage * 2
		fresh -= dec
		l["freshness"] = max(0, fresh)
		if fresh <= 0:
			lead_feedback_queue.append("\u4e00\u6761\u7ebf\u7d22\u56e0\u957f\u65f6\u95f4\u672a\u5904\u7406\u800c\u6d88\u6563\u4e86\u3002")
			continue
		if fresh < 35 and rng.randf() < 0.30:
			l["risk_hint"] = "\u9ad8\u98ce\u9669"
			l["title_variant"] = int(l.get("title_variant", 0)) + 1
			lead_feedback_queue.append("\u7ebf\u7d22\u53d8\u8d28\uff1a\u5df2\u6709\u75d5\u8ff9\u53d7\u4f53\u5019\u5e72\u6270\uff0c\u98ce\u9669\u4e0a\u5347\u3002")
		if (not turned_once) and fresh < 26 and int(l.get("stage", 0)) <= 2 and rng.randf() < 0.22:
			variant_bases.append(l.duplicate(true))
			turned_once = true
			lead_feedback_queue.append("\u7ebf\u7d22\u8f6c\u5411\uff1a\u539f\u8def\u5f84\u53d8\u5f97\u6df7\u4e71\uff0c\u51fa\u73b0\u4e86\u4e00\u6761\u65b0\u65b9\u5411\u3002")
		next.append(l)
	leads = next
	for b in variant_bases:
		if b is Dictionary:
			_spawn_variant_lead_from(b as Dictionary)

func _advance_time(hours: int) -> void:
	for _i in range(max(1, hours)):
		time_hours += 1
		if time_hours >= 24:
			time_hours = 0
			day += 1
		energy = clamp(energy - 1, 0, energy_max)
		if energy <= 4:
			sanity = clamp(sanity - 1, 0, sanity_max)
		if sanity <= 8:
			hp = clamp(hp - 1, 0, hp_max)
		_decay_leads_one_hour()

func _action_result(text: String) -> Dictionary:
	return {"text": text}
