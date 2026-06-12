# res://scripts/singletons/RNG.gd
extends Node
class_name RNG

var _r := RandomNumberGenerator.new()

func _ready() -> void:
	_r.randomize()

func f() -> float:
	return _r.randf()

func i(mini: int, maxi: int) -> int:
	return _r.randi_range(mini, maxi)

func pick_one(arr: Array) -> Variant:
	if arr.is_empty(): return null
	return arr[i(0, arr.size()-1)]
