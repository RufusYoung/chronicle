# world_news 去重与阶段化报告

## 1. 本次目标

本次任务改进 `world_sim` 的新闻表现层，让 `WorldNews` 从逐日事实日志变为经过筛选、累计和阶段化的世界消息。

核心边界：

- `WorldFact` 继续完整记录
- 不改变地区和势力演化规则
- 不扩写事件池
- 不接正式 UI
- 不修改当前 Demo 行为

## 2. 修改 / 新增文件

新增：

- `scripts/sim/world_news_digest.gd`
- `scripts/sim/world_news_digest.gd.uid`
- `tests/world_news_digest_test.gd`
- `tests/world_news_digest_test.gd.uid`
- `texts/reports/2026/2026-06-13_world_news_digest_report.md`

修改：

- `scripts/sim/world_sim_state.gd`
- `scripts/sim/world_simulator.gd`
- `scripts/dev/world_sim_observer.gd`
- `tests/world_sim_observer_test.gd`
- `texts/reports/2026/2026-06-13_world_sim_observer_output.md`

未修改：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

## 3. 去重规则

重复行动使用稳定 `news_key`：

```text
region_id|actor_faction_id|action_type|world_cause
```

示例：

```text
border_town|wardens|suppress_smugglers|warden_security_response
border_town|smugglers|raid_supplies|scarcity_high_and_smuggler_raid
old_ruins|echo_cult|perform_ritual|cult_ritual_and_mystic_pressure
```

每个 key 在 `WorldSimState.news_history` 中维护：

```text
news_key
first_day
last_day
last_published_day
count
last_fact_id
related_fact_ids
stage
severity
last_text
```

冷却期间事件仍会增加 `count`、更新事实引用，但不会重复创建同句 `WorldNews`。

## 4. 冷却规则

默认冷却为 3 天。

以下情况可突破冷却：

- 首次出现
- 累计次数达到新阶段
- 地区状态进入更高严重等级
- 地区标签真实发生变化

普通重复不会因为冷却结束就机械重播；观察器通过“连续事件摘要”展示仍在发展的长期事项。

## 5. 阶段化规则

累计阶段点：

```text
1 次：首次
3 次：阶段 2
5 次：阶段 3
10 次：阶段 4
20 次：阶段 5
```

同时根据地区数值判断 `normal`、`high`、`critical` 严重等级。

已覆盖的主要连续事项：

- 走私者袭击补给线
- 守望者清剿走私据点
- 守望者护送补给
- 回声教团搬运遗物
- 回声教团举行仪式
- 异梦传播
- 森林草药集中采集
- 走私暗线和情报活动

阶段样例：

```text
一批补给在边境镇外被截走。
补给线已遇袭 3 次，边境镇的空货架越来越多。
补给线已遇袭 10 次，边境镇粮食接近见底。
```

```text
守望者突袭了边境镇的走私据点。
守望者连续清剿走私据点，路口盘查变多。
第 10 次清剿后，边境镇秩序仍跌入危险线。
```

```text
森林中的稀有草药被成批采走。
湖岸药草变少，采药人开始深入危险地带。
草药已被集中采集 8 次，采药人开始深入危险地带。
```

## 6. WorldFact 保留情况

固定 seed `20260613` 运行 30 天：

```text
无模拟干预：
  改造前 WorldFact: 192
  改造后 WorldFact: 192

第 3 天测试注入：
  改造前 WorldFact: 202
  改造后 WorldFact: 202
```

新闻去重只发生在表现层，没有删除、合并或跳过任何事实。

## 7. WorldNews 重复率变化

30 天无模拟干预：

```text
改造前 WorldNews: 98
改造后 WorldNews: 41
减少: 57
降幅: 58.2%
```

观察输出中可见的“当天新闻”文本：

```text
改造前：
  展示 90 条
  唯一文本 7 条
  重复文本 83 条
  精确重复率 92.2%

改造后：
  展示 38 条
  唯一文本 38 条
  重复文本 0 条
  精确重复率 0%
```

测试注入组：

```text
改造前 WorldNews: 103
改造后 WorldNews: 46
```

## 8. 观察输出变化样例

观察器现在把新闻分为两类：

```text
当天新新闻：
- border_town / 镜湖守望者 / 阶段 2 / 累计 3：
  守望者连续清剿走私据点，路口盘查变多。

连续事件摘要：
- border_town / 阶段 2 / 累计 3：
  走私者袭击补给线已持续 3 次，边境镇粮食压力仍在升高。
```

每日最多展示：

- 当天新新闻 3 条
- 连续事件摘要 3 条
- `LeadCandidate` 3 条
- 适配后 v0.3 线索 3 条

重新生成的观察输出：

```text
texts/reports/2026/2026-06-13_world_sim_observer_output.md
```

## 9. A/B 测试注入结果

第 3 天执行测试注入：

```gdscript
help_faction(state, "wardens", "border_town")
```

结果：

- 第 10 天地区、势力或新闻已出现差异
- 30 天后边境镇状态仍不同
- 无模拟干预组 `WorldNews` 为 41
- 测试注入组 `WorldNews` 为 46
- 测试注入组比基线多 5 条新闻
- `LeadCandidate` 与适配后线索签名仍不同

## 10. 测试结果

新增测试：

```text
res://tests/world_news_digest_test.gd
```

验证：

- 两组 `WorldFact` 数量完整保留
- `WorldNews` 数量显著下降
- 同一 `news_key` 不会连续两天发布
- 冷却期间历史 `count` 继续累积
- 至少 3 类行动产生阶段新闻
- 地区标签变化仍会立即生成新闻
- 连续事件摘要存在
- 测试注入仍改变新闻与最终地区状态

输出：

```text
[WORLD NEWS DIGEST RESULT] PASS
[WORLD SIM OBSERVER RESULT] PASS
```

## 11. 当前局限

1. 阶段文本仍是规则模板，不是自然语言模型生成。
2. 阈值目前针对三个 MVP 地区和三个势力设置。
3. 连续事件摘要按阶段、次数和最近日期排序，还没有玩家位置权重。
4. 地区标签再次进入同一组合时会保留次数说明，但没有解释中间为何退出该状态。
5. 新闻历史目前存在于运行时状态，尚未接入存档。

## 12. 下一步建议

1. 为新闻增加地点距离和信息传播延迟。
2. 根据消息来源调整可信度与措辞。
3. 支持多个 `news_key` 合并为一条地区危机摘要。
4. 增加缓解阶段文本，让危机下降时也能形成明确消息。
5. 世界新闻稳定后，再考虑独立开发者面板；不要接入当前 Demo UI。
