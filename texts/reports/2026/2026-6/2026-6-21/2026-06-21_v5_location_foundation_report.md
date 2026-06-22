# 2026-06-21 v5 地点局面主界面原型报告

## 1. 本次完成内容

本次完成了 v5.1 重构阶段 1 的独立开发原型：

- 新增独立 rebuild 开发场景，不接入旧 `mainui.tscn`。
- 新增静态湖湾镇地点局面数据。
- 新增 `State / ViewModel / Viewer` 三层拆分。
- 实现左侧角色状态、中央地点局面、右侧地区状态 / 线索 / 地点、底部行动选项、顶部导航入口。
- 实现最小湖湾镇交互闭环：走近陈米、查看涨价告示、市场打听粮价、前往废弃粮仓、停留一月。
- 实现线索获得、线索列表展示、线索行动卡展示。
- 实现生涯面板占位，并能在“在湖湾镇停留一月”后写入已完成经历。

## 2. 新增文件

```text
chronicle-godot/data/rebuild/lake_town_location_foundation.json
chronicle-godot/scripts/rebuild/v5_location_foundation_state.gd
chronicle-godot/scripts/rebuild/v5_location_foundation_view_model.gd
chronicle-godot/scripts/rebuild/v5_location_foundation_viewer.gd
chronicle-godot/scenes/rebuild/v5_location_foundation_viewer.tscn
chronicle-godot/tests/rebuild/v5_location_foundation_state_test.gd
chronicle-godot/tests/rebuild/v5_location_foundation_viewer_test.gd
texts/reports/2026/2026-6/2026-6-21/2026-06-21_v5_location_foundation_report.md
```

## 3. 交互能力

当前场景可打开后显示：

- 左侧：阿尔维斯状态、生命、健康、精力、理智、饥饿、六大属性、核心特质。
- 中央：湖湾镇或当前地点局面、可见人物、可见痕迹、子地点按钮。
- 右侧：地区状态、已获得线索、地点节点。
- 底部：当前行动按钮。

已验证的交互：

- `[对话] 走近陈米` 会切换为陈米近景，并显示“给她食物 / 问粮从哪来的 / 装作没看见”。
- `[普通] 查看涨价告示` 会获得 `[线索] 粮价明天再涨一次`。
- 点击粮价线索会打开线索行动卡。
- `[线索] 去市场打听粮价 1小时` 会更新粮食状态，并获得 `[线索] 北路商队迟到`。
- `[危险] 前往废弃粮仓 半日` 会切换当前地点到废弃粮仓。
- `[长期] 在湖湾镇停留一月` 会改变角色状态和地区状态，并把“在湖湾镇停留一月”写入生涯面板。

## 4. 测试结果

已运行：

```text
Godot --headless --quit-after 200 --path . --script res://tests/rebuild/v5_location_foundation_state_test.gd
Godot --headless --quit-after 200 --path . --script res://tests/rebuild/v5_location_foundation_viewer_test.gd
```

结果：

```text
[V5 LOCATION FOUNDATION RESULT] PASS
[V5 LOCATION VIEWER LOOP RESULT] PASS
```

同时执行了保护文件 diff 检查，未发现保护文件改动。

## 5. 未完成内容

本次没有完成完整 Chronicle Demo。

本次未实现：

- 完整战斗系统
- 完整装备系统
- 完整职业系统
- 完整食物系统
- 完整天气系统
- 完整传记系统
- AI 文本生成
- 旧 `mainui.tscn` 接入
- 旧 `story_player.gd` 改造
- 旧 `world_generation_v03.gd` 改造
- 湖湾镇阶段 2 的真实状态因果闭环
- 完整长期项目和阶段结算
- 美术资源接入

当前原型仍是静态湖湾镇交互闭环，重点是验证前台承载面和 State / ViewModel / Viewer 分离。

## 6. 未修改保护文件确认

本次未修改：

```text
chronicle-godot/scenes/ui/story_player.gd
chronicle-godot/scripts/gen/world_generation_v03.gd
chronicle-godot/scenes/ui/mainui.tscn
chronicle-godot/project.godot
chronicle-godot/素材包/
```

`chronicle-godot/素材包/` 中的图标和音效本次仅被识别为可用素材来源，没有修改，也没有接入到本阶段原型。

## 7. 下一步建议

下一步进入路线图阶段 2：湖湾镇最小状态闭环。

建议聚焦：

- 把当前静态陈米局面改为可追溯状态链。
- 新增老陈、陈米、玛婶、刘账房、废弃粮仓、腐败粮食等最小对象状态。
- 让玩家行动改变 NPC、地点、地区状态、痕迹和线索。
- 继续保持 rebuild 独立目录，不接旧主界面。
