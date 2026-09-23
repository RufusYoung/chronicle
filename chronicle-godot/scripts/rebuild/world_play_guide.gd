extends RefCounted

const Style = preload("res://scripts/rebuild/v5_shared_interface_style.gd")
const PAGES := {
	"起步": "你是途经港外的旅人，不必按任务清单生活。世界只在行动时推进，读说明、翻页和查看行囊不耗时。\n\n先备粮：到泊台采食，留出出行和疗伤的口粮。\n先谋生：短工需要雇主在场、付得起钱；中断不保证报酬。\n先探索：路线写明时长与用途，远处是否有货、是否安全，要到场或听取消息才知道。\n\n三种安排会争用同一天的时间。先看右侧身体和路线，再看下方行动代价；不必把亮起的按钮都点一遍。",
	"装备与成长": "「行囊与成长」可查看实物、耐久、被动条件与穿戴。物品在行囊里不等于已装备；途中或交锋中不能换装。\n\n长工棚可徒手搓绳，再用绳具编织装备。制作消耗当地苇材、时间和工具耐久；复杂配方需要真实制作经验。\n\n长枪有利进攻但妨碍撤离；苇甲更能防守但笨重；轻披和结绳带有利离场。没有一套配置样样最强。\n\n技能来自实际工作、行路或攻守，特质来自经历，也可能带有代价。规则以当前行囊和行动说明为准；旧存档不会自动增加新内容。",
	"危险与后续": "危险会随当地时刻、资源和居民行动变化。坡田有时平静，这不表示它永远安全；也不会为了等你而锁住一场战斗。\n\n进攻可迫使对方退却；稳守积累优势；脱离成功只打开离场窗口，还要沿道路离开。失败会受伤、耗损装备；先备餐或换装，要付出时间。\n\n回到安全处休养，疲劳会下降；疗伤需要真实口粮。分粮、交易或排除危险之后，可以再见到当地人、询问后续，查看他们实际如何使用物资。帮助不保证所有人都变好。\n\n每次结果会说明发生了什么。更多经过在「记录」。本版需手动保存；「声音」可静音。",
}


static func install(parent: Node, header: Control) -> AcceptDialog:
	var opener := Button.new()
	opener.name = "PlayGuide"
	opener.text = "怎么玩"
	opener.tooltip_text = "查看操作与选择说明，不推进时间。"
	Style.apply_command_button(opener)
	header.add_child(opener)
	var dialog := AcceptDialog.new()
	dialog.title = "旅人手册"
	dialog.get_ok_button().text = "返回游戏"
	parent.add_child(dialog)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	dialog.add_child(content)
	var choices := HBoxContainer.new()
	content.add_child(choices)
	var body := Label.new()
	body.name = "GuideBody"
	body.custom_minimum_size = Vector2(600, 300)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = PAGES["起步"]
	var group := ButtonGroup.new()
	for title: String in PAGES:
		var button := Button.new()
		button.text = title
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = title == "起步"
		Style.apply_command_button(button)
		choices.add_child(button)
		button.pressed.connect(func() -> void: body.text = PAGES[title])
	content.add_child(body)
	opener.pressed.connect(func() -> void:
		dialog.popup_centered(Vector2i(660, 445))
		choices.get_child(0).grab_focus())
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			opener.grab_focus())
	return dialog
