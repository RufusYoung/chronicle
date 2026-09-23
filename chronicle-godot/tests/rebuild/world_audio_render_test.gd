extends "res://tests/rebuild/world_demo_surface_test.gd"

const Audio = preload("res://scripts/rebuild/world_audio.gd")


func _run() -> void:
	output = "user://tests/world_audio_evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = path
	viewer.initial_content_extension = true
	viewer.audio_settings_path = "user://tests/sound_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".cfg"
	root.add_child(viewer)
	await process_frame
	await process_frame
	var before := _signature(viewer.view_model)
	var sound: Node = viewer.world_audio
	var button: Button = viewer.find_child("SoundSettings", true, false)
	_check(button != null, "shared header has labeled sound settings")
	for row: Dictionary in viewer.current_view_data.get("visible_observations", []):
		_check("generated_resident." not in str(row.get("state_text", "")), "unknown organization representative is not a raw entity ID")
	for height: int in [720, 900]:
		root.size = Vector2i(1280 if height == 720 else 1600, height)
		root.content_scale_size = root.size
		await process_frame
		await process_frame
		_check(viewer.action_dock.get_global_rect().end.y <= height, "sound control keeps dock inside viewport")
		_check(button.get_global_rect().end.x <= root.size.x, "sound control remains in header")
		button.pressed.emit()
		await process_frame
		await _screenshot("sound_settings_%d.png" % height)
		var slider := sound._dialog.find_child("EffectsVolume", true, false) as HSlider
		_check(slider.has_focus(), "volume slider receives keyboard focus")
		slider.value = 0
		var count: int = sound.play_count
		sound.play("arrival")
		_check(sound.play_count == count and not sound.output.playing, "mute stops and suppresses actual audio")
		slider.value = 50
		sound._dialog.hide()
		_check(button.has_focus(), "closing dialog returns focus")
		var guide_button: Button = viewer.find_child("PlayGuide", true, false)
		_check(guide_button.get_global_rect().end.x <= root.size.x, "guide stays inside compact header")
		guide_button.pressed.emit()
		await process_frame
		var guide: AcceptDialog = viewer._play_guide
		var guide_body: Label = guide.find_child("GuideBody", true, false)
		for section: String in viewer.PlayGuide.PAGES:
			var page_buttons: Array = guide.find_children("*", "Button", true, false).filter(func(row: Button) -> bool: return row.text == section)
			page_buttons[0].button_pressed = true
			page_buttons[0].pressed.emit()
			await process_frame
			_check(guide_body.text == viewer.PlayGuide.PAGES[section], "guide page has complete content: " + section)
			_check(page_buttons[0].button_pressed, "guide navigation shows active section")
			_check(guide.size.y < height - 40 and guide_body.get_global_rect().end.y <= guide.size.y, "guide fits without inner scrolling: " + section)
			await _screenshot("guide_%d_%s.png" % [height, section])
		guide.hide()
		_check(guide_button.has_focus(), "closing guide restores keyboard focus")
	_check(_signature(viewer.view_model) == before, "audio settings change neither world nor RNG")
	var reloaded := Audio.new()
	reloaded.settings_path = viewer.audio_settings_path
	root.add_child(reloaded)
	_check(is_equal_approx(reloaded.level, 0.5), "audio preference reloads outside world save")
	for cue: String in Audio.STREAMS:
		var stream: AudioStream = Audio.STREAMS[cue]
		_check(stream.get_length() > 0.05 and stream.get_length() < 1, "bounded valid cue: " + cue)
		sound.play(cue)
		await process_frame
		_check(sound.output.playing and sound.last_cue == cue, "AudioStreamPlayer actually starts cue: " + cue)
	var initial := {"location": {"id": "a"}, "player": {"health": 100}, "equipment_journal": {
		"features": [{"id": "skill.craft", "kind": "skill", "name": "craft", "rank": 0, "xp": 0}]}}
	var changed := initial.duplicate(true)
	changed.equipment_journal.features[0].xp = 4
	_check(Audio.cue_for("act_player_life", {"success": true}, initial, changed) == "action", "ordinary XP is not an unlock celebration")
	changed.equipment_journal.features[0].rank = 1
	_check(Audio.cue_for("act_player_life", {"success": true}, initial, changed) == "growth", "actual changed rank has distinct cue")
	changed.feedback = {"status": "interrupted"}
	_check(Audio.cue_for("act_player_life", {"success": true}, initial, changed) == "warning", "accepted but interrupted work never sounds like reward")
	for method: String in ["save_to_path", "load_from_path", "start"]:
		_check(Audio.cue_for(method, {"success": true}, initial, changed) == "", "no replayed result on " + method)
	viewer.perform_travel(_route_to(viewer.view_model, "generated_location.echo_landing.landing"))
	await _settle(viewer)
	_check(sound.last_cue == "arrival", "formal asynchronous travel selects actual arrival cue")
	var count: int = sound.play_count
	viewer.refresh_view()
	_check(sound.play_count == count, "redraw does not replay audio")
	var settings: String = viewer.audio_settings_path
	reloaded.queue_free()
	viewer.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings))
	print("WORLD_AUDIO_RENDER %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
