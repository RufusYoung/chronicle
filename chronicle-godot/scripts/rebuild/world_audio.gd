extends Node
## Presentation-only audio: no world state, simulation RNG or global audio-bus mutation.

const STREAMS := {
	"action": preload("res://art/audio/action_v1.wav"),
	"arrival": preload("res://art/audio/arrival_v1.wav"),
	"work": preload("res://art/audio/work_v1.wav"),
	"warning": preload("res://art/audio/warning_v1.wav"),
	"growth": preload("res://art/audio/growth_v1.wav"),
}
const Style = preload("res://scripts/rebuild/v5_shared_interface_style.gd")
var settings_path := "user://presentation.cfg"
var level := 0.5
var output: AudioStreamPlayer
var last_cue := ""
var play_count := 0
var _dialog: AcceptDialog


func _ready() -> void:
	var config := ConfigFile.new()
	if settings_path != "" and config.load(settings_path) == OK:
		var saved: Variant = config.get_value("audio", "volume", 0.5)
		if (saved is int or saved is float) and is_finite(float(saved)):
			level = clampf(float(saved), 0.0, 1.0)
	output = AudioStreamPlayer.new()
	add_child(output)
	output.volume_db = linear_to_db(maxf(level, 0.0001))


func install_control(header: Control) -> void:
	var button := Button.new()
	button.name = "SoundSettings"
	button.text = "声音"
	button.tooltip_text = "调整结果音效音量，不推进世界时间。"
	Style.apply_command_button(button)
	header.add_child(button)
	_dialog = AcceptDialog.new()
	_dialog.title = "声音设置"
	_dialog.get_ok_button().text = "返回游戏"
	add_child(_dialog)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 16)
	_dialog.add_child(form)
	var label := Label.new()
	label.text = "结果音效 %d%%（0%% 为静音）" % roundi(level * 100)
	form.add_child(label)
	var slider := HSlider.new()
	slider.name = "EffectsVolume"
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = roundi(level * 100)
	slider.custom_minimum_size = Vector2(340, 32)
	slider.tooltip_text = "结果音效音量，可用左右方向键调整。"
	form.add_child(slider)
	slider.value_changed.connect(func(value: float) -> void:
		set_level(value / 100.0)
		label.text = "结果音效 %d%%（0%% 为静音）" % roundi(value))
	var preview := Button.new()
	preview.text = "试听"
	Style.apply_command_button(preview)
	form.add_child(preview)
	preview.pressed.connect(func() -> void: play("arrival"))
	button.pressed.connect(func() -> void:
		_dialog.popup_centered(Vector2i(400, 220))
		slider.grab_focus())
	_dialog.visibility_changed.connect(func() -> void:
		if not _dialog.visible:
			button.grab_focus())


func set_level(value: float, persist: bool = true) -> void:
	level = clampf(value, 0.0, 1.0)
	output.volume_db = linear_to_db(maxf(level, 0.0001))
	if level == 0:
		output.stop()
	if persist and settings_path != "":
		var config := ConfigFile.new()
		config.load(settings_path)
		config.set_value("audio", "volume", level)
		if config.save(settings_path) != OK:
			push_warning("Could not save local sound preference; world save is unchanged.")


static func cue_for(method: String, result: Dictionary, before: Dictionary, after: Dictionary) -> String:
	if method in ["save_to_path", "load_from_path", "start"]:
		return ""
	if not result.get("success", false) or after.get("feedback", {}).get("status") in ["failure", "interrupted"]:
		return "warning"
	if int(after.get("player", {}).get("health", 100)) < int(before.get("player", {}).get("health", 100)):
		return "warning"
	var old := {}
	for feature: Dictionary in before.get("equipment_journal", {}).get("features", []):
		old[feature.id] = feature.get("rank", feature.get("acquired", false))
	for feature: Dictionary in after.get("equipment_journal", {}).get("features", []):
		if old.has(feature.id) and old[feature.id] != feature.get("rank", feature.get("acquired", false)):
			return "growth"
	if before.get("location", {}).get("id") != after.get("location", {}).get("id"):
		return "arrival"
	if result.get("work_completed", false):
		return "work"
	return "action" if method != "advance_time" else ""


func play(cue: String) -> void:
	if DisplayServer.get_name() == "headless" or level <= 0 or not STREAMS.has(cue):
		return
	last_cue = cue
	play_count += 1
	output.stream = STREAMS[cue]
	output.play()


func _exit_tree() -> void:
	if is_instance_valid(output):
		output.stop()
		output.stream = null
