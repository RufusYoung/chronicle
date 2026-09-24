extends RefCounted

const Style = preload("res://scripts/rebuild/v5_shared_interface_style.gd")
const PAGES := {
	"起步": "你是途经镜湖北岸的旅人。世界只在行动时推进，查看说明、行囊和行动详情不耗时；不必点完每个选项。\n\n想探险：泊台通向回水洞，守望处通向废灯台。先辨路、准备绳具，或冒险直接尝试，代价不同。可以放弃眼前发现，物资不会刷新。\n想谋生：去长工棚制作自己的装备，或在有人、有货时买卖。短工会被离场与危险打断。\n想结识当地人：晚间到客舍，主人在场时可交谈、喝麦饮或付费住宿。得到的消息可能改变探路方法。\n\n留意食物与疲劳，但不用每天只睡觉找粮。先选一件自己想做的事，再看路线和代价。旧存档没有这些新地点，需「新世界」。",
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
