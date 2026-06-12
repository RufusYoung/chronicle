extends Node
class_name WorldGeneration

const WS_PATH := "/root/_WorldState"
const EQUIP_GEN_PATH := "res://scripts/gen/proc/equipment_generator.gd"
const CREATURE_GEN_PATH := "res://scripts/gen/proc/creature_variant_generator.gd"

# 渚濊禆锛欰utoload 鐨?_Registry锛圧egistry锛夛紝浠ュ強 RegionLoader锛坈lass_name RegionLoader锛?var region_loader: RegionLoader

# 褰撳墠鍖哄煙
var current_region: Dictionary = {}
var current_region_id: String = ""
var current_region_path: String = ""

# 鏃堕棿涓庨殢鏈?var time_hours: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# 澶╂皵鎾姤鑺傛祦
var last_weather_id: String = ""
var weather_cooldown_h: int = 3
var last_weather_broadcast_hour: int = -9999

# 涓栫晫杞婚噺鐘舵€?var flags: Dictionary = {}
var counters: Dictionary = {}
var meters: Dictionary = {}
var chronicle_lines: Array[String] = []

# 瑙掕壊鐢熷瓨鐘舵€侊紙demo 鍙帺鏍稿績锛?var hp_max: int = 120
var hp: int = 120
var sanity_max: int = 100
var sanity: int = 100
var hunger_max: int = 36
var hunger: int = 24
var sleep_max: int = 36
var sleep_energy: int = 28
var cold_max: int = 100
var cold: int = 0
var coin: int = 12
var food_tick_h: int = 0
var ration: int = 10

var equipment_inventory: Array[Dictionary] = []
var creature_codex: Dictionary = {}
var action_cooldowns: Dictionary = {}
var global_arc: Dictionary = {
	"danger": 18,
	"mystic": 15,
	"scarcity": 20,
	"order": 40,
	"war": 12
}
var story_threads: Array[Dictionary] = []
var story_alert_queue: Array[String] = []
var memory_beats: Array[String] = []
var thread_nonce: int = 0
var recent_regular_event_ids: Array[String] = []
var last_regular_event_hour: int = -9999
var module_nonce: int = 0
var module_tickets: Dictionary = {}

var trait_catalog: Dictionary = {}
var thread_templates: Dictionary = {}
var situation_modules: Array[Dictionary] = []
var traits: Dictionary = {}
var impact_tags: Array[String] = []
var echo_log: Array[String] = []
var echo_hooks: Array[Dictionary] = []
var echo_nonce: int = 0
var exposure_tags: Dictionary = {}
var relations: Dictionary = {}
var event_nodes_count: int = 0
var hard_growth_count: int = 0
var small_reward_clock: int = 0
var hard_reward_clock: int = 0
var last_energy_incident_h: int = -9999
var trait_fragments: int = 0
var world_regions: Dictionary = {}
var world_factions: Dictionary = {}
var world_news_queue: Array[String] = []
var world_reaction_queue: Array[Dictionary] = []
var world_reaction_tickets: Dictionary = {}
var world_reaction_nonce: int = 0
var world_reaction_stamp: Dictionary = {}

var equipment_gen: Variant = null
var creature_gen: Variant = null

# 鍏淮灞炴€э紙鍏堜綔涓烘紨绀洪┍鍔級
var stat_str: int = 10
var stat_dex: int = 10
var stat_int: int = 10
var stat_cha: int = 10
var stat_con: int = 10
var stat_wis: int = 10

# 浜嬩欢寰呴€夐」
var _pending_choices: Array[Dictionary] = []
var _has_pending: bool = false

# 鍙欎簨
var last_snippet_line: String = ""

# tone / bias锛堟潵鑷?JSON锛屽彲閫夛級
var region_tone: Dictionary = {}   # {"warm":0.6,"peril":0.4}
var region_bias: Dictionary = {}   # {"time_of_day":{...},"season":{...}}

# v0.1 loop: free-action main loop + event sessions + backlog + rumors
var v01_enabled: bool = true
var v01_turn_count: int = 0
var v01_last_processed_hour: int = 0
var v01_session_nonce: int = 0
var v01_sessions: Dictionary = {}
var v01_backlog_ids: Array[String] = []
var v01_backlog_pinned: Array[String] = []
var v01_active_locked_id: String = ""
var v01_rumor_queue: Array[Dictionary] = []
var v01_rumor_history: Array[String] = []
var v01_unknown_notice_queue: Array[String] = []
var v01_recent_fingerprint_hour: Dictionary = {}
var v01_guidance_due: bool = true
var v01_region_threads: Dictionary = {}
var v01_thread_nonce: int = 0
var v01_turns_since_weird: int = 0
var v01_metrics: Dictionary = {
	"segment_free_total": 0,
	"segment_free_negative_or_backlash": 0,
	"segment_free_structural": 0,
	"segment_free_info_or_opportunity": 0,
	"ignored_total": 0,
	"ignored_visible_impact": 0,
	"weird_option_seen": 0
}

# v0.2 final: action board + objectified actions + micro sessions + lead loop
var v02_enabled: bool = true
var v02_turn_count: int = 0
var v02_guidance_due: bool = true
var v02_last_guidance_hour: int = -9999
var v02_micro_nonce: int = 0
var v02_lead_nonce: int = 0
var v02_active_micro_id: String = ""
var v02_micro_sessions: Dictionary = {}
var v02_leads: Array[Dictionary] = []
var v02_last_micro_fingerprint_h: Dictionary = {}
var v02_goal_reminders: Array[Dictionary] = []
var v02_recent_visible_outcomes: Array[String] = []
var v02_metrics: Dictionary = {
	"micro_total": 0,
	"micro_with_backlash": 0,
	"micro_with_structural": 0,
	"micro_with_info_or_opportunity": 0,
	"lead_generated": 0,
	"lead_consumed": 0,
	"track_repeat_prevented": 0
}

func _ready() -> void:
	rng.randomize()
	_ensure_loader()
	_init_generators()
	_init_content_tables()
	_sync_shared_state()

func _init_generators() -> void:
	var eq_script := load(EQUIP_GEN_PATH)
	if eq_script != null:
		equipment_gen = eq_script.new()
	var cv_script := load(CREATURE_GEN_PATH)
	if cv_script != null:
		creature_gen = cv_script.new()

