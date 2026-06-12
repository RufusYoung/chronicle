# res://scripts/gen/common/json_util.gd
extends Node
class_name JsonUtil

# ------- 文件读取 / JSON 解析 -------
static func read_text(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		push_error("[JsonUtil] Empty or missing file: %s" % path)
	return text

static func parse_any(text: String) -> Variant:
	var v: Variant = JSON.parse_string(text)
	if v == null:
		push_error("[JsonUtil] JSON parse failed. Text length=%d" % text.length())
	return v

static func load_dict(path: String) -> Dictionary:
	var text: String = read_text(path)
	if text == "":
		return {}
	var v: Variant = parse_any(text)
	if typeof(v) != TYPE_DICTIONARY:
		push_error("[JsonUtil] Root is not Dictionary: %s" % path)
		return {}
	return v as Dictionary

static func load_array(path: String) -> Array:
	var text: String = read_text(path)
	if text == "":
		return []
	var v: Variant = parse_any(text)
	if typeof(v) != TYPE_ARRAY:
		push_error("[JsonUtil] Root is not Array: %s" % path)
		return []
	return v as Array

# ------- 安全取字段（带类型约束）-------
static func dict_get_dict(d: Dictionary, key: String, default_val: Dictionary = {}) -> Dictionary:
	var any: Variant = d.get(key, default_val)
	if any is Dictionary:
		return any as Dictionary
	else:
		return default_val

static func dict_get_array(d: Dictionary, key: String, default_val: Array = []) -> Array:
	var any: Variant = d.get(key, default_val)
	if any is Array:
		return any as Array
	else:
		return default_val

static func dict_get_string(d: Dictionary, key: String, default_val: String = "") -> String:
	var any: Variant = d.get(key, default_val)
	if any is String:
		return any as String
	else:
		return default_val
