# world_sim 开发者观察工具报告

## 1. 本次目标

建立一个独立的无头开发者观察工具，用于读取并展示：

- 每日地区状态
- 每日势力状态
- 每日 `world_news`
- 每日 `LeadCandidate`
- 每日适配后 v0.3 线索
- 无模拟干预与第 3 天测试注入的 A/B 差异

本工具属于开发工具层，不接正式 UI，不修改当前 Demo 行为，也不生成新的世界事实规则。

## 2. 新增文件

核心文件：

- `scripts/dev/world_sim_observer.gd`
- `tests/world_sim_observer_test.gd`
- `texts/reports/2026/2026-06-13_world_sim_observer_output.md`
- `texts/reports/2026/2026-06-13_world_sim_observer_report.md`

Godot 自动生成的脚本 UID：

- `scripts/dev/world_sim_observer.gd.uid`
- `tests/world_sim_observer_test.gd.uid`

## 3. 未修改的保护文件

本次没有修改：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

测试在运行观察器前后读取并比较上述 Demo 运行文件，结果一致。

## 4. 观察器接口

已实现：

```gdscript
func run_baseline(days: int = 30) -> Dictionary
func run_with_test_injection(days: int = 30, injection_day: int = 3) -> Dictionary
func build_daily_snapshot(state: Variant) -> Dictionary
func build_region_summary(state: Variant) -> Array
func build_faction_summary(state: Variant) -> Array
func build_news_summary(state: Variant, day: int) -> Array
func build_lead_summary(state: Variant, day: int) -> Array
func build_adapted_lead_summary(state: Variant, day: int) -> Array
func compare_runs(a_result: Dictionary, b_result: Dictionary) -> Dictionary
func export_markdown_report(result: Dictionary, output_path: String) -> void
```

`WorldSimState` 当前是对象。观察器直接读取该对象，同时让地区与势力汇总接口兼容序列化后的字典结构。

## 5. 观察输出内容

每日 snapshot 包含：

- 当前天数
- 三个地区的八项主要数值与 tags
- 三个势力的 power、wealth、hostility 与 goal
- 当天 `world_news`
- 当天新生成的 `LeadCandidate`
- 当天新生成线索的 v0.3 适配结果

30 天总览包含：

- 最终地区与势力状态
- `world_fact`、`world_news`、候选线索和适配后线索数量
- 适配后线索类型分布
- 地区 tag 变化

观察输出写入：

```text
res://texts/reports/2026/2026-06-13_world_sim_observer_output.md
```

每日新闻、候选线索和适配后线索各最多展示 3 条。

## 6. 无模拟干预 30 天观察摘要

固定 seed：`20260613`

总量：

```text
world_fact: 192
world_news: 98
LeadCandidate: 40
适配后 v0.3 线索: 40
```

适配后类型分布：

```text
传闻: 15
河流: 3
烟柱: 13
足迹: 9
```

最终地区重点状态：

```text
border_town:
  danger 66.69 / order 0.00 / scarcity 98.00 / food 3.61

mirror_lake_forest:
  danger 71.66 / order 29.07 / scarcity 35.09 / mystic 65.59

old_ruins:
  danger 100.00 / order 0.00 / scarcity 58.96 / mystic 100.00
```

最终势力重点状态：

```text
echo_cult: power 72.30 / wealth 48.10 / hostility 0.00
smugglers: power 42.60 / wealth 100.00 / hostility 0.00
wardens: power 79.40 / wealth 10.00 / hostility 0.00
```

## 7. 第 3 天测试注入后观察摘要

第 3 天执行：

```gdscript
help_faction(state, "wardens", "border_town")
```

总量：

```text
world_fact: 202
world_news: 103
LeadCandidate: 39
适配后 v0.3 线索: 39
```

适配后类型分布：

```text
传闻: 15
河流: 3
烟柱: 12
足迹: 9
```

最终 `border_town`：

```text
danger 62.55 / order 1.53 / scarcity 75.37 / food 32.61
```

最终相关势力：

```text
smugglers: power 43.20 / wealth 100.00 / hostility 8.00
wardens: power 82.80 / wealth 5.00 / hostility -6.00
```

## 8. A/B 差异摘要

- 第 10 天已经出现地区、势力、新闻或线索差异。
- 第 30 天 `border_town` 的危险、秩序、匮乏和粮食状态不同。
- 第 30 天守望者与走私者的 power、wealth 或 hostility 不同。
- 测试注入组比基线多 5 条 `world_news`。
- 测试注入组比基线少 1 条 `LeadCandidate`。
- 测试注入组比基线少 1 条适配后线索。
- 原始线索签名不同。
- 适配后线索签名不同。

这说明观察器能展示模拟干预如何沿后续世界演化传播，而不是只显示注入当日的即时数值。

## 9. 测试结果

执行：

```text
Godot --headless --path chronicle-godot --script res://tests/world_sim_observer_test.gd
```

验证内容：

- 两组运行均产生 30 个每日 snapshot
- 地区与势力摘要存在
- 新闻、候选线索和适配后线索摘要存在
- 第 10 天已出现 A/B 差异
- 原始与适配后线索签名均不同
- Markdown 观察输出存在且结构完整
- 报告使用“测试注入”和“模拟干预”措辞
- Demo 保护文件在测试前后内容一致

最终输出：

```text
[WORLD SIM OBSERVER RESULT] PASS
```

## 10. 当前局限

1. 当前输出是无头 Markdown，不是图形化开发者面板。
2. 每日摘要只展示当天新生成的新闻和线索，不展开全部历史累计项。
3. A/B 对照固定使用第 3 天帮助守望者这一种测试注入。
4. 当前比较聚焦地区、势力、数量和线索签名，没有生成逐事实因果图。
5. 输出包含 30 天完整摘要，适合审阅，但还没有按地区或势力筛选。

## 11. 下一步建议

1. 为观察器增加天数、地区和势力过滤参数。
2. 增加 JSON 导出，便于后续自动分析。
3. 增加按天的状态差值摘要，减少人工对照成本。
4. 在核心模拟稳定后，再考虑独立开发者场景；不要接入当前 Demo UI。
