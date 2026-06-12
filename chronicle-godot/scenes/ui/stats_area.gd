extends VBoxContainer  # 假设脚本附加到 VBoxContainer

func _ready():
	# 获取 VBoxContainer 下所有的 ProgressBar 和 Label
	var progress_bars = [
		$ProgressBar1,
		$ProgressBar2,
		$ProgressBar3,
		$ProgressBar4
	]
	
	for bar in progress_bars:
		# 获取每个 ProgressBar 对应的 Label 节点
		var label = bar.get_node("CenterContainer/Label")
		
		# 更新进度条
		update_progress_bar(bar, label)

# 更新进度条和 Label
func update_progress_bar(progress_bar, label):
	# 获取 Label 中的文本 (例如： "475/600")
	var text = label.text
	
	# 使用正则表达式提取当前进度和最大进度
	var regex = RegEx.new()
	regex.compile(r"(\d+)/(\d+)")  # 匹配形如 "475/600" 的文本
	var match = regex.search(text)
	
	if match:
		# 提取当前进度和最大进度
		var current_progress = int(match.get_string(1))  # 获取第一个数字（当前进度）
		var max_progress = int(match.get_string(2))      # 获取第二个数字（最大进度）

		# 计算进度百分比
		var progress_percentage = float(current_progress) / float(max_progress)

		# 根据进度百分比来设置 ProgressBar 的值
		progress_bar.value = progress_percentage * progress_bar.max_value  # 设置进度条的当前值
		
		# 输出调试信息
		print("ProgressBar value: ", progress_bar.value, " / ", progress_bar.max_value)
