# res://scripts/ui/mainui.gd
extends Control

var world: WorldGeneration = WorldGeneration.new()
@onready var story: RichTextLabel = $StoryBox
@onready var btn_new: Button = $BtnBar/NewRunBtn
@onready var btn_reset: Button = $BtnBar/RestartBtn
@onready var btn_open: Button = $BtnBar/OpenLogBtn

# 你的区域 JSON 路径（确认这个文件真存在）
const REGION_JSON := "res://data/regions/回响之境/地区/中央偏北界域 - 碎星与镜湖/镜湖森林带/镜湖森林带.json"

func _ready() -> void:
	# --- 基本 UI 设置 ---
	story.bbcode_enabled = true
	story.autowrap_mode = TextServer.AUTOWRAP_WORD
	story.scroll_active = true
	story.mouse_filter = Control.MOUSE_FILTER_STOP   # 确保能接收到 gui_input

	# --- 页面先给一行，确认脚本在跑 ---
	_append_line("[color=gray]UI ready（脚本已运行）[/color]")

	# --- 验证 JSON 路径 ---
	if not FileAccess.file_exists(REGION_JSON):
		_append_line("[color=crimson]区域 JSON 不存在：[/color]" + REGION_JSON)
	else:
		_append_line("[color=gray]找到区域 JSON：[/color]" + REGION_JSON)

	# --- 尝试加载区域 ---
	_safe_load_region()

	# --- 接信号（健壮版，失败会在页面提示） ---
	_connect_ui_signals()

	# --- 首段 ---
	_append_next()


func _connect_ui_signals() -> void:
	var ok := true
	if story:
		var err1 = story.gui_input.connect(_on_story_gui_input)
		if err1 != OK:
			ok = false
			_append_line("[color=crimson]连接 story.gui_input 失败[/color]")

	if btn_new:
		var err2 = btn_new.pressed.connect(_on_new_run)
		if err2 != OK:
			ok = false
			_append_line("[color=crimson]连接 NewRunBtn.pressed 失败[/color]")
	if btn_reset:
		var err3 = btn_reset.pressed.connect(_on_reset_logs)
		if err3 != OK:
			ok = false
			_append_line("[color=crimson]连接 RestartBtn.pressed 失败[/color]")
	if btn_open:
		var err4 = btn_open.pressed.connect(_on_open_logs_dir)
		if err4 != OK:
			ok = false
			_append_line("[color=crimson]连接 OpenLogBtn.pressed 失败[/color]")

	if ok:
		_append_line("[color=gray]UI 信号已连接[/color]")


func _safe_load_region() -> void:
	if world == null:
		_append_line("[color=crimson]world 为 null，WorldGeneration 未实例化[/color]")
		return
	if not FileAccess.file_exists(REGION_JSON):
		return
	# 有些项目里把 load_region 命名成 bootstrap，这里两种名都兼容
	if world.has_method("load_region"):
		world.load_region(REGION_JSON)
		_append_line("[color=gray]load_region() 已调用[/color]")
	elif world.has_method("bootstrap"):
		world.bootstrap(REGION_JSON)
		_append_line("[color=gray]bootstrap() 已调用[/color]")
	else:
		_append_line("[color=crimson]WorldGeneration 里既没有 load_region 也没有 bootstrap[/color]")


func _on_story_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_append_line("[color=gray]点击 StoryBox：继续[/color]")
		_append_next()


func _append_next() -> void:
	if world == null:
		_append_line("[color=crimson]world 为 null（未实例化）[/color]")
		return

	# 保底：如果 get_next_paragraph 不存在，直接报给你
	if not world.has_method("get_next_paragraph"):
		_append_line("[color=crimson]WorldGeneration.get_next_paragraph() 缺失[/color]")
		return

	var p := ""
	# 用 try 防止内部异常把 UI“吃掉”
	# Godot 没有 try/catch，这里直接调用并检查结果
	p = world.get_next_paragraph()

	if typeof(p) != TYPE_STRING:
		_append_line("[color=crimson]get_next_paragraph() 未返回字符串[/color]")
		return

	if p == "":
		var hint := "[color=gray]（空段落：可能 1) 区域未正确加载；2) 入区事件未触发；3) 正在等待选项；4) 区域 pools/events 为空；5) 你的 get_next_paragraph 内部直接返回了空）[/color]"
		_append_line(hint)
		return

	_append_line(p)
	# 如果有 flush_page_to_disk 就调用（没有也不报错）
	if world.has_method("flush_page_to_disk"):
		world.flush_page_to_disk()


func _on_new_run() -> void:
	_append_line("[color=gray]点击 新开一段[/color]")
	if world and world.has_method("flush_page_to_disk"):
		world.flush_page_to_disk()
	story.clear()
	world = WorldGeneration.new()
	_safe_load_region()
	_append_next()


func _on_reset_logs() -> void:
	_append_line("[color=gray]点击 清理日志[/color]")
	if world and world.has_method("clear_logs_folder"):
		world.clear_logs_folder()
	else:
		_append_line("[color=gray]WorldGeneration.clear_logs_folder() 不存在，已忽略[/color]")


func _on_open_logs_dir() -> void:
	_append_line("[color=gray]点击 打开日志目录[/color]")
	OS.shell_open(ProjectSettings.globalize_path("user://logs"))


# ===== 小工具 =====
func _append_line(s: String) -> void:
	if story == null:
		return
	story.append_text(s + "\n\n")
	story.scroll_to_line(999999)
