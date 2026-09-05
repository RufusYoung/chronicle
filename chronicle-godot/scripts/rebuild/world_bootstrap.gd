extends Node


func _ready() -> void:
	if "--agent-stdio" in OS.get_cmdline_user_args():
		var driver = load("res://scripts/agent/agent_stdio_driver.gd").new()
		get_tree().quit(driver.run())
		return
	var scene := load("res://scenes/rebuild/world_demo.tscn") as PackedScene
	add_child(scene.instantiate())
