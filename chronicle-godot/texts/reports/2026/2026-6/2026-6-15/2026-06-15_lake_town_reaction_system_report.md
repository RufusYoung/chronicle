# 湖湾镇微观后续反应系统报告

## 1. 本次目标

在既有湖湾镇粮食危机与微观行动写回基础上，增加由 NPC、地点、物品、WorldFact、Trace、Memory 和场景状态共同驱动的每日后续反应。该层只服务无头世界模拟、观察输出与测试，不接正式 UI，不改变当前 Demo 行为，也不使用随机事件池或固定日期触发。

## 2. 新增 / 修改文件

新增：

- `scripts/sim/lake_town_reaction_system.gd`
- `tests/lake_town_reaction_system_test.gd`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_lake_town_reaction_system_report.md`

修改：

- `data/world_seed_mirror_lake.json`
- `scripts/sim/world_simulator.gd`
- `scripts/dev/world_sim_observer.gd`
- `tests/world_sim_observer_test.gd`
- `texts/reports/2026/2026-6/2026-6-15/2026-06-15_world_sim_observer_output.md`

任务指令归档于 `log/2026-6/2026-6-15/2026-06-15.2.md`。

## 3. 未修改的保护文件

以下保护范围未修改：

- `scenes/ui/story_player.gd`
- `scripts/gen/world_generation_v03.gd`
- `scenes/ui/mainui.tscn`
- `project.godot`
- `素材包/`

## 4. 后续反应状态结构

`WorldSimState.micro_state` 维护：

- `reaction_history`：按唯一反应 key 记录发生日和事实 ID。
- `scene_followup`：记录场景起始、吃粮、生病、发现、邻居帮助、催债和守卫来访等阶段。
- `closed_shop_days`、`unresolved_scene_days`：累计闭店与未解决场景时长。
- `neighbor_attention`、`debt_pressure`、`health_pressure`、`rumor_pressure`：汇总社会、债务、健康与传闻压力。

系统还记录 `reaction_state_update_day`，保证同一天的压力状态只推进一次。`has_reaction_happened()` 与 `record_reaction()` 共同阻止同一反应逐日重复生成。

## 5. 新增 NPC / 社会角色

- 玛婶 `ma_shen`：邻居，拥有关注度、余粮和对老陈的信任。她会先注意闭店，再根据余粮、信任和陈米需求决定是否送粥。
- 刘账房 `liu_zhangfang`：债主与账房，拥有耐心和债权值。其耐心随闭店与债务压力下降，达到阈值后才留下催债告示。

两者均由状态阈值触发行为，没有固定剧情日期。

## 6. 七类后续反应规则

1. `chen_mi_ate_spoiled_grain`：陈米持有发霉麦子、饥饿达到阈值且未得到有效食物帮助时发生。
2. `chen_mi_fell_sick_from_spoiled_grain`：依赖已经吃过发霉麦子的事实，并至少间隔一天。
3. `old_chen_discovered_spoiled_grain`：依赖藏粮痕迹、闭店状态和老陈高压力。
4. `ma_shen_noticed_closed_shop`：依赖连续闭店、`closed_shop` 痕迹与邻里关注条件。
5. `ma_shen_brought_porridge`：依赖玛婶已注意异常、仍有余粮、信任足够，且陈米饥饿或生病。
6. `creditor_left_debt_notice`：依赖债务、闭店时长和刘账房耐心达到催收阈值。
7. `guard_checked_old_chen_shop`：只依赖举报事实与守卫关注痕迹，基线不会凭空发生。

每日顺序为：宏观地区与势力推进、地区标签更新、湖湾镇粮食链推进、湖湾镇后续反应推进、线索投影。外部模拟行动仅在测试或观察分支中显式调用。

## 7. 无外部模拟行动时的时间线

- Day 6：陈米取走发霉麦子，老陈闭店，形成可追溯微观场景。
- Day 7：生成 `chen_mi_ate_spoiled_grain`、`old_chen_discovered_spoiled_grain`、`ma_shen_noticed_closed_shop`。
- Day 8：生成 `chen_mi_fell_sick_from_spoiled_grain`。
- Day 9：生成 `ma_shen_brought_porridge`。
- Day 12：生成 `creditor_left_debt_notice`。

因此 Day 6 后三天内共出现五条新微观反应事实，超过至少两条的验收要求。

## 8. 外部模拟行动后三日分支对照

- `give_food_to_chen_mi`：三日内只出现玛婶注意闭店；陈米没有立即吃发霉麦子，最终 hunger 72、fear 33、health 84。
- `ignore_chen_mi`：出现吃发霉麦子、老陈发现、玛婶注意、生病和送粥；最终 hunger 59、fear 57、health 58。
- `report_to_guard`：除吃粮、发现、邻里注意、生病和送粥外，还出现 `guard_checked_old_chen_shop`；最终 fear 87，并留下守卫来访状态。
- `buy_spoiled_grain_low`：陈米不再持有发霉麦子，没有吃粮或生病；出现玛婶注意和送粥，最终 hunger 76、fear 58、health 84。
- `ask_grain_origin`：即时写入粮仓提示，后三日反应与未提供食物的高风险分支相近。

## 9. WorldFact / Trace / Memory 写回说明

| 反应 | Trace | Memory |
| --- | --- | --- |
| 陈米吃发霉麦子 | `spoiled_grain_crumbs`、`stomach_pain_sign` | `chen_mi_remembers_eating_spoiled_grain` |
| 陈米生病 | `sick_child_at_shop_door` | `old_chen_remembers_chen_mi_sick` |
| 老陈发现藏粮 | `overturned_grain_bag` | `old_chen_found_spoiled_grain` |
| 玛婶注意闭店 | `neighbor_footprints_at_shop`、`whispered_market_rumor` | `noticed_old_chen_shop_closed` |
| 玛婶送粥 | `empty_porridge_bowl_at_door` | `chen_mi_remembers_ma_shen_porridge` |
| 刘账房催债 | `debt_notice_on_shop_door` | `old_chen_remembers_debt_notice` |
| 守卫盘问 | `guard_boot_marks_at_shop` | `chen_mi_remembers_guard_visit` |

所有反应 WorldFact 都写入 `cause_fact_ids`，所有反应 Trace 都写入 `source_fact_id`。反应事实使用 `scope = "micro"`，不会改变宏观新闻事实计数。

## 10. 观察输出变化

观察输出新增：

- `## 湖湾镇微观后续反应时间线`
- `## 外部模拟行动后三日后续分支`

