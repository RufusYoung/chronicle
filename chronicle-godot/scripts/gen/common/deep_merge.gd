extends Node
class_name DeepMerge

## 深度合并：
## - 两边都是 Dictionary -> 递归合并
## - （可选）两边都是 Array -> 连接（concat），否则覆盖
## - 其他类型 -> 覆盖
## 会对写入的 Dictionary/Array 做 deep duplicate，避免别处引用被连带修改
func deep_merge(base: Dictionary, extra: Dictionary, merge_arrays: bool = false) -> Dictionary:
	var out: Dictionary = base.duplicate(true)  # 深拷贝 base，避免改到外部
	for k in extra.keys():
		var v_extra: Variant = extra[k]
		var v_out: Variant = out.get(k, null)

		# 字典 + 字典：递归
		if (v_out is Dictionary) and (v_extra is Dictionary):
			out[k] = deep_merge(v_out as Dictionary, v_extra as Dictionary, merge_arrays)
			continue

		# （可选）数组 + 数组：合并，否则覆盖
		if merge_arrays and (v_out is Array) and (v_extra is Array):
			var a_out: Array = (v_out as Array).duplicate(true)
			var a_extra: Array = (v_extra as Array).duplicate(true)
			a_out.append_array(a_extra)
			out[k] = a_out
			continue

		# 其他情况：覆盖（但若是复合类型，先深拷贝再写回，避免共享引用）
		if v_extra is Dictionary:
			out[k] = (v_extra as Dictionary).duplicate(true)
		elif v_extra is Array:
			out[k] = (v_extra as Array).duplicate(true)
		else:
			out[k] = v_extra

	return out