func _init_content_tables() -> void:
	trait_catalog = {
		"trait.hunter_mark": {"name":"鐚庢墜鏍囪", "bias_tags":["wild","predator"], "unlock":"棰勫垽浼忓嚮", "fail_shift":"鐙╃寧澶辫触淇濈暀鍗婃暟绾跨储"},
		"trait.echo_resonance": {"name":"鍥炲０鍏遍福", "bias_tags":["echo","ruin"], "unlock":"杩介棶鐪熺浉", "fail_shift":"绁炵澶辫触浠嶄繚鐣欓挜鍖?},
		"trait.supply_route": {"name":"琛ョ粰璺暟", "bias_tags":["supply","town"], "unlock":"鏇夸唬閰嶇粰", "fail_shift":"琛ョ粰澶辫触涓嶅弻鎵ｈ祫婧?},
		"trait.grey_contacts": {"name":"鐏板競浜鸿剦", "bias_tags":["town","faction"], "unlock":"璧婅处浜ゆ槗", "fail_shift":"浜ゆ槗澶辫触鏀瑰€哄姟"},
		"trait.track_reading": {"name":"鑴氬嵃瑙ｈ", "bias_tags":["wild","trail"], "unlock":"杩借釜鍒嗗弶", "fail_shift":"鎺㈢储澶辫触涔熸毚闇插嵄闄?},
		"trait.break_negotiation": {"name":"鐮村眬璋堝垽", "bias_tags":["faction","town"], "unlock":"鍘嬩环鍋滅伀", "fail_shift":"璋堝垽澶辫触鏀逛负鍘嬪姏涓婂崌"},
		"trait.calm_layers": {"name":"鍐烽潤鍒嗗眰", "bias_tags":["echo","survival"], "unlock":"寤舵椂鍐崇瓥", "fail_shift":"鑷村懡澶辫鏀归敊澶辨満浼?},
		"trait.rust_crafter": {"name":"閿堣殌宸ュ尃", "bias_tags":["relic","supply"], "unlock":"涓存敼璇嶇紑", "fail_shift":"瑁呭鍓綔鐢ㄥ噺鍗?},
		"trait.headwind_march": {"name":"閫嗛琛屽啗", "bias_tags":["wild","war"], "unlock":"鍘嬬嚎鎺ㄨ繘", "fail_shift":"澶辫触淇濈暀绾跨▼杩涘害"},
		"trait.debt_favor": {"name":"鍊哄姟浜烘儏", "bias_tags":["town","faction"], "unlock":"鍏堟嬁鍚庝粯", "fail_shift":"鐮翠骇鏀瑰叧绯昏礋鍊?},
		"trait.terrain_memory": {"name":"鍦板舰璁板繂", "bias_tags":["ruin","water","wild"], "unlock":"鏀归亾鏆撮湶", "fail_shift":"缁曡浠嶄繚鐣欐満浼?},
		"trait.ember_will": {"name":"浣欑儸鎰忓織", "bias_tags":["war","survival"], "unlock":"婵掑嵄鍙嶆墦", "fail_shift":"涓€娆¤嚧鍛芥敼閲嶄激"}
	}

	thread_templates = {
		"predator": {"title":"鐚庤釜鎵╂暎", "tags":["wild","predator"], "reward_trait":"trait.hunter_mark", "echo":"浣犲湪鐚庣嚎涓婄殑鍚嶅０琚紶鎾€?},
		"echo": {"title":"鍥炲０瑁傞殭", "tags":["echo","ruin"], "reward_trait":"trait.echo_resonance", "echo":"鍥炲０鐐瑰紑濮嬪浣犲憟鐜扮ǔ瀹氱獥鍙ｃ€?},
		"scarcity": {"title":"鏂緵璧板粖", "tags":["supply","town"], "reward_trait":"trait.supply_route", "echo":"琛ョ粰绾胯浣忎簡浣犵殑澶勭悊鏂瑰紡銆?},
		"faction": {"title":"杈瑰缂夋崟", "tags":["faction","town"], "reward_trait":"trait.grey_contacts", "echo":"杈瑰鍔垮姏瀵逛綘鐨勮瘑鍒閲嶅啓銆?},
		"relic": {"title":"閬楄抗浜夊ず", "tags":["ruin","war"], "reward_trait":"trait.terrain_memory", "echo":"閬楄抗鐘舵€佸洜浣犵殑閫夋嫨鏀瑰彉銆?},
		"patrol": {"title":"宸＄伅姹傛彺", "tags":["patrol","wild"], "reward_trait":"trait.break_negotiation", "echo":"宸＄伅浜轰細鍦ㄥ悗缁簨浠朵腑鍥炲簲浣犮€?}
	}

	situation_modules = [
		_make_module("sm01", "{place}鐨勫贰鐏汉鎷︿綇浣犺姹傚崗鍔┿€?, "survival", ["faction","wild","patrol"], {"tension_max": 55}, _module_options("survival", 1, 2, 1, 68, 44)),
		_make_module("sm02", "{place}鍏ュ彛琚檶鐢熷皬闃熷崰鎹€?, "negotiation", ["ruin","faction","town"], {"tension_min": 20}, _module_options("negotiation", 1, 2, 1, 64, 42)),
		_make_module("sm03", "{water}鍑虹幇姹℃煋锛岃ˉ缁欏嚭鐜板垎姝с€?, "survival", ["water","supply","wild"], {"scarcity_min": 28}, _module_options("survival", 1, 2, 1, 66, 40)),
		_make_module("sm04", "{place}澶滃箷涓嬩紶鏉ラ噸澶嶈剼姝ャ€?, "stealth", ["wild","predator","night"], {"danger_min": 24}, _module_options("stealth", 1, 2, 1, 62, 39)),
		_make_module("sm05", "{town}杈圭紭鏈変汉鍏滃敭绂佸繉鎯呮姤銆?, "negotiation", ["town","faction","echo"], {"order_min": 10}, _module_options("negotiation", 1, 1, 0, 70, 43)),
		_make_module("sm06", "{place}鏂ˉ涓嬮湶鍑哄皝瀛樿ˉ缁欑銆?, "explore", ["wild","supply","water"], {"tension_max": 70}, _module_options("explore", 1, 2, 1, 65, 41)),
		_make_module("sm07", "{echo_site}鍑虹幇寤惰繜褰卞儚銆?, "explore", ["echo","ruin","mystic"], {"mystic_min": 24}, _module_options("explore", 1, 1, 0, 60, 37)),
		_make_module("sm08", "{faction_name}宸￠€婚槦瑕佹眰鏍搁獙銆?, "negotiation", ["faction","town","war"], {"war_min": 18}, _module_options("negotiation", 1, 1, 1, 67, 42)),
		_make_module("sm09", "{place}搴熻惀鍦版畫鐏湭鐔勩€?, "explore", ["wild","trail","faction"], {"tension_min": 12}, _module_options("explore", 1, 2, 0, 66, 43)),
		_make_module("sm10", "{town}鍟嗛槦鍦ㄩ鏆村墠璇锋眰鎶ら€併€?, "survival", ["town","supply","patrol"], {"scarcity_min": 22}, _module_options("survival", 2, 4, 1, 69, 45)),
		_make_module("sm11", "{place}灞卞彛鍑虹幇濉屾柟棰勫厗銆?, "survival", ["wild","war","trail"], {"danger_min": 34}, _module_options("survival", 1, 1, 1, 64, 39)),
		_make_module("sm12", "{patrol_mark}鏃у鍗囪捣淇″彿鐏€?, "explore", ["patrol","faction","wild"], {"thread_kind":"patrol"}, _module_options("explore", 1, 2, 0, 63, 40)),
		_make_module("sm13", "{place}鍑虹幇閲嶅璺爣銆?, "explore", ["echo","trail","wild"], {"mystic_min": 30}, _module_options("explore", 1, 2, 1, 61, 38)),
		_make_module("sm14", "{predator_name}鐚庣墿鏃佸嚭鐜伴潪鏈湴瓒宠抗銆?, "combat", ["predator","wild","trail"], {"thread_kind":"predator"}, _module_options("combat", 1, 2, 0, 65, 40)),
		_make_module("sm15", "{town}璺彛鍑虹幇鍊轰富涓棿浜恒€?, "negotiation", ["town","faction","supply"], {"relation_or_debt": true}, _module_options("negotiation", 1, 2, 1, 68, 43)),
		_make_module("sm16", "闆ㄥ閲屼綘鐨勮澶囧壇浣滅敤绐佺劧鍙戜綔銆?, "survival", ["relic","echo","supply"], {"needs_equipment": true}, _module_options("survival", 1, 1, 0, 66, 37)),
		_make_module("sm17", "{town}鍩庨棬璐村嚭鏂扮殑鎮祻浠ゃ€?, "negotiation", ["town","war","faction"], {"war_min": 26}, _module_options("negotiation", 1, 1, 1, 67, 41)),
		_make_module("sm18", "{water}娴呮哗鎸栧嚭灏佽湣淇＄瓛銆?, "explore", ["water","town","faction"], {"tension_max": 75}, _module_options("explore", 1, 1, 0, 71, 44)),
		_make_module("sm19", "{place}鍧￠亾涓婁綘鍑虹幇鏄庢樉閫忔敮寰佸厗銆?, "survival", ["survival","trail","wild"], {"energy_max": 18}, _module_options("survival", 1, 1, 1, 74, 49)),
		_make_module("sm20", "{war_site}浼犳潵浜屾闆嗙粨鍙枫€?, "combat", ["war","faction","ruin"], {"war_min": 34, "tension_min": 34}, _module_options("combat", 2, 2, 0, 62, 36))
	]

func _make_module(id: String, intro: String, conflict: String, tags: Array, gate: Dictionary, options: Array[Dictionary]) -> Dictionary:
	return {
		"id": id,
		"intro": intro,
		"conflict": conflict,
		"tags": tags,
		"gate": gate,
		"options": options
	}

func _module_options(conflict: String, steady_h: int, gamble_h: int, retreat_h: int, steady_success: int, gamble_success: int) -> Array[Dictionary]:
	var steady_label: String = "绋虫€佸鐞?
	var gamble_label: String = "鎶兼敞绐佺牬"
	var retreat_label: String = "姝㈡崯杞繘"
	match conflict:
		"negotiation":
			steady_label = "浜ゆ秹澶囨"
			gamble_label = "鏂藉帇鍗氬紙"
			retreat_label = "鏆傞伩鏀归亾"
		"combat":
			steady_label = "甯冮槻璇曟帰"
			gamble_label = "寮鸿澶哄娍"
			retreat_label = "鑴辩浜ゆ垬"
		"stealth":
			steady_label = "娼滆缁曡繃"
			gamble_label = "鍙嶅悜鍩嬩紡"
			retreat_label = "涓㈤サ鑴辩"
		"explore":
			steady_label = "璋ㄦ厧鍕樻煡"
			gamble_label = "娣卞叆鍐掓帰"
			retreat_label = "鏍囪鎾ょ"
		"survival":
			steady_label = "鍏堢ǔ鐘舵€?
			gamble_label = "鍘嬬嚎纭棷"
			retreat_label = "鍋滄崯鍚庢挙"
		_:
			pass
	return [
		{"id":"steady", "label":steady_label, "risk":"浣?, "reward":"涓?, "cost_h": steady_h, "energy_cost": 1, "success_base": steady_success},
		{"id":"gamble", "label":gamble_label, "risk":"楂?, "reward":"楂?, "cost_h": gamble_h, "energy_cost": 2, "success_base": gamble_success},
		{"id":"retreat", "label":retreat_label, "risk":"浣?, "reward":"淇濆簳", "cost_h": retreat_h, "energy_cost": 0, "success_base": 100}
	]

func _ws() -> WorldState:
	return get_node_or_null(WS_PATH) as WorldState

func _ensure_loader() -> void:
	if region_loader != null and is_instance_valid(region_loader):
		return
	region_loader = RegionLoader.new()
	add_child(region_loader)

func _current_day() -> int:
	return 1 + int(time_hours / 24)

func _current_hour() -> int:
	return time_hours % 24

func _sync_shared_state() -> void:
	var ws: WorldState = _ws()
	if ws == null:
		return
	ws.day = _current_day()
	ws.hour = _current_hour()
	ws.time_of_day = _time_of_day_name()
	ws.weather_tag = last_weather_id
	ws.current_region_path = current_region_path
	ws.current_region_id = current_region_id
	ws.flags = flags.duplicate(true)
	ws.counters = counters.duplicate(true)
	var merged_meters: Dictionary = meters.duplicate(true)
	merged_meters["hp"] = hp
	merged_meters["sanity"] = sanity
	merged_meters["hunger"] = hunger
	merged_meters["sleep"] = sleep_energy
	merged_meters["energy"] = _energy_value()
	merged_meters["food"] = hunger
	merged_meters["fatigue"] = max(0, sleep_max - sleep_energy)
	merged_meters["cold"] = cold
	merged_meters["ration"] = ration
	ws.meters = merged_meters
	ws.inventory = {
		"ration": ration,
		"coin": coin
	}
	ws.counters["v01_backlog_count"] = v01_backlog_ids.size()
	ws.counters["v01_rumor_pending"] = v01_rumor_queue.size()
	ws.counters["v01_locked_active"] = 1 if v01_active_locked_id != "" else 0
	ws.facts["v01_turn"] = v01_turn_count
	ws.counters["v02_lead_count"] = v02_leads.size()
	ws.counters["v02_micro_active"] = 1 if v02_active_micro_id != "" else 0
	ws.facts["v02_turn"] = v02_turn_count
	ws.counters["traits_count"] = traits.size()
	ws.counters["hard_growth_count"] = hard_growth_count
	ws.counters["event_nodes_count"] = event_nodes_count
	ws.facts["world_region_count"] = world_regions.size()
	ws.facts["world_faction_count"] = world_factions.size()
	ws.facts["world_war_heat"] = int(global_arc.get("war", 0))
	ws.facts["world_scarcity"] = int(global_arc.get("scarcity", 0))
	ws.facts["world_order"] = int(global_arc.get("order", 0))
	ws.journey_marks = [
		"origin.wanderer",
		"region.%s" % current_region_id
	]
	ws.last_snippet_line = last_snippet_line

func _decorate_snapshot(snap: Dictionary) -> Dictionary:
	snap["day"] = _current_day()
	snap["hour"] = _current_hour()
	snap["time_of_day"] = _time_of_day_name()
	snap["region_id"] = current_region_id
	snap["turn"] = v01_turn_count
	snap["backlog_count"] = v01_backlog_ids.size()
	snap["locked_session_active"] = v01_active_locked_id != ""
	snap["v02_turn"] = v02_turn_count
	snap["v02_lead_count"] = v02_leads.size()
	snap["v02_active_micro"] = v02_active_micro_id != ""
	_sync_shared_state()
	return snap

# ========== 鍚姩鎸囧畾鍖哄煙 ==========
func bootstrap(path_to_region_json: String, reset_time: bool=false) -> void:
	_ensure_loader()

	if reset_time:
		rng.randomize()
		time_hours = 0
		flags.clear()
		counters.clear()
		meters.clear()
		chronicle_lines.clear()
		_reset_player_state()

	current_region_path = path_to_region_json
	var region: Dictionary = region_loader.load_region_from_path(path_to_region_json)
	if region.is_empty():
		push_error("[GameGameWorldGeneration] bootstrap 澶辫触: 绌哄尯鍩?%s" % path_to_region_json)
		current_region = {}
		current_region_id = ""
		return

	current_region = region
	current_region_id = String(region.get("id", path_to_region_json.get_file().get_basename()))
	last_weather_id = ""
	last_weather_broadcast_hour = -9999
	last_snippet_line = ""

	_pending_choices.clear()
	_has_pending = false

	region_tone = {}
	if current_region.has("tone") and current_region.get("tone") is Dictionary:
		region_tone = current_region.get("tone") as Dictionary
	region_bias = {}
	if current_region.has("bias") and current_region.get("bias") is Dictionary:
		region_bias = current_region.get("bias") as Dictionary

	_ensure_world_sim_init()
	_set_flag("entered_" + current_region_id, true)

	if current_region_id == "region.silence.forest":
		_set_flag("in_silence", true)

	var starter_key: String = "starter_fired_" + current_region_id
	if not flags.has(starter_key):
		_set_flag(starter_key, false)

	if v01_enabled:
		_v01_after_bootstrap(reset_time)
	if v02_enabled:
		_v02_after_bootstrap(reset_time)

	_sync_shared_state()

func _reset_player_state() -> void:
	hp_max = 120
	hp = hp_max
	sanity_max = 100
	sanity = sanity_max
	hunger_max = 36
	hunger = 24
	sleep_max = 36
	sleep_energy = 28
	cold_max = 100
	cold = 0
	coin = 12
	food_tick_h = 0
	ration = 10
	equipment_inventory.clear()
	creature_codex.clear()
	action_cooldowns.clear()
	story_threads.clear()
	story_alert_queue.clear()
	memory_beats.clear()
	thread_nonce = 0
	recent_regular_event_ids.clear()
	last_regular_event_hour = -9999
	module_nonce = 0
	module_tickets.clear()
	traits.clear()
	impact_tags.clear()
	echo_log.clear()
	echo_hooks.clear()
	echo_nonce = 0
	exposure_tags.clear()
	relations.clear()
	event_nodes_count = 0
	hard_growth_count = 0
	small_reward_clock = 0
	hard_reward_clock = 0
	last_energy_incident_h = -9999
	trait_fragments = 0
	world_regions.clear()
	world_factions.clear()
	world_news_queue.clear()
	world_reaction_queue.clear()
	world_reaction_tickets.clear()
	world_reaction_nonce = 0
	world_reaction_stamp.clear()
	global_arc = {
		"danger": 18,
		"mystic": 15,
		"scarcity": 20,
		"order": 40,
		"war": 12
	}
	stat_str = 10
	stat_dex = 10
	stat_int = 10
	stat_cha = 10
	stat_con = 10
	stat_wis = 10
	if v01_enabled:
		_v01_reset_runtime()
	if v02_enabled:
		_v02_reset_runtime()

func _ensure_world_sim_init() -> void:
	if world_factions.is_empty():
		_world_bootstrap_factions()
	if not world_regions.is_empty() and (current_region_id == "" or world_regions.has(current_region_id)):
		_world_sync_global_arc()
		return

	var entries: Array[Dictionary] = _world_region_entries()
	if entries.is_empty() and current_region_id != "":
		entries.append({"id": current_region_id, "path": current_region_path})

	for ent in entries:
		var rid: String = String(ent.get("id", ""))
		var path: String = String(ent.get("path", ""))
		if rid == "":
			continue
		if world_regions.has(rid):
			continue
		var tags: Array[String] = _world_infer_tags(rid, path)
		var neighbors: Array[String] = _world_load_neighbors(path)
		var controller: String = _world_pick_controller(tags)
		var region_data: Dictionary = {
			"id": rid,
			"name": String(ent.get("name", rid)),
			"path": path,
			"tags": tags,
			"neighbors": neighbors,
			"controller": controller,
			"food": rng.randi_range(36, 68),
			"wood": rng.randi_range(30, 74),
			"water": rng.randi_range(34, 72),
			"flora": rng.randi_range(40, 78),
			"fauna": rng.randi_range(34, 70),
			"pollution": rng.randi_range(8, 24),
			"hazard": rng.randi_range(16, 38),
			"conflict": rng.randi_range(10, 30),
			"mystic": rng.randi_range(12, 46)
		}
		if "echo" in tags:
			region_data["mystic"] = _clamp_int(int(region_data.get("mystic", 25)) + 12, 0, 100)
		if "water" in tags:
			region_data["water"] = _clamp_int(int(region_data.get("water", 50)) + 10, 0, 100)
		if "town" in tags:
			region_data["wood"] = _clamp_int(int(region_data.get("wood", 50)) - 8, 0, 100)
		world_regions[rid] = region_data

	if current_region_id != "" and not world_regions.has(current_region_id):
		world_regions[current_region_id] = {
			"id": current_region_id,
			"name": String(current_region.get("name", current_region_id)),
			"path": current_region_path,
			"tags": _world_infer_tags(current_region_id, current_region_path),
			"neighbors": [],
			"controller": "faction_patrol",
			"food": 52,
			"wood": 46,
			"water": 48,
			"flora": 56,
			"fauna": 50,
			"pollution": 14,
			"hazard": 24,
			"conflict": 20,
			"mystic": 28
		}

	_world_rebuild_territories()
	_world_sync_global_arc()

func _world_bootstrap_factions() -> void:
	world_factions = {
		"faction_patrol": {
			"id": "faction_patrol",
			"name": "宸＄伅闃?,
			"power": 58,
			"economy": 44,
			"aggression": 38,
			"legitimacy": 62,
			"relations": {
				"faction_grey_market": -12,
				"faction_scavengers": -22,
				"faction_echo_cult": -30
			},
			"territory": []
		},
		"faction_grey_market": {
			"id": "faction_grey_market",
			"name": "鐏板競璺戠嚎鍟?,
			"power": 43,
			"economy": 61,
			"aggression": 33,
			"legitimacy": 34,
			"relations": {
				"faction_patrol": -12,
				"faction_scavengers": 16,
				"faction_echo_cult": -8
			},
			"territory": []
		},
		"faction_scavengers": {
			"id": "faction_scavengers",
			"name": "鎷捐崚缇よ惤",
			"power": 47,
			"economy": 37,
			"aggression": 49,
			"legitimacy": 27,
			"relations": {
				"faction_patrol": -22,
				"faction_grey_market": 16,
				"faction_echo_cult": -18
			},
			"territory": []
		},
		"faction_echo_cult": {
			"id": "faction_echo_cult",
			"name": "鍥炲０鏁欏洟",
			"power": 39,
			"economy": 32,
			"aggression": 42,
			"legitimacy": 21,
			"relations": {
				"faction_patrol": -30,
				"faction_grey_market": -8,
				"faction_scavengers": -18
			},
			"territory": []
		}
	}

func _world_region_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var idx_text: String = JsonUtil.read_text("res://data/regions/region_index.json")
	if idx_text == "":
		return out
	var root_any: Variant = JsonUtil.parse_any(idx_text)
	if not (root_any is Dictionary):
		return out
	var root: Dictionary = root_any as Dictionary
	var regions_any: Variant = root.get("regions", [])
	if regions_any is Dictionary:
		var mp: Dictionary = regions_any as Dictionary
		for k_any in mp.keys():
			var rid: String = String(k_any)
			var path: String = String(mp.get(rid, ""))
			out.append({"id": rid, "path": path, "name": rid})
		return out
	if regions_any is Array:
		for it_any in (regions_any as Array):
			if not (it_any is Dictionary):
				continue
			var it: Dictionary = it_any as Dictionary
			var rid2: String = String(it.get("id", ""))
			if rid2 == "":
				continue
			var path2: String = String(it.get("path", ""))
			var nm: String = rid2
			if path2 != "":
				var rg: Dictionary = region_loader.load_region_from_path(path2)
				if not rg.is_empty():
					nm = String(rg.get("name", rid2))
			out.append({"id": rid2, "path": path2, "name": nm})
	return out

func _world_infer_tags(rid: String, path: String) -> Array[String]:
	var raw: String = (rid + " " + path).to_lower()
	var tags: Array[String] = []
	if "forest" in raw or "妫? in rid:
		tags.append("wild")
	if "lake" in raw or "water" in raw or "婀? in rid:
		tags.append("water")
	if "town" in raw or "market" in raw or "鍩? in rid:
		tags.append("town")
	if "ruin" in raw or "閬? in rid:
		tags.append("ruin")
	if "silence" in raw or "echo" in raw or "鍥炲搷" in path:
		tags.append("echo")
	if tags.is_empty():
		tags.append("wild")
	return tags

func _world_load_neighbors(path: String) -> Array[String]:
	var out: Array[String] = []
	if path == "":
		return out
	var rg: Dictionary = region_loader.load_region_from_path(path)
	if rg.is_empty():
		return out
	var edges_any: Variant = rg.get("edges", [])
	if edges_any is Array:
		for e_any in (edges_any as Array):
			if not (e_any is Dictionary):
				continue
			var e: Dictionary = e_any as Dictionary
			var to_id: String = String(e.get("to", ""))
			if to_id != "" and not out.has(to_id):
				out.append(to_id)
	return out

func _world_pick_controller(tags: Array[String]) -> String:
	if "echo" in tags and rng.randf() < 0.55:
		return "faction_echo_cult"
	if "town" in tags and rng.randf() < 0.62:
		return "faction_grey_market"
	if "wild" in tags and rng.randf() < 0.46:
		return "faction_scavengers"
	return "faction_patrol"

func _world_rebuild_territories() -> void:
	for fid_any in world_factions.keys():
		var fid: String = String(fid_any)
		var f_any: Variant = world_factions.get(fid, {})
		if not (f_any is Dictionary):
			continue
		var f: Dictionary = f_any as Dictionary
		f["territory"] = []
		world_factions[fid] = f
	for rid_any in world_regions.keys():
		var rid: String = String(rid_any)
		var r_any: Variant = world_regions.get(rid, {})
		if not (r_any is Dictionary):
			continue
		var r: Dictionary = r_any as Dictionary
		var ctrl: String = String(r.get("controller", ""))
		if ctrl == "" or not world_factions.has(ctrl):
			continue
		var f2_any: Variant = world_factions.get(ctrl, {})
		if not (f2_any is Dictionary):
			continue
		var f2: Dictionary = f2_any as Dictionary
		var tr_any: Variant = f2.get("territory", [])
		var tr: Array = tr_any as Array if tr_any is Array else []
		if not tr.has(rid):
			tr.append(rid)
		f2["territory"] = tr
		world_factions[ctrl] = f2

func _world_current_region() -> Dictionary:
	if current_region_id == "" or not world_regions.has(current_region_id):
		return {}
	var r_any: Variant = world_regions.get(current_region_id, {})
	return r_any as Dictionary if r_any is Dictionary else {}

func _world_set_region(rid: String, r: Dictionary) -> void:
	if rid == "":
		return
	world_regions[rid] = r

func _world_set_faction(fid: String, f: Dictionary) -> void:
	if fid == "":
		return
	world_factions[fid] = f

func _world_tick_hour() -> void:
	if world_regions.is_empty():
		return
	_add_counter("world_tick_h", 1)
	var h: int = _get_counter("world_tick_h")
	if h % 2 == 0:
		_world_evolve_regions()
	if h % 6 == 0:
		_world_evolve_factions()
		_world_maybe_queue_reactions()
	_world_sync_global_arc()

func _world_evolve_regions() -> void:
	var keys: Array = world_regions.keys()
	for rid_any in keys:
		var rid: String = String(rid_any)
		var r_any: Variant = world_regions.get(rid, {})
		if not (r_any is Dictionary):
			continue
		var r: Dictionary = r_any as Dictionary
		var ctrl: String = String(r.get("controller", "faction_patrol"))
		var f_any: Variant = world_factions.get(ctrl, {})
		var f: Dictionary = f_any as Dictionary if f_any is Dictionary else {}
		var econ: int = int(f.get("economy", 45))
		var aggression: int = int(f.get("aggression", 35))
		var food: int = int(r.get("food", 50))
		var wood: int = int(r.get("wood", 50))
		var water: int = int(r.get("water", 50))
		var flora: int = int(r.get("flora", 50))
		var fauna: int = int(r.get("fauna", 50))
		var pollution: int = int(r.get("pollution", 12))
		var hazard: int = int(r.get("hazard", 24))
		var conflict: int = int(r.get("conflict", 20))
		var mystic: int = int(r.get("mystic", 20))
		var tags_any: Variant = r.get("tags", [])
		var tags: Array = tags_any as Array if tags_any is Array else []

		var extraction: int = 1
		if econ < 40:
			extraction += 1
		if int(global_arc.get("scarcity", 20)) > 55:
			extraction += 1
		if conflict > 50 or aggression > 55:
			extraction += 1

		food += int(flora / 42) + rng.randi_range(-1, 1) - extraction
		wood += int(flora / 55) + rng.randi_range(0, 1) - int(conflict / 70)
		water += 1 + rng.randi_range(-1, 1) - int(pollution / 45) - int(conflict / 85)
		flora += int(water / 65) + rng.randi_range(-1, 1) - int(extraction / 2) - int(conflict / 68)
		fauna += int(flora / 70) + rng.randi_range(-1, 1) - int(hazard / 52) - int(conflict / 64)
		pollution += int(extraction / 2) + int(conflict / 36) - int(flora / 78)
		hazard += int(conflict / 34) + int(pollution / 46) - int(flora / 72)
		conflict += int(_world_neighbor_hostility(rid, ctrl) / 24.0) + rng.randi_range(-1, 2) + int(global_arc.get("war", 12) / 70)
		mystic += rng.randi_range(-1, 1) + (1 if "echo" in tags else 0) - int(conflict / 80)

		if food < 16 or water < 16:
			conflict += 1
		if flora > 70 and fauna > 66:
			hazard -= 1
			pollution -= 1

		r["food"] = _clamp_int(food, 0, 100)
		r["wood"] = _clamp_int(wood, 0, 100)
		r["water"] = _clamp_int(water, 0, 100)
		r["flora"] = _clamp_int(flora, 0, 100)
		r["fauna"] = _clamp_int(fauna, 0, 100)
		r["pollution"] = _clamp_int(pollution, 0, 100)
		r["hazard"] = _clamp_int(hazard, 0, 100)
		r["conflict"] = _clamp_int(conflict, 0, 100)
		r["mystic"] = _clamp_int(mystic, 0, 100)
		world_regions[rid] = r

func _world_neighbor_hostility(rid: String, controller: String) -> int:
	if rid == "" or controller == "" or not world_regions.has(rid):
		return 0
	var r_any: Variant = world_regions.get(rid, {})
	if not (r_any is Dictionary):
		return 0
	var r: Dictionary = r_any as Dictionary
	var n_any: Variant = r.get("neighbors", [])
	if not (n_any is Array):
		return 0
	var neighbors: Array = n_any as Array
	var score: int = 0
	for nb_any in neighbors:
		var nb: String = String(nb_any)
		if nb == "" or not world_regions.has(nb):
			continue
		var nr_any: Variant = world_regions.get(nb, {})
		if not (nr_any is Dictionary):
			continue
		var nr: Dictionary = nr_any as Dictionary
		var nc: String = String(nr.get("controller", ""))
		if nc == "" or nc == controller:
			continue
		var f_any: Variant = world_factions.get(controller, {})
		if not (f_any is Dictionary):
			continue
		var f: Dictionary = f_any as Dictionary
		var rels_any: Variant = f.get("relations", {})
		var rels: Dictionary = rels_any as Dictionary if rels_any is Dictionary else {}
		score += max(0, -int(rels.get(nc, -20)))
	return score

func _world_evolve_factions() -> void:
	_world_rebuild_territories()
	var avg_scarcity: int = int(global_arc.get("scarcity", 20))
	var keys: Array = world_factions.keys()
	for fid_any in keys:
		var fid: String = String(fid_any)
		var f_any: Variant = world_factions.get(fid, {})
		if not (f_any is Dictionary):
			continue
		var f: Dictionary = f_any as Dictionary
		var territory_any: Variant = f.get("territory", [])
		var territory: Array = territory_any as Array if territory_any is Array else []
		var t_count: int = max(1, territory.size())
		var res_acc: float = 0.0
		var conflict_acc: float = 0.0
		for rid_any in territory:
			var rid: String = String(rid_any)
			var r_any: Variant = world_regions.get(rid, {})
			if not (r_any is Dictionary):
				continue
			var r: Dictionary = r_any as Dictionary
			res_acc += float(int(r.get("food", 50)) + int(r.get("wood", 50)) + int(r.get("water", 50))) / 3.0
			conflict_acc += float(r.get("conflict", 20))
		var avg_res: float = res_acc / float(t_count)
		var avg_conflict: float = conflict_acc / float(t_count)
		var economy: int = int(f.get("economy", 40))
		var power: int = int(f.get("power", 40))
		var aggression: int = int(f.get("aggression", 40))
		var legitimacy: int = int(f.get("legitimacy", 40))
		var war_cost: int = int(avg_conflict / 24.0) + int(aggression / 34.0)
		var income: int = int(avg_res / 16.0) + int(t_count / 2)
		economy += income - war_cost + rng.randi_range(-1, 1)
		power += int(economy / 36.0) + int(t_count / 3) - int(war_cost / 2)
		legitimacy += int((60.0 - avg_conflict) / 18.0) - int(aggression / 42.0)
		aggression += rng.randi_range(-2, 2) + (1 if avg_scarcity > 55 else 0) - (1 if economy > 64 else 0)
		f["economy"] = _clamp_int(economy, 5, 100)
		f["power"] = _clamp_int(power, 5, 100)
		f["aggression"] = _clamp_int(aggression, 5, 100)
		f["legitimacy"] = _clamp_int(legitimacy, 0, 100)
		world_factions[fid] = f

	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: String = String(keys[i])
			var b: String = String(keys[j])
			var fa_any: Variant = world_factions.get(a, {})
			var fb_any: Variant = world_factions.get(b, {})
			if not (fa_any is Dictionary) or not (fb_any is Dictionary):
				continue
			var fa: Dictionary = fa_any as Dictionary
			var fb: Dictionary = fb_any as Dictionary
			var rel_a_any: Variant = fa.get("relations", {})
			var rel_b_any: Variant = fb.get("relations", {})
			var rel_a: Dictionary = rel_a_any as Dictionary if rel_a_any is Dictionary else {}
			var rel_b: Dictionary = rel_b_any as Dictionary if rel_b_any is Dictionary else {}
			var cur: int = int(rel_a.get(b, -12))
			var drift: int = rng.randi_range(-2, 2)
			drift -= int((int(fa.get("aggression", 40)) + int(fb.get("aggression", 40))) / 95.0)
			if avg_scarcity > 65:
				drift -= 1
			if int(fa.get("economy", 40)) > 68 and int(fb.get("economy", 40)) > 68:
				drift += 1
			cur = _clamp_int(cur + drift, -100, 100)
			rel_a[b] = cur
			rel_b[a] = cur
			fa["relations"] = rel_a
			fb["relations"] = rel_b
			world_factions[a] = fa
			world_factions[b] = fb
			if cur <= -72 and rng.randf() < 0.16:
				_world_try_conflict_shift(a, b, cur)
			elif cur >= 70 and rng.randf() < 0.10:
				_world_queue_news("涓栫晫鎬佸娍锛?s 涓?%s 褰㈡垚浜嗙煭鏈熶簰鎯犮€?
					% [String(fa.get("name", a)), String(fb.get("name", b))])

func _world_try_conflict_shift(a: String, b: String, rel: int) -> void:
	var rid: String = _world_pick_border_region(a, b)
	if rid == "":
		return
	var r_any: Variant = world_regions.get(rid, {})
	if not (r_any is Dictionary):
		return
	var r: Dictionary = r_any as Dictionary
	r["conflict"] = _clamp_int(int(r.get("conflict", 20)) + rng.randi_range(10, 18), 0, 100)
	r["hazard"] = _clamp_int(int(r.get("hazard", 20)) + rng.randi_range(5, 11), 0, 100)
	if rng.randf() < 0.28:
		var fa_any: Variant = world_factions.get(a, {})
		var fb_any: Variant = world_factions.get(b, {})
		var fa: Dictionary = fa_any as Dictionary if fa_any is Dictionary else {}
		var fb: Dictionary = fb_any as Dictionary if fb_any is Dictionary else {}
		var pa: int = int(fa.get("power", 40))
		var pb: int = int(fb.get("power", 40))
		r["controller"] = a if pa >= pb else b
	world_regions[rid] = r
	_world_rebuild_territories()
	var nm: String = String(r.get("name", rid))
	_world_queue_news("涓栫晫鎬佸娍锛?s 鍛ㄨ竟鐖嗗彂姝﹁鎽╂摝锛堝叧绯?d锛夈€? % [nm, rel])
	if _world_can_emit_reaction("clash_" + rid, 20):
		_world_mark_reaction("clash_" + rid)
		_world_queue_reaction(
			"frontier_clash",
			rid,
			"%s 杈圭紭鐖嗗彂鍔垮姏鍐茬獊锛岃ˉ缁欑嚎鍜屾不瀹夐兘鍦ㄦ姈鍔ㄣ€? % nm,
			[
				{
					"id":"support_order",
					"text":"鍗忓姪缁寸ǔ锛堣€楅噾甯侊紝闄嶅啿绐侊級",
					"coin_cost": 2,
					"region_delta": {"conflict": -18, "hazard": -8},
					"faction_delta": {"faction_patrol": {"legitimacy": 6}},
					"result_text":"浣犳敮鎻翠簡缁寸ǔ琛屽姩锛屽墠绾挎殏鏃堕檷娓┿€?
				},
				{
					"id":"war_profit",
					"text":"瓒佷贡鑾峰埄锛堟嬁璧勬簮锛屽崌鍐茬獊锛?,
					"gain_coin": 3,
					"gain_ration": 1,
					"region_delta": {"conflict": 12, "pollution": 6},
					"faction_delta": {"faction_grey_market": {"economy": 4}},
					"result_text":"浣犳嬁鍒扮煭鏈熸敹鐩婏紝浣嗗眬鍔胯杩涗竴姝ユ斁澶с€?
				},
				{
					"id":"broker",
					"text":"鏂℃棆鍋滅伀锛堢悊鏅?2锛屾崲鍏崇郴锛?,
					"sanity_cost": 2,
					"region_delta": {"conflict": -10},
					"relation_delta": {"faction_patrol:faction_grey_market": 6, "faction_patrol:faction_scavengers": 4},
					"result_text":"浣犲己琛岃皥鎴愪簡鐭殏鍋滅伀锛屾晫鎰忚鍘嬩綆銆?
				}
			]
		)

func _world_pick_border_region(a: String, b: String) -> String:
	var border: Array[String] = []
	for rid_any in world_regions.keys():
		var rid: String = String(rid_any)
		var r_any: Variant = world_regions.get(rid, {})
		if not (r_any is Dictionary):
			continue
		var r: Dictionary = r_any as Dictionary
		var ctrl: String = String(r.get("controller", ""))
		if ctrl != a and ctrl != b:
			continue
		var n_any: Variant = r.get("neighbors", [])
		if not (n_any is Array):
			continue
		for nb_any in (n_any as Array):
			var nb: String = String(nb_any)
			if not world_regions.has(nb):
				continue
			var nr_any: Variant = world_regions.get(nb, {})
			if not (nr_any is Dictionary):
				continue
			var nctrl: String = String((nr_any as Dictionary).get("controller", ""))
			if (ctrl == a and nctrl == b) or (ctrl == b and nctrl == a):
				if not border.has(rid):
					border.append(rid)
				break
	if border.is_empty():
		return ""
	return border[rng.randi_range(0, border.size() - 1)]

func _world_sync_global_arc() -> void:
	if world_regions.is_empty():
		return
	var n: float = float(max(1, world_regions.size()))
	var sum_food: float = 0.0
	var sum_water: float = 0.0
	var sum_hazard: float = 0.0
	var sum_conflict: float = 0.0
	var sum_mystic: float = 0.0
	var sum_fauna: float = 0.0
	for rid_any in world_regions.keys():
		var r_any: Variant = world_regions.get(String(rid_any), {})
		if not (r_any is Dictionary):
			continue
		var r: Dictionary = r_any as Dictionary
		sum_food += float(r.get("food", 50))
		sum_water += float(r.get("water", 50))
		sum_hazard += float(r.get("hazard", 25))
		sum_conflict += float(r.get("conflict", 20))
		sum_mystic += float(r.get("mystic", 20))
		sum_fauna += float(r.get("fauna", 50))
	var avg_food: float = sum_food / n
	var avg_water: float = sum_water / n
	var avg_hazard: float = sum_hazard / n
	var avg_conflict: float = sum_conflict / n
	var avg_mystic: float = sum_mystic / n
	var avg_fauna: float = sum_fauna / n
	var hostility: float = _world_avg_relation_heat()
	var avg_legit: float = 46.0
	if not world_factions.is_empty():
		var lg: float = 0.0
		for f_any in world_factions.values():
			if f_any is Dictionary:
				lg += float((f_any as Dictionary).get("legitimacy", 40))
		avg_legit = lg / float(max(1, world_factions.size()))

	var target_scarcity: int = _clamp_int(int(100.0 - ((avg_food + avg_water) * 0.5)), 0, 100)
	var target_danger: int = _clamp_int(int(avg_hazard * 0.58 + avg_conflict * 0.42 + max(0.0, 45.0 - avg_fauna) * 0.35), 0, 100)
	var target_war: int = _clamp_int(int(avg_conflict * 0.72 + hostility * 0.28), 0, 100)
	var target_order: int = _clamp_int(int(avg_legit * 0.55 + (100.0 - avg_conflict) * 0.25 - avg_hazard * 0.12), 0, 100)
	var target_mystic: int = _clamp_int(int(avg_mystic), 0, 100)
	global_arc["scarcity"] = _clamp_int(int(round(float(global_arc.get("scarcity", 20)) * 0.72 + float(target_scarcity) * 0.28)), 0, 100)
	global_arc["danger"] = _clamp_int(int(round(float(global_arc.get("danger", 20)) * 0.70 + float(target_danger) * 0.30)), 0, 100)
	global_arc["war"] = _clamp_int(int(round(float(global_arc.get("war", 12)) * 0.68 + float(target_war) * 0.32)), 0, 100)
	global_arc["order"] = _clamp_int(int(round(float(global_arc.get("order", 40)) * 0.70 + float(target_order) * 0.30)), 0, 100)
	global_arc["mystic"] = _clamp_int(int(round(float(global_arc.get("mystic", 20)) * 0.72 + float(target_mystic) * 0.28)), 0, 100)

func _world_avg_relation_heat() -> float:
	if world_factions.size() <= 1:
		return 20.0
	var vals: Array[float] = []
	for f_any in world_factions.values():
		if not (f_any is Dictionary):
			continue
		var f: Dictionary = f_any as Dictionary
		var rel_any: Variant = f.get("relations", {})
		if not (rel_any is Dictionary):
			continue
		var rel: Dictionary = rel_any as Dictionary
		for k_any in rel.keys():
			vals.append(float(rel.get(k_any, 0)))
	if vals.is_empty():
		return 20.0
	var hostility: float = 0.0
	for v in vals:
		hostility += max(0.0, -v)
	return hostility / float(vals.size())

func _world_queue_news(line: String) -> void:
	if line == "":
		return
	world_news_queue.append(line)
	while world_news_queue.size() > 8:
		world_news_queue.pop_front()

func _world_pop_news() -> String:
	if world_news_queue.is_empty():
		return ""
	var out: String = world_news_queue[0]
	world_news_queue.pop_front()
	return out

func _world_can_emit_reaction(key: String, cooldown_h: int) -> bool:
	var last_h: int = int(world_reaction_stamp.get(key, -99999))
	return time_hours - last_h >= cooldown_h

func _world_mark_reaction(key: String) -> void:
	world_reaction_stamp[key] = time_hours

func _world_queue_reaction(kind: String, rid: String, text: String, choices: Array, effects: Array=[]) -> void:
	if text == "":
		return
	world_reaction_nonce += 1
	world_reaction_queue.append({
		"id":"wr%04d" % world_reaction_nonce,
		"kind": kind,
		"rid": rid,
		"text": text,
		"choices": choices.duplicate(true),
		"effects": effects.duplicate(true)
	})
	while world_reaction_queue.size() > 6:
		world_reaction_queue.pop_front()

func _world_maybe_queue_reactions() -> void:
	if world_regions.is_empty():
		return
	for rid_any in world_regions.keys():
		var rid: String = String(rid_any)
		var r_any: Variant = world_regions.get(rid, {})
		if not (r_any is Dictionary):
			continue
		var r: Dictionary = r_any as Dictionary
		var food: int = int(r.get("food", 50))
		var water: int = int(r.get("water", 50))
		var flora: int = int(r.get("flora", 50))
		var fauna: int = int(r.get("fauna", 50))
		var conflict: int = int(r.get("conflict", 20))
		var hazard: int = int(r.get("hazard", 20))
		var mystic: int = int(r.get("mystic", 20))
		var nm: String = String(r.get("name", rid))
		if (food <= 18 or water <= 18) and _world_can_emit_reaction("scarcity_" + rid, 30):
			_world_mark_reaction("scarcity_" + rid)
			_world_queue_reaction(
				"resource_crisis",
				rid,
				"%s 杩涘叆璧勬簮绱х缉锛岃ˉ缁欎笌鐢ㄦ按閮藉湪鎶环銆? % nm,
				[
					{
						"id":"aid_route",
						"text":"鎶曞叆琛ョ粰绋冲畾姘戠敓锛堥噾甯?2 鍙ｇ伯-1锛?,
						"coin_cost": 2,
						"ration_cost": 1,
						"region_delta": {"food": 14, "water": 10, "conflict": -8},
						"faction_delta": {"faction_patrol": {"legitimacy": 4}},
						"result_text":"浣犳妸琛ョ粰鎶曞叆浜嗙揣缂╁尯锛屽眬鍔挎殏鏃跺洖绋炽€?
					},
					{
						"id":"speculate",
						"text":"瓒佺揣缂╁€掕揣锛堥噾甯?3锛?,
						"gain_coin": 3,
						"region_delta": {"food": -6, "water": -4, "conflict": 8},
						"faction_delta": {"faction_grey_market": {"economy": 3}},
						"result_text":"浣犺禋鍒颁簡宸环锛屼絾绱х缉杩涗竴姝ユ墿澶с€?
					},
					{
						"id":"ignore",
						"text":"鏆備笉浠嬪叆",
						"region_delta": {"conflict": 4},
						"result_text":"浣犳病鏈変粙鍏ワ紝绱х缉鍘嬪姏缁х画婊氬姩銆?
					}
				]
			)
		if (flora <= 22 or fauna <= 20 or hazard >= 66) and _world_can_emit_reaction("ecology_" + rid, 36):
			_world_mark_reaction("ecology_" + rid)
			_world_queue_reaction(
				"ecology_break",
				rid,
				"%s 鐢熸€佹槑鏄炬伓鍖栵紝鐚庣墿涓庤崏鏈兘鍦ㄩ€€鍦恒€? % nm,
				[
					{
						"id":"restore",
						"text":"缁勭粐淇锛堥噾甯?2锛?,
						"coin_cost": 2,
						"region_delta": {"flora": 16, "fauna": 12, "pollution": -10, "hazard": -10},
						"result_text":"浣犳帹鍔ㄤ簡淇鎺柦锛岀敓鎬佸紑濮嬬紦鎱㈠洖鍗囥€?
					},
					{
						"id":"last_harvest",
						"text":"鎶㈡渶鍚庝竴娉㈣祫婧愶紙鍙ｇ伯+2锛?,
						"gain_ration": 2,
						"region_delta": {"flora": -8, "fauna": -6, "pollution": 8},
						"result_text":"浣犳嬁鍒颁簡鐭湡鏀剁泭锛屼絾鐢熸€佽繘涓€姝ヤ笅娌夈€?
					},
					{
						"id":"relocate",
						"text":"鏍囪鎾ょ璺嚎",
						"region_delta": {"hazard": -4, "conflict": -2},
						"result_text":"浣犲紩瀵间簡杩佺Щ锛岃嚦灏戝帇浣庝簡鐩存帴浼や骸銆?
					}
				]
			)
		if (conflict >= 62 or hazard >= 70) and _world_can_emit_reaction("frontier_" + rid, 24):
			_world_mark_reaction("frontier_" + rid)
			_world_queue_reaction(
				"frontier_heat",
				rid,
				"%s 鐨勮竟澧冩懇鎿﹀崌娓╋紝娌诲畨涓庨€氳矾閮藉彉寰楄剢寮便€? % nm,
				[
					{
						"id":"stabilize",
						"text":"缁寸ǔ宸℃煡锛堝彛绮?1锛?,
						"ration_cost": 1,
						"region_delta": {"conflict": -14, "hazard": -8},
						"result_text":"浣犳妸楂樺帇鍦版鍘嬪洖浜嗗彲鎺ц寖鍥淬€?
					},
					{
						"id":"arm_proxy",
						"text":"鏆楀姪浠ｇ悊鍐茬獊锛堥噾甯?2锛?,
						"gain_coin": 2,
						"region_delta": {"conflict": 12, "hazard": 6},
						"faction_delta": {"faction_scavengers": {"power": 3}},
						"result_text":"浣犳嬁鍒颁簡鏀剁泭锛屼絾鐏娍琚帹楂樸€?
					},
					{
						"id":"silent_pass",
						"text":"浣庤皟缁曡",
						"region_delta": {"conflict": 2},
						"result_text":"浣犻伩寮€浜嗗啿绐佹牳蹇冿紝浠ｄ环鏄け鍘诲共棰勭獥鍙ｃ€?
					}
				]
			)
		if mystic >= 68 and _world_can_emit_reaction("mystic_" + rid, 28):
			_world_mark_reaction("mystic_" + rid)
			_world_queue_reaction(
				"mystic_surge",
				rid,
				"%s 鍑虹幇鍥炲０娑ㄦ疆锛岀幇瀹炶竟鐣屽紑濮嬩笉绋冲畾銆? % nm,
				[
					{
						"id":"seal",
						"text":"灏侀棴鍥炲０缂濓紙鐞嗘櫤-2锛?,
						"sanity_cost": 2,
						"region_delta": {"mystic": -12, "hazard": -4},
						"result_text":"浣犲帇浣忎簡鍥炲０娑ㄦ疆锛岀煭鏈熷畨鍏ㄦ€ф彁鍗囥€?
					},
					{
						"id":"resonate",
						"text":"鍊熷娍鍏辨尟锛堢嚎绱?2锛?,
						"counter_add": {"k":"clue_key","inc":2},
						"region_delta": {"mystic": 8, "conflict": 4},
						"result_text":"浣犳姄鍒颁簡绋€鏈変俊鎭紝浣嗕唬浠锋槸涓栫晫鍣０鏇撮珮銆?
					},
					{
						"id":"observe",
						"text":"鍙仛瑙傛祴",
						"region_delta": {"mystic": 2},
						"result_text":"浣犺褰曚簡娑ㄦ疆杞ㄨ抗锛屼负鍚庣画鍒ゆ柇鐣欎簡鏍锋湰銆?
					}
				]
			)

func _maybe_offer_world_reaction_choice() -> String:
	if _get_flag("run_ended") or has_pending_choice():
		return ""
	if world_reaction_queue.is_empty():
		return ""
	var ev: Dictionary = world_reaction_queue[0]
	world_reaction_queue.pop_front()
	var rid: String = String(ev.get("rid", ""))
	var kind: String = String(ev.get("kind", "world"))
	var ticket: String = String(ev.get("id", "wr0000"))
	world_reaction_tickets[ticket] = ev.duplicate(true)
	var eff_any: Variant = ev.get("effects", [])
	if eff_any is Array:
		_apply_effects(eff_any as Array)
	_pending_choices.clear()
	var choices_any: Variant = ev.get("choices", [])
	if choices_any is Array:
		for c_any in (choices_any as Array):
			if not (c_any is Dictionary):
				continue
			var c: Dictionary = c_any as Dictionary
			var oid: String = String(c.get("id", "pick"))
			var txt: String = String(c.get("text", oid))
			_pending_choices.append({
				"id":"world_%s_%s" % [ticket, oid],
				"text": txt,
				"system_action":"sys.world.%s.%s" % [ticket, oid]
			})
	_has_pending = not _pending_choices.is_empty()
	if not _has_pending:
		world_reaction_tickets.erase(ticket)
		return ""
	var head: String = String(ev.get("text", "涓栫晫鎬佸娍鍙戠敓浜嗗彉鍖栥€?))
	_add_impact_tag("涓栫晫鎬佸娍")
	_echo_world("鍥炲搷瑙﹀彂锛? + head)
	_add_counter("world_reaction_" + kind, 1)
	if rid != "":
		_add_counter("world_reaction_region_" + rid, 1)
	return head + "\n[color=orange]涓栫晫鎶夋嫨宸茶嚜鍔ㄥ脊鍑恒€俒/color]"

func _apply_world_reaction_action(choice_id: String) -> Dictionary:
	var parts: PackedStringArray = choice_id.split(".")
	if parts.size() < 4:
		return _action_result("涓栫晫鎬佸娍绐楀彛宸插亸绉汇€?)
	var ticket: String = parts[2]
	var opt_id: String = parts[3]
	if not world_reaction_tickets.has(ticket):
		return _action_result("杩欐潯涓栫晫鎬佸娍宸茬粡杩囧幓銆?)
	var ctx_any: Variant = world_reaction_tickets.get(ticket, {})
	world_reaction_tickets.erase(ticket)
	if not (ctx_any is Dictionary):
		return _action_result("浣犳病鑳芥姄浣忚繖娆′笘鐣岀獥鍙ｃ€?)
	var ctx: Dictionary = ctx_any as Dictionary
	var c_any: Variant = ctx.get("choices", [])
	if not (c_any is Array):
		return _action_result("鍙墽琛岄」宸茬粡鍏抽棴銆?)
	var picked: Dictionary = {}
	for it_any in (c_any as Array):
		if not (it_any is Dictionary):
			continue
		var it: Dictionary = it_any as Dictionary
		if String(it.get("id", "")) == opt_id:
			picked = it
			break
	if picked.is_empty():
		return _action_result("璇ヤ笘鐣岄€夐」宸茬粡涓嶅彲鐢ㄣ€?)

	var coin_cost: int = int(picked.get("coin_cost", 0))
	var ration_cost: int = int(picked.get("ration_cost", 0))
	var sanity_cost: int = int(picked.get("sanity_cost", 0))
	if coin < coin_cost or ration < ration_cost:
		return _action_result("浣犳兂鎵ц杩欓」澶勭疆锛屼絾璧勬簮涓嶈冻銆?)
	coin = max(0, coin - coin_cost)
	ration = max(0, ration - ration_cost)
	if sanity_cost > 0:
		sanity = max(0, sanity - sanity_cost)

	if picked.has("gain_coin"):
		coin += int(picked.get("gain_coin", 0))
	if picked.has("gain_ration"):
		ration += int(picked.get("gain_ration", 0))
	if picked.has("counter_add") and picked.get("counter_add") is Dictionary:
		var ad: Dictionary = picked.get("counter_add", {})
		_add_counter(String(ad.get("k", "")), int(ad.get("inc", 0)))

	var rid: String = String(ctx.get("rid", ""))
	if picked.has("region_delta") and picked.get("region_delta") is Dictionary:
		_world_apply_region_delta(rid, picked.get("region_delta", {}))
	if picked.has("faction_delta") and picked.get("faction_delta") is Dictionary:
		var fd: Dictionary = picked.get("faction_delta", {})
		for fid_any in fd.keys():
			var fid: String = String(fid_any)
			if fd.get(fid_any) is Dictionary:
				_world_apply_faction_delta(fid, fd.get(fid_any, {}))
	if picked.has("relation_delta") and picked.get("relation_delta") is Dictionary:
		var rd: Dictionary = picked.get("relation_delta", {})
		for k_any in rd.keys():
			var key: String = String(k_any)
			var pair: PackedStringArray = key.split(":")
			if pair.size() == 2:
				_world_apply_relation_delta(String(pair[0]), String(pair[1]), int(rd.get(k_any, 0)))

	_world_sync_global_arc()
	var rtxt: String = String(picked.get("result_text", "浣犲湪涓栫晫鎬佸娍涓仛鍑轰簡鎶夋嫨銆?))
	_echo_world("涓栫晫鍥炲搷锛?s" % rtxt)
	return _action_result(rtxt)

func _world_apply_region_delta(rid: String, delta_any: Variant) -> void:
	if rid == "" or not world_regions.has(rid):
		return
	if not (delta_any is Dictionary):
		return
	var delta: Dictionary = delta_any as Dictionary
	var r_any: Variant = world_regions.get(rid, {})
	if not (r_any is Dictionary):
		return
	var r: Dictionary = r_any as Dictionary
	for k_any in delta.keys():
		var k: String = String(k_any)
		var inc: int = int(delta.get(k_any, 0))
		r[k] = _clamp_int(int(r.get(k, 0)) + inc, 0, 100)
	world_regions[rid] = r

func _world_apply_faction_delta(fid: String, delta_any: Variant) -> void:
	if fid == "" or not world_factions.has(fid):
		return
	if not (delta_any is Dictionary):
		return
	var d: Dictionary = delta_any as Dictionary
	var f_any: Variant = world_factions.get(fid, {})
	if not (f_any is Dictionary):
		return
	var f: Dictionary = f_any as Dictionary
	for k_any in d.keys():
		var k: String = String(k_any)
		var inc: int = int(d.get(k_any, 0))
		f[k] = _clamp_int(int(f.get(k, 0)) + inc, 0, 100)
	world_factions[fid] = f

func _world_apply_relation_delta(a: String, b: String, inc: int) -> void:
	if a == "" or b == "":
		return
	if not world_factions.has(a) or not world_factions.has(b):
		return
	var fa_any: Variant = world_factions.get(a, {})
	var fb_any: Variant = world_factions.get(b, {})
	if not (fa_any is Dictionary) or not (fb_any is Dictionary):
		return
	var fa: Dictionary = fa_any as Dictionary
	var fb: Dictionary = fb_any as Dictionary
	var ra_any: Variant = fa.get("relations", {})
	var rb_any: Variant = fb.get("relations", {})
	var ra: Dictionary = ra_any as Dictionary if ra_any is Dictionary else {}
	var rb: Dictionary = rb_any as Dictionary if rb_any is Dictionary else {}
	ra[b] = _clamp_int(int(ra.get(b, 0)) + inc, -100, 100)
	rb[a] = _clamp_int(int(rb.get(a, 0)) + inc, -100, 100)
	fa["relations"] = ra
	fb["relations"] = rb
	world_factions[a] = fa
	world_factions[b] = fb

func _world_apply_player_action(action: String, intensity: int=1, extra: Dictionary={}) -> void:
	var s: int = max(1, intensity)
	var rid: String = String(extra.get("rid", current_region_id))
	if rid == "" or not world_regions.has(rid):
		return
	var r_any: Variant = world_regions.get(rid, {})
	if not (r_any is Dictionary):
		return
	var r: Dictionary = r_any as Dictionary
	match action:
		"forage":
			r["food"] = _clamp_int(int(r.get("food", 50)) - 2 * s, 0, 100)
			r["flora"] = _clamp_int(int(r.get("flora", 50)) - 1 * s, 0, 100)
			r["pollution"] = _clamp_int(int(r.get("pollution", 10)) + s, 0, 100)
		"hunt":
			r["fauna"] = _clamp_int(int(r.get("fauna", 50)) - 3 * s, 0, 100)
			r["food"] = _clamp_int(int(r.get("food", 50)) + 2 * s, 0, 100)
			r["hazard"] = _clamp_int(int(r.get("hazard", 20)) + s, 0, 100)
		"trade":
			_world_apply_faction_delta("faction_grey_market", {"economy": 2 * s})
			_world_apply_relation_delta("faction_grey_market", "faction_patrol", -1 * s)
		"leverage":
			_world_apply_faction_delta("faction_patrol", {"legitimacy": 2 * s})
			_world_apply_relation_delta("faction_patrol", "faction_grey_market", 1 * s)
		"deep_echo", "meditate":
			r["mystic"] = _clamp_int(int(r.get("mystic", 20)) + 3 * s, 0, 100)
			r["hazard"] = _clamp_int(int(r.get("hazard", 20)) + int(s / 2), 0, 100)
		"reroute":
			r["conflict"] = _clamp_int(int(r.get("conflict", 20)) - 2 * s, 0, 100)
			r["hazard"] = _clamp_int(int(r.get("hazard", 20)) - 2 * s, 0, 100)
		"travel":
			r["hazard"] = _clamp_int(int(r.get("hazard", 20)) + 1 * s, 0, 100)
		"rest":
			r["conflict"] = _clamp_int(int(r.get("conflict", 20)) - s, 0, 100)
		"push":
			r["hazard"] = _clamp_int(int(r.get("hazard", 20)) + 2 * s, 0, 100)
			r["conflict"] = _clamp_int(int(r.get("conflict", 20)) + s, 0, 100)
		"scout":
			r["mystic"] = _clamp_int(int(r.get("mystic", 20)) + s, 0, 100)
			r["conflict"] = _clamp_int(int(r.get("conflict", 20)) + int(s / 2), 0, 100)
		_:
			pass
	world_regions[rid] = r
	_world_sync_global_arc()

func _world_apply_module_outcome(module: Dictionary, style: String, success: bool) -> void:
	var rid: String = current_region_id
	if rid == "" or not world_regions.has(rid):
		return
	var tags_any: Variant = module.get("tags", [])
	var tags: Array = tags_any as Array if tags_any is Array else []
	var delta: Dictionary = {}
	if success:
		if "supply" in tags:
			delta["food"] = 6 if style == "gamble" else 3
			delta["water"] = 3
		if "faction" in tags:
			delta["conflict"] = -6 if style != "gamble" else -3
			_world_apply_relation_delta("faction_patrol", "faction_grey_market", 2 if style != "gamble" else -1)
		if "predator" in tags:
			delta["hazard"] = -5
			delta["fauna"] = -2 if style == "gamble" else -1
		if "echo" in tags:
			delta["mystic"] = 5
		if style == "retreat":
			delta["hazard"] = int(delta.get("hazard", 0)) + 2
	else:
		delta["conflict"] = 7
		delta["hazard"] = 5
		if "supply" in tags:
			delta["food"] = -4
			delta["water"] = -3
		if "faction" in tags:
			_world_apply_relation_delta("faction_patrol", "faction_scavengers", -3)
	_world_apply_region_delta(rid, delta)

func _world_apply_thread_outcome(kind: String, resolved: bool, pressure: int) -> void:
	var rid: String = current_region_id
	if rid == "" or not world_regions.has(rid):
		return
	if resolved:
		match kind:
			"predator":
				_world_apply_region_delta(rid, {"hazard": -14, "conflict": -6, "fauna": -4})
			"scarcity":
				_world_apply_region_delta(rid, {"food": 16, "water": 10, "conflict": -8})
			"echo":
				_world_apply_region_delta(rid, {"mystic": 8, "hazard": -4})
			"faction":
				_world_apply_region_delta(rid, {"conflict": -12, "hazard": -6})
				_world_apply_relation_delta("faction_patrol", "faction_grey_market", 4)
			"patrol":
				_world_apply_faction_delta("faction_patrol", {"legitimacy": 5, "power": 2})
			_:
				_world_apply_region_delta(rid, {"conflict": -6})
	else:
		var inc: int = 6 + int(pressure / 18)
		match kind:
			"predator":
				_world_apply_region_delta(rid, {"hazard": inc, "fauna": -4})
			"scarcity":
				_world_apply_region_delta(rid, {"food": -8, "water": -6, "conflict": 6})
			"echo":
				_world_apply_region_delta(rid, {"mystic": 10, "hazard": 5})
			"faction":
				_world_apply_region_delta(rid, {"conflict": inc, "hazard": 4})
				_world_apply_relation_delta("faction_patrol", "faction_scavengers", -4)
			_:
				_world_apply_region_delta(rid, {"conflict": 6, "hazard": 4})
	_world_sync_global_arc()

# ========== 鎻愪緵缁?UI ==========
func has_pending_choice() -> bool:
	return _has_pending and not _pending_choices.is_empty()

func get_current_choices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in _pending_choices:
		out.append(it.duplicate(true))
	return out

func apply_choice(choice_id: String) -> Dictionary:
	var out: Dictionary = {"type":"", "text":""}
	if not has_pending_choice():
		_sync_shared_state()
		return out

	var picked: Dictionary = {}
	for c in _pending_choices:
		if String(c.get("id","")) == choice_id:
			picked = c
			break

	_pending_choices.clear()
	_has_pending = false
	if picked.is_empty():
		_sync_shared_state()
		return out

	# 鍏堟墽琛岄€夐」鏁堟灉
	var eff_any: Variant = picked.get("effects", [])
	if eff_any is Array:
		_apply_effects(eff_any as Array)

	# 鑻ユ湁 goto锛岀洿鎺ヨ烦鎸囧畾浜嬩欢
	var goto_id: String = String(picked.get("goto",""))
	if goto_id != "":
		var ev_txt: String = _run_event_by_id(goto_id)
		if ev_txt != "":
			_sync_shared_state()
			return {"type":"event","text": ev_txt}

	# 鍏佽鎶夋嫨鐩存帴鏄犲皠鍒扮郴缁熻鍔?	var sys_act: String = String(picked.get("system_action", ""))
	if sys_act != "":
		var out_sys: Dictionary = apply_system_choice(sys_act)
		_sync_shared_state()
		return out_sys

	out["type"] = "event"
	out["text"] = String(picked.get("result_text", ""))
	_sync_shared_state()
	return out

# ========== 姣忔鎺ㄨ繘涓€灏忔椂 ==========
func produce_snapshot(_opts: Dictionary={}) -> Dictionary:
	if v02_enabled:
		return _produce_snapshot_v02(_opts)
	if v01_enabled:
		return _produce_snapshot_v01(_opts)

	var snap: Dictionary = {}

	# 绛夊緟鐜╁閫夋嫨鏃朵笉鍐嶆帹杩?	if has_pending_choice():
		snap["event_text"] = "褰撳墠鏈夊緟澶勭悊鎶夋嫨锛屽厛鍦ㄣ€岄€夋嫨銆嶉噷鍐崇瓥銆?
		return _decorate_snapshot(snap)

	# 寮犲姏椹卞姩鎺ㄨ繘姝ラ暱锛氫綆寮犲姏蹇繘锛岄珮寮犲姏缁嗙矑搴?	var step_h: int = _choose_time_step()
	time_hours += step_h
	_survival_tick(step_h)
	_decay_exposure(pow(0.985, float(step_h)))
	var collapse_text: String = _check_collapse_text()
	if collapse_text != "":
		snap["event_text"] = collapse_text
		return _decorate_snapshot(snap)

	var montage_line: String = ""
	if step_h >= 6:
		montage_line = _build_montage_summary(step_h)

	# 澶╂皵锛堝彉鍖栦笖杩囧喎鍗存墠鎾姤锛?	var w: Dictionary = _pick_weather_once()
	if not w.is_empty():
		snap["weather"] = w

	# 鍏堣窇棣栧叆 starter:true
	var t: String = _run_starter_if_needed()
	if t != "":
		snap["event_text"] = _merge_event_text(montage_line, t)
		return _decorate_snapshot(snap)

	# 鍏堝鐞嗗欢杩熺粨绠楋紙绾跨▼澶辨帶绛夛級
	var alert_text: String = _pop_story_alert()
	if alert_text != "":
		snap["event_text"] = _merge_event_text(montage_line, alert_text)
		return _decorate_snapshot(snap)

	# 鍥炲搷瑙﹀彂锛氳繃鍘婚€夋嫨鍦ㄦ湭鏉ヨ妭鐐瑰弽寮?	var echo_text: String = _trigger_due_echo_hook()
	if echo_text != "":
		snap["event_text"] = _merge_event_text(montage_line, echo_text)
		return _decorate_snapshot(snap)

	var world_prompt: String = _maybe_offer_world_reaction_choice()
	if world_prompt != "":
		snap["event_text"] = _merge_event_text(montage_line, world_prompt)
		return _decorate_snapshot(snap)

	if step_h >= 6 or rng.randf() < 0.35:
		var world_news: String = _world_pop_news()
		if world_news != "":
			snap["event_text"] = _merge_event_text(montage_line, world_news)
			return _decorate_snapshot(snap)

	# 绮惧姏闃堝€艰浆鍓ф儏鍖栦簨浠讹紙鏇夸唬姣忓皬鏃剁‖鎵ｏ級
	var energy_text: String = _maybe_spawn_energy_incident()
	if energy_text != "":
		snap["event_text"] = _merge_event_text(montage_line, energy_text)
		return _decorate_snapshot(snap)

	# 鍐嶅皾璇曠敓鎴愭柊鐨勪笘鐣岀嚎绋嬶紙鍗辨満/鏈轰細/璋滃洟锛?	var spawn_text: String = _maybe_spawn_story_thread()
	if spawn_text != "":
		snap["event_text"] = _merge_event_text(montage_line, spawn_text)
		return _decorate_snapshot(snap)

	# 浼樺厛鎶涘嚭鏈夊悗鏋滅殑寮€鏀炬妷鎷?	var thread_prompt: String = _maybe_offer_story_thread_choice()
	if thread_prompt != "":
		snap["event_text"] = _merge_event_text(montage_line, thread_prompt)
		return _decorate_snapshot(snap)

	# 浣庡紶鍔涘揩杩涙椂锛屽己鍒剁粰涓€涓満浼氳妭鐐癸紝閬垮厤绌虹偣鍑?	var module_prompt: String = _maybe_offer_situation(true)
	if module_prompt != "":
		snap["event_text"] = _merge_event_text(montage_line, module_prompt)
		return _decorate_snapshot(snap)

	# 鍐嶈窇甯歌浜嬩欢
	var ev_txt: String = _run_regular_event()
	if ev_txt != "":
		snap["event_text"] = _merge_event_text(montage_line, ev_txt)
		return _decorate_snapshot(snap)

	# 鍏ㄥ眬鐘舵€侀┍鍔ㄤ簨浠讹紙闈炴ā鏉垮浐瀹氾級
	var arc_txt: String = _run_global_state_event()
	if arc_txt != "":
		snap["event_text"] = _merge_event_text(montage_line, arc_txt)
		return _decorate_snapshot(snap)

	# 鏃犱簨浠跺垯鍚堟垚涓€娈电邯浜?	var dyn_dilemma: String = _maybe_spawn_state_dilemma()
	if dyn_dilemma != "":
		snap["event_text"] = _merge_event_text(montage_line, dyn_dilemma)
		return _decorate_snapshot(snap)

	# 鏃犱簨浠跺垯鍚堟垚涓€娈电邯浜?	var para: String = _compose_hourly_paragraph()
	if para != "":
		snap["event_text"] = _merge_event_text(montage_line, para)
	elif montage_line != "":
		snap["event_text"] = montage_line

	return _decorate_snapshot(snap)

# ========== 浜嬩欢锛歴tarter 涓庡父瑙?==========
func _run_starter_if_needed() -> String:
	var key: String = "starter_fired_" + current_region_id
	if _get_flag(key):
		return ""
	var arr: Array = _region_events_array()
	var pool: Array[Dictionary] = []
	for w_any in arr:
		if not (w_any is Dictionary):
			continue
		var wrap: Dictionary = w_any as Dictionary
		var ev_any: Variant = wrap.get("event", {})
		if not (ev_any is Dictionary):
			continue
		var ev: Dictionary = ev_any as Dictionary
		var is_starter: bool = bool(ev.get("starter", false))
		if not is_starter:
			continue
		pool.append({"event": ev, "weight": float(wrap.get("weight", 1.0))})
	if pool.is_empty():
		return ""
	var picked: Dictionary = _weighted_pick(pool)
	var evd_any: Variant = picked.get("event", {})
	var evd: Dictionary = evd_any as Dictionary if evd_any is Dictionary else {}
	_set_flag(key, true)
	return _execute_event(evd)

func _run_regular_event() -> String:
	if time_hours - last_regular_event_hour < 2:
		return ""

	var chance: float = 0.16
	chance += float(global_arc.get("danger", 20)) / 420.0
	chance += float(global_arc.get("mystic", 20)) / 700.0
	chance += float(global_arc.get("scarcity", 20)) / 620.0
	chance -= float(max(0, _story_open_count() - 1)) * 0.03
	chance = clamp(chance, 0.08, 0.46)
	if rng.randf() > chance:
		return ""

	var pools_any: Variant = current_region.get("pools", {})
	if not (pools_any is Dictionary):
		return ""
	var pools: Dictionary = pools_any as Dictionary
	var candidates_any: Variant = pools.get("events", [])
	if not (candidates_any is Array):
		return ""
	var candidates: Array = candidates_any as Array

	var usable: Array[Dictionary] = []
	for w in candidates:
		if not (w is Dictionary):
			continue
		var wrap: Dictionary = w as Dictionary
		var ev_any: Variant = wrap.get("event", {})
		var ev: Dictionary = ev_any as Dictionary if ev_any is Dictionary else {}
		var ev_id: String = String(ev.get("id", ""))
		var wt: float = float(wrap.get("weight", 1.0))
		if ev_id != "":
			var repeat_penalty: float = pow(0.52, float(_count_str_in_array(recent_regular_event_ids, ev_id)))
			var long_penalty: float = pow(0.92, float(int(counters.get("event_used_" + ev_id, 0))))
			wt *= repeat_penalty * long_penalty
		if wt <= 0.0:
			continue
		if _check_event_pre(ev):
			usable.append({"event": ev, "weight": wt})
	if usable.is_empty():
		return ""

	var chosen: Dictionary = _weighted_pick(usable)
	var ev_run_any: Variant = chosen.get("event", {})
	var ev_run: Dictionary = ev_run_any as Dictionary if ev_run_any is Dictionary else {}
	var chosen_id: String = String(ev_run.get("id", ""))
	if chosen_id != "":
		_add_counter("event_used_" + chosen_id, 1)
		recent_regular_event_ids.append(chosen_id)
		if recent_regular_event_ids.size() > 6:
			recent_regular_event_ids.pop_front()
	last_regular_event_hour = time_hours
	return _execute_event(ev_run)

func _run_event_by_id(eid: String) -> String:
	if eid == "":
		return ""
	var arr: Array = _region_events_array()
	for w in arr:
		if not (w is Dictionary):
			continue
		var wrap: Dictionary = w as Dictionary
		var ev_any: Variant = wrap.get("event", {})
		var ev: Dictionary = ev_any as Dictionary if ev_any is Dictionary else {}
		if String(ev.get("id","")) == eid:
			return _execute_event(ev)
	push_warning("[GameGameWorldGeneration] goto 浜嬩欢鏈壘鍒? %s" % eid)
	return ""

func _region_events_array() -> Array:
	var pools_any: Variant = current_region.get("pools", {})
	if not (pools_any is Dictionary):
		return []
	var pools: Dictionary = pools_any as Dictionary
	var events_any: Variant = pools.get("events", [])
	if events_any is Array:
		return events_any as Array
	return []

func _check_event_pre(ev: Dictionary) -> bool:
	var pre_any: Variant = ev.get("pre", [])
	if not (pre_any is Array):
		return true
	for cond_any in (pre_any as Array):
		if not (cond_any is Dictionary):
			continue
		var cond: Dictionary = cond_any as Dictionary
		if cond.has("flag_present"):
			if not _get_flag(String(cond.get("flag_present",""))):
				return false
		if cond.has("flag_absent"):
			if _get_flag(String(cond.get("flag_absent",""))):
				return false
		if cond.has("flag_present_any"):
			var arr_any: Variant = cond.get("flag_present_any", [])
			var ok: bool = false
			if arr_any is Array:
				for f_any in (arr_any as Array):
					if _get_flag(String(f_any)):
						ok = true
						break
			if not ok:
				return false
		if cond.has("counter_gte"):
			var kv_any: Variant = cond.get("counter_gte", {})
			var kv: Dictionary = kv_any as Dictionary if kv_any is Dictionary else {}
			var k: String = String(kv.get("k",""))
			var v: int = int(kv.get("v",0))
			if _get_counter(k) < v:
				return false
	return true

func _execute_event(ev: Dictionary) -> String:
	var tpls_any: Variant = ev.get("text_templates", [])
	var text: String = _pick_one(tpls_any as Array if tpls_any is Array else [])

	var eff_any: Variant = ev.get("effects", [])
	if eff_any is Array:
		_apply_effects(eff_any as Array)

	_pending_choices.clear()
	_has_pending = false
	var choices_any: Variant = ev.get("choices", [])
	if choices_any is Array and not (choices_any as Array).is_empty():
		for o_any in (choices_any as Array):
			if o_any is Dictionary:
				_pending_choices.append((o_any as Dictionary).duplicate(true))
		_has_pending = not _pending_choices.is_empty()

	if not _has_pending:
		var next_any: Variant = ev.get("next", [])
		if next_any is Array and not (next_any as Array).is_empty():
			var pool: Array[Dictionary] = []
			for n_any in (next_any as Array):
				if not (n_any is Dictionary):
					continue
				var nd: Dictionary = n_any as Dictionary
				var nid: String = String(nd.get("id",""))
				if nid == "":
					continue
				var req_ok: bool = true
				var req_any: Variant = nd.get("req", [])
				if req_any is Array:
					for r_any in (req_any as Array):
						if not (r_any is Dictionary):
							continue
						var r: Dictionary = r_any as Dictionary
						if r.has("counter_gte"):
							var kv_any2: Variant = r.get("counter_gte", {})
							var kv2: Dictionary = kv_any2 as Dictionary if kv_any2 is Dictionary else {}
							var k2: String = String(kv2.get("k",""))
							var v2: int = int(kv2.get("v",0))
							if _get_counter(k2) < v2:
								req_ok = false
								break
				if req_ok:
					pool.append({"event_id": nid, "weight": float(nd.get("weight",1.0))})
			if not pool.is_empty():
				var picked: Dictionary = _weighted_pick(pool)
				var pid: String = String(picked.get("event_id",""))
				if pid != "":
					var t2: String = _run_event_by_id(pid)
					if t2 != "":
						if text != "":
							text += "\n" + t2
						else:
							text = t2

	return text.strip_edges()

func _maybe_spawn_state_dilemma() -> String:
	if _get_flag("run_ended"):
		return ""
	if has_pending_choice():
		return ""
	if rng.randf() > 0.22:
		return ""

	var unslept: int = max(0, sleep_max - sleep_energy)
	var lines: Array[Dictionary] = []

	if hunger <= 10:
		lines.append({
			"text": "浣犵殑鑳冮儴鎸佺画鎶界棝锛岃鍥婇噷鍙珛鍗抽鐢ㄧ殑涓滆タ宸茬粡涓嶅銆?,
			"choices": [
				{"id":"dilemma_hunt_now", "text":"鍐掗櫓杩界寧锛堥珮椋庨櫓锛岄珮鏀剁泭锛?, "system_action":"sys.hunt"},
				{"id":"dilemma_ration_now", "text":"鍚冩帀鍙ｇ伯绋充綇鐘舵€?, "system_action":"sys.eat"},
				{"id":"dilemma_endure", "text":"纭拺鍓嶈锛堢悊鏅?2锛?, "effects":[{"op":"meter_add","k":"sanity","inc":-2}]}
			]
		})

	if unslept >= 16:
		lines.append({
			"text":"浣犵殑鐪肩湺鍍忕亴浜嗙爞锛岃剼姝ュ紑濮嬪嚭鐜颁笉鍙楁帶鐨勫亸宸€?,
			"choices":[
				{"id":"dilemma_sleep", "text":"绔嬪埢浼戞伅锛堣€楁椂7h锛?, "system_action":"sys.rest"},
				{"id":"dilemma_push", "text":"寮鸿鎺ㄨ繘锛堝嵄闄?锛?, "effects":[{"op":"meter_add","k":"sanity","inc":-3},{"op":"meter_add","k":"hp","inc":-2}]}
			]
		})

	if int(global_arc.get("danger", 0)) >= 48:
		lines.append({
			"text":"鏋楅棿浼犳潵瀵嗛泦韪╄笍澹帮紝鍍忔湁鎴愮兢鐢熺墿姝ｅ湪骞宠灏鹃殢銆?,
			"choices":[
				{"id":"dilemma_trap", "text":"涓存椂甯冪疆闄烽槺鎷栧欢", "system_action":"sys.trap"},
				{"id":"dilemma_hide", "text":"缁曡瑙勯伩锛堣€楁椂+1h锛?, "effects":[{"op":"counter_add","k":"delay_h","inc":1}]},
				{"id":"dilemma_face", "text":"姝ｉ潰绌胯繃鍘伙紙鐢熷懡-4锛屾崲鍙栨帹杩涳級", "effects":[{"op":"meter_add","k":"hp","inc":-4}]}
			]
		})

	if int(global_arc.get("mystic", 0)) >= 46:
		lines.append({
			"text":"鍓嶆柟钖勯浘閲屽嚭鐜颁簡鍜屼綘鍔ㄤ綔鐣ユ湁鏃跺樊鐨勫奖瀛愶紝鍍忓彟涓€鏉℃椂闂寸嚎鐨勮嚜宸便€?,
			"choices":[
				{"id":"dilemma_echo_touch", "text":"鎺ヨЕ鍥炲０锛堢悊鏅烘尝鍔紝鍙兘寰楄澶囷級", "system_action":"sys.meditate"},
				{"id":"dilemma_echo_leave", "text":"鐩存帴绂诲紑锛堝畨鍏級", "effects":[{"op":"counter_add","k":"echo_avoided","inc":1}]}
			]
		})

	if lines.is_empty():
		return ""

	var picked: Dictionary = lines[rng.randi_range(0, lines.size() - 1)]
	var c_any: Variant = picked.get("choices", [])
	if c_any is Array:
		_pending_choices.clear()
		for c in (c_any as Array):
			if c is Dictionary:
				_pending_choices.append((c as Dictionary).duplicate(true))
		_has_pending = not _pending_choices.is_empty()
		if _has_pending:
			return String(picked.get("text", "")) + "\n[color=orange]鍑虹幇鍏抽敭鎶夋嫨锛氬凡鑷姩寮瑰嚭锛岃鐩存帴閫夋嫨銆俒/color]"
	return ""

# ========== Effects ==========
func _apply_effects(effects: Array) -> void:
	for e_any in effects:
		if not (e_any is Dictionary):
			continue
		var e: Dictionary = e_any as Dictionary
		var op: String = String(e.get("op",""))
		match op:
			"flag_set":
				_set_flag(String(e.get("id","")), true)
			"flag_clear":
				_set_flag(String(e.get("id","")), false)
			"counter_add":
				_add_counter(String(e.get("k","")), int(e.get("inc", 0)))
			"meter_add":
				_add_meter(String(e.get("k","")), int(e.get("inc",0)), e)
			"coin_add":
				coin = max(0, coin + int(e.get("inc", 0)))
			"ration_add":
				ration = max(0, ration + int(e.get("inc", 0)))
			"chronicle_push":
				_chronicle_push(String(e.get("text", "")))
			"travel_to_region":
				_travel_to_region(String(e.get("to","")), int(e.get("hours", 1)))
			"timer_set":
				_set_counter(String(e.get("k","")), int(e.get("hours", 0)))
			"world_region_delta":
				_world_apply_region_delta(String(e.get("rid", current_region_id)), e.get("delta", {}))
			"world_faction_delta":
				_world_apply_faction_delta(String(e.get("fid", "")), e.get("delta", {}))
			"world_relation_add":
				_world_apply_relation_delta(String(e.get("a", "")), String(e.get("b", "")), int(e.get("inc", 0)))
			_:
				push_warning("[GameGameWorldGeneration] 鏈疄鐜扮殑 effect: %s" % op)

func _chronicle_push(text: String) -> void:
	if text == "":
		return
	var line: String = "[%s D%02d H%02d] %s" % [current_region_id, _current_day(), _current_hour(), text]
	chronicle_lines.append(line)
	var ws: WorldState = _ws()
	if ws != null:
		ws.chronicle_push(line)

# ========== 澶╂皵 / 鍙欎簨 / 灏忛澶?==========
func _pick_weather_once() -> Dictionary:
	var pools: Dictionary = {}
	if current_region.has("pools") and current_region.get("pools") is Dictionary:
		pools = current_region.get("pools") as Dictionary

	var arr_any: Variant = pools.get("weather", [])
	if not (arr_any is Array):
		return {}
	var arr: Array = arr_any as Array
	if arr.is_empty():
		return {}

	# 鍐峰嵈锛氭湭鍒板喎鍗存湡锛屼笉鎾姤
	if time_hours - last_weather_broadcast_hour < weather_cooldown_h:
		return {}

	var pool: Array[Dictionary] = []
	for w_any in arr:
		if not (w_any is Dictionary):
			continue
		var wrap: Dictionary = w_any as Dictionary
		var entry: Dictionary = {}
		if wrap.has("event") and wrap.get("event") is Dictionary:
			entry = wrap.get("event") as Dictionary
		else:
			entry = wrap
		var wt: float = float(wrap.get("weight", 1.0))
		if wt > 0.0:
			pool.append({"entry": entry, "weight": wt})

	if pool.is_empty():
		return {}

	var pick: Dictionary = _weighted_pick(pool)
	var entry2_any: Variant = pick.get("entry", {})
	var entry2: Dictionary = entry2_any as Dictionary if entry2_any is Dictionary else {}
	var id: String = String(entry2.get("id",""))

	if id == "" or id == last_weather_id:
		return {}
	last_weather_id = id
	last_weather_broadcast_hour = time_hours
	return entry2

func _pick_narrative_snippet() -> String:
	var arr_any: Variant = current_region.get("narrative_snippets", [])
	if not (arr_any is Array):
		return ""
	var arr: Array = arr_any as Array
	return _pick_one(arr)

func _roll_small_extras() -> Dictionary:
	var out: Dictionary = {}

	# sublocation: 20%
	if rng.randf() < 0.2 and current_region.has("sublocations"):
		var subs_any: Variant = current_region.get("sublocations", [])
		if subs_any is Array and not (subs_any as Array).is_empty():
			var sub: Dictionary = _pick_one_dict(subs_any as Array)
			if not sub.is_empty():
				out["subloc"] = sub

	# flora: 30%
	var pools: Dictionary = _region_pools()
	if rng.randf() < 0.3:
		var fl_any: Variant = pools.get("flora", [])
		if fl_any is Array and not (fl_any as Array).is_empty():
			out["flora"] = _pick_one_dict(fl_any as Array)

	# fauna/creatures: 25%
	if rng.randf() < 0.25:
		var fa_any: Variant = pools.get("fauna", [])
		if not (fa_any is Array):
			fa_any = pools.get("creatures", [])
		if fa_any is Array and not (fa_any as Array).is_empty():
			out["fauna"] = _pick_one_dict(fa_any as Array)

	return out

func _compose_hourly_paragraph() -> String:
	var lines: Array[String] = []
	var danger: int = int(global_arc.get("danger", 20))
	var mystic: int = int(global_arc.get("mystic", 20))
	var scarcity: int = int(global_arc.get("scarcity", 20))

	var base_line: String = _pick_narrative_snippet()
	if base_line != "" and base_line != last_snippet_line:
		lines.append(base_line)
		last_snippet_line = base_line

	var extras: Dictionary = _roll_small_extras()
	if extras.has("subloc"):
		var sub: Dictionary = extras["subloc"] as Dictionary
		var sn: String = String(sub.get("name",""))
		if sn != "":
			lines.append("浣犳部鐫€鏋楅棿鐨勬棫寰勶紝鎶佃揪銆?s銆嶃€? % sn)
	if extras.has("flora"):
		var fl: Dictionary = extras["flora"] as Dictionary
		var fn: String = String(fl.get("name",""))
		if fn != "":
			lines.append("鏋椾笅鐨勩€?s銆嶆摝杩囬澊杈癸紝鐣欎笅涓€涓濇疆鑵ョ殑姘斿懗銆? % fn)
	if extras.has("fauna"):
		var fa: Dictionary = extras["fauna"] as Dictionary
		var an: String = String(fa.get("name",""))
		if an != "":
			lines.append("涓嶈繙澶勬湁銆?s銆嶈鎯曞湴鍋滀綇锛岄殢鍚庢矇鍏ラ浘褰便€? % an)

	if danger >= 55 and rng.randf() < 0.4:
		lines.append("鏋楀湴閲岀殑鎹曢绉╁簭姝ｅ湪鏀瑰啓锛岃繛椋庡悜閮藉甫鐫€鐚庢剰銆?)
	elif danger <= 20 and rng.randf() < 0.3:
		lines.append("璺潰缃曡鍦板畨闈欙紝浠夸經鏈変粈涔堝姏閲忓湪缁存寔绉╁簭銆?)

	if mystic >= 50 and rng.randf() < 0.35:
		lines.append("浣犲惉瑙佷笉灞炰簬褰撳墠鏃跺埢鐨勮交璇紝鍍忓埆澶勫勾浠ｇ殑鍥炲０銆?)
	if scarcity >= 48 and rng.randf() < 0.3:
		lines.append("闄勮繎鍙敤琛ョ粰閫愭笎绋€钖勶紝浣犲紑濮嬫洿棰戠箒璁＄畻鍙ｇ伯銆?)

	if not equipment_inventory.is_empty() and rng.randf() < 0.16:
		var eq: Dictionary = equipment_inventory[max(0, equipment_inventory.size() - 1)]
		lines.append("鑳屽寘閲岀殑銆?s銆嶅伓灏斾笌鍛ㄩ伃鐜鍏遍福锛屾彁閱掍綘瀹冨苟闈炲嚒鐗┿€? % String(eq.get("name", "鏈煡瑁呭")))

	if not creature_codex.is_empty() and rng.randf() < 0.14:
		lines.append("浣犲洖鎯宠捣鍏堝墠閬亣鐨勭敓鐗╀範鎬э紝琛屽姩璺嚎鍥犳鍙戠敓浜嗗井璋冦€?)

	var active_threads: Array[Dictionary] = _active_story_threads()
	if not active_threads.is_empty() and rng.randf() < 0.45:
		active_threads.sort_custom(Callable(self, "_thread_more_urgent"))
		var top: Dictionary = active_threads[0]
		var remain: int = max(0, int(top.get("deadline_h", time_hours + 1)) - time_hours)
		lines.append("銆?s銆嶄粛鍦ㄧ壍鍔ㄤ綘鐨勮矾绾垮垽鏂紙鍘嬪姏%d锛岀害%d灏忔椂鍐呬細澶辨帶锛夈€? % [
			String(top.get("title", "鏈煡浜嬫€?)),
			int(top.get("pressure", 0)),
			remain
		])

	if not memory_beats.is_empty() and rng.randf() < 0.18:
		lines.append("浣犳兂璧?s銆? % memory_beats[memory_beats.size() - 1])

	if lines.is_empty():
		lines.append("椋庢妸鏋濆彾鍘嬩綆锛屾箍鎰忎粠鑻旈潰婕笂鏉ャ€?)

	return " ".join(lines).strip_edges()

# ========== 鏃呰 / 鍒囧尯 ==========
func _travel_to_region(to_region_id: String, hours: int) -> void:
	time_hours += max(0, hours)
	var next_path: String = _resolve_region_path_by_id(to_region_id)
	if next_path == "":
		push_warning("[GameGameWorldGeneration] travel_to_region 鎵句笉鍒?id=%s 鐨勮矾寰? % to_region_id)
		return
	bootstrap(next_path)

func _resolve_region_path_by_id(rid: String) -> String:
	if rid == "" or rid == current_region_id:
		return ""
	var idx_text: String = JsonUtil.read_text("res://data/regions/region_index.json")
	if idx_text == "":
		return ""
	var v: Variant = JsonUtil.parse_any(idx_text)
	if not (v is Dictionary):
		return ""
	var root: Dictionary = v as Dictionary
	var regions_any: Variant = root.get("regions", {})

	# 鍏煎 { "regions": { id: path } }
	if regions_any is Dictionary:
		var mp: Dictionary = regions_any as Dictionary
		return String(mp.get(rid, ""))

	# 鍏煎 { "regions": [ {id, path}, ... ] }
	if regions_any is Array:
		for it in (regions_any as Array):
			if not (it is Dictionary):
				continue
			var d: Dictionary = it as Dictionary
			if String(d.get("id", "")) == rid:
				return String(d.get("path", ""))
	return ""

# ========== 灏忓伐鍏?==========
func _region_pools() -> Dictionary:
	var pools_any: Variant = current_region.get("pools", {})
	if pools_any is Dictionary:
		return pools_any as Dictionary
	return {}

func _weighted_pick(pool: Array) -> Dictionary:
	var sum: float = 0.0
	for it in pool:
		var d: Dictionary = it as Dictionary
		sum += float(d.get("weight", 1.0))
	if sum <= 0.0:
		return {}
	var r: float = rng.randf() * sum
	var acc: float = 0.0
	for it2 in pool:
		var d2: Dictionary = it2 as Dictionary
		acc += float(d2.get("weight", 1.0))
		if r <= acc:
			return d2
	return (pool.back() as Dictionary)

func _pick_one(arr: Array) -> String:
	var n: int = arr.size()
	if n <= 0:
		return ""
	var idx: int = rng.randi_range(0, n - 1)
	return String(arr[idx])

func _pick_one_dict(arr: Array) -> Dictionary:
	var n: int = arr.size()
	if n <= 0:
		return {}
	var idx: int = rng.randi_range(0, n - 1)
	var elem: Variant = arr[idx]
	if elem is Dictionary:
		return (elem as Dictionary).duplicate(true)
	return {}

func _set_flag(k: String, v: bool) -> void:
	flags[k] = v

func _get_flag(k: String) -> bool:
	return bool(flags.get(k, false))

func _add_counter(k: String, inc: int) -> void:
	var cur: int = int(counters.get(k, 0)) + inc
	if cur < 0:
		cur = 0
	counters[k] = cur

func _set_counter(k: String, v: int) -> void:
	counters[k] = max(0, v)

func _get_counter(k: String) -> int:
	return int(counters.get(k, 0))

# 閬垮厤浣跨敤涓庡唴缃嚱鏁板悓鍚嶇殑鍙傛暟锛坢ini/maxi锛夛紝缁熶竴璧拌繖涓す绱у嚱鏁?func _clamp_int(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v

func _add_meter(k: String, inc: int, extra: Dictionary) -> void:
	var cur: int = int(meters.get(k, 0)) + inc
	# 杩欓噷鐨?min/max 鏄瓧鍏搁敭锛屼笉鏄嚱鏁板悕锛屼笉浼氳Е鍙戣鍛?	if extra.has("min"):
		cur = _clamp_int(cur, int(extra["min"]), 999999)
	if extra.has("max"):
		cur = _clamp_int(cur, -999999, int(extra["max"]))
	meters[k] = cur

	# 鎶婂叧閿?meter 鍚屾鍒拌鑹茬湡瀹炵姸鎬侊紝閬垮厤鈥滄樉绀哄彉鍖栦絾鐜╂硶涓嶅彉鈥?	match k:
		"hp":
			hp = cur
		"sanity":
			sanity = cur
		"hunger":
			hunger = cur
		"food":
			hunger = cur
		"sleep":
			sleep_energy = cur
		"fatigue":
			# 鍏煎鏃ф暟鎹細fatigue 璐熷€艰〃绀烘仮澶嶇潯鐪?			sleep_energy += -inc
		"cold":
			cold = cur
		_:
			pass
	_check_player_clamp()

# ========== 鐢熷瓨 / 鐘舵€?==========
func _survival_tick(hours: int) -> void:
	var h: int = max(0, hours)
	var base_hour: int = max(0, time_hours - h)
	for _i in range(h):
		var sim_hour: int = base_hour + _i + 1
		if _get_counter("energy_grace_h") > 0:
			_add_counter("energy_grace_h", -1)
		if _get_counter("force_fine_h") > 0:
			_add_counter("force_fine_h", -1)

		food_tick_h += 1
		sleep_energy -= 1
		hunger -= 1

		# 姣?灏忔椂鑷姩娑堣€?浠藉彛绮紝鎻愬崌6鐐归ケ鑵?		if food_tick_h >= 6:
			food_tick_h = 0
			if ration > 0:
				ration -= 1
				hunger += 6
			else:
				hunger -= 1

		# 鐢熷瓨鍣煶闄嶆潈锛氬彧淇濈暀鏋佺浣庣簿鍔涜交鎯╃綒锛屼富瑕佽浆涓哄墽鎯呰Е鍙?		var energy: int = _energy_value()
		if energy <= 4 and sim_hour % 4 == 0:
			hp -= 1
			sanity -= 1
		elif energy <= 8 and sim_hour % 8 == 0:
			sanity -= 1

		# 瀵掑喎浣滀负浣庨鑳屾櫙鎯╃綒
		if cold > 75 and sim_hour % 8 == 0:
			hp -= 1

		_drift_global_arc("tick", 1)
		_advance_story_threads(1)
		_world_tick_hour()

	_check_player_clamp()
	meters["hp"] = hp
	meters["sanity"] = sanity
	meters["hunger"] = hunger
	meters["sleep"] = sleep_energy
	meters["food"] = hunger
	meters["fatigue"] = max(0, sleep_max - sleep_energy)
	meters["cold"] = cold
	meters["ration"] = ration

func _check_player_clamp() -> void:
	hp = _clamp_int(hp, 0, hp_max)
	sanity = _clamp_int(sanity, 0, sanity_max)
	hunger = _clamp_int(hunger, 0, hunger_max)
	sleep_energy = _clamp_int(sleep_energy, 0, sleep_max)
	ration = _clamp_int(ration, 0, 999)
	cold = _clamp_int(cold, 0, cold_max)

func _check_collapse_text() -> String:
	if hp <= 0:
		_set_flag("run_ended", true)
		_set_flag("end_by_death", true)
		return "浣犲湪婕暱鏃呴€斾腑鍊掍笅锛屽懠鍚哥粓姝㈠湪瀵掗浘閲屻€?
	if sanity <= 0:
		_set_flag("run_ended", true)
		_set_flag("end_by_madness", true)
		return "浣犵殑鐞嗘櫤琚粦鏆楃（绌猴紝涓栫晫鍦ㄤ綘鐪煎墠纰庢垚鏃犳剰涔夌殑鍥炲０銆?
	return ""

func get_player_panel() -> Dictionary:
	var energy: int = _energy_value()
	var energy_max: int = _energy_max()
	var wr: Dictionary = _world_current_region()
	var ctrl: String = String(wr.get("controller", ""))
	var ctrl_name: String = ctrl
	if ctrl != "" and world_factions.has(ctrl):
		var f_any: Variant = world_factions.get(ctrl, {})
		if f_any is Dictionary:
			ctrl_name = String((f_any as Dictionary).get("name", ctrl))
	return {
		"hp": hp,
		"hp_max": hp_max,
		"sanity": sanity,
		"sanity_max": sanity_max,
		"hunger": hunger,
		"hunger_max": hunger_max,
		"sleep": sleep_energy,
		"sleep_max": sleep_max,
		# 鍏煎鐜版湁 HUD 瀛楁鍚?		"food": hunger,
		"food_max": hunger_max,
		"fatigue": sleep_energy,
		"fatigue_max": sleep_max,
		"energy": energy,
		"energy_max": energy_max,
		"cold": cold,
		"cold_max": cold_max,
		"ration": ration,
		"coin": coin,
		"gear_count": equipment_inventory.size(),
		"creature_seen": creature_codex.size(),
		"thread_open": _story_open_count(),
		"world_ctrl": ctrl_name,
		"world_conflict": int(wr.get("conflict", 0)),
		"world_hazard": int(wr.get("hazard", 0)),
		"world_food": int(wr.get("food", 0)),
		"world_water": int(wr.get("water", 0)),
		"traits_count": traits.size(),
		"trait_fragments": trait_fragments,
		"str": stat_str,
		"dex": stat_dex,
		"int": stat_int,
		"cha": stat_cha,
		"con": stat_con,
		"wis": stat_wis
	}

func get_feedback_panel() -> Dictionary:
	var trait_names: Array[String] = []
	for tid_any in traits.keys():
		var tid: String = String(tid_any)
		var def_any: Variant = trait_catalog.get(tid, {})
		if def_any is Dictionary:
			trait_names.append(String((def_any as Dictionary).get("name", tid)))
	var tags: Array[String] = []
	for t in impact_tags:
		tags.append(t)
	for tn in trait_names:
		if tags.size() >= 8:
			break
		if not tags.has(tn):
			tags.append(tn)
	var wr: Dictionary = _world_current_region()
	if not wr.is_empty():
		var ctrl: String = String(wr.get("controller", ""))
		if ctrl != "":
			var fname: String = ctrl
			var f_any: Variant = world_factions.get(ctrl, {})
			if f_any is Dictionary:
				fname = String((f_any as Dictionary).get("name", ctrl))
			if tags.size() < 8:
				tags.append("杈栧尯:" + fname)
		var pressure_tag: String = "鍩熷帇:%d" % int((int(wr.get("conflict", 20)) + int(wr.get("hazard", 20))) / 2)
		if tags.size() < 8:
			tags.append(pressure_tag)
	var echoes: Array[String] = []
	for e in echo_log:
		echoes.append(e)
	if not wr.is_empty():
		echoes.append("涓栫晫鎬佸娍 璧刐%d/%d] 鐢焄%d/%d] 鍐?d" % [
			int(wr.get("food", 50)),
			int(wr.get("water", 50)),
			int(wr.get("flora", 50)),
			int(wr.get("fauna", 50)),
			int(wr.get("conflict", 20))
		])
	while echoes.size() > 3:
		echoes.pop_front()
	return {
		"impact_tags": tags,
		"echo_log": echoes
	}

func get_system_choices() -> Array[Dictionary]:
	return get_action_offers()

func get_action_offers() -> Array[Dictionary]:
	if v02_enabled:
		return _get_action_offers_v02()
	if v01_enabled:
		return _get_action_offers_v01()

	if _get_flag("run_ended"):
		return []
	var cands: Array[Dictionary] = []
	var unslept: int = max(0, sleep_max - sleep_energy)
	var danger: int = int(global_arc.get("danger", 20))
	var mystic: int = int(global_arc.get("mystic", 20))
	var scarcity: int = int(global_arc.get("scarcity", 20))

	var active_threads: Array[Dictionary] = _active_story_threads()
	if not active_threads.is_empty():
		active_threads.sort_custom(Callable(self, "_thread_more_urgent"))
		var top_n: int = min(2, active_threads.size())
		for i in range(top_n):
			var th: Dictionary = active_threads[i]
			var tid: String = String(th.get("id", ""))
			var title: String = String(th.get("title", "鏈煡浜嬫€?))
			var pressure: int = int(th.get("pressure", 0))
			var remain: int = max(0, int(th.get("deadline_h", time_hours + 1)) - time_hours)
			var aid_engage: String = "sys.thread.%s.engage" % tid
			var aid_stabilize: String = "sys.thread.%s.stabilize" % tid
			var aid_exploit: String = "sys.thread.%s.exploit" % tid
			_push_action_candidate(cands, aid_engage, "澶勭悊銆?s銆嶏紙鍘?d锛?dh锛? % [title, pressure, remain], 24 + pressure / 3, _action_ready(aid_engage))
			_push_action_candidate(cands, aid_stabilize, "绋充綇銆?s銆嶏紙鑰楄ˉ缁欙級" % title, 15 + pressure / 4, _action_ready(aid_stabilize) and (ration > 0 or coin > 0))
			_push_action_candidate(cands, aid_exploit, "鍒╃敤銆?s銆嶇墴鍒╋紙澧炲帇锛? % title, 7 + pressure / 5, _action_ready(aid_exploit))

	_push_action_candidate(cands, "sys.observe", "瑙傚療鍥涘懆锛?h锛?, 20, _action_ready("sys.observe"))
	_push_action_candidate(cands, "sys.forage", "閲囬泦璧勬簮锛?h锛?, 20 + scarcity / 4, _action_ready("sys.forage"))
	_push_action_candidate(cands, "sys.hunt", "杩借釜鐢熺墿锛?h锛?, 12 + danger / 4, _action_ready("sys.hunt"))
	_push_action_candidate(cands, "sys.rest", "浼戞伅鎭㈠锛?h锛?, 8 + unslept, _action_ready("sys.rest"))
	_push_action_candidate(cands, "sys.eat", "杩涢鍙ｇ伯锛?6楗辫吂锛屽墿浣?d锛? % ration, 9 + max(0, 22 - hunger), _action_ready("sys.eat") and ration > 0)
	_push_action_candidate(cands, "sys.trap", "甯冪疆闄烽槺锛?h锛屽帇鍒跺嵄闄╋級", 6 + danger / 3, _action_ready("sys.trap") and danger >= 32)
	_push_action_candidate(cands, "sys.meditate", "闈欏惉鍥炲０锛?h锛岀悊鏅烘祦锛?, 6 + mystic / 3, _action_ready("sys.meditate") and mystic >= 28)
	_push_action_candidate(cands, "sys.trade", "涓存椂鎹㈣ˉ缁欙紙閲戝竵->鍙ｇ伯锛?, 6 + scarcity / 3, _action_ready("sys.trade") and coin >= 2)
	_push_action_candidate(cands, "sys.push", "寮鸿鎺ㄨ繘锛?h锛岄珮椋庨櫓锛?, 6 + danger / 2, _action_ready("sys.push"))
	_push_action_candidate(cands, "sys.scout", "渚﹀療閬楄抗锛?h锛屼笉纭畾鏀剁泭锛?, 8 + mystic / 4, _action_ready("sys.scout"))
	if _has_trait("trait.break_negotiation"):
		_push_action_candidate(cands, "sys.leverage", "鍏崇郴鏂藉帇锛?h锛岃浆鍐茬獊涓轰氦鏄擄級", 10 + int(relations.get("patrol", 0)), _action_ready("sys.leverage"))
	if _has_trait("trait.terrain_memory"):
		_push_action_candidate(cands, "sys.reroute", "鍦板舰鏀归亾锛?h锛岄噸缃満浼氭毚闇诧級", 9 + int(exposure_tags.size()), _action_ready("sys.reroute"))
	if _has_trait("trait.rust_crafter") and not equipment_inventory.is_empty():
		_push_action_candidate(cands, "sys.tune_gear", "涓存敼璇嶇紑锛?h锛屽帇鍓綔鐢級", 8, _action_ready("sys.tune_gear"))
	if _has_trait("trait.echo_resonance"):
		_push_action_candidate(cands, "sys.deep_echo", "娣卞眰鍥炲搷锛?h锛屾崲鐪熺浉閽ュ寵锛?, 8 + mystic / 4, _action_ready("sys.deep_echo"))

	var edges_any: Variant = current_region.get("edges", [])
	if edges_any is Array:
		for e_any in (edges_any as Array):
			if not (e_any is Dictionary):
				continue
			var e: Dictionary = e_any as Dictionary
			var to_id: String = String(e.get("to", ""))
			if to_id == "":
				continue
			var h: int = int(e.get("base_hours", 3))
			var aid: String = "sys.travel." + to_id
			_push_action_candidate(cands, aid, "鍓嶅線銆?s銆嶏紙%dh锛? % [to_id, h], 7 + rng.randi_range(0, 2), _action_ready(aid))

	return _pick_action_candidates(cands, 6)

func _push_action_candidate(out: Array, id: String, text: String, weight: int, ok: bool) -> void:
	if not ok:
		return
	var decay: float = pow(0.82, float(int(counters.get("act_used_" + id, 0))))
	out.append({
		"id": id,
		"text": text,
		"weight": max(1.0, float(weight) * decay)
	})

func _pick_action_candidates(cands: Array, count: int) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	var work: Array = cands.duplicate(true)
	var n: int = min(count, work.size())
	for _i in range(n):
		var p: Dictionary = _weighted_pick(work)
		if p.is_empty():
			break
		res.append({
			"id": String(p.get("id", "")),
			"text": String(p.get("text", "")),
			"weight": float(p.get("weight", 1.0))
		})
		# remove picked id
		var pid: String = String(p.get("id", ""))
		var next_work: Array = []
		for it in work:
			if not (it is Dictionary):
				continue
			var d: Dictionary = it as Dictionary
			if String(d.get("id", "")) != pid:
				next_work.append(d)
		work = next_work
	return res

func _action_ready(id: String) -> bool:
	return time_hours >= int(action_cooldowns.get(id, 0))

func _set_action_cd(id: String, hours: int) -> void:
	action_cooldowns[id] = time_hours + max(1, hours)

func apply_system_choice(choice_id: String) -> Dictionary:
	if v02_enabled:
		var out_v02: Dictionary = _apply_system_choice_v02(choice_id)
		if bool(out_v02.get("handled", false)):
			out_v02.erase("handled")
			return out_v02
	if v01_enabled:
		var out_v01: Dictionary = _apply_system_choice_v01(choice_id)
		if bool(out_v01.get("handled", false)):
			out_v01.erase("handled")
			return out_v01

	if _get_flag("run_ended"):
		return _action_result("鏃呯▼宸茬粡缁撴潫銆?)

	if choice_id.begins_with("sys.module."):
		return _apply_module_action(choice_id)

	if choice_id.begins_with("sys.thread."):
		return _apply_story_thread_action(choice_id)

	if choice_id.begins_with("sys.world."):
		return _apply_world_reaction_action(choice_id)

	if choice_id == "sys.observe":
		_mark_action_used(choice_id, 1)
		time_hours += 1
		_survival_tick(1)
		var msg: String = _compose_hourly_paragraph()
		_expose_tags(["trail", "wild"], 0.9)
		if rng.randf() < 0.35:
			_add_counter("insight", 1)
			msg += " 浣犳敞鎰忓埌涓€浜涙鍓嶅拷鐣ョ殑绾跨储銆?
		var arc_evt: String = _run_global_state_event(true)
		if arc_evt != "":
			msg += "\n" + arc_evt
		_world_apply_player_action("observe", 1)
		return _action_result(msg)

	if choice_id == "sys.forage":
		_mark_action_used(choice_id, 2)
		time_hours += 1
		_survival_tick(1)
		var pools: Dictionary = _region_pools()
		var fl_any: Variant = pools.get("flora", [])
		var got: String = "浣犲湪娼箍鍦伴潰涓婃悳瀵伙紝浣嗘敹鑾蜂笉澶氥€?
		if fl_any is Array and not (fl_any as Array).is_empty():
			var fl: Dictionary = _pick_one_dict(fl_any as Array)
			var fl_name: String = String(fl.get("name", fl.get("id", "鏈煡妞嶇墿")))
			got = "浣犻噰鍒般€?s銆嶃€? % fl_name
			inventory_add(fl.get("id", "unknown_flora"), 1)
			if rng.randf() < 0.55:
				ration += 1
				got += " 浣犲鐞嗘垚浜嗗彲淇濆瓨鍙ｇ伯锛堝彛绮?1锛夈€?
			if rng.randf() < 0.12:
				var eq_msg: String = _try_generate_equipment("forage")
				if eq_msg != "":
					got += "\n" + eq_msg
		_drift_global_arc("forage", 1)
		_expose_tags(["supply", "wild", "water"], 1.2)
		_world_apply_player_action("forage", 1)
		return _action_result(got)

	if choice_id == "sys.hunt":
		_mark_action_used(choice_id, 3)
		time_hours += 2
		_survival_tick(2)
		var pools2: Dictionary = _region_pools()
		var fa_any: Variant = pools2.get("fauna", pools2.get("creatures", []))
		if not (fa_any is Array) or (fa_any as Array).is_empty():
			return _action_result("浣犺拷韪簡寰堜箙锛屽嵈娌℃湁鍙戠幇鏄庢樉韪抗銆?)
		var fa: Dictionary = _pick_one_dict(fa_any as Array)
		var variant: Dictionary = _roll_creature_variant(fa)
		var fa_name: String = String(variant.get("name", fa.get("name", fa.get("id", "鏈煡鐢熺墿"))))
		var danger: int = int(variant.get("danger", 3))
		var hit: float = 0.34 + float(stat_dex + stat_wis + stat_str) / 60.0 - float(danger) * 0.03
		if rng.randf() <= clamp(hit, 0.12, 0.9):
			var gain: int = 1 + int(rng.randi_range(1, 2))
			ration += gain
			coin += 1
			_drift_global_arc("hunt_win", 1)
			var loot_desc: String = _join_loot_tags(variant)
			var hunt_text: String = "浣犳垚鍔熺嫨鐚庡埌銆?s銆嶏紝鑾峰緱鍙ｇ伯+%d銆?s" % [fa_name, gain, loot_desc]
			if rng.randf() < 0.18:
				var eq_text: String = _try_generate_equipment("hunt")
				if eq_text != "":
					hunt_text += "\n" + eq_text
			_expose_tags(["predator", "wild"], 1.5)
			_world_apply_player_action("hunt", 1)
			return _action_result(hunt_text)
		hp = max(0, hp - (2 + int(danger / 2)))
		sanity = max(0, sanity - 1)
		_drift_global_arc("hunt_fail", 1)
		_expose_tags(["predator", "wild"], 1.2)
		_world_apply_player_action("hunt", 1)
		return _action_result("浣犲湪杩借釜銆?s銆嶆椂鍙嶈閫奸€€锛屽彈浜嗕激銆? % fa_name)

	if choice_id == "sys.rest":
		_mark_action_used(choice_id, 4)
		time_hours += 7
		_survival_tick(7)
		var rec: int = 8 + int(stat_con / 3)
		hp = min(hp_max, hp + rec)
		sanity = min(sanity_max, sanity + 6)
		sleep_energy = min(sleep_max, sleep_energy + 28)
		hunger = min(hunger_max, hunger + 6)
		cold = min(cold_max, cold + 2)
		_set_counter("energy_grace_h", 30)
		_set_counter("force_fine_h", 16)
		_check_player_clamp()
		_drift_global_arc("rest", 1)
		_expose_tags(["survival"], 0.6)
		_world_apply_player_action("rest", 1)
		return _action_result("浣犱紤鎭簡涓€娈垫椂闂达紝鎭㈠浜嗕綋鍔涗笌鐞嗘櫤銆?)

	if choice_id == "sys.eat":
		_mark_action_used(choice_id, 1)
		if ration <= 0:
			return _action_result("浣犵炕閬嶈鍥婏紝鍗村凡缁忔病鏈夊彛绮€?)
		ration -= 1
		hunger = min(hunger_max, hunger + 6)
		hp = min(hp_max, hp + 3)
		sanity = min(sanity_max, sanity + 2)
		_check_player_clamp()
		_expose_tags(["supply"], 0.8)
		return _action_result("浣犲悆鎺変簡涓€浠藉彛绮紝鐘舵€佺◢鏈夊ソ杞€?)

	if choice_id == "sys.trap":
		_mark_action_used(choice_id, 4)
		time_hours += 2
		_survival_tick(2)
		var success: float = 0.45 + float(stat_wis + stat_dex) / 55.0
		if rng.randf() <= clamp(success, 0.15, 0.92):
			global_arc["danger"] = max(0, int(global_arc.get("danger", 20)) - 8)
			_expose_tags(["predator", "wild"], 1.0)
			return _action_result("浣犲湪鏋楅棿甯冧笅闄烽槺锛屽懆杈瑰▉鑳佹殏鏃朵笅闄嶃€?)
		hp = max(0, hp - 2)
		_expose_tags(["predator", "wild"], 0.9)
		return _action_result("闄烽槺甯冭澶辫触锛屼綘鍙嶈€岃鏈哄叧鎿︿激銆?)

	if choice_id == "sys.meditate":
		_mark_action_used(choice_id, 2)
		time_hours += 1
		_survival_tick(1)
		var gain: int = 2 + int(stat_wis / 6)
		sanity = min(sanity_max, sanity + gain)
		_expose_tags(["echo", "ruin"], 1.2)
		_world_apply_player_action("meditate", 1)
		if rng.randf() < 0.28:
			var eqm: String = _try_generate_equipment("echo")
			if eqm != "":
				return _action_result("浣犲湪鍥炲０涓崟鎹夊埌涓€娈靛け钀借蹇嗐€俓n" + eqm)
		return _action_result("浣犳妸鍛煎惛鍘嬪埌鏈€杞伙紝蹇冪閫愭绋冲畾锛堢悊鏅?%d锛夈€? % gain)

	if choice_id == "sys.trade":
		_mark_action_used(choice_id, 3)
		if coin < 2:
			return _action_result("浣犵炕浜嗙炕閽辫锛屽彂鐜伴噾甯佷笉瓒炽€?)
		coin -= 2
		ration += 2
		global_arc["scarcity"] = max(0, int(global_arc.get("scarcity", 20)) - 4)
		relations["grey_market"] = int(relations.get("grey_market", 0)) + 1
		_expose_tags(["town", "supply", "faction"], 1.1)
		_world_apply_player_action("trade", 1)
		return _action_result("浣犱笌璺繃琛屽晢浜ゆ崲浜嗚ˉ缁欙紙鍙ｇ伯+2锛岄噾甯?2锛夈€?)

	if choice_id == "sys.push":
		_mark_action_used(choice_id, 3)
		time_hours += 2
		_survival_tick(2)
		var risk: int = 2 + int(global_arc.get("danger", 20) / 20)
		hp = max(0, hp - risk)
		sanity = max(0, sanity - 2)
		_drift_global_arc("travel", 1)
		_expose_tags(["trail", "war", "wild"], 1.4)
		_world_apply_player_action("push", 1)
		if rng.randf() < 0.22:
			var push_eq: String = _try_generate_equipment("push")
			if push_eq != "":
				return _action_result("浣犲己琛岀┛瓒婇珮椋庨櫓璺緞锛屼粯鍑轰唬浠蜂絾鎶㈠埌浜嗘満浼氥€俓n" + push_eq)
		return _action_result("浣犲己琛屾帹杩涗簡璺▼锛屼絾鐘舵€佹槑鏄句笅婊戙€?)

	if choice_id == "sys.scout":
		_mark_action_used(choice_id, 3)
		time_hours += 2
		_survival_tick(2)
		var scout_roll: float = 0.35 + float(stat_wis + stat_int) / 70.0
		_expose_tags(["ruin", "trail", "faction"], 1.2)
		_world_apply_player_action("scout", 1)
		if rng.randf() <= clamp(scout_roll, 0.12, 0.9):
			var coin_gain: int = rng.randi_range(1, 3)
			coin += coin_gain
			if rng.randf() < 0.25:
				var sc_eq: String = _try_generate_equipment("scout")
				if sc_eq != "":
					return _action_result("浣犲湪閬楄抗杈圭紭鎵惧埌鍙敤鐗╄祫锛堥噾甯?%d锛夈€俓n%s" % [coin_gain, sc_eq])
			return _action_result("浣犱睛瀵熷悗甯﹀洖浜嗗彲鐢ㄦ儏鎶ヤ笌鐗╄祫锛堥噾甯?%d锛夈€? % coin_gain)
		sanity = max(0, sanity - 2)
		_drift_global_arc("hunt_fail", 1)
		return _action_result("渚﹀療杩囩▼涓伃閬囧共鎵帮紝浣犺杩挙鍥炪€?)

	if choice_id == "sys.leverage":
		_mark_action_used(choice_id, 2)
		time_hours += 1
		_survival_tick(1)
		relations["patrol"] = int(relations.get("patrol", 0)) + 1
		relations["grey_market"] = int(relations.get("grey_market", 0)) + 1
		global_arc["order"] = _clamp_int(int(global_arc.get("order", 40)) + 3, 0, 100)
		_expose_tags(["faction", "town"], 1.4)
		_echo_world("涓栫晫鍥炲搷锛氫綘鐨勮瘽璇柟寮忚杈瑰灏忓湀瀛愯浣忋€?)
		_world_apply_player_action("leverage", 1)
		return _action_result("浣犵敤鍏崇郴鍜岃瘽鏈妸娼滃湪鍐茬獊鏀瑰啓鎴愪簡鍙皥鏉′欢銆?)

	if choice_id == "sys.reroute":
		_mark_action_used(choice_id, 2)
		time_hours += 1
		_survival_tick(1)
		_decay_exposure(0.6)
		_expose_tags(["trail", "ruin", "water"], 0.8)
		_echo_world("涓栫晫鍥炲搷锛氫綘鏀瑰啓浜嗚矾寰勬毚闇诧紝鍚庣画鏈轰細姹犲彂鐢熷亸绉汇€?)
		_world_apply_player_action("reroute", 1)
		return _action_result("浣犳寜鍦板舰璁板繂閲嶆帓浜嗚矾绾匡紝涓嬩竴鎵规満浼氬皢鍋忓悜鏂板湴甯︺€?)

	if choice_id == "sys.tune_gear":
		_mark_action_used(choice_id, 2)
		time_hours += 1
		_survival_tick(1)
		if equipment_inventory.is_empty():
			return _action_result("浣犳殏鏃舵病鏈夊彲璋冩牎鐨勮澶囥€?)
		var idx_last: int = equipment_inventory.size() - 1
		var eq: Dictionary = equipment_inventory[idx_last]
		var mods_any: Variant = eq.get("mods", {})
		if mods_any is Dictionary:
			var mods: Dictionary = mods_any as Dictionary
			for k_any in mods.keys():
				var k: String = String(k_any)
				var v: int = int(mods[k])
				if v < 0:
					mods[k] = int(round(float(v) * 0.5))
			eq["mods"] = mods
			equipment_inventory[idx_last] = eq
		return _action_result("浣犲瑁呭鍋氫簡鐜板満璋冩牎锛屽壇浣滅敤琚帇浣庛€?)

	if choice_id == "sys.deep_echo":
		_mark_action_used(choice_id, 2)
		time_hours += 1
		_survival_tick(1)
		sanity = max(0, sanity - 1)
		_add_counter("clue_key", 2)
		_expose_tags(["echo", "ruin"], 1.5)
		_echo_world("涓栫晫鍥炲搷锛氫綘鍦ㄥ洖澹板眰鐣欎笅浜嗗彲杩借釜鐨勫嵃璁般€?)
		_world_apply_player_action("deep_echo", 1)
		if rng.randf() < 0.22:
			var eq_deep: String = _try_generate_equipment("deep_echo")
			if eq_deep != "":
				return _action_result("浣犱粠娣卞眰鍥炲０甯﹀洖浜嗗畬鏁寸嚎绱€俓n%s" % eq_deep)
		return _action_result("浣犱笅鎺㈠洖澹板眰锛屾嬁鍒颁簡鍙敤浜庨珮浠峰€煎垎鏀殑閽ュ寵銆?)

	if choice_id.begins_with("sys.travel."):
		_mark_action_used(choice_id, 2)
		var from_region: String = current_region_id
		var to_id: String = choice_id.trim_prefix("sys.travel.")
		var edge_h: int = 3
		var edges_any2: Variant = current_region.get("edges", [])
		if edges_any2 is Array:
			for e2_any in (edges_any2 as Array):
				if not (e2_any is Dictionary):
					continue
				var e2: Dictionary = e2_any as Dictionary
				if String(e2.get("to", "")) == to_id:
					edge_h = int(e2.get("base_hours", 3))
					break
		_survival_tick(edge_h)
		_travel_to_region(to_id, edge_h)
		_drift_global_arc("travel", 1)
		var travel_tags: Array = _derive_travel_tags(to_id)
		_expose_tags(travel_tags, 1.6)
		_world_apply_player_action("travel", 1, {"rid": from_region})
		return _action_result("浣犳部鐫€鏃ц矾鍓嶅線涓嬩竴涓尯鍩熴€?)

	return _action_result("浣犵姽璞簡涓€浼氬効锛屾殏鏃舵病鏈夎鍔ㄣ€?)

func _mark_action_used(id: String, cd_hours: int) -> void:
	_add_counter("act_used_" + id, 1)
	_set_action_cd(id, cd_hours)

func inventory_add(id_any: Variant, q: int=1) -> void:
	var key: String = String(id_any)
	if key == "":
		return
	var cur: int = int(counters.get("inv_" + key, 0))
	counters["inv_" + key] = cur + max(1, q)

func _action_result(text: String) -> Dictionary:
	if v01_enabled:
		v01_turn_count += 1
		v01_turns_since_weird += 1
		_v01_process_time_drift()
	_check_player_clamp()
	var collapse_text: String = _check_collapse_text()
	_sync_shared_state()
	if collapse_text != "":
		return {"text": collapse_text}
	return {"text": text}

func _energy_max() -> int:
	return max(1, min(hunger_max, sleep_max))

func _energy_value() -> int:
	return int(round((float(hunger) + float(sleep_energy)) * 0.5))

func _current_tension() -> int:
	var t: float = 0.0
	t += float(global_arc.get("danger", 20)) * 0.35
	t += float(global_arc.get("war", 12)) * 0.25
	t += float(global_arc.get("scarcity", 20)) * 0.25
	var wr: Dictionary = _world_current_region()
	if not wr.is_empty():
		t += float(wr.get("conflict", 20)) * 0.20
		t += float(wr.get("hazard", 20)) * 0.18
	t += float(max(0, _highest_open_thread_pressure() - 20)) * 0.45
	if _story_open_count() >= 2:
		t += 8.0
	if _energy_value() <= 16:
		t += 10.0
	return int(clamp(t, 0.0, 100.0))

func _highest_open_thread_pressure() -> int:
	var mx: int = 0
	for th in story_threads:
		if String(th.get("state", "open")) != "open":
			continue
		mx = max(mx, int(th.get("pressure", 0)))
	return mx

func _choose_time_step() -> int:
	if _get_counter("force_fine_h") > 0:
		return 1 if _current_tension() >= 45 else 2

	var energy_now: int = _energy_value()
	if energy_now <= 12:
		return 1 if _current_tension() >= 40 else 2
	if energy_now <= 20:
		return 2 if _current_tension() >= 45 else 4

	if ration <= 0:
		return 2 if _current_tension() >= 40 else 4
	if ration <= 2:
		return 2 if _current_tension() >= 50 else 6

	var tension: int = _current_tension()
	if tension >= 60:
		return 1
	if tension >= 38:
		return 2
	if _story_open_count() == 0 and tension < 30:
		return rng.randi_range(12, 24)
	return rng.randi_range(6, 12)

func _build_montage_summary(step_h: int) -> String:
	var tag: String = _dominant_exposure_tag()
	var day_span: String = "%dh" % step_h
	var line: String = "浣犲湪%s閲岀┛杩囦簡鏃犳暟閲嶅鍦拌矊锛岀洿鍒版柊鐨勬満浼氬嚭鐜般€? % day_span
	match tag:
		"ruin":
			line = "浣犳部鐫€娈嬬鍜屽澧欏揩閫熸帹杩涗簡%s锛岃繙澶勯仐杩规椿鍔ㄥ彉寰楁竻鏅般€? % day_span
		"town":
			line = "浣犵┛杩囬浂鏁ｈ仛钀芥帹杩涗簡%s锛屼氦鏄撻澹板紑濮嬭仛鎷㈠埌浣犺韩杈广€? % day_span
		"wild":
			line = "浣犲湪鑽掗噹閲岃繛缁刀璺?s锛岄鍚戝拰鍏借抗閮藉湪鎻愮ず灞€鍔垮彉鍖栥€? % day_span
		"water":
			line = "浣犳部姘寸嚎鐤捐浜?s锛岃ˉ缁欏拰鍐茬獊鐨勮抗璞″悓鏃舵诞鐜般€? % day_span
		_:
			pass
	return "[color=gray]%s[/color]" % line

func _merge_event_text(montage: String, body: String) -> String:
	if montage == "":
		return body
	if body == "":
		return montage
	return montage + "\n" + body

func _dominant_exposure_tag() -> String:
	var best_tag: String = ""
	var best_val: float = -9999.0
	for k in exposure_tags.keys():
		var v: float = float(exposure_tags[k])
		if v > best_val:
			best_val = v
			best_tag = String(k)
	return best_tag

func _decay_exposure(factor: float=0.92) -> void:
	var keys: Array = exposure_tags.keys()
	for k_any in keys:
		var k: String = String(k_any)
		var v: float = float(exposure_tags.get(k, 0.0)) * factor
		if absf(v) < 0.05:
			exposure_tags.erase(k)
		else:
			exposure_tags[k] = v

func _expose_tags(tags: Array, amount: float=1.0) -> void:
	for t_any in tags:
		var t: String = String(t_any)
		if t == "":
			continue
		exposure_tags[t] = float(exposure_tags.get(t, 0.0)) + amount

func _maybe_spawn_energy_incident() -> String:
	if _get_counter("energy_grace_h") > 0:
		return ""

	var energy: int = _energy_value()
	if energy > 10:
		return ""
	if time_hours - last_energy_incident_h < 30:
		return ""
	if has_pending_choice():
		return ""

	last_energy_incident_h = time_hours
	_pending_choices.clear()
	_pending_choices.append({
		"id":"energy_rest",
		"text":"绋充綇鍛煎惛浼戞暣锛堜繚瀹堬紝鑰楁椂锛?,
		"system_action":"sys.rest"
	})
	_pending_choices.append({
		"id":"energy_push",
		"text":"鍜墮纭帹锛堥珮椋庨櫓锛屼繚杩涘害锛?,
		"system_action":"sys.push"
	})
	_pending_choices.append({
		"id":"energy_tradeoff",
		"text":"鍚冨彛绮崲娓呴啋锛堣祫婧愭崲绋冲畾锛?,
		"system_action":"sys.eat"
	})
	_has_pending = true
	return "绮惧姏閫艰繎闃堝€硷紝浣犲嚭鐜颁簡鏄庢樉鐨勫垽鏂紓绉汇€傜户缁‖璧颁細寮曞彂杩為攣鍚庢灉銆俓n[color=orange]鍏抽敭鎶夋嫨宸茶嚜鍔ㄥ脊鍑猴紝璇风洿鎺ラ€夋嫨銆俒/color]"

func _maybe_offer_situation(force: bool=false) -> String:
	if has_pending_choice():
		return ""
	var module: Dictionary = _pick_situation_module(force)
	if module.is_empty():
		return ""

	module_nonce += 1
	var ticket: String = "m%04d" % module_nonce
	var ctx: Dictionary = _build_module_context(module, ticket)
	module_tickets[ticket] = ctx

	_pending_choices.clear()
	var options: Array = module.get("options", [])
	for op_any in options:
		if not (op_any is Dictionary):
			continue
		var op: Dictionary = op_any as Dictionary
		var oid: String = String(op.get("id", "steady"))
		var label: String = _module_option_label(module, op)
		_pending_choices.append({
			"id":"module_%s_%s" % [ticket, oid],
			"text": label,
			"system_action":"sys.module.%s.%s" % [ticket, oid]
		})

	var trait_op: Dictionary = _module_trait_option(module)
	if not trait_op.is_empty():
		var toid: String = String(trait_op.get("id", "trait_bonus"))
		var tlabel: String = _module_option_label(module, trait_op)
		_pending_choices.append({
			"id":"module_%s_%s" % [ticket, toid],
			"text": tlabel,
			"system_action":"sys.module.%s.%s" % [ticket, toid]
		})
	_has_pending = true

	var intro: String = String(ctx.get("intro", "浣犻亣鍒版柊鐨勫眬鍔胯妭鐐广€?))
	return intro + "\n[color=orange]鏈轰細鎶夋嫨宸茶嚜鍔ㄥ脊鍑恒€俒/color]"

func _module_option_label(module: Dictionary, op: Dictionary) -> String:
	var risk: String = String(op.get("risk", "浣?))
	var reward: String = String(op.get("reward", "涓?))
	var cost_h: int = int(op.get("cost_h", 1))
	var base_label: String = String(op.get("label", "澶勭悊"))
	var conflict: String = String(module.get("conflict", "survival"))
	if conflict == "negotiation" and base_label == "鏂藉帇鍗氬紙" and int(relations.get("patrol", 0)) > 0:
		base_label = "鏂藉帇鍗氬紙(浜鸿剦鍔犳垚)"
	if String(op.get("id", "")).begins_with("trait_"):
		base_label = "[鐗硅川] " + base_label
	return "%s锛堥櫓%s/鐩?s/%dh锛? % [base_label, risk, reward, cost_h]

func _module_trait_option(module: Dictionary) -> Dictionary:
	var tags_any: Variant = module.get("tags", [])
	var tags: Array = tags_any as Array if tags_any is Array else []
	var conflict: String = String(module.get("conflict", "survival"))
	if conflict == "negotiation" and _has_trait("trait.break_negotiation"):
		return {"id":"trait_leverage", "label":"鍘嬩环鍋滅伀", "risk":"涓?, "reward":"楂?, "cost_h":1, "energy_cost":1, "success_base":72}
	if _has_trait("trait.echo_resonance") and "echo" in tags:
		return {"id":"trait_truth", "label":"杩介棶鐪熺浉", "risk":"涓?, "reward":"楂?, "cost_h":1, "energy_cost":1, "success_base":70}
	if _has_trait("trait.hunter_mark") and "predator" in tags:
		return {"id":"trait_ambush", "label":"棰勫垽浼忓嚮", "risk":"涓?, "reward":"楂?, "cost_h":1, "energy_cost":1, "success_base":74}
	if _has_trait("trait.terrain_memory") and "trail" in tags:
		return {"id":"trait_reroute", "label":"鏀归亾鏆撮湶", "risk":"浣?, "reward":"涓?, "cost_h":1, "energy_cost":0, "success_base":78}
	return {}

func _pick_situation_module(force: bool) -> Dictionary:
	if situation_modules.is_empty():
		return {}
	var tension: int = _current_tension()
	var pool: Array = []
	for m_any in situation_modules:
		if not (m_any is Dictionary):
			continue
		var m: Dictionary = m_any as Dictionary
		if not _module_gate_ok(m, tension):
			continue
		var w: float = _module_weight(m, tension)
		if w <= 0.01:
			continue
		pool.append({"event": m, "weight": w})
	if pool.is_empty():
		return {}
	if not force and rng.randf() > clamp(0.34 + float(tension) / 200.0, 0.28, 0.78):
		return {}
	var picked: Dictionary = _weighted_pick(pool)
	var ev_any: Variant = picked.get("event", {})
	return ev_any as Dictionary if ev_any is Dictionary else {}

func _module_gate_ok(module: Dictionary, tension: int) -> bool:
	var gate_any: Variant = module.get("gate", {})
	if not (gate_any is Dictionary):
		return true
	var gate: Dictionary = gate_any as Dictionary
	if gate.has("tension_min") and tension < int(gate["tension_min"]):
		return false
	if gate.has("tension_max") and tension > int(gate["tension_max"]):
		return false
	if gate.has("danger_min") and int(global_arc.get("danger", 20)) < int(gate["danger_min"]):
		return false
	if gate.has("war_min") and int(global_arc.get("war", 12)) < int(gate["war_min"]):
		return false
	if gate.has("scarcity_min") and int(global_arc.get("scarcity", 20)) < int(gate["scarcity_min"]):
		return false
	if gate.has("mystic_min") and int(global_arc.get("mystic", 20)) < int(gate["mystic_min"]):
		return false
	if gate.has("energy_max") and _energy_value() > int(gate["energy_max"]):
		return false
	if bool(gate.get("needs_equipment", false)) and equipment_inventory.is_empty():
		return false
	if bool(gate.get("relation_or_debt", false)):
		if int(relations.get("grey_market", 0)) <= 0 and int(counters.get("debt_open", 0)) <= 0:
			return false
	if gate.has("thread_kind"):
		var tk: String = String(gate.get("thread_kind", ""))
		if tk != "" and not _has_open_thread_kind(tk):
			return false
	return true

func _module_weight(module: Dictionary, tension: int) -> float:
	var w: float = 10.0 + float(tension) * 0.06
	var wr: Dictionary = _world_current_region()
	var tags_any: Variant = module.get("tags", [])
	if tags_any is Array:
		for tg_any in (tags_any as Array):
			var tg: String = String(tg_any)
			w += float(exposure_tags.get(tg, 0.0)) * 1.8
			w += _trait_bias_for_tag(tg)
			match tg:
				"wild", "predator":
					w += float(global_arc.get("danger", 20)) * 0.05
				"echo", "ruin":
					w += float(global_arc.get("mystic", 20)) * 0.05
				"supply":
					w += float(global_arc.get("scarcity", 20)) * 0.04
				"war":
					w += float(global_arc.get("war", 12)) * 0.06
				"town", "faction":
					w += float(global_arc.get("order", 40)) * 0.03
				_:
					pass
			if not wr.is_empty():
				match tg:
					"supply":
						w += max(0.0, 30.0 - float(wr.get("food", 50))) * 0.22
						w += max(0.0, 30.0 - float(wr.get("water", 50))) * 0.20
					"faction", "war":
						w += float(wr.get("conflict", 20)) * 0.12
					"wild", "predator":
						w += float(wr.get("hazard", 20)) * 0.10
					"echo":
						w += float(wr.get("mystic", 20)) * 0.10
					_:
						pass
	return max(0.1, w)

func _trait_bias_for_tag(tag: String) -> float:
	var bonus: float = 0.0
	for tid_any in traits.keys():
		var tid: String = String(tid_any)
		var def_any: Variant = trait_catalog.get(tid, {})
		if not (def_any is Dictionary):
			continue
		var def: Dictionary = def_any as Dictionary
		var arr_any: Variant = def.get("bias_tags", [])
		if arr_any is Array:
			for t_any in (arr_any as Array):
				if String(t_any) == tag:
					bonus += 1.8
	return bonus

func _build_module_context(module: Dictionary, ticket: String) -> Dictionary:
	var intro_tpl: String = String(module.get("intro", "浣犻亣鍒版柊鐨勫眬鍔胯妭鐐广€?))
	var ctx: Dictionary = {
		"ticket": ticket,
		"module_id": String(module.get("id", "sm00")),
		"module": module.duplicate(true),
		"intro": _render_module_intro(intro_tpl),
		"opened_h": time_hours
	}
	return ctx

func _render_module_intro(tpl: String) -> String:
	var out: String = tpl
	out = out.replace("{place}", _pick_pool_name(["sublocations"], "鍓嶆柟鍦板甫"))
	out = out.replace("{water}", _pick_pool_name(["water", "sublocations"], "娌垮哺"))
	out = out.replace("{town}", "涓存椂闆嗗競")
	out = out.replace("{faction_name}", _pick_faction_name())
	out = out.replace("{echo_site}", _pick_pool_name(["sublocations"], "闆句腑鍥炲０鐐?))
	out = out.replace("{patrol_mark}", "宸＄伅鍝?)
	out = out.replace("{predator_name}", _pick_pool_name(["fauna", "creatures"], "闄岀敓鐚庣墿"))
	out = out.replace("{war_site}", _pick_pool_name(["sublocations"], "鏃ф垬鍦?))
	return out

func _pick_faction_name() -> String:
	var names: Array[String] = ["宸＄伅浜?, "鐏板競璺戠嚎瀹?, "杈瑰绋芥牳闃?, "閬楄抗鎺樺彇闃?]
	return names[rng.randi_range(0, names.size() - 1)]

func _derive_travel_tags(to_id: String) -> Array:
	var lid: String = to_id.to_lower()
	var tags: Array = ["trail"]
	if "ruin" in lid or "閬楄抗" in to_id or "纰庢槦" in to_id:
		tags.append("ruin")
		tags.append("war")
	elif "lake" in lid or "婀? in to_id or "婀? in to_id:
		tags.append("water")
		tags.append("supply")
	elif "forest" in lid or "妫? in to_id or "鏋? in to_id:
		tags.append("wild")
		tags.append("predator")
	elif "town" in lid or "鍩? in to_id or "娓? in to_id:
		tags.append("town")
		tags.append("faction")
	else:
		tags.append("wild")
	return tags

func _apply_module_action(choice_id: String) -> Dictionary:
	var parts: PackedStringArray = choice_id.split(".")
	if parts.size() < 4:
		return _action_result("灞€鍔跨獥鍙ｅ凡鍋忕Щ銆?)
	var ticket: String = parts[2]
	var opt_id: String = parts[3]
	if not module_tickets.has(ticket):
		return _action_result("杩欎釜鏈轰細宸茬粡閿欒繃銆?)
	var ctx_any: Variant = module_tickets.get(ticket, {})
	if not (ctx_any is Dictionary):
		module_tickets.erase(ticket)
		return _action_result("浣犳病鑳芥姄浣忚繖涓獥鍙ｃ€?)
	var ctx: Dictionary = ctx_any as Dictionary
	var module_any: Variant = ctx.get("module", {})
	if not (module_any is Dictionary):
		module_tickets.erase(ticket)
		return _action_result("灞€鍔垮凡澶辨晥銆?)
	var module: Dictionary = module_any as Dictionary
	var options_any: Variant = module.get("options", [])
	var opt: Dictionary = {}
	if options_any is Array:
		for op_any in (options_any as Array):
			if not (op_any is Dictionary):
				continue
			var d: Dictionary = op_any as Dictionary
			if String(d.get("id", "")) == opt_id:
				opt = d
				break
	if opt.is_empty():
		var trait_opt: Dictionary = _module_trait_option(module)
		if not trait_opt.is_empty() and String(trait_opt.get("id", "")) == opt_id:
			opt = trait_opt
		else:
			module_tickets.erase(ticket)
			return _action_result("鍙墽琛岄€夐」宸茬粡鍏抽棴銆?)

	module_tickets.erase(ticket)
	var cost_h: int = max(0, int(opt.get("cost_h", 1)))
	var energy_cost: int = max(0, int(opt.get("energy_cost", 0)))
	if cost_h > 0:
		_mark_action_used(choice_id, max(1, cost_h))
		time_hours += cost_h
		_survival_tick(cost_h)
	if energy_cost > 0:
		hunger -= energy_cost
		sleep_energy -= energy_cost

	var style: String = String(opt.get("id", "steady"))
	var success: bool = true
	if style != "retreat":
		var rate: float = _module_success_rate(module, opt)
		success = rng.randf() <= rate

	var text: String = ""
	if success:
		text = _module_success_text(module, opt)
	else:
		text = _module_fail_text(module, opt)
	_world_apply_module_outcome(module, style, success)
	_register_module_reverb(module, style, success)
	_on_event_node_resolved(String(module.get("id", "sm00")), style, success)

	var echo_mark: String = "%s.%s.%s" % [String(module.get("id", "sm00")), style, "ok" if success else "fail"]
	_echo_world("鍥炲搷锛?s" % echo_mark)
	_expose_tags(module.get("tags", []), 0.9 if success else 0.4)
	_decay_exposure(0.96)
	return _action_result(text)

func _module_success_rate(module: Dictionary, opt: Dictionary) -> float:
	var base: float = float(opt.get("success_base", 60)) / 100.0
	var conflict: String = String(module.get("conflict", "survival"))
	var stat_bonus: float = 0.0
	match conflict:
		"negotiation":
			stat_bonus = float(stat_cha + stat_wis) / 220.0
		"combat":
			stat_bonus = float(stat_str + stat_dex + stat_con) / 260.0
		"stealth":
			stat_bonus = float(stat_dex + stat_wis) / 240.0
		"explore":
			stat_bonus = float(stat_int + stat_wis + stat_dex) / 280.0
		_:
			stat_bonus = float(stat_con + stat_wis) / 250.0

	if _has_trait("trait.track_reading") and conflict in ["explore", "stealth"]:
		stat_bonus += 0.08
	if _has_trait("trait.break_negotiation") and conflict == "negotiation":
		stat_bonus += 0.08
	if _has_trait("trait.hunter_mark") and conflict == "combat":
		stat_bonus += 0.06
	var tags_any: Variant = module.get("tags", [])
	if _has_trait("trait.echo_resonance") and tags_any is Array and "echo" in (tags_any as Array):
		stat_bonus += 0.08

	var tension_penalty: float = float(_current_tension()) / 220.0
	var style: String = String(opt.get("id", "steady"))
	if style == "gamble":
		base -= 0.12
	elif style.begins_with("trait_"):
		base += 0.08
	elif style == "retreat":
		return 1.0
	return clamp(base + stat_bonus - tension_penalty, 0.12, 0.94)

func _module_success_text(module: Dictionary, opt: Dictionary) -> String:
	var style: String = String(opt.get("id", "steady"))
	var mid: String = String(module.get("id", "sm00"))
	var conflict: String = String(module.get("conflict", "survival"))
	var base: String = "浣犲鐞嗕簡灞€鍔裤€?s銆嶃€? % mid
	if style == "retreat":
		var small_retreat: String = _grant_small_reward("retreat")
		_add_counter("module_exit_safe", 1)
		return base + " 浣犻€夋嫨淇濆簳鎾ょ锛屾敼鍐欎簡涓嬩竴娈甸闄╂毚闇层€俓n" + small_retreat

	if style == "gamble":
		var high_gain: String = ""
		if rng.randf() < 0.64:
			high_gain = _grant_hard_growth("gamble")
		else:
			high_gain = _grant_small_reward("gamble")
		if conflict == "combat":
			ration += 1
		elif conflict == "negotiation":
			relations["patrol"] = int(relations.get("patrol", 0)) + 1
		elif conflict == "explore":
			_add_counter("clue_key", 1)
		return base + " 浣犵殑鎶兼敞鎴愬姛锛屾敹鐩婅鏀惧ぇ涓旀敼鍙樹簡鍚庣画灞€鍔垮叆鍙ｃ€俓n" + high_gain

	if style.begins_with("trait_"):
		var trait_gain: String = _grant_small_reward("trait_path")
		match style:
			"trait_truth":
				_add_counter("clue_key", 2)
				_echo_world("鍥炲搷瑙﹀彂婧愶細浣犳帉鎻′簡鏇存繁鐪熺浉鍒嗘敮銆?)
				return base + " 浣犵敤鐗硅川鍒囧嚭浜嗙湡鐩歌矾寰勶紝鍚庣画绁炵鑺傜偣浼氬嚭鐜伴澶栭€夐」銆俓n" + trait_gain
			"trait_leverage":
				relations["patrol"] = int(relations.get("patrol", 0)) + 2
				relations["grey_market"] = int(relations.get("grey_market", 0)) + 1
				return base + " 浣犳妸鍐茬獊鍘嬫垚浜ゆ槗锛屽悗缁墽娉?鍩庨晣鑺傜偣缁撴瀯鏀瑰彉銆俓n" + trait_gain
			"trait_ambush":
				ration += 2
				return base + " 浣犻鍒や簡鐚庣嚎锛屽悗缁嫨鐚庝笌杩借釜鑺傜偣灏嗗亸鍚戜富鍔ㄦ潈銆俓n" + trait_gain
			"trait_reroute":
				_expose_tags(["ruin", "water"], 1.2)
				return base + " 浣犳敼鍐欎簡璺嚎鏆撮湶锛屼笅涓€鎵规満浼氳妭鐐瑰彂鐢熷亸绉汇€俓n" + trait_gain
			_:
				return base + " 浣犳墦鍑轰簡鐗硅川鍒嗘敮銆俓n" + trait_gain

	var steady_gain: String = _grant_small_reward("steady")
	if rng.randf() < 0.24:
		steady_gain += "\n" + _grant_hard_growth("steady_bonus")
	match conflict:
		"negotiation":
			relations["patrol"] = int(relations.get("patrol", 0)) + 1
		"explore":
			_add_counter("clue_key", 1)
		"survival":
			ration += 1
		_:
			pass
	return base + " 浣犵ǔ浣忎簡椋庨櫓骞舵嬁鍒板彲瑙傚洖鎶ワ紝鏈潵鑺傜偣浼氬姝や綔鍑哄弽搴斻€俓n" + steady_gain

func _module_fail_text(module: Dictionary, opt: Dictionary) -> String:
	var conflict: String = String(module.get("conflict", "survival"))
	var style: String = String(opt.get("id", "steady"))
	var salvage: String = ""
	if _has_trait("trait.calm_layers") and conflict in ["survival", "explore"]:
		salvage = "澶辫触琚綘杞垚浜嗛敊澶辨満浼氾紝鎹熷け琚帇浣庛€?
		_add_counter("missed_opportunity", 1)
		_expose_tags(module.get("tags", []), 0.7)
		return "浣犳病鑳藉畬鎴愯繖娆″鐞嗐€?s" % salvage
	if _has_trait("trait.break_negotiation") and conflict == "negotiation":
		_raise_open_thread_pressure(8)
		return "浣犺皥宕╀簡锛屼絾鍑粡楠屾妸灞€闈㈠帇鍦ㄥ彲鏀舵嬀鑼冨洿锛堟敼涓虹嚎绋嬪崌鍘嬶級銆?
	if _has_trait("trait.headwind_march") and style == "gamble":
		_add_counter("thread_progress_keep", 1)
		hp -= 1
		return "浣犵殑婵€杩涙柟妗堝け璐ワ紝浣嗕繚浣忎簡鎺ㄨ繘鎴愭灉鐨勫叧閿儴鍒嗐€?
	if style.begins_with("trait_"):
		_add_counter("trait_branch_failed", 1)
		_add_counter("clue_key", 1)
		sanity -= 1
		return "浣犵殑鐗硅川鍒嗘敮娌℃墦绌匡紝浣嗕繚鐣欎簡绾跨储锛屽悗缁粛鍙浆鍏ユ浛浠ｈ矾寰勩€?

	hp -= 2
	sanity -= 2
	_raise_open_thread_pressure(12)
	return "浣犲鐞嗗け璐ュ苟浠樺嚭浜嗕唬浠凤紙鐢熷懡-2锛岀悊鏅?2锛夛紝灞€鍔垮帇鍔涚户缁蛋楂樸€?

func _raise_open_thread_pressure(inc: int) -> void:
	for i in range(story_threads.size()):
		var th: Dictionary = story_threads[i]
		if String(th.get("state", "open")) != "open":
			continue
		th["pressure"] = _clamp_int(int(th.get("pressure", 0)) + inc, 0, 120)
		story_threads[i] = th

func _on_event_node_resolved(module_id: String, style: String, success: bool) -> void:
	event_nodes_count += 1
	small_reward_clock += 1
	hard_reward_clock += 1
	_add_counter("module_resolved_total", 1)
	_add_counter("module_resolved_" + module_id, 1)
	_add_counter("module_style_" + style, 1)
	if success:
		_add_counter("module_success_total", 1)

	if event_nodes_count >= 3 and echo_log.is_empty():
		_echo_world("涓栫晫鍥炲搷锛氫綘涔嬪墠鐨勮鍔ㄥ凡缁忓紑濮嬭浠栦汉寮曠敤銆?)

	if hard_growth_count < 1 and event_nodes_count >= 2:
		_echo_world(_grant_hard_growth("pity_2"))
		hard_reward_clock = 0
	elif hard_growth_count < 2 and event_nodes_count >= 5:
		_echo_world(_grant_hard_growth("pity_5"))
		hard_reward_clock = 0
	elif hard_reward_clock >= rng.randi_range(5, 8):
		_echo_world(_grant_hard_growth("clock"))
		hard_reward_clock = 0

	if small_reward_clock >= rng.randi_range(1, 2):
		_echo_world(_grant_small_reward("clock"))
		small_reward_clock = 0

func _grant_small_reward(source: String) -> String:
	var roll: int = rng.randi_range(0, 3)
	match roll:
		0:
			trait_fragments += 1
			return "灏忓洖鎶ワ細鑾峰緱1鏋歍rait纰庣墖銆?
		1:
			var key: String = "grey_market"
			relations[key] = int(relations.get(key, 0)) + 1
			_add_impact_tag("浜烘儏+1")
			return "灏忓洖鎶ワ細浣犵Н绱簡鐏板競浜烘儏銆?
		2:
			coin += 1
			ration += 1
			return "灏忓洖鎶ワ細鍥炴敹浜嗛浂鏁ｈˉ缁欙紙鍙ｇ伯+1锛岄噾甯?1锛夈€?
		_:
			_add_counter("clue_key", 1)
			return "灏忓洖鎶ワ細鑾峰緱绾跨储閽ュ寵锛屽彲鐢ㄤ簬鍚庣画楂樹环鍊煎垎鏀€?

func _grant_hard_growth(source: String) -> String:
	hard_growth_count += 1
	var trait_id: String = _pick_unowned_trait()
	if trait_id != "" and (rng.randf() < 0.7 or hard_growth_count <= 2):
		var trait_text: String = _grant_trait(trait_id, source)
		if trait_text != "":
			return "纭垚闀匡細%s" % trait_text
	var eq_text: String = _try_generate_equipment("hard_growth")
	if eq_text != "":
		_add_impact_tag("鍏抽敭瑁呭")
		return "纭垚闀匡細浣犺幏寰椾簡鍏抽敭瑁呭銆俓n" + eq_text
	relations["patrol"] = int(relations.get("patrol", 0)) + 2
	_add_impact_tag("鍏崇郴鍗囩骇")
	return "纭垚闀匡細浣犱笌宸＄伅浜虹殑鍏崇郴鍗囩骇锛屽悗缁皢鍑虹幇鏂伴€氳矾銆?

func _pick_unowned_trait() -> String:
	var candidates: Array[String] = []
	for k_any in trait_catalog.keys():
		var k: String = String(k_any)
		if not _has_trait(k):
			candidates.append(k)
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func _has_trait(id: String) -> bool:
	return bool(traits.get(id, false))

func _grant_trait(id: String, source: String) -> String:
	if id == "" or _has_trait(id):
		return ""
	traits[id] = true
	var def_any: Variant = trait_catalog.get(id, {})
	var def: Dictionary = def_any as Dictionary if def_any is Dictionary else {}
	var name: String = String(def.get("name", id))
	_add_impact_tag(name)
	_add_counter("trait_gain_total", 1)
	_add_counter("trait_source_" + source, 1)
	return "鑾峰緱鐗硅川銆?s銆嶏細%s锛涘け璐ュ舰鎬佹敼鍙樹负锛?s銆? % [
		name,
		String(def.get("unlock", "瑙ｉ攣鏂伴€夐」")),
		String(def.get("fail_shift", "澶辫触鎹熷け闄嶄綆"))
	]

func _add_impact_tag(tag: String) -> void:
	if tag == "":
		return
	if impact_tags.has(tag):
		return
	impact_tags.append(tag)
	while impact_tags.size() > 8:
		impact_tags.pop_front()

func _echo_world(line: String) -> void:
	if line == "":
		return
	echo_log.append(line)
	while echo_log.size() > 3:
		echo_log.pop_front()

func _queue_echo_hook(text: String, delay_h: int, effects: Array=[], choices: Array=[]) -> void:
	if text == "":
		return
	echo_nonce += 1
	echo_hooks.append({
		"id": "echo_%04d" % echo_nonce,
		"due_h": time_hours + max(1, delay_h),
		"text": text,
		"effects": effects.duplicate(true),
		"choices": choices.duplicate(true)
	})

func _pop_due_echo_hook() -> Dictionary:
	if echo_hooks.is_empty():
		return {}
	var picked_idx: int = -1
	var picked_due: int = 999999999
	for i in range(echo_hooks.size()):
		var hk_any: Variant = echo_hooks[i]
		if not (hk_any is Dictionary):
			continue
		var hk: Dictionary = hk_any as Dictionary
		var due: int = int(hk.get("due_h", 999999999))
		if due <= time_hours and due < picked_due:
			picked_due = due
			picked_idx = i
	if picked_idx < 0:
		return {}
	var out_any: Variant = echo_hooks[picked_idx]
	echo_hooks.remove_at(picked_idx)
	return out_any as Dictionary if out_any is Dictionary else {}

func _trigger_due_echo_hook() -> String:
	var hk: Dictionary = _pop_due_echo_hook()
	if hk.is_empty():
		return ""
	var eff_any: Variant = hk.get("effects", [])
	if eff_any is Array:
		_apply_effects(eff_any as Array)
	var text: String = String(hk.get("text", "涓栫晫鍥炲搷鍦ㄦ鍒昏Е鍙戙€?))
	_echo_world("鍥炲搷瑙﹀彂锛? + text)
	_add_impact_tag("鍥炲搷瑙﹀彂")

	var choices_any: Variant = hk.get("choices", [])
	if choices_any is Array and not (choices_any as Array).is_empty():
		_pending_choices.clear()
		for c_any in (choices_any as Array):
			if c_any is Dictionary:
				_pending_choices.append((c_any as Dictionary).duplicate(true))
		_has_pending = not _pending_choices.is_empty()
		if _has_pending:
			return text + "\n[color=orange]鍥炲搷鎶夋嫨宸茶嚜鍔ㄥ脊鍑恒€俒/color]"
	return text

func _register_module_reverb(module: Dictionary, style: String, success: bool) -> void:
	var tags_any: Variant = module.get("tags", [])
	var tags: Array = tags_any as Array if tags_any is Array else []
	var mid: String = String(module.get("id", "sm00"))

	if success and "patrol" in tags:
		_world_queue_news("涓栫晫鎬佸娍锛氬贰鐏綉缁滃紑濮嬪浣犵殑琛屽姩缁欏嚭姝ｅ弽棣堛€?)
		_queue_echo_hook(
			"宸＄伅浜哄啀娆″嚭鐜板苟璁ゅ嚭浣狅紝鎰挎剰浜ゆ崲涓€娈靛畨鍏ㄨ矾鎯呮姤銆?,
			rng.randi_range(6, 14),
			[{"op":"counter_add","k":"clue_key","inc":1}],
			[
				{"id":"echo_patrol_safe", "text":"鎺ュ彈鎶ら€侊紙闄嶉闄╋級", "effects":[{"op":"counter_add","k":"safe_route","inc":1}], "result_text":"浣犲€熸姢閫佽烦杩囦簡涓€娈甸珮鍘嬭矾娈点€?},
				{"id":"echo_patrol_trade", "text":"浜ゆ崲鎯呮姤锛堟嬁閽ュ寵锛?, "effects":[{"op":"counter_add","k":"clue_key","inc":2},{"op":"meter_add","k":"sanity","inc":-1}], "result_text":"浣犳嬁鍒版洿娣辩嚎绱紝浣嗗績绁炶鎷夋壇銆?}
			]
		)

	if success and "faction" in tags and style in ["steady", "gamble", "trait_leverage"]:
		_world_apply_relation_delta("faction_patrol", "faction_grey_market", 2 if style != "gamble" else -1)
		_world_queue_news("涓栫晫鎬佸娍锛氳竟澧冨娍鍔涜皟鏁翠簡瀵逛綘鐨勫垽瀹氬彛寰勩€?)
		_queue_echo_hook(
			"杈瑰鍔垮姏瀵逛綘鐨勫缃柟寮忔湁浜嗘柊鍒ゆ柇锛屽悗缁鏌ュ彛寰勬敼鍙樸€?,
			rng.randi_range(8, 16),
			[{"op":"counter_add","k":"faction_echo","inc":1}],
			[
				{"id":"echo_faction_pass", "text":"璧版瑙勫彛锛堢ǔ锛?, "effects":[{"op":"counter_add","k":"checkpoint_easy","inc":1}], "result_text":"浣犻€氳繃浜嗘洿瀹芥澗鐨勬牳楠屻€?},
				{"id":"echo_faction_use", "text":"鍊熷娍鍘嬩环锛堣祵锛?, "effects":[{"op":"counter_add","k":"debt_open","inc":1},{"op":"coin_add","inc":1}], "result_text":"浣犲帇鍑轰簡鐭湡鍒╃泭锛屼絾娆犱笅浜嗕汉鎯呭€恒€?}
			]
		)

	if success and "ruin" in tags:
		_world_queue_news("涓栫晫鎬佸娍锛氶仐杩瑰尯鍏ュ彛缁撴瀯鍙戠敓浜嗗彉鍖栥€?)
		_queue_echo_hook(
			"閬楄抗鐘舵€佸洜浣犵殑鍔ㄤ綔鏀瑰彉锛屼竴澶勬柊鍏ュ彛鍦ㄥ悗缁毚闇层€?,
			rng.randi_range(10, 18),
			[{"op":"counter_add","k":"ruin_open","inc":1}]
		)

	if (not success) and ("faction" in tags or "town" in tags):
		_world_apply_region_delta(current_region_id, {"conflict": 8, "hazard": 4})
		_world_apply_relation_delta("faction_patrol", "faction_scavengers", -3)
		_queue_echo_hook(
			"浣犱箣鍓嶅鐞嗗け鎵嬬殑褰卞搷鎵╂暎浜嗭紝涓嬩竴娆℃鏌ユ洿涓ユ牸銆?,
			rng.randi_range(5, 10),
			[{"op":"counter_add","k":"heat_level","inc":1},{"op":"meter_add","k":"sanity","inc":-1}]
		)

	if success and style == "gamble":
		_world_apply_region_delta(current_region_id, {"conflict": 5, "hazard": 2})
		_queue_echo_hook(
			"浣犵殑婵€杩涙墜娉曡浼犲紑锛屾湁浜哄紑濮嬩富鍔ㄦ壘浣犲仛楂橀闄╁鎵樸€?,
			rng.randi_range(7, 15),
			[{"op":"counter_add","k":"high_risk_offer","inc":1}]
		)

	_add_counter("reverb_seed_" + mid, 1)

func _has_open_thread_kind(kind: String) -> bool:
	for th in story_threads:
		if String(th.get("state", "open")) != "open":
			continue
		if String(th.get("kind", "")) == kind:
			return true
	return false

func _count_str_in_array(arr: Array[String], needle: String) -> int:
	if needle == "":
		return 0
	var cnt: int = 0
	for s in arr:
		if s == needle:
			cnt += 1
	return cnt

func _story_open_count() -> int:
	var cnt: int = 0
	for th in story_threads:
		if String(th.get("state", "open")) == "open":
			cnt += 1
	return cnt

func _active_story_threads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for th in story_threads:
		if String(th.get("state", "open")) == "open":
			out.append(th)
	return out

func _thread_more_urgent(a: Dictionary, b: Dictionary) -> bool:
	var rem_a: int = max(0, int(a.get("deadline_h", time_hours + 24)) - time_hours)
	var rem_b: int = max(0, int(b.get("deadline_h", time_hours + 24)) - time_hours)
	var score_a: int = int(a.get("pressure", 0)) * 3 + max(0, 30 - rem_a) * 2
	var score_b: int = int(b.get("pressure", 0)) * 3 + max(0, 30 - rem_b) * 2
	return score_a > score_b

func _trim_memory_beats() -> void:
	while memory_beats.size() > 10:
		memory_beats.pop_front()

func _pick_pool_name(keys: Array[String], fallback: String) -> String:
	var pools: Dictionary = _region_pools()
	for k in keys:
		var arr_any: Variant = pools.get(k, [])
		if arr_any is Array and not (arr_any as Array).is_empty():
			var d: Dictionary = _pick_one_dict(arr_any as Array)
			var nm: String = String(d.get("name", d.get("id", "")))
			if nm != "":
				return nm
	return fallback

func _make_story_thread(kind: String) -> Dictionary:
	thread_nonce += 1
	var tid: String = "t%04d" % thread_nonce
	var tpl_any: Variant = thread_templates.get(kind, {})
	var tpl: Dictionary = tpl_any as Dictionary if tpl_any is Dictionary else {}
	var title_head: String = String(tpl.get("title", "灞€鍔挎尝鍔?))
	var subject: String = _pick_pool_name(["sublocations", "fauna", "flora"], "杈瑰鍦板甫")
	var deadline_span: int = rng.randi_range(8, 16)
	var base_pressure: int = rng.randi_range(22, 36)
	if kind == "predator":
		subject = _pick_pool_name(["fauna", "creatures"], "闄岀敓鐚庣兢")
		base_pressure += 6
	elif kind == "scarcity":
		subject = _pick_pool_name(["flora", "resources"], "琛ョ粰璧板粖")
	elif kind == "echo":
		subject = _pick_pool_name(["sublocations"], "闆句腑鍥炲搷")
		base_pressure += 3
	elif kind == "faction":
		subject = _pick_faction_name()
	elif kind == "relic":
		subject = _pick_pool_name(["sublocations"], "娈嬬鍦板甫")
	elif kind == "patrol":
		subject = "宸＄伅璺"

	return {
		"id": tid,
		"kind": kind,
		"subject": subject,
		"title": "%s锛?s" % [title_head, subject],
		"state": "open",
		"stage": 1,
		"progress": 0,
		"jackpot": 0,
		"pressure": _clamp_int(base_pressure, 10, 90),
		"born_h": time_hours,
		"last_prompt_h": -9999,
		"deadline_h": time_hours + deadline_span,
		"reward_trait": String(tpl.get("reward_trait", "")),
		"echo": String(tpl.get("echo", "涓栫晫璁颁綇浜嗕綘鐨勫鐞嗘柟寮忋€?))
	}

func _maybe_spawn_story_thread() -> String:
	if _get_flag("run_ended") or has_pending_choice():
		return ""
	if _story_open_count() >= 2:
		return ""

	var chance: float = 0.10
	if _story_open_count() == 0:
		chance += 0.10
	chance += float(global_arc.get("danger", 20)) / 1200.0
	chance += float(global_arc.get("mystic", 20)) / 1400.0
	chance = clamp(chance, 0.08, 0.28)
	if rng.randf() > chance:
		return ""

	var pool: Array = [
		{"event":{"kind":"predator"}, "weight": 8 + int(global_arc.get("danger", 20))},
		{"event":{"kind":"scarcity"}, "weight": 8 + int(global_arc.get("scarcity", 20))},
		{"event":{"kind":"echo"}, "weight": 8 + int(global_arc.get("mystic", 20))},
		{"event":{"kind":"faction"}, "weight": 6 + int(global_arc.get("order", 30))},
		{"event":{"kind":"relic"}, "weight": 6 + int(global_arc.get("war", 10))},
		{"event":{"kind":"patrol"}, "weight": 5 + int(global_arc.get("order", 30))}
	]
	var pick: Dictionary = _weighted_pick(pool)
	var ev_any: Variant = pick.get("event", {})
	var ev: Dictionary = ev_any as Dictionary if ev_any is Dictionary else {}
	var kind: String = String(ev.get("kind", "predator"))
	var th: Dictionary = _make_story_thread(kind)
	story_threads.append(th)
	memory_beats.append("浣犲嵎鍏ヤ簡銆?s銆? % String(th.get("title", "鏈煡浜嬫€?)))
	_trim_memory_beats()
	_echo_world("涓栫晫鍥炲搷锛氭柊绾跨▼銆?s銆嶆诞鍑烘按闈€? % String(th.get("title", "鏈煡浜嬫€?)))
	return "銆愮嚎绋?Stage1銆?s銆備綘鍙互淇濆畧澶勭悊灏忚禋淇濆簳锛屼篃鍙互鎶兼敞鍐查珮鏀剁泭銆? % String(th.get("title", "鏈煡浜嬫€?))

func _advance_story_threads(hours: int) -> void:
	var h: int = max(0, hours)
	for _i in range(h):
		for idx in range(story_threads.size()):
			var th: Dictionary = story_threads[idx]
			if String(th.get("state", "open")) != "open":
				continue
			var kind: String = String(th.get("kind", "predator"))
			var stage: int = int(th.get("stage", 1))
			var drift: int = 1 + rng.randi_range(0, 2)
			if kind == "predator":
				drift += int(global_arc.get("danger", 20) / 35)
			elif kind == "scarcity":
				drift += int(global_arc.get("scarcity", 20) / 42)
			elif kind == "echo":
				drift += int(global_arc.get("mystic", 20) / 40)
			elif kind == "faction":
				drift += int(global_arc.get("war", 10) / 45)
			th["pressure"] = _clamp_int(int(th.get("pressure", 0)) + drift + max(0, stage - 1), 0, 120)
			story_threads[idx] = th
			if stage == 1 and int(th.get("pressure", 0)) >= 55:
				th["stage"] = 2
				story_threads[idx] = th
				story_alert_queue.append("銆愮嚎绋?Stage2銆戙€?s銆嶅崌绾э細鍐茬獊鏇村己锛屼絾鏀舵潫濂栧姳涔熸洿楂樸€? % String(th.get("title", "鏈煡浜嬫€?)))
			if stage <= 2 and time_hours >= int(th.get("deadline_h", time_hours + 1)):
				if int(th.get("stage", 1)) == 1:
					th["stage"] = 2
					th["pressure"] = _clamp_int(int(th.get("pressure", 0)) + 16, 0, 120)
					th["deadline_h"] = time_hours + rng.randi_range(4, 8)
					story_threads[idx] = th
					story_alert_queue.append("銆?s銆嶈繘鍏ュ帇绾块樁娈碉紝鍐嶆嫋灏变細澶辨帶銆? % String(th.get("title", "鏈煡浜嬫€?)))
				else:
					_fail_story_thread(idx, "瓒呮椂宕╃洏")
			elif int(th.get("pressure", 0)) >= 100:
				_fail_story_thread(idx, "鍘嬪姏鐖嗚〃")

func _pop_story_alert() -> String:
	if story_alert_queue.is_empty():
		return ""
	var t: String = story_alert_queue[0]
	story_alert_queue.pop_front()
	return t

func _maybe_offer_story_thread_choice() -> String:
	if _get_flag("run_ended") or has_pending_choice():
		return ""
	var active: Array[Dictionary] = _active_story_threads()
	if active.is_empty():
		return ""
	active.sort_custom(Callable(self, "_thread_more_urgent"))
	var top: Dictionary = active[0]
	var tid: String = String(top.get("id", ""))
	var idx: int = _find_story_thread_index(tid)
	if idx < 0:
		return ""
	var pressure: int = int(top.get("pressure", 0))
	var stage: int = int(top.get("stage", 1))
	var last_prompt_h: int = int(top.get("last_prompt_h", -9999))
	var chance: float = clamp(0.20 + float(pressure) / 150.0, 0.16, 0.76)
	if time_hours - last_prompt_h < 2:
		chance *= 0.35
	if rng.randf() > chance:
		return ""

	story_threads[idx]["last_prompt_h"] = time_hours
	var title: String = String(top.get("title", "鏈煡浜嬫€?))
	var remain: int = max(0, int(top.get("deadline_h", time_hours + 1)) - time_hours)
	var gain_hint: String = "娼滃湪鏀剁泭锛氬皬璧氫繚搴?/ 鎶兼敞楂樺洖鎶?/ 鏀句换鍙兘鏀惧ぇ浣嗕唬浠蜂笂鍗?
	_pending_choices.clear()
	_pending_choices.append({
		"id": "thread_" + tid + "_engage",
		"text": "姝ｉ潰澶勭悊锛堢ǔ鎺ㄨ繘锛?h锛?,
		"system_action": "sys.thread.%s.engage" % tid
	})
	_pending_choices.append({
		"id": "thread_" + tid + "_stabilize",
		"text": "鎶曞叆琛ョ粰绋充綇锛堜繚搴曪紝1h锛?,
		"system_action": "sys.thread.%s.stabilize" % tid
	})
	_pending_choices.append({
		"id": "thread_" + tid + "_exploit",
		"text": "瓒佷贡鐗熷埄锛堥珮鏀剁泭锛屽鍘嬶級",
		"system_action": "sys.thread.%s.exploit" % tid
	})
	_has_pending = true
	return "銆愮嚎绋?Stage%d銆戜綘涓庛€?s銆嶆闈㈤伃閬囷紝绐楀彛绾?d灏忔椂銆俓n%s\n[color=orange]绾跨▼鎶夋嫨宸茶嚜鍔ㄥ脊鍑恒€俒/color]" % [stage, title, remain, gain_hint]

func _find_story_thread_index(tid: String) -> int:
	if tid == "":
		return -1
	for i in range(story_threads.size()):
		if String(story_threads[i].get("id", "")) == tid:
			return i
	return -1

func _resolve_story_thread(idx: int, mode: String) -> String:
	if idx < 0 or idx >= story_threads.size():
		return "灞€鍔跨煭鏆傚钩鎭€?
	var th: Dictionary = story_threads[idx]
	if String(th.get("state", "open")) != "open":
		return "灞€鍔垮凡缁忓彉鍖栥€?
	th["state"] = "resolved"
	story_threads[idx] = th

	var kind: String = String(th.get("kind", "predator"))
	var title: String = String(th.get("title", "鏈煡浜嬫€?))
	var jackpot: int = int(th.get("jackpot", 0))
	var reward_text: String = ""
	if kind == "predator":
		var gain_ration: int = rng.randi_range(1, 3) + int(jackpot / 2)
		ration += gain_ration
		global_arc["danger"] = _clamp_int(int(global_arc.get("danger", 20)) - 9, 0, 100)
		reward_text = "浣犲帇浣忎簡鐚庤釜鎵╂暎骞跺洖鏀惰ˉ缁欙紙鍙ｇ伯+%d锛夈€? % gain_ration
	elif kind == "scarcity":
		ration += 2 + int(jackpot / 3)
		coin += 1 + int(jackpot / 4)
		global_arc["scarcity"] = _clamp_int(int(global_arc.get("scarcity", 20)) - 11, 0, 100)
		reward_text = "浣犳墦閫氫簡琛ョ粰鏂彛銆?
	elif kind == "echo":
		sanity = min(sanity_max, sanity + 6 + int(jackpot / 4))
		global_arc["mystic"] = _clamp_int(int(global_arc.get("mystic", 20)) + 2, 0, 100)
		reward_text = "浣犲畬鎴愪簡鍥炲０鏍″噯锛堢悊鏅烘仮澶嶏級銆?
	elif kind == "faction":
		coin += 2 + int(jackpot / 3)
		relations["patrol"] = int(relations.get("patrol", 0)) + 2
		global_arc["order"] = _clamp_int(int(global_arc.get("order", 30)) + 9, 0, 100)
		reward_text = "浣犳妸杈瑰鎽╂摝鍘嬭繘浜嗗彲浜ゆ槗鍖洪棿銆?
	elif kind == "patrol":
		relations["patrol"] = int(relations.get("patrol", 0)) + 3
		ration += 1 + int(jackpot / 4)
		reward_text = "浣犲畬鎴愪簡宸＄伅鏀彺骞跺缓绔嬬ǔ瀹氬洖搴斻€?
	else:
		coin += rng.randi_range(1, 3) + int(jackpot / 3)
		reward_text = "浣犲湪閬楄抗浜夊ず绾挎敹鏉熸椂甯﹀洖浜嗛珮浠峰€肩墿璧勩€?
		if rng.randf() < 0.45:
			var relic_eq: String = _try_generate_equipment("thread_relic")
			if relic_eq != "":
				reward_text += "\n" + relic_eq

	var reward_trait: String = String(th.get("reward_trait", ""))
	if reward_trait != "" and not _has_trait(reward_trait):
		var t_text: String = _grant_trait(reward_trait, "thread_settle")
		if t_text != "":
			hard_growth_count += 1
			reward_text += "\n纭垚闀匡細" + t_text
		else:
			reward_text += "\n" + _grant_hard_growth("thread_trait")
	else:
		reward_text += "\n" + _grant_hard_growth("thread_settle")

	_add_counter("thread_resolved_" + kind, 1)
	memory_beats.append("浣犲鐞嗚繃銆?s銆? % title)
	_trim_memory_beats()
	_add_impact_tag("绾跨▼鏀舵潫")
	_echo_world(String(th.get("echo", "涓栫晫璁颁綇浜嗕綘鐨勫鐞嗘柟寮忋€?)))
	_world_apply_thread_outcome(kind, true, int(th.get("pressure", 0)))
	hard_reward_clock = 0
	small_reward_clock = 0
	_on_event_node_resolved("thread_" + kind, mode, true)
	_check_player_clamp()
	return "銆愮嚎绋?Stage3 鏀舵潫銆戜綘澶勭悊浜嗐€?s銆嶃€?s" % [title, reward_text]

func _fail_story_thread(idx: int, reason: String) -> void:
	if idx < 0 or idx >= story_threads.size():
		return
	var th: Dictionary = story_threads[idx]
	if String(th.get("state", "open")) != "open":
		return
	th["state"] = "failed"
	story_threads[idx] = th

	var kind: String = String(th.get("kind", "predator"))
	var pressure: int = int(th.get("pressure", 60))
	var title: String = String(th.get("title", "鏈煡浜嬫€?))
	hp -= 1 + int(pressure / 40)
	sanity -= 1 + int(pressure / 45)
	match kind:
		"predator":
			global_arc["danger"] = _clamp_int(int(global_arc.get("danger", 20)) + 7, 0, 100)
		"scarcity":
			ration = max(0, ration - 1)
			global_arc["scarcity"] = _clamp_int(int(global_arc.get("scarcity", 20)) + 7, 0, 100)
		"echo":
			sanity -= 1
			global_arc["mystic"] = _clamp_int(int(global_arc.get("mystic", 20)) + 6, 0, 100)
		"faction":
			coin = max(0, coin - 1)
			global_arc["war"] = _clamp_int(int(global_arc.get("war", 10)) + 6, 0, 100)
		_:
			cold = _clamp_int(cold + 5, 0, cold_max)
			global_arc["danger"] = _clamp_int(int(global_arc.get("danger", 20)) + 4, 0, 100)
	_world_apply_thread_outcome(kind, false, pressure)
	_check_player_clamp()

	_add_counter("thread_failed_" + kind, 1)
	memory_beats.append("浣犳斁浠讳簡銆?s銆?s" % [title, reason])
	_trim_memory_beats()
	_on_event_node_resolved("thread_" + kind, "ignored", false)
	story_alert_queue.append("浣犳病鑳藉強鏃跺鐞嗐€?s銆嶏紝灞€鍔?s锛岃繛閿佸悗鏋滃紑濮嬫樉鐜般€? % [title, reason])

func _apply_story_thread_action(choice_id: String) -> Dictionary:
	var parts: PackedStringArray = choice_id.split(".")
	if parts.size() < 4:
		return _action_result("浣犺繜鐤戜簡涓€鐬紝绐楀彛宸茬粡鍋忕Щ銆?)

	var tid: String = parts[2]
	var mode: String = parts[3]
	var idx: int = _find_story_thread_index(tid)
	if idx < 0:
		return _action_result("璇ヤ簨鎬佸凡缁忔紨鍖栧埌鍒锛屼綘娌¤刀涓婄獥鍙ｃ€?)

	var cd_h: int = 2
	var spend_h: int = 2
	if mode == "stabilize":
		cd_h = 1
		spend_h = 1
	elif mode == "exploit":
		cd_h = 2
		spend_h = 1
	_mark_action_used(choice_id, cd_h)

	time_hours += spend_h
	_survival_tick(spend_h)

	idx = _find_story_thread_index(tid)
	if idx < 0:
		return _action_result("浣犺刀鍒版椂锛屽眬鍔垮凡缁忔敼鍐欍€?)
	var th: Dictionary = story_threads[idx]
	if String(th.get("state", "open")) != "open":
		var late_alert: String = _pop_story_alert()
		return _action_result(late_alert if late_alert != "" else "浣犺刀鍒版椂锛屽眬鍔垮凡缁忓け鎺с€?)

	var title: String = String(th.get("title", "鏈煡浜嬫€?))
	var pressure: int = int(th.get("pressure", 30))
	var progress: int = int(th.get("progress", 0))
	var stage: int = int(th.get("stage", 1))
	var tpl_any: Variant = thread_templates.get(String(th.get("kind", "")), {})
	if tpl_any is Dictionary:
		_expose_tags((tpl_any as Dictionary).get("tags", []), 1.0)

	match mode:
		"engage":
			var engage_chance: float = 0.36 + float(stat_str + stat_dex + stat_wis + stat_int) / 220.0 - float(pressure) / 230.0
			if stage >= 2:
				engage_chance -= 0.06
			if rng.randf() <= clamp(engage_chance, 0.14, 0.9):
				var add_prog: int = rng.randi_range(24, 42) + (8 if stage >= 2 else 0)
				var dec_pressure: int = rng.randi_range(10, 18)
				th["progress"] = _clamp_int(progress + add_prog, 0, 130)
				th["pressure"] = _clamp_int(pressure - dec_pressure, 0, 120)
				story_threads[idx] = th
				if int(th.get("progress", 0)) >= 100:
					return _action_result(_resolve_story_thread(idx, mode))
				_on_event_node_resolved("thread_" + String(th.get("kind", "")), mode, true)
				return _action_result("浣犲己琛屼粙鍏ャ€?s銆嶏紝鎶婂眬鍔挎寜浣忎簡涓€鎴紙杩涘害+%d锛屽帇鍔?%d锛夈€? % [title, add_prog, dec_pressure])
			hp -= 2 + int(pressure / 45)
			sanity -= 1 + int(pressure / 60)
			th["pressure"] = _clamp_int(pressure + rng.randi_range(9, 16), 0, 120)
			story_threads[idx] = th
			if int(th.get("pressure", 0)) >= 100:
				_fail_story_thread(idx, "纰版挒鍗囩骇")
				var fail_alert: String = _pop_story_alert()
				return _action_result(fail_alert if fail_alert != "" else "浣犵殑浠嬪叆瑙﹀彂浜嗘洿鍧忕殑杩為攣鍙嶅簲銆?)
			_on_event_node_resolved("thread_" + String(th.get("kind", "")), mode, false)
			return _action_result("浣犱粙鍏ャ€?s銆嶅け璐ワ紝鑷繁涔熶粯鍑轰簡浠ｄ环銆? % title)
		"stabilize":
			var cost_text: String = ""
			if ration > 0:
				ration -= 1
				cost_text = "鍙ｇ伯-1"
			elif coin > 0:
				coin -= 1
				cost_text = "閲戝竵-1"
			else:
				hp -= 1
				sanity -= 2
				th["pressure"] = _clamp_int(pressure + 8, 0, 120)
				story_threads[idx] = th
				return _action_result("浣犺瘯鍥剧ǔ浣忋€?s銆嶏紝浣嗚ˉ缁欎笉瓒筹紝鍙嶈€岃鎷栧灝浜嗕竴鐐广€? % title)

			var reduce_p: int = 16 + int(stat_wis / 8)
			var add_p: int = 10 + int(stat_cha / 10)
			th["pressure"] = _clamp_int(pressure - reduce_p, 0, 120)
			th["progress"] = _clamp_int(progress + add_p, 0, 130)
			story_threads[idx] = th
			if int(th.get("progress", 0)) >= 100:
				return _action_result(_resolve_story_thread(idx, mode))
			_on_event_node_resolved("thread_" + String(th.get("kind", "")), mode, true)
			return _action_result("浣犵敤%s绋充綇浜嗐€?s銆嶏紝鑷冲皯浜夊彇鍒颁簡鏃堕棿銆? % [cost_text, title])
		"exploit":
			var gain_coin: int = rng.randi_range(2, 4)
			coin += gain_coin
			th["pressure"] = _clamp_int(pressure + 18, 0, 120)
			th["progress"] = _clamp_int(progress + 6, 0, 130)
			th["jackpot"] = int(th.get("jackpot", 0)) + 1 + (1 if stage >= 2 else 0)
			story_threads[idx] = th
			global_arc["danger"] = _clamp_int(int(global_arc.get("danger", 20)) + 4, 0, 100)
			var exploit_text: String = "浣犱粠銆?s銆嶉噷鎹炲埌涓€绗旀敹鐩婏紙閲戝竵+%d锛夛紝浣嗗眬鍔挎洿绱т簡銆? % [title, gain_coin]
			if rng.randf() < 0.22:
				var extra_eq: String = _try_generate_equipment("thread_exploit")
				if extra_eq != "":
					exploit_text += "\n" + extra_eq
			if int(th.get("pressure", 0)) >= 100:
				_fail_story_thread(idx, "琚繃搴︽斁澶?)
				var boom: String = _pop_story_alert()
				if boom != "":
					exploit_text += "\n" + boom
			else:
				_on_event_node_resolved("thread_" + String(th.get("kind", "")), mode, true)
			return _action_result(exploit_text)
		_:
			return _action_result("浣犳殏鏃舵病鏈夋姄鍒板彲鎵ц鐨勫垏鍏ュ彛銆?)

func _drift_global_arc(action: String, scale: int=1) -> void:
	var s: int = max(1, scale)
	match action:
		"tick":
			global_arc["danger"] = int(global_arc.get("danger", 18)) + rng.randi_range(-1, 1)
			global_arc["mystic"] = int(global_arc.get("mystic", 15)) + rng.randi_range(-1, 1)
			global_arc["scarcity"] = int(global_arc.get("scarcity", 20)) + rng.randi_range(-1, 1)
			global_arc["order"] = int(global_arc.get("order", 40)) + rng.randi_range(-1, 1)
		"hunt_win":
			global_arc["danger"] = int(global_arc.get("danger", 18)) - 2 * s
			global_arc["order"] = int(global_arc.get("order", 40)) + 1 * s
		"hunt_fail":
			global_arc["danger"] = int(global_arc.get("danger", 18)) + 3 * s
			global_arc["mystic"] = int(global_arc.get("mystic", 15)) + 1 * s
		"forage":
			global_arc["scarcity"] = int(global_arc.get("scarcity", 20)) - 1 * s
		"travel":
			global_arc["danger"] = int(global_arc.get("danger", 18)) + 1 * s
			global_arc["war"] = int(global_arc.get("war", 12)) + rng.randi_range(0, 1)
		"rest":
			global_arc["order"] = int(global_arc.get("order", 40)) + 1 * s
		_:
			pass

	for k in global_arc.keys():
		global_arc[k] = _clamp_int(int(global_arc[k]), 0, 100)
	if not world_regions.is_empty():
		_world_sync_global_arc()

func _run_global_state_event(force: bool=false) -> String:
	if _get_flag("run_ended"):
		return ""
	var chance: float = 0.18
	chance += float(global_arc.get("danger", 0)) / 500.0
	chance += float(global_arc.get("mystic", 0)) / 600.0
	if not force and rng.randf() > chance:
		return ""

	var d: int = int(global_arc.get("danger", 20))
	var m: int = int(global_arc.get("mystic", 20))
	var s: int = int(global_arc.get("scarcity", 20))
	var o: int = int(global_arc.get("order", 40))
	var wr: Dictionary = _world_current_region()
	if not wr.is_empty():
		d = _clamp_int(d + int(wr.get("hazard", 20)) / 7 + int(wr.get("conflict", 20)) / 8, 0, 100)
		m = _clamp_int(m + int(wr.get("mystic", 20)) / 8, 0, 100)
		s = _clamp_int(s + max(0, 28 - int(wr.get("food", 50))) / 3 + max(0, 28 - int(wr.get("water", 50))) / 3, 0, 100)
		o = _clamp_int(o + int(40 - int(wr.get("conflict", 20))) / 6, 0, 100)

	var pool: Array[Dictionary] = [
		{"id":"wild_spike", "w": 10 + d},
		{"id":"mystic_echo", "w": 10 + m},
		{"id":"scarcity_wave", "w": 8 + s},
		{"id":"calm_order", "w": 6 + o}
	]
	var wrapped: Array = []
	for it in pool:
		wrapped.append({"event": it, "weight": float((it as Dictionary).get("w", 1.0))})
	var pick: Dictionary = _weighted_pick(wrapped)
	var ev: Dictionary = pick.get("event", {})
	var eid: String = String(ev.get("id", ""))

	if eid == "wild_spike":
		_world_apply_region_delta(current_region_id, {"hazard": 6, "fauna": -2, "conflict": 2})
		var pools: Dictionary = _region_pools()
		var fa_any: Variant = pools.get("fauna", pools.get("creatures", []))
		if fa_any is Array and not (fa_any as Array).is_empty():
			var base: Dictionary = _pick_one_dict(fa_any as Array)
			var cv: Dictionary = _roll_creature_variant(base)
			return "鏋楃嚎闂翠紶鏉ユ€ヤ績鍔ㄩ潤锛氥€?s銆嶅嚭鐜板湪浣犵殑璺緞鏃侊紝鍛ㄩ伃閲庢€ф鍦ㄥ崌楂樸€? % String(cv.get("name", "鏈煡鐢熺墿"))
		return "鏋楅棿寮傚姩棰戝彂锛岀寧椋熻€呬技涔庡湪閲嶆帓棰嗗湴銆?

	if eid == "mystic_echo":
		_world_apply_region_delta(current_region_id, {"mystic": 6, "hazard": 2})
		if rng.randf() < 0.35:
			var eq_text: String = _try_generate_equipment("mystic")
			if eq_text != "":
				return "绌烘皵鍍忚缁嗙嚎鎷夌揣銆?s" % eq_text
		return "钖勯浘娣卞浼犳潵涓嶅睘浜庝粖澶滅殑鍥為煶锛岀悊鏅轰笌鐩磋閮借杞昏交鎵姩銆?

	if eid == "scarcity_wave":
		ration = max(0, ration - 1)
		coin = max(0, coin - 1)
		_world_apply_region_delta(current_region_id, {"food": -8, "water": -6, "conflict": 4})
		return "琛ョ粰绾垮嚭鐜版柇鍙ｏ紝浣犺杩鑰椾簡涓€浠藉彛绮拰璺垂銆?

	global_arc["danger"] = max(0, d - 2)
	_world_apply_region_delta(current_region_id, {"hazard": -4, "conflict": -3})
	return "宸¤矾鑰呯殑鐏妸鍦ㄨ繙澶勫嚭鐜帮紝灞€鍔跨煭鏆傝秼浜庡畨瀹氥€?

func _roll_creature_variant(base: Dictionary) -> Dictionary:
	if creature_gen == null or not creature_gen.has_method("roll"):
		return base
	var cv_any: Variant = creature_gen.roll(rng, base, current_region_id)
	if not (cv_any is Dictionary):
		return base
	var cv: Dictionary = cv_any as Dictionary
	var key: String = String(cv.get("id", "unknown"))
	creature_codex[key] = int(creature_codex.get(key, 0)) + 1
	return cv

func _join_loot_tags(cv: Dictionary) -> String:
	var lt_any: Variant = cv.get("loot_tags", [])
	if not (lt_any is Array):
		return ""
	var lt: Array = lt_any as Array
	if lt.is_empty():
		return ""
	var names: Array[String] = []
	for v in lt:
		names.append(String(v))
	return "鍙彁鍙栨潗鏂欙細" + "銆?.join(names) + "銆?

func _try_generate_equipment(source: String) -> String:
	if equipment_gen == null or not equipment_gen.has_method("roll"):
		return ""
	var eq_any: Variant = equipment_gen.roll(rng, source)
	if not (eq_any is Dictionary):
		return ""
	var eq: Dictionary = eq_any as Dictionary
	equipment_inventory.append(eq)
	_apply_equipment_impact(eq)
	var mod_text: String = _format_mods(eq.get("mods", {}))
	return "浣犲緱鍒拌澶囷細銆?s銆峓%s] %s锛堝壇浣滅敤锛?s锛? % [
		String(eq.get("name", "鏈煡瑁呭")),
		String(eq.get("rarity_name", "鏅€?)),
		mod_text,
		String(eq.get("side_effect", "鏃?))
	]

func _apply_equipment_impact(eq: Dictionary) -> void:
	var mod_any: Variant = eq.get("mods", {})
	if not (mod_any is Dictionary):
		return
	var mod: Dictionary = mod_any as Dictionary
	for k in mod.keys():
		var v: int = int(mod[k])
		match String(k):
			"str":
				stat_str = _clamp_int(stat_str + v, 1, 99)
			"dex":
				stat_dex = _clamp_int(stat_dex + v, 1, 99)
			"int":
				stat_int = _clamp_int(stat_int + v, 1, 99)
			"cha":
				stat_cha = _clamp_int(stat_cha + v, 1, 99)
			"con":
				stat_con = _clamp_int(stat_con + v, 1, 99)
			"wis":
				stat_wis = _clamp_int(stat_wis + v, 1, 99)
			"hp":
				hp = _clamp_int(hp + v, 0, hp_max)
			"sanity":
				sanity = _clamp_int(sanity + v, 0, sanity_max)
			"hunger":
				hunger = _clamp_int(hunger + v, 0, hunger_max)
			"sleep":
				sleep_energy = _clamp_int(sleep_energy + v, 0, sleep_max)
			"cold":
				cold = _clamp_int(cold + v, 0, cold_max)
			"coin_gain":
				coin += max(0, v)
			_:
				pass

func _format_mods(mod_any: Variant) -> String:
	if not (mod_any is Dictionary):
		return ""
	var mod: Dictionary = mod_any as Dictionary
	var keys := mod.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		var v: float = float(mod[k])
		var sign: String = "+" if v >= 0 else ""
		parts.append("%s%s%s" % [String(k), sign, str(int(v))])
	return "{" + ", ".join(parts) + "}"

# ===== tone / bias 涔樻潈锛堟寜浣?JSON 鐨勯敭锛?====
func _bias_multiplier(_family: String) -> float:
	var mult: float = 1.0

	var tod: String = _time_of_day_name()
	if region_bias.has("time_of_day") and region_bias["time_of_day"] is Dictionary:
		var mp: Dictionary = region_bias["time_of_day"] as Dictionary
		if mp.has(tod):
			mult *= float(mp.get(tod, 1.0))

	var season: String = "spring" # 鍏堝浐瀹氾紝绛変綘鎶?WorldState 鐨勫鑺傛帴杩涙潵
	if region_bias.has("season") and region_bias["season"] is Dictionary:
		var sp: Dictionary = region_bias["season"] as Dictionary
		if sp.has(season):
			mult *= float(sp.get(season, 1.0))

	return mult

func _time_of_day_name() -> String:
	var h: int = time_hours % 24
	if h < 5:
		return "night"
	elif h < 8:
		return "dawn"
	elif h < 18:
		return "day"
	elif h < 20:
		return "dusk"
	else:
		return "night"

# =========================
# === UI 鍏煎閫傞厤灞傦紙鏂板锛?==
# =========================

# 璁?UI 鐨?world.load_region(...) 缁х画鍙敤
func get_backlog_count() -> int:
	return v01_backlog_ids.size()

func get_v01_metrics() -> Dictionary:
	return v01_metrics.duplicate(true)

func _v01_reset_runtime() -> void:
	v01_turn_count = 0
	v01_last_processed_hour = time_hours
	v01_session_nonce = 0
	v01_sessions.clear()
	v01_backlog_ids.clear()
	v01_backlog_pinned.clear()
	v01_active_locked_id = ""
	v01_rumor_queue.clear()
	v01_rumor_history.clear()
	v01_unknown_notice_queue.clear()
	v01_recent_fingerprint_hour.clear()
	v01_guidance_due = true
	v01_region_threads.clear()
	v01_thread_nonce = 0
	v01_turns_since_weird = 0
	v01_metrics = {
		"segment_free_total": 0,
		"segment_free_negative_or_backlash": 0,
		"segment_free_structural": 0,
		"segment_free_info_or_opportunity": 0,
		"ignored_total": 0,
		"ignored_visible_impact": 0,
		"weird_option_seen": 0
	}

func _v01_after_bootstrap(reset_time: bool) -> void:
	if reset_time:
		_v01_reset_runtime()
	if not v01_region_threads.has(current_region_id):
		v01_region_threads[current_region_id] = _v01_seed_threads_for_region(current_region_id)
	v01_guidance_due = true
	v01_last_processed_hour = time_hours
	_v01_process_time_drift()

func _v01_seed_threads_for_region(_rid: String) -> Array[Dictionary]:
	var pool: Array[Dictionary] = [
		{"id":"thread.bandit", "name":"鐩楀尓閾?, "stage":1, "heat":52},
		{"id":"thread.echo", "name":"鍥炲０閾?, "stage":1, "heat":46},
		{"id":"thread.trade", "name":"璐告槗閾?, "stage":1, "heat":38},
		{"id":"thread.plague", "name":"鐦熺柅閾?, "stage":1, "heat":34}
	]
	var wr: Dictionary = _world_current_region()
	if not wr.is_empty():
		var tags_any: Variant = wr.get("tags", [])
		if tags_any is Array:
			var tags: Array = tags_any as Array
			if tags.has("echo"):
				pool[1]["heat"] = 66
			if tags.has("town"):
				pool[2]["heat"] = 58
				pool[0]["heat"] = 46
			if tags.has("wild"):
				pool[0]["heat"] = 62
	var picked: Array[Dictionary] = []
	var work: Array = pool.duplicate(true)
	for _i in range(2):
		if work.is_empty():
			break
		var wrap: Array[Dictionary] = []
		for d_any in work:
			if d_any is Dictionary:
				var d: Dictionary = d_any as Dictionary
				wrap.append({"entry": d, "weight": float(d.get("heat", 30))})
		var p: Dictionary = _weighted_pick(wrap)
		var ent_any: Variant = p.get("entry", {})
		if not (ent_any is Dictionary):
			break
		var ent: Dictionary = (ent_any as Dictionary).duplicate(true)
		picked.append(ent)
		var pid: String = String(ent.get("id", ""))
		var next_work: Array = []
		for d_any2 in work:
			if not (d_any2 is Dictionary):
				continue
			var d2: Dictionary = d_any2 as Dictionary
			if String(d2.get("id", "")) != pid:
				next_work.append(d2)
		work = next_work
	if picked.is_empty():
		picked.append({"id":"thread.bandit", "name":"鐩楀尓閾?, "stage":1, "heat":52})
	return picked

func _v01_region_thread_label() -> String:
	var arr_any: Variant = v01_region_threads.get(current_region_id, [])
	if not (arr_any is Array):
		return "鏃犱富绾?
	var arr: Array = arr_any as Array
	if arr.is_empty():
		return "鏃犱富绾?
	var top_any: Variant = arr[0]
	if not (top_any is Dictionary):
		return "鏃犱富绾?
	var top: Dictionary = top_any as Dictionary
	var n: String = String(top.get("name", "绾跨▼"))
	var stage: int = int(top.get("stage", 1))
	return "%s %d/3" % [n, stage]

func _v01_pick_thread_for_event() -> Dictionary:
	var arr_any: Variant = v01_region_threads.get(current_region_id, [])
	if not (arr_any is Array):
		return {"id":"thread.bandit", "name":"鐩楀尓閾?, "stage":1}
	var arr: Array = arr_any as Array
	if arr.is_empty():
		return {"id":"thread.bandit", "name":"鐩楀尓閾?, "stage":1}
	var wrap: Array[Dictionary] = []
	for d_any in arr:
		if not (d_any is Dictionary):
			continue
		var d: Dictionary = d_any as Dictionary
		wrap.append({"entry": d, "weight": float(d.get("heat", 20))})
	var pick: Dictionary = _weighted_pick(wrap)
	var ent_any: Variant = pick.get("entry", {})
	return ent_any as Dictionary if ent_any is Dictionary else {"id":"thread.bandit", "name":"鐩楀尓閾?, "stage":1}

func _v01_process_time_drift() -> void:
	if time_hours < v01_last_processed_hour:
		v01_last_processed_hour = time_hours
	if time_hours <= v01_last_processed_hour:
		return
	_v01_expire_sessions()
	v01_last_processed_hour = time_hours
	var stale_keys: Array = []
	for k_any in v01_recent_fingerprint_hour.keys():
		var k: String = String(k_any)
		var h: int = int(v01_recent_fingerprint_hour.get(k, 0))
		if time_hours - h > 48:
			stale_keys.append(k)
	for k2 in stale_keys:
		v01_recent_fingerprint_hour.erase(k2)

func _v01_expire_sessions() -> void:
	var expired: Array[String] = []
	for sid_any in v01_sessions.keys():
		var sid: String = String(sid_any)
		var s_any: Variant = v01_sessions.get(sid, {})
		if not (s_any is Dictionary):
			continue
		var s: Dictionary = s_any as Dictionary
		var stype: String = String(s.get("type", "segment_free"))
		var status: String = String(s.get("status", "open"))
		if stype != "segment_free":
			continue
		if status != "backlog" and status != "open":
			continue
		var dl: int = int(s.get("deadline", time_hours + 1))
		if time_hours >= dl:
			expired.append(sid)
	for sid in expired:
		_v01_expire_one_session(sid)

func _v01_expire_one_session(sid: String) -> void:
	var s_any: Variant = v01_sessions.get(sid, {})
	if not (s_any is Dictionary):
		return
	var s: Dictionary = s_any as Dictionary
	var out: Dictionary = _v01_pick_outcome(s, "EXPIRED", "expired")
	_v01_apply_outcome_to_world(s, out, "expired")
	_v01_remove_session_from_backlog(sid)
	v01_sessions.erase(sid)
	v01_metrics["ignored_total"] = int(v01_metrics.get("ignored_total", 0)) + 1
	if _v01_outcome_has_visible_impact(out):
		v01_metrics["ignored_visible_impact"] = int(v01_metrics.get("ignored_visible_impact", 0)) + 1

func _v01_outcome_has_visible_impact(outcome: Dictionary) -> bool:
	var b_any: Variant = outcome.get("buckets", [])
	if not (b_any is Array):
		return false
	for b_any2 in (b_any as Array):
		var b: String = String(b_any2)
		if b == "A" or b == "B" or b == "D" or b == "E":
			return true
	return false

func _v01_remove_session_from_backlog(sid: String) -> void:
	var next_ids: Array[String] = []
	for id in v01_backlog_ids:
		if id != sid:
			next_ids.append(id)
	v01_backlog_ids = next_ids
	var next_pin: Array[String] = []
	for id2 in v01_backlog_pinned:
		if id2 != sid:
			next_pin.append(id2)
	v01_backlog_pinned = next_pin

func _v01_add_backlog(sid: String) -> void:
	if sid == "":
		return
	if not v01_backlog_ids.has(sid):
		v01_backlog_ids.append(sid)

func _v01_backlog_sort_ids() -> Array[String]:
	var pins: Array[String] = []
	var others: Array[String] = []
	for sid in v01_backlog_ids:
		if v01_backlog_pinned.has(sid):
			pins.append(sid)
		else:
			others.append(sid)
	pins.sort_custom(Callable(self, "_v01_backlog_more_urgent"))
	others.sort_custom(Callable(self, "_v01_backlog_more_urgent"))
	var out: Array[String] = []
	for p in pins:
		out.append(p)
	for o in others:
		out.append(o)
	return out

func _v01_backlog_more_urgent(a: String, b: String) -> bool:
	var sa_any: Variant = v01_sessions.get(a, {})
	var sb_any: Variant = v01_sessions.get(b, {})
	if not (sa_any is Dictionary) or not (sb_any is Dictionary):
		return a < b
	var sa: Dictionary = sa_any as Dictionary
	var sb: Dictionary = sb_any as Dictionary
	var ra: int = max(0, int(sa.get("deadline", time_hours + 1)) - time_hours)
	var rb: int = max(0, int(sb.get("deadline", time_hours + 1)) - time_hours)
	if ra == rb:
		return int(sa.get("urgency", 1)) > int(sb.get("urgency", 1))
	return ra < rb

func _v01_find_active_session_by_fingerprint(fp: String) -> String:
	for sid_any in v01_sessions.keys():
		var sid: String = String(sid_any)
		var s_any: Variant = v01_sessions.get(sid, {})
		if not (s_any is Dictionary):
			continue
		var s: Dictionary = s_any as Dictionary
		var status: String = String(s.get("status", "open"))
		if status == "resolved" or status == "expired" or status == "abandoned":
			continue
		if String(s.get("fingerprint", "")) == fp:
			return sid
	return ""

func _v01_should_spawn_free() -> bool:
	if has_pending_choice():
		return false
	if v01_active_locked_id != "":
		return false
	var base: float = 0.26
	base += float(int(global_arc.get("danger", 20))) / 500.0
	base += float(int(global_arc.get("scarcity", 20))) / 700.0
	base -= float(v01_backlog_ids.size()) * 0.03
	base = clamp(base, 0.08, 0.42)
	return rng.randf() <= base

func _v01_should_spawn_locked() -> bool:
	if has_pending_choice():
		return false
	if v01_active_locked_id != "":
		return false
	var danger: int = int(global_arc.get("danger", 20))
	if danger < 28 and rng.randf() > 0.1:
		return false
	var chance: float = 0.08 + float(max(0, danger - 20)) / 260.0
	return rng.randf() <= clamp(chance, 0.06, 0.24)

func _v01_is_town_context() -> bool:
	var wr: Dictionary = _world_current_region()
	if wr.is_empty():
		return false
	var tags_any: Variant = wr.get("tags", [])
	if not (tags_any is Array):
		return false
	var tags: Array = tags_any as Array
	return tags.has("town")

func _v01_array_has_str(arr: Array, target: String) -> bool:
	for x_any in arr:
		if String(x_any) == target:
			return true
	return false

func _v01_default_outcome_set(_thread_id: String) -> Array[Dictionary]:
	return [
		{
			"id":"out.visible_positive",
			"spectrum":"visible_positive",
			"buckets":["A","C"],
			"weight":30.0,
			"text":"浣犵珛鍒诲緱鍒板彲鐢ㄧ嚎绱紝骞舵墦寮€浜嗕竴涓悗缁満浼氥€?,
			"rumor":"鏈変汉璇翠綘鍦ㄧ幇鍦虹暀涓嬩簡鍙潬绾跨储銆?
		},
		{
			"id":"out.hidden_positive",
			"spectrum":"hidden_positive",
			"buckets":["B","C"],
			"weight":25.0,
			"text":"褰撲笅鏀剁泭涓嶆樉锛屼絾浣犺鍏抽敭浜虹墿璁颁綇浜嗐€?,
			"rumor":"鏈変紶瑷€璇翠綘鍜屾煇鑲″娍鍔涘缓绔嬩簡闅愭€ц仈绯汇€?
		},
		{
			"id":"out.visible_negative",
			"spectrum":"visible_negative",
			"buckets":["D"],
			"weight":25.0,
			"text":"浣犱粯鍑轰簡鍗虫椂浠ｄ环锛屼笖椋庨櫓淇″彿涓婂崌銆?,
			"rumor":"璺汉閮藉湪浼犺繖浠朵簨鍙兘浼氬弽鍣€?
		},
		{
			"id":"out.hidden_negative",
			"spectrum":"hidden_negative",
			"buckets":["D","E"],
			"weight":20.0,
			"text":"琛ㄩ潰鏃犱簨锛屼絾灞€鍔跨粨鏋勫凡缁忔倓鎮勬敼鍙樸€?,
			"rumor":"鍏憡鏉夸笂鍑虹幇浜嗕笌姝ょ浉鍏崇殑鏂伴檺鍒躲€?
		}
	]

func _v01_spawn_free_session(trigger_reason: String) -> String:
	var templates: Array[Dictionary] = [
		{"id":"street_help", "title":"琛楀ご姹傚姪", "actors":["娴佹皯","鍟嗕細"], "zone":"town", "urgency":2, "deadline_h":6, "intents":["HELP","ASK","OBSERVE","CALL_AUTHORITY","BRIBE","REFUSE","ESCORT"]},
		{"id":"suspicious_tracks", "title":"鍙枒瓒宠抗", "actors":["宸＄伅闃?], "zone":"wild", "urgency":2, "deadline_h":8, "intents":["OBSERVE","ASK","ESCORT","THREATEN","REFUSE"]},
		{"id":"merchant_dispute", "title":"鍟嗕汉绾犵悍", "actors":["鐏板競","鎶ゅ崼"], "zone":"town", "urgency":1, "deadline_h":10, "intents":["ASK","BRIBE","CALL_AUTHORITY","THREATEN","REFUSE","HELP"]},
		{"id":"roadside_body", "title":"璺竟灏镐綋", "actors":["鏈煡"], "zone":"wild", "urgency":3, "deadline_h":5, "intents":["OBSERVE","ASK","CALL_AUTHORITY","REFUSE","ESCORT"]}
	]
	var wrap: Array[Dictionary] = []
	for t in templates:
		var w: float = 1.0
		if String(t.get("zone", "")) == "town" and _v01_is_town_context():
			w = 1.4
		if String(t.get("zone", "")) == "wild" and not _v01_is_town_context():
			w = 1.4
		wrap.append({"entry": t, "weight": w})
	var pick: Dictionary = _weighted_pick(wrap)
	var tpl_any: Variant = pick.get("entry", {})
	if not (tpl_any is Dictionary):
		return ""
	var tpl: Dictionary = tpl_any as Dictionary
	var fp: String = "%s|%s" % [String(tpl.get("id", "free")), current_region_id]
	var existing: String = _v01_find_active_session_by_fingerprint(fp)
	if existing != "":
		var es_any: Variant = v01_sessions.get(existing, {})
		if es_any is Dictionary:
			var es: Dictionary = es_any as Dictionary
			es["deadline"] = max(int(es.get("deadline", time_hours + 1)), time_hours + 3)
			v01_sessions[existing] = es
		return "Duplicate event merged into backlog."

	v01_session_nonce += 1
	var sid: String = "es_%d" % v01_session_nonce
	var thread: Dictionary = _v01_pick_thread_for_event()
	var session: Dictionary = {
		"id": sid,
		"type": "segment_free",
		"template_id": String(tpl.get("id", "free")),
		"title": String(tpl.get("title", "鏈懡鍚嶄簨浠?)),
		"location_context": {"region": current_region_id, "zone": String(tpl.get("zone", "wild"))},
		"actors": tpl.get("actors", []),
		"thread_id": String(thread.get("id", "")),
		"thread_label": "%s %d/3" % [String(thread.get("name", "绾跨▼")), int(thread.get("stage", 1))],
		"urgency": int(tpl.get("urgency", 2)),
		"deadline": time_hours + int(tpl.get("deadline_h", 8)),
		"stage_index": 0,
		"stage_count": 1,
		"session_state": {"trust":0, "alert":0, "exposure":0, "debt":0, "injury":0},
		"outcome_set": _v01_default_outcome_set(String(thread.get("id", ""))),
		"knowability_rules": {"base":0.25, "distance_penalty":0.35, "network_bonus":0.2, "impact_bonus":0.25},
		"status": "open",
		"fingerprint": fp,
		"trigger_reason": trigger_reason,
		"intents": tpl.get("intents", []),
		"can_abandon": true
	}
	v01_recent_fingerprint_hour[fp] = time_hours
	v01_sessions[sid] = session
	return _v01_offer_session_modal(sid, false, false)

func _v01_spawn_locked_session(trigger_reason: String) -> String:
	v01_session_nonce += 1
	var sid: String = "es_%d" % v01_session_nonce
	var thread: Dictionary = _v01_pick_thread_for_event()
	var steps: int = rng.randi_range(2, 4)
	var title_pool: Array[String] = ["杩介€愬け鎺?, "褰撳満鍐茬獊", "鍧犺惤杩為攣", "鐏娍钄撳欢"]
	var title: String = String(title_pool[rng.randi_range(0, title_pool.size() - 1)])
	var session: Dictionary = {
		"id": sid,
		"type": "segment_locked",
		"template_id": "locked_crisis",
		"title": title,
		"location_context": {"region": current_region_id, "zone": "crisis"},
		"actors": ["鏈煡濞佽儊"],
		"thread_id": String(thread.get("id", "")),
		"thread_label": "%s %d/3" % [String(thread.get("name", "绾跨▼")), int(thread.get("stage", 1))],
		"urgency": 3,
		"deadline": time_hours + 2,
		"stage_index": 0,
		"stage_count": steps,
		"session_state": {"trust":-1, "alert":2, "exposure":2, "debt":0, "injury":0},
		"outcome_set": _v01_default_outcome_set(String(thread.get("id", ""))),
		"knowability_rules": {"base":0.45, "distance_penalty":0.2, "network_bonus":0.25, "impact_bonus":0.35},
		"status": "locked",
		"fingerprint": "%s|%s|%d" % [title, current_region_id, sid.hash()],
		"trigger_reason": trigger_reason,
		"intents": ["DODGE","PRESS","STRIKE","RETREAT"],
		"can_abandon": false
	}
	v01_sessions[sid] = session
	v01_active_locked_id = sid
	return _v01_offer_session_modal(sid, false, false)

func _v01_option_text(title: String, short_term: String, mid_term: String) -> String:
	return "%s\n[鐭湡] %s\n[涓湡] %s" % [title, short_term, mid_term]

func _v01_offer_session_modal(sid: String, from_backlog: bool, use_more_menu: bool) -> String:
	var s_any: Variant = v01_sessions.get(sid, {})
	if not (s_any is Dictionary):
		return ""
	var s: Dictionary = s_any as Dictionary
	s["status"] = "open" if String(s.get("type", "segment_free")) == "segment_free" else "locked"
	v01_sessions[sid] = s
	_pending_choices.clear()
	var choices: Array[Dictionary] = _v01_build_session_choice_set(s, use_more_menu)
	for c in choices:
		_pending_choices.append(c.duplicate(true))
	_has_pending = not _pending_choices.is_empty()
	var remain: int = max(0, int(s.get("deadline", time_hours + 1)) - time_hours)
	var header: String = _v01_format_session_header(s, remain, from_backlog)
	return header

func _v01_format_session_header(session: Dictionary, remain_h: int, from_backlog: bool) -> String:
	var loc: Dictionary = session.get("location_context", {}) as Dictionary
	var actors_any: Variant = session.get("actors", [])
	var actors_txt: String = "鏃?
	if actors_any is Array and not (actors_any as Array).is_empty():
		var parts: Array[String] = []
		for a_any in (actors_any as Array):
			parts.append(String(a_any))
		actors_txt = "/".join(parts)
	var urgency: int = int(session.get("urgency", 1))
	var level_txt: String = "I"
	if urgency == 2:
		level_txt = "II"
	elif urgency >= 3:
		level_txt = "III"
	var title: String = String(session.get("title", "浜嬩欢"))
	var head: Array[String] = []
	head.append("[b]%s[/b]" % title)
	head.append("鍦扮偣: %s | 鐗垫秹: %s" % [String(loc.get("region", current_region_id)), actors_txt])
	head.append("瑙﹀彂: %s" % String(session.get("trigger_reason", "灞€鍔夸俊鍙?)))
	head.append("灞€鍔跨瓑绾? %s | 绾跨▼: %s" % [level_txt, String(session.get("thread_label", _v01_region_thread_label()))])
	if String(session.get("type", "segment_free")) == "segment_free":
		var line: String = "鎴: %dh | 鍓╀綑: %dh" % [int(session.get("deadline", time_hours + 1)), remain_h]
		if from_backlog:
			line = "浠庢湭澶勭悊鍒楄〃鎭㈠ | " + line
		head.append(line)
	else:
		head.append("杩炴浜嬩欢: 闇€瑕佽繛缁鐞?%d 姝ワ紙鑷敱琛屽姩鏆備笉鍙敤锛? % int(session.get("stage_count", 2)))
	return "\n".join(head)

func _v01_dedupe_intent_descriptors(items: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for d_any in items:
		if not (d_any is Dictionary):
			continue
		var d: Dictionary = d_any as Dictionary
		var key: String = String(d.get("intent", ""))
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		out.append(d)
	return out

func _v01_generate_option_descriptors(session: Dictionary) -> Array[Dictionary]:
	var intents_any: Variant = session.get("intents", [])
	var intents: Array = intents_any as Array if intents_any is Array else []
	var out: Array[Dictionary] = []
	var is_town: bool = _v01_is_town_context()
	var has_coin: bool = coin >= 2
	var has_ration: bool = ration > 0
	var danger: int = int(global_arc.get("danger", 20))

	for it_any in intents:
		var it: String = String(it_any)
		if it == "CALL_AUTHORITY" and not is_town:
			continue
		if it == "BRIBE" and not has_coin:
			continue
		if it == "HELP" and not (has_ration or has_coin):
			continue
		if it == "ESCORT" and stat_con < 9:
			continue
		if it == "THREATEN" and stat_str < 11:
			continue
		match it:
			"DODGE":
				out.append({"intent":"DODGE", "title":"瑙勯伩鍐插嚮", "short":"娑堣€?h锛屼綆鍙椾激姒傜巼", "mid":"闄嶄綆鏆撮湶骞剁ǔ瀹氬眬鍔?})
			"PRESS":
				out.append({"intent":"PRESS", "title":"鍘嬬嚎鎺ㄨ繘", "short":"楂橀闄╅珮鎺ㄨ繘", "mid":"鍙兘蹇€熸敹鏉熶篃鍙兘鍙嶅櫖"})
			"STRIKE":
				out.append({"intent":"STRIKE", "title":"姝ｉ潰鍘嬪埗", "short":"娑堣€椾綋鍔涘苟鎻愰珮鍙椾激椋庨櫓", "mid":"寮鸿鎺ㄥ姩绾跨▼杩涘害"})
			"RETREAT":
				out.append({"intent":"RETREAT", "title":"鎴樻湳鍚庢挙", "short":"鍑忓皯褰撳墠鎹熷け", "mid":"鍙兘鏀惧ぇ鍚庣画椋庨櫓"})
			"HELP":
				out.append({"intent":"HELP", "title":"鐩存帴鎻村姪", "short":"娑堣€楀彛绮垨闆堕挶", "mid":"鎻愬崌鍏崇郴骞跺彲鑳借幏寰楀紩鑽?})
			"ASK":
				out.append({"intent":"ASK", "title":"杩介棶缁嗚妭", "short":"鑺辫垂1h锛屼綆椋庨櫓", "mid":"鎻愰珮淇℃伅绫讳笌鏈轰細绫荤粨鏋?})
			"OBSERVE":
				out.append({"intent":"OBSERVE", "title":"鍏堣瀵?, "short":"璋ㄦ厧璇曟帰锛屼唬浠峰彲鎺?, "mid":"鍋忓悜淇℃伅鏀剁泭锛屾帹杩涜緝鎱?})
			"CALL_AUTHORITY":
				var mid: String = "娌诲畨楂樻椂鏇寸ǔ锛屾不瀹変綆鏃跺彲鑳借鍙嶅挰"
				if danger >= 45:
					mid = "褰撳墠娌诲畨鍋忎綆锛屽彲鑳藉紩鍙戝弽鍣?
				out.append({"intent":"CALL_AUTHORITY", "title":"鍛煎彨瀹樻柟鍔垮姏", "short":"鐭湡鍙檷椋庨櫓", "mid":mid})
			"BRIBE":
				out.append({"intent":"BRIBE", "title":"鐢ㄩ挶鎵撶偣", "short":"閲戝竵-2锛屽揩閫熷紑璺?, "mid":"鍙兘寤虹珛闅愬€哄叧绯?})
			"THREATEN":
				out.append({"intent":"THREATEN", "title":"鏂藉帇鎭愬悡", "short":"鐭湡鍘嬩綇鍦洪潰", "mid":"涓湡鏄撹Е鍙戞晫鎰忎笌浼犻椈"})
			"ESCORT":
				out.append({"intent":"ESCORT", "title":"鎶ら€佺鍦?, "short":"鑰楁椂鏇撮暱浣嗘洿绋?, "mid":"鏈轰細鍚戞敹鐩婅緝楂?})
			"REFUSE":
				out.append({"intent":"REFUSE", "title":"鎷掔粷浠嬪叆", "short":"绔嬪嵆鑴辩椋庨櫓", "mid":"鍚庣画鍙兘鍑虹幇闅愭€у弽鍣?})
			_:
				out.append({"intent":"OBSERVE", "title":"璋ㄦ厧澶勭悊", "short":"缁存寔瀹夊叏杈归檯", "mid":"缂撴參鎺ㄨ繘"})

	var has_refuse: bool = false
	for d in out:
		if String(d.get("intent", "")) == "REFUSE":
			has_refuse = true
			break
	if not has_refuse:
		out.append({"intent":"REFUSE", "title":"鎷掔粷浠嬪叆", "short":"绔嬪嵆鑴辩椋庨櫓", "mid":"鍚庣画鍙兘鍑虹幇闅愭€у弽鍣?})

	var weird_needed: bool = v01_turns_since_weird >= 8
	if weird_needed or rng.randf() < 0.33:
		out.append({
			"intent":"ODD_ROUTE",
			"title":"璧版璺瘯璇?,
			"short":"鏀剁泭涓嶅彲棰勬祴锛屽彲鑳界櫧蹇?,
			"mid":"鍙兘瑙﹀彂濂囨€紶闂汇€佹€汉鍏崇郴鎴栧洖澹板悗鏋?
		})
		v01_metrics["weird_option_seen"] = int(v01_metrics.get("weird_option_seen", 0)) + 1
		v01_turns_since_weird = 0

	return _v01_dedupe_intent_descriptors(out)

func _v01_build_session_choice_set(session: Dictionary, use_more_menu: bool) -> Array[Dictionary]:
	var sid: String = String(session.get("id", ""))
	var stype: String = String(session.get("type", "segment_free"))
	var descs: Array[Dictionary] = _v01_generate_option_descriptors(session)
	var choices: Array[Dictionary] = []
	var intent_choices: Array[Dictionary] = []
	for d_any in descs:
		if not (d_any is Dictionary):
			continue
		var d: Dictionary = d_any as Dictionary
		var intent: String = String(d.get("intent", "OBSERVE"))
		intent_choices.append({
			"id": "v01_%s_%s" % [sid, intent],
			"text": _v01_option_text(String(d.get("title", intent)), String(d.get("short", "")), String(d.get("mid", ""))),
			"system_action": "sys.v01.session.%s.intent.%s" % [sid, intent]
		})

	var overflow: Array[Dictionary] = []
	if stype == "segment_free":
		var max_main_intents: int = 3
		if use_more_menu:
			max_main_intents = 99
		if intent_choices.size() > max_main_intents:
			for i in range(max_main_intents, intent_choices.size()):
				overflow.append(intent_choices[i])
			intent_choices = intent_choices.slice(0, max_main_intents)
		for c in intent_choices:
			choices.append(c)
		if not overflow.is_empty() and not use_more_menu:
			choices.append({
				"id":"v01_%s_more" % sid,
				"text":"鏇村鏂规\n[鐭湡] 鏌ョ湅鍏跺畠鍙璺緞\n[涓湡] 鍙兘鍑虹幇楂橀闄╂垨鎬€夐」",
				"system_action":"sys.v01.session.%s.more" % sid
			})
		choices.append({
			"id":"v01_%s_later" % sid,
			"text":"绋嶅悗澶勭悊锛堟斁鍏ユ湭澶勭悊鍒楄〃锛塡n[鐭湡] 绔嬪嵆鑴辫韩锛屼笉娑堣€楄祫婧怽n[涓湡] 浜嬩欢浼氱户缁帹杩涘苟鍙兘杩囨湡",
			"system_action":"sys.v01.session.%s.later" % sid
		})
		if use_more_menu:
			choices.append({
				"id":"v01_%s_abandon" % sid,
				"text":"鏀惧純骞剁寮€\n[鐭湡] 绔嬪埢缁撴潫浜嬩欢\n[涓湡] 鍐欏洖鍏崇郴/椋庨櫓/浼犻椈涔嬩竴",
				"system_action":"sys.v01.session.%s.abandon" % sid
			})
			choices.append({
				"id":"v01_%s_back_main" % sid,
				"text":"杩斿洖涓婚€夐」\n[鐭湡] 鍥炲埌绮剧畝鎸夐挳\n[涓湡] 渚夸簬蹇€熷喅绛?,
				"system_action":"sys.v01.session.%s.back_main" % sid
			})
	else:
		for c2 in intent_choices.slice(0, min(5, intent_choices.size())):
			choices.append(c2)
	return choices

func _v01_bucket_contains(outcome: Dictionary, bucket: String) -> bool:
	var b_any: Variant = outcome.get("buckets", [])
	if not (b_any is Array):
		return false
	for x_any in (b_any as Array):
		if String(x_any) == bucket:
			return true
	return false

func _v01_pick_outcome(session: Dictionary, intent: String, mode: String) -> Dictionary:
	var set_any: Variant = session.get("outcome_set", [])
	if not (set_any is Array):
		return {}
	var set_arr: Array = set_any as Array
	var pool: Array[Dictionary] = []
	for o_any in set_arr:
		if not (o_any is Dictionary):
			continue
		var o: Dictionary = o_any as Dictionary
		var w: float = float(o.get("weight", 1.0))
		var spectrum: String = String(o.get("spectrum", ""))
		if mode == "expired":
			if spectrum.find("negative") >= 0:
				w *= 1.45
			if _v01_bucket_contains(o, "E"):
				w *= 1.25
		elif intent == "HELP" or intent == "ASK" or intent == "ESCORT":
			if spectrum.find("positive") >= 0:
				w *= 1.35
		elif intent == "REFUSE" or intent == "THREATEN" or intent == "RETREAT":
			if spectrum.find("negative") >= 0:
				w *= 1.35
		elif intent == "ODD_ROUTE":
			if _v01_bucket_contains(o, "A") or _v01_bucket_contains(o, "D"):
				w *= 1.45
		pool.append({"entry": o, "weight": max(0.1, w)})
	var p: Dictionary = _weighted_pick(pool)
	var out_any: Variant = p.get("entry", {})
	return out_any as Dictionary if out_any is Dictionary else {}

func _v01_route_knowability(session: Dictionary, outcome: Dictionary, mode: String) -> void:
	var know: String = _v01_roll_knowability(session, outcome, mode)
	var rumor_base: String = String(outcome.get("rumor", "鏈変汉鎻愬埌涓€浠舵棫浜嬪彂鐢熶簡鍙樺寲銆?))
	var title: String = String(session.get("title", "浜嬩欢"))
	if know == "full":
		_v01_push_rumor("[浼犻椈] %s锛?s" % [title, rumor_base], String(session.get("id", "")))
	elif know == "partial":
		var partial: String = rumor_base
		if rng.randf() < 0.35:
			partial = "鐗堟湰涓嶄竴锛氭湁浜鸿杩欎簨鍜屼綘鏈夊叧锛屼篃鏈変汉鍚﹁銆?
		_v01_push_rumor("[浼犻椈-涓嶅畬鏁碷 %s" % partial, String(session.get("id", "")))
	else:
		v01_unknown_notice_queue.append("鏈変簺鍚庢灉娌℃湁鍥炴祦鍒颁綘杩欓噷锛堜綘宸茬寮€褰撳湴鎴栨秷鎭柇灞傦級銆?)
		if v01_unknown_notice_queue.size() > 4:
			v01_unknown_notice_queue.pop_front()

func _v01_roll_knowability(session: Dictionary, outcome: Dictionary, mode: String) -> String:
	if mode == "handled":
		return "full"
	var rules_any: Variant = session.get("knowability_rules", {})
	var rules: Dictionary = rules_any as Dictionary if rules_any is Dictionary else {}
	var p_full: float = float(rules.get("base", 0.2))
	var p_partial: float = 0.38
	var same_region: bool = String((session.get("location_context", {}) as Dictionary).get("region", "")) == current_region_id
	if same_region:
		p_full += 0.25
	else:
		p_full -= float(rules.get("distance_penalty", 0.3))
	if int(counters.get("insight", 0)) > 0 or int(relations.get("grey_market", 0)) > 0:
		p_full += float(rules.get("network_bonus", 0.2))
	if _v01_bucket_contains(outcome, "E"):
		p_full += float(rules.get("impact_bonus", 0.2))
	p_full = clamp(p_full, 0.02, 0.9)
	p_partial = clamp(p_partial, 0.05, 0.8)
	var r: float = rng.randf()
	if r <= p_full:
		return "full"
	if r <= p_full + p_partial:
		return "partial"
	return "unknown"

func _v01_push_rumor(text: String, source_id: String) -> void:
	if text == "":
		return
	v01_rumor_queue.append({
		"text": text,
		"source_id": source_id,
		"time_h": time_hours
	})
	if v01_rumor_queue.size() > 16:
		v01_rumor_queue.pop_front()

func _v01_pop_rumor_line() -> String:
	if not v01_rumor_queue.is_empty():
		var r_any: Variant = v01_rumor_queue.pop_front()
		if r_any is Dictionary:
			var r: Dictionary = r_any as Dictionary
			var t: String = String(r.get("text", ""))
			if t != "":
				v01_rumor_history.append(t)
				if v01_rumor_history.size() > 12:
					v01_rumor_history.pop_front()
				return t
	if not v01_unknown_notice_queue.is_empty():
		return "[娑堟伅鏂眰] " + String(v01_unknown_notice_queue.pop_front())
	return ""

func _v01_apply_thread_structural_change(thread_id: String, mode: String) -> void:
	var label: String = thread_id.replace("thread.", "")
	if mode == "expired":
		_world_apply_region_delta(current_region_id, {"conflict": 8, "hazard": 6})
		_world_queue_news("绾跨▼鏀舵潫锛堟伓鍖栵級锛?s 鍦ㄦ湰鍦板尯閫犳垚闀挎湡鍘嬪姏鍙樺寲銆? % label)
	else:
		_world_apply_region_delta(current_region_id, {"conflict": -8, "hazard": -4})
		_world_queue_news("绾跨▼鏀舵潫锛堥噸缃級锛?s 鏀瑰啓浜嗚鍦板尯鐨勯暱鏈熷眬鍔裤€? % label)

func _v01_advance_thread_progress(thread_id: String, buckets: Array, mode: String) -> void:
	if thread_id == "":
		return
	var arr_any: Variant = v01_region_threads.get(current_region_id, [])
	if not (arr_any is Array):
		return
	var arr: Array = arr_any as Array
	var changed: bool = false
	for i in range(arr.size()):
		var t_any: Variant = arr[i]
		if not (t_any is Dictionary):
			continue
		var t: Dictionary = t_any as Dictionary
		if String(t.get("id", "")) != thread_id:
			continue
		var stage: int = int(t.get("stage", 1))
		var heat: int = int(t.get("heat", 40))
		if mode == "expired":
			heat += 5
			if _v01_array_has_str(buckets, "D") or _v01_array_has_str(buckets, "E"):
				stage = min(3, stage + 1)
		else:
			heat = max(18, heat - 2)
			if _v01_array_has_str(buckets, "A") or _v01_array_has_str(buckets, "C"):
				stage = min(3, stage + 1)
		t["heat"] = _clamp_int(heat, 10, 90)
		t["stage"] = stage
		arr[i] = t
		changed = true
		if stage >= 3:
			_v01_apply_thread_structural_change(thread_id, mode)
		break
	if changed:
		v01_region_threads[current_region_id] = arr

func _v01_apply_outcome_to_world(session: Dictionary, outcome: Dictionary, mode: String) -> void:
	var buckets_any: Variant = outcome.get("buckets", [])
	var buckets: Array = buckets_any as Array if buckets_any is Array else []
	var title: String = String(session.get("title", "浜嬩欢"))
	var thread_id: String = String(session.get("thread_id", ""))
	var thread_line: String = ""
	if thread_id != "":
		thread_line = "锛?s锛? % String(session.get("thread_label", "绾跨▼"))

	var has_info_or_opp: bool = false
	var has_negative: bool = false
	var has_structural: bool = false
	for b_any in buckets:
		var b: String = String(b_any)
		match b:
			"A":
				_add_counter("intel_clues", 1)
				_add_counter("thread_clue_" + thread_id, 1)
				has_info_or_opp = true
			"B":
				relations["locals"] = int(relations.get("locals", 0)) + (1 if mode != "expired" else -1)
			"C":
				_add_counter("opportunity_tokens", 1)
				_set_flag("opportunity_" + thread_id.replace(".", "_"), true)
				has_info_or_opp = true
			"D":
				global_arc["danger"] = _clamp_int(int(global_arc.get("danger", 20)) + 4, 0, 100)
				global_arc["order"] = _clamp_int(int(global_arc.get("order", 40)) - 2, 0, 100)
				_expose_tags(["risk", "faction"], 1.0)
				has_negative = true
			"E":
				has_structural = true
				var delta: Dictionary = {
					"hazard": rng.randi_range(-4, 8),
					"conflict": rng.randi_range(-3, 7)
				}
				if mode == "expired":
					delta["hazard"] = int(delta.get("hazard", 0)) + 3
					delta["conflict"] = int(delta.get("conflict", 0)) + 2
				_world_apply_region_delta(current_region_id, delta)
				if rng.randf() < 0.5:
					_set_flag("route_blocked_" + current_region_id, true)
					_world_queue_news("璺綉鍙樺姩锛?s 闄勮繎鍑虹幇鏂扮殑灏侀攣杩硅薄銆? % current_region_id)
				else:
					_set_flag("route_open_" + current_region_id, true)
					_world_queue_news("璺綉鍙樺姩锛?s 鍑虹幇浜嗕竴鏉″彲缁曡灏忛亾銆? % current_region_id)
			_:
				pass

	_world_sync_global_arc()
	_v01_advance_thread_progress(thread_id, buckets, mode)

	if String(session.get("type", "segment_free")) == "segment_free":
		v01_metrics["segment_free_total"] = int(v01_metrics.get("segment_free_total", 0)) + 1
		if has_negative:
			v01_metrics["segment_free_negative_or_backlash"] = int(v01_metrics.get("segment_free_negative_or_backlash", 0)) + 1
		if has_structural:
			v01_metrics["segment_free_structural"] = int(v01_metrics.get("segment_free_structural", 0)) + 1
		if has_info_or_opp:
			v01_metrics["segment_free_info_or_opportunity"] = int(v01_metrics.get("segment_free_info_or_opportunity", 0)) + 1

	_chronicle_push("%s%s -> %s" % [title, thread_line, String(outcome.get("id", "outcome"))])
	_v01_route_knowability(session, outcome, mode)

func _v01_open_backlog_menu() -> Dictionary:
	_pending_choices.clear()
	var ids: Array[String] = _v01_backlog_sort_ids()
	var top_n: int = min(5, ids.size())
	for i in range(top_n):
		var sid: String = ids[i]
		var s_any: Variant = v01_sessions.get(sid, {})
		if not (s_any is Dictionary):
			continue
		var s: Dictionary = s_any as Dictionary
		var remain: int = max(0, int(s.get("deadline", time_hours + 1)) - time_hours)
		var pinned: String = "[缃《]" if v01_backlog_pinned.has(sid) else ""
		var urgency: int = int(s.get("urgency", 1))
		var urgency_tag: String = "鍙兘閿欒繃鏈轰細"
		if urgency >= 3:
			urgency_tag = "鍙兘鎭跺寲"
		elif urgency == 2:
			urgency_tag = "鍙兘琚粬浜鸿В鍐?
		var label: String = "%s%s @%s 鍓╀綑%dh" % [
			pinned,
			String(s.get("title", sid)),
			String((s.get("location_context", {}) as Dictionary).get("region", current_region_id)),
			remain
		]
		label += " [%s] [%s]" % [urgency_tag, String(s.get("thread_label", "鏃犵嚎绋?))]
		_pending_choices.append({
			"id":"v01_backlog_pick_" + sid,
			"text": label,
			"system_action":"sys.v01.backlog.pick." + sid
		})
	_pending_choices.append({
		"id":"v01_backlog_close",
		"text":"鍏抽棴\n[鐭湡] 杩斿洖鑷敱琛屽姩\n[涓湡] 涓嶆敼鍙樹换浣曠姸鎬?,
		"system_action":"sys.v01.backlog.close"
	})
	_has_pending = not _pending_choices.is_empty()
	return _action_result("鏈鐞嗕簨浠讹紙%d锛夊凡灞曞紑銆傚彲缁х画銆佹斁寮冩垨缃《杩借釜銆? % v01_backlog_ids.size())

func _v01_open_backlog_item_menu(sid: String) -> Dictionary:
	var s_any: Variant = v01_sessions.get(sid, {})
	if not (s_any is Dictionary):
		return _action_result("璇ュ緟鍔炲凡澶辨晥銆?)
	var s: Dictionary = s_any as Dictionary
	var remain: int = max(0, int(s.get("deadline", time_hours + 1)) - time_hours)
	_pending_choices.clear()
	_pending_choices.append({
		"id":"v01_backlog_resume_" + sid,
		"text":"缁х画澶勭悊\n[鐭湡] 鍥炲埌褰撳墠闃舵\n[涓湡] 鍙兘浜夊彇鏈轰細骞跺奖鍝嶇嚎绋?,
		"system_action":"sys.v01.backlog.resume." + sid
	})
	_pending_choices.append({
		"id":"v01_backlog_abandon_" + sid,
		"text":"鏀惧純\n[鐭湡] 绔嬪埢缁撴\n[涓湡] 鍐欏洖鍏崇郴/椋庨櫓/浼犻椈涔嬩竴",
		"system_action":"sys.v01.backlog.abandon." + sid
	})
	if v01_backlog_pinned.has(sid):
		_pending_choices.append({
			"id":"v01_backlog_unpin_" + sid,
			"text":"鍙栨秷缃《\n[鐭湡] 浠庤拷韪垪琛ㄧЩ闄n[涓湡] 浠呭奖鍝嶆帓搴?,
			"system_action":"sys.v01.backlog.unpin." + sid
		})
	else:
		_pending_choices.append({
			"id":"v01_backlog_pin_" + sid,
			"text":"缃《杩借釜\n[鐭湡] 璇ヤ簨浠朵紭鍏堟樉绀篭n[涓湡] 闄嶄綆閬楀繕椋庨櫓",
			"system_action":"sys.v01.backlog.pin." + sid
		})
	_pending_choices.append({
		"id":"v01_backlog_return",
		"text":"杩斿洖鏈鐞嗗垪琛╘n[鐭湡] 鍥炰笂涓€灞俓n[涓湡] 涓嶆敼鍙樹簨浠?,
		"system_action":"sys.v01.backlog.open"
	})
	_has_pending = true
	return _action_result("寰呭姙锛?s锛堝墿浣?dh锛? % [String(s.get("title", sid)), remain])

func _v01_remove_pin_only(sid: String) -> void:
	var out: Array[String] = []
	for id in v01_backlog_pinned:
		if id != sid:
			out.append(id)
	v01_backlog_pinned = out

func _v01_resume_session_from_backlog(sid: String) -> Dictionary:
	var s_any: Variant = v01_sessions.get(sid, {})
	if not (s_any is Dictionary):
		return _action_result("璇ュ緟鍔炲凡涓嶅瓨鍦ㄣ€?)
	_v01_remove_session_from_backlog(sid)
	return _action_result(_v01_offer_session_modal(sid, true, false))

func _v01_put_session_to_backlog(sid: String) -> Dictionary:
	var s_any: Variant = v01_sessions.get(sid, {})
	if not (s_any is Dictionary):
		return _action_result("浜嬩欢宸蹭笉鍙鐞嗐€?)
	var s: Dictionary = s_any as Dictionary
	s["status"] = "backlog"
	v01_sessions[sid] = s
	_v01_add_backlog(sid)
	_pending_choices.clear()
	_has_pending = false
	return _action_result("浜嬩欢宸叉斁鍏ユ湭澶勭悊鍒楄〃銆傝秴杩囨埅姝㈡椂闂翠細鑷姩杩囨湡骞跺啓鍥炰笘鐣屻€?)

func _v01_abandon_session(sid: String) -> Dictionary:
	var s_any: Variant = v01_sessions.get(sid, {})
	if not (s_any is Dictionary):
		return _action_result("浜嬩欢宸茬粨鏉熴€?)
	var s: Dictionary = s_any as Dictionary
	var out: Dictionary = _v01_pick_outcome(s, "REFUSE", "abandon")
	_v01_apply_outcome_to_world(s, out, "abandon")
	_v01_remove_session_from_backlog(sid)
	v01_sessions.erase(sid)
	if v01_active_locked_id == sid:
		v01_active_locked_id = ""
	_pending_choices.clear()
	_has_pending = false
	return _action_result("You abandoned this session. %s" % String(out.get("text", "")))

func _v01_apply_session_intent(sid: String, intent: String) -> Dictionary:
	var s_any: Variant = v01_sessions.get(sid, {})
	if not (s_any is Dictionary):
		return _action_result("Session window already closed.")
	var s: Dictionary = s_any as Dictionary
	var stype: String = String(s.get("type", "segment_free"))
	time_hours += 1
	_survival_tick(1)
	_v01_process_time_drift()

	if intent == "ODD_ROUTE":
		s["session_state"] = {"trust":-1, "alert":2, "exposure":2, "debt":0, "injury":0}
		v01_sessions[sid] = s

	if stype == "segment_locked":
		var step: int = int(s.get("stage_index", 0)) + 1
		var total: int = int(s.get("stage_count", 2))
		s["stage_index"] = step
		v01_sessions[sid] = s
		if step < total:
			var prompt: String = _v01_offer_session_modal(sid, false, false)
			return _action_result("Locked segment progress %d/%d.\n%s" % [step, total, prompt])
		var out_locked: Dictionary = _v01_pick_outcome(s, intent, "handled")
		_v01_apply_outcome_to_world(s, out_locked, "handled")
		v01_sessions.erase(sid)
		v01_active_locked_id = ""
		_pending_choices.clear()
		_has_pending = false
		return _action_result("Locked segment finished. %s" % String(out_locked.get("text", "")))

	var out: Dictionary = _v01_pick_outcome(s, intent, "handled")
	_v01_apply_outcome_to_world(s, out, "handled")
	_v01_remove_session_from_backlog(sid)
	v01_sessions.erase(sid)
	_pending_choices.clear()
	_has_pending = false
	return _action_result(String(out.get("text", "Session resolved.")))

func _v01_build_guidance_block() -> String:
	var percepts: Array[String] = []
	var reminders: Array[String] = []
	var next_actions: Array[String] = []
	var danger: int = int(global_arc.get("danger", 20))
	var scarcity: int = int(global_arc.get("scarcity", 20))
	var is_town: bool = _v01_is_town_context()
	if is_town:
		percepts.append("Town board has two new conflict notices.")
		percepts.append("Travelers mention a trade road may be blocked.")
	else:
		percepts.append("Fresh tracks appear at the fork ahead.")
		percepts.append("Wind shifted; distant metal echoes repeat.")
	if danger >= 45:
		percepts.append("Threat pressure is rising in this area.")
	if scarcity >= 40:
		percepts.append("Supply pressure is high and prices are rising.")

	reminders.append("Backlog events: %d." % v01_backlog_ids.size())
	reminders.append("Active thread: %s." % _v01_region_thread_label())
	if ration <= 2:
		reminders.append("Rations are low; long pushes are risky.")

	var offers: Array[Dictionary] = _get_action_offers_v01()
	for it in offers:
		var id: String = String(it.get("id", ""))
		if id.begins_with("sys.v01.backlog") or id == "sys.v01.rumor.feed":
			continue
		next_actions.append(String(it.get("text", id)))
		if next_actions.size() >= 4:
			break
	if next_actions.is_empty():
		next_actions.append("Observe and re-plan route.")

	var lines: Array[String] = []
	lines.append("[b]GuidanceBlock[/b]")
	lines.append("Percepts:")
	for p in percepts.slice(0, 4):
		lines.append("- " + p)
	lines.append("Reminders:")
	for r in reminders.slice(0, 3):
		lines.append("- " + r)
	lines.append("Next Actions:")
	for a in next_actions.slice(0, 5):
		lines.append("- " + a)
	return "\n".join(lines)

func _produce_snapshot_v01(_opts: Dictionary={}) -> Dictionary:
	var snap: Dictionary = {}
	_v01_process_time_drift()

	if has_pending_choice():
		snap["event_text"] = "Pending event stage: resolve it now or move to backlog."
		return _decorate_snapshot(snap)

	v01_turn_count += 1
	v01_turns_since_weird += 1
	time_hours += 1
	_survival_tick(1)
	_v01_process_time_drift()

	var collapse_text: String = _check_collapse_text()
	if collapse_text != "":
		snap["event_text"] = collapse_text
		return _decorate_snapshot(snap)

	var w: Dictionary = _pick_weather_once()
	if not w.is_empty():
		snap["weather"] = w

	if v01_active_locked_id != "":
		var locked_prompt: String = _v01_offer_session_modal(v01_active_locked_id, false, false)
		if locked_prompt != "":
			snap["event_text"] = locked_prompt
			return _decorate_snapshot(snap)

	if v01_guidance_due:
		v01_guidance_due = false
		snap["event_text"] = _v01_build_guidance_block()
		return _decorate_snapshot(snap)

	if _v01_should_spawn_locked():
		var lock_text: String = _v01_spawn_locked_session("crisis threshold")
		if lock_text != "":
			snap["event_text"] = lock_text
			return _decorate_snapshot(snap)

	if _v01_should_spawn_free():
		var free_text: String = _v01_spawn_free_session("regional signal")
		if free_text != "":
			snap["event_text"] = free_text
			return _decorate_snapshot(snap)

	if rng.randf() < 0.32:
		var rumor: String = _v01_pop_rumor_line()
		if rumor != "":
			snap["event_text"] = rumor
			return _decorate_snapshot(snap)

	var idle_lines: Array[String] = []
	idle_lines.append("You continue in the free-action main loop.")
	if not v01_backlog_ids.is_empty():
		idle_lines.append("Backlog events: %d (resume anytime)." % v01_backlog_ids.size())
	idle_lines.append("Active thread: %s" % _v01_region_thread_label())
	snap["event_text"] = "\n".join(idle_lines)
	return _decorate_snapshot(snap)

func _get_action_offers_v01() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	if _get_flag("run_ended"):
		return offers

	offers.append({"id":"sys.v01.backlog.open", "text":"Backlog(%d)" % v01_backlog_ids.size(), "weight":90.0})
	offers.append({"id":"sys.v01.rumor.feed", "text":"Rumor Feed", "weight":72.0})

	if v01_active_locked_id != "":
		offers.append({"id":"sys.v01.session.%s.continue" % v01_active_locked_id, "text":"Continue Locked Segment", "weight":100.0})
		return offers

	if _v01_is_town_context():
		offers.append({"id":"sys.observe", "text":"Ask Around", "weight":70.0})
		offers.append({"id":"sys.trade", "text":"Trade", "weight":62.0})
		offers.append({"id":"sys.v01.work", "text":"Work", "weight":50.0})
		offers.append({"id":"sys.scout", "text":"Visit/Scout", "weight":46.0})
		offers.append({"id":"sys.rest", "text":"Rest", "weight":52.0})
	else:
		offers.append({"id":"sys.push", "text":"Push Forward", "weight":66.0})
		offers.append({"id":"sys.observe", "text":"Observe", "weight":64.0})
		offers.append({"id":"sys.forage", "text":"Forage", "weight":60.0})
		offers.append({"id":"sys.hunt", "text":"Track/Hunt", "weight":58.0})
		offers.append({"id":"sys.rest", "text":"Rest", "weight":50.0})

	if not v01_backlog_ids.is_empty():
		var ids: Array[String] = _v01_backlog_sort_ids()
		var top_id: String = ids[0]
		var s_any: Variant = v01_sessions.get(top_id, {})
		if s_any is Dictionary:
			var s: Dictionary = s_any as Dictionary
			offers.append({
				"id":"sys.v01.backlog.resume." + top_id,
				"text":"Resume: %s" % String(s.get("title", top_id)),
				"weight":84.0
			})
	return offers

func _with_handled(out_any: Variant) -> Dictionary:
	if not (out_any is Dictionary):
		return {"handled": true, "text": String(out_any)}
	var d: Dictionary = out_any as Dictionary
	d["handled"] = true
	return d

func _apply_system_choice_v01(choice_id: String) -> Dictionary:
	if choice_id == "sys.v01.backlog.open":
		return _with_handled(_v01_open_backlog_menu())
	if choice_id == "sys.v01.rumor.feed":
		var rumor: String = _v01_pop_rumor_line()
		if rumor == "":
			rumor = "No new rumor. Some outcomes may remain unknown forever."
		return _with_handled(_action_result(rumor))
	if choice_id == "sys.v01.work":
		time_hours += 2
		_survival_tick(2)
		coin += rng.randi_range(0, 2)
		_v01_process_time_drift()
		return _with_handled(_action_result("You worked for a while; income was unstable but useful."))

	if choice_id.begins_with("sys.v01.backlog.pick."):
		var sid_pick: String = choice_id.trim_prefix("sys.v01.backlog.pick.")
		return _with_handled(_v01_open_backlog_item_menu(sid_pick))
	if choice_id.begins_with("sys.v01.backlog.resume."):
		var sid_resume: String = choice_id.trim_prefix("sys.v01.backlog.resume.")
		return _with_handled(_v01_resume_session_from_backlog(sid_resume))
	if choice_id.begins_with("sys.v01.backlog.abandon."):
		var sid_abandon: String = choice_id.trim_prefix("sys.v01.backlog.abandon.")
		return _with_handled(_v01_abandon_session(sid_abandon))
	if choice_id.begins_with("sys.v01.backlog.pin."):
		var sid_pin: String = choice_id.trim_prefix("sys.v01.backlog.pin.")
		if not v01_backlog_pinned.has(sid_pin):
			v01_backlog_pinned.append(sid_pin)
		return _with_handled(_v01_open_backlog_item_menu(sid_pin))
	if choice_id.begins_with("sys.v01.backlog.unpin."):
		var sid_unpin: String = choice_id.trim_prefix("sys.v01.backlog.unpin.")
		_v01_remove_pin_only(sid_unpin)
		return _with_handled(_v01_open_backlog_item_menu(sid_unpin))
	if choice_id == "sys.v01.backlog.close":
		_pending_choices.clear()
		_has_pending = false
		return _with_handled(_action_result("Back to free action."))

	if choice_id.begins_with("sys.v01.session."):
		var tail: String = choice_id.trim_prefix("sys.v01.session.")
		var parts: PackedStringArray = tail.split(".")
		if parts.size() < 2:
			return {"handled": true, "text":"Invalid event command."}
		var sid: String = String(parts[0])
		var action: String = String(parts[1])
		if action == "continue":
			return _with_handled(_action_result(_v01_offer_session_modal(sid, false, false)))
		if action == "more":
			return _with_handled(_action_result(_v01_offer_session_modal(sid, false, true)))
		if action == "back_main":
			return _with_handled(_action_result(_v01_offer_session_modal(sid, false, false)))
		if action == "later":
			return _with_handled(_v01_put_session_to_backlog(sid))
		if action == "abandon":
			return _with_handled(_v01_abandon_session(sid))
		if action == "intent" and parts.size() >= 3:
			var intent: String = String(parts[2])
			return _with_handled(_v01_apply_session_intent(sid, intent))

	if choice_id.begins_with("sys.travel."):
		v01_guidance_due = true
		return {"handled": false}

	return {"handled": false}

func run_v01_acceptance_smoke() -> Dictionary:
	var report: Dictionary = {}
	var old_hour: int = time_hours
	var old_pending: bool = has_pending_choice()
	var old_pending_choices: Array[Dictionary] = get_current_choices()

	# Case A: SegmentFree -> later -> expire -> rumor/unknown
	var a_text: String = _v01_spawn_free_session("smoke.caseA")
	var sid_a: String = ""
	for sid_any in v01_sessions.keys():
		var sid: String = String(sid_any)
		var s_any: Variant = v01_sessions.get(sid, {})
		if s_any is Dictionary and String((s_any as Dictionary).get("type", "")) == "segment_free":
			sid_a = sid
			break
	if sid_a != "":
		_v01_put_session_to_backlog(sid_a)
		time_hours += 12
		_v01_process_time_drift()
	var rumor_a: String = _v01_pop_rumor_line()
	report["case_a"] = {
		"spawned": a_text != "",
		"expired": sid_a == "" or not v01_sessions.has(sid_a),
		"rumor_or_unknown": rumor_a != "" or not v01_unknown_notice_queue.is_empty()
	}

	# Case B: SegmentLocked 2~4 steps
	var b_text: String = _v01_spawn_locked_session("smoke.caseB")
	var sid_b: String = v01_active_locked_id
	var b_steps: int = 0
	while sid_b != "" and v01_sessions.has(sid_b):
		b_steps += 1
		_v01_apply_session_intent(sid_b, "DODGE")
		sid_b = v01_active_locked_id
		if b_steps > 6:
			break
	report["case_b"] = {
		"spawned": b_text != "",
		"steps": b_steps,
		"returned_to_free": v01_active_locked_id == ""
	}

	# Case C: Guidance block output structure
	v01_guidance_due = true
	var c_text: String = _v01_build_guidance_block()
	report["case_c"] = {
		"has_percepts": c_text.find("Percepts") >= 0,
		"has_reminders": c_text.find("Reminders") >= 0,
		"has_actions": c_text.find("Next Actions") >= 0
	}

	# Case D: duplicate free sessions merged
	var d1: String = _v01_spawn_free_session("smoke.caseD")
	var d2: String = _v01_spawn_free_session("smoke.caseD")
	report["case_d"] = {
		"first_spawned": d1 != "",
		"second_merged": d2.find("merged into backlog") >= 0
	}

	report["metrics"] = get_v01_metrics()
	time_hours = old_hour
	_pending_choices.clear()
	for c in old_pending_choices:
		_pending_choices.append(c.duplicate(true))
	_has_pending = old_pending and not _pending_choices.is_empty()
	return report

func _v02_reset_runtime() -> void:
	v02_turn_count = 0
	v02_guidance_due = true
	v02_last_guidance_hour = -9999
	v02_micro_nonce = 0
	v02_lead_nonce = 0
	v02_active_micro_id = ""
	v02_micro_sessions.clear()
	v02_leads.clear()
	v02_last_micro_fingerprint_h.clear()
	v02_goal_reminders = [
		{"text":"\u9152\u4fdd\u63d0\u5230\u897f\u4fa7\u9057\u8ff9\u6709\u5f02\u5e38\u52a8\u9759\u3002", "hint_target":"\u897f\u4fa7\u8db3\u8ff9"},
		{"text":"\u540c\u4f34\u75c5\u60c5\u52a0\u91cd\uff0c\u4f60\u8fd8\u7f3a\u4e00\u4efd\u8349\u836f\u3002", "hint_target":"\u6cb3\u8fb9\u8349\u836f"}
	]
	v02_recent_visible_outcomes.clear()
	v02_metrics = {
		"micro_total": 0,
		"micro_with_backlash": 0,
		"micro_with_structural": 0,
		"micro_with_info_or_opportunity": 0,
		"lead_generated": 0,
		"lead_consumed": 0,
		"track_repeat_prevented": 0
	}

func _v02_after_bootstrap(reset_time: bool) -> void:
	if reset_time:
		_v02_reset_runtime()
	v02_guidance_due = true
	_v02_ensure_leads_from_percepts(3)

func _v02_region_name_human() -> String:
	return String(current_region.get("name", current_region_id))

func _v02_current_thread_brief() -> String:
	return _v01_region_thread_label()

func _v02_build_percepts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var danger: int = int(global_arc.get("danger", 20))
	var scarcity: int = int(global_arc.get("scarcity", 20))
	if _v02_is_town_context():
		out.append({"type":"smoke", "text":"\u4e1c\u5317\u65b9\u5411\u6709\u7ec6\u70df\u5347\u8d77\uff0c\u50cf\u662f\u6709\u4eba\u5c45\u4f4f\u3002", "target":"\u70df\u67f1", "direction":"\u4e1c\u5317"})
		out.append({"type":"rumor", "text":"\u9547\u53e3\u544a\u793a\u63d0\u5230\u897f\u4fa7\u9057\u8ff9\u9644\u8fd1\u6709\u4eba\u5931\u8e2a\u3002", "target":"\u897f\u4fa7\u9057\u8ff9\u4f20\u95fb", "direction":"\u897f\u4fa7"})
	else:
		out.append({"type":"tracks", "text":"\u65b0\u9c9c\u8db3\u8ff9\u5411\u897f\u504f\u53bb\u3002", "target":"\u8db3\u8ff9", "direction":"\u897f\u4fa7"})
		out.append({"type":"water", "text":"\u5357\u8fb9\u6301\u7eed\u4f20\u6765\u6c34\u58f0\u3002", "target":"\u6c34\u58f0", "direction":"\u5357\u4fa7"})
	if danger >= 45:
		out.append({"type":"patrol", "text":"\u5de1\u903b\u8def\u7ebf\u6bd4\u5e73\u65f6\u66f4\u5bc6\u96c6\u3002", "target":"\u5de1\u903b\u8def\u7ebf", "direction":"\u5317\u4fa7"})
	if scarcity >= 40:
		out.append({"type":"herbs", "text":"\u8865\u7ed9\u7d27\u5f20\uff0c\u6cb3\u8fb9\u53ef\u80fd\u6709\u53ef\u91c7\u8349\u836f\u3002", "target":"\u8349\u836f\u70b9", "direction":"\u6cb3\u5cb8"})
	return out

func _v02_lead_title(lead: Dictionary) -> String:
	var t: String = String(lead.get("type", "lead"))
	var dir: String = String(lead.get("direction", "nearby"))
	match t:
		"tracks":
			return "\u6cbf\u8db3\u8ff9\u5f80%s\u8ffd\u67e5" % dir
		"smoke":
			return "\u524d\u5f80%s\u70df\u67f1\u5904\u5bfb\u627e\u4eba\u70df" % dir
		"water":
			return "\u5faa\u6c34\u58f0\u53bb%s\u6cb3\u8fb9\u8865\u6c34\u5e76\u627e\u8349\u836f" % dir
		"rumor":
			return "\u56de\u9547\u91cc\u6253\u542c\u201c%s\u201d" % String(lead.get("target", "\u4f20\u95fb"))
		"patrol":
			return "\u7ed5\u5f00%s\u5de1\u903b\u8def\u7ebf\u4f4e\u8c03\u7a7f\u884c" % dir
		"herbs":
			return "\u53bb%s\u641c\u5bfb\u53ef\u7528\u8349\u836f" % dir
		_:
			return "\u8c03\u67e5%s" % String(lead.get("target", "\u65b0\u7ebf\u7d22"))

func _v02_add_lead(lead_type: String, target: String, direction: String, source: String, thread_hint: String="") -> String:
	v02_lead_nonce += 1
	var lead_id: String = "lead_%d" % v02_lead_nonce
	var lead: Dictionary = {
		"id": lead_id,
		"type": lead_type,
		"target": target,
		"direction": direction,
		"source": source,
		"thread_hint": thread_hint,
		"stage": 1,
		"quality": rng.randi_range(45, 82),
		"created_h": time_hours,
		"expires_h": time_hours + rng.randi_range(10, 26)
	}
	v02_leads.append(lead)
	v02_metrics["lead_generated"] = int(v02_metrics.get("lead_generated", 0)) + 1
	return lead_id

func _v02_find_lead_index(lead_id: String) -> int:
	for i in range(v02_leads.size()):
		var l_any: Variant = v02_leads[i]
		if not (l_any is Dictionary):
			continue
		if String((l_any as Dictionary).get("id", "")) == lead_id:
			return i
	return -1

func _v02_ensure_leads_from_percepts(min_count: int) -> void:
	_v02_prune_leads()
	if v02_leads.size() >= min_count:
		return
	var percepts: Array[Dictionary] = _v02_build_percepts()
	for p in percepts:
		if v02_leads.size() >= min_count:
			break
		_v02_add_lead(
			String(p.get("type", "tracks")),
			String(p.get("target", "unknown signal")),
			String(p.get("direction", "nearby")),
			"guidance",
			_v02_current_thread_brief()
		)

func _v02_ensure_percept_lead_links(percepts: Array[Dictionary]) -> void:
	for p in percepts:
		var p_type: String = String(p.get("type", "tracks"))
		var p_dir: String = String(p.get("direction", "nearby"))
		var p_target: String = String(p.get("target", "unknown signal"))
		var found: bool = false
		for l_any in v02_leads:
			if not (l_any is Dictionary):
				continue
			var l: Dictionary = l_any as Dictionary
			if String(l.get("type", "")) == p_type and String(l.get("direction", "")) == p_dir:
				found = true
				break
		if not found:
			_v02_add_lead(p_type, p_target, p_dir, "guidance", _v02_current_thread_brief())

func _v02_prune_leads() -> void:
	var next: Array[Dictionary] = []
	for l_any in v02_leads:
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		if time_hours < int(l.get("expires_h", time_hours + 1)):
			next.append(l)
	v02_leads = next

func _v02_add_visible_outcome(line: String) -> void:
	if line == "":
		return
	v02_recent_visible_outcomes.append(line)
	if v02_recent_visible_outcomes.size() > 6:
		v02_recent_visible_outcomes.pop_front()

func _v02_micro_fingerprint(action_key: String, stage: int, target_label: String) -> String:
	return "%s|%s|%d|%s" % [action_key, current_region_id, stage, target_label]

func _v02_is_town_context() -> bool:
	return _v01_is_town_context()

func _v02_action_entry(id: String, title: String, why: String, cost: String, direction: String, objectified: bool=true, disabled: bool=false) -> Dictionary:
	return {
		"id": id,
		"title": title,
		"why": why,
		"cost": cost,
		"direction": direction,
		"objectified": objectified,
		"disabled": disabled
	}

func _v02_unique_actions(items: Array[Dictionary], limit: int=99) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for it_any in items:
		if out.size() >= limit:
			break
		if not (it_any is Dictionary):
			continue
		var it: Dictionary = it_any as Dictionary
		if bool(it.get("disabled", false)):
			continue
		var id: String = String(it.get("id", ""))
		if id == "":
			continue
		var title: String = String(it.get("title", ""))
		var key: String = title.strip_edges().to_lower()
		if key == "":
			key = id
		if seen.has(key):
			continue
		seen[key] = true
		out.append(it)
	return out

func _v02_generate_object_actions_from_leads(limit: int=4) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_v02_ensure_leads_from_percepts(max(2, limit))
	for l_any in v02_leads:
		if out.size() >= limit:
			break
		if not (l_any is Dictionary):
			continue
		var l: Dictionary = l_any as Dictionary
		var lid: String = String(l.get("id", ""))
		var lt: String = String(l.get("type", "tracks"))
		var title: String = _v02_lead_title(l)
		var aid: String = "sys.v02.lead.follow." + lid
		var dir_tag: String = "\u8865\u5145\u4fe1\u606f\u5e76\u4e89\u53d6\u673a\u4f1a"
		if lt == "water" or lt == "herbs":
			aid = "sys.v02.lead.gather." + lid
			dir_tag = "\u8865\u7ed9\u4e0e\u673a\u4f1a"
		elif lt == "rumor":
			aid = "sys.v02.lead.ask." + lid
			dir_tag = "\u4fe1\u606f\u4e0e\u5173\u7cfb"
		elif lt == "smoke":
			aid = "sys.v02.lead.investigate." + lid
			dir_tag = "\u63a8\u8fdb\u5730\u533a\u7ebf\u7a0b\u5e76\u4e89\u53d6\u673a\u4f1a"
		out.append(_v02_action_entry(
			aid,
			title,
			"\u6765\u81ea\u7ebf\u7d22\uff1a" + String(l.get("source", "\u73af\u5883\u611f\u77e5")),
			"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669",
			dir_tag,
			true,
			false
		))
	return out

func _v02_generate_context_actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _v02_is_town_context():
		out.append(_v02_action_entry(
			"sys.v02.act.observe",
			"\u5728\u9547\u53e3\u6253\u542c\u65b0\u6d88\u606f",
			"\u5f53\u524d\u5728\u57ce\u9547\u53ef\u83b7\u53d6\u60c5\u62a5",
			"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669",
			"\u83b7\u5f97\u7ebf\u7d22\u5e76\u5f71\u54cd\u5173\u7cfb",
			false,
			false
		))
		out.append(_v02_action_entry(
			"sys.v02.act.push",
			"\u53bb\u57ce\u5916\u5c94\u8def\u53e3\u8e29\u70b9",
			"\u4f60\u9700\u8981\u4e0b\u4e00\u6b65\u8def\u5f84\u4fe1\u606f",
			"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669",
			"\u63a8\u8fdb\u8def\u7ebf\u5224\u65ad",
			false,
			false
		))
		out.append(_v02_action_entry(
			"sys.v02.act.forage",
			"\u5728\u96c6\u5e02\u4e0e\u540e\u5df7\u8865\u7ed9",
			"\u57ce\u9547\u8865\u7ed9\u6548\u7387\u66f4\u9ad8",
			"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669",
			"\u8865\u7ed9\u4e0e\u673a\u4f1a",
			false,
			false
		))
	else:
		out.append(_v02_action_entry(
			"sys.v02.act.push",
			"\u6cbf\u6797\u95f4\u5c0f\u9053\u5411\u524d\u63a8\u8fdb",
			"\u524d\u65b9\u5c1a\u672a\u52d8\u660e",
			"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669",
			"\u63a8\u8fdb\u63a2\u7d22\u8fdb\u5ea6",
			false,
			false
		))
		out.append(_v02_action_entry(
			"sys.v02.act.observe",
			"\u89c2\u5bdf\u5730\u5f62\u4e0e\u5f02\u52a8\u4fe1\u53f7",
			"\u7f3a\u4e4f\u7a33\u5b9a\u7ebf\u7d22\u65f6\u4f18\u5148\u89c2\u5bdf",
			"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669",
			"\u8865\u5145\u7ebf\u7d22\u6c60",
			false,
			false
		))
		out.append(_v02_action_entry(
			"sys.v02.act.forage",
			"\u5728\u5468\u8fb9\u641c\u5bfb\u6c34\u6e90\u4e0e\u8349\u836f",
			"\u5f53\u524d\u73af\u5883\u53ef\u91c7\u96c6",
			"1\u5c0f\u65f6\uff5c\u4e2d\u98ce\u9669",
			"\u8865\u7ed9\u4e0e\u673a\u4f1a",
			false,
			false
		))
	out.append(_v02_action_entry(
		"sys.v02.act.rest",
		"\u5728\u80cc\u98ce\u5904\u77ed\u6682\u4f11\u6574",
		"\u7a33\u4f4f\u72b6\u6001\u907f\u514d\u5931\u8bef",
		"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669",
		"\u6062\u590d\u5e76\u964d\u4f4e\u66b4\u9732",
		false,
		false
	))
	return out
func _v02_pick_recommended_actions() -> Array[Dictionary]:
	var cands: Array[Dictionary] = []
	var lead_actions: Array[Dictionary] = _v02_generate_object_actions_from_leads(8)
	for a in lead_actions:
		cands.append(a)

	var goal_added: int = 0
	for r_any in v02_goal_reminders:
		if goal_added >= 2:
			break
		if not (r_any is Dictionary):
			continue
		var r: Dictionary = r_any as Dictionary
		var hint: String = String(r.get("hint_target", "\u76ee\u6807"))
		var text: String = String(r.get("text", ""))
		var linked_action: Dictionary = {}
		for a_any in lead_actions:
			if not (a_any is Dictionary):
				continue
			var ad: Dictionary = a_any as Dictionary
			var t: String = String(ad.get("title", ""))
			if t.find(hint) >= 0:
				linked_action = ad
				break
		if not linked_action.is_empty():
			cands.append(linked_action)
		else:
			cands.append(_v02_action_entry(
				"sys.v02.act.observe",
				"\u56f4\u7ed5\u201c%s\u201d\u8865\u5145\u60c5\u62a5" % hint,
				"\u6765\u81ea\u5f53\u524d\u6302\u5ff5\uff1a" + text,
				"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669",
				"\u63a8\u8fdb\u76ee\u6807\u7ebf\u7d22",
				true,
				false
			))
		goal_added += 1

	if _v02_is_town_context():
		cands.append(_v02_action_entry(
			"sys.v02.act.rest",
			"\u5148\u56de\u5ba2\u6808\u77ed\u4f11\u5e76\u6574\u7406\u7ebf\u7d22",
			"\u9700\u8981\u4e00\u4e2a\u7a33\u59a5\u56de\u9000\u65b9\u6848",
			"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669",
			"\u7a33\u5b9a\u72b6\u6001\u5e76\u51c6\u5907\u4e0b\u4e00\u6b65",
			true,
			false
		))
	else:
		cands.append(_v02_action_entry(
			"sys.v02.act.rest",
			"\u5728\u80cc\u98ce\u5904\u624e\u8425\u4f11\u6574",
			"\u9700\u8981\u4e00\u4e2a\u7a33\u59a5\u56de\u9000\u65b9\u6848",
			"1\u5c0f\u65f6\uff5c\u4f4e\u98ce\u9669",
			"\u6062\u590d\u5e76\u964d\u4f4e\u66b4\u9732",
			true,
			false
		))

	for ctx in _v02_generate_context_actions():
		cands.append(ctx)
	return _v02_unique_actions(cands, 12)

func _v02_parse_pending_choice(c: Dictionary) -> Dictionary:
	var cid: String = String(c.get("id", ""))
	var raw: String = String(c.get("text", "\u4e8b\u4ef6\u9009\u9879"))
	var lines: PackedStringArray = raw.split("\n", false)
	var title: String = "\u4e8b\u4ef6\u9009\u9879"
	if lines.size() > 0:
		title = String(lines[0]).strip_edges()
	var cost: String = "\u7acb\u5373\u51b3\u7b56"
	var direction: String = "\u63a8\u8fdb\u5f53\u524d\u4e8b\u4ef6\u9636\u6bb5"
	for l_any in lines:
		var l: String = String(l_any)
		if l.find("[\u77ed\u671f]") >= 0:
			cost = l.replace("[\u77ed\u671f]", "").strip_edges()
		elif l.find("[\u4e2d\u671f]") >= 0:
			direction = l.replace("[\u4e2d\u671f]", "").strip_edges()
	return _v02_action_entry(
		cid,
		title,
		"\u5f53\u524d\u4e8b\u4ef6\u9636\u6bb5\u53ef\u6267\u884c\u65b9\u6848",
		cost,
		direction,
		true,
		false
	)
func _v02_pending_event_as_actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not has_pending_choice():
		return out
	for c in get_current_choices():
		out.append(_v02_parse_pending_choice(c))
	return out

func _v02_extract_pending_session_id() -> String:
	for c_any in _pending_choices:
		if not (c_any is Dictionary):
			continue
		var c: Dictionary = c_any as Dictionary
		var sa: String = String(c.get("system_action", ""))
		if not sa.begins_with("sys.v01.session."):
			continue
		var tail: String = sa.trim_prefix("sys.v01.session.")
		var parts: PackedStringArray = tail.split(".")
		if parts.size() >= 1:
			return String(parts[0])
	return ""

func _v02_build_event_header_text() -> String:
	var sid: String = ""
	if v01_active_locked_id != "":
		sid = v01_active_locked_id
	if sid == "":
		sid = _v02_extract_pending_session_id()
	if sid != "" and v01_sessions.has(sid):
		var s_any: Variant = v01_sessions.get(sid, {})
		if s_any is Dictionary:
			var s: Dictionary = s_any as Dictionary
			var remain: int = max(0, int(s.get("deadline", time_hours + 1)) - time_hours)
			var header: String = _v01_format_session_header(s, remain, false)
			header = header.replace(current_region_id, _v02_region_name_human())
			return header
	if v02_active_micro_id != "" and v02_micro_sessions.has(v02_active_micro_id):
		var m_any: Variant = v02_micro_sessions.get(v02_active_micro_id, {})
		if m_any is Dictionary:
			var m: Dictionary = m_any as Dictionary
			return "[b]\u5f53\u524d\u884c\u52a8\u6b65\u9aa4[/b]\n\u76ee\u6807\uff1a%s\n\u8fdb\u5ea6\uff1a\u7b2c%d/%d\u6b65" % [
				String(m.get("title", "\u672a\u547d\u540d\u76ee\u6807")),
				int(m.get("stage", 1)),
				int(m.get("max_stage", 2))
			]
	return "[b]\u5f53\u524d\u4e8b\u4ef6\u9636\u6bb5[/b]\n\u8bf7\u5148\u5b8c\u6210\u672c\u9636\u6bb5\u540e\u518d\u8fdb\u884c\u81ea\u7531\u884c\u52a8\u3002"
func _v02_build_guidance_payload() -> Dictionary:
	var percepts_raw: Array[Dictionary] = _v02_build_percepts()
	_v02_ensure_percept_lead_links(percepts_raw)
	var percepts: Array[String] = []
	for p in percepts_raw.slice(0, 3):
		if p is Dictionary:
			percepts.append(String((p as Dictionary).get("text", "鐜淇″彿")))
	var reminders: Array[String] = []
	for r_any in v02_goal_reminders.slice(0, 2):
		if r_any is Dictionary:
			reminders.append(String((r_any as Dictionary).get("text", "褰撳墠鐩爣")))
	return {
		"percepts": percepts,
		"reminders": reminders
	}

func _v02_split_primary_more(actions: Array[Dictionary], fill_with_context: bool=true) -> Dictionary:
	var uniq: Array[Dictionary] = _v02_unique_actions(actions, 12)
	var primary: Array[Dictionary] = []
	var more: Array[Dictionary] = []
	for i in range(uniq.size()):
		if i < 6:
			primary.append(uniq[i])
		elif i < 10:
			more.append(uniq[i])
	if fill_with_context and primary.size() < 3:
		var fill_pool: Array[Dictionary] = _v02_unique_actions(_v02_generate_context_actions(), 6)
		for f in fill_pool:
			if primary.size() >= 3:
				break
			var exists: bool = false
			for p in primary:
				if String(p.get("id", "")) == String(f.get("id", "")):
					exists = true
					break
			if not exists:
				primary.append(f)
	return {
		"primary": primary,
		"more": more
	}

func _v02_build_action_board() -> Dictionary:
	var quick: Array[Dictionary] = [
		_v02_action_entry("sys.v01.backlog.open", "寰呭姙(%d)" % v01_backlog_ids.size(), "", "", "", false, false),
		_v02_action_entry("sys.v01.rumor.feed", "浼犻椈", "", "", "", false, false)
	]

	if has_pending_choice():
		var pending_actions: Array[Dictionary] = _v02_pending_event_as_actions()
		var split_pending: Dictionary = _v02_split_primary_more(pending_actions, false)
		return {
			"mode": "event",
			"event_header": _v02_build_event_header_text(),
			"guidance": {},
			"actions": split_pending.get("primary", []),
			"more_actions": split_pending.get("more", []),
			"quick": quick
		}

	var guidance: Dictionary = _v02_build_guidance_payload()
	var free_actions: Array[Dictionary] = _v02_pick_recommended_actions()
	var split_free: Dictionary = _v02_split_primary_more(free_actions)
	var board: Dictionary = {
		"mode": "free",
		"event_header": "",
		"guidance": guidance,
		"actions": split_free.get("primary", []),
		"more_actions": split_free.get("more", []),
		"quick": quick
	}
	return board

func get_action_board() -> Dictionary:
	if v02_enabled:
		return _v02_build_action_board()
	return {
		"mode": "free",
		"event_header": "",
		"guidance": {},
		"actions": [],
		"more_actions": [],
		"quick": []
	}

func get_goal_panel_v02() -> Dictionary:
	_v02_prune_leads()
	var leads_text: Array[String] = []
	for l_any in v02_leads:
		if leads_text.size() >= 2:
			break
		if not (l_any is Dictionary):
			continue
		leads_text.append(_v02_lead_title(l_any as Dictionary))
	var reminder_text: Array[String] = []
	for r_any in v02_goal_reminders:
		if reminder_text.size() >= 2:
			break
		if r_any is Dictionary:
			reminder_text.append(String((r_any as Dictionary).get("text", "")))
	return {
		"location": _v02_region_name_human(),
		"leads": leads_text,
		"reminders": reminder_text,
		"thread": _v02_current_thread_brief(),
		"recent_outcome": String(v02_recent_visible_outcomes[v02_recent_visible_outcomes.size() - 1]) if not v02_recent_visible_outcomes.is_empty() else ""
	}

func _get_action_offers_v02() -> Array[Dictionary]:
	var board: Dictionary = _v02_build_action_board()
	var out: Array[Dictionary] = []
	for sec in ["actions", "more_actions", "quick"]:
		var arr_any: Variant = board.get(sec, [])
		if not (arr_any is Array):
			continue
		for d_any in (arr_any as Array):
			if not (d_any is Dictionary):
				continue
			var d: Dictionary = d_any as Dictionary
			out.append({
				"id": String(d.get("id", "")),
				"text": "%s\n缂樼敱锛?s锝滀唬浠凤細%s锝滆蛋鍚戯細%s" % [
					String(d.get("title", "")),
					String(d.get("why", "")),
					String(d.get("cost", "")),
					String(d.get("direction", ""))
				],
				"disabled": bool(d.get("disabled", false))
			})
	return out

func _v02_start_micro(action_key: String, target_label: String, lead_id: String="", source_reason: String="") -> Dictionary:
	if has_pending_choice():
		return _action_result("褰撳墠鏈夊緟鍐抽樁娈碉紝璇峰厛瀹屾垚瀹冦€?)
	if action_key == "track":
		if lead_id == "":
			return _action_result("杩借釜鍓嶈鍏堥€夋嫨涓€涓叿浣撶嚎绱€?)
		if _v02_find_lead_index(lead_id) < 0:
			return _action_result("璇ョ嚎绱㈠凡澶辨晥锛岃鍏堣瀵熻幏鍙栨柊绾跨储銆?)

	v02_micro_nonce += 1
	var mid: String = "micro_%d" % v02_micro_nonce
	var fp: String = _v02_micro_fingerprint(action_key, 1, target_label)
	var repeated_recently: bool = false
	if v02_last_micro_fingerprint_h.has(fp):
		var prev_h: int = int(v02_last_micro_fingerprint_h.get(fp, -9999))
		if time_hours - prev_h < 24:
			repeated_recently = true
			v02_metrics["track_repeat_prevented"] = int(v02_metrics.get("track_repeat_prevented", 0)) + 1
	v02_last_micro_fingerprint_h[fp] = time_hours

	var session: Dictionary = {
		"id": mid,
		"action_key": action_key,
		"title": target_label,
		"lead_id": lead_id,
		"stage": 1,
		"max_stage": 2,
		"state": {
			"progress": 0,
			"exposure": 0,
			"alert": 0
		},
		"source_reason": source_reason,
		"repeat_variant": repeated_recently
	}
	v02_micro_sessions[mid] = session
	v02_active_micro_id = mid
	return _v02_offer_micro_stage(mid)

func _v02_offer_micro_stage(mid: String) -> Dictionary:
	var s_any: Variant = v02_micro_sessions.get(mid, {})
	if not (s_any is Dictionary):
		return _action_result("璇ヨ鍔ㄥ井浼氳瘽宸茬粨鏉熴€?)
	var s: Dictionary = s_any as Dictionary
	var stage: int = int(s.get("stage", 1))
	var action_key: String = String(s.get("action_key", "observe"))
	var title: String = String(s.get("title", "琛屽姩"))
	var reason: String = String(s.get("source_reason", "鐜淇″彿"))

	_pending_choices.clear()
	_pending_choices.append({
		"id": "v02_%s_safe" % mid,
		"text": "%s\n[鐭湡] 绋冲Ε鎺ㄨ繘锛岄闄╄緝浣嶾n[涓湡] 绋冲畾鑾峰彇淇℃伅骞舵帶鍒舵毚闇瞈n[缂樼敱] %s" % [_v02_stage_title(action_key, title, stage, "绋冲Ε"), reason],
		"system_action": "sys.v02.micro.%s.safe" % mid
	})
	_pending_choices.append({
		"id": "v02_%s_probe" % mid,
		"text": "%s\n[鐭湡] 涓瓑椋庨櫓璇曟帰\n[涓湡] 鑾峰彇淇℃伅骞朵簤鍙栨満浼歕n[缂樼敱] %s" % [_v02_stage_title(action_key, title, stage, "璇曟帰"), reason],
		"system_action": "sys.v02.micro.%s.probe" % mid
	})
	_pending_choices.append({
		"id": "v02_%s_risky" % mid,
		"text": "%s\n[鐭湡] 楂橀闄╁己鎺╘n[涓湡] 杩涘害鏇村揩浣嗘洿鏄撳弽鍣琝n[缂樼敱] %s" % [_v02_stage_title(action_key, title, stage, "鍐掕繘"), reason],
		"system_action": "sys.v02.micro.%s.risky" % mid
	})
	_has_pending = true
	return _action_result("琛屽姩姝ラ %d/%d锛?s\n缂樼敱锛?s" % [stage, int(s.get("max_stage", 2)), title, reason])

func _v02_stage_title(action_key: String, target: String, stage: int, style: String) -> String:
	var verb: String = "澶勭悊"
	match action_key:
		"observe":
			verb = "瑙傚療"
		"push":
			verb = "鎺ㄨ繘鑷?
		"forage":
			verb = "鎼滃"
		"track":
			verb = "杩借釜"
		"rest":
			verb = "浼戞暣浜?
		_:
			verb = "澶勭悊"
	return "%s %s锛堢%d姝ワ綔%s锛? % [verb, target, stage, style]

func _v02_apply_micro_choice(mid: String, style: String) -> Dictionary:
	var s_any: Variant = v02_micro_sessions.get(mid, {})
	if not (s_any is Dictionary):
		return _action_result("璇ヨ鍔ㄦ楠ゅ凡缁撴潫銆?)
	var s: Dictionary = s_any as Dictionary

	time_hours += 1
	_survival_tick(1)
	_v01_process_time_drift()
	_v02_prune_leads()

	var stage: int = int(s.get("stage", 1))
	var max_stage: int = int(s.get("max_stage", 2))
	var state: Dictionary = s.get("state", {}) as Dictionary
	state["progress"] = int(state.get("progress", 0)) + (2 if style == "risky" else 1)
	state["exposure"] = int(state.get("exposure", 0)) + (2 if style == "risky" else (1 if style == "probe" else 0))
	state["alert"] = int(state.get("alert", 0)) + (1 if style == "risky" else 0)
	s["state"] = state

	if stage < max_stage:
		s["stage"] = stage + 1
		v02_micro_sessions[mid] = s
		return _v02_offer_micro_stage(mid)

	var outcome: Dictionary = _v02_micro_roll_outcome(s, style)
	var txt: String = _v02_apply_micro_outcome(s, outcome)

	v02_micro_sessions.erase(mid)
	if v02_active_micro_id == mid:
		v02_active_micro_id = ""
	_pending_choices.clear()
	_has_pending = false
	return _action_result(txt)

func _v02_micro_roll_outcome(session: Dictionary, style: String) -> Dictionary:
	var action_key: String = String(session.get("action_key", "observe"))
	var lead_id: String = String(session.get("lead_id", ""))
	var state_any: Variant = session.get("state", {})
	var state: Dictionary = state_any as Dictionary if state_any is Dictionary else {}
	var repeat_variant: bool = bool(session.get("repeat_variant", false))
	var chance: float = 0.55
	if style == "safe":
		chance = 0.62
	elif style == "probe":
		chance = 0.56
	else:
		chance = 0.48
	chance += float(int(state.get("progress", 0))) * 0.02
	chance -= float(int(state.get("exposure", 0))) * 0.015
	if repeat_variant:
		chance -= 0.04
	if action_key == "track" and lead_id != "":
		var li: int = _v02_find_lead_index(lead_id)
		if li >= 0:
			var lead: Dictionary = v02_leads[li]
			chance += float(int(lead.get("quality", 50)) - 50) / 180.0

	var success: bool = rng.randf() < clamp(chance, 0.12, 0.9)
	var buckets: Array[String] = []
	var text: String = ""
	var success_texts: Array[String] = [
		"浣犳嬁鍒颁簡鍙敤杩涘睍锛屽苟鎵撳紑浜嗗悗缁鍔ㄧ獥鍙ｃ€?,
		"杩欐澶勭悊鏈夋晥锛屼笅涓€姝ヨ鍔ㄦ洿绋炽€?,
		"浣犳妸杩欎竴姝ヨ浆鎴愪簡瀹炶川鎺ㄨ繘銆?
	]
	var fail_texts: Array[String] = [
		"杩欐澶勭悊澶辨墜锛屼笘鐣岀粰鍑轰簡鍙嶅櫖淇″彿銆?,
		"浣犻敊杩囦簡绐楀彛锛屽眬鍔垮帇鍔涢殢涔嬩笂鍗囥€?,
		"琛屽姩鍙楅樆锛屼絾浣犱篃鐪嬪埌浜嗘柊鐨勯闄╃嚎绱€?
	]
	if action_key == "track":
		success_texts = [
			"浣犳纭鍑轰簡杞ㄨ抗锛岀嚎绱㈡帹杩涗簡涓€姝ャ€?,
			"鐥曡抗浠嶇劧杩炶疮锛屼綘鎶婄嚎绱㈡帹鍒颁簡涓嬩竴闃舵銆?,
			"浣犻攣瀹氫簡鐩爣璺緞锛屾帉鎻′簡涓诲姩銆?
		]
		fail_texts = [
			"绾跨储鏂锛屼綘鍦ㄥ帇鍔涗笅琚揩鍋忕璺嚎銆?,
			"浣犱涪澶变簡杞ㄨ抗锛屽苟鐣欎笅浜嗛珮椋庨櫓鐥曡抗銆?,
			"鐩爣鑴辩瑙嗛噹锛屽懆杈瑰▉鑳佷笂鍗囥€?
		]
		if repeat_variant:
			fail_texts.append("浣犱互涓鸿矾绾跨啛鎮夛紝浣嗚繖娆″矓绾垮弽鑰屾儵缃氫簡鍐掕繘銆?)
	if success:
		buckets.append("A")
		buckets.append("C")
		if rng.randf() < 0.24:
			buckets.append("E")
		text = success_texts[rng.randi_range(0, success_texts.size() - 1)]
	else:
		buckets.append("D")
		if action_key == "observe":
			buckets.append("A")
		else:
			buckets.append("B")
		if rng.randf() < 0.2:
			buckets.append("E")
		text = fail_texts[rng.randi_range(0, fail_texts.size() - 1)]
	return {
		"success": success,
		"buckets": buckets,
		"text": text
	}

func _v02_apply_bucket_effects(buckets: Array, action_key: String, lead_id: String, success: bool) -> String:
	var lines: Array[String] = []
	var has_backlash: bool = false
	var has_structural: bool = false
	var has_info_or_opp: bool = false
	for b_any in buckets:
		var b: String = String(b_any)
		match b:
			"A":
				has_info_or_opp = true
				_add_counter("intel_clues", 1)
				lines.append("浣犺幏寰椾簡鏂颁俊鎭細鍙墽琛岃鍔ㄥ凡鏇存柊銆?)
			"B":
				relations["locals"] = int(relations.get("locals", 0)) + 1
				lines.append("鍏崇郴鍙樺寲锛氬綋鍦颁汉璁颁綇浜嗕綘鐨勫鐞嗘柟寮忋€?)
			"C":
				has_info_or_opp = true
				_add_counter("opportunity_tokens", 1)
				lines.append("鏈轰細瑙ｉ攣锛氬嚭鐜颁簡鏂扮殑璺嚎鎴栫壒娈婅鍔ㄣ€?)
			"D":
				has_backlash = true
				global_arc["danger"] = _clamp_int(int(global_arc.get("danger", 20)) + 4, 0, 100)
				lines.append("鍑虹幇鍙嶅櫖锛氬嵄闄╁帇鍔涗笂鍗囥€?)
			"E":
				has_structural = true
				_world_apply_region_delta(current_region_id, {"conflict": rng.randi_range(-3, 8), "hazard": rng.randi_range(-3, 9)})
				lines.append("缁撴瀯鍙樺寲锛氳矾寰勬垨娌诲畨缁撴瀯鍙戠敓鏀瑰彉銆?)
			_:
				pass

	if action_key == "observe":
		# hard rule: each observe produces at least one lead
		var lead_type: String = "tracks" if rng.randf() < 0.5 else "water"
		var direction: String = "west" if lead_type == "tracks" else "south"
		_v02_add_lead(lead_type, lead_type, direction, "observe", _v02_current_thread_brief())
		lines.append("瑙傚療浜у嚭浜嗕竴鏉″彲杩借釜绾跨储銆?)
	if action_key == "track" and lead_id != "":
		var li: int = _v02_find_lead_index(lead_id)
		if li >= 0:
			var lead: Dictionary = v02_leads[li]
			if success:
				lead["stage"] = min(3, int(lead.get("stage", 1)) + 1)
				lead["quality"] = _clamp_int(int(lead.get("quality", 60)) + 6, 20, 95)
				v02_leads[li] = lead
				v02_metrics["lead_consumed"] = int(v02_metrics.get("lead_consumed", 0)) + 1
				lines.append("璇ョ嚎绱㈠凡鎺ㄨ繘鍒扮%d闃舵銆? % int(lead.get("stage", 1)))
				if int(lead.get("stage", 1)) >= 3 and rng.randf() < 0.5:
					var e_text: String = _v01_spawn_free_session("lead-chain stage3")
					if e_text != "":
						lines.append("绾跨储鏀舵潫瑙﹀彂浜嗘柊鐨勪簨浠朵細璇濄€?)
			else:
				lead["quality"] = _clamp_int(int(lead.get("quality", 60)) - 10, 20, 95)
				if rng.randf() < 0.34:
					v02_leads.remove_at(li)
					lines.append("杞ㄨ抗宕╂暎鎴愬櫔澹帮紝杩欐潯绾跨储宸蹭笉鍙敤銆?)
					_v01_push_rumor("[浼犻椈] 鏈変汉璇磋タ渚ч偅鏉¤釜杩规槸璇銆?, "v02." + lead_id)
				else:
					lead["stage"] = max(1, int(lead.get("stage", 1)) - 1)
					v02_leads[li] = lead
					lines.append("杞ㄨ抗鍒嗚锛岀嚎绱㈣川閲忎笅闄嶏紝涓嬩竴娆¤拷韪洿鍗遍櫓銆?)
					_v01_push_rumor("[浼犻椈] 宸￠€婚槦鍦ㄦ柇瑁傛敮绾块檮杩戝彂鐜板彲鐤戝姩鍚戙€?, "v02." + lead_id)
	if has_backlash:
		v02_metrics["micro_with_backlash"] = int(v02_metrics.get("micro_with_backlash", 0)) + 1
	if has_structural:
		v02_metrics["micro_with_structural"] = int(v02_metrics.get("micro_with_structural", 0)) + 1
	if has_info_or_opp:
		v02_metrics["micro_with_info_or_opportunity"] = int(v02_metrics.get("micro_with_info_or_opportunity", 0)) + 1
	_world_sync_global_arc()
	return "\n".join(lines)

func _v02_apply_micro_outcome(session: Dictionary, outcome: Dictionary) -> String:
	var action_key: String = String(session.get("action_key", "observe"))
	var lead_id: String = String(session.get("lead_id", ""))
	var success: bool = bool(outcome.get("success", false))
	var buckets_any: Variant = outcome.get("buckets", [])
	var buckets: Array = buckets_any as Array if buckets_any is Array else []
	var txt: String = String(outcome.get("text", "缁撴灉宸茬敓鏁堛€?))
	var extra: String = _v02_apply_bucket_effects(buckets, action_key, lead_id, success)
	v02_metrics["micro_total"] = int(v02_metrics.get("micro_total", 0)) + 1
	var visible: String = "%s -> %s" % [String(session.get("title", "琛屽姩")), txt]
	_v02_add_visible_outcome(visible)
	if extra != "":
		return txt + "\n" + extra
	return txt

func _v02_handle_lead_action(choice_id: String) -> Dictionary:
	var parts: PackedStringArray = choice_id.split(".")
	if parts.size() < 5:
		return _action_result("绾跨储琛屽姩鏃犳晥銆?)
	var mode: String = String(parts[3]) # follow/gather/ask/investigate
	var lead_id: String = String(parts[4])
	var li: int = _v02_find_lead_index(lead_id)
	if li < 0:
		return _action_result("璇ョ嚎绱㈠凡澶辨晥銆?)
	var lead: Dictionary = v02_leads[li]
	var title: String = _v02_lead_title(lead)
	match mode:
		"follow":
			return _v02_start_micro("track", title, lead_id, "宸查€夋嫨绾跨储鐩爣")
		"investigate":
			return _v02_start_micro("push", title, lead_id, "宸查€夋嫨绾跨储鐩爣")
		"gather":
			return _v02_start_micro("forage", title, lead_id, "宸查€夋嫨绾跨储鐩爣")
		"ask":
			return _v02_start_micro("observe", title, lead_id, "宸查€夋嫨绾跨储鐩爣")
		_:
			return _v02_start_micro("observe", title, lead_id, "宸查€夋嫨绾跨储鐩爣")

func _v02_guidance_block_text() -> String:
	var percepts: Array[Dictionary] = _v02_build_percepts()
	_v02_ensure_percept_lead_links(percepts)
	_v02_ensure_leads_from_percepts(4)
	var rec: Array[Dictionary] = _v02_pick_recommended_actions()
	var lines: Array[String] = []
	lines.append("[b]寮曞鍧梉/b]")
	lines.append("浣犳敞鎰忓埌锛?)
	for p in percepts.slice(0, 4):
		lines.append("- " + String((p as Dictionary).get("text", "鐜淇″彿")))
	lines.append("浣犳兂璧凤細")
	for r_any in v02_goal_reminders.slice(0, 3):
		if r_any is Dictionary:
			lines.append("- " + String((r_any as Dictionary).get("text", "")))
	lines.append("浣犳墦绠楀仛锛?)
	for a_any in rec.slice(0, 5):
		if a_any is Dictionary:
			lines.append("- " + String((a_any as Dictionary).get("title", "")))
	return "\n".join(lines)

func _produce_snapshot_v02(_opts: Dictionary={}) -> Dictionary:
	var snap: Dictionary = {}
	_v01_process_time_drift()
	_v02_prune_leads()

	if has_pending_choice():
		snap["event_text"] = "褰撳墠鏈夊緟鍐抽樁娈碉紝璇峰厛澶勭悊鎴栨斁鍏ュ緟鍔炪€?
		return _decorate_snapshot(snap)

	v02_turn_count += 1
	time_hours += 1
	_survival_tick(1)
	_v01_process_time_drift()
	_v02_prune_leads()

	var collapse_text: String = _check_collapse_text()
	if collapse_text != "":
		snap["event_text"] = collapse_text
		return _decorate_snapshot(snap)

	var w: Dictionary = _pick_weather_once()
	if not w.is_empty():
		snap["weather"] = w

	if v02_guidance_due or time_hours - v02_last_guidance_hour >= 6:
		v02_guidance_due = false
		v02_last_guidance_hour = time_hours
		snap["event_text"] = _v02_guidance_block_text()
		return _decorate_snapshot(snap)

	if v01_active_locked_id != "":
		var lock_msg: String = _v01_offer_session_modal(v01_active_locked_id, false, false)
		if lock_msg != "":
			snap["event_text"] = "杩炴浜嬩欢杩涜涓€俓n" + lock_msg
			return _decorate_snapshot(snap)

	if rng.randf() < 0.18 and v01_active_locked_id == "" and not has_pending_choice():
		var locked: String = _v01_spawn_locked_session("dynamic pressure")
		if locked != "":
			snap["event_text"] = "绐佸彂楂樺帇浜嬩欢鏀瑰彉浜嗗綋鍓嶈鍔ㄤ紭鍏堢骇銆俓n" + locked
			return _decorate_snapshot(snap)

	if rng.randf() < 0.24 and not has_pending_choice():
		var free_ev: String = _v01_spawn_free_session("living world drift")
		if free_ev != "":
			snap["event_text"] = "涓栫晫鍙樺寲浜х敓浜嗘柊浜嬩欢锛屼細褰卞搷浣犵殑閫夐」銆俓n" + free_ev
			return _decorate_snapshot(snap)

	if rng.randf() < 0.35:
		var rumor: String = _v01_pop_rumor_line()
		if rumor != "":
			snap["event_text"] = rumor
			return _decorate_snapshot(snap)

	var idle: Array[String] = []
	idle.append("浣犲浜庤嚜鐢辫鍔ㄩ樁娈点€?)
	idle.append("褰撳墠浣嶇疆锛?s" % _v02_region_name_human())
	idle.append("娲昏穬绾跨▼锛?s" % _v02_current_thread_brief())
	if not v02_recent_visible_outcomes.is_empty():
		idle.append("鍙鍥炴祦锛? + String(v02_recent_visible_outcomes[v02_recent_visible_outcomes.size() - 1]))
	snap["event_text"] = "\n".join(idle)
	return _decorate_snapshot(snap)

func _apply_system_choice_v02(choice_id: String) -> Dictionary:
	if choice_id.begins_with("sys.v01."):
		var out_v01: Dictionary = _apply_system_choice_v01(choice_id)
		return _with_handled(out_v01)

	if choice_id == "sys.v02.micro.resume":
		if v02_active_micro_id == "":
			return _with_handled(_action_result("褰撳墠娌℃湁杩涜涓殑琛屽姩姝ラ銆?))
		return _with_handled(_v02_offer_micro_stage(v02_active_micro_id))

	if choice_id.begins_with("sys.v02.micro."):
		var tail: String = choice_id.trim_prefix("sys.v02.micro.")
		var ps: PackedStringArray = tail.split(".")
		if ps.size() >= 2:
			var mid: String = String(ps[0])
			var style: String = String(ps[1])
			return _with_handled(_v02_apply_micro_choice(mid, style))
		return _with_handled(_action_result("琛屽姩姝ラ鎸囦护鏃犳晥銆?))

	if choice_id.begins_with("sys.v02.lead."):
		return _with_handled(_v02_handle_lead_action(choice_id))

	if choice_id == "sys.v02.act.observe":
		return _with_handled(_v02_start_micro("observe", "闄勮繎淇″彿", "", "鍦烘櫙琛屽姩"))
	if choice_id == "sys.v02.act.push":
		return _with_handled(_v02_start_micro("push", "涓嬩竴璺緞鑺傜偣", "", "鍦烘櫙琛屽姩"))
	if choice_id == "sys.v02.act.forage":
		return _with_handled(_v02_start_micro("forage", "鍛ㄨ竟璧勬簮鐐?, "", "鍦烘櫙琛屽姩"))
	if choice_id == "sys.v02.act.track":
		return _with_handled(_action_result("璇峰厛鍦ㄦ帹鑽愯鍔ㄤ腑閫夋嫨鍏蜂綋绾跨储锛屽啀寮€濮嬭拷韪€?))
	if choice_id == "sys.v02.act.rest":
		return _with_handled(_v02_start_micro("rest", "涓存椂瀹夊叏鐐?, "", "鍦烘櫙琛屽姩"))

	if choice_id == "sys.observe":
		return _with_handled(_v02_start_micro("observe", "闄勮繎淇″彿", "", "鍏煎鍏ュ彛"))
	if choice_id == "sys.forage":
		return _with_handled(_v02_start_micro("forage", "鍛ㄨ竟璧勬簮鐐?, "", "鍏煎鍏ュ彛"))
	if choice_id == "sys.hunt":
		_v02_ensure_leads_from_percepts(3)
		var track_lead_id: String = ""
		var best_score: int = -9999
		for l_any in v02_leads:
			if not (l_any is Dictionary):
				continue
			var l: Dictionary = l_any as Dictionary
			var lt: String = String(l.get("type", ""))
			if lt != "tracks" and lt != "patrol" and lt != "smoke":
				continue
			var score: int = int(l.get("quality", 50)) + int(l.get("stage", 1)) * 8
			if lt == "tracks":
				score += 8
			if score > best_score:
				best_score = score
				track_lead_id = String(l.get("id", ""))
		if track_lead_id == "":
			return _with_handled(_action_result("褰撳墠娌℃湁鏄庣‘杩借釜鐩爣锛岃鍏堣瀵熻幏鍙栫嚎绱€?))
		var li_track: int = _v02_find_lead_index(track_lead_id)
		if li_track < 0:
			return _with_handled(_action_result("褰撳墠娌℃湁鏄庣‘杩借釜鐩爣锛岃鍏堣瀵熻幏鍙栫嚎绱€?))
		var lead_track: Dictionary = v02_leads[li_track]
		return _with_handled(_v02_start_micro("track", _v02_lead_title(lead_track), track_lead_id, "鍏煎鍏ュ彛鑷姩閫夌洰鏍?))
	if choice_id == "sys.push":
		return _with_handled(_v02_start_micro("push", "鍓嶆柟璺嚎", "", "鍏煎鍏ュ彛"))
	if choice_id == "sys.rest":
		return _with_handled(_v02_start_micro("rest", "涓存椂浼戞暣鐐?, "", "鍏煎鍏ュ彛"))

	if choice_id == "sys.v02.tool.inventory":
		return _with_handled(_action_result("鑳屽寘宸叉墦寮€锛氬彲鏌ョ湅宸ュ叿銆佽嵂鍝佷笌琛ョ粰銆?))
	if choice_id == "sys.v02.tool.map":
		return _with_handled(_action_result("鍦板浘宸叉墦寮€锛氬彲鏌ョ湅璺嚎鍒嗘敮涓庡嵄闄╁彉鍖栥€?))
	if choice_id == "sys.v02.tool.log":
		var msg: String = "鏈€杩戝洖娴侊細\n"
		for l in v02_recent_visible_outcomes.slice(max(0, v02_recent_visible_outcomes.size() - 3), v02_recent_visible_outcomes.size()):
			msg += "- " + String(l) + "\n"
		return _with_handled(_action_result(msg.strip_edges()))
	if choice_id == "sys.v02.tool.growth":
		return _with_handled(_action_result("鎴愰暱闈㈡澘宸叉墦寮€锛氬彲鏌ョ湅鐗硅川涓庡睘鎬у彉鍖栥€?))
	if choice_id == "sys.v02.tool.system":
		return _with_handled(_action_result("绯荤粺闈㈡澘锛氬彲浣跨敤銆愬緟鍔炪€戜笌銆愪紶闂汇€戝叆鍙ｇ户缁拷韪腑鏈熷彉鍖栥€?))

	if choice_id.begins_with("sys.travel."):
		v02_guidance_due = true
		v01_guidance_due = true
		return {"handled": false}

	return {"handled": false}

func load_region(path: String) -> void:
	bootstrap(path, true)

# UI 姣忔鐐瑰嚮闇€瑕佷竴娈电函鏂囨湰锛岃繖閲屾妸 snapshot -> 鏂囨湰
func get_next_paragraph() -> String:
	if current_region.is_empty():
		return "[绌烘钀斤細鍖哄煙鏈姞杞絔"

	if has_pending_choice():
		return "[绛夊緟閫夋嫨] 璇峰厛鍦ㄤ笅鏂归€変竴涓鍔ㄣ€?

	var snap: Dictionary = produce_snapshot()
	var lines: Array[String] = []

	if snap.has("weather") and snap["weather"] is Dictionary:
		var w: Dictionary = snap["weather"] as Dictionary
		var wline: String = _pick_one(JsonUtil.dict_get_array(w, "text_templates", []))
		if wline == "":
			var wn: String = String(w.get("name", ""))
			if wn != "":
				wline = "澶╂皵杞负銆?s銆嶃€? % wn
		if wline != "":
			lines.append("[i]%s[/i]" % wline)

	var et: String = String(snap.get("event_text", ""))
	if et != "":
		lines.append(et)

	if lines.is_empty():
		return "椋庣┛杩囨灄姊紝鏃堕棿缁х画鍚戝墠銆?
	return "\n".join(lines)



# 鏃?UI 鐐瑰嚮鈥滈噸缃棩蹇椻€濅細璋冪敤
func clear_logs_folder() -> void:
	if DirAccess.dir_exists_absolute("user://logs"):
		var d := DirAccess.open("user://logs")
		if d:
			d.list_dir_begin()
			while true:
				var f := d.get_next()
				if f == "":
					break
				if d.current_is_dir():
					continue
				d.remove("user://logs/" + f)
			d.list_dir_end()
func _run_starter_once() -> String:
	var fired_key := "starter_fired_" + current_region_id
	if bool(flags.get(fired_key, false)):
		return ""

	var pools_any: Variant = current_region.get("pools", {})
	if not (pools_any is Dictionary):
		return ""

	var pools := pools_any as Dictionary
	var evs_any: Variant = pools.get("events", [])
	if not (evs_any is Array):
		return ""

	var starters: Array[Dictionary] = []
	for w_any in (evs_any as Array):
		if not (w_any is Dictionary):
			continue
		var wdict := w_any as Dictionary
		var ev_any: Variant = wdict.get("event", {})
		if not (ev_any is Dictionary):
			continue
		var ev := ev_any as Dictionary
		if bool(ev.get("starter", false)):
			starters.append({"event": ev, "weight": float(wdict.get("weight", 1.0))})

	if starters.is_empty():
		return ""

	flags[fired_key] = true
	var chosen := _weighted_pick(starters)
	var evd_any: Variant = chosen.get("event", {})
	var evd := evd_any as Dictionary if evd_any is Dictionary else {}
	return _execute_event(evd)
	
func _pick_one_event_text(wrapped_events: Array) -> String:
	var usable: Array[Dictionary] = []
	for w_any in wrapped_events:
		if not (w_any is Dictionary):
			continue
		var wdict := w_any as Dictionary
		var ev_any: Variant = wdict.get("event", {})
		if not (ev_any is Dictionary):
			continue
		var ev := ev_any as Dictionary
		var wt := float(wdict.get("weight", 1.0))
		if wt <= 0.0:
			continue
		usable.append({"event": ev, "weight": wt})
	if usable.is_empty():
		return ""
	var chosen := _weighted_pick(usable)
	var ev_run_any: Variant = chosen.get("event", {})
	var ev_run := ev_run_any as Dictionary if ev_run_any is Dictionary else {}
	return _execute_event(ev_run)

func _rng_index(n: int) -> int:
	if n <= 1:
		return 0
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng.randi_range(0, n - 1)
	
func flush_page_to_disk() -> void:
	var base := "user://logs"
	if not DirAccess.dir_exists_absolute(base):
		DirAccess.make_dir_absolute(base)
	var f := FileAccess.open(base + "/latest.txt", FileAccess.WRITE_READ)
	if f:
		f.seek_end()
		f.store_string("tick " + str(Time.get_unix_time_from_system()) + "\n")
		f.flush()
		f.close()
		print("鏃ュ織鎴愬姛鍐欏叆")  # 杩欐槸璋冭瘯淇℃伅
