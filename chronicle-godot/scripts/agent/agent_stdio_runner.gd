extends SceneTree

const Driver = preload("res://scripts/agent/agent_stdio_driver.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	quit(Driver.new().run())
