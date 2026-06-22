# 2026-06-21 v5 地点局面主界面体验修正报告

## 1. 本次修正内容

本次是 v5.1 重构阶段 1.1 小修，只修正上一轮地点局面主界面原型的体验问题。

完成内容：

- 顶部菜单改为覆盖式弹窗，不再永久替换主界面。
- 弹窗支持关闭按钮。
- 弹窗支持 Esc 返回主界面。
- 切换地点后，底部行动选项会根据当前地点变化。
- 左侧角色状态栏调整为更紧凑的状态摘要格式。
- 新增 UI 修正测试，覆盖菜单弹窗、Esc、地点行动刷新和左侧状态栏格式。

## 2. 菜单弹窗与 Esc 返回

顶部菜单按钮仍为：

```text
背包
角色
世界
生涯
设置
```

现在点击后会打开覆盖式弹窗：

- 背包：显示“背包系统尚未接入。”
- 角色：显示角色详情、六大属性、核心特质和当前状态。
- 世界：显示“世界地图尚未接入。”
- 生涯：显示可开始方向、听说过但尚未开启、已完成经历和纪事。
- 设置：显示“设置系统尚未接入。”

弹窗关闭方式：

- 点击“关闭”按钮。
- 按 Esc。

关闭弹窗不会重置当前地点，不会清空线索，也不会清空行动历史。

## 3. 地点切换后的行动选项刷新

地点切换后，底部行动选项现在由 State 层根据当前地点返回。

已支持：

- 湖湾镇：走近陈米、查看涨价告示、市场打听粮价、前往废弃粮仓、停留一月、离开湖湾镇。
- 老陈铺子：走近陈米、查看涨价告示、敲门找老陈、观察门口痕迹、返回湖湾镇。
- 市场：去市场打听粮价、观察买粮的人、询问摊贩、返回湖湾镇。
- 码头：查看停靠商船、打听北路商队、观察守卫巡逻、返回湖湾镇。
- 守卫所：询问夜巡情况、向守卫报告异常、查看告示栏、返回湖湾镇。
- 废弃粮仓：检查门缝、查看灰白粮粉、进入粮仓、返回湖湾镇。

这些行动仍是阶段 1 的静态交互，不代表已经进入阶段 2 的真实因果闭环。

## 4. 左侧状态栏格式调整

左侧状态栏已改为：

```text
阿尔维斯
26 岁｜流浪者｜湖湾镇

生命：32 / 32
精力：48 / 60
健康：76 / 100　无明显伤势
理智：67 / 100　夜里睡得不深
饥饿：28 / 100

核心特质：流浪者、天生敏锐

力量 7
敏捷 8
智慧 9
魅力 6
体质 8
感知 10
```

已移除单独的：

```text
伤势：
精神：
```

## 5. 测试结果

已运行：

```text
Godot --headless --quit-after 200 --path . --script res://tests/rebuild/v5_location_foundation_state_test.gd
Godot --headless --quit-after 200 --path . --script res://tests/rebuild/v5_location_foundation_viewer_test.gd
Godot --headless --quit-after 200 --path . --script res://tests/rebuild/v5_location_ui_fix_test.gd
```

结果：

```text
[V5 LOCATION FOUNDATION RESULT] PASS
[V5 LOCATION VIEWER LOOP RESULT] PASS
[V5 LOCATION UI FIX RESULT] PASS
```

## 6. 未修改保护文件确认

本次未修改：

```text
chronicle-godot/scenes/ui/story_player.gd
chronicle-godot/scripts/gen/world_generation_v03.gd
chronicle-godot/scenes/ui/mainui.tscn
chronicle-godot/project.godot
chronicle-godot/素材包/
```

本次没有接入旧主界面，没有修改旧 Demo，没有进入阶段 2。

## 7. 下一步建议

下一步可以继续在 `exp/v5-rebuild-location-foundation` 上体验这个阶段 1.1 场景。

如果主界面体验认可，再进入路线图阶段 2：

```text
湖湾镇最小状态闭环
```

阶段 2 应重点处理真实状态链，而不是继续扩展静态按钮数量。