每日摘要不再重复完整的老陈、陈米和店铺状态。普通日期只显示“今日无新增反应”或新增反应数量；基础事实、基础痕迹与初始可叙述状态仅在形成链条的关键日期展开。

观察输出路径：

`texts/reports/2026/2026-6/2026-6-15/2026-06-15_world_sim_observer_output.md`

## 11. 测试结果

以下 Godot 4.6.3 无头测试全部通过：

- `lake_town_reaction_system_test.gd`
- `micro_action_resolver_test.gd`
- `lake_town_food_chain_test.gd`
- `world_sim_observer_test.gd`
- `world_news_digest_test.gd`
- `world_sim_lead_adapter_test.gd`
- `scripts/sim/world_sim_debug_runner.gd`
- `project_cleanup_smoke.gd`
- Godot 编辑器无头解析

专项测试最终输出：`[LAKE TOWN REACTION SYSTEM RESULT] PASS`。

## 12. 当前局限

- 当前只覆盖老陈家粮食危机周边的七类反应，社会网络规模仍小。
- 闭店后的重新开店、变卖物品、正式赊账与邻里疏远尚未建模。
- `ask_grain_origin` 已留下粮仓提示，但尚未形成独立的邻里调查或守卫追查反应。
- 微观反应目前主要服务状态写回和观察验证，尚未接正式交互入口。

## 13. 下一步建议

优先扩展“解决与恢复”方向：让食物获得、债务缓解、重新开店和关系修复也能形成可追溯反应。随后可将 `granary_hint` 接入独立调查链，并继续保持事实先于文本、状态决定候选、外部输入只调用既有规则的边界。
